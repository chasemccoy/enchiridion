# Enchiridion iOS: architecture

This is how the iPhone and iPad client is built.

- **Read this first.** Read this file before changing a public API, and update it in the same change.
- **The wire contract** is the Express API in `../backend/api/`.
- **The visual spec** is the web app (`../app/`, its `theme.css` and its components).
- **The sibling.** The structure mirrors familiar's Apple client (`~/Repositories/familiar/apple/`): three packages and thin targets.

## Principles

- **The server is the only copy.** Nothing from Enchiridion is persisted on the device, and nothing is cached on its disk. Only settings are kept: the library's filters and sort, in UserDefaults through `AppEnvironment.preferences` (`.none` in tests and previews, `.userDefaults` for the app), restored when `LibraryModel` starts. Every screen loads from the API, and every change is a request. Record images, which SwiftUI's `AsyncImage` loads through `URLSession.shared`, are cached in memory only: both targets call `URLCache.keepMediaInMemory()` at launch, which empties the shared cache and replaces it with a memory-only one. A failed request leaves the screen as it was, with the error shown; only a record found deleted elsewhere closes its screen, and then the library says so ("Curating and deleting").
- **No pairing, no tokens.** The API's address is a constant, `Server.production` = `https://enchiridion-api.chsmc.tools`. voyager knows the device through Tailscale.
- **Thin targets.** Anything that decides something lives in a package and is tested with `swift test` on the Mac. The app and extension targets hold only glue: `@main`, font registration, the memory-only media cache, `NSItemProvider`, the extension context, App Intents and the widget's timeline.
- **Platform-neutral packages.**
  - EnchiridionKit and EnchiridionCore import no UI framework.
  - EnchiridionUI is SwiftUI. It touches UIKit or AppKit only under `Sources/EnchiridionUI/Platform/`.
  - All three build for macOS, so the checks never need a simulator.
- **Swift 6 language mode** with strict concurrency set to complete, Swift Testing, and no third-party dependencies.

## Packages

| Package | Imports | Holds |
|---|---|---|
| `EnchiridionKit` | Foundation | Wire types, `EnchiridionClient` (an actor over an injected `HTTPTransport`), `EnchiridionError`, `Slug`, `DBTimestamp`, the predicate vocabulary |
| `EnchiridionCore` | Foundation, Observation, Kit | `AppEnvironment`, `Server`, and the `@MainActor @Observable` models: `LibraryModel`, `RecordDetailModel`, `RecordEditorModel`, `ShareComposeModel`. Also slug planning and share input. |
| `EnchiridionUI` | SwiftUI, Kit, Core | The theme (`Palette`, `Typography`, `Radius`, `Space`, `Metrics`, `FontRegistry`), the components (`RecordRow`, `MonthHeader`, `NotAllowedView`, `ErrorState`, …) and the screens (`EnchiridionRootView`, `LibraryScreen`, `RecordDetailScreen`, `RecordEditorSheet`, `ShareComposeView`) |

Dependencies point one way: Kit ← Core ← UI ← targets. Each package has `swift-tools-version: 6.4` and `platforms: [.iOS(.v27), .macOS(.v27)]`.

### Wire (EnchiridionKit)

**Requests and timeouts.**
- `EnchiridionClient` builds every request with `Accept: application/json`, and with `Content-Type: application/json` when there is a body.
- It sends `X-Enchiridion-Client: ios/<version> <role>`. The role is `app` or `share`.
- It never sends an `Origin` header.
- Timeouts: the app 30 s, the share extension 10 s.
- `URLSessionTransport` uses an ephemeral session: no cookies, no cache, and `waitsForConnectivity = false`, so "Tailscale is off" shows at once. Media goes through `URLSession.shared` instead (`AsyncImage`), whose cache is made memory-only at launch (`URLCache.keepMediaInMemory()`).

**Endpoints.**

| Call | Request |
|---|---|
| `info()` | `GET /info` (unauthenticated) |
| `me()` | `GET /me` |
| `list(_:)` | `POST /records` (a read). The index request mirrors the web's `ListQuery.index`: limit 100 000, `hideUntitledChildren`, ordered by `recordCreatedAt` desc then `slug` asc. The slug tiebreak matters because hundreds of rows share a timestamp. `ListQuery.newest` is the same with limit 1. |
| `search(_:limit:)` | `GET /search/hybrid?q=…&limit=100` |
| `record(id:)` | `GET /record/:id`, which returns `RecordDetail` (the record, outgoing links with full targets, media, archives) |
| `record(slug:)` | `GET /record/slug/:slug`. A 404 returns nil. |
| `links(id:)` | `GET /record/:id/links` |
| `save(_:)` | `PUT /record` |
| `setCurated(id:slug:_:)` | `PUT /record` with `{id, slug, isCurated}` only |
| `delete(id:)` | `DELETE /record/:id` |
| `deleteMedia(recordID:)` | `DELETE /media/record/:id` |
| `putLink` / `deleteLink` | `PUT /link` / `DELETE /link/:id` |

