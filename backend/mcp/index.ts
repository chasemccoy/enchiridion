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

export const server = new McpServer(
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
    const tables = db.all(sql`SELECT sql FROM sqlite_master WHERE type='table'`);

    return {
      contents: [
        {
          uri: uri.href,
          // @ts-expect-error idk why this is broken
          text: tables.map((t: { sql: string }) => t.sql).join('\n'),
        },
      ],
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
  async ({ sql }) => {
    try {
      const results = db.all(sql);

      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(results, null, 2),
          },
        ],
      };
    } catch (err: unknown) {
      const error = err as Error;
      return {
        content: [
          {
            type: 'text',
            text: `Error: ${error.message}`,
          },
        ],
        isError: true,
      };
    }
  },
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
      orderBy: OrderBySchema.optional().default([{ field: 'recordCreatedAt', direction: 'desc' }]),
    },
  },
  async ({ filters, limit, offset, orderBy }) => {
    try {
      const results = await listRecords({ filters, limit, offset, orderBy });

      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(results, null, 2),
          },
        ],
      };
    } catch (err: unknown) {
      const error = err as Error;
      return {
        content: [
          {
            type: 'text',
            text: `Error: ${error.message}`,
          },
        ],
        isError: true,
      };
    }
  },
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
  async ({ query, limit }) => {
    try {
      if (!isEmbeddingEnabled()) {
        return {
          content: [
            {
              type: 'text',
              text: 'Embeddings are not configured (OPENAI_API_KEY is unset). Falling back is not automatic — use the `search` tool for keyword-based queries instead.',
            },
          ],
          isError: true,
        };
      }
      const results = await searchRecordsByEmbedding({ query, limit });
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(results, null, 2),
          },
        ],
      };
    } catch (err: unknown) {
      const error = err as Error;
      return {
        content: [{ type: 'text', text: `Error: ${error.message}` }],
        isError: true,
      };
    }
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
  async ({ recordId, limit, minScore }) => {
    try {
      const results = await findSimilarRecords({ recordId, limit, minScore });
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(results, null, 2),
          },
        ],
      };
    } catch (err: unknown) {
      const error = err as Error;
      return {
        content: [{ type: 'text', text: `Error: ${error.message}` }],
        isError: true,
      };
    }
  },
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
  async ({ title, content, summary, url, type, slug }) => {
    try {
      const result = await db
        .insert(records)
        .values({
          title,
          content,
          summary,
          url,
          slug,
          type,
        })
        .returning();

      if (url) {
        archiveUrlToWayback(url);
      }

      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (err: unknown) {
      const error = err as Error;
      return {
        content: [
          {
            type: 'text',
            text: `Error: ${error.message}. Reference the database schema resource at schema://main for the correct arguments.`,
          },
        ],
        isError: true,
      };
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
  async ({ title, content, summary, url, type, slug }) => {
    try {
      const result = upsertRecord({
        title,
        content,
        summary,
        url,
        slug,
        type,
      });

      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (err: unknown) {
      const error = err as Error;
      return {
        content: [
          {
            type: 'text',
            text: `Error: ${error.message}. Reference the database schema resource at schema://main for the correct arguments.`,
          },
        ],
        isError: true,
      };
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
  async ({ sourceId, targetId, predicateId }) => {
    try {
      const result = await upsertLink({ sourceId, targetId, predicateId });

      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(result, null, 2),
          },
        ],
      };
    } catch (err: unknown) {
      const error = err as Error;
      return {
        content: [
          {
            type: 'text',
            text: `Error: ${error.message}. Reference the database schema resource at schema://main for the correct arguments.`,
          },
        ],
        isError: true,
      };
    }
  },
);
