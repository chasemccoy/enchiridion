import { db } from '@db/index';
import { upsertLink } from '@db/queries/links';
import { listRecords, upsertRecord } from '@db/queries/records';
import { findSimilarRecords } from '@db/queries/similar-records';
import { records } from '@db/schema';
import { LimitSchema, OffsetSchema, OrderBySchema, RecordFiltersSchema } from '@mcp/schemas';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { recordTypeEnum } from '@shared/types';
import { sql } from 'drizzle-orm';
import * as z from 'zod';
import { archiveUrlToWayback } from '@integrations/wayback/archive';
import { isEmbeddingEnabled, searchRecordsByEmbedding } from '@integrations/embeddings';

type ToolResult = { content: Array<{ type: 'text'; text: string }>; isError?: boolean };

const json = (value: unknown): ToolResult => ({
  content: [{ type: 'text', text: JSON.stringify(value, null, 2) }],
});

const error = (message: string): ToolResult => ({
  content: [{ type: 'text', text: message }],
  isError: true,
});

const schemaHint = (err: unknown) =>
  error(
    `Error: ${(err as Error).message}. Reference the database schema resource at schema://main for the correct arguments.`,
  );

const tryJson = async (run: () => Promise<unknown> | unknown): Promise<ToolResult> => {
  try {
    return json(await run());
  } catch (err) {
    return error(`Error: ${(err as Error).message}`);
  }
};

export function createMcpServer(): McpServer {
  const server = new McpServer(
    {
      name: 'Enchiridion MCP server',
      version: '1.0.0',
    },
    {
      instructions: `
    This MCP server provides access to an SQLite database of research materials organized into records, links, and predicates. Records are the main objects in the database, and can be linked to one another via predicates. Links are the relationships between records, and predicates are the types of relationships. Records can be one of three types: artifacts, entities, or concepts.

    As an LLM acting on behalf of a user, you can:
    - Retrieve the database schema by reading the "schema://main" resource.
    - Use the available tools and resources to answer user questions, summarize data, or perform lookups as requested.
    - Prefer the high-level tools when they fit the user's intent:
      - "semantic_search" for natural-language conceptual queries over the corpus.
      - "similar" to find records like a known anchor record.
      - "search" for exact substring matches or filters by record type/source/URL/etc.
      - "query" only as a last resort, for relational or aggregate questions the high-level tools cannot express.
    - Query the database using the "query" tool by providing raw SQL statements. The schema of the database is available as a resource at "schema://main".
    - Always validate and format your SQL queries to ensure they are safe and relevant to the user's intent.
    - If you are unsure about the structure of the database, consult the schema resource before constructing queries.
  `.trim(),
    },
  );

  server.registerResource(
    'schema',
    'schema://main',
    {
      title: 'Database schema',
      description: 'Enchiridion database schema',
      mimeType: 'text/plain',
    },
    async (uri) => {
      const tables = db.all<{ sql: string }>(sql`SELECT sql FROM sqlite_master WHERE type='table'`);
      return {
        contents: [{ uri: uri.href, text: tables.map((t) => t.sql).join('\n') }],
      };
    },
  );

  server.registerTool(
    'query',
    {
      title: 'SQL Query',
      description:
        'Execute SQL queries on the database whose schema is available as a resource at schema://main',
      inputSchema: { sql: z.string() },
    },
    async ({ sql }) => tryJson(() => db.all(sql)),
  );

  server.registerTool(
    'search',
    {
      title: 'Search records',
      description:
        'Keyword and filter-based search. Use this for exact substring matches in record fields (title, content, summary, etc.) or to filter by structured properties like record type, source, URL, or curation status. For natural-language conceptual queries ("articles about decentralized social media"), use the `semantic_search` tool instead.',
      inputSchema: {
        filters: RecordFiltersSchema.optional().default({}),
        limit: LimitSchema.optional().default(100),
        offset: OffsetSchema.optional().default(0),
        orderBy: OrderBySchema.optional().default([
          { field: 'recordCreatedAt', direction: 'desc' },
        ]),
      },
    },
    async (args) => tryJson(() => listRecords(args)),
  );

  server.registerTool(
    'semantic_search',
    {
      title: 'Semantic search',
      description:
        'Find records whose meaning is closest to a natural-language query, ranked by cosine similarity over OpenAI embeddings. Use this for conceptual searches ("articles about decentralized identity", "anything related to typography on the web") where keyword matching would miss synonyms or paraphrased ideas. Returns records sorted most-similar first, each with a `score` in [-1, 1] (higher = more similar). If embeddings are not configured this returns an empty array.',
      inputSchema: {
        query: z.string().min(1).describe('Natural-language search query'),
        limit: z.number().int().min(1).max(50).optional().default(10),
      },
    },
    async (args) => {
      if (!isEmbeddingEnabled()) {
        return error(
          'Embeddings are not configured (OPENAI_API_KEY is unset). Falling back is not automatic — use the `search` tool for keyword-based queries instead.',
        );
      }
      return tryJson(() => searchRecordsByEmbedding(args));
    },
  );

  server.registerTool(
    'similar',
    {
      title: 'Find similar records',
      description:
        'Given a record id, return records that are semantically similar to it by cosine similarity over their embeddings. This is the same algorithm that powers the "Similar records" section in the UI. Returns records sorted most-similar first, each with a `score` in [-1, 1]. Use this for "what else is like this?" — e.g. exploring a topic cluster from a known anchor record. Returns an empty array if the anchor has no stored embedding (e.g. it has no title/summary/content/notes).',
      inputSchema: {
        recordId: z.number().int().describe('Anchor record id'),
        limit: z.number().int().min(1).max(50).optional().default(10),
        minScore: z
          .number()
          .min(-1)
          .max(1)
          .optional()
          .default(0.1)
          .describe('Drop hits whose cosine similarity is below this threshold'),
      },
    },
    async (args) => tryJson(() => findSimilarRecords(args)),
  );

  server.registerTool(
    'create',
    {
      title: 'Create new record',
      description:
        'Create a new record (not a link) in the database whose schema is available as a resource at schema://main. Returns the created record.',
      inputSchema: {
        title: z.string(),
        slug: z.string(),
        content: z.string().optional(),
        summary: z.string().optional(),
        url: z.string().optional(),
        type: z.enum(recordTypeEnum).optional().default('artifact'),
      },
    },
    async (values) => {
      try {
        const result = await db.insert(records).values(values).returning();
        if (values.url) archiveUrlToWayback(values.url);
        return json(result);
      } catch (err) {
        return schemaHint(err);
      }
    },
  );

  server.registerTool(
    'update',
    {
      title: 'Update record',
      description:
        'Update an existing record in the database whose schema is available as a resource at schema://main. Returns the updated record. If the record does not exist, it will be created.',
      inputSchema: {
        title: z.string().optional(),
        slug: z.string(),
        content: z.string().optional(),
        summary: z.string().optional(),
        url: z.string().optional(),
        type: z.enum(recordTypeEnum).optional().default('artifact'),
      },
    },
    async (values) => {
      try {
        return json(upsertRecord(values));
      } catch (err) {
        return schemaHint(err);
      }
    },
  );

  server.registerTool(
    'link',
    {
      title: 'Link two records via a specified predicate',
      description: 'Link two records in the database',
      inputSchema: {
        sourceId: z.number(),
        targetId: z.number(),
        predicateId: z.number(),
      },
    },
    async (args) => {
      try {
        return json(await upsertLink(args));
      } catch (err) {
        return schemaHint(err);
      }
    },
  );

  return server;
}