**`RecordInput` encoding.** It encodes an explicit `null` for every nil optional it sends. The server leaves absent keys untouched and clears null ones. `id` is left out for a create. A create sends every field; an update sends `id`, `slug` and only the fields in `fields` (`only(_:)`, from `fieldsDiffering(from:)`), so a column changed elsewhere since the client loaded its copy is never written back stale.

**Timestamps.**
- The server sends `"YYYY-MM-DD HH:MM:SS"` in UTC. `DBTimestamp` keeps that raw string, parses it with en_US_POSIX in UTC, and encodes it back unchanged.
- Display formats, all in the device's time zone:

  | Where | Example |
  |---|---|
  | Row date | "September 14" |
  | Detail captured badge | "March 14, 2026 at 10:12 AM" |
  | Published | "March 14, 2026" |
  | Month header | "September 2026" |

- Media URLs are relative (`/uploads/…`) and are resolved against the server.

**Open enums.** `RecordType` and `RecordSource` decode unknown values instead of failing.

### Errors

`EnchiridionError` is `Equatable` and `Sendable`. Every failure becomes one of these:

| Case | From | Message |
|---|---|---|
| `tailscaleOff` | URLError -1003, -1006 | "Tailscale is off. Turn it on to reach Enchiridion." |
| `unreachable` | -1001, -1004, -1005, any other URLError | "Can't reach voyager." |
| `offline` | -1009, -1020, -1018, TLS -1200…-1206 | "You're offline." |
| `restarting` | HTTP 502 (Caddy while pm2 restarts the API) | "Enchiridion is restarting." |
| `unauthorized(device:)` | 401, with `device` decoded from the body | "This iPhone isn't on Enchiridion's list yet." / "Enchiridion couldn't tell which device this is. Is Tailscale on?" |
| `forbidden` | 403 | "voyager refused the connection. Is this device on the tailnet?" |
| `notFound` | 404 (an HTML body; or JSON, from an update of a record deleted elsewhere) | "That record couldn't be found." |
| `rejected(status:message:)` | other 4xx | the server's message, cut to 250 characters |
| `server(status:message:)` | other 5xx | the same |
| `decoding` | an unreadable body | "Enchiridion sent something this app couldn't read." |

**Why -1003 means Tailscale is off.** `*.chsmc.tools` is a public CNAME to a `ts.net` name that is NXDOMAIN off the tailnet, so with Tailscale off the lookup fails at once.

**What is transient.** `isTransient` is true only for `tailscaleOff`, `unreachable`, `offline` and `restarting`. Enchiridion's 500s carry validation errors (Zod) and duplicate-slug errors, so they are permanent and are never retried automatically.

**Error bodies.** These are decoded in three shapes:
- `{message}`
- `{error: "string"}`
- `{error: {code, message}, message, device}`

## Data flow

```
EnchiridionApp (target)            FontRegistry.register(bundle: .main); AppEnvironment.live(server:)
  └ EnchiridionRootView(environment:)     owns the models in @State, passes them down with .environment(model)
      └ LibraryModel ── detailModel(id:) ──▶ RecordDetailModel ── makeEditor() ──▶ RecordEditorModel
             ▲                                     │                                   │
             └──────────── RecordChange (.created / .updated / .deleted) ◀─────────────┘
```

**The environment.** `AppEnvironment` is a `Sendable` struct holding everything a model touches outside itself:
- the server URL and the transport;
- the app version and platform (for the client header);
- `now`, a `Clock`, the time zone and `Timings` (search debounce 250 ms, saved linger 1 s, share deadline 10 s, editor deadline 30 s);
- the fallback-slug generator.

Models build their own clients with `client(role:)`. There are two factories:
- `.live(server:bundle:)` for the app;
- `.shareExtension(server:bundle:)` for the extension: production, unless a DEBUG build names another server (see "Overriding the server").

Tests use stub transports and a manual clock.

**The models.**
- Each is `@MainActor @Observable final class`. Fields that views read are `public private(set)`. Internal state is `@ObservationIgnored`.
- `LoadState` (idle, loading, loaded, failed) describes the last request only. Loaded data survives a failed refresh, so a view shows its content whenever there is some, and falls back to the error or the not-allowed state when there is none.

**Changes between models.** Detail and editor models report what they did through `onChange: RecordChange` to the library's `apply(_:)`:
- `.created` inserts the record in index order.
- `.updated` merges into rows the library already lists. An edited untitled highlight never enters the index, which hides those.
- `.deleted` removes the row.

