# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Frontend & Backend Development

- `pnpm dev` - Start both frontend (Vue) and backend (Express) concurrently
- `pnpm dev:app` - Start only the Vue frontend (port 3456)
- `pnpm dev:backend` - Start only the Express backend (port 4321)

### Building & Quality Checks

- `pnpm build` - Build the Vue frontend for production
- `pnpm lint` - Format, lint, and type-check all code (includes Prettier, ESLint, and vue-tsc)
- `pnpm format` - Format code with Prettier only

### Database Operations

- `pnpm db:push` - Push schema changes to SQLite database
- `pnpm db:studio` - Open Drizzle Studio for database inspection
- `pnpm db:seed` - Seed the database with initial data
- `pnpm db:generate` - Generate migration files
- `pnpm db:migrate` - Run database migrations

### Integrations

- `pnpm sync:readwise` - Sync records from Readwise integration

### CLI (`ench`)

`ench` is the stdio interface to the knowledge base — designed for agents and shell workflows that don't want to spin up the HTTP server.

- `pnpm cli <command>` - Run the CLI from inside the repo (no install needed)
- `pnpm link --global` then `ench <command>` - Install globally on PATH
- `ench --help` - Full command reference

Common commands:

- `ench records get <id>` / `records list [filters]` / `records create '<json>'`
- `ench search <query>` (hybrid) / `search text` / `search semantic` / `search similar`
- `ench links list <id>` / `links predicates`
- `ench sync readwise` / `sync embeddings [--force]`
- `ench db status` / `db backup [--out=path]`

Output is JSON by default (`{data, meta}` envelope; errors as `{error: {code, message}}` with exit 1). Use `--format=table` for human-readable output. See [backend/cli/ench/](backend/cli/ench/) for the implementation.

## Architecture Overview

### Project Structure

This is a full-stack TypeScript application with a Vue 3 frontend and Express backend, using SQLite with Drizzle ORM.

**Key directories:**

- `app/` - Vue 3 frontend with PrimeVue UI components
- `backend/api/` - Express API server (REST routes)
- `backend/db/` - Drizzle schema, queries, migrations
- `backend/cli/ench/` - `ench` CLI: stdio interface for agents/shell
- `backend/integrations/` - Readwise, Twitter, Wayback, embeddings
- `shared/` - Shared types and utilities between frontend/backend

### Frontend Architecture

- **Framework**: Vue 3 with Composition API
- **Routing**: Vue Router with typed routes
- **UI**: PrimeVue components with Nuxt UI
- **State**: TanStack Query for server state, composables for client logic
- **Styling**: Tailwind CSS with custom theme

### Backend Architecture

- **API**: Express.js with typed route handlers
- **Database**: SQLite with Drizzle ORM
- **Schema**: Three main entities - Records, Links, and Predicates forming a knowledge graph

### Core Data Model

The application models a knowledge graph with:

- **Records**: The main entities (artifacts, concepts, entities) with metadata
- **Links**: Relationships between records via predicates
- **Predicates**: Typed relationships (creation, containment, description, etc.)

### Path Aliases

Both frontend and backend use these path aliases:

- `@app/*` → `./app/*`
- `@shared/*` → `./shared/*`
- `@db/*` → `./backend/db/*`
- `@integrations/*` → `./backend/integrations/*`

### Environment Configuration

Required environment variables (see `.env`):

- `BACKEND_PORT` - Express server port (default: 4321)
- `FRONTEND_PORT` - Vite dev server port (default: 3456)
- `READWISE_TOKEN` - API token for Readwise integration
