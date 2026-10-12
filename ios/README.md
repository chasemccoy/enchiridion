# Enchiridion for iPhone and iPad

A native client for Enchiridion. It covers the library and the share sheet:

- **The library.** Browse every record, grouped by month. Filter by type or to what still needs curating, and search with hybrid search.
- **Records.** Read a record with its metadata and linked records. Curate, edit, delete, or create one.
- **The share sheet.** From Safari or any app, save a page (its URL, title, selected text and description) or some text as a new artifact.

The app talks to the API on voyager at `https://enchiridion-api.chsmc.tools` over Tailscale. The server is the only copy of the data. Nothing from the server is stored on the phone: record images are cached in memory while the app runs, never on disk.

`ARCHITECTURE.md` describes how the app works. `CLAUDE.md` has the rules for agents. The visual design follows the web app (`../app/`), token for token.

## First install on the iPhone

The app is signed automatically with the free Personal Team (`756EWAN4G2`).

1. On the MacBook, once per clone: install XcodeGen and the git hooks that keep the project in step (see "Staying in sync" below).

   ```zsh
   brew install xcodegen
   ~/Repositories/enchiridion/ios/scripts/install-hooks.sh
   ```

2. Generate the project and open it. The generated `.xcodeproj` is never committed.

   ```zsh
   ~/Repositories/enchiridion/ios/scripts/xcode.sh
   ```

   In **Xcode › Settings › Accounts**, the Apple ID with the free team (`756EWAN4G2`) must be signed in. It's the same one familiar and faulkner use.

3. Pick the iPhone as the run destination, leave the scheme on **Enchiridion**, and press Run. The Run action builds Release, so the phone always talks to the production server.
4. The first time only:
   - On the iPhone, turn on **Settings › Privacy & Security › Developer Mode**. The phone restarts.
   - After the install, go to **Settings › General › VPN & Device Management** and trust the developer certificate.

### What the free team allows

- **App IDs.** The first install registered two: `org.chsmc.enchiridion` and `org.chsmc.enchiridion.share`. The widget adds a third, `org.chsmc.enchiridion.widget`, the first time a build with it is installed. A free team may register 10 App IDs in any 7 days, and familiar and faulkner already use 3 each. Each new ID counts against that limit, so don't rename bundle IDs or add targets casually.
- **The widget is a trial.** If installing fails with a message about the number of apps or App IDs, the widget extension is what tipped it: say so, and it comes out of `project.yml` (or wait out the 7 days for an App ID limit).
- **Apps per device.** A free team may have **3 apps** installed on one device. familiar and faulkner already take 2, so Enchiridion takes the last slot.
  - To install a fourth app, delete one of the three first.
  - Keep **Offload Unused Apps** off (Settings › Apps › App Store). An offloaded app still counts toward the 3.
- **Not available on the free team:** App Groups, keychain sharing, push and UI-test targets. The app needs none of them. The share extension saves straight to the server.

## Staying in sync

Work on the app can happen anywhere (including on voyager), but the phone is installed from the MacBook. The project file is generated, so after a pull Xcode only sees new files or target changes once it's regenerated. Two pieces take care of that:

- **`scripts/xcode.sh`** regenerates `Enchiridion.xcodeproj` when anything XcodeGen reads has changed (`project.yml`, `Config/*.xcconfig`, the file list of `iOS/`, `ShareExtension/` and `Widget/`, or the XcodeGen version), then opens it. It's cheap when nothing changed, so it's fine to use as the everyday way to open the project. `--pull` pulls first; `--force` regenerates regardless; `--no-open` skips opening Xcode.
- **The git hooks** from `scripts/install-hooks.sh` run `xcode.sh --no-open --quiet` after every pull (merge or rebase) and branch switch. An open Xcode reloads the regenerated project by itself. The hooks never fail a pull: if XcodeGen is missing they print the reason and the pull completes.

Changes inside `Packages/` never need a regeneration: Xcode reads the Swift packages directly.

The day-to-day loop on the MacBook is:

```zsh
cd ~/Repositories/enchiridion && git pull      # the hook regenerates if needed
ios/scripts/xcode.sh                           # or just switch to Xcode if it's already open
```

Then press Run with the iPhone as the destination.

## Every week: re-signing

Free-team profiles expire 7 days after the build that made them. Once they expire, the app and the share extension won't open until you install a fresh build. Nothing is lost when that happens, because nothing lives on the phone.

To renew, connect the iPhone (or put it on the same Wi-Fi as the Mac) and press Run in Xcode again before the week is up.

## Adding the phone to Enchiridion's list

There is nothing to pair and no token to enter. The API recognizes devices through Tailscale, so Tailscale must be on and signed in on the phone.

The API checks devices only while `~/.enchiridion/devices` exists on voyager.

**Without the file**, the API is open, as it always was.

**With the file** (even an empty one), only these can reach the API:

