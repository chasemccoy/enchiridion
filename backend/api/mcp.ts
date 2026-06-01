/* eslint-disable no-console */
import { Router } from 'express';
import type { Request, Response } from 'express';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { createMcpServer } from '@mcp/index';
import { z } from 'zod/v4';

const BACKEND_PORT = z.coerce.number().parse(process.env.BACKEND_PORT);

export const mcpRoutes = Router();

mcpRoutes.post('/mcp', async (req: Request, res: Response) => {
  const server = createMcpServer();
  try {
    const transport: StreamableHTTPServerTransport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      ...(process.env.NODE_ENV === 'development'
        ? {
            enableDnsRebindingProtection: true,
            allowedHosts: [`localhost:${BACKEND_PORT}`],
          }
        : {}),
    });
    res.on('close', () => {
      console.log('Request closed');
      transport.close();
      server.close();
    });
    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (error) {
    console.error('Error handling MCP request:', error);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: {
          code: -32603,
          message: 'Internal server error',
        },
        id: null,
      });
    }
  }
});

mcpRoutes.get('/mcp', async (_, res: Response) => {
  console.log('Received GET MCP request');

  res.writeHead(405).end(
    JSON.stringify({
      jsonrpc: '2.0',
      error: {
        code: -32000,
        message: 'Method not allowed.',
      },
      id: null,
    }),
  );
});

mcpRoutes.delete('/mcp', async (_, res: Response) => {
  console.log('Received DELETE MCP request');

  res.writeHead(405).end(
    JSON.stringify({
      jsonrpc: '2.0',
      error: {
        code: -32000,
        message: 'Method not allowed.',
      },
      id: null,
    }),
  );
});
