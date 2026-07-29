// EditComments — a tiny menu-bar app that inserts Obsidian-style review comments
// via global hotkeys, keeping focus in the document the whole time.
//
//   Cmd+Shift+E  copy selection, then a category key -> ==selection==%%TAG[: ]%%
//   Cmd+Shift+G  general comment at the cursor      -> \n\n%%GENERAL: %%\n\n
//   Cmd+Shift+N  add a new category on the fly
//
// All hotkeys and categories live in ~/Library/Application Support/EditComments/categories.json
// Single file, compiled with swiftc (see build.sh). No Xcode project needed.

import Cocoa
import ServiceManagement

// MARK: - Config model

struct Category: Codable {
    var key: String        // single character, e.g. "d"
    var tag: String        // e.g. "DELETE"
    var needsText: Bool    // true -> leave cursor inside for inline typing
}

struct Hotkeys: Codable {
    var anchored: String
    var general: String
}

struct Config: Codable {
    var hotkeys: Hotkeys
    var generalTag: String
    var categories: [Category]

    static let fallback = Config(
        hotkeys: Hotkeys(anchored: "cmd+shift+e", general: "cmd+shift+g"),
        generalTag: "GENERAL",
        categories: [
            Category(key: "d", tag: "DELETE",  needsText: false),
            Category(key: "s", tag: "SHORTEN", needsText: false),
            Category(key: "f", tag: "FIX",     needsText: true),
            Category(key: "a", tag: "ADD",     needsText: true),
        ]
    )
}

// MARK: - Config storage

enum Store {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("EditComments", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("categories.json") }

    static func load() -> Config {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: file) else {
            save(.fallback)
            return .fallback
        }
        if let cfg = try? JSONDecoder().decode(Config.self, from: data) { return cfg }
        return .fallback
    }

    static func save(_ cfg: Config) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) { try? data.write(to: file) }
    }
}

// MARK: - Hotkey parsing

struct HotkeyCombo {
    var flags: CGEventFlags
    var keyCode: CGKeyCode

    // US-layout key codes for the characters we care about in hotkeys.
    static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "space": 49,
    ]

    static func parse(_ s: String) -> HotkeyCombo? {
        var flags: CGEventFlags = []
        var code: CGKeyCode?
        for raw in s.lowercased().split(separator: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "cmd", "command", "meta": flags.insert(.maskCommand)
            case "shift":                   flags.insert(.maskShift)
            case "ctrl", "control":         flags.insert(.maskControl)
            case "alt", "option", "opt":    flags.insert(.maskAlternate)
            default:                        code = codes[part]
            }
        }
        guard let c = code else { return nil }
        return HotkeyCombo(flags: flags, keyCode: c)
    }

    // Compare against a live event, ignoring irrelevant flag bits (caps lock, etc.).
    func matches(flags evFlags: CGEventFlags, keyCode evCode: CGKeyCode) -> Bool {
        let relevant: CGEventFlags = [.maskCommand, .maskShift, .maskControl, .maskAlternate]
        return evCode == keyCode && evFlags.intersection(relevant) == flags
    }
}

// MARK: - Synthetic keyboard output

enum Keyboard {
    static let cmdV: CGKeyCode = 9
    static let cmdC: CGKeyCode = 8
    static let left: CGKeyCode = 123

    static func post(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
        let src = CGEventSource(stateID: .combinedSessionState)
        if let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }
}

// MARK: - Pasteboard helpers

enum Clip {
    static var pb: NSPasteboard { .general }
    static func read() -> String? { pb.string(forType: .string) }
    static func write(_ s: String) { pb.clearContents(); pb.setString(s, forType: .string) }
}

// MARK: - HUD (non-activating cheat sheet)

final class HUD {
    private var panel: NSPanel?

    func show(_ categories: [Category]) {
        hide()
        var chips = categories.map { "\($0.key.uppercased())  \($0.tag.lowercased())" }
        chips.append("N  new")
        chips.append("esc  cancel")
        let text = chips.joined(separator: "     ")

        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 17, weight: .semibold)
        label.textColor = .black
        label.sizeToFit()

        let pad: CGFloat = 16
        let w = label.frame.width + pad * 2
        let h = label.frame.height + pad * 2

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                        styleMask: [.nonactivatingPanel, .borderless],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.ignoresMouseEvents = true
        p.hasShadow = true
        // Force a light panel so black text stays high-contrast even in Dark Mode.
        p.appearance = NSAppearance(named: .aqua)

        let bg = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        bg.wantsLayer = true
        bg.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.97).cgColor
        bg.layer?.cornerRadius = 12
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.black.withAlphaComponent(0.15).cgColor
        bg.layer?.masksToBounds = true
        label.frame = NSRect(x: pad, y: pad, width: label.frame.width, height: label.frame.height)
        bg.addSubview(label)
        p.contentView = bg

        if let screen = NSScreen.main {
            let sf = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: sf.midX - w / 2, y: sf.minY + 90))
        }
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}

// MARK: - Add-category window

