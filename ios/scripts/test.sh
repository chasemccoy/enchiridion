#!/bin/zsh
# The iOS app's checks (ios/ARCHITECTURE.md, "Testing"). By default: the static gates, then in parallel `swift test`
# in EnchiridionKit and EnchiridionCore, `swift build` of EnchiridionUI for macOS, and an xcodebuild of EnchiridionUI
# for the iOS Simulator (which compiles Kit and Core for iOS too). Nothing boots a simulator. Keeps going after a
# failure and exits non-zero if anything failed.
#
# Usage: scripts/test.sh [--build | --gates]
#   (none)    the gates and the package steps
#   --gates   just the static gates (seconds)
#   --build   also `xcodegen generate` (first, so the gates check the Info.plists project.yml makes now) and a build of
#             the whole app (both targets) for the iPhone 18 Pro simulator with signing off: for a change to iOS/,
#             ShareExtension/, Config/ or project.yml
set -uo pipefail
zmodload zsh/datetime zsh/stat
cd "$(dirname "$0")/.."
(( $+commands[xcodegen] )) || path=(/opt/homebrew/bin $path)

build=""
gates_only=""
while (( $# )); do
  case "$1" in
    --build) build=1; shift ;;
    --gates) gates_only=1; shift ;;
    -h|--help) awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

LOGS="$(mktemp -d)"
failed=()
STEP_LIMIT=900      # seconds for one package step: a cold xcodebuild of EnchiridionUI takes a few minutes
SILENCE_LIMIT=300   # seconds without output before an xcodebuild counts as hung
SIMULATOR='platform=iOS Simulator,name=iPhone 18 Pro'

# Runs <command...> into <log>, stopped after STEP_LIMIT seconds, or 15 s after xcodebuild's "** … **" result line
# (xcodebuild sometimes hangs after it), or after SILENCE_LIMIT seconds without output. Returns the command's status;
# for xcodebuild, whether its result line says SUCCEEDED.
guarded() {  # guarded <log> <command...>
  local log="$1"; shift
  "$@" >"$log" 2>&1 &
  local pid=$! start=$EPOCHREALTIME last_size=-1 last_change=$EPOCHREALTIME size done_at=""
  while kill -0 $pid 2>/dev/null; do
    sleep 1
    size=$(zstat +size "$log" 2>/dev/null || echo 0)
    if (( size != last_size )); then last_size=$size; last_change=$EPOCHREALTIME; fi
    if [[ -z "$done_at" ]] && grep -qE '^\*\* [A-Z ]+ (SUCCEEDED|FAILED) \*\*' "$log"; then done_at=$EPOCHREALTIME; fi
    if [[ -n "$done_at" ]] && (( EPOCHREALTIME - done_at > 15 )); then
      echo "(stopped: xcodebuild didn't exit after its result)" >>"$log"; kill $pid 2>/dev/null; break
    fi
    if (( EPOCHREALTIME - start > STEP_LIMIT )) || { [[ -z "$done_at" ]] && (( EPOCHREALTIME - last_change > SILENCE_LIMIT )); }; then
      echo "(stopped: over ${STEP_LIMIT}s, or no output for ${SILENCE_LIMIT}s)" >>"$log"
      kill $pid 2>/dev/null; wait $pid 2>/dev/null; return 124
    fi
  done
  wait $pid; local rc=$?
  if [[ -n "$done_at" ]]; then
    grep -qE '^\*\* [A-Z ]+ SUCCEEDED \*\*' "$log"; return $?
  fi
  return $rc
}

# MARK: Static gates

gate_failures=()
gate() {  # gate <name> <offending lines, empty when the gate passes>
  if [[ -n "$2" ]]; then
    gate_failures+=("$1")
    echo "  ✘ $1"
    print -r -- "$2" | sed 's/^/      /' | head -20
  fi
}

# grep -rn over Swift sources, never into build directories. A path that doesn't exist is an offending line, so a
# gate looking in the wrong place fails instead of passing on no matches.
swift_grep() {  # swift_grep <extended regex> <paths...>
  local pattern="$1" target; shift
  for target in "$@"; do
    [[ -e "$target" ]] || print -r -- "$target: no such file or directory (the gate looks in the wrong place)"
  done
  grep -rnE --include='*.swift' --exclude-dir='.build*' --exclude-dir=build "$pattern" "$@" 2>&1
}

