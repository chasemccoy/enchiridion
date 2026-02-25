# AGENTS.md

## Cursor Cloud specific instructions

### Services overview

This is a full-stack TypeScript app (Vue 3 + Express + SQLite). Two services must run for development:

| Service | Command | Port | Notes |
|---------|---------|------|-------|
| Vue frontend (Vite) | `pnpm dev:app` | 3456 | |
| Express backend | `pnpm dev:backend` | 4321 | Uses SQLite file `enchiridion.db` |

Run both together with `pnpm dev` (includes a database health check before starting).

### Quick reference

- **Dev commands, scripts, architecture**: See `CLAUDE.md` and `README.md` — do not duplicate here.
- **Lint**: `pnpm run lint` — note there is a pre-existing ESLint error (`_next` unused in `backend/api/errorHandler.ts`), which is standard for Express error-handler middleware signatures.
- **Build**: `pnpm run build` runs `vue-tsc -b && vite build`. The `vue-tsc` step has pre-existing type errors from third-party declarations (floating-ui, reka-ui, etc.) and some project-level TS issues. The Vite build itself (`npx vite build`) succeeds. Use `npx vite build` if you only need to verify the production bundle compiles.
- **Database**: SQLite file-based (`enchiridion.db` in project root). Initialize with `pnpm db:push && pnpm db:seed`. Reset with `pnpm db:reset`.
- **Environment**: Copy `.env.example` to `.env` if `.env` doesn't exist. Default ports are 3456 (frontend) and 4321 (backend).
- **Record creation API**: `PUT /record` with a JSON body parsed by `RecordInsertSchema`. `POST /records` lists/filters records (not creation).
- **No Docker or containers** are needed.
- **No automated test suite** exists in this repo — there are no test files or test runner configured.
