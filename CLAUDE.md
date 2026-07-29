# EditComments — working rules

Tiny Swift menu-bar app for marking up drafts with Obsidian-style review comments. Single source
file, `src/main.swift`, compiled by `build.sh`. No Xcode project. See [README.md](README.md) for what
the app does and how it is configured.

## After every rebuild: clear the Accessibility grant

The app is ad-hoc signed, so each rebuild changes its code hash and macOS silently invalidates the
existing Accessibility grant. The checkbox in System Settings still looks ticked, but the global
hotkeys are dead. This bites every single time, so:

- `build.sh` now runs `tccutil reset Accessibility co.tobias.editcomments` itself, after killing the
  old instance and before relaunching. Do not remove that step.
- If you rebuild by hand (calling `swiftc` directly rather than `build.sh`), **run the reset command
  yourself and tell Tobias to re-grant access.** Never hand back a rebuilt app without doing this or
  saying it out loud, or the hotkeys just stop working with no visible cause.
- After the reset, Tobias re-enables EditComments in System Settings ▸ Privacy & Security ▸
  Accessibility. No relaunch needed: the app polls and starts listening within ~2s. The menu-bar icon
  reads `✎!` while it lacks access and `✎` once it works.

## Conventions

- The comment convention (`==highlight==%%TAG: note%%` anchored, `%%TAG: note%%` general) is shared
  with the `edit` skill in the Agents-info-personal repo. Change one, check the other.
- Hotkeys and categories live in `~/Library/Application Support/EditComments/categories.json`, with
  `categories.default.json` as the shipped default. New config fields must be **optional** in the
  Swift `Codable` structs, so an older on-disk config still decodes instead of resetting to fallback
  and wiping Tobias's custom categories.
- Verify string-munging logic (e.g. `Strip.annotations`) by compiling that `enum` on its own with a
  few test cases before rebuilding the whole app.

## Git

Conventional commits, straight to `main`, always push. This is a OneDrive path, so after any
`git init` run `xattr -w com.apple.fileprovider.ignore#P 1 .git`.
