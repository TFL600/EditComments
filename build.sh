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

echo "▸ Launching…"
open "$APP"

cat <<EOF

✓ Built:  $APP

First run only:
  1. macOS will ask for Accessibility access (or the app will prompt).
     System Settings ▸ Privacy & Security ▸ Accessibility ▸ enable EditComments.
  2. Quit and reopen the app once after granting access.

Menu bar: click ✎ for hotkeys, add categories, "Open at Login", and quit.

Note: because this is ad-hoc signed, re-running build.sh can reset the
Accessibility grant. If hotkeys stop working after a rebuild, remove and
re-add EditComments in the Accessibility list.
EOF