- the devices listed in the file;
- voyager itself, so the web app opened on voyager, the Simulator and agents still work;
- local processes on voyager that connect without a proxy.

Creating the file turns checking on for everyone at once, so list your devices in it before you create it. The file is re-read whenever it changes, so there's no restart. Deleting it turns checking off again once it has stayed gone for two seconds; the server keeps checking for itself in that time, so an editor that replaces the file as it saves never opens the API.

The file has one Tailscale node ID per line, optionally followed by a name. Lines starting with `#` are comments:

```
# Devices allowed to reach Enchiridion's API: Tailscale node ID, then a name
nXXXXXXXXXXXCNTRL vern
nYYYYYYYYYYYCNTRL ranger
```

familiar's `~/.familiar/devices` uses the same format and already lists the phone and the MacBook, so the quickest start is a copy of it:

```zsh
ssh voyager 'test -e ~/.enchiridion/devices && { echo "Already on: add to it instead" >&2; exit 1; }; mkdir -p ~/.enchiridion && chmod 700 ~/.enchiridion && cp ~/.familiar/devices ~/.enchiridion/devices && chmod 600 ~/.enchiridion/devices'
```

It refuses when the file already exists, so it never overwrites a list you've added to.

To add a device later:

1. Open Enchiridion on it. It shows **This iPhone isn't on Enchiridion's list yet**, with the phone's Tailscale name and ID underneath. Tap **Copy ID**.
2. On the MacBook, add that ID to the file on voyager. Universal Clipboard carries the copied ID over. The MacBook reads its own pasteboard and sends the ID along, then the device's name (change `ipad` to it):

   ```zsh
   id=$(pbpaste)
   if [[ $id =~ '^n[[:alnum:]]+CNTRL$' ]]; then
     ssh voyager "test -f ~/.enchiridion/devices || { echo 'No devices file on voyager, so nothing to add to' >&2; exit 1; }; grep -qE '^[[:space:]]*$id([[:space:]#]|\$)' ~/.enchiridion/devices && { echo '$id is already listed: copy the ID on the new device again' >&2; exit 1; }; echo '$id ipad' >> ~/.enchiridion/devices" && echo "Added $id"
   else
     echo "The clipboard doesn't hold a Tailscale node ID (n…CNTRL)" >&2
   fi
   ```

   The check takes only a whole node ID: `n`, then letters and digits, then `CNTRL`. Anything else on the clipboard (a quote, a space, several lines) never reaches voyager, and the command says so instead of doing nothing. It refuses an ID the file already lists: that is what's left on the MacBook's clipboard when the new device's Copy ID didn't sync, often the last device added. It also only adds to a devices file that exists, so it can't turn checking on with one device listed.

   An older ID that isn't in the file yet still passes, so compare the ID the command prints after "Added" with the one on the device's screen.

3. Go back to Enchiridion. It loads again when it returns to the foreground after a failed load, or you can pull to refresh.

Other problems have their own messages, and none of them looks like the not-listed screen:

- "Enchiridion couldn't tell which device this is. Is Tailscale on?" means the request reached voyager, but not through Tailscale.
- "Tailscale is off", "You're offline", "Can't reach voyager" and "Enchiridion is restarting" each come with Retry.

To check the API's state from anywhere on the tailnet:

```zsh
curl -s https://enchiridion-api.chsmc.tools/info   # {"name":"enchiridion","auth":["tailscale"]} when checking
curl -s https://enchiridion-api.chsmc.tools/me     # how voyager sees the device you ran it on
```

## Using it

