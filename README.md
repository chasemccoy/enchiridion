# Enchiridion

A full-stack knowledge graph application for managing and connecting ideas, links, and information. Built with Vue 3, Express, and SQLite. Inspired by and heavily borrowed from Nick Trombley's [Red Cliff Record](https://github.com/Aias/red-cliff-record) and [barnsworthburning](https://barnsworthburning.net/).

![CleanShot 2025-06-28 at 16 45 32@2x](https://github.com/user-attachments/assets/4f61b4b8-e756-4e83-b6fa-599d1640371a)

## 🏗️ Architecture

### Tech stack

- **Frontend**: Vue 3 with Composition API, Vue Router, TanStack Query
- **Backend**: Express.js with TypeScript
- **Database**: SQLite with Drizzle ORM
- **UI**: Nuxt UI components

### Core data model

The application models a knowledge graph with three main entities:

- **Records**: The primary entities (artifacts, concepts, entities) with metadata
- **Links**: Relationships between records via predicates
- **Predicates**: Typed relationships (creation, containment, description, reference, association, identity)

## 📁 Project structure

```
enchiridion/
├── app/                   # Vue frontend app
│   ├── components/        # Reusable Vue components
│   ├── composables/       # Vue composition functions
│   ├── views/             # Page components
│   └── router.ts          # Vue Router configuration
├── backend/               # Express.js API server
│   ├── api/               # REST API endpoints
│   ├── cli/ench/          # `ench` — stdio CLI for agents and scripts
│   ├── db/                # Database schema and queries
│   │   ├── schema/        # Drizzle ORM schemas
│   │   ├── queries/       # Database queries
│   │   └── migrations/    # Database migration files
│   └── integrations/      # External service integrations
│       ├── readwise/      # Readwise sync
│       ├── twitter/       # Tweet fetching
│       ├── wayback/       # Wayback Machine archiving
│       └── embeddings/    # OpenAI embeddings + sqlite-vec search
├── shared/                # Shared types and utilities
│   ├── lib/               # Utility functions
│   └── types/             # TypeScript type definitions
└── uploads/               # File storage for media uploads
```

## 🚀 Getting started

### Prerequisites

- Node.js 22+
- SQLite
- pnpm (recommended) or npm

### Setup

1. **Clone the repository**

   ```bash
   git clone https://github.com/chasemccoy/enchiridion
   cd enchiridion
   ```

2. **Install dependencies**

   ```bash
   pnpm install
   ```

3. **Set up environment variables**

   ```bash
   cp .env.example .env
   ```

4. **Initialize the database**

   ```bash
   pnpm db:push         # Initialize database w/ schema
   pnpm db:seed         # Seed with initial data
   pnpm sync:readwise   # Sync Readwise data, optional
   ```

5. **Start development servers**
   ```bash
   pnpm dev        # Start both frontend and backend
   ```

The application will be available at:

- Frontend: `http://localhost:3456`
- API: `http://localhost:4321`

## 📚 Available scripts

### Development

- `pnpm dev` - Start both frontend and backend concurrently
- `pnpm dev:app` - Start only the Vue frontend (port 3456)
- `pnpm dev:backend` - Start only the Express backend (port 4321)

### Database operations

- `pnpm db:push` - Push schema changes to SQLite database
- `pnpm db:studio` - Open Drizzle Studio for database inspection
- `pnpm db:seed` - Seed the database with initial data
- `pnpm db:generate` - Generate migration files
- `pnpm db:migrate` - Run database migrations
- `pnpm db:reset` - Clean, recreate, and seed the database

### Integrations

- `pnpm sync:readwise` - Sync records from Readwise integration
- `pnpm sync` - Sync records from all integrations
- `pnpm embed` - Backfill OpenAI embeddings for all records

### CLI (`ench`)

- `pnpm cli <command>` - Run the `ench` CLI from inside the repo
- See [the CLI section](#-cli) for what `ench` can do

## 🤖 CLI

`ench` is a stdio interface to your knowledge base. It's the same data the web UI sees, exposed as JSON-on-stdout commands so agents (Claude Code, scripts, shell pipelines) can read, write, search, and curate without running the HTTP server.

### Install

From inside the project, no install needed:

```bash
pnpm cli --help
pnpm cli records list --type=artifact --limit=10
```

To make `ench` available on PATH everywhere:

```bash
pnpm link --global
ench --help
ench db status
```

The launcher resolves the project's `tsconfig.json` and SQLite file from its own real path, so `ench` works from any working directory.

### What it does

```bash
# Records
ench records get 1
ench records list --type=artifact --curated --limit=5 --full
ench records list --curated=false              # records needing curation
ench records create '{"slug":"foo","title":"Foo","type":"concept"}'
ench records tree 220
ench records similar 220 --limit=5

# Search
ench search "knowledge graph"                  # hybrid (text + vector, RRF merge)
ench search text "hypertext"
ench search semantic "ways of thinking about links"

# Links
ench links list 1 --predicate=created_by
ench links predicates

# Sync
ench sync                                      # all integrations + embedding backfill
ench sync readwise
ench sync embeddings --force

# Database
ench db status
ench db backup --out=/tmp/ench-backup.sqlite

# Wayback Machine
ench wayback archive https://example.com
ench wayback status https://example.com
```

All commands return `{data, meta}` JSON on stdout (or `{error: {code, message}}` on stderr + stdout with exit 1). Pass `--format=table` for human-readable output, `--raw` to drop the envelope, `--dry-run`/`-n` to preview mutations.

## 🔧 Development

### Path aliases

Both frontend and backend use these path aliases:

- `@app/*` → `./app/*`
- `@db/*` → `./backend/db/*`
- `@api/*` → `./backend/api/*`
- `@shared/*` → `./shared/*`
- `@integrations/*` → `./backend/integrations/*`

## 🔌 Integrations

### Readwise

Connect your Readwise account to automatically sync highlights and articles:

1. Get your Readwise API token from [readwise.io/access_token](https://readwise.io/access_token)
2. Add it to your `.env` file as `READWISE_TOKEN`
3. Run `pnpm sync:readwise` (or `ench sync readwise`) to sync your data

### OpenAI embeddings

Semantic search and the "similar records" feature use OpenAI text embeddings stored in [sqlite-vec](https://github.com/asg017/sqlite-vec):

1. Add your API key to `.env` as `OPENAI_API_KEY`
2. Run `pnpm embed` (or `ench sync embeddings`) to backfill vectors for existing records

New records embed automatically on write; the backfill is only needed for the initial seed.
