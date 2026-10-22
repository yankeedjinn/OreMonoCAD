//
//  MenuRows.swift
//  OreMonoCAD
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

/// A menu item of a tool: when the mouse rests on its row, the tool's HOW TO USE shows next to the menu.
final class ToolMenuItem: NSMenuItem {
    var usage: String?
}

/// The menu of a tool button: its choices (arc methods, text kinds…) show the HOW TO USE of the tool.
final class ToolMenu: NSMenu {
    private var usages: [ObjectIdentifier: String] = [:]

    func setUsage(_ usage: String, for item: NSMenuItem) {
        usages[ObjectIdentifier(item)] = usage
    }

    func usage(for item: NSMenuItem) -> String? {
        return usages[ObjectIdentifier(item)]
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
    private var wasHighlighted = false

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

    /// The HOW TO USE of the row: its own (a tool item) or the one of the tool whose menu this is.
    private var usage: String? {
        guard let item = item else { return nil }
        return (item as? ToolMenuItem)?.usage ?? (item.menu as? ToolMenu)?.usage(for: item)
    }

    /// The menu redraws a row whenever its highlight changes (by mouse or by arrow keys),
    /// so the help is started and stopped from here.
    private func highlightChanged(_ highlighted: Bool) {
        guard highlighted != wasHighlighted else { return }
        wasHighlighted = highlighted
        // a row with a submenu gets none – the submenu opens where the help would cover it
        if highlighted, item?.hasSubmenu == false, let usage = usage {
            MenuUsageTip.shared.schedule(usage, for: self)
        } else if !highlighted {
            MenuUsageTip.shared.cancel(for: self)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard isActive, let item = item, let action = item.action else { return }
        MenuUsageTip.shared.cancel()
        item.menu?.cancelTracking()
        NSApp.sendAction(action, to: item.target, from: item)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let item = item else { return }
        let highlighted = isHighlighted
        highlightChanged(highlighted)
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

/// The HOW TO USE help of a menu row: after the mouse has rested on the row for a while,
/// it shows in a small window of its own next to the menu (like the help of the tool panel).
final class MenuUsageTip: NSObject {
    static let shared = MenuUsageTip()

    private let delay: TimeInterval = 3.0       // the same as the usage help of the tool panel
    private var timer: Timer?
    private weak var row: NSView?
    private var usage = ""
    private let tipView = MenuUsageTipView()
    private lazy var window: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)     // above the menu
        panel.contentView = tipView
        return panel
    }()

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(menuEnded(_:)),
                                               name: NSMenu.didEndTrackingNotification, object: nil)
    }

    func schedule(_ usage: String, for row: NSView) {
        cancel()
        self.usage = usage
        self.row = row
        let timer = Timer(timeInterval: delay, target: self, selector: #selector(show), userInfo: nil, repeats: false)
        // the open menu runs its own event loop – the timer has to fire in it too
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Hides the help; with a row only if the help belongs to that row (the mouse may already be on the next one).
    func cancel(for row: NSView? = nil) {
        if let row = row, row !== self.row { return }
        timer?.invalidate()
        timer = nil
        self.row = nil
        window.orderOut(nil)
    }

    @objc private func show() {
        timer = nil
        guard let row = row, let rowWindow = row.window else { return }
        tipView.configure(usage: usage)
        let size = tipView.frame.size
        let rowFrame = rowWindow.convertToScreen(row.convert(row.bounds, to: nil))
        let menuFrame = rowWindow.frame
        let screen = rowWindow.screen?.visibleFrame ?? menuFrame
        // right of the menu, top edge level with the row; left of it when there is no room on the right
        var x = menuFrame.maxX + 6
        if x + size.width > screen.maxX { x = menuFrame.minX - 6 - size.width }
        let y = min(max(rowFrame.maxY - size.height, screen.minY + 4), screen.maxY - size.height - 4)
        window.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        window.orderFrontRegardless()
    }

    @objc private func menuEnded(_ notification: Notification) {
        cancel()
    }
}

/// The help bubble: the caption HOW TO USE and the text, in the colors of the tool panel's help.
final class MenuUsageTipView: NSView {
    private let caption = NSTextField(labelWithString: "HOW TO USE")
    private let label = NSTextField(wrappingLabelWithString: "")
    private let width: CGFloat = 250
    private let padding: CGFloat = 10

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.tipBackground.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.popupBorder.cgColor
        caption.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        caption.textColor = Theme.accent
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = Theme.textLabel
        addSubview(caption)
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(usage: String) {
        label.stringValue = usage
        let inner = width - 2 * padding
        label.preferredMaxLayoutWidth = inner
        let usageHeight = ceil(label.sizeThatFits(NSSize(width: inner, height: .greatestFiniteMagnitude)).height)
        let captionHeight: CGFloat = 12
        let total = padding + captionHeight + 2 + usageHeight + padding
        setFrameSize(NSSize(width: width, height: total))
        caption.frame = NSRect(x: padding, y: total - padding - captionHeight, width: inner, height: captionHeight)
        label.frame = NSRect(x: padding, y: padding, width: inner, height: usageHeight)
    }
}
