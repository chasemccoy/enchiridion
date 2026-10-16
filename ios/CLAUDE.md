# Enchiridion for iOS

The iPhone and iPad client and its share extension. Three documents cover it:

- `ARCHITECTURE.md` is normative. Read it before changing any public API, and update it in the same change.
- The wire contract is the Express API in `../backend/api/`. The visual spec is the web app in `../app/`.
- `README.md` is Chase's guide: first install, the team, the devices file, re-signing, fonts and the device checks.

## Commands

Run these from `ios/`:

```zsh
scripts/test.sh              # static gates, then in parallel: swift test (Kit, Core), EnchiridionUI built for
                             # macOS (swift build) and for the iOS Simulator (xcodebuild)
scripts/test.sh --gates      # just the static gates (seconds)
scripts/test.sh --build      # also xcodegen (before the gates) + a full app build for the iPhone 18 Pro simulator, signing off
(cd Packages/EnchiridionCore && swift test --scratch-path .build-<name>)   # one package, your own scratch path
PATH=/opt/homebrew/bin:$PATH xcodegen generate                           # regenerate Enchiridion.xcodeproj
scripts/xcode.sh --no-open                                                # regenerate only if project inputs changed
```

- **The MacBook stays in sync through git hooks** (`scripts/install-hooks.sh`, see README "Staying in sync"). If you add a target folder or a project input that XcodeGen reads, add it to the fingerprint in `scripts/xcode.sh` too.

- **Scratch paths.** Several `swift test` processes in one package contend on `.build`, so give each its own `--scratch-path .build-<name>`.
- **Ignored output.** Every `.build*` directory, `build/` and the `.xcodeproj` are gitignored by the repo's root `.gitignore`.
- **The web gates skip this folder.** `pnpm lint` ignores `ios/` (`.prettierignore`, `eslint.config.js`). `scripts/test.sh` is this folder's gate.

## Build discipline

- **No simulator boots and no UI tests.** No app unit-test target. No screenshots unless Chase asks.
- **Package-only changes:** run `scripts/test.sh`.
- **Changes to `iOS/`, `ShareExtension/`, `Widget/`, `Config/` or `project.yml`:** run `scripts/test.sh --build`, at most once per change.
- **Device behaviour** is checked by hand on Chase's iPhone (README, "Device checks for the first install").

## Hands off production

voyager is the production server.

- **The database.** `../enchiridion.db` is the live database.
- **No writes to the live API.** Never point a test, preview or script that writes at `https://enchiridion-api.chsmc.tools` or `localhost:4321`.
  - Tests use stub transports.
  - Kit's `LiveSmokeTests` only reads, and runs only with `ENCHIRIDION_LIVE=1`.
- **The devices file.** Never create, edit or delete `~/.enchiridion/devices`. Creating it turns device checking on for everyone, and deleting it turns checking off.
- **Backend edits restart the API.** Saving a file under `../backend/` restarts the live API, because pm2 runs it in watch mode.

## Invariants

- **The server is the only copy.** No disk cache, no persistence, no outbox. The one thing kept on the device is settings, never records: the library's filters and sort, in the app's UserDefaults (`Preferences`). Record images load through `URLCache.shared`, which both targets make memory-only at launch (`URLCache.keepMediaInMemory()`). Without App Groups the extension can't hand anything to the app, so a share is saved now or the card says it wasn't (or, when its answer was lost, that it couldn't confirm it).
- **No pairing.** The server is the constant `Server.production`, and voyager knows the device through Tailscale. Nothing about the server or the device is stored.
  - DEBUG builds of the app accept `-EnchiridionServer <origin>`.
  - DEBUG builds of the app and the share extension read `ENCHIRIDION_SERVER` from the gitignored `Config/Local.xcconfig` (the `EnchiridionServer` Info.plist key). Release builds always use production.
  - An override that is set but isn't an http(s) address goes to `Server.misconfigured` (a `.invalid` host, so every request fails), never to production.
- **Only a 401 shows the not-allowed state.** Being offline, Tailscale being off or voyager restarting show `ErrorState` with Retry, never `NotAllowedView`.
- **Enchiridion's 500s are permanent.** They carry validation and duplicate-slug errors. `isTransient` covers only `tailscaleOff`, `unreachable`, `offline` and `restarting`.
- **Creates are idempotent by slug.** A create whose answer was lost is looked up by its slug before any retry (`RecordCreation`), matched against the body that was sent; edits made since go to that record as an update of the fields that differ from that body (never from the record as stored now, which others may have changed). An editor closed with a create unsettled looks it up the same way and reports it if it landed (`RecordEditorModel.close()`). Never retry a `PUT /record` create blindly.
- **Explicit nulls, only what changed.** `RecordInput` encodes `null` for every nil optional it sends, never `id` when nil. The server treats an absent key as "unchanged" and `null` as "clear". Updates send only the fields that changed (`only(_:)`): a copy loaded earlier must never write stale columns back. The one addition is an earlier update's fields when it failed and may have landed: those go again until one lands, even if the draft has gone back (`RecordEditorModel.hasUnsettledEdit`).
- **Delete media first.** Deletes always call `deleteMedia` before `delete`, as the web does, whatever a row says about media.
- **Loads don't undo changes.** A change confirmed while an index load or a search is out is replayed onto its answer (`LibraryModel.replay`), and a detail keeps a record changed during its load. A list change that comes while a detail is busy is compared once it's done (`RecordDetailModel.rowChanged`).
- **Platform-neutral packages.**
  - EnchiridionKit and EnchiridionCore import no UI framework.
  - UIKit and AppKit appear only in the targets and under `EnchiridionUI/Sources/EnchiridionUI/Platform/`.
  - Every package builds for macOS.
- **Thin targets.** Anything that decides something lives in a package and is tested with `swift test`.
- **Paid team (`GXA23694DJ`, since 2026-10-15; before it the free `756EWAN4G2`).**
  - No entitlements, App Groups, push or test targets yet: none is needed, though the team now allows them. Adding one is Chase's call.
  - Don't rename the bundle ids (`org.chsmc.enchiridion`, `.share`, `.widget`) or add targets without Chase asking: a new bundle id means a new install on the phone.

## Style

- **Swift.** Swift 6 language mode, strict concurrency complete, Swift Testing (`import Testing`), no third-party dependencies.
- **Models.** Explicitly `@MainActor @Observable final class`. Fields views read are `public private(set)`, and internal state is `@ObservationIgnored`. Models live in `@State` once, at the root, and go down through `.environment`.
- **Tokens.** Views take every color, font, space and radius from EnchiridionUI's theme: `Palette`, `Typography`, `Space`, `Radius`, `Metrics`.
  - Never use `.primary`, `.secondary` or other system colors; `scripts/test.sh` greps for them.
  - Corners are always `.continuous`.
  - The root of every hierarchy (the app, each sheet, the share card) applies `enchiridionRoot()`.
- **Serif.** Martina Plantijn is used only for the wordmark and the detail title, registered at runtime by `FontRegistry`, with New York as the fallback. Never copy the `.woff2` files into `ios/`: they are Klim-licensed and referenced in place from `../app/public/fonts/`.
- **Copy.** Sentence case in every string and heading. The product is "Enchiridion" in UI copy; identifiers and URLs stay lowercase. Comments are brief doc comments that explain why, not narration.