- **Library.**
  - Pull to refresh.
  - The bottom bar holds the filter menu (type, **Needs curation**, **Has media**, and the sort: newest, oldest, title, or relevance while searching), search, and **+** for a new record.
  - Search runs hybrid search as you type: matches by meaning (semantic, from the records' embeddings) fused with matches on the words, as the web's search does. "Essays about small websites" finds them without those words in the title.
  - Swipe a card to curate or delete it, or long-press for Open link, Copy link, Curate and Delete.
  - On iPad the record opens beside the list.
- **Record.**
  - The content, a Details card (summary, link, published date, notes) and the linked records, a card per kind of link. Tap a linked record to open it; swiping back returns one screen at a time.
  - **Edit** is at the top. The bottom bar has **Curate**, **Open link**, **Share** and **Delete**.
  - **Add link** (beside Linked records) searches for a record, then asks how it's linked. Long-press a linked record for **Remove link**.
  - **Similar records** lists records close in meaning that aren't linked yet. Tap one to open it, or its link button to link it.
  - Links open in an in-app browser sheet.
- **New record.** The editor has a Links section like the share card's; the links are added once the record saves.
- **Siri and Shortcuts.** No setup: the actions appear in the Shortcuts app under Enchiridion.
  - "Show me something from Enchiridion": a random curated record, read out, and handed to the next action.
  - "Open a record in Enchiridion": asks which (searching as you type or say it), then opens it.
  - "Save a link to Enchiridion": saves a URL (with an optional title and note) without opening the app; the page's own title is fetched when none is given.
  - `enchiridion://record/<id>` opens a record from anywhere (an Open URL action, a note).
- **Widget.** Long-press the Home Screen › Edit › Add Widget › Enchiridion: a random curated record (small, medium or large, or on the Lock Screen), a new one each hour; medium and large add the summary, the content and the record's image (every other hour is a record with one); tap it to open the record. Edit the widget to include uncurated records.
- **Sharing.**
  - Share a page from Safari. Select text first to save it as the record's content; the page's description becomes the summary.
  - The card is the web's add form: title, type, content, and Details (summary, link, notes), plus Curated. Everything is filled from the share and editable.
  - **Add link** searches for a record, then asks how it's linked ("Created by", "Tagged with"…). Change a pending link's relationship from its menu, or remove it. Links are added once the record saves.
  - Tap **Save** (in the bar) or **Save to Enchiridion**. If the record saves but a link doesn't, the card stays open naming the links that failed, with **Retry** and **Done**.
  - If the save fails, the card stays open with **Retry** and **Copy link**. A retry never saves the record twice. When the save may have reached voyager though its answer didn't come back, the card says it couldn't confirm the save rather than "Not saved": tap Retry, since sharing the page again later would save it twice.

## Fonts

The record titles and the wordmark use **Martina Plantijn**, the web app's serif. The app bundles the web's own `regular.woff2` and `medium.woff2` from `../app/public/fonts/martina-plantijn/`. `project.yml` references them where they are, never copies them, and the app registers them at launch.

Martina Plantijn is licensed from Klim Type Foundry. The files name Klim order Nº 24010112, and the licence terms are at <https://klim.co.nz/licences/>. A web licence doesn't necessarily cover embedding a font in an app, so **confirm that the licence covers app embedding** before installing this anywhere but your own devices.

Without the fonts, the app falls back to the system serif (New York), which is also in the web's font stack. To drop them, remove the two `.woff2` entries from each target's sources in `project.yml`.

## Development

```zsh
scripts/test.sh            # static gates, swift test (Kit, Core), EnchiridionUI built for macOS and the iOS Simulator
scripts/test.sh --gates    # just the static gates
scripts/test.sh --build    # also xcodegen and a build of the whole app for the iPhone 18 Pro simulator, signing off
```

A Debug build can point at another API. Release builds always use production.

- **The app alone:** set it under Product › Scheme › Edit Scheme › Run: set the Build Configuration to Debug, and add `-EnchiridionServer http://localhost:4321` under Arguments Passed On Launch. Put the scheme back on Release when you're done.
- **The app and the share extension** (which never sees launch arguments): set `ENCHIRIDION_SERVER` in a `Config/Local.xcconfig` (gitignored), then build Debug. `//` starts a comment in an xcconfig, so put an empty `$()` between the slashes:

  ```
  ENCHIRIDION_SERVER = http:/$()/localhost:4399
  ```

  It reaches every target's Info.plist as `EnchiridionServer`. A launch argument still wins for the app. Delete the line (or the file) to go back to production.

  Written as `http://localhost:4399`, the value arrives cut to `http:`. Like any value that isn't an http(s) address, that sends the build to `enchiridion-server-misconfigured.invalid` instead of production: every request fails, and the app shows it can't reach voyager.

The Simulator on voyager runs on voyager's own network, so it reaches production as voyager itself.

**Production safety.** The API on voyager and `../enchiridion.db` hold the live data. Nothing in `scripts/test.sh` touches the network. Kit's opt-in smoke test only reads. Run it from `ios/`:

```zsh
(cd Packages/EnchiridionKit && ENCHIRIDION_LIVE=1 swift test --scratch-path .build-live --filter LiveSmokeTests)
```

## Device checks for the first install

1. **First run.** With checking on and the phone not yet listed, the app shows the not-listed screen with the phone's name and ID. Add the ID to the file; a pull to refresh then loads the library.
2. **Tailscale off.** Turn Tailscale off. The library says "Tailscale is off. Turn it on to reach Enchiridion." with Retry, never the not-listed screen.
3. **Share from Safari.** Select a paragraph and share to Enchiridion. The card shows the domain and title. Add a note, add a link to an existing record (search, then pick "Created by"), and save: the card reads "Saved to Enchiridion" and closes. The record appears in the web app with the URL, the selection as its content, the description as its summary, the note as its notes and the link.
4. **Share while offline.** Share with Tailscale off. The card fails with a message, Retry and Copy link. Turn Tailscale on and tap Retry: the share is saved once.
5. **Curation.** Filter to Needs curation, open a record and turn Curated on. The record leaves the list and the next one is selected (on iPad, side by side).
6. **Fonts.** The detail title is set in Martina Plantijn, not New York. Compare it with the web app.
