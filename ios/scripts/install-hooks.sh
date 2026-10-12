#!/bin/zsh
# Install git hooks that keep ios/Enchiridion.xcodeproj in step with the checkout.
#
# Run once per clone (on the MacBook). Afterwards every `git pull` (merge or rebase) and every
# branch switch runs `scripts/xcode.sh --no-open --quiet`, which regenerates the project only if
# something XcodeGen reads has changed. An open Xcode picks the regenerated project up by itself.
#
# Hooks are never allowed to fail a git command: a missing xcodegen or a generation error is
# printed and the pull still completes. Existing hooks are kept; this adds one marked line to each.
set -euo pipefail

ios=${0:A:h:h}
repo=${ios:h}
hooks=$(git -C $repo rev-parse --git-path hooks)
[[ $hooks == /* ]] || hooks=$repo/$hooks
mkdir -p $hooks

marker='# enchiridion: keep the Xcode project in step (ios/scripts/install-hooks.sh)'
line='[ -x "$(git rev-parse --show-toplevel)/ios/scripts/xcode.sh" ] && "$(git rev-parse --show-toplevel)/ios/scripts/xcode.sh" --no-open --quiet || true'

install_hook() {
  local name=$1 guard=$2 file=$hooks/$1
  if [[ -f $file ]] && grep -qF -- $marker $file; then
    print "✓ $name already installed"
    return
  fi
  if [[ ! -f $file ]]; then
    print '#!/bin/sh' > $file
  fi
  {
    print ''
    print -- $marker
    if [[ -n $guard ]]; then
      print -- "$guard && { $line; }"
    else
      print -- $line
    fi
  } >> $file
  chmod +x $file
  print "✓ $name installed"
}

install_hook post-merge ''
install_hook post-rewrite ''
# post-checkout's third argument is 1 for a branch switch and 0 for a file checkout.
install_hook post-checkout '[ "$3" = "1" ]'

print "Done. The next pull regenerates the project if it needs it; run ios/scripts/xcode.sh to open it."
