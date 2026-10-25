//
//  KeyboardShortcuts.swift
//  OreMonoCAD
//
//  Help › Keyboard Shortcuts…: an overview of all keys in one place.
//  Rebuilt every time – menu shortcuts are read straight from the main menu, tool letters
//  from Shortcuts (including custom ones from Settings), so the overview never goes stale.
//

import AppKit

final class KeyboardShortcutsWindowController: NSWindowController {
    private let textView = NSTextView()

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Keyboard Shortcuts"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 300)
        super.init(window: window)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 14)
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        window.contentView = scroll
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        textView.textStorage?.setAttributedString(KeyboardShortcutsWindowController.overview())
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Content

    /// A “key – what it does” row; the key sits in a fixed-width column.
    private struct Row {
        let key: String
        let action: String
    }

    private static func overview() -> NSAttributedString {
        var sections: [(String, [Row])] = []

        // tool letters (default and custom)
        var toolRows: [Row] = []
        for command in Shortcuts.commands {
            guard let key = Shortcuts.key(for: command) else { continue }
            toolRows.append(Row(key: key, action: command.title))
        }
        if Shortcuts.key(for: .select) == nil { toolRows.append(Row(key: "Space", action: DrawingTool.select.title)) }
        // Space first, then plain letters, then with ⇧, then with ⌥
        func rank(_ key: String) -> Int { return key == "Space" ? 0 : key.hasPrefix("⇧") ? 2 : key.hasPrefix("⌥") ? 3 : 1 }
        func letter(_ key: String) -> String { return key.hasPrefix("⇧") ? String(key.dropFirst()) + "⇧" : key }
        toolRows.sort { (rank($0.key), letter($0.key)) < (rank($1.key), letter($1.key)) }
        sections.append(("Tools (on the drawing area – change them in Settings › Shortcuts)", toolRows))

        sections.append(("While drawing", [
            Row(key: "↩", action: "Confirm / finish; with nothing in progress repeat the last tool"),
            Row(key: "Space", action: "Select when nothing is in progress (a second Space right after clears the selection); while drawing or typing a value it confirms like ↩"),
            Row(key: "Esc", action: "Cancel the current step; again = back to Select"),
            Row(key: "0–9 . -", action: "Start typing a value (length, radius, angle…)"),
            Row(key: "Tab", action: "Jump into the value box at the cursor"),
            Row(key: "⌫", action: "Remove the last point (Polyline, Spline, Wall, Leader, Revision Cloud, Wipeout, Area); in Select delete"),
            Row(key: "C", action: "Close (Polyline, Spline, Wall, Revision Cloud, Wipeout, continuous lines)"),
            Row(key: DrawingTool.line.shortcut ?? "–", action: "In the Line tool: continuous lines (LNC) on / off"),
            Row(key: "Letters", action: "Options of the current tool, shown in the bottom line (I / C / E, H / V / A / B, T, J…) – also with Shift held for Ortho; ⌥ + letter switches the tool"),
            Row(key: "Y / N", action: "Answer a question (Mirror, Close?)"),
            Row(key: "⇧ + letter", action: "Tool shortcut with Shift (e.g. ⇧P Polygon) – only with nothing in progress and nothing being typed; while drawing Shift stays Ortho (⇧Z works always)"),
            Row(key: "Shift (hold)", action: "Ortho while moving the mouse; a square in Rectangle, Wipeout and Revision Cloud; 15° steps in Rotate and Arc"),
            Row(key: "⌥ (tap)", action: "In Move, Rotate and while dragging a selection: switch to copying (the originals stay) and back"),
            Row(key: "x5  /5  ↩", action: "Right after placing a copy: five copies repeating the step (distance or angle) / five copies spread up to the placed one")
        ]))

        sections.append(("Drawing aids (always work)", [
            Row(key: "⌥3  F3", action: "Object snap"),
            Row(key: "⌥1  F11", action: "Snap tracking – hold the cursor on a snap point to line up with it (F11 only when macOS does not use it for Show Desktop)"),
            Row(key: "⌥4  F4", action: "Ask to close polylines and splines (CLS)"),
            Row(key: "⌥5  F5", action: "Show lineweights (LWT)"),
            Row(key: "⌥7  F6", action: "Continuous lines (LNC)"),
            Row(key: "⌥2  F7", action: "Show grid"),
            Row(key: "⌥8  F8", action: "Ortho (or hold Shift)"),
            Row(key: "⌥9  F9", action: "Snap to grid"),
            Row(key: "⌥0  F10", action: "Polar angles"),
            Row(key: "⌥6  F12", action: "Value box always visible")
        ]))

        sections.append(("Help and windows", [
            Row(key: "F1", action: "This overview (Help › Keyboard Shortcuts…)"),
            Row(key: "F2", action: "Info Panel"),
            Row(key: "⇧⌘]  ⇧⌘[", action: "Next / previous tab (also ⌃⇥ and ⌃⇧⇥)")
        ]))

        sections.append(("Mouse", [
            Row(key: "Right-click", action: "Confirm / finish; with nothing in progress end or repeat the tool"),
            Row(key: "Right button held", action: "Context menu in Select with nothing in progress (also Control-click)"),
            Row(key: "Middle drag", action: "Pan (also ⌘ + drag)"),
            Row(key: "Middle double-click", action: "Zoom Extents"),
            Row(key: "Wheel", action: "Zoom; Shift = fine, ⌥ = fast"),
            Row(key: "Double-click", action: "Edit a text or a block")
        ]))

        // shortcuts from the main menu, menu by menu
        if let mainMenu = NSApp.mainMenu {
            for top in mainMenu.items {
                guard let menu = top.submenu else { continue }
                var rows: [Row] = []
                collect(menu, path: [], into: &rows)
                if !rows.isEmpty { sections.append(("\(top.title) menu", rows)) }
            }
        }

        let result = NSMutableAttributedString()
        let heading: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 13)]
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: 150)]
        paragraph.headIndent = 150
        let keyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let actionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        for (index, section) in sections.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n", attributes: actionAttributes)) }
            result.append(NSAttributedString(string: section.0 + "\n", attributes: heading))
            for row in section.1 {
                result.append(NSAttributedString(string: row.key, attributes: keyAttributes))
                result.append(NSAttributedString(string: "\t" + row.action + "\n", attributes: actionAttributes))
            }
        }
        return result
    }

    /// Walks the menu (including submenus) and collects items that have a keyboard shortcut.
    private static func collect(_ menu: NSMenu, path: [String], into rows: inout [Row]) {
        for item in menu.items where !item.isSeparatorItem {
            if let submenu = item.submenu {
                collect(submenu, path: path + [item.title], into: &rows)
            } else if !item.keyEquivalent.isEmpty {
                let title = (path + [item.title]).joined(separator: " › ")
                rows.append(Row(key: describe(item), action: title))
            }
        }
    }

    /// A menu item's shortcut in the usual macOS notation (⌃⌥⇧⌘ + key).
    private static func describe(_ item: NSMenuItem) -> String {
        let mask = item.keyEquivalentModifierMask
        var text = ""
        if mask.contains(.control) { text += "⌃" }
        if mask.contains(.option) { text += "⌥" }
        var key = item.keyEquivalent
        // an uppercase letter in keyEquivalent means Shift
        if mask.contains(.shift) || (key.count == 1 && key != key.lowercased()) { text += "⇧" }
        if mask.contains(.command) { text += "⌘" }
        switch key {
        case "\u{8}", "\u{7f}": key = "⌫"
        case "\t": key = "⇥"
        case "\r": key = "↩"
        case " ": key = "Space"
        default: key = key.uppercased()
        }
        return text + key
    }
}
