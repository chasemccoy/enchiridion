# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Frontend & Backend Development

- `pnpm dev` - Start both frontend (Vue) and backend (Express) concurrently
- `pnpm dev:app` - Start only the Vue frontend (port 3456)
- `pnpm dev:backend` - Start only the Express backend (port 4321)

### Building & Quality Checks

- `pnpm build` - Build the Vue frontend for production
- `pnpm preview` - Preview the production build locally
- `pnpm lint` - Check-only quality gate: Prettier `--check`, ESLint (no fix), and vue-tsc. Never mutates files, so it's safe as a CI/pre-commit gate. Should always pass on `main`.
- `pnpm fix` - The mutating counterpart: Prettier `--write` + ESLint `--fix`, then vue-tsc. Use this to format.
- `pnpm test` / `pnpm test:watch` - Run the Vitest suite (see Testing below).

`app/design-lab/` is a scratch playground and is deliberately exempt from both type checking and lint (excluded in `tsconfig.app.json` and `eslint.config.js`; the router reaches it via `import.meta.glob` so TypeScript doesn't follow the import). Don't "fix" its errors and don't let real code depend on it.

### Testing

Tests live in `tests/` and run with Vitest (`vitest.config.ts`). The harness gives every test file its own forked process and its own scratch SQLite database:

- `tests/setup.ts` runs before each file and points `DATABASE_PATH` (the override `backend/db/index.ts` exists for) at a fresh temp file, migrated from `backend/db/migrations` — tests never touch `enchiridion.db`.
- `ARCHIVE_DIR`/`ARCHIVE_BACKEND` point at a temp folder with static-fetch capture, and `ANTHROPIC_API_KEY` is cleared so amber uses heuristics — no network, no LLM calls. Archive tests that need a real URL serve one from a local ephemeral-port HTTP server (`servePage` in `tests/helpers.ts`).
- API tests use supertest against the assembled Express app (`backend/api/app.ts` — assembly is split from the listener in `backend/api/index.ts` precisely so tests can import it without binding a port).

Prefer tests for invariant-heavy core logic (db queries, claim/upsert semantics, CLI parsing, route contracts) over UI components.

### Database Operations

**Canonical workflow: `generate` → `migrate`. Do NOT use `db:push` on a populated database.**

The sqlite-vec virtual tables (`vec_records`, created at runtime in `backend/db/index.ts`) break every drizzle-kit command that introspects the live DB — `drizzle-kit push`/`pull`/`studio` die with `no such module: vec0` because drizzle-kit's connection doesn't load the extension. `db:generate` (schema-diff, no DB) and `db:migrate` (runs through the app's vec-loaded connection via `scripts/migrate.ts`) are unaffected, so they are the supported path.

To change the schema:

1. Edit `backend/db/schema/*`.
2. `pnpm db:generate` — writes a minimal migration to `backend/db/migrations/<ts>_<name>/` (diffs against the previous snapshot; e.g. a clean `ALTER TABLE … ADD COLUMN`).
3. Review the generated `migration.sql`.
4. `pnpm db:migrate` — applies pending migrations through the app connection and records them in `__drizzle_migrations` (matched **by migration name** in Drizzle v1).

Other commands:

- `pnpm db:migrate --mark-applied` - Stamp all migration files as applied **without running them** — use to adopt an existing DB into a (re)baselined history.
- `pnpm db:generate` / `pnpm db:studio` / `pnpm db:seed`
- `pnpm db:backup` - Diffable JSON backup of the SQLite file. Skips virtual tables and their shadow/companion tables (`vec_*`), which are regenerable via `pnpm embed`. For a quick raw snapshot before a risky change, `cp enchiridion.db enchiridion.db.bak` is instant and bulletproof.
- `pnpm db:reset` - `db:clean && db:migrate && db:seed` (rebuilds from migrations, not push). Also `db:clean`, `db:check`.
- `pnpm db:push` - Only safe on an **empty** DB (no vec tables yet). Avoid on a populated DB — it can't introspect past `vec_records`.

Notes:

- Drizzle is on the **v1 RC** line (`1.0.0-rc.4`): migrations live in per-folder `<ts>_<name>/{migration.sql,snapshot.json}` with **no `meta/_journal.json`**, and applied migrations are tracked by name.
- SQLite can't ALTER most things in place, so non-additive changes (drop/rename column, change constraints) generate a table-recreation migration — review those `migration.sql` files carefully.

### Integrations

- `pnpm sync:readwise` (or `pnpm sync`) - Sync records from Readwise integration
- `pnpm embed` - Generate embeddings for records (requires `OPENAI_API_KEY`)

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

- `app/` - Vue 3 frontend with Nuxt UI components
- `backend/api/` - Express API server (REST routes)
- `backend/db/` - Drizzle schema, queries, migrations
- `backend/cli/ench/` - `ench` CLI: stdio interface for agents/shell
- `backend/integrations/` - Readwise, Twitter, Wayback, embeddings, chrome-extension, utils
- `shared/` - Shared types and utilities between frontend/backend

### Frontend Architecture

- **Framework**: Vue 3 with Composition API
- **Routing**: Vue Router with typed routes
- **UI**: Nuxt UI (v4) components
- **State**: TanStack Query for server state, composables for client logic
- **Styling**: Tailwind CSS (v4) with custom theme

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
- `@api/*` → `./backend/api/*`
- `@integrations/*` → `./backend/integrations/*`

### Environment Configuration

Required environment variables (see `.env.example`). The ports are parsed at startup and will throw if unset — they are required, not defaulted:

- `BACKEND_PORT` - Express server port (e.g. 4321)
- `FRONTEND_PORT` - Vite dev server port (e.g. 3456)
- `DATABASE_NAME` - SQLite database filename
- `READWISE_TOKEN` - API token for Readwise integration
- `OPENAI_API_KEY` - Required for embeddings / semantic search

Optional (local web archives — the record detail "Archive this page" action, backed by the `amber` library at `../amber`):

- `ANTHROPIC_API_KEY` - Drives the archive cleanup plan; archiving falls back to heuristics if unset
- `ARCHIVE_DIR` - Where archive folders are written (defaults to `~/Documents/Archives`)
- `ARCHIVE_BACKEND` - Capture backend: `playwright` (default, full render — runs JS and triggers lazy-loaded images), `auto` (static fetch, escalate only if the page looks empty), or `fetch` (static only)
- `ARCHIVE_INSECURE_TLS` - Set to `1` only behind a trusted TLS-intercepting proxy
