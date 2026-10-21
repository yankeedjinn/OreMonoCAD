//
//  MenuRows.swift
//  OhMyCAD
//
//  Menu rows drawn by the app: icon, title and gray subtitle. Some macOS versions hide
//  the images of ordinary menu items in every menu; a row with its own view shows them always.
//

import AppKit

enum MenuRows {
    /// Replaces the ordinary items of a menu by rows drawn by the app (separators and submenus stay).
    /// Only menus with at least one image change.
    static func apply(to menu: NSMenu) {
        let items = menu.items.filter { !$0.isSeparatorItem && $0.submenu == nil && $0.view == nil }
        guard items.contains(where: { $0.image != nil }) else { return }
        let layout = MenuRowLayout(items: items)
        for item in items {
            item.view = MenuRowView(item: item, layout: layout)
        }
    }
}

/// Sizes shared by all rows of one menu, so the icons and texts line up.
struct MenuRowLayout {
    static let titleFont = NSFont.menuFont(ofSize: 0)
    static let subtitleFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    static let maxTextWidth: CGFloat = 300

    let iconWidth: CGFloat
    let textWidth: CGFloat
    let hasState: Bool

    let inset: CGFloat = 5          // the highlight keeps this far from the menu edge
    let checkWidth: CGFloat = 16
    let gap: CGFloat = 7
    let rightPadding: CGFloat = 14

    init(items: [NSMenuItem]) {
        iconWidth = max(16, items.compactMap { $0.image?.size.width }.max() ?? 16)
        hasState = items.contains { $0.state != .off }
        var widest: CGFloat = 0
        for item in items {
            widest = max(widest, Self.width(of: item.title, font: Self.titleFont))
            if let subtitle = item.subtitle { widest = max(widest, Self.width(of: subtitle, font: Self.subtitleFont)) }
        }
        textWidth = min(Self.maxTextWidth, ceil(widest))
    }

    var textX: CGFloat { return inset + 4 + (hasState ? checkWidth : 0) + iconWidth + gap }
    var rowWidth: CGFloat { return textX + textWidth + rightPadding + inset }

    static func width(of text: String, font: NSFont) -> CGFloat {
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// The subtitle wrapped to the text width.
    func subtitleHeight(_ subtitle: String) -> CGFloat {
        let rect = (subtitle as NSString).boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
                                                       options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                       attributes: [.font: Self.subtitleFont])
        return ceil(rect.height)
    }
}

/// One row of a menu: highlight, checkmark, icon, title and subtitle; a click runs the item's action.
final class MenuRowView: NSView {
    private weak var item: NSMenuItem?
    private let layout: MenuRowLayout
    private let titleHeight = ceil(MenuRowLayout.titleFont.ascender - MenuRowLayout.titleFont.descender
                                   + MenuRowLayout.titleFont.leading)
    private var subtitleHeight: CGFloat = 0
    private var tracking: NSTrackingArea?

    init(item: NSMenuItem, layout: MenuRowLayout) {
        self.item = item
        self.layout = layout
        if let subtitle = item.subtitle, !subtitle.isEmpty { subtitleHeight = layout.subtitleHeight(subtitle) }
        let textHeight = titleHeight + (subtitleHeight > 0 ? subtitleHeight + 1 : 0)
        let iconHeight = item.image?.size.height ?? 0
        let height = max(22, textHeight + 6, iconHeight + 4)
        super.init(frame: NSRect(x: 0, y: 0, width: layout.rowWidth, height: height))
        autoresizingMask = [.width]
        // a row with its own view does not show the item's tooltip by itself
        toolTip = item.toolTip
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { return true }

    /// Headers (no action) and disabled items are drawn gray and do not react.
    private var isActive: Bool {
        guard let item = item else { return false }
        return item.isEnabled && item.action != nil
    }

    private var isHighlighted: Bool {
        return isActive && (enclosingMenuItem?.isHighlighted ?? false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    // the menu changes the highlight itself; redraw when the mouse comes or goes
    override func mouseEntered(with event: NSEvent) { needsDisplay = true }
    override func mouseExited(with event: NSEvent) { needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        guard isActive, let item = item, let action = item.action else { return }
        item.menu?.cancelTracking()
        NSApp.sendAction(action, to: item.target, from: item)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item = item else { return }
        let highlighted = isHighlighted
        if highlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: layout.inset, dy: 0), xRadius: 5, yRadius: 5).fill()
        }
        let ink: NSColor = highlighted ? .alternateSelectedControlTextColor
            : isActive ? .labelColor : .tertiaryLabelColor
        let subInk: NSColor = highlighted ? NSColor.alternateSelectedControlTextColor.withAlphaComponent(0.85) : .secondaryLabelColor

        var x = layout.inset + 4
        if layout.hasState {
            if item.state == .on, let check = NSImage(named: NSImage.menuOnStateTemplateName) {
                let size = check.size
                draw(check, in: NSRect(x: x + (layout.checkWidth - size.width) / 2, y: (titleHeight - size.height) / 2 + 3,
                                       width: size.width, height: size.height), ink: ink)
            }
            x += layout.checkWidth
        }
        if let image = item.image {
            let size = image.size
            draw(image, in: NSRect(x: x + (layout.iconWidth - size.width) / 2, y: (bounds.height - size.height) / 2,
                                   width: size.width, height: size.height), ink: isActive ? ink : .tertiaryLabelColor)
        }

        let textTop = (bounds.height - titleHeight - (subtitleHeight > 0 ? subtitleHeight + 1 : 0)) / 2
        (item.title as NSString).draw(at: NSPoint(x: layout.textX, y: textTop),
                                      withAttributes: [.font: MenuRowLayout.titleFont, .foregroundColor: ink])
        if let subtitle = item.subtitle, subtitleHeight > 0 {
            (subtitle as NSString).draw(with: NSRect(x: layout.textX, y: textTop + titleHeight + 1,
                                                     width: layout.textWidth, height: subtitleHeight),
                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                        attributes: [.font: MenuRowLayout.subtitleFont, .foregroundColor: subInk])
        }
    }

    /// A template image takes the color of the text, any other one is drawn as it is.
    private func draw(_ image: NSImage, in rect: NSRect, ink: NSColor) {
        guard image.isTemplate else {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: isActive ? 1 : 0.4,
                       respectFlipped: true, hints: nil)
            return
        }
        // in a layer of its own, so the color covers only the icon and not the highlight under it
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.beginTransparencyLayer(in: rect, auxiliaryInfo: nil)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        ink.set()
        rect.fill(using: .sourceAtop)
        context.endTransparencyLayer()
        context.restoreGState()
    }
}
