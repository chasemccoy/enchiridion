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
- `ENCHIRIDION_DEVICES` points at a path that doesn't exist, so the Tailscale auth scheme is off and the API open for every test; `ENCHIRIDION_TAILSCALE` points at a missing binary, so no test can run the real CLI. `tests/auth.test.ts` turns the scheme on by creating that file, with a stand-in CLI script.

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
- `pnpm db:backup` - Diffable JSON backup of the SQLite file. Skips virtual tables and their shadow/companion tables (`vec_*`), which are regenerable via `pnpm embed`. For a quick raw snapshot before a risky change, copy the database and its WAL into a dated folder under `db-backups/`, like the ones already there (the copies stay gitignored, and the Vite dev server never serves that folder; see Auth): `d=db-backups/$(date +%Y%m%d-%H%M%S) && mkdir -p $d && cp enchiridion.db* $d/`. Don't leave a copy beside `enchiridion.db` under another name.
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

The server imports amber's **built** output (`../amber/dist`, linked as `node_modules/amber`), not its source, so after pulling amber run `pnpm --dir ../amber build` and restart the API, or Enchiridion keeps archiving with the old build. Archives keep their history as folders (amber's `<slug>/versions/<stamp>/`); a record's archive row points at the folder, and `GET /record/:id/archive/versions` lists the captures in it. `POST /record/:id/archive` with `{ at }` (a date, a Wayback timestamp, `latest`, or a web.archive.org link to the same page) archives a past version from the Wayback Machine into that timeline; `ench archive <id> --at=…` does the same.

- `ANTHROPIC_API_KEY` - Drives the archive cleanup plan; archiving falls back to heuristics if unset
- `ARCHIVE_DIR` - Where archive folders are written (defaults to `~/Documents/Archives`)
- `ARCHIVE_BACKEND` - Capture backend: `playwright` (default, full render — runs JS and triggers lazy-loaded images), `auto` (static fetch, escalate only if the page looks empty), or `fetch` (static only)
- `ARCHIVE_INSECURE_TLS` - Set to `1` only behind a trusted TLS-intercepting proxy
- `ARCHIVE_WAYBACK_BASE` - Test seam: an alternate Wayback Machine host for past-version captures (tests point it at a local stand-in; unset in production)
- `WAYBACK_AUTO_ARCHIVE` - Set to `0` to stop new records from being auto-submitted to the Wayback Machine on creation (tests set this; explicit `ench wayback archive` is unaffected)

Optional (Tailscale auth — see Auth below):

