# EditComments

A tiny macOS menu-bar app for marking up drafts (Obsidian, or any text field) with review
comments, keyboard-only, without ever leaving the document. Replaces the old espanso `;co` / `;ge`
snippets and, unlike them, copies the selected text for you.

## Comment convention

| Hotkey | What it does | Result |
|---|---|---|
| **⇧⌘E** then a category key | Anchored comment on the selection | `==selection==%%TAG%%` (or `%%TAG: ▮%%`) |
| **⇧⌘G** | General comment at the cursor | `\n\n%%GENERAL: ▮%%\n\n` |
| **⇧⌘R** | Accept: strip every comment and highlight from the selection | `==text==%%EDITED%%` becomes `text` |

`▮` is where the cursor is left, so you keep typing straight into the document.

⇧⌘R is the other half of the loop: Claude's `edit` skill marks what it changed as
`==changed text==%%EDITED%%`, you read the highlights in Obsidian, then select a passage and hit ⇧⌘R
to accept everything in it. It removes `%%…%%` comments (any tag, including multi-line ones), unwraps
`==…==` highlights, and tidies the leftover whitespace. If the selection contains nothing to strip it
beeps and leaves the document alone.

Add or remove categories from the menu-bar ✎ menu (*Add category…* / *Remove category*), or press
`n` while the ⇧⌘E HUD is showing to add one on the spot.

### Default categories (press after ⇧⌘E)

| Key | Tag | Asks for text? |
|---|---|---|
| `d` | DELETE | no |
| `s` | SHORTEN | no |
| `f` | FIX | yes (cursor left inside) |
| `a` | ADD | yes (cursor left inside) |

A HUD strip shows the choices each time. `esc` cancels, `n` opens the add-category window.

## Build & install

```bash
bash build.sh
```

This compiles to `~/Applications/EditComments.app`, ad-hoc signs it, registers it to open at login,
and launches it.

### One-time setup
1. Grant **Accessibility** access when prompted (System Settings ▸ Privacy & Security ▸
   Accessibility ▸ enable EditComments). The global hotkeys need it.
2. Quit and reopen the app once after granting.

## Configuration

Everything lives in `~/Library/Application Support/EditComments/categories.json` — edit it directly
(menu ▸ *Edit config file…*) then *Reload config*, or use *Add category…*. Hotkeys are editable
there too (e.g. `"anchored": "cmd+shift+e"`).

## Notes & limits

- **Obsidian / plain-text only** for now. It pastes markdown (`==…==%%…%%`), so it works in any text
  field. Real Microsoft Word comment objects are a future addition.
- Because it is ad-hoc signed, re-running `build.sh` changes the app's signature, so macOS
  invalidates the Accessibility grant each rebuild. `build.sh` clears the stale entry for you
  (`tccutil reset Accessibility co.tobias.editcomments`), so you only have to re-enable EditComments
  in the Accessibility list. The app self-heals — it polls for the grant and starts listening within
  ~2s, no quit/reopen needed.
- The clipboard is saved and restored around each insertion (plain text).

## Uninstall

```bash
pkill -x EditComments
rm -rf ~/Applications/EditComments.app
rm -rf ~/Library/Application\ Support/EditComments
```
Then remove it from System Settings ▸ General ▸ Login Items, and from the Accessibility list.
