#!/bin/bash
# Build EditComments.app into ~/Applications, ad-hoc sign it, and (re)launch.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$HOME/Applications/EditComments.app"
BIN="EditComments"

echo "▸ Compiling…"
mkdir -p "$HOME/Applications"

# Fresh bundle skeleton
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O "$SRC_DIR/src/main.swift" \
  -o "$APP/Contents/MacOS/$BIN" \
  -framework Cocoa -framework ServiceManagement

cp "$SRC_DIR/Info.plist" "$APP/Contents/Info.plist"
cp "$SRC_DIR/categories.default.json" "$APP/Contents/Resources/categories.default.json"

echo "▸ Ad-hoc signing…"
codesign --force --deep -s - "$APP"

# Stop any running instance so the new binary takes over.
pkill -x "$BIN" 2>/dev/null || true
sleep 0.3

# Every rebuild changes the code hash, so the old Accessibility grant is dead even though the
# checkbox still looks ticked. Clear it here so the app re-prompts instead of failing silently.
echo "▸ Clearing the stale Accessibility grant…"
tccutil reset Accessibility co.tobias.editcomments 2>/dev/null || true

echo "▸ Launching…"
open "$APP"

cat <<EOF

✓ Built:  $APP

IMPORTANT — every rebuild changes the app's code hash, so the old Accessibility
grant is dead (the checkbox still LOOKS enabled, but the app is untrusted).
This script has already cleared it with:

    tccutil reset Accessibility co.tobias.editcomments

so all you need to do is grant access again:
    System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable EditComments

No relaunch needed after granting: the app polls and starts listening within
~2s. The menu-bar icon shows "✎!" while it lacks access, "✎" once working.

Menu bar ✎: hotkeys, add/remove categories, "Open at Login", quit.
EOF