- `ENCHIRIDION_DEVICES` - The devices file (defaults to `~/.enchiridion/devices`; a leading `~` is expanded). Its existence turns auth on
- `ENCHIRIDION_TAILSCALE` - The tailscale CLI to run (defaults to `tailscale` on PATH; on voyager that's `/usr/local/bin/tailscale`)
- `ENCHIRIDION_API_HOST` - The API's public name, which Caddy passes through as `Host` (defaults to `enchiridion-api.chsmc.tools`). `X-Forwarded-For` is only read from requests to this name

`.env` isn't watched: a change to these needs `pm2 restart enchiridion`. The devices file itself is.

### Auth

`backend/api/auth.ts`, a port of familiar's Tailscale identity scheme. **Off unless the devices file exists**: without it the API is open, as it always was. With it (even empty), every request but `GET /info` must come from one of:

- **A listed device** (`tailscale`): Caddy proxies `enchiridion-api.chsmc.tools` from loopback, passing its `Host` through and setting `X-Forwarded-For` to the tailnet peer; `tailscale whois` turns that address into the node's stable id (cached a minute, misses too; any failure refuses), which must be in the devices file. The header is read only from a loopback peer whose `Host` is that name (`ENCHIRIDION_API_HOST`).
- **voyager's own node** (`tailscale`), learned from `tailscale status`: the web app, the iOS Simulator and agents on voyager reach the API through Caddy as voyager.
- **A local process** (`local`): a loopback peer with no `X-Forwarded-For` whose `Host` (if any) is `localhost`, a 127/8 address or `[::1]` (Vite dev on localhost, scripts, supertest). Caddy always adds the header, so this is never a remote client. The Host checks keep out a web page in a browser on voyager whose name was DNS-rebound to 127.0.0.1: it sends its own host name, so it passes neither as a local process nor, by setting `X-Forwarded-For` itself, as a device.

Anything else gets a 401 with `WWW-Authenticate: Tailscale realm="enchiridion"` and `{error:{code:"unauthorized",message}, message, device}`, where `device` (`{id, name}`) names an unlisted node so it can be added, and is `null` when the address couldn't be resolved. A direct (non-loopback) connection to `:4321` is refused whatever it sends. `GET /info` → `{name:"enchiridion", auth:["tailscale"]}` (or `[]` when off); `GET /me` → `{scheme: "tailscale"|"local"|"open", device, user}`. Server log lines start with `[auth]`.

**Browsers: only the web app's own pages.** Admission goes by where a request comes from, so any page open in an admitted browser (Safari on a listed phone, any browser on voyager) would otherwise use the API as that device. While the scheme is on, the origin gate (`originGate`, mounted first) answers 403 `{error:{code:"forbidden_origin",message}, message}` to any request whose `Origin` isn't `https://enchiridion.chsmc.tools`, or `http://{localhost,127.0.0.1,[::1]}:$FRONTEND_PORT` on a request from a local process (`isWebOrigin`) — preflights and form posts included — and CORS echoes only those origins (so 401s stay readable to the web app). The dev origins count only locally because `localhost` is whichever machine the browser runs on: through Caddy they'd be a page on some device's own port 3456 (another project's dev server, say), while the dev web app always calls its own machine's API straight on `:4321`. Requests without an `Origin` (the iOS app, curl, scripts) are unaffected. One exception: an archived page's own fonts, images, style sheets, scripts and media under `/archives/` (GET/HEAD with a `Sec-Fetch-Dest` of `font`, `image`, `style`, `script`, `audio`, `video` or `track`, which page script can't set) pass the gate with their origin echoed, since the web app shows archives in a sandboxed frame whose font loads say `Origin: null`; they still need the device check. And while on, everything under `/archives` is served with `Content-Security-Policy: sandbox allow-scripts …` (no `allow-same-origin`, `ARCHIVE_CSP`): an archive that kept its site's scripts, opened in a tab, gets an opaque origin, so its scripts' calls carry `Origin: null` and are refused instead of running as the API's own origin. While off, CORS is `*`, archives aren't sandboxed, and nothing is gated, as before.

**Updates must name a record that exists.** `PUT /record` upserts on `id`, so an update of a record deleted elsewhere would insert a bare row under that id. `app.ts` answers such a `PUT` (one with an `id` no row has) with 404 `{error:{code:"not_found",message}, message}`; creates (no `id`) are unaffected.

The file is re-checked (mtime + size) on every request, so creating, editing or deleting it takes effect without a restart. Once the scheme is on, a missing file turns it off only after it has stayed missing for 2 s (`MISSING_GRACE_MS`): an editor that saves by renaming the old file away (Vim's default) leaves no file for a moment, and that must not open the API. "Stayed missing" means every check over those 2 s found it gone, none more than 1 s apart; while it's missing the server re-checks it every 0.5 s on its own, request or not, and a longer gap between checks (one that could hide the file coming back and a second save) starts the grace over.

**The device check only covers `:4321`.** The Vite dev server that pm2 runs (`vite --host`, on `*:3456`, proxied by Caddy as `enchiridion.chsmc.tools`) answers any LAN or tailnet client without it. `vite.config.ts` therefore locks it down: `allowedHosts` lists `enchiridion.chsmc.tools`, `voyager` and `.ts.net` (localhost and raw IPs are always allowed), which keeps Vite's DNS-rebinding guard on; `server.fs.allow` limits `/@fs/` to `app/`, `shared/`, `backend/` and `node_modules/`; and `server.fs.deny` adds `*.env`, `*.db`, `*.db-*`, `*.db.*`, `*.sqlite*`, `*.bak`, `uploads/`, `backup/`, `db-backups/` and `.claude-test/` as a second layer. `*.env` matters because `node_modules/amber` links the sibling amber repo into an allowed folder, and Vite checks the linked path, not the real one: amber's native-host secrets file, `extension/host/host.env`, would otherwise be served (Vite's own `.env`/`.env.*` only match names starting `.env`). It's the allow list that keeps data out: on voyager's case-insensitive volume a deny glob can be sidestepped with characters picomatch doesn't fold (`bacKup` with a Kelvin sign is `backup`), and a prefix can't. So the dev server still serves the app's and backend's source to anyone who reaches it, but not the database, a copy of it, uploads or backups; keep data out of those four folders. A custom `deny` replaces Vite's defaults, so its first six entries copy Vite 8.3.1's: check them again when upgrading Vite.

The devices file is per machine: it's the one beside the API that reads it. Production's is `~/.enchiridion/devices` **on voyager**; creating one on the MacBook only switches the MacBook's own local API. The commands below run from the MacBook through `ssh voyager` (drop the `ssh voyager '…'` wrapper when you're on voyager). `ios/README.md` walks through adding the phone.

- **Turn it on**: creating the file turns checking on for every device at once, and an unlisted one (the MacBook's browser on the production web app, the Chrome extension's `/add` page) gets 401s from then on. So never create it with a single device: start from a copy of familiar's list, which already has the phone (`vern`) and the MacBook (`ranger`) in the same format, as `ios/README.md` does.

  ```sh
  ssh voyager 'test -e ~/.enchiridion/devices && { echo "Already on: add to it instead" >&2; exit 1; }; mkdir -p ~/.enchiridion && chmod 700 ~/.enchiridion && cp ~/.familiar/devices ~/.enchiridion/devices && chmod 600 ~/.enchiridion/devices'
  ```

- **List a device**: get its stable id from the 401's `device.id` (open the app on it, or `curl https://enchiridion-api.chsmc.tools/me` from it), or from `ssh voyager '/usr/local/bin/tailscale whois --json <its 100.x address>'` (`Node.StableID`; a command run over ssh doesn't get `/usr/local/bin` on its `PATH`). Add one line per device: the id, then an optional name; `#` starts a comment. This only adds to a file that exists, and refuses otherwise, so it can't turn checking on with one device listed:

  ```sh
  ssh voyager 'test -f ~/.enchiridion/devices || { echo "No devices file, so checking is off: turn it on first (copy ~/.familiar/devices)" >&2; exit 1; }; echo "nPh0neAbcd11CNTRL vern  # iPhone" >> ~/.enchiridion/devices'
  ```

- **Turn it off**: `ssh voyager 'rm ~/.enchiridion/devices'`. Once it has stayed gone for 2 s, the API is open again (no restart).