static_gates() {
  echo "▸ Static gates"
  local kit=Packages/EnchiridionKit/Sources core=Packages/EnchiridionCore/Sources ui=Packages/EnchiridionUI/Sources

  gate "EnchiridionKit and EnchiridionCore import no UI or app framework" \
    "$(swift_grep '^[[:space:]]*(@[a-zA-Z]+[[:space:]]+)*import[[:space:]]+((struct|class|enum|protocol|func|var|typealias)[[:space:]]+)?(UIKit|AppKit|SwiftUI|WidgetKit|ActivityKit)\b' $kit $core)"

  gate "EnchiridionUI touches UIKit and AppKit only under Platform/" \
    "$(swift_grep '^[[:space:]]*(@[a-zA-Z]+[[:space:]]+)*import[[:space:]]+(UIKit|AppKit)\b|canImport\((UIKit|AppKit)\)' $ui | grep -v '/Platform/')"

  # Every color comes from Palette. Doc comments may name the system styles.
  gate "EnchiridionUI draws with Palette, not .primary/.secondary system colors" \
    "$(swift_grep '\.(foregroundStyle|foregroundColor|background|fill|stroke|strokeBorder|tint|listRowBackground|shadow)\([[:space:]]*\.(primary|secondary|tertiary|quaternary)\b|Color\.(primary|secondary|accentColor)\b|HierarchicalShapeStyle\.|\.fill\.(primary|secondary|tertiary|quaternary)\b' $ui \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*///')"

  local plists=(iOS/Info.plist ShareExtension/Info.plist) lint="" file
  for file in $plists; do
    if [[ ! -f "$file" ]]; then lint+="$file is missing (xcodegen generate writes it)"$'\n'; continue; fi
    plutil -lint -s "$file" >/dev/null 2>&1 || lint+="$(plutil -lint "$file" 2>&1)"$'\n'
  done
  # Asset catalogs are JSON, which plutil reads (but -lint doesn't).
  for file in iOS/Assets.xcassets/**/Contents.json(N); do
    plutil -convert xml1 -o /dev/null "$file" >/dev/null 2>&1 || lint+="$file isn't valid JSON"$'\n'
  done
  gate "the Info.plists and asset catalog lint" "${lint%$'\n'}"

  local keys=""
  expect() {  # expect <file> <key path> <value>
    local actual; actual="$(plutil -extract "$2" raw -o - "$1" 2>/dev/null)"
    [[ "$actual" == "$3" ]] || keys+="$1: $2 is '${actual}', expected '$3'"$'\n'
  }
  for file in $plists; do
    [[ -f "$file" ]] || continue
    expect "$file" CFBundleDisplayName Enchiridion
    expect "$file" CFBundleShortVersionString '$(MARKETING_VERSION)'
    expect "$file" CFBundleVersion '$(CURRENT_PROJECT_VERSION)'
    expect "$file" EnchiridionServer '$(ENCHIRIDION_SERVER)'
  done
  if [[ -f iOS/Info.plist ]]; then
    expect iOS/Info.plist ITSAppUsesNonExemptEncryption false
    plutil -extract UILaunchScreen raw -o - iOS/Info.plist >/dev/null 2>&1 || keys+="iOS/Info.plist has no UILaunchScreen"$'\n'
  fi
  if [[ -f ShareExtension/Info.plist ]]; then
    local share=ShareExtension/Info.plist rule=NSExtension.NSExtensionAttributes.NSExtensionActivationRule
    expect $share NSExtension.NSExtensionPointIdentifier com.apple.share-services
    expect $share NSExtension.NSExtensionPrincipalClass '$(PRODUCT_MODULE_NAME).ShareViewController'
    expect $share NSExtension.NSExtensionAttributes.NSExtensionJavaScriptPreprocessingFile Preprocess
    expect $share $rule.NSExtensionActivationSupportsWebURLWithMaxCount 1
    expect $share $rule.NSExtensionActivationSupportsWebPageWithMaxCount 1
    expect $share $rule.NSExtensionActivationSupportsText true
  fi
  [[ -f ShareExtension/Preprocess.js ]] || keys+="ShareExtension/Preprocess.js is missing"$'\n'
  [[ -f iOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png ]] || keys+="the 1024 pt AppIcon.png is missing"$'\n'
  for file in regular medium; do
    [[ -f ../app/public/fonts/martina-plantijn/$file.woff2 ]] \
      || keys+="../app/public/fonts/martina-plantijn/$file.woff2 is missing (project.yml bundles it)"$'\n'
  done
  gate "the required Info.plist keys and resources" "${keys%$'\n'}"

  # The free team gets no App Groups or keychain groups, and nothing here needs an entitlement.
  gate "no entitlements files" "$(find iOS ShareExtension Config -name '*.entitlements' 2>/dev/null)"

  if (( ${#gate_failures[@]} )); then
    failed+=("Static gates")
  else
    echo "  all passed"
  fi
}

# MARK: Packages

# Starts one step in the background, in a package directory; its status lands in $LOGS/<name>.status.
start_step() {  # start_step <name> <package dir> <command...>
  local name="$1" dir="$2"; shift 2
  steps+=("$name")
  (
    local start=$EPOCHREALTIME rc
    ( cd "Packages/$dir" && guarded "$LOGS/$name.log" "$@" ); rc=$?
    printf '%.1f' $(( EPOCHREALTIME - start )) >"$LOGS/$name.time"
    echo $rc >"$LOGS/$name.status"
  ) &
}

report_step() {  # report_step <name>
  local name="$1"
  if [[ "$(<"$LOGS/$name.status")" == 0 ]]; then
    echo "▸ $name ($(<"$LOGS/$name.time") s)"
    grep -E "Test run with|Build complete|^\*\* BUILD" "$LOGS/$name.log" | tail -2 | sed 's/^/  /'
    local warnings; warnings=$(grep -E ': warning: ' "$LOGS/$name.log" | sort -u | wc -l | tr -d ' ')
    (( warnings )) && echo "  $warnings warnings (log: $LOGS/$name.log)"
  else
    echo "▸ $name"
    failed+=("$name")
    # SwiftPM colors its diagnostics even into a file: strip the escapes.
    grep -E "✘|error:|stopped:|\*\* BUILD FAILED" "$LOGS/$name.log" | head -20 | sed -E $'s/\e\\[[0-9;]*m//g; s/^/  /'
    echo "  (full log: $LOGS/$name.log)"
  fi
}

# MARK: The project

# With --build, the project and its Info.plists are generated before the gates run, so the gates judge what
# project.yml makes now rather than the copies from the last generation. A plist that changed is reported: commit it.
generated=""
if [[ -n "$build" ]]; then
  echo "▸ xcodegen generate"
  for file in iOS/Info.plist ShareExtension/Info.plist; do
    [[ -f "$file" ]] && cp "$file" "$LOGS/${file:h}.plist.before"
  done
  if xcodegen generate >"$LOGS/xcodegen.log" 2>&1; then
    generated=1
    for file in iOS/Info.plist ShareExtension/Info.plist; do
      cmp -s "$file" "$LOGS/${file:h}.plist.before" 2>/dev/null \
        || echo "  $file changed with project.yml: review and commit it"
    done
  else
    failed+=("xcodegen"); sed 's/^/  /' "$LOGS/xcodegen.log"
  fi
fi

static_gates
if [[ -n "$gates_only" ]]; then
  (( ${#failed[@]} )) && { echo "✘ Failed: ${(j:, :)failed}"; exit 1; }
  echo "✔ The static gates passed"; exit 0
fi

# Each step has its own scratch path, so the steps (and an Xcode build) never contend on one `.build`.
steps=()
start_step EnchiridionKit EnchiridionKit swift test --scratch-path .build-check --disable-index-store
start_step EnchiridionCore EnchiridionCore swift test --scratch-path .build-check --disable-index-store
start_step "EnchiridionUI (macOS)" EnchiridionUI swift build --scratch-path .build-check --disable-index-store
start_step "EnchiridionUI (iOS Simulator)" EnchiridionUI xcodebuild build -scheme EnchiridionUI \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath .build-check-ios COMPILER_INDEX_STORE_ENABLE=NO
wait
for step in $steps; do report_step "$step"; done

# MARK: The app

if [[ -n "$generated" ]]; then
  echo "▸ App build (iPhone 18 Pro simulator, signing off)"
  if guarded "$LOGS/App.log" xcodebuild build -project Enchiridion.xcodeproj -scheme Enchiridion \
         -configuration Debug -destination "$SIMULATOR" -derivedDataPath build CODE_SIGNING_ALLOWED=NO; then
    grep -E '^\*\* BUILD' "$LOGS/App.log" | sed 's/^/  /'
    echo "  $(grep -E ': warning: ' "$LOGS/App.log" | sort -u | wc -l | tr -d ' ') warnings (log: $LOGS/App.log)"
  else
    failed+=("App build")
    grep -E "error:|stopped:|\*\* BUILD" "$LOGS/App.log" | head -20 | sed 's/^/  /'
    echo "  (full log: $LOGS/App.log)"
  fi
fi

if (( ${#failed[@]} )); then
  echo "✘ Failed: ${(j:, :)failed}"; exit 1
fi
echo "✔ All checks passed"