final class AddCategoryWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let keyField = NSTextField(string: "")
    private let tagField = NSTextField(string: "")
    private let needsText = NSButton(checkboxWithTitle: "Needs inline text (leaves cursor inside)", target: nil, action: nil)
    private let error = NSTextField(labelWithString: "")
    var onSave: ((Category) -> Void)?

    func present() {
        if window != nil { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "New comment category"
        w.delegate = self
        w.isReleasedWhenClosed = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        stack.translatesAutoresizingMaskIntoConstraints = false

        keyField.placeholderString = "Trigger key (one letter, e.g. t)"
        tagField.placeholderString = "Tag label (e.g. TONE)"
        keyField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        tagField.widthAnchor.constraint(equalToConstant: 320).isActive = true
        error.textColor = .systemRed
        error.font = .systemFont(ofSize: 11)

        let save = NSButton(title: "Add", target: self, action: #selector(saveTapped))
        save.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancel, save])
        buttons.spacing = 10

        [makeLabel("Key:"), keyField, makeLabel("Tag:"), tagField, needsText, error, buttons]
            .forEach { stack.addArrangedSubview($0) }

        let content = NSView()
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        w.contentView = content
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(keyField)
    }

    private func makeLabel(_ s: String) -> NSTextField {
        let l = NSTextField(labelWithString: s)
        l.font = .boldSystemFont(ofSize: 12)
        return l
    }

    @objc private func saveTapped() {
        let key = keyField.stringValue.lowercased().trimmingCharacters(in: .whitespaces)
        let tag = tagField.stringValue.trimmingCharacters(in: .whitespaces)
        guard key.count == 1, let ch = key.first, ch.isLetter else {
            error.stringValue = "Key must be a single letter."; return
        }
        guard !tag.isEmpty else { error.stringValue = "Tag can't be empty."; return }
        if key == "n" { error.stringValue = "'n' is reserved (add-category shortcut in the HUD)."; return }
        onSave?(Category(key: key, tag: tag.uppercased(), needsText: needsText.state == .on))
        close()
    }

    @objc private func cancelTapped() { close() }

    private func close() {
        window?.orderOut(nil)
        window = nil
        keyField.stringValue = ""; tagField.stringValue = ""; needsText.state = .off
        error.stringValue = ""
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Controller

final class Controller {
    enum State { case idle, awaitingCategory }

    var config = Store.load()
    private var state: State = .idle
    private var capturedClip = ""
    private var savedClipboard: String?
    private let hud = HUD()
    private let queue = DispatchQueue(label: "co.tobias.editcomments.keys")

    private var anchored: HotkeyCombo? { HotkeyCombo.parse(config.hotkeys.anchored) }
    private var general: HotkeyCombo? { HotkeyCombo.parse(config.hotkeys.general) }

    private var tap: CFMachPort?

    // Returns true if the event should be swallowed.
    func handle(flags: CGEventFlags, keyCode: CGKeyCode, event: CGEvent) -> Bool {
        if state == .awaitingCategory {
            return handleCategoryKey(keyCode: keyCode, event: event)
        }
        if let a = anchored, a.matches(flags: flags, keyCode: keyCode) { beginAnchored(); return true }
        if let g = general, g.matches(flags: flags, keyCode: keyCode) { insertGeneral(); return true }
        return false
    }

    private func handleCategoryKey(keyCode: CGKeyCode, event: CGEvent) -> Bool {
        if keyCode == 53 { cancel(); return true } // esc
        let ch = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased()
        if ch == "n" { cancel(); showAddCategory(); return true }
        if let ch, let cat = config.categories.first(where: { $0.key == ch }) {
            apply(cat); return true
        }
        cancel(); return true // swallow anything else so no stray char lands
    }

    // Cmd+Shift+E: copy the selection, then wait for a category key.
    private func beginAnchored() {
        queue.async {
            usleep(80_000) // let the user's Cmd+Shift lift before we send Cmd+C
            self.savedClipboard = Clip.read()
            let before = Clip.pb.changeCount
            Keyboard.post(Keyboard.cmdC, [.maskCommand])
            var clip: String?
            for _ in 0..<50 {
                if Clip.pb.changeCount != before { clip = Clip.read(); break }
                usleep(10_000)
            }
            let text = (clip ?? "").trimmingCharacters(in: .newlines)
            DispatchQueue.main.async {
                guard !text.isEmpty else { NSSound.beep(); return }
                self.capturedClip = clip ?? ""
                self.state = .awaitingCategory
                self.hud.show(self.config.categories)
            }
        }
    }

    private func apply(_ cat: Category) {
        hud.hide()
        state = .idle
        let clip = capturedClip
        let insert = cat.needsText ? "==\(clip)==%%\(cat.tag): %%" : "==\(clip)==%%\(cat.tag)%%"
        paste(insert, moveLeft: cat.needsText ? 2 : 0, restoreTo: savedClipboard)
    }

    // Cmd+Shift+G: general comment at the cursor, cursor left inside.
    private func insertGeneral() {
        let saved = Clip.read()
        let insert = "\n\n%%\(config.generalTag): %%\n\n"
        // small delay to let Cmd+Shift lift before pasting
        queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.pasteNow(insert, moveLeft: 4, restoreTo: saved)
        }
    }

    private func paste(_ text: String, moveLeft: Int, restoreTo saved: String?) {
        queue.async { [weak self] in self?.pasteNow(text, moveLeft: moveLeft, restoreTo: saved) }
    }

    private func pasteNow(_ text: String, moveLeft: Int, restoreTo saved: String?) {
        Clip.write(text)
        usleep(40_000)
        Keyboard.post(Keyboard.cmdV, [.maskCommand])
        if moveLeft > 0 {
            usleep(130_000)
            for _ in 0..<moveLeft { Keyboard.post(Keyboard.left); usleep(8_000) }
        }
        usleep(150_000)
        if let saved { Clip.write(saved) }
    }

    private func cancel() {
        hud.hide()
        state = .idle
    }

    // MARK: add category

    private let addWindow = AddCategoryWindow()
    private func showAddCategory() {
        cancel()
        DispatchQueue.main.async {
            self.addWindow.onSave = { [weak self] cat in
                guard let self else { return }
                if let i = self.config.categories.firstIndex(where: { $0.key == cat.key }) {
                    self.config.categories[i] = cat
                } else {
                    self.config.categories.append(cat)
                }
                Store.save(self.config)
            }
            self.addWindow.present()
        }
    }

    func reload() { config = Store.load() }

    // MARK: event tap

    func startTap() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let ctrl = Unmanaged<Controller>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = ctrl.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            if ctrl.handle(flags: event.flags, keyCode: keyCode, event: event) {
                return nil // swallow
            }
            return Unmanaged.passUnretained(event)
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                          place: .headInsertEventTap,
                                          options: .defaultTap,
                                          eventsOfInterest: CGEventMask(mask),
                                          callback: callback,
                                          userInfo: refcon) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = Controller()
    var statusItem: NSStatusItem?
    private let addWin = AddCategoryWindow()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        ensureAccessibility()
        registerLoginItem()
        if !controller.startTap() {
            showAccessibilityAlert()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "✎"
        item.button?.toolTip = "EditComments"
        rebuildMenu(item)
        statusItem = item
    }

    private func rebuildMenu(_ item: NSStatusItem) {
        let menu = NSMenu()
        let hk = controller.config.hotkeys
        menu.addItem(withTitle: "Anchored comment:  \(pretty(hk.anchored))", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "General comment:   \(pretty(hk.general))", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Add category…", action: #selector(addCategory), keyEquivalent: "")

        let remove = NSMenuItem(title: "Remove category", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if controller.config.categories.isEmpty {
            let empty = NSMenuItem(title: "(none)", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            for cat in controller.config.categories {
                let mi = NSMenuItem(title: "\(cat.key.uppercased())  \(cat.tag)", action: #selector(removeCategory(_:)), keyEquivalent: "")
                mi.representedObject = cat.key
                mi.target = self
                sub.addItem(mi)
            }
        }
        remove.submenu = sub
        menu.addItem(remove)

        menu.addItem(withTitle: "Edit config file…", action: #selector(editConfig), keyEquivalent: "")
        menu.addItem(withTitle: "Reload config", action: #selector(reloadConfig), keyEquivalent: "")
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(login)
        menu.addItem(withTitle: "Open Accessibility settings", action: #selector(openAX), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit EditComments", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        item.menu = menu
    }

    private func pretty(_ s: String) -> String {
        s.split(separator: "+").map { part -> String in
            switch part.lowercased() {
            case "cmd", "command": return "⌘"
            case "shift": return "⇧"
            case "ctrl", "control": return "⌃"
            case "alt", "option", "opt": return "⌥"
            default: return part.uppercased()
            }
        }.joined()
    }

    @objc private func addCategory() {
        addWin.onSave = { [weak self] cat in
            guard let self else { return }
            var cfg = Store.load()
            if let i = cfg.categories.firstIndex(where: { $0.key == cat.key }) { cfg.categories[i] = cat }
            else { cfg.categories.append(cat) }
            Store.save(cfg)
            self.controller.reload()
            if let item = self.statusItem { self.rebuildMenu(item) }
        }
        addWin.present()
    }

    @objc private func removeCategory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        var cfg = Store.load()
        cfg.categories.removeAll { $0.key == key }
        Store.save(cfg)
        controller.reload()
        if let item = statusItem { rebuildMenu(item) }
    }

    @objc private func editConfig() {
        NSWorkspace.shared.open(Store.file)
    }

    @objc private func reloadConfig() {
        controller.reload()
        if let item = statusItem { rebuildMenu(item) }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        if let item = statusItem { rebuildMenu(item) }
    }

    @objc private func openAX() { openAccessibilityPane() }

    @objc private func quit() { NSApp.terminate(nil) }

    private func ensureAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    private func registerLoginItem() {
        if SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "EditComments needs Accessibility access"
        alert.informativeText = "Enable EditComments under System Settings ▸ Privacy & Security ▸ Accessibility, then quit and reopen the app."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn { openAccessibilityPane() }
    }

    private func openAccessibilityPane() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