**Changes made while a load is out.** The server may answer a load from before a change this client made meanwhile, so a load never simply overwrites what was changed:
- `LibraryModel` keeps the changes confirmed while `POST /records` is out and replays them onto its answer (`replay(_:onto:)`: a deleted row stays gone, an update is merged unless the row is newer, a created record is kept). A curate still waiting for its answer keeps showing on its row.
- Search answers get the same: changes confirmed while a search is out are replayed onto its results (`replay(_:onto:inserting: false)`, since a new record has no place in relevance order), and pending curates show. Hybrid search reads its text matches before the embedding call, so its answer can predate a delete or curate confirmed meanwhile.
- `RecordDetailModel` keeps its record over a loaded one that isn't newer (`recordUpdatedAt`) when a curate or an edit happened while the load was out.
- An open detail follows its list row (`RowSync` reports it to `rowChanged(_:)`): once the row has settled and is ahead of the record shown (`rowIsAhead`: a later `recordUpdatedAt`, or the same one with the other curation), the detail reloads. A row change that comes while the detail is loading or curating is kept and compared once it's done, so a curate from the list that lands during the detail's first load isn't missed.

**Curating and deleting.**
- Curating is optimistic. The row and the switch change at once, the server gets `{id, slug, isCurated}`, and a failure reverts the change and sets `actionError`. A lost answer (`unreachable` or `restarting`) may hide a curate that landed, so the record is read back first (`RecordCuration.confirm`): if it holds the new value, the curate succeeded and nothing reverts. If the read fails too, the change reverts with the error: the screen keeps to what the server last confirmed, and curating again is safe because it sets a value rather than toggling one.
- Deleting waits for the server, and always deletes media first (`deleteMedia`, then `delete`), as the web does. A row's or detail's media list can be stale (media added on the web since it loaded), and deleting none costs one request.
- A row with a curate or delete in flight (`workingIDs`) takes no other action: the model refuses it and the row's actions are disabled.
- A record deleted elsewhere answers a curate, an edit or a detail's load with 404 (the server refuses to update an id no row has, and ids are never reused). The row leaves, an open detail closes, and the record is said to be gone where the user will see it:
  - From the list (a swipe, the context menu), the library's alert says it.
  - From a detail (its Curate button, or loading it: a row the phone still lists after a delete on the web), the detail reports `.vanished`: it closes, and the library's alert (on `LibraryScreen`, above the navigation) says it.
  - From an editor, the sheet stays up with "That record couldn't be found." inline and the typed text still there. It reports `.deleted` when it closes (`RecordEditorModel.close()`, from the sheet's `onDisappear`); only then does the row leave and the detail it was opened from close.
- **Every editor is presented by `LibraryScreen`**, above the navigation: New record, a row's Edit, and a detail's Edit (`RecordDetailScreen`'s `onEdit`). A reload can move the selection while an editor is open (the record left the list: curated on the web while the list shows what needs curating, say), and a sheet goes with the screen that presented it, typed text and all. A detail's editor reports through its detail while that is still shown, and straight to the library once it isn't (`RecordDetailModel.makeEditor()`).

**Coming back to the foreground.** `EnchiridionRootView` reloads the index when the app becomes active after a failed load (a 401 included, because the not-allowed state has no Retry of its own) or after 15 minutes in the background. After a shorter time in the background (a share from Safari, say) it calls `refreshIfNewer()`, which asks for `ListQuery.newest` alone and reloads only when that record isn't in the index yet. Nothing pushes new records to the phone.

### The library

**Index, filters and sort.** `LibraryModel` loads the whole index once, as the web does. `visibleRecords` applies the web IndexView's filters and sort (`LibraryModel.Filters`):
- `type`: one type, or all;
- `needsCuration`: hides curated records;
- `hasMedia`: keeps records with any media attached;
- `sort`: newest (the index's own order), oldest, title A–Z (untitled last), or relevance (the search's ranking, offered only while searching). Nil means the default: relevance while searching, newest otherwise. Sorts are stable.

**Rows.** The list is a plain iOS list rather than the web's cards (`RecordRow`): edge to edge with the list's hairlines between rows, `elevated` while pressed and, on iPad, while selected. Inside, the web card's slots 6 pt apart: the record a search hit sits in, the title (semibold), the first image (150 pt, full width), the summary (else the content as plain text, `WidgetContent.excerpt`) on three lines, a muted line (the creator or domain, the date, the type unless an artifact, the highlight count, `#tags`) and the note's bubble. Rows use iOS's list sizes rather than the web's scale: title `.headline`, summary `.subheadline`, muted line `.footnote`, month headings `.subheadline` semibold.

**Sections.** Records are grouped by the local month of `recordCreatedAt` ("September 2026"). A section shows its count, " (N)", only when it has more than 4 records. Rows whose timestamp won't parse go into a trailing "Undated" section. While searching, or sorted by title, there is a single flat section with no header (the web's rule).

**Navigation.** On an iPhone (a compact width) `LibraryScreen` is one `NavigationStack`: the list, the selected record pushed on it, linked records pushed on that, so back goes one screen at a time. The stack's first screen follows `selectedID` (a model-moved selection replaces it, under any linked records above), and popping back to the list clears it. On an iPad it's a `NavigationSplitView` whose detail column has its own stack. The list's bottom bar holds the filter and sort menu, search and New record; a detail's has Curate, Open link, Share and Delete, with Edit in the navigation bar. Links open in an in-app Safari sheet (`inAppBrowser()`, which takes over `openURL` at the root).

**Detail layout.** A ledger: one left edge (`Metrics.detailMargin`, 20 pt) for text, hairlines and images, no boxes. A muted meta line replaces the web's badges (Needs curating in `text`, then type, source, saved date, number); the title; the byline (from the parent, by the creator; the domain moved to the Link row); the summary as a muted introduction and the note's bubble; images; content; a two-column facts table (Link, Published; `Metrics.ledgerLabelWidth`); then Linked records, each group's label above its plain rows (`LedgerList`: a hairline above the first row and below each, margin to margin), and Similar records the same way. Rows are at least 44 pt (`Metrics.ledgerRowHeight`) and highlight `elevated` out to the screen's edges when pressed. Designs explored on the "Record detail explorations" canvas (dense Ledger, 2026-10-16).

**Links on a detail.** "Linked records" has **Add link**, which presents `LinkPickerSheet` (the share card's two steps in a sheet of their own, over `RecordDetailModel.makeLinkSearch()`, which leaves out the record and the ones linked already) and calls `addLink(to:predicate:)`: `PUT /link` from this record, then the links alone reload. A linked row's context menu has Remove link (`removeLink(_:)`, `DELETE /link/:id`). Either failure sets `actionError`. **Similar records** below it come from `GET /record/:id/similar` (6, loaded beside the record and never holding it up or failing it; already-linked ones are left out as they're read), each with a menu to link it. A new record's editor has the share card's Links section (`RecordEditorModel.links`, sent after the create, `failedLinks` and `retryLinks()` as the card's, with an alert naming any that failed); an edit's links are changed on the detail.

**The count** (`countText`) reads as the web's: "567 records", "12 of 567 records", "8 results", "Searching…", "Search failed. Try again.". It is nil, and the title shows no count, until an index has loaded.

**Search.**
- Typing waits 250 ms for a pause, then runs a hybrid search (`GET /search/hybrid`): the server fuses the text match with semantic search over the records' embeddings by reciprocal rank, so it is semantic search that also finds exact names and domains. The link pickers and Shortcuts search the same way.
- The previous results stay on screen while a refined query loads.
- Clearing the field returns to the index at once.
- `refresh()` searches again immediately, for what the field holds now (text typed while the index reloaded included).

### Selection rule

This matches the web fix in commit `0c0f040`. `selectedID` is what the detail column shows. Whenever `visibleRecords` changes within the same list (a filter, a curate, a delete, a save, a reload of the index or of the same query's results):

1. A selection that is still listed stays.
2. A selection that left the list moves to the record that took its index, else to the last record, else to nil.
3. A selection that was never in the list stays as it is. For example, a record opened from a linked record.

Typical ways a record leaves the list: it's curated while the list is filtered to needs-curation, or it's deleted.

When the list becomes a different list, a position in the old one means nothing, so the rule doesn't run and the selection stays: clearing the search (results become the index, which may hide an opened result, such as an untitled highlight), or results for another query arriving. On iPad, results and an open record share the screen.

The rule is a pure function, `LibraryModel.successor(of:previous:next:)`, tested on its own. `remove(id:)` clears a selection that still points at the removed record. Starting a search from the index closes the open record (`selectedID = nil`), as on the web.

## Auth and connection states

### On the server (`../backend/api/auth.ts`)

**Off unless a devices file exists.** The file is `ENCHIRIDION_DEVICES`, or `~/.enchiridion/devices` by default.
- Without the file, the API is open, exactly as before, and `/me` answers scheme `open`.
- With the file, even an empty one, a request is admitted only if it is one of these:
  - **Loopback without `X-Forwarded-For`, with a `Host` naming this machine** (`localhost`, 127/8, `[::1]`). Scheme `local`: local dev, scripts, tests. A page DNS-rebound to 127.0.0.1 sends its own host name and is refused.
  - **voyager's own Tailscale node.** `Self.ID` from `tailscale status --json`. This covers the web app on voyager, the Simulator and agents.
  - **A listed device.** It must arrive through Caddy: a loopback peer with exactly one tailnet address in `X-Forwarded-For`, resolved with `tailscale whois`.
- A direct, non-loopback connection to `:4321` is refused.
- **Browsers, only from the web app.** While checking is on, a request whose `Origin` isn't the web app's (`https://enchiridion.chsmc.tools`, or the Vite dev server on loopback, which counts only on a request from a local process, since `localhost` is whatever machine the browser runs on) gets a 403 before anything else, and CORS echoes only the web app's origins. Admission goes by where a request comes from, so otherwise any page open in a listed device's browser could use the API as that device. The app sends no `Origin`, so none of this touches it.
- The file is re-read when its mtime or size changes, so creating or deleting it takes effect without a restart. Once checking is on, a missing file turns it off only after it has stayed missing for 2 s, every check in that time finding it gone (the server re-checks every 0.5 s while it's missing, request or not), so an editor replacing the file as it saves never opens the API.
- **Updates must name a record that exists.** `PUT /record` with an `id` no row has answers 404 instead of inserting a bare row under that id (a curate of a record deleted elsewhere would otherwise make one).

**Device names.** A device's name is the first label of its MagicDNS name (`vern`), because iPhones report the hostname "localhost". It falls back to the hostname, then the id.

**Routes.**
- `GET /info` is never gated. It answers `{"name":"enchiridion","auth":["tailscale"]}` when checking is on, and `"auth":[]` when it's off.
- `GET /me` answers `{scheme, device, user}`, where `scheme` is `tailscale`, `local` or `open`.
- A refusal is a `401` with the header `WWW-Authenticate: Tailscale realm="enchiridion"` and the body `{error: {code: "unauthorized", message}, message, device}`. `device` is present when Tailscale named the device but it isn't listed.

### On the client

**The not-allowed state.** Only a 401 shows it: `NotAllowedView`, reading "This iPhone isn't on Enchiridion's list yet", then the device's `name · id` (selectable), Copy ID, and "Add it to ~/.enchiridion/devices on voyager.".
- A 401 without a device reads "Enchiridion couldn't tell which device this is. Is Tailscale on?" instead.
- Being offline, Tailscale being off, or voyager restarting never looks like the not-allowed state. Those show `ErrorState` with the error's message and Retry.

**Who you are.** `GET /me` says how voyager sees the device (`scheme`, `device`, `user`); the app doesn't call it. Its only identity screen is the not-allowed state, which takes the device from the 401's body.

**Overriding the server.** Release builds always use `Server.production`. DEBUG builds may point elsewhere:
- the app with the launch argument `-EnchiridionServer <origin>` (`Server.fromArguments`);
- the app and the share extension, which never receives launch arguments, with the `EnchiridionServer` Info.plist key (`Server.fromInfoDictionary`). project.yml sets it from the `ENCHIRIDION_SERVER` build setting, empty in `Config/Base.xcconfig` and set in the gitignored `Config/Local.xcconfig`. The launch argument wins for the app.

Only an override that is absent, empty or unexpanded means production. One that is set but isn't an http(s) address (the `http:` an xcconfig leaves of `http://localhost:4399`, a typo, a bare `-EnchiridionServer`) gives `Server.misconfigured`, `https://enchiridion-server-misconfigured.invalid`: a reserved name that never resolves, so every request fails and the app says it can't reach voyager. A build meant for a sandbox never quietly writes to the live database.

## Editing and slug rules

`RecordDraft` holds the editable columns:
- `type`, `title`, `url`, `summary`, `content`, `notes`, `isCurated`;
- plus the record's `id`, `slug` and `source`, which are kept as they are.

**Saving a draft.**
- Title and URL are trimmed.
- Summary, content and notes are sent exactly as typed. Only a blank field becomes `null`.
- A draft can be saved when it has a non-blank title, URL, content or summary.

**Edits** always resend the record's own slug, because the server requires one, and otherwise only the fields the user changed (`RecordDraft.update(from:)`, against the draft the editor opened with). The editor may have opened on a copy loaded long ago (a list row, an open detail), so a field the user didn't touch is never sent: a change made elsewhere since (notes from an agent, a curate on the web) stays. An edit with nothing changed reads the record back instead of writing.

An update whose answer was lost (`unreachable` or `restarting`) may have landed, so it is checked first: the record is read back, and if it holds every field that was sent, the save succeeded. Otherwise the fields that update sent (after any failure but a 404, a cancelled request included) are sent again by every later save, even one the user has put back to how the editor opened, until one lands (`RecordEditorModel.hasUnsettledEdit`). Until then the sheet treats them as changes: Save stays on and Cancel asks first. Discarded anyway, the editor reads the record back as it closes and reports it as `.updated`, so the rows and an open detail show what the server holds.

A save that failed but may have landed all the same (`RecordEditorModel.mayHaveSaved`: an unsettled update, or a create whose record may exist) reads "Couldn't confirm the save" above the form, not "Couldn't save the record", and says that saving again won't save twice.

A save in the editor has `Timings.editorDeadline` (30 s) for all its requests together, as the share card has its own (below): each request's timeout only counts idle time, and the sheet can't be cancelled or swiped away while it saves. Past the deadline the save is cancelled and fails as unreachable; a create is checked by its slug on the next attempt, and an update is sent again.

**Creates** need a new slug. The server requires a unique, non-empty slug and never makes one. `RecordSlug` builds it:

1. **Base.** `Slug.make(title)`, a port of the web's `slugify(…, {lower, strict, trim})`, including its character map: accented letters to ASCII, `&` → `and`, `$` → `dollar`, and so on.
   - If the title gives nothing, the URL's host (without `www.`) and path are used. Every non-alphanumeric character becomes a word break, so `https://www.example.com/posts/X` gives `example-com-posts-x`. A bare `example.com/x` is read with https assumed (`WebAddress`, as links open it). These URL slugs are capped at 80 characters, cut at a hyphen.
   - If neither gives anything, the fallback is `note-` plus 8 lowercase hex digits. The live database already uses that form.
2. **Uniqueness.** `GET /record/slug/<candidate>` is tried for `base`, `base-2`, … `base-20` (20 probes). If all are taken, the fallback is used.
3. **Idempotency.** `PUT /record` without an id inserts every time, so a create whose answer was lost (`unreachable` or `restarting`) might have landed. `RecordCreation` remembers the body of a create whose outcome is unknown (`pending`).
   - After such a failure, and again before any retry, it looks that body's slug up.
   - A record there matching the body that was sent (the same URL; with no URL, the same title too) is ours: the create landed. The form stays editable after a failure, so the fields edited since that attempt go to that record as an update. They are what differs from the body that was sent, not from the record as it is stored now: a change made elsewhere since it landed (a curate on the web, an agent's summary) is never written back, and with no edits nothing is written. Once it is found, the record is remembered, and a failed update is sent again, its fields included even if the draft has since gone back to what was sent (it may have landed).
   - If the slug is still free, it is reused. If the title changed in between, a new slug is probed.
   - So Retry never makes a second record, and never drops an edit made before it.
   - A failure after which the record may exist all the same is unconfirmed (`RecordCreation.isUnconfirmed`): the answer was lost (or the save was cancelled at its deadline, or its 2xx body couldn't be read) and no check got through, or the record landed and an update to it failed. The editor and the share card word it as unconfirmed rather than unsaved, since a new form wouldn't know to look. A create the server refused (any answer but a 2xx or a 502), one that never left (Tailscale off, offline), and one whose check found its slug free or someone else's read as not saved; a free slug is still checked again before a retry, in case the request was only slow.
   - An editor closed with a create pending (discarded after a lost answer) looks the record up as it closes (`RecordCreation.abandon()`) and reports `.created` if it landed, so the list shows a record that is on the server.

## Share flow

1. **Preprocessing.** Safari runs `ShareExtension/Preprocess.js` before the extension opens. It returns `{url, title, selection, description}`. The description comes from `meta[name=description]`, else `og:description`, as the Chrome extension reads it.
2. **Reading the items.** `ShareViewController` (UIKit glue) reads the item providers in order:
   - the JavaScript results (`public.property-list`, via the legacy `loadItem`, the only API that returns that dictionary);
   - a URL;
   - plain text, or the item's attributed text.
3. **Interpreting them.** `ShareInput.from(javaScript:url:text:itemTitle:)` decides what was shared:
   - Safari's results with a web URL win.
   - Otherwise a web URL. Extra text that differs from the URL becomes the title if it's one line, or the selection if it's several.
   - A web share still without a title takes the share item's own (`NSExtensionItem.attributedTitle`, the `itemTitle` argument). Failing that, the extension fetches the page's metadata (`LPMetadataProvider`, 8 s) once the card is up and hands its title to `ShareComposeModel.suggestTitle(_:)`, which fills a blank title only, once, and only while editing, so nothing typed is overwritten.
   - Otherwise text. Text that is exactly one web URL counts as a URL share.
   - With nothing usable, the extension shows "Nothing to share" and closes after 1.5 s.
4. **The card.** `ShareComposeView` over `ShareComposeModel` (client role `share`, 10 s timeout) shows:
   - a preview row: the domain, then the page's title as shared (else its path); "Text" for a text share;
   - the web's add form, filled from the share (`ShareDraft`): the title in the serif, the type (segmented), the content (the selection or shared text), Details (summary, link, notes) and Curated;
   - Links: the pending links (`ShareDraft.links`, one per target: `link(_:)` replaces), each with a relationship menu (`Predicate.linkOptions`, the canonical predicates) and remove, then **Add link**. Add link pushes the web's two-step picker on the card's stack: `RecordLinkSearch` (the model's `linkSearch`, a `RecordSearchModel`, hybrid search after the debounce) and then `LinkPredicatePicker`;
   - **Save** in the bar and a **Save to Enchiridion** button.
5. **Saving** creates this record:

   ```
   {type, source: "manual", title, slug, url, isCurated, summary: description, content: selection, notes: note}
   ```

   Then each pending link goes as `PUT /link {sourceId: <new id>, targetId, predicate}` (the server canonicalizes and upserts). Links that fail are kept in `failedLinks`.

   The slug comes from the slug rules above, including the idempotency check.
6. **Endings.** The model's `state` goes from `editing` to `saving`, then to `saved` or `failed`.
   - `saved`: the card reads "Saved to Enchiridion", then completes the extension request after `savedLinger` (1 s). If any link failed, it stays open instead, naming them, with Retry (`retryLinks()`, links only: the record is never created again) and Done.
   - `failed`: the card keeps the message, with Retry and Copy link. It reads "Not saved" only when nothing was; a failure after which the record may exist (`ShareComposeModel.mayHaveSaved`: the answer was lost and the check after it failed too) reads "Couldn't confirm it saved", says it may be in Enchiridion already, and that Retry checks first. Sharing the page again from a new card would save it twice, since a new card can't know about this one's create.
   - A save has `Timings.shareDeadline` (10 s) for all its requests together; each request's own timeout only counts idle time. Past the deadline the save is cancelled and the card fails as unreachable. The create may have landed, so Retry checks its slug first.
   - Cancel is off while saving (at most the deadline) and cancels the card otherwise.

There is no outbox. Without App Groups the app can't see anything the extension parks, so a share is saved now or the card says it wasn't (or that it couldn't confirm it).

## Shortcuts

App Intents in the app target (`iOS/Shortcuts.swift`), no entitlement needed, over EnchiridionCore's `RecordShortcuts` on the app's own server (`AppServer.url`):
- `RecordEntity` and its `EntityStringQuery`: by id, by hybrid search, the 20 newest as suggestions.
- `OpenRecordIntent` (an `OpenIntent`): opens `enchiridion://record/<id>` (`DeepLink`, registered in the app's `CFBundleURLTypes`), which the root view's `onOpenURL` turns into `LibraryModel.selectedID`.
- `RandomRecordIntent`: a random record from the index query (curated only by default), said as its title and summary and returned for the next action.
- `SaveLinkIntent`: creates an artifact as the share card would with nothing edited (`RecordCreation`, so idempotent by slug), the title fetched with LinkPresentation when none is given.
- `EnchiridionShortcuts` gives each Siri phrases.

## Widget

`Widget/EnchiridionWidget.swift`, the `EnchiridionWidget` extension: one `AppIntentConfiguration` widget (small, medium, large, extra large, Lock Screen rectangular) whose configuration intent has Curated only (on by default) and New record every (15 min by default, 30 min or an hour: `RecordInterval`). It shows artifacts only (concepts and entities are mostly a name), and highlights (untitled records inside another, which the index hides) are always in the pool, curated or not (`RecordShortcuts.widgetPicks`): a highlight shows as its passage in the serif, "from <source> · by <creator>" below, typed Highlight. Its timeline is 12 hours of entries that far apart (at most 48) from one index load (`RecordShortcuts.sampleRetrying`, client role `widget`, 10 s a request), then `.atEnd`. Every size names the creator when the record has a `created_by` link ("by Robin Sloan · example.com" on the bottom line; on the Lock Screen in place of the type). The medium and larger sizes show the summary and the content as plain text (`WidgetContent.excerpt`) and the first image, fetched for each entry side by side (ephemeral session, 10 s) and downsampled to JPEG (`WidgetContent.thumbnail`: 480 px medium, 1000 px large) to stay inside a widget's memory; they take at most 12 entries per load (3 h at 15 min), every other one a record with an image while any are left (`imagesEvery`), since few records have one. Moving to the next entry is free; only loads count against WidgetKit's budget (roughly 40 to 70 a day), and this makes 2 to 8. A refresh runs in the background, sometimes before the phone's Tailscale tunnel is back, so a network failure is tried 3 times 3 s apart before it counts. Nothing to show waits 6 h; a failure shows the error's message with a Try again button (`ReloadRecordWidget`, an intent whose run reloads the timeline) and tries again on its own in 15 min. A tap opens `enchiridion://record/<id>`. It talks to the server itself (no App Groups to borrow the app's data), so it shows nothing while Tailscale is off. The serif comes from the extension's own bundle, as the share card's does.

## Targets (`project.yml`)

Generate the project with `xcodegen generate` (XcodeGen 2.46.0). The `.xcodeproj` is gitignored; the two Info.plists are generated from `project.yml` and committed.

| Target | Bundle id | Sources | Notes |
|---|---|---|---|
| `Enchiridion` (application) | `com.chsmc.enchiridion` | `iOS/` | Device family 1,2: portrait on iPhone, all orientations on iPad. `UILaunchScreen` with `LaunchIcon` (the icon cut from the web's `splash-light.png`, corners made transparent, 120 pt; its dark variant made the way the web's dark splash makes its own: the light icon by luminance, tinted by three quarters of the background's color cast, which the warm-neutral #1a1a19 leaves grey where the web's navy turns it blue-grey; then pulled halfway to the background's luminance, so it sits darker and quieter than the web's) on `LaunchBackground` (the page color, #fcfcfb light, #1a1a19 dark), as the web PWA's splash, `ITSAppUsesNonExemptEncryption: false`. `AppIcon` (1024 pt, single size, upscaled from `../app/public/pwa-512.png`). `AccentColor` (#2a78d6 light, #6da7ec dark). Embeds the extension. URL scheme `enchiridion` (`DeepLink`). |
| `EnchiridionWidget` (app extension) | `com.chsmc.enchiridion.widget` | `Widget/` | `com.apple.widgetkit-extension`. Links WidgetKit and SwiftUI. `APPLICATION_EXTENSION_API_ONLY`. |
| `EnchiridionShare` (app extension) | `com.chsmc.enchiridion.share` | `ShareExtension/` | `com.apple.share-services`. Principal class `$(PRODUCT_MODULE_NAME).ShareViewController`. Activates for one web URL, one web page, or text. Preprocessing file `Preprocess`. `APPLICATION_EXTENSION_API_ONLY`. |

**Shared settings.**
- Every target depends on all three packages.
- Each bundles Martina Plantijn's `regular.woff2` and `medium.woff2`, referenced in place from `../app/public/fonts/martina-plantijn/` and copied to the bundle's root.
- `FontRegistry.register(bundle:)` registers the fonts at runtime with CoreText, since `UIAppFonts` documents only TrueType and OpenType. If registration fails, the app uses New York.
  - Failures are logged as errors under subsystem `com.chsmc.enchiridion`, category `fonts`. DEBUG builds also log a notice, `Martina Plantijn registered: …`, which confirms the serif. In the Simulator, read its own log store (the Mac's `log show` never sees the Simulator's apps, and in zsh `log` is a builtin): `xcrun simctl spawn booted log show --last 1h --predicate 'subsystem == "com.chsmc.enchiridion"'`. On a device, use Console.app with the phone selected.
- `Config/Base.xcconfig` sets the team `GXA23694DJ` (paid; the free `756EWAN4G2` before 2026-10-15), automatic signing, iOS 27.0, `MARKETING_VERSION` 0.1, `CURRENT_PROJECT_VERSION` 1 (the commit count once `scripts/xcode.sh` has written the gitignored `Build.xcconfig`) and an empty `ENCHIRIDION_SERVER`, and includes the optional, gitignored `Local.xcconfig`. project.yml sets none of these: a project-level setting there would outrank the xcconfig, and `Local.xcconfig` couldn't override it.
- Both Info.plists carry `EnchiridionServer: $(ENCHIRIDION_SERVER)`, which only DEBUG builds read.

**Scheme.** The `Enchiridion` scheme builds all three targets. Run uses Release.

**Team.** The paid team allows entitlements, App Groups, keychain groups and push, but none is used: the extensions talk to the server themselves. No test targets in the project. Renaming a bundle id makes a new app on the phone.

## Testing

`scripts/test.sh` (zsh) runs:

- **Static gates:**
  - Kit and Core import no UI framework.
  - EnchiridionUI touches UIKit or AppKit only under `Platform/`.
  - EnchiridionUI never uses `.primary`, `.secondary` or other system colors.
  - The Info.plists lint and carry their required keys.
  - The asset catalog parses.
  - The font files exist.
  - There are no entitlements files.
- **Package steps, in parallel:**
  - `swift test` in EnchiridionKit and EnchiridionCore;
  - `swift build` of EnchiridionUI for macOS;
  - `xcodebuild` of EnchiridionUI for the iOS Simulator.
- **`--build`** first runs `xcodegen generate`, so the gates check the Info.plists project.yml makes now (and a plist that changed is reported, to be committed), then builds the whole app for the iPhone 18 Pro simulator with `CODE_SIGNING_ALLOWED=NO`.
- A gate that greps a path that doesn't exist fails rather than passing on no matches.

**No network in tests.** Tests use stub transports and never touch the network or the live server. Kit's `LiveSmokeTests` is read-only and runs only with `ENCHIRIDION_LIVE=1`.

**No device tests in CI.** Nothing boots a simulator. Device behaviour is checked by hand (README, "Device checks for the first install").
