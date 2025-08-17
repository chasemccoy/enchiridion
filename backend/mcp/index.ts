import { db } from '@db/index';
import { upsertLink } from '@db/queries/links';
import { listRecords, upsertRecord } from '@db/queries/records';
import { records } from '@db/schema';
import { LimitSchema, OffsetSchema, OrderBySchema, RecordFiltersSchema } from '@mcp/schemas';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { recordTypeEnum } from '@shared/types';
import { sql } from 'drizzle-orm';
import { z } from 'zod';

export const server = new McpServer(
  {
    name: 'Enchiridion MCP server',
    version: '1.0.0',
  },
  {
    instructions: `
    This MCP server provides access to the Enchiridion SQLite database.

    As an LLM acting on behalf of a user, you can:
    - Retrieve the database schema by reading the "schema://main" resource.
    - Use the available tools and resources to answer user questions, summarize data, or perform lookups as requested.
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
    description: 'Search for records',
    inputSchema: {
      filters: RecordFiltersSchema.optional().default({}),
      limit: LimitSchema.optional().default(100),
      offset: OffsetSchema.optional().default(0),
      orderBy: OrderBySchema.optional().default([{ field: 'recordCreatedAt', direction: 'desc' }]),
    },
  },
  async ({ filters, limit, offset, orderBy }) => {
    try {
      // @ts-expect-error orderBy is optional
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
  'create',
  {
    title: 'Create new record',
    description:
      'Create a new record (not a link) in the database whose schema is available as a resource at schema://main',
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
