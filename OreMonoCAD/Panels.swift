//
//  Panels.swift
//  OreMonoCAD
//
//  Tool panel, layer panel, properties panel and the status line.
//

import Cocoa

// MARK: - Toolbar

protocol ToolbarViewDelegate: AnyObject {
    func toolbarDidSelectTool(_ tool: DrawingTool)
    func toolbarDidSelectArcMethod(_ method: ArcMethod)
    func toolbarDidSelectHatchPattern(_ pattern: HatchPattern)
    func toolbarDidRequestCustomHatchPattern()
    func toolbarDidRequestHatchSettings()
    func toolbarDidRemoveCustomHatchPattern(_ name: String)
    /// The “scale” text for the menu (according to the editor state).
    func toolbarHatchSettingsSummary() -> (angle: CGFloat, scaleText: String)
    func toolbarDidSelectTextKind(_ kind: TextKind)
    func toolbarDidRequestTextStyle()
    func toolbarDidSelectMeasureKind(_ kind: MeasureKind)
    func toolbarDidSelectXLineKind(_ kind: XLineKind)
    func toolbarDidSelectArrayKind(_ kind: ArrayKind)
    /// Blocks for the Insert Block menu.
    func toolbarBlockDefinitions() -> [BlockDefinition]
    func toolbarCurrentBlock() -> BlockDefinition?
    func toolbarDidChooseBlock(_ definition: BlockDefinition)
    /// Terminator of new dimensions and the dimension style dialog.
    func toolbarDidSelectDimArrowStyle(_ style: DimArrowStyle)
    func toolbarDidRequestDimensionStyle()
    /// What Match Properties transfers has changed.
    func toolbarDidChangeMatchProperties()
    /// Polygon: input method and number of sides.
    func toolbarPolygonSettings() -> (method: PolygonMethod, sides: Int)
    func toolbarDidSelectPolygonMethod(_ method: PolygonMethod)
    func toolbarDidRequestPolygonSides()
}

/// A part of the tool panel: the user's favorite tools or one tool group.
enum ToolPanelSection: Hashable {
    case favorites
    case group(ToolGroup)

    /// Also the name under which the layout is saved (a title survives adding a new group).
    var title: String {
        switch self {
        case .favorites: return "Favorites"
        case .group(let group): return group.title
        }
    }

    init?(title: String) {
        if title == "Favorites" { self = .favorites; return }
        // layouts saved before Insert was split into Block and Reference
        if title == "Insert" { self = .group(.block); return }
        guard let group = ToolGroup.allCases.first(where: { $0.title == title }) else { return nil }
        self = .group(group)
    }

    static var all: [ToolPanelSection] {
        return [.favorites] + ToolGroup.allCases.map { .group($0) }
    }
}

/// How the user arranged the tool panel: order of the sections, hidden sections and favorite tools.
/// Kept in the app's settings on this Mac (not in the drawing).
enum ToolPanelLayout {
    private static let orderKey = "ToolPanelOrder"
    private static let hiddenKey = "ToolPanelHidden"
    private static let favoritesKey = "ToolPanelFavorites"

    /// All sections in the user's order; a section the saved order doesn't know yet keeps its default place.
    static var order: [ToolPanelSection] {
        get {
            var result: [ToolPanelSection] = []
            for title in UserDefaults.standard.stringArray(forKey: orderKey) ?? [] {
                if let section = ToolPanelSection(title: title), !result.contains(section) { result.append(section) }
            }
            for (index, section) in ToolPanelSection.all.enumerated() where !result.contains(section) {
                result.insert(section, at: min(index, result.count))
            }
            return result
        }
        set { UserDefaults.standard.set(newValue.map { $0.title }, forKey: orderKey) }
    }

    static var hidden: Set<ToolPanelSection> {
        get { return Set((UserDefaults.standard.stringArray(forKey: hiddenKey) ?? []).compactMap { ToolPanelSection(title: $0) }) }
        set { UserDefaults.standard.set(newValue.map { $0.title }.sorted(), forKey: hiddenKey) }
    }

    /// Favorite tools in the user's order (a combined button is saved as its first tool).
    static var favorites: [DrawingTool] {
        get {
            var result: [DrawingTool] = []
            for title in UserDefaults.standard.stringArray(forKey: favoritesKey) ?? [] {
                // a tool that is no longer first of its combined button stands for that button
                if let tool = DrawingTool.availableTools.first(where: { $0.title == title })?.paletteLeader,
                   !result.contains(tool) {
                    result.append(tool)
                }
            }
            return result
        }
        set { UserDefaults.standard.set(newValue.map { $0.title }, forKey: favoritesKey) }
    }

    /// Back to the default order with all sections shown; the favorites stay.
    static func resetLayout() {
        UserDefaults.standard.removeObject(forKey: orderKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }
}

/// Dragging a section heading, a tool button or a floating palette.
enum ToolDragPhase {
    case moved, ended
}

/// The picture of a dragged tool that follows the mouse across the whole window.
final class ToolDragGhost {
    static let shared = ToolDragGhost()
    private let view = NSView()
    private let imageView = NSImageView()
    private let size = NSSize(width: 34, height: 32)

    private init() {
        view.frame.size = size
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.toolbarBackground.cgColor
        view.layer?.cornerRadius = 6
        view.layer?.borderWidth = 1
        view.alphaValue = 0.9
        imageView.frame = NSRect(origin: .zero, size: size).insetBy(dx: 6, dy: 5)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        view.addSubview(imageView)
    }

    /// Shows the icon centered on the mouse of the event.
    func show(_ icon: NSImage?, for event: NSEvent) {
        guard let content = event.window?.contentView else { return }
        if view.superview !== content {
            view.layer?.borderColor = Theme.accent.cgColor
            imageView.image = icon.flatMap { ToolIcons.colored($0, selected: false) } ?? icon
            content.addSubview(view, positioned: .above, relativeTo: nil)
        }
        let point = content.convert(event.locationInWindow, from: nil)
        view.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2))
    }

    func hide() {
        view.removeFromSuperview()
    }
}

/// The picture of a whole group dragged out of the tool panel by its heading: the group as it looks in the panel,
/// in an accent outline – the palette it will become. It follows the mouse, held by its heading.
final class GroupDragGhost {
    static let shared = GroupDragGhost()
    private let imageView = NSImageView()
    var isShown: Bool { return imageView.superview != nil }

    private init() {
        imageView.wantsLayer = true
        imageView.imageScaling = .scaleNone
        imageView.layer?.cornerRadius = 8
        imageView.layer?.borderWidth = 2
        imageView.alphaValue = 0.85
    }

    /// Shows the picture with its heading under the mouse of the event (the picture is taken once per drag).
    func show(_ image: @autoclosure () -> NSImage?, for event: NSEvent) {
        guard let content = event.window?.contentView else { return }
        if imageView.superview !== content {
            let picture = image()
            imageView.image = picture
            imageView.frame.size = picture?.size ?? NSSize(width: 80, height: 60)
            imageView.layer?.backgroundColor = Theme.toolbarBackground.cgColor
            imageView.layer?.borderColor = Theme.accent.cgColor
            content.addSubview(imageView, positioned: .above, relativeTo: nil)
        }
        let point = content.convert(event.locationInWindow, from: nil)
        imageView.setFrameOrigin(NSPoint(x: point.x - imageView.frame.width / 2, y: point.y - imageView.frame.height + 8))
    }

    func hide() {
        imageView.removeFromSuperview()
    }
}

/// Vertical tool panel on the left – icons in 1 to 4 columns, by section (Favorites and the tool groups).
/// Holding (or right-clicking) the Arc tool opens a menu of arc construction methods.
/// A section is moved by dragging its heading and hidden from the heading's menu;
/// a tool is added to Favorites from its right-click menu.
final class ToolbarView: NSView, NSMenuDelegate {
    weak var delegate: ToolbarViewDelegate?
    /// Buttons of each tool – a favorite tool has two (in Favorites and in its group).
    private var buttons: [DrawingTool: [ToolButtonView]] = [:]
    /// Combined buttons: which tool of the family the button currently stands for (key = the family's first tool).
    private var familyChoice: [DrawingTool: DrawingTool] = [:]
    /// Icons set from outside (arc method, text kind, …) – they survive rebuilding the panel.
    private var customIcons: [DrawingTool: NSImage] = [:]
    /// Buttons on the floating palettes – a palette owns them, the panel only keeps them up to date.
    private var paletteButtons: [DrawingTool: NSHashTable<ToolButtonView>] = [:]
    /// Combined buttons on the floating palettes (key = the family's first tool), kept up to date like the panel's.
    private var combinedPaletteButtons: [DrawingTool: NSHashTable<ToolButtonView>] = [:]
    private var selectedTool: DrawingTool = .select
    private(set) var arcMethod: ArcMethod = .threePoint
    /// Tools (one button or a whole group) dragged out of the panel and released elsewhere in the window
    /// (point in window coordinates).
    var onToolsDroppedOutside: (([DrawingTool], NSPoint) -> Void)?
    /// A whole section dragged out of the panel by its heading and released elsewhere in the window.
    var onSectionDroppedOutside: ((ToolPanelSection, [DrawingTool], NSPoint) -> Void)?
    /// Reset Tool Panel and Palettes was chosen – the window resets the panel and the palettes together.
    var onLayoutReset: (() -> Void)?
    /// A section was shown in the panel again from its menu – it leaves the palette holding it.
    var onSectionShown: ((ToolPanelSection) -> Void)?
    /// No section is shown in the panel (all hidden or moved to palettes) – the window hides the panel.
    private(set) var isEmpty = false
    /// The width the panel wants: one column of groups, more when they don't fit and columns are added.
    private(set) var panelWidth: CGFloat = ToolbarView.columnWidth
    /// The panel became empty, got a section again or changed its width – the window lays itself out again.
    var onShapeChanged: (() -> Void)?

    /// When the groups don't fit the panel's height: true = they go on in another column (the panel gets wider),
    /// false = the panel scrolls (kept in the app's settings).
    static var addsColumns: Bool {
        get { return UserDefaults.standard.bool(forKey: "ToolPanelAddsColumns") }
        set { UserDefaults.standard.set(newValue, forKey: "ToolPanelAddsColumns") }
    }

    static let preferredWidth: CGFloat = 80

    /// Icons in a row of the panel, 1 to 4 – set by dragging the panel's inner edge (kept in the app's settings).
    static var iconsPerRow: Int {
        get {
            let saved = UserDefaults.standard.integer(forKey: "ToolPanelIconsPerRow")
            return saved == 0 ? 2 : min(4, max(1, saved))
        }
        set { UserDefaults.standard.set(min(4, max(1, newValue)), forKey: "ToolPanelIconsPerRow") }
    }

    /// Width of one column of groups for the current number of icons in a row (80 for two icons).
    static var columnWidth: CGFloat {
        let icons = CGFloat(iconsPerRow)
        return icons * 34 + (icons - 1) * 4 + 8
    }
    private let buttonSize = NSSize(width: 34, height: 32)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { return true }   // laid out from top to bottom

    /// Panel content in a scroll view – on a small screen the panel can be scrolled with the wheel.
    private let scroll = OverlayScrollView()
    private let content = FlippedToolbarContent()

    /// Always keeps the thin overlay scroller. With a mouse connected macOS switches scroll views
    /// to a wide, always visible scroller (and switches them back on its own whenever the setting
    /// changes), which would cover the right column of icons and cut off the group captions.
    private final class OverlayScrollView: NSScrollView {
        override var scrollerStyle: NSScroller.Style {
            get { super.scrollerStyle }
            set { super.scrollerStyle = .overlay }
        }
    }

    private final class FlippedToolbarContent: NSView {
        var menuProvider: (() -> NSMenu?)?
        override var isFlipped: Bool { return true }
        // right-click on an empty place of the panel: which sections to show
        override func menu(for event: NSEvent) -> NSMenu? { return menuProvider?().map(withRows) }
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = Theme.toolbarBackground.cgColor
        scroll.frame = bounds
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.horizontalScrollElasticity = .none
        content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        content.menuProvider = { [weak self] in self?.makeLayoutMenu() }
        scroll.documentView = content
        addSubview(scroll)
        rebuild()
    }

    /// Where each shown section lies (its column's left edge, heading top to the end of its buttons) –
    /// for dragging a heading.
    private var sectionSpans: [(section: ToolPanelSection, left: CGFloat, top: CGFloat, bottom: CGFloat)] = []
    /// Top of the Favorites buttons (nil = Favorites not shown) and the left edge of their column –
    /// for dragging a favorite.
    private var favoritesTop: CGFloat?
    private var favoritesLeft: CGFloat = 0
    /// Line showing where a dragged section will land.
    private let dropMarker = NSBox()

    /// The buttons' left edge inside a column of the panel.
    private var buttonsLeft: CGFloat {
        let icons = CGFloat(ToolbarView.iconsPerRow)
        return (ToolbarView.columnWidth - icons * buttonSize.width - (icons - 1) * 4) / 2
    }

    // in the column mode a new height can need another number of columns
    override func setFrameSize(_ newSize: NSSize) {
        let heightChanged = newSize.height != frame.height
        super.setFrameSize(newSize)
        // while the window is resized: laid out again only when a group moves to another column
        if heightChanged && ToolbarView.addsColumns && columnBreaks(height: bounds.height) != builtColumnBreaks { rebuild() }
    }

    /// The sections that started a new column in the last layout.
    private var builtColumnBreaks: [Int] = []

    /// The sections (by their place among the shown ones) that start a new column at this height – as `rebuild` lays them out.
    private func columnBreaks(height: CGFloat) -> [Int] {
        let icons = ToolbarView.iconsPerRow
        var y: CGFloat = 8
        var result: [Int] = []
        for (index, section) in visibleSections.enumerated() {
            let sectionHeight = 14 + CGFloat((tools(in: section).count + icons - 1) / icons) * (buttonSize.height + 2) + 8
            if y > 8 {
                if y + 4 + sectionHeight > height {
                    result.append(index)
                    y = 8
                } else {
                    y += 4
                }
            }
            y += sectionHeight
        }
        return result
    }

    /// Sections shown on the panel, in the user's order (an empty Favorites is not shown).
    private var visibleSections: [ToolPanelSection] {
        let hidden = ToolPanelLayout.hidden
        return ToolPanelLayout.order.filter { !hidden.contains($0) && !tools(in: $0).isEmpty }
    }

    private func tools(in section: ToolPanelSection) -> [DrawingTool] {
        switch section {
        case .favorites: return ToolPanelLayout.favorites
        // only one button for combined tools, none for tools offered in another button's menu
        case .group(let group): return DrawingTool.tools(in: group).filter { $0.paletteLeader == $0 && !Self.menuOnlyTools.contains($0) }
        }
    }

    /// Lays the panel out again from the saved layout (order, hidden sections, favorites).
    private func rebuild() {
        hideTip()
        builtColumnBreaks = ToolbarView.addsColumns ? columnBreaks(height: bounds.height) : []
        content.subviews.forEach { $0.removeFromSuperview() }
        buttons = [:]
        sectionSpans = []
        favoritesTop = nil
        let columnWidth = ToolbarView.columnWidth
        let icons = ToolbarView.iconsPerRow
        var y: CGFloat = 8, left: CGFloat = 0, contentHeight: CGFloat = 0
        let sections = visibleSections
        for section in sections {
            let sectionTools = tools(in: section)
            let sectionHeight = 14 + CGFloat((sectionTools.count + icons - 1) / icons) * (buttonSize.height + 2) + 8
            if y > 8 {
                // the group doesn't fit the column: it starts the next one (in the column mode)
                if ToolbarView.addsColumns && y + 4 + sectionHeight > bounds.height {
                    contentHeight = max(contentHeight, y)
                    left += columnWidth
                    y = 8
                } else {
                    // separator between groups of one column
                    let separator = NSBox(frame: NSRect(x: left + 10, y: y - 4, width: columnWidth - 20, height: 1))
                    separator.boxType = .separator
                    content.addSubview(separator)
                    y += 4
                }
            }
            let top = y
            let caption = ToolSectionCaptionView(frame: NSRect(x: left, y: y, width: columnWidth, height: 13), title: section.title)
            caption.toolTip = "Drag to move this group, right-click to hide it"
            caption.onDrag = { [weak self] phase, event in self?.sectionDragged(section, phase: phase, event: event) }
            caption.menuProvider = { [weak self] in self?.makeSectionMenu(section) }
            content.addSubview(caption)
            y += 14

            if section == .favorites {
                favoritesTop = y
                favoritesLeft = left
            }
            for (index, tool) in sectionTools.enumerated() {
                let column = CGFloat(index % icons)
                let row = CGFloat(index / icons)
                let button = makeButton(tool, frame: NSRect(x: left + buttonsLeft + column * (buttonSize.width + 4),
                                                            y: y + row * (buttonSize.height + 2),
                                                            width: buttonSize.width, height: buttonSize.height))
                let inFavorites = section == .favorites
                button.onDrag = { [weak self] phase, event in
                    self?.buttonDragged(tool, fromFavorites: inFavorites, phase: phase, event: event)
                }
                content.addSubview(button)
                buttons[tool, default: []].append(button)
            }
            y += CGFloat((sectionTools.count + icons - 1) / icons) * (buttonSize.height + 2) + 8
            sectionSpans.append((section, left, top, y))
        }
        contentHeight = max(contentHeight, y)
        dropMarker.boxType = .custom
        dropMarker.borderWidth = 0
        dropMarker.fillColor = Theme.accent
        dropMarker.isHidden = true
        content.addSubview(dropMarker)
        content.frame.size = NSSize(width: left + columnWidth, height: contentHeight + 4)
        if sections.isEmpty != isEmpty || left + columnWidth != panelWidth {
            isEmpty = sections.isEmpty
            panelWidth = left + columnWidth
            onShapeChanged?()
        }
        let leader = selectedTool.paletteLeader
        for (key, list) in buttons { list.forEach { $0.isSelected = key == leader } }
    }

    /// Rebuilds after the current event (a menu or a drag) has finished with the old buttons.
    private func scheduleRebuild() {
        DispatchQueue.main.async { [weak self] in self?.rebuild() }
    }

    /// Lays the panel out again after the saved layout changed elsewhere (a section moved to or from a palette).
    func reloadLayout() {
        scheduleRebuild()
    }

    /// fixed = a palette button that always stands for this one tool, also a tool of a combined button
    /// (so Circle and Ellipse can lie side by side).
    private func makeButton(_ tool: DrawingTool, frame: NSRect, fixed: Bool = false) -> ToolButtonView {
        let combined = !fixed && tool.paletteFamily != nil
        if combined, familyChoice[tool] == nil { familyChoice[tool] = tool }
        let button = ToolButtonView(frame: frame)
        button.image = fixed ? fixedIcon(for: tool) : icon(for: tool)
        // the tool the button stands for now (a combined button: the last chosen one of its family)
        let current: () -> DrawingTool = { [weak self] in combined ? (self?.familyChoice[tool] ?? tool) : tool }
        // hover help: summary immediately, usage after 3 s (instead of a plain tooltip)
        button.onHover = { [weak self, weak button] hovering in
            guard let self = self, let button = button else { return }
            self.hoverChanged(tool: current(), button: button, combined: combined, hovering: hovering)
        }
        button.onClick = { [weak self] in
            guard let self = self else { return }
            self.hideTip()
            self.delegate?.toolbarDidSelectTool(current())
        }
        // holding opens the tool's own menu; right-click opens it too, with Add to / Remove from Favorites
        button.hasMenu = combined || Self.toolsWithMenu.contains(tool)
        // Insert Block has nothing to choose until the drawing has a block
        if tool == .blockInsert && !combined {
            button.menuCondition = { [weak self] in !(self?.delegate?.toolbarBlockDefinitions().isEmpty ?? true) }
        }
        button.menuProvider = { [weak self] in self?.makeButtonMenu(tool, combined: combined) }
        return button
    }

    /// The icon a tool's button shows now (the chosen tool of a combined button, the arc method, …).
    private func icon(for tool: DrawingTool) -> NSImage? {
        return customIcons[tool] ?? (familyChoice[tool] ?? tool).icon()
    }

    /// The icon of a palette button that always stands for this one tool.
    private func fixedIcon(for tool: DrawingTool) -> NSImage? {
        return customIcons[tool] ?? tool.icon()
    }

    /// A button for a floating palette – the same as in the panel, kept up to date by the panel.
    /// combined = it offers the tool's whole family like the panel button (a group moved to a palette),
    /// otherwise it always stands for this one tool.
    func makePaletteButton(_ tool: DrawingTool, combined: Bool = false) -> ToolButtonView {
        let button = makeButton(tool, frame: NSRect(origin: .zero, size: buttonSize), fixed: !combined)
        if combined {
            button.isSelected = tool == selectedTool.paletteLeader
            let table = combinedPaletteButtons[tool] ?? .weakObjects()
            table.add(button)
            combinedPaletteButtons[tool] = table
        } else {
            button.isSelected = tool == selectedTool
            let table = paletteButtons[tool] ?? .weakObjects()
            table.add(button)
            paletteButtons[tool] = table
        }
        return button
    }

    /// Sets the icon on all buttons of a tool (in the panel and on the floating palettes).
    private func setIcon(_ image: NSImage?, for tool: DrawingTool) {
        customIcons[tool] = image
        buttons[tool]?.forEach { $0.image = icon(for: tool) }
        paletteButtons[tool]?.allObjects.forEach { $0.image = fixedIcon(for: tool) }
        combinedPaletteButtons[tool]?.allObjects.forEach { $0.image = icon(for: tool) }
    }

    func setSelectedTool(_ tool: DrawingTool) {
        selectedTool = tool
        let leader = tool.paletteLeader
        // a combined button takes over the icon of the chosen tool
        if tool.paletteFamily != nil, familyChoice[leader] != tool {
            familyChoice[leader] = tool
            buttons[leader]?.forEach { $0.image = icon(for: leader) }
            combinedPaletteButtons[leader]?.allObjects.forEach { $0.image = icon(for: leader) }
        }
        for (key, list) in buttons { list.forEach { $0.isSelected = key == leader } }
        for (key, table) in combinedPaletteButtons { table.allObjects.forEach { $0.isSelected = key == leader } }
        // a single-tool palette button stands for exactly one tool
        for (key, table) in paletteButtons { table.allObjects.forEach { $0.isSelected = key == tool } }
    }

    // MARK: Favorites and the panel layout

    /// Tools (besides combined buttons) that have their own menu.
    private static let toolsWithMenu: Set<DrawingTool> = [.arc, .hatch, .text, .xline, .matchProperties, .measure, .array, .blockInsert]

    /// Tools without a button of their own in the panel – they are in the menu of Hatch.
    private static let menuOnlyTools: Set<DrawingTool> = [.hatchRebuild, .hatchCut]

    private func toolMenu(_ tool: DrawingTool) -> NSMenu? {
        if tool.paletteFamily != nil { return makeFamilyMenu(tool) }
        let menu: NSMenu?
        switch tool {
        case .arc: menu = makeArcMenu()
        case .hatch: menu = makeHatchMenu()
        case .text: menu = makeTextMenu()
        case .xline: menu = makeXLineMenu()
        case .matchProperties: menu = makeMatchMenu()
        case .measure: menu = makeMeasureMenu()
        case .array: menu = makeArrayMenu()
        case .blockInsert: menu = makeBlockMenu()
        default: menu = nil
        }
        // the choices of the tool show its HOW TO USE (the “…” settings items do not)
        if let menu = menu as? ToolMenu {
            for item in menu.items where !item.title.hasSuffix("…") { menu.setUsage(tool.usage, for: item) }
        }
        return menu
    }

    /// The tool's own menu (if it has one) followed by Add to / Remove from Favorites.
    /// A palette button of one tool of a combined button has no family menu and no favorites item.
    private func makeButtonMenu(_ tool: DrawingTool, combined: Bool) -> NSMenu {
        let own = combined || tool.paletteFamily == nil ? toolMenu(tool) : nil
        let menu = own ?? NSMenu(title: tool.title)
        guard tool.paletteLeader == tool else { return menu }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        let isFavorite = ToolPanelLayout.favorites.contains(tool)
        let item = NSMenuItem(title: isFavorite ? "Remove from Favorites" : "Add to Favorites",
                              action: #selector(favoriteToggled(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tool.rawValue
        item.image = NSImage(systemSymbolName: isFavorite ? "star.slash" : "star", accessibilityDescription: nil)
        menu.addItem(item)
        return menu
    }

    @objc private func favoriteToggled(_ sender: NSMenuItem) {
        guard let tool = DrawingTool(rawValue: sender.tag) else { return }
        var favorites = ToolPanelLayout.favorites
        if let index = favorites.firstIndex(of: tool) { favorites.remove(at: index) } else { favorites.append(tool) }
        ToolPanelLayout.favorites = favorites
        scheduleRebuild()
    }

    /// A dragged tool button: released on the drawing it goes to a floating palette (the tool the button
    /// shows now), a favorite released inside Favorites takes the place under the mouse.
    private func buttonDragged(_ tool: DrawingTool, fromFavorites: Bool, phase: ToolDragPhase, event: NSEvent) {
        let shown = familyChoice[tool] ?? tool
        switch phase {
        case .moved:
            ToolDragGhost.shared.show(icon(for: tool), for: event)
        case .ended:
            ToolDragGhost.shared.hide()
            if !bounds.contains(convert(event.locationInWindow, from: nil)) {
                onToolsDroppedOutside?([shown], event.locationInWindow)
            } else if fromFavorites {
                moveFavorite(tool, to: content.convert(event.locationInWindow, from: nil))
            }
        }
    }

    /// A favorite released inside the panel takes the place under the mouse.
    private func moveFavorite(_ tool: DrawingTool, to point: NSPoint) {
        guard let top = favoritesTop else { return }
        let icons = ToolbarView.iconsPerRow
        let column = max(0, min(icons - 1, Int((point.x - favoritesLeft - buttonsLeft + 2) / (buttonSize.width + 4))))
        let row = max(0, Int(((point.y - top) / (buttonSize.height + 2)).rounded(.down)))
        var favorites = ToolPanelLayout.favorites
        guard let from = favorites.firstIndex(of: tool) else { return }
        favorites.remove(at: from)
        favorites.insert(tool, at: min(row * icons + column, favorites.count))
        ToolPanelLayout.favorites = favorites
        scheduleRebuild()
    }

    /// A dragged heading: inside the panel a line shows where the section will land and on release it moves there;
    /// released on the drawing the whole section becomes a floating palette.
    private func sectionDragged(_ section: ToolPanelSection, phase: ToolDragPhase, event: NSEvent) {
        let outside = !bounds.contains(convert(event.locationInWindow, from: nil))
        let shownTools = tools(in: section).map { familyChoice[$0] ?? $0 }
        let point = content.convert(event.locationInWindow, from: nil)
        let y = point.y
        // the place in front of the first section whose middle lies below the mouse in its column
        // (or that starts a column further right)
        let columnLeft = (point.x / ToolbarView.columnWidth).rounded(.down) * ToolbarView.columnWidth
        let index = sectionSpans.firstIndex { $0.left > columnLeft || ($0.left == columnLeft && ($0.top + $0.bottom) / 2 > y) }
            ?? sectionSpans.count
        switch phase {
        case .moved where outside:
            dropMarker.isHidden = true
            GroupDragGhost.shared.show(self.picture(of: section), for: event)
        case .moved:
            GroupDragGhost.shared.hide()
            let markerY = index < sectionSpans.count ? sectionSpans[index].top - 5 : (sectionSpans.last?.bottom ?? 0) - 2
            let markerX = index < sectionSpans.count ? sectionSpans[index].left : (sectionSpans.last?.left ?? 0)
            dropMarker.frame = NSRect(x: markerX + 6, y: markerY, width: ToolbarView.columnWidth - 12, height: 2)
            dropMarker.isHidden = false
        case .ended:
            dropMarker.isHidden = true
            GroupDragGhost.shared.hide()
            if outside {
                onSectionDroppedOutside?(section, shownTools, event.locationInWindow)
            } else {
                move(section, toVisibleIndex: index)
            }
        }
    }

    /// The section as it looks in the panel (its heading and buttons) – the picture of a dragged group.
    private func picture(of section: ToolPanelSection) -> NSImage? {
        guard let span = sectionSpans.first(where: { $0.section == section }) else { return nil }
        let rect = NSRect(x: span.left, y: span.top - 3, width: ToolbarView.columnWidth, height: span.bottom - span.top - 2)
        guard let rep = content.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
        content.cacheDisplay(in: rect, to: rep)
        let image = NSImage(size: rect.size)
        image.addRepresentation(rep)
        return image
    }

    /// Moves a section in front of the shown section at the index (index = count: to the end).
    private func move(_ section: ToolPanelSection, toVisibleIndex index: Int) {
        var visible = visibleSections
        guard let from = visible.firstIndex(of: section) else { return }
        visible.remove(at: from)
        let target = index > from ? index - 1 : index
        var order = ToolPanelLayout.order
        order.removeAll { $0 == section }
        // hidden sections keep their place among the shown ones
        if target < visible.count, let anchor = order.firstIndex(of: visible[target]) {
            order.insert(section, at: anchor)
        } else if let last = visible.last, let anchor = order.firstIndex(of: last) {
            order.insert(section, at: anchor + 1)
        } else {
            order.append(section)
        }
        ToolPanelLayout.order = order
        scheduleRebuild()
    }

    /// Menu of a section heading: hide or move the section, which sections to show.
    private func makeSectionMenu(_ section: ToolPanelSection) -> NSMenu {
        let menu = NSMenu(title: section.title)
        let hide = NSMenuItem(title: "Hide \(section.title)", action: #selector(sectionVisibilityToggled(_:)), keyEquivalent: "")
        hide.target = self
        hide.representedObject = section.title
        hide.image = NSImage(systemSymbolName: "eye.slash", accessibilityDescription: nil)
        menu.addItem(hide)
        let index = visibleSections.firstIndex(of: section) ?? 0
        let up = NSMenuItem(title: "Move Up", action: index > 0 ? #selector(sectionMovedUp(_:)) : nil, keyEquivalent: "")
        let down = NSMenuItem(title: "Move Down", action: index < visibleSections.count - 1 ? #selector(sectionMovedDown(_:)) : nil,
                              keyEquivalent: "")
        up.image = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: nil)
        down.image = NSImage(systemSymbolName: "arrow.down", accessibilityDescription: nil)
        for item in [up, down] {
            item.target = self
            item.representedObject = section.title
            menu.addItem(item)
        }
        menu.addItem(.separator())
        addLayoutItems(to: menu)
        return menu
    }

    /// Right-click on an empty place of the panel.
    private func makeLayoutMenu() -> NSMenu {
        let menu = NSMenu(title: "Tool Panel")
        addLayoutItems(to: menu)
        return menu
    }

    /// View › Tool Panel: the same choices, filled in each time the menu opens.
    func makeToolPanelMenu() -> NSMenu {
        let menu = NSMenu(title: "Tool Panel")
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addLayoutItems(to: menu)
    }

    /// One checked item per section (shown / hidden) and the reset.
    private func addLayoutItems(to menu: NSMenu) {
        let hidden = ToolPanelLayout.hidden
        let noFavorites = ToolPanelLayout.favorites.isEmpty
        for section in ToolPanelLayout.order {
            let item = NSMenuItem(title: section.title, action: #selector(sectionVisibilityToggled(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = section.title
            item.state = hidden.contains(section) ? .off : .on
            if section == .favorites && noFavorites { item.subtitle = "Right-click a tool to add it" }
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let columns = NSMenuItem(title: "Add Columns When Groups Don't Fit", action: #selector(addsColumnsToggled(_:)),
                                 keyEquivalent: "")
        columns.target = self
        columns.state = ToolbarView.addsColumns ? .on : .off
        columns.subtitle = "Otherwise the panel scrolls"
        menu.addItem(columns)
        let reset = NSMenuItem(title: "Reset Tool Panel and Palettes", action: #selector(layoutReset(_:)),
                               keyEquivalent: "")
        reset.target = self
        reset.subtitle = "The tool panel and all palettes as at the start"
        reset.image = NSImage(systemSymbolName: "arrow.counterclockwise", accessibilityDescription: nil)
        menu.addItem(reset)
    }

    private func section(of sender: NSMenuItem) -> ToolPanelSection? {
        return (sender.representedObject as? String).flatMap { ToolPanelSection(title: $0) }
    }

    @objc private func sectionVisibilityToggled(_ sender: NSMenuItem) {
        guard let section = section(of: sender) else { return }
        var hidden = ToolPanelLayout.hidden
        let shown = hidden.contains(section)
        if shown { hidden.remove(section) } else { hidden.insert(section) }
        ToolPanelLayout.hidden = hidden
        // a section lying in a floating palette comes back from it, so it is not in both places
        if shown { onSectionShown?(section) }
        scheduleRebuild()
    }

    @objc private func sectionMovedUp(_ sender: NSMenuItem) {
        guard let section = section(of: sender), let index = visibleSections.firstIndex(of: section) else { return }
        move(section, toVisibleIndex: index - 1)
    }

    @objc private func sectionMovedDown(_ sender: NSMenuItem) {
        guard let section = section(of: sender), let index = visibleSections.firstIndex(of: section) else { return }
        // in front of the section two places further = one place down
        move(section, toVisibleIndex: index + 2)
    }

    @objc private func addsColumnsToggled(_ sender: NSMenuItem) {
        ToolbarView.addsColumns.toggle()
        scheduleRebuild()
    }

    @objc private func layoutReset(_ sender: NSMenuItem) {
        onLayoutReset?()
    }

    /// Back to the default panel: all groups shown in the default order, two icons in a row, scrolling
    /// (the favorites stay).
    func resetToDefaults() {
        ToolPanelLayout.resetLayout()
        ToolbarView.iconsPerRow = 2
        ToolbarView.addsColumns = false
        scheduleRebuild()
    }

    // MARK: Combined buttons (Circle / Ellipse / Polygon, Fillet / Chamfer)

    private func makeFamilyMenu(_ leader: DrawingTool) -> NSMenu {
        let menu = ToolMenu(title: leader.title)
        guard let family = leader.paletteFamily else { return menu }
        let current = familyChoice[leader] ?? leader
        for tool in family {
            let item = ToolMenuItem(title: tool.menuTitle, action: #selector(familyToolChosen(_:)), keyEquivalent: "")
            item.target = self
            item.usage = tool.usage
            item.tag = tool.rawValue
            item.image = ToolIcons.image(for: tool, size: 22)
            item.subtitle = tool.summary
            item.state = tool == current ? .on : .off
            menu.addItem(item)
        }
        if family.contains(.polygon) {
            let settings = delegate?.toolbarPolygonSettings() ?? (method: PolygonMethod.inscribed, sides: 6)
            menu.addItem(.separator())
            for method in PolygonMethod.allCases {
                let item = NSMenuItem(title: method.title, action: #selector(polygonMethodChosen(_:)), keyEquivalent: "")
                item.target = self
                item.tag = method.rawValue
                item.image = ToolIcons.image(for: method, size: 22)
                item.subtitle = method.detail
                item.state = method == settings.method ? .on : .off
                menu.addItem(item)
                menu.setUsage(DrawingTool.polygon.usage, for: item)
            }
            let sides = NSMenuItem(title: "Number of Sides: \(settings.sides)…", action: #selector(polygonSidesChosen(_:)),
                                   keyEquivalent: "")
            sides.target = self
            sides.subtitle = "Also S while drawing, or the Sides field at the cursor"
            sides.image = ToolIcons.settingsImage(size: 22)
            menu.addItem(sides)
        }
        if family.contains(.dimLinear) {
            // dimension ends and style once for all dimension kinds
            menu.addItem(.separator())
            addDimensionItems(to: menu)
        }
        return menu
    }

    @objc private func familyToolChosen(_ sender: NSMenuItem) {
        guard let tool = DrawingTool(rawValue: sender.tag) else { return }
        hideTip()
        delegate?.toolbarDidSelectTool(tool)
    }

    @objc private func polygonMethodChosen(_ sender: NSMenuItem) {
        guard let method = PolygonMethod(rawValue: sender.tag) else { return }
        delegate?.toolbarDidSelectPolygonMethod(method)
    }

    @objc private func polygonSidesChosen(_ sender: NSMenuItem) {
        delegate?.toolbarDidRequestPolygonSides()
    }

    func setArcMethod(_ method: ArcMethod) {
        arcMethod = method
        setIcon(ToolIcons.image(for: method, size: 19), for: .arc)
    }

    // MARK: Tool help

    private let tipView = HoverTipView(frame: .zero)
    private var tipTool: DrawingTool?
    /// The hovered button is a combined one – the help then says what else is under it.
    private var tipCombined = true
    private weak var tipButton: NSView?
    private let tipDelay: TimeInterval = 0.5
    private let usageDelay: TimeInterval = 3.0

    private func hoverChanged(tool: DrawingTool, button: NSView, combined: Bool, hovering: Bool) {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        if hovering {
            tipTool = tool
            tipCombined = combined
            tipButton = button
            perform(#selector(showTip), with: nil, afterDelay: tipView.superview == nil || tipView.isHidden ? tipDelay : 0)
            perform(#selector(expandTip), with: nil, afterDelay: usageDelay)
        } else {
            hideTip()
        }
    }

    @objc private func showTip() {
        guard let tool = tipTool, let button = tipButton, let content = window?.contentView else { return }
        if tipView.superview !== content {
            tipView.removeFromSuperview()
            content.addSubview(tipView, positioned: .above, relativeTo: nil)
        }
        let shortcut = tool.shortcut.map { "  (\($0))" } ?? ""
        tipView.configure(title: tool.title + shortcut, summary: tool.summary + (tipCombined ? familyNote(tool) : ""), usage: tool.usage, expanded: false)
        positionTip(next: button, in: content)
        tipView.isHidden = false
    }

    @objc private func expandTip() {
        guard !tipView.isHidden, let tool = tipTool, let button = tipButton, let content = window?.contentView else { return }
        let shortcut = tool.shortcut.map { "  (\($0))" } ?? ""
        tipView.configure(title: tool.title + shortcut, summary: tool.summary + (tipCombined ? familyNote(tool) : ""), usage: tool.usage, expanded: true)
        positionTip(next: button, in: content)
    }

    /// For a combined button: what else is hidden under it.
    private func familyNote(_ tool: DrawingTool) -> String {
        guard let family = tool.paletteFamily else { return "" }
        let others = family.filter { $0 != tool }.map { $0.title }
        guard !others.isEmpty else { return "" }
        let extra = family.contains(.dimLinear) ? ", the dimension ends and the Dimension Style"
            : family.contains(.polygon) ? ", the polygon method and the number of sides" : ""
        return "\nHold the button (or right-click it) for " + others.joined(separator: ", ") + extra + "."
    }

    func hideTip() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        tipView.isHidden = true
        tipTool = nil
    }

    /// A popup to the right of the button, always fully inside the window.
    private func positionTip(next button: NSView, in content: NSView) {
        let buttonFrame = button.convert(button.bounds, to: content)
        let size = tipView.frame.size
        var origin = CGPoint(x: buttonFrame.maxX + 10, y: buttonFrame.maxY - size.height)
        origin.y = min(max(origin.y, 4), content.bounds.height - size.height - 4)
        origin.x = min(origin.x, content.bounds.width - size.width - 4)
        tipView.setFrameOrigin(origin)
    }

    private(set) var hatchPattern: HatchPattern = .lines

    func setHatchPattern(_ pattern: HatchPattern) {
        hatchPattern = pattern
    }

    private func makeHatchMenu() -> NSMenu {
        let menu = ToolMenu(title: "Hatch")
        let summary = delegate?.toolbarHatchSettingsSummary() ?? (angle: 0, scaleText: "1")
        HatchMenuBuilder.populate(menu, current: hatchPattern, angle: summary.angle, scaleText: summary.scaleText,
                                  actions: .init(target: self,
                                                 choose: #selector(hatchPatternChosen(_:)),
                                                 newCustom: #selector(customHatchPattern(_:)),
                                                 settings: #selector(hatchSettings(_:)),
                                                 removeCustom: #selector(removeCustomHatchPattern(_:))),
                                  imageSize: 22)
        menu.addItem(.separator())
        menu.addItem(toolItem(.hatchRebuild))
        menu.addItem(toolItem(.hatchCut))
        return menu
    }

    /// A menu item that starts a tool which has no button of its own in the panel.
    private func toolItem(_ tool: DrawingTool, imageSize: CGFloat = 22) -> NSMenuItem {
        let item = ToolMenuItem(title: tool.menuTitle, action: #selector(menuToolChosen(_:)), keyEquivalent: "")
        item.target = self
        item.tag = tool.rawValue
        item.usage = tool.usage
        item.image = ToolIcons.image(for: tool, size: imageSize)
        // the tool has no button of its own, so its help is shown here
        item.subtitle = tool.summary
        return item
    }

    @objc private func menuToolChosen(_ sender: NSMenuItem) {
        guard let tool = DrawingTool(rawValue: sender.tag) else { return }
        delegate?.toolbarDidSelectTool(tool)
    }

    @objc private func hatchPatternChosen(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let pattern = HatchPatternLibrary.named(name) else { return }
        delegate?.toolbarDidSelectHatchPattern(pattern)
    }

    @objc private func customHatchPattern(_ sender: NSMenuItem) {
        delegate?.toolbarDidRequestCustomHatchPattern()
    }

    @objc private func hatchSettings(_ sender: NSMenuItem) {
        delegate?.toolbarDidRequestHatchSettings()
    }

    @objc private func removeCustomHatchPattern(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        delegate?.toolbarDidRemoveCustomHatchPattern(name)
    }

    private func makeArcMenu() -> NSMenu {
        let menu = ToolMenu(title: "Arc")
        for method in ArcMethod.allCases {
            let item = NSMenuItem(title: method.title, action: #selector(arcMethodChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = method.rawValue
            item.image = ToolIcons.image(for: method, size: 22)
            item.subtitle = method.detail
            item.state = method == arcMethod ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func arcMethodChosen(_ sender: NSMenuItem) {
        guard let method = ArcMethod(rawValue: sender.tag) else { return }
        delegate?.toolbarDidSelectArcMethod(method)
    }

    // MARK: Text – text kinds

    private(set) var textKind: TextKind = .simple

    func setTextKind(_ kind: TextKind) {
        textKind = kind
        setIcon(ToolIcons.image(for: kind, size: 19), for: .text)
    }

    private func makeTextMenu() -> NSMenu {
        let menu = ToolMenu(title: "Text")
        for kind in TextKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(textKindChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = kind.rawValue
            item.image = ToolIcons.image(for: kind, size: 22)
            item.subtitle = kind.detail
            item.state = kind == textKind ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let style = NSMenuItem(title: "Text Style…", action: #selector(textStyleChosen(_:)), keyEquivalent: "")
        style.target = self
        style.subtitle = "Font, typeface and height for new text"
        style.image = ToolIcons.settingsImage(size: 22)
        menu.addItem(style)
        return menu
    }

    @objc private func textKindChosen(_ sender: NSMenuItem) {
        guard let kind = TextKind(rawValue: sender.tag) else { return }
        delegate?.toolbarDidSelectTextKind(kind)
    }

    @objc private func textStyleChosen(_ sender: NSMenuItem) {
        delegate?.toolbarDidRequestTextStyle()
    }

    // MARK: Dimensions – terminators

    private func addDimensionItems(to menu: NSMenu) {
        let current = AppSettings.dimArrowStyle
        for style in DimArrowStyle.allCases {
            let item = NSMenuItem(title: style.title, action: #selector(dimArrowChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style.rawValue
            item.image = ToolIcons.image(for: style, size: 22)
            item.subtitle = style.detail
            item.state = style == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let styleItem = NSMenuItem(title: "Dimension Style…", action: #selector(dimStyleChosen(_:)), keyEquivalent: "")
        styleItem.target = self
        styleItem.subtitle = "Text height, size of the ends and decimals of new dimensions"
        styleItem.image = ToolIcons.settingsImage(size: 22)
        menu.addItem(styleItem)
    }

    @objc private func dimArrowChosen(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = DimArrowStyle(rawValue: raw) else { return }
        delegate?.toolbarDidSelectDimArrowStyle(style)
    }

    @objc private func dimStyleChosen(_ sender: NSMenuItem) {
        delegate?.toolbarDidRequestDimensionStyle()
    }

    // MARK: Blocks – which one to insert

    private var blockMenuItems: [ObjectIdentifier: BlockDefinition] = [:]

    private func makeBlockMenu() -> NSMenu {
        let menu = ToolMenu(title: "Insert Block")
        blockMenuItems.removeAll()
        let definitions = delegate?.toolbarBlockDefinitions() ?? []
        let current = delegate?.toolbarCurrentBlock()
        if definitions.isEmpty {
            let none = NSMenuItem(title: "No blocks in this drawing yet", action: nil, keyEquivalent: "")
            none.isEnabled = false
            menu.addItem(none)
        }
        for (index, definition) in definitions.enumerated() {
            if index > 0, definition.isExternal, !definitions[index - 1].isExternal { menu.addItem(.separator()) }
            let item = NSMenuItem(title: definition.name, action: #selector(blockChosen(_:)), keyEquivalent: "")
            item.target = self
            item.image = BlockPreview.image(of: definition, size: 22)
            item.subtitle = definition.menuSubtitle
            item.state = definition === current ? .on : .off
            item.representedObject = definition.name
            blockMenuItems[ObjectIdentifier(item)] = definition
            menu.addItem(item)
        }
        return menu
    }

    @objc private func blockChosen(_ sender: NSMenuItem) {
        guard let definition = blockMenuItems[ObjectIdentifier(sender)] else { return }
        delegate?.toolbarDidChooseBlock(definition)
    }

    // MARK: Array – kind

    private(set) var arrayKind: ArrayKind = .rectangular

    func setArrayKind(_ kind: ArrayKind) {
        arrayKind = kind
        setIcon(ToolIcons.image(for: kind, size: 19), for: .array)
    }

    private func makeArrayMenu() -> NSMenu {
        let menu = ToolMenu(title: "Array")
        for kind in ArrayKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(arrayKindChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = kind.rawValue
            item.image = ToolIcons.image(for: kind, size: 22)
            item.subtitle = kind.detail
            item.state = kind == arrayKind ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func arrayKindChosen(_ sender: NSMenuItem) {
        guard let kind = ArrayKind(rawValue: sender.tag) else { return }
        delegate?.toolbarDidSelectArrayKind(kind)
    }

    // MARK: Construction lines – method

    private(set) var xlineKind: XLineKind = .twoPoints

    func setXLineKind(_ kind: XLineKind) {
        xlineKind = kind
        setIcon(ToolIcons.image(for: kind, size: 19), for: .xline)
    }

    private func makeXLineMenu() -> NSMenu {
        let menu = ToolMenu(title: "Construction Line")
        for kind in XLineKind.allCases {
            let item = NSMenuItem(title: kind.title, action: #selector(xlineKindChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = kind.rawValue
            item.image = ToolIcons.image(for: kind, size: 22)
            item.subtitle = kind.detail
            item.state = kind == xlineKind ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func xlineKindChosen(_ sender: NSMenuItem) {
        guard let kind = XLineKind(rawValue: sender.tag) else { return }
        delegate?.toolbarDidSelectXLineKind(kind)
    }

    // MARK: Match properties – what to transfer

    private func makeMatchMenu() -> NSMenu {
        let menu = ToolMenu(title: "Match Properties")
        let chosen = AppSettings.matchProperties
        for (index, property) in MatchProperty.allCases.enumerated() {
            if property == .style { menu.addItem(.separator()) }
            let item = NSMenuItem(title: property.title, action: #selector(matchPropertyToggled(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.subtitle = property.detail
            item.image = ToolIcons.image(for: property, size: 22)
            item.state = chosen.contains(property) ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func matchPropertyToggled(_ sender: NSMenuItem) {
        let all = MatchProperty.allCases
        guard all.indices.contains(sender.tag) else { return }
        var chosen = AppSettings.matchProperties
        let property = all[sender.tag]
        if chosen.contains(property) { chosen.remove(property) } else { chosen.insert(property) }
        AppSettings.matchProperties = chosen
        delegate?.toolbarDidChangeMatchProperties()
    }

    // MARK: Measure – what to measure

    private(set) var measureKind: MeasureKind = .distance

    func setMeasureKind(_ kind: MeasureKind) {
        measureKind = kind
        setIcon(ToolIcons.image(for: kind, size: 19), for: .measure)
    }

    private func makeMeasureMenu() -> NSMenu {
        let menu = ToolMenu(title: "Measure")
        for kind in MeasureKind.allCases {
            if kind == .areaPoints || kind == .point { menu.addItem(.separator()) }
            let item = NSMenuItem(title: kind.title, action: #selector(measureKindChosen(_:)), keyEquivalent: "")
            item.target = self
            item.tag = kind.rawValue
            item.image = ToolIcons.image(for: kind, size: 22)
            item.subtitle = kind.detail
            item.state = kind == measureKind ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    @objc private func measureKindChosen(_ sender: NSMenuItem) {
        guard let kind = MeasureKind(rawValue: sender.tag) else { return }
        delegate?.toolbarDidSelectMeasureKind(kind)
    }
}

/// A single tool button: icon, selection and hover highlighting,
/// for tools with a menu a small triangle in the corner and opening the menu by holding.
final class ToolButtonView: NSView {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    /// Dragging the button: the panel shows where it goes and places it on release.
    var onDrag: ((ToolDragPhase, NSEvent) -> Void)?
    var hasMenu = false { didSet { needsDisplay = true } }
    /// When set, the menu (and its triangle) is offered only while this returns true.
    var menuCondition: (() -> Bool)?
    private var offersMenu: Bool { hasMenu && menuCondition?() != false }
    var isSelected = false { didSet { updateAppearance() } }
    var image: NSImage? {
        didSet { updateAppearance() }
    }

    private let imageView = NSImageView()
    private var isHovered = false
    private var isPressed = false
    private var menuShown = false
    private var trackingArea: NSTrackingArea?
    private let longPressDelay: TimeInterval = 0.4
    private var mouseDownPoint: NSPoint?
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        imageView.frame = bounds.insetBy(dx: 6, dy: 5)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateAppearance() {
        let background: NSColor
        if isSelected {
            background = Theme.accent
        } else if isPressed {
            background = Theme.buttonPressed
        } else if isHovered {
            background = Theme.buttonHover
        } else {
            background = .clear
        }
        layer?.backgroundColor = background.cgColor
        // two-color tool icon; one dark/white color on the selected button
        imageView.image = image.flatMap { ToolIcons.colored($0, selected: isSelected) } ?? image
        imageView.contentTintColor = isSelected ? Theme.selectedInk : Theme.textSoft
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard offersMenu else { return }
        // small triangle at the bottom right = hold to open a menu
        let path = NSBezierPath()
        path.move(to: NSPoint(x: bounds.maxX - 3, y: 3))
        path.line(to: NSPoint(x: bounds.maxX - 3, y: 9))
        path.line(to: NSPoint(x: bounds.maxX - 9, y: 3))
        path.close()
        (isSelected ? Theme.selectedInk : Theme.menuTriangle).setFill()
        path.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
        refreshHover()
    }

    /// The button can move away from under a still mouse (a palette bar scrolled or laid out again) without
    /// getting an exit event – then it would stay lit up. Checks where the mouse really is.
    func refreshHover() {
        guard let window = window else { return }
        let inside = bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        guard inside != isHovered else { return }
        isHovered = inside
        updateAppearance()
        if !inside { onHover?(false) }
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateAppearance()
        onHover?(false)
    }

    override func mouseDown(with event: NSEvent) {
        onHover?(false)
        isPressed = true
        menuShown = false
        mouseDownPoint = event.locationInWindow
        isDragging = false
        updateAppearance()
        if offersMenu {
            perform(#selector(showMenu), with: nil, afterDelay: longPressDelay)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let onDrag = onDrag, !menuShown, let start = mouseDownPoint else { return }
        if !isDragging {
            guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4 else { return }
            // a drag, not a click or a hold: no menu
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showMenu), object: nil)
            isDragging = true
        }
        onDrag(.moved, event)
    }

    override func mouseUp(with event: NSEvent) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(showMenu), object: nil)
        mouseDownPoint = nil
        if isDragging {
            isDragging = false
            isPressed = false
            updateAppearance()
            onDrag?(.ended, event)
            return
        }
        let wasMenu = menuShown
        isPressed = false
        updateAppearance()
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if !wasMenu && inside { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) {
        if menuProvider != nil { showMenu() } else { super.rightMouseDown(with: event) }
    }

    @objc private func showMenu() {
        guard let menu = menuProvider?().map(withRows) else { return }
        menuShown = true
        menu.popUp(positioning: nil, at: NSPoint(x: bounds.maxX + 2, y: bounds.maxY), in: self)
        // the menu “swallows” the mouse-up – restore the state manually
        isPressed = false
        updateAppearance()
    }
}

/// The heading of a tool panel section: drag it to move the section, right-click it for its menu.
final class ToolSectionCaptionView: NSView {
    var onDrag: ((ToolDragPhase, NSEvent) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    private let label: NSTextField
    private var mouseDownPoint: NSPoint?
    private var isDragging = false

    init(frame frameRect: NSRect, title: String) {
        label = NSTextField(labelWithString: title.uppercased())
        super.init(frame: frameRect)
        label.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        label.textColor = Theme.textHeading
        label.alignment = .center
        // a long name (ARCHITECTURE) gets a slightly smaller font so it fits the narrow panel
        var fontSize: CGFloat = 9.5
        while label.intrinsicContentSize.width > frameRect.width - 4 && fontSize > 7 {
            fontSize -= 0.5
            label.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        }
        label.frame = bounds
        label.autoresizingMask = [.width]
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // the whole heading takes the mouse, not the label inside
    override func hitTest(_ point: NSPoint) -> NSView? {
        return frame.contains(point) ? self : nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        if !isDragging {
            guard hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3 else { return }
            isDragging = true
            NSCursor.closedHand.push()
        }
        onDrag?(.moved, event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
        guard isDragging else { return }
        isDragging = false
        NSCursor.pop()
        onDrag?(.ended, event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return menuProvider?().map(withRows)
    }
}

/// Menus with rows drawn by the app, so their icons and line previews show on every macOS.
private func withRows(_ menu: NSMenu) -> NSMenu {
    MenuRows.apply(to: menu)
    return menu
}

// MARK: - Layer Panel

final class LayerPanelView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSMenuDelegate {
    var layerManager: LayerManager? {
        didSet { reloadData() }
    }
    /// Renaming and deleting are handled by the controller (it must update the entities too).
    var onRenameLayer: ((_ oldName: String, _ newName: String) -> Void)?
    var onDeleteLayer: ((String) -> Void)?
    /// Select all objects of the layer in the drawing.
    var onSelectLayerObjects: ((String) -> Void)?
    /// Layers that the selected objects lie on (the ○ mark in the compact panel).
    var selectedObjectLayers: (() -> Set<String>)?
    /// Detach into its own window / return to the side panel / maximize the window.
    var onDetach: (() -> Void)?
    var onAttach: (() -> Void)?
    var onToggleMaximize: (() -> Void)?

    /// tray = in the side panel (compact rows, the panel has the heading), otherwise a full table with its own header.
    enum Mode { case popover, window, maximized, tray }

    private var headerButtons: [NSButton] = []
    private var bottomButtons: [NSButton] = []
    private var compactButtons: [NSButton] = []
    private let titleLabel = NSTextField(labelWithString: "Layers")
    private let searchField = NSSearchField()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let tableScroll = NSScrollView()
    private let tableView = NSTableView()
    private var savedHeaderView: NSTableHeaderView?
    /// Displayed layers (after filtering) – row index = index in this array.
    private var layers: [Layer] = []
    private var filterText = ""
    private var objectLayers: Set<String> = []
    private var suppressReload = false
    private var compact = false
    /// The layer the open menu belongs to (right click, line sample, ⋯).
    private var menuLayer: String?

    private enum Column: String, CaseIterable {
        // Print is at the far right; style = compact line sample (type + weight)
        case current, visible, locked, color, name, lineType, lineWeight, printable, style

        static let full: [Column] = [.current, .visible, .locked, .color, .name, .lineType, .lineWeight, .printable]
        static let compact: [Column] = [.color, .name, .style, .visible, .locked]

        var title: String {
            switch self {
            case .current: return ""
            case .visible: return "On"
            case .locked: return "Lock"
            case .printable: return "Print"
            case .color: return "Color"
            case .name: return "Name"
            case .lineType: return "Linetype"
            case .lineWeight: return "Weight"
            case .style: return "Line"
            }
        }

        /// Tooltip when hovering over a column header.
        var headerTip: String? {
            switch self {
            case .current: return "Current layer – new objects are drawn on it"
            case .visible: return "Visible – unchecked layers are hidden on screen"
            case .locked: return "Locked – objects on the layer cannot be selected or edited"
            case .printable: return "Printable – unchecked layers stay visible on screen but are skipped when printing or exporting to PDF"
            case .color: return "Layer color (used by objects set to ByLayer)"
            case .name: return "Layer name – double-click to rename"
            case .lineType: return "Layer linetype"
            case .lineWeight: return "Layer lineweight"
            case .style: return "Linetype and lineweight – click to change"
            }
        }

        func width(compact: Bool) -> CGFloat {
            switch self {
            case .current: return 14
            case .visible: return compact ? 18 : 24
            case .locked: return compact ? 18 : 30
            case .printable: return 34
            case .color: return compact ? 18 : 34
            case .name: return 76
            case .lineType: return 86
            case .lineWeight: return 76
            case .style: return 34
            }
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = Theme.panelBackground.cgColor

        let title = titleLabel
        title.font = NSFont.boldSystemFont(ofSize: 12)
        title.textColor = .white
        title.frame = NSRect(x: 10, y: bounds.height - 30, width: 120, height: 18)
        title.autoresizingMask = [.minYMargin]
        addSubview(title)

        // Buttons of the full table (window)
        let buttons: [(String, String, Selector)] = [
            ("+", "New layer – double-click its name to rename it", #selector(addLayer)),
            ("−", "Delete the selected layer (must be empty)", #selector(deleteLayer)),
            ("Rename…", "Rename the selected layer (or double-click its name)", #selector(renameLayer)),
            ("Set Current", "Make the selected layer current (or double-click the row)", #selector(setCurrent))
        ]
        var x: CGFloat = 10
        for (label, tip, action) in buttons {
            let button = NSButton(title: label, target: self, action: action)
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 11)
            button.bezelStyle = .push
            button.toolTip = tip
            button.sizeToFit()
            button.frame.origin = CGPoint(x: x, y: 8)
            addSubview(button)
            bottomButtons.append(button)
            x += button.frame.width + 4
        }

        // Compact panel: filter and icons at the top, summary at the bottom
        searchField.controlSize = .small
        searchField.font = NSFont.systemFont(ofSize: 11)
        searchField.placeholderString = "Filter"
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(filterChanged(_:))
        searchField.toolTip = "Show only layers whose name contains the text"
        addSubview(searchField)

        let compactItems: [(String, String, Selector)] = [
            ("plus", "New layer – double-click its name to rename it", #selector(addLayer)),
            ("trash", "Delete the selected layer (must be empty)", #selector(deleteLayer)),
            ("ellipsis.circle", "More: set current, rename, show or unlock all, open in a window", #selector(showMoreMenu(_:)))
        ]
        for (symbol, tip, action) in compactItems {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            button.imageScaling = .scaleProportionallyDown
            button.isBordered = false
            button.contentTintColor = Theme.textSecondary
            button.toolTip = tip
            button.target = self
            button.action = action
            button.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(button)
            compactButtons.append(button)
        }

        summaryLabel.font = NSFont.systemFont(ofSize: 10)
        summaryLabel.textColor = Theme.textCaption
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.autoresizingMask = [.width, .maxYMargin]
        addSubview(summaryLabel)

        // Table
        savedHeaderView = tableView.headerView
        tableView.intercellSpacing = NSSize(width: 2, height: 2)
        tableView.backgroundColor = Theme.listBackground
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        // the name column grows when the window is enlarged
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        let contextMenu = NSMenu(title: "Layer")
        contextMenu.delegate = self
        tableView.menu = contextMenu

        let scrollView = tableScroll
        scrollView.frame = NSRect(x: 6, y: 40, width: bounds.width - 12, height: bounds.height - 76)
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        setMode(.popover)
    }

    /// Columns according to the mode (compact rows in the side panel, full table in a window).
    private func configureColumns() {
        for column in tableView.tableColumns { tableView.removeTableColumn(column) }
        for column in compact ? Column.compact : Column.full {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.title = column.title
            let width = column.width(compact: compact)
            tableColumn.width = width
            tableColumn.headerToolTip = column.headerTip
            tableColumn.minWidth = width
            if column == .name {
                tableColumn.resizingMask = [.autoresizingMask, .userResizingMask]
                tableColumn.maxWidth = 2000
            } else {
                tableColumn.resizingMask = compact ? [] : .userResizingMask
            }
            tableView.addTableColumn(tableColumn)
        }
        tableView.headerView = compact ? nil : savedHeaderView
        tableView.rowHeight = compact ? 20 : 22
        tableScroll.hasHorizontalScroller = !compact     // the full table scrolls sideways in a narrow space
    }

    /// Buttons in the top right corner depending on where the panel is.
    func setMode(_ mode: Mode) {
        headerButtons.forEach { $0.removeFromSuperview() }
        headerButtons.removeAll()
        compact = mode == .tray

        // in the side panel the heading is in the panel header
        titleLabel.isHidden = compact
        bottomButtons.forEach { $0.isHidden = compact }
        compactButtons.forEach { $0.isHidden = !compact }
        searchField.isHidden = !compact
        summaryLabel.isHidden = !compact

        if compact {
            let buttonsWidth = CGFloat(compactButtons.count) * 24
            searchField.frame = NSRect(x: 6, y: bounds.height - 28, width: max(bounds.width - 12 - buttonsWidth - 4, 60), height: 22)
            searchField.autoresizingMask = [.width, .minYMargin]
            var bx = bounds.width - 6 - buttonsWidth
            for button in compactButtons {
                button.frame.origin = CGPoint(x: bx + 1, y: bounds.height - 28)
                bx += 24
            }
            summaryLabel.frame = NSRect(x: 10, y: 3, width: bounds.width - 20, height: 14)
            tableScroll.frame = NSRect(x: 6, y: 20, width: bounds.width - 12, height: max(bounds.height - 20 - 34, 40))
        } else {
            searchField.stringValue = ""
            filterText = ""
            tableScroll.frame = NSRect(x: 6, y: 40, width: bounds.width - 12, height: max(bounds.height - 40 - 36, 40))
        }
        configureColumns()

        let items: [(String, String, Selector)]
        switch mode {
        case .tray:
            items = []
        case .popover:
            items = [("macwindow.on.rectangle", "Detach into its own window", #selector(detachClicked)),
                     ("arrow.up.left.and.arrow.down.right", "Maximize", #selector(maximizeClicked))]
        case .window:
            items = [("rectangle.righthalf.inset.filled", "Dock to the side panel", #selector(attachClicked)),
                     ("arrow.up.left.and.arrow.down.right", "Maximize", #selector(maximizeClicked))]
        case .maximized:
            items = [("rectangle.righthalf.inset.filled", "Dock to the side panel", #selector(attachClicked)),
                     ("arrow.down.right.and.arrow.up.left", "Restore the window size", #selector(maximizeClicked))]
        }
        var x = bounds.width - 8
        for (symbol, tip, action) in items.reversed() {
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 20))
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
                ?? NSImage(systemSymbolName: "square", accessibilityDescription: tip)
            button.imageScaling = .scaleProportionallyDown
            button.isBordered = false
            button.contentTintColor = Theme.textSecondary
            button.toolTip = tip
            button.target = self
            button.action = action
            x -= 24
            button.frame.origin = CGPoint(x: x, y: bounds.height - 30)
            button.autoresizingMask = [.minXMargin, .minYMargin]
            addSubview(button)
            headerButtons.append(button)
        }
        reloadData()
    }

    @objc private func detachClicked() { onDetach?() }
    @objc private func attachClicked() { onAttach?() }
    @objc private func maximizeClicked() { onToggleMaximize?() }

    func reloadData() {
        guard !suppressReload else { return }
        refreshList()
        objectLayers = compact ? (selectedObjectLayers?() ?? []) : []
        tableView.reloadData()
    }

    /// Layer list after filtering and the summary below the table.
    private func refreshList() {
        let all = layerManager?.getAllLayers() ?? []
        let filter = filterText.trimmingCharacters(in: .whitespaces)
        layers = filter.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        var parts = ["\(all.count) layer\(all.count == 1 ? "" : "s")"]
        if layers.count != all.count { parts[0] = "\(layers.count) of \(all.count) layers" }
        let hidden = all.filter { !$0.isVisible }.count
        let locked = all.filter { $0.isLocked }.count
        let notPrinted = all.filter { !$0.isPrintable }.count
        if hidden > 0 { parts.append("\(hidden) hidden") }
        if locked > 0 { parts.append("\(locked) locked") }
        if notPrinted > 0 { parts.append("\(notPrinted) not printed") }
        summaryLabel.stringValue = parts.joined(separator: " · ")
    }

    @objc private func filterChanged(_ sender: NSSearchField) {
        filterText = sender.stringValue
        reloadData()
    }

    private var selectedLayerName: String? {
        let row = tableView.selectedRow
        return row >= 0 && row < layers.count ? layers[row].name : nil
    }

    // MARK: Data source & delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        return layers.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let rowView = LayerRowView()
        rowView.isCurrent = compact && row < layers.count && layers[row].name == layerManager?.currentLayerName
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier.rawValue, let column = Column(rawValue: identifier),
              row < layers.count else { return nil }
        let layer = layers[row]

        switch column {
        case .current:
            let label = NSTextField(labelWithString: layer.name == layerManager?.currentLayerName ? "▶︎" : "")
            label.textColor = .systemGreen
            label.font = NSFont.systemFont(ofSize: 10)
            return label

        case .visible where compact, .locked where compact:
            let isVisibleColumn = column == .visible
            let isOn = isVisibleColumn ? layer.isVisible : layer.isLocked
            let symbol = isVisibleColumn ? (isOn ? "eye" : "eye.slash") : (isOn ? "lock.fill" : "lock.open")
            let tip = isVisibleColumn
                ? (isOn ? "Visible – click to hide · ⌥-click = show only this layer" : "Hidden – click to show")
                : (isOn ? "Locked – click to unlock" : "Unlocked – click to lock (objects cannot be selected or edited)")
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
            button.imageScaling = .scaleProportionallyDown
            button.isBordered = false
            button.contentTintColor = isVisibleColumn
                ? (isOn ? Theme.iconOn : Theme.iconOff)
                : (isOn ? .systemOrange : Theme.iconOff)
            button.toolTip = tip
            button.tag = row
            button.target = self
            button.action = isVisibleColumn ? #selector(flipVisible(_:)) : #selector(flipLocked(_:))
            return button

        case .visible, .locked, .printable:
            let action: Selector
            let isOn: Bool
            switch column {
            case .visible:
                action = #selector(toggleVisible(_:)); isOn = layer.isVisible
            case .locked:
                action = #selector(toggleLocked(_:)); isOn = layer.isLocked
            default:
                action = #selector(togglePrintable(_:)); isOn = layer.isPrintable
            }
            let checkbox = NSButton(checkboxWithTitle: "", target: self, action: action)
            checkbox.state = isOn ? .on : .off
            checkbox.toolTip = column == .printable
                ? (isOn ? "Printable – click to exclude this layer from printing" : "Not printable – shown on screen, skipped when printing")
                : nil
            checkbox.tag = row
            checkbox.controlSize = .small
            return checkbox

        case .color:
            let well = NSColorWell(style: .minimal)
            well.color = layer.color
            well.tag = row
            well.target = self
            well.action = #selector(colorChanged(_:))
            well.toolTip = "Layer color – click to change"
            return well

        case .name:
            let isCurrent = layer.name == layerManager?.currentLayerName
            let field = NSTextField(string: layer.name)
            field.isBordered = false
            field.drawsBackground = false
            field.textColor = layer.isVisible || !compact ? .white : Theme.textDimmed
            field.font = isCurrent ? NSFont.boldSystemFont(ofSize: 11) : NSFont.systemFont(ofSize: 11)
            // Editing is enabled only by double-click – otherwise the field would “swallow” the table click.
            field.isEditable = false
            field.isSelectable = false
            field.lineBreakMode = .byTruncatingTail
            field.toolTip = (isCurrent ? "Current layer – new objects are drawn on it\n" : "")
                + (layer.name == "0" ? "Layer 0 cannot be renamed" : "Double-click the name to rename · right-click for more")
            field.tag = row
            field.delegate = self
            guard compact else { return field }

            // compact row: name + marks (not plotted, selected objects lie here)
            let height = tableView.rowHeight
            let width = tableColumn?.width ?? 100
            let cell = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            var marksWidth: CGFloat = 0
            var marks: [NSView] = []
            if objectLayers.contains(layer.name) {
                let ring = SelectionRingView(frame: NSRect(x: 0, y: 0, width: 10, height: height))
                ring.toolTip = "Selected objects lie on this layer"
                marks.append(ring)
            }
            if !layer.isPrintable {
                let image = NSImageView(frame: NSRect(x: 0, y: 0, width: 14, height: height))
                image.image = NSImage(systemSymbolName: "printer.slash", accessibilityDescription: "Not printed")
                    ?? NSImage(systemSymbolName: "nosign", accessibilityDescription: "Not printed")
                image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
                image.contentTintColor = Theme.textDimmed
                image.toolTip = "Not printed – shown on screen, skipped when printing (right-click › Printable)"
                marks.append(image)
            }
            for mark in marks.reversed() {
                marksWidth += mark.frame.width + 2
                mark.frame.origin.x = width - marksWidth
                mark.autoresizingMask = [.minXMargin]
                cell.addSubview(mark)
            }
            field.sizeToFit()
            let fieldHeight = field.frame.height
            field.frame = NSRect(x: 2, y: (height - fieldHeight) / 2, width: max(width - marksWidth - 4, 20), height: fieldHeight)
            field.autoresizingMask = [.width]
            cell.addSubview(field)
            return cell

        case .style:
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 34, height: tableView.rowHeight))
            button.image = LineStylePreview.image(for: layer.lineType, weight: layer.lineWeight, width: 30, height: 12)
            button.imageScaling = .scaleNone
            button.isBordered = false
            button.toolTip = "\(layer.lineType.name) · \(LineWeights.title(layer.lineWeight)) – click to change"
            button.tag = row
            button.target = self
            button.action = #selector(showStyleMenu(_:))
            return button

        case .lineType:
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.controlSize = .mini
            popup.font = NSFont.systemFont(ofSize: 10)
            for type in LineTypeLibrary.all {
                popup.addItem(withTitle: type.name)
                popup.lastItem?.image = LineStylePreview.image(for: type, width: 30, height: 8)
                popup.lastItem?.toolTip = type.isContinuous ? type.description : "\(type.description)  [\(type.definition)]"
            }
            if popup.item(withTitle: layer.lineType.name) == nil {
                popup.addItem(withTitle: layer.lineType.name)
            }
            popup.menu?.addItem(.separator())
            popup.addItem(withTitle: "Custom…")
            popup.lastItem?.tag = -1
            popup.selectItem(withTitle: layer.lineType.name)
            popup.tag = row
            popup.target = self
            popup.action = #selector(lineTypeChanged(_:))
            return popup

        case .lineWeight:
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.controlSize = .mini
            popup.font = NSFont.systemFont(ofSize: 10)
            for weight in LineWeights.all {
                popup.addItem(withTitle: LineWeights.title(weight))
                popup.lastItem?.representedObject = weight
            }
            if popup.item(withTitle: LineWeights.title(layer.lineWeight)) == nil {
                popup.addItem(withTitle: LineWeights.title(layer.lineWeight))
                popup.lastItem?.representedObject = layer.lineWeight
            }
            popup.menu?.addItem(.separator())
            popup.addItem(withTitle: "Custom…")
            popup.lastItem?.tag = -1
            popup.selectItem(withTitle: LineWeights.title(layer.lineWeight))
            popup.tag = row
            popup.target = self
            popup.action = #selector(lineWeightChanged(_:))
            return popup
        }
    }

    // MARK: Actions

    private func layerName(forTag tag: Int) -> String? {
        return tag >= 0 && tag < layers.count ? layers[tag].name : nil
    }

    private func applyChange(to name: String, reload: Bool = true, _ change: (inout Layer) -> Void) {
        suppressReload = !reload
        layerManager?.updateLayer(name, change)
        suppressReload = false
        if !reload { refreshList() }
    }

    @objc private func toggleVisible(_ sender: NSButton) {
        guard let name = layerName(forTag: sender.tag) else { return }
        applyChange(to: name) { $0.isVisible = sender.state == .on }
    }

    @objc private func toggleLocked(_ sender: NSButton) {
        guard let name = layerName(forTag: sender.tag) else { return }
        applyChange(to: name) { $0.isLocked = sender.state == .on }
    }

    @objc private func togglePrintable(_ sender: NSButton) {
        guard let name = layerName(forTag: sender.tag) else { return }
        applyChange(to: name) { $0.isPrintable = sender.state == .on }
    }

    /// The eye in the compact panel (⌥-click = only this layer visible).
    @objc private func flipVisible(_ sender: NSButton) {
        guard let name = layerName(forTag: sender.tag) else { return }
        if NSEvent.modifierFlags.contains(.option) {
            isolate(name)
            return
        }
        applyChange(to: name) { $0.isVisible.toggle() }
    }

    @objc private func flipLocked(_ sender: NSButton) {
        guard let name = layerName(forTag: sender.tag) else { return }
        applyChange(to: name) { $0.isLocked.toggle() }
    }

    /// Shows only the given layer, hides the others.
    private func isolate(_ name: String) {
        guard let manager = layerManager else { return }
        suppressReload = true
        for layer in manager.getAllLayers() {
            let visible = layer.name == name
            if layer.isVisible != visible { manager.updateLayer(layer.name) { $0.isVisible = visible } }
        }
        suppressReload = false
        reloadData()
    }

    private func setAll(_ change: (inout Layer) -> Void) {
        guard let manager = layerManager else { return }
        suppressReload = true
        for layer in manager.getAllLayers() { manager.updateLayer(layer.name, change) }
        suppressReload = false
        reloadData()
    }

    @objc private func colorChanged(_ sender: NSColorWell) {
        guard let name = layerName(forTag: sender.tag) else { return }
        let color = sender.color
        applyChange(to: name, reload: false) { $0.color = color }
    }

    @objc private func lineTypeChanged(_ sender: NSPopUpButton) {
        guard let name = layerName(forTag: sender.tag), let item = sender.selectedItem else { return }
        if item.tag == -1 {
            // a new custom line type → this layer gets it right away
            if let type = LineTypeEditor().run() {
                LineTypeLibrary.addCustom(type)
                applyChange(to: name) { $0.lineType = type }
            } else {
                reloadData()
            }
            return
        }
        guard let type = LineTypeLibrary.named(item.title) else { return }
        applyChange(to: name, reload: false) { $0.lineType = type }
    }

    @objc private func lineWeightChanged(_ sender: NSPopUpButton) {
        guard let name = layerName(forTag: sender.tag), let item = sender.selectedItem else { return }
        if item.tag == -1 {
            if let weight = LineWeightDialog.run() {
                applyChange(to: name) { $0.lineWeight = weight }
            } else {
                reloadData()
            }
            return
        }
        guard let weight = item.representedObject as? CGFloat else { return }
        applyChange(to: name, reload: false) { $0.lineWeight = weight }
    }

    // MARK: Line type and weight menu (compact panel)

    @objc private func showStyleMenu(_ sender: NSButton) {
        guard let name = layerName(forTag: sender.tag), let layer = layers.first(where: { $0.name == name }) else { return }
        menuLayer = name
        let menu = NSMenu(title: "Line")
        let typeHeader = NSMenuItem(title: "Linetype", action: nil, keyEquivalent: "")
        typeHeader.isEnabled = false
        menu.addItem(typeHeader)
        var types = LineTypeLibrary.all
        if !types.contains(where: { $0.name == layer.lineType.name }) { types.append(layer.lineType) }
        for type in types {
            let item = NSMenuItem(title: type.name, action: #selector(styleTypeChosen(_:)), keyEquivalent: "")
            item.target = self
            item.image = LineStylePreview.image(for: type, width: 40, height: 8)
            item.state = type.name == layer.lineType.name ? .on : .off
            item.toolTip = type.isContinuous ? type.description : "\(type.description)  [\(type.definition)]"
            menu.addItem(item)
        }
        let customType = NSMenuItem(title: "Custom Linetype…", action: #selector(styleTypeChosen(_:)), keyEquivalent: "")
        customType.target = self
        customType.tag = -1
        customType.image = ToolIcons.settingsImage(size: 18)
        menu.addItem(customType)

        menu.addItem(.separator())
        let weightHeader = NSMenuItem(title: "Lineweight", action: nil, keyEquivalent: "")
        weightHeader.isEnabled = false
        menu.addItem(weightHeader)
        var weights = LineWeights.all
        if !weights.contains(layer.lineWeight) { weights.append(layer.lineWeight); weights.sort() }
        for weight in weights {
            let item = NSMenuItem(title: LineWeights.title(weight), action: #selector(styleWeightChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = weight
            item.image = LineStylePreview.image(for: .continuous, weight: weight, width: 40, height: 8)
            item.state = weight == layer.lineWeight ? .on : .off
            menu.addItem(item)
        }
        let customWeight = NSMenuItem(title: "Custom Lineweight…", action: #selector(styleWeightChosen(_:)), keyEquivalent: "")
        customWeight.target = self
        customWeight.tag = -1
        customWeight.image = ToolIcons.settingsImage(size: 18)
        menu.addItem(customWeight)
        _ = withRows(menu).popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func styleTypeChosen(_ sender: NSMenuItem) {
        guard let name = menuLayer else { return }
        if sender.tag == -1 {
            if let type = LineTypeEditor().run() {
                LineTypeLibrary.addCustom(type)
                applyChange(to: name) { $0.lineType = type }
            }
            return
        }
        guard let type = LineTypeLibrary.named(sender.title) ?? layers.first(where: { $0.name == name })?.lineType else { return }
        applyChange(to: name) { $0.lineType = type }
    }

    @objc private func styleWeightChosen(_ sender: NSMenuItem) {
        guard let name = menuLayer else { return }
        if sender.tag == -1 {
            if let weight = LineWeightDialog.run() { applyChange(to: name) { $0.lineWeight = weight } }
            return
        }
        guard let weight = sender.representedObject as? CGFloat else { return }
        applyChange(to: name) { $0.lineWeight = weight }
    }

    // MARK: Right click and the ⋯ menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === tableView.menu else { return }
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, row < layers.count else { return }
        let layer = layers[row]
        menuLayer = layer.name
        func add(_ title: String, _ action: Selector, symbol: String? = nil, state: Bool? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let symbol = symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
            if let state = state { item.state = state ? .on : .off }
            menu.addItem(item)
        }
        add("Set Current", #selector(menuSetCurrent), symbol: "pencil")
        add("Rename…", #selector(menuRename), symbol: "character.cursor.ibeam")
        menu.addItem(.separator())
        add("Printable", #selector(menuTogglePrintable), state: layer.isPrintable)
        add("Isolate (Only This Visible)", #selector(menuIsolate))
        add("Select Objects on Layer", #selector(menuSelectObjects))
        menu.addItem(.separator())
        add("Delete Layer", #selector(menuDelete), symbol: "trash")
        MenuRows.apply(to: menu)
    }

    @objc private func showMoreMenu(_ sender: NSButton) {
        menuLayer = selectedLayerName
        let menu = NSMenu(title: "Layers")
        func add(_ title: String, _ action: Selector, symbol: String? = nil, enabled: Bool = true) {
            let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
            item.target = self
            if let symbol = symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) }
            menu.addItem(item)
        }
        let hasSelection = menuLayer != nil
        add("Set Current", #selector(menuSetCurrent), symbol: "pencil", enabled: hasSelection)
        add("Rename…", #selector(menuRename), symbol: "character.cursor.ibeam", enabled: hasSelection)
        menu.addItem(.separator())
        add("Show All Layers", #selector(menuShowAll))
        add("Unlock All Layers", #selector(menuUnlockAll))
        menu.addItem(.separator())
        add("Open in Window (Full Table)", #selector(detachClicked))
        _ = withRows(menu).popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    @objc private func menuSetCurrent() {
        guard let name = menuLayer else { return }
        layerManager?.setCurrentLayer(name)
        reloadData()
    }

    @objc private func menuRename() {
        guard let name = menuLayer else { return }
        rename(name)
    }

    @objc private func menuTogglePrintable() {
        guard let name = menuLayer else { return }
        applyChange(to: name) { $0.isPrintable.toggle() }
    }

    @objc private func menuIsolate() {
        guard let name = menuLayer else { return }
        isolate(name)
    }

    @objc private func menuSelectObjects() {
        guard let name = menuLayer else { return }
        onSelectLayerObjects?(name)
    }

    @objc private func menuDelete() {
        guard let name = menuLayer else { return }
        onDeleteLayer?(name)
    }

    @objc private func menuShowAll() { setAll { $0.isVisible = true } }
    @objc private func menuUnlockAll() { setAll { $0.isLocked = false } }

    // MARK: Renaming

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, let oldName = layerName(forTag: field.tag) else { return }
        field.isEditable = false
        field.isSelectable = false
        // Esc = cancel renaming
        if let movement = obj.userInfo?["NSTextMovement"] as? Int, movement == NSTextMovement.cancel.rawValue {
            reloadData()
            return
        }
        let newName = field.stringValue.trimmingCharacters(in: .whitespaces)
        if newName != oldName {
            onRenameLayer?(oldName, newName)
        }
        reloadData()
    }

    /// New layer – immediately with a temporary name (Layer1, Layer2…); renamed by double-click or Rename….
    @objc private func addLayer() {
        guard let manager = layerManager else { return }
        // the new layer must be visible – the filter is cleared
        searchField.stringValue = ""
        filterText = ""
        let name = manager.uniqueLayerName()
        let colors: [NSColor] = [.red, .yellow, .green, .cyan, .blue, .magenta]
        let color = colors[(manager.count - 1 + colors.count) % colors.count]
        manager.addLayer(Layer(name: name, color: color))
        if let row = layers.firstIndex(where: { $0.name == name }) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
    }

    /// Renaming the selected layer via a dialog.
    @objc private func renameLayer() {
        guard let name = selectedLayerName else {
            NSSound.beep()
            return
        }
        rename(name)
    }

    private func rename(_ name: String) {
        guard name != "0" else {
            showWarning("Layer 0 is the default layer and cannot be renamed.")
            return
        }
        guard let newName = askForName(title: "Rename Layer", message: "New name of the layer “\(name)”:",
                                       initial: name, button: "Rename"), newName != name else { return }
        onRenameLayer?(name, newName)
        reloadData()
    }

    /// Double-click on the name = rename directly in the table, elsewhere = set as current.
    @objc private func doubleClicked() {
        let row = tableView.clickedRow, column = tableView.clickedColumn
        guard row >= 0, row < layers.count else { return }
        let nameColumn = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(Column.name.rawValue))
        if column == nameColumn {
            guard layers[row].name != "0" else {
                NSSound.beep()
                return
            }
            let cellView = tableView.view(atColumn: column, row: row, makeIfNecessary: false)
            guard let field = (cellView as? NSTextField) ?? (cellView?.subviews.first { $0 is NSTextField } as? NSTextField) else { return }
            field.isEditable = true
            field.isSelectable = true
            field.drawsBackground = true
            field.backgroundColor = Theme.fieldBackground
            if window?.makeFirstResponder(field) == true {
                field.currentEditor()?.selectAll(nil)
            }
        } else {
            setCurrent()
        }
    }

    private func askForName(title: String, message: String, initial: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private func showWarning(_ text: String) {
        let alert = NSAlert()
        alert.messageText = text
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func deleteLayer() {
        guard let name = selectedLayerName else {
            NSSound.beep()
            return
        }
        onDeleteLayer?(name)
    }

    @objc private func setCurrent() {
        guard let name = selectedLayerName else { return }
        layerManager?.setCurrentLayer(name)
        reloadData()
    }
}

/// Row of the compact layer panel: the current layer has a vertical bar on the left (row selection is separate).
private final class LayerRowView: NSTableRowView {
    var isCurrent = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isCurrent else { return }
        Theme.accent.setFill()
        NSRect(x: 0, y: 3, width: 3, height: bounds.height - 6).fill()
    }
}

/// The “selected objects are on this layer” ring.
private final class SelectionRingView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let d: CGFloat = 6
        let rect = NSRect(x: (bounds.width - d) / 2, y: (bounds.height - d) / 2, width: d, height: d)
        let path = NSBezierPath(ovalIn: rect)
        path.lineWidth = 1.4
        Theme.textLabel.setStroke()
        path.stroke()
    }
}

extension LineStylePreview {
    /// Line sample with weight (for the compact layer panel and the lineweight menu).
    static func image(for type: LineType, weight: CGFloat, width: CGFloat, height: CGFloat) -> NSImage {
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            // 0.13 mm ≈ 1 px … 1 mm and more ≈ 4 px
            stroke(type, from: CGPoint(x: 1, y: rect.midY), to: CGPoint(x: rect.maxX - 1, y: rect.midY),
                   width: min(max(weight * 4.5, 0.8), 4), color: Theme.iconLight)
            return true
        }
    }
}

// MARK: - Info Panel

/// Information about the selected objects (sizes, lengths, areas) – clearly laid out as label / value pairs.
final class InfoPanelView: NSView {
    private final class FlippedView: NSView {
        override var isFlipped: Bool { return true }
    }

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    private let captionWidth: CGFloat = 78
    /// The last displayed content (so it is not rebuilt for the same selection).
    private var lastSignature = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.panelBackground.cgColor

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        addSubview(scrollView)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor)
        ])

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selection: [CADEntity], objectCount: Int, layerCount: Int) {
        var lines: [String] = []
        let title: String
        switch selection.count {
        case 0:
            title = "Nothing selected"
            lines = ["Objects: \(objectCount)", "Layers: \(layerCount)", "",
                     "Select an object to see its size, length or area here."]
        case 1:
            let all = selection[0].infoText.components(separatedBy: "\n")
            title = all.first ?? selection[0].typeName
            // layer and color are in Properties
            lines = all.dropFirst().filter { !$0.hasPrefix("Layer:") && !$0.hasPrefix("Color:") }
        default:
            title = "\(selection.count) objects"
            var counts: [String: Int] = [:]
            for entity in selection { counts[entity.typeName, default: 0] += 1 }
            lines = counts.keys.sorted().map { "\($0): \(counts[$0]!)" }
            let curves = selection.compactMap { $0 as? CurveEntity }
            let hatches = selection.compactMap { $0 as? HatchEntity }
            if !curves.isEmpty || !hatches.isEmpty { lines.append("") }
            if !curves.isEmpty {
                let total = curves.reduce(CGFloat(0)) { $0 + $1.curveLength }
                lines.append(String(format: "Total length: %.3f", Double(total)))
            }
            if !hatches.isEmpty {
                let total = hatches.reduce(CGFloat(0)) { $0 + $1.area }
                lines.append(String(format: "Hatch area: %.3f", Double(total)))
            }
        }
        let signature = ([title] + lines).joined(separator: "\u{1}")
        guard signature != lastSignature else { return }
        lastSignature = signature
        rebuild(title: title, lines: lines)
    }

    private func rebuild(title: String, lines: [String]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let heading = NSTextField(labelWithString: title)
        heading.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        heading.textColor = .white
        heading.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(heading)
        stack.setCustomSpacing(6, after: heading)

        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(9, after: last) }
                continue
            }
            // “Label: value” → two columns; otherwise plain text
            if let colon = line.firstIndex(of: ":"), line.distance(from: line.startIndex, to: colon) <= 16 {
                let caption = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                addRow(caption, value)
            } else {
                let label = NSTextField(wrappingLabelWithString: line)
                label.font = NSFont.systemFont(ofSize: 11)
                label.textColor = Theme.textNote
                label.isSelectable = true
                stack.addArrangedSubview(label)
                label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
            }
        }
    }

    private func addRow(_ caption: String, _ value: String) {
        let captionLabel = NSTextField(labelWithString: caption)
        captionLabel.font = NSFont.systemFont(ofSize: 11)
        captionLabel.textColor = Theme.textInfoCaption
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.toolTip = caption
        captionLabel.widthAnchor.constraint(equalToConstant: captionWidth).isActive = true

        let valueLabel = NSTextField(wrappingLabelWithString: value)
        valueLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = Theme.textValue
        valueLabel.isSelectable = true      // the value can be selected and copied
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [captionLabel, valueLabel])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 6
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
    }
}

// MARK: - Properties Panel

final class PropertiesPanelView: NSView {
    /// Changing the layer / color of the selected objects (handled by the controller because of Undo).
    var onChangeLayer: ((String) -> Void)?
    var onChangeColor: ((NSColor?) -> Void)?
    var onChangeLineWeight: ((CGFloat?) -> Void)?
    /// Edits of the selected hatches.
    var onChangeHatchPattern: ((HatchPattern) -> Void)?
    var onChangeHatchAngle: ((CGFloat) -> Void)?
    var onChangeHatchScale: ((CGFloat) -> Void)?
    var onRequestCustomHatchPattern: (() -> Void)?
    var onRebuildHatch: (() -> Void)?
    var onSubtractFromHatch: (() -> Void)?
    /// Editing geometry and other properties: the action name for Undo and a function that turns an object
    /// into an edited copy (nil = the object does not change).
    var onEdit: ((String, @escaping (CADEntity) -> CADEntity?) -> Void)?
    /// Drawing coordinates (UCS → world): positions and angles are shown like in the status bar.
    var ucsToWorld = CGAffineTransform.identity
    private var ucsAngle: CGFloat { return atan2(ucsToWorld.b, ucsToWorld.a) }
    private func shown(_ p: CGPoint) -> CGPoint { return p.applying(ucsToWorld.inverted()) }
    private func stored(_ p: CGPoint) -> CGPoint { return p.applying(ucsToWorld) }
    /// Angle from the drawing X axis in degrees ↔ world angle in radians.
    /// A direction of an object as shown (degrees or gons, a bearing if chosen in Settings – Units.swift).
    private func shownDegrees(_ angle: CGFloat) -> CGFloat {
        return AngleStyle.shown(Geometry.normalizeAngle(angle - ucsAngle) * 180 / .pi, .direction)
    }
    private func storedAngle(_ shown: CGFloat) -> CGFloat {
        return Geometry.normalizeAngle(AngleStyle.degrees(shown, .direction) * .pi / 180 + ucsAngle)
    }
    private var directionTip: String {
        return AngleStyle.bearings ? "Bearings go clockwise from north (the Y axis)" : "Angles go counter-clockwise from the X axis"
    }

    /// X and Y rows of a point in drawing coordinates; `apply` gets the new point in world coordinates.
    private func addPointRows(_ xLabel: String, _ yLabel: String, _ point: CGPoint, tip: String? = nil,
                              apply: @escaping (CGPoint) -> Void) {
        let p = shown(point)
        addNumber(xLabel, p.x, tip: tip) { [weak self] v in
            guard let self = self else { return }
            apply(self.stored(CGPoint(x: v, y: p.y)))
        }
        addNumber(yLabel, p.y, tip: tip) { [weak self] v in
            guard let self = self else { return }
            apply(self.stored(CGPoint(x: p.x, y: v)))
        }
    }
    /// The drawing's blocks (block replacement in Properties).
    var blockDefinitions: (() -> [BlockDefinition])?
    /// Reload an external reference from the file.
    var onReloadXref: ((BlockDefinition) -> Void)?

    private let hatchPatternPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let layerPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let colorPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let weightPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private let scrollView = NSScrollView()
    private let stack = NSStackView()
    /// Actions of the fields created in the last `update` (keeps them alive).
    private var actions: [ControlAction] = []
    /// The selected polyline vertex / spline control point (for editing coordinates).
    private var vertexIndex = 0
    private var vertexEntityID: UUID?

    private let captionWidth: CGFloat = 70

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = Theme.panelBackground.cgColor

        scrollView.frame = bounds
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        addSubview(scrollView)

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = document
        let clip = scrollView.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor)
        ])

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 12, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor)
        ])

        for popup in [layerPopup, colorPopup, weightPopup, hatchPatternPopup] {
            popup.controlSize = .small
            popup.font = NSFont.systemFont(ofSize: 11)
            popup.target = self
        }
        layerPopup.action = #selector(layerChosen(_:))
        colorPopup.action = #selector(colorChosen(_:))
        weightPopup.action = #selector(weightChosen(_:))
        hatchPatternPopup.action = #selector(hatchPatternChosen(_:))
        rebuildWeightPopup()

        colorPopup.addItem(withTitle: "ByLayer")
        for entry in ACIColor.table {
            colorPopup.addItem(withTitle: entry.name)
            colorPopup.lastItem?.image = PropertiesPanelView.swatch(entry.color)
        }
    }

    static func swatch(_ color: NSColor) -> NSImage {
        return NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2).fill()
            return true
        }
    }

    // MARK: Building rows

    private final class FlippedView: NSView {
        override var isFlipped: Bool { return true }
    }

    /// Target of a control's action with a closure.
    private final class ControlAction: NSObject {
        let handler: (NSControl) -> Void
        init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
        @objc func run(_ sender: NSControl) { handler(sender) }
    }

    private func clearRows() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        actions.removeAll()
    }

    private func addSection(_ title: String) {
        let label = NSTextField(labelWithString: title.uppercased())
        label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        label.textColor = Theme.textHeading
        if !stack.arrangedSubviews.isEmpty { stack.setCustomSpacing(12, after: stack.arrangedSubviews.last!) }
        stack.addArrangedSubview(label)
    }

    private func addRow(_ caption: String, _ control: NSView, tip: String? = nil) {
        let label = NSTextField(labelWithString: caption)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = Theme.textLabel
        label.alignment = .right
        label.toolTip = tip
        label.translatesAutoresizingMaskIntoConstraints = false
        label.widthAnchor.constraint(equalToConstant: captionWidth).isActive = true
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.toolTip = control.toolTip ?? tip
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .centerY
        stack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
    }

    /// Numeric field: the value (nil = varies) and what to do with a new value.
    private func addNumber(_ caption: String, _ value: CGFloat?, tip: String? = nil, apply: @escaping (CGFloat) -> Void) {
        let field = NSTextField(string: value.map { LineType.format($0) } ?? "")
        field.placeholderString = value == nil ? "*varies*" : nil
        field.controlSize = .small
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.cell?.sendsActionOnEndEditing = true
        field.toolTip = (tip.map { $0 + "\n" } ?? "") + "Type a value or an expression (e.g. 2*25) and press ↩"
        let original = field.stringValue
        var applied = false     // both Enter and end of editing send the action – use it only once
        let action = ControlAction { control in
            guard !applied, let field = control as? NSTextField else { return }
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, text != original else { return }
            guard let number = ExpressionEvaluator.evaluate(text) else {
                NSSound.beep()
                field.stringValue = original
                return
            }
            applied = true
            apply(CGFloat(number))
        }
        field.target = action
        field.action = #selector(ControlAction.run(_:))
        actions.append(action)
        addRow(caption, field, tip: tip)
    }

    private func addText(_ caption: String, _ value: String, placeholder: String?, apply: @escaping (String) -> Void) {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        field.controlSize = .small
        field.font = NSFont.systemFont(ofSize: 11)
        field.cell?.sendsActionOnEndEditing = true
        let original = value
        var applied = false
        let action = ControlAction { control in
            guard !applied, let field = control as? NSTextField, field.stringValue != original else { return }
            applied = true
            apply(field.stringValue)
        }
        field.target = action
        field.action = #selector(ControlAction.run(_:))
        actions.append(action)
        addRow(caption, field)
    }

    private func addCheck(_ caption: String, _ value: Bool?, apply: @escaping (Bool) -> Void) {
        let check = NSButton(checkboxWithTitle: "", target: nil, action: nil)
        check.allowsMixedState = value == nil
        check.state = value.map { $0 ? .on : .off } ?? .mixed
        let action = ControlAction { control in
            guard let check = control as? NSButton else { return }
            apply(check.state == .on)
        }
        check.target = action
        check.action = #selector(ControlAction.run(_:))
        actions.append(action)
        addRow(caption, check)
    }

    private func addInfo(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular)
        label.textColor = Theme.textSecondary
        label.isSelectable = true
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -20).isActive = true
    }

    /// A change of all selected objects of the given type.
    private func edit<T: CADEntity>(_ name: String, _ type: T.Type, _ change: @escaping (T) -> CADEntity?) {
        onEdit?(name) { entity in
            guard let typed = entity as? T else { return nil }
            return change(typed)
        }
    }

    // MARK: Updating from the selection

    func update(selection: [CADEntity], layerNames: [String]) {
        clearRows()

        // general properties
        addSection("General")
        layerPopup.removeAllItems()
        layerPopup.addItems(withTitles: layerNames)
        let enabled = !selection.isEmpty
        layerPopup.isEnabled = enabled
        colorPopup.isEnabled = enabled
        weightPopup.isEnabled = enabled
        if let first = selection.first {
            if selection.allSatisfy({ $0.layer == first.layer }) {
                layerPopup.selectItem(withTitle: first.layer)
            } else {
                layerPopup.insertItem(withTitle: "*varies*", at: 0)
                layerPopup.selectItem(at: 0)
            }
            rebuildWeightPopup()
            let weights = Set(selection.map { $0.lineWeight.map { LineWeights.title($0) } ?? "ByLayer" })
            if weights.count == 1, let title = weights.first { weightPopup.selectItem(withTitle: title) } else { weightPopup.selectItem(at: -1) }
            let names = Set(selection.map { $0.colorDescription })
            // a color outside the basic menu (e.g. from DXF: “Color 41”) – a temporary item with a swatch
            while let extra = colorPopup.menu?.item(withTag: 99) { colorPopup.menu?.removeItem(extra) }
            if names.count == 1, let name = names.first, colorPopup.item(withTitle: name) == nil, let color = first.color {
                colorPopup.addItem(withTitle: name)
                colorPopup.lastItem?.tag = 99
                colorPopup.lastItem?.image = PropertiesPanelView.swatch(color)
            }
            if names.count == 1, let name = names.first, colorPopup.item(withTitle: name) != nil {
                colorPopup.selectItem(withTitle: name)
            } else {
                colorPopup.selectItem(at: -1)
            }
        }
        addRow("Layer", layerPopup)
        addRow("Color", colorPopup)
        addRow("Weight", weightPopup)
        if !selection.isEmpty {
            let orders = Set(selection.map { $0.drawOrder })
            addNumber("Draw order", orders.count == 1 ? CGFloat(orders.first ?? 0) : nil,
                      tip: "Pseudo Z position: higher numbers are drawn over lower ones (with the same number: images and hatches under lines, wipeouts over them, texts and dimensions on top). Edit › Draw Order: ⇧⌘F front, ⇧⌘B back") { [weak self] value in
                // a sensible range – a huge number would stop the app (and Bring to Front adds 1 to it)
                guard value.isFinite, abs(value) <= 1_000_000 else { NSSound.beep(); return }
                let order = Int(value.rounded())
                self?.onEdit?("Change Draw Order") { entity in
                    guard entity.drawOrder != order else { return nil }
                    let copy = entity.clone()
                    copy.drawOrder = order
                    return copy
                }
            }
        }

        if !selection.isEmpty { addLineTypeScaleRows(for: selection) }

        // hatches
        let hatches = selection.compactMap { $0 as? HatchEntity }
        if !hatches.isEmpty && hatches.count == selection.count, let first = hatches.first {
            addSection("Hatch")
            rebuildHatchPatternPopup()
            if hatches.allSatisfy({ $0.pattern.name == first.pattern.name }) {
                if hatchPatternPopup.item(withTitle: first.pattern.name) == nil {
                    hatchPatternPopup.insertItem(withTitle: first.pattern.name, at: 0)
                }
                hatchPatternPopup.selectItem(withTitle: first.pattern.name)
            } else {
                hatchPatternPopup.selectItem(at: -1)
            }
            addRow("Pattern", hatchPatternPopup)
            let angles = Set(hatches.map { LineType.format($0.angle * 180 / .pi) })
            let scales = Set(hatches.map { LineType.format($0.scale) })
            addNumber(AngleStyle.caption("Angle", .amount), angles.count == 1 ? AngleStyle.shown(first.angle * 180 / .pi, .amount) : nil) { [weak self] value in
                self?.onChangeHatchAngle?(AngleStyle.degrees(value, .amount))
            }
            addNumber("Scale", scales.count == 1 ? first.scale : nil) { [weak self] value in
                guard value > 0 else { NSSound.beep(); return }
                self?.onChangeHatchScale?(value)
            }
            let rebuild = NSButton(title: "Rebuild Hatch", target: nil, action: nil)
            rebuild.toolTip = "The hatch takes the shape of the closed area around it – e.g. after you draw the jambs of an opening"
            let rebuildAction = ControlAction { [weak self] _ in self?.onRebuildHatch?() }
            rebuild.target = rebuildAction
            rebuild.action = #selector(ControlAction.run(_:))
            actions.append(rebuildAction)
            let subtract = NSButton(title: "Cut Out of Hatch", target: nil, action: nil)
            subtract.toolTip = "Select the hatch together with closed shapes (rectangle, circle, closed polyline) – they are cut out of it"
            let subtractAction = ControlAction { [weak self] _ in self?.onSubtractFromHatch?() }
            subtract.target = subtractAction
            subtract.action = #selector(ControlAction.run(_:))
            actions.append(subtractAction)
            for button in [rebuild, subtract] {
                button.controlSize = .small
                button.bezelStyle = .push
                button.font = NSFont.systemFont(ofSize: 11)
            }
            addRow("Boundary", rebuild)
            addRow("", subtract)
            addInfo("Edit points: drag the blue grips · Cut out: select the hatch and a closed shape over it")
        }

        // revision clouds (polylines whose arcs are all alike – RevisionCloud.swift)
        let clouds = selection.compactMap { $0 as? Polyline }.filter { RevisionCloud.isCloud($0) }
        if !clouds.isEmpty && clouds.count == selection.count, let first = clouds.first {
            addSection("Revision Cloud")
            let unit = RevisionCloud.defaultArcSizeMM * max(unitsPerPaperMM?() ?? 1, 1e-9)
            let scales = Set(clouds.map { LineType.format(RevisionCloud.scale(of: $0, unit: unit)) })
            addNumber("Scale", scales.count == 1 ? RevisionCloud.scale(of: first, unit: unit) : nil,
                      tip: "Size of the arcs: 1 = \(LineType.format(RevisionCloud.defaultArcSizeMM)) mm on paper at the drawing scale, 2 = twice as large; the outline stays") { [weak self] value in
                guard value > 0 else { NSSound.beep(); return }
                self?.edit("Change Revision Cloud Scale", Polyline.self) { RevisionCloud.rescaled($0, arcSize: value * unit) }
            }
        }

        // hatch + closed shapes: offer cutting them out
        if selection.contains(where: { $0 is HatchEntity }),
           selection.contains(where: { ($0 as? CurveEntity)?.isClosedCurve ?? false }) {
            addSection("Hatch")
            let cut = NSButton(title: "Cut Out of Hatch", target: nil, action: nil)
            cut.controlSize = .small
            cut.bezelStyle = .push
            cut.font = NSFont.systemFont(ofSize: 11)
            cut.toolTip = "The selected closed shapes are cut out of the selected hatch (the shapes stay)"
            let cutAction = ControlAction { [weak self] _ in self?.onSubtractFromHatch?() }
            cut.target = cutAction
            cut.action = #selector(ControlAction.run(_:))
            actions.append(cutAction)
            addRow("", cut)
        }

        // geometry (information about the object is in the Info panel)
        addGeometry(for: selection)
    }

    /// Linetype scale of the objects; for the Batting line type also the insulation thickness it gives.
    private func addLineTypeScaleRows(for selection: [CADEntity]) {
        let scales = Set(selection.map { LineType.format($0.lineTypeScale ?? 1) })
        let firstScale = selection.first?.lineTypeScale ?? 1
        let change: (String, @escaping (CADEntity) -> CGFloat?) -> Void = { [weak self] name, newScale in
            self?.onEdit?(name) { entity in
                guard let scale = newScale(entity) else { return nil }
                let value: CGFloat? = abs(scale - 1) < 1e-9 ? nil : scale
                guard entity.lineTypeScale != value else { return nil }
                let copy = entity.clone()
                copy.lineTypeScale = value
                return copy
            }
        }
        addNumber("Line scale", scales.count == 1 ? firstScale : nil,
                  tip: "Linetype scale of the object: multiplies the dashes, texts and shapes of its layer's linetype (1 = as defined)") { value in
            guard value > 0 else { NSSound.beep(); return }
            change("Change Linetype Scale") { _ in value }
        }
        // insulation (Batting): the thickness in drawing units instead of a scale
        let widths = selection.map { lineTypeOf?($0).battingWidth }
        guard let firstWidth = widths.first ?? nil, widths.allSatisfy({ $0 != nil }) else { return }
        let unit = max(unitsPerPaperMM?() ?? 1, 1e-9)
        func thickness(_ entity: CADEntity, width: CGFloat) -> CGFloat { return width * unit * (entity.lineTypeScale ?? 1) }
        let thicknesses = Set(zip(selection, widths).map { LineType.format(thickness($0, width: $1 ?? firstWidth)) })
        addNumber("Thickness", thicknesses.count == 1 ? thickness(selection[0], width: firstWidth) : nil,
                  tip: "Thickness of the insulation in drawing units – the line is its middle; it sets the linetype scale") { [weak self] value in
            guard value > 0 else { NSSound.beep(); return }
            change("Change Insulation Thickness") { entity in
                guard let width = self?.lineTypeOf?(entity).battingWidth, width > 0 else { return nil }
                return value / (width * unit)
            }
        }
    }

    private func addGeometry(for selection: [CADEntity]) {
        // several circles / dimensions at once: common values
        if selection.count > 1 {
            if selection.allSatisfy({ $0 is Circle }) {
                let circles = selection.compactMap { $0 as? Circle }
                let radius = Set(circles.map { LineType.format($0.radius) }).count == 1 ? circles[0].radius : nil
                addSection("Circles")
                addNumber("Radius", radius) { [weak self] r in
                    guard r > 0 else { NSSound.beep(); return }
                    self?.edit("Change Radius", Circle.self) { c in let copy = c.clone() as! Circle; copy.radius = r; return copy }
                }
                addNumber("Diameter", radius.map { $0 * 2 }) { [weak self] d in
                    guard d > 0 else { NSSound.beep(); return }
                    self?.edit("Change Diameter", Circle.self) { c in let copy = c.clone() as! Circle; copy.radius = d / 2; return copy }
                }
            } else if selection.allSatisfy({ $0 is DimensionEntity }) {
                addDimensionRows(selection.compactMap { $0 as? DimensionEntity })
            } else if selection.allSatisfy({ $0 is TextEntity }) {
                addTextRows(selection.compactMap { $0 as? TextEntity })
            } else if selection.allSatisfy({ $0 is ImageEntity }) {
                addImageRows(selection.compactMap { $0 as? ImageEntity })
            }
            return
        }
        guard let entity = selection.first else { return }

        switch entity {
        case let line as Line:
            addSection("Line")
            addPointRows("Start X", "Start Y", line.startPoint) { [weak self] p in
                self?.edit("Move Start Point", Line.self) { l in let c = l.clone() as! Line; c.startPoint = p; return c }
            }
            addPointRows("End X", "End Y", line.endPoint) { [weak self] p in
                self?.edit("Move End Point", Line.self) { l in let c = l.clone() as! Line; c.endPoint = p; return c }
            }
            let angle = Geometry.angle(from: line.startPoint, to: line.endPoint)
            addNumber("Length", line.length, tip: "The start point stays, the direction is kept") { [weak self] length in
                guard length > 0 else { NSSound.beep(); return }
                self?.edit("Change Length", Line.self) { l in
                    let c = l.clone() as! Line
                    c.endPoint = Geometry.pointOnCircle(l.startPoint, length, Geometry.angle(from: l.startPoint, to: l.endPoint))
                    return c
                }
            }
            addNumber(AngleStyle.caption("Angle", .direction), shownDegrees(angle), tip: "Rotates the line around its start point") { [weak self] degrees in
                guard let self = self else { return }
                let world = self.storedAngle(degrees)
                self.edit("Change Angle", Line.self) { l in
                    let c = l.clone() as! Line
                    c.endPoint = Geometry.pointOnCircle(l.startPoint, l.length, world)
                    return c
                }
            }

        case let circle as Circle:
            addSection("Circle")
            addPointRows("Center X", "Center Y", circle.center) { [weak self] p in
                self?.edit("Move Circle", Circle.self) { o in let c = o.clone() as! Circle; c.center = p; return c }
            }
            addNumber("Radius", circle.radius) { [weak self] r in
                guard r > 0 else { NSSound.beep(); return }
                self?.edit("Change Radius", Circle.self) { o in let c = o.clone() as! Circle; c.radius = r; return c }
            }
            addNumber("Diameter", circle.radius * 2) { [weak self] d in
                guard d > 0 else { NSSound.beep(); return }
                self?.edit("Change Diameter", Circle.self) { o in let c = o.clone() as! Circle; c.radius = d / 2; return c }
            }

        case let arc as Arc:
            addSection("Arc")
            addPointRows("Center X", "Center Y", arc.center) { [weak self] p in
                self?.edit("Move Arc", Arc.self) { o in let c = o.clone() as! Arc; c.center = p; return c }
            }
            addNumber("Radius", arc.radius) { [weak self] r in
                guard r > 0 else { NSSound.beep(); return }
                self?.edit("Change Radius", Arc.self) { o in let c = o.clone() as! Arc; c.radius = r; return c }
            }
            addNumber(AngleStyle.caption("Start", .direction), shownDegrees(arc.startAngle), tip: directionTip) { [weak self] v in
                guard let self = self else { return }
                let world = self.storedAngle(v)
                self.edit("Change Arc", Arc.self) { o in let c = o.clone() as! Arc; c.startAngle = world; return c }
            }
            addNumber(AngleStyle.caption("End", .direction), shownDegrees(arc.endAngle), tip: directionTip) { [weak self] v in
                guard let self = self else { return }
                let world = self.storedAngle(v)
                self.edit("Change Arc", Arc.self) { o in let c = o.clone() as! Arc; c.endAngle = world; return c }
            }

        case let polyline as Polyline:
            if let box = PropertiesPanelView.rectangleBox(polyline) {
                addSection("Rectangle")
                // with a rotated UCS the corner is not “lower-left” in drawing coordinates – the vertex rows remain
                if abs(ucsAngle) < 1e-12 {
                    addPointRows("X", "Y", box.origin, tip: "Lower-left corner") { [weak self] p in
                        self?.editRectangle { $0.origin = p }
                    }
                }
                addNumber("Width", box.width, tip: "The lower-left corner stays") { [weak self] v in
                    guard v > 0 else { NSSound.beep(); return }
                    self?.editRectangle { $0.size.width = v }
                }
                addNumber("Height", box.height, tip: "The lower-left corner stays") { [weak self] v in
                    guard v > 0 else { NSSound.beep(); return }
                    self?.editRectangle { $0.size.height = v }
                }
            }
            addSection("Polyline")
            addCheck("Closed", polyline.closed) { [weak self] closed in
                self?.edit("Change Closed", Polyline.self) { p in
                    guard p.vertices.count >= 3 || !closed else { return nil }
                    let c = p.clone() as! Polyline
                    c.closed = closed
                    return c
                }
            }
            addNumber("Polyline Width", polyline.width,
                      tip: "Width of the polyline in drawing units, drawn as a band \u{2013} 0 = a thin line with its lineweight") { [weak self] v in
                guard v >= 0 else { NSSound.beep(); return }
                self?.edit("Change Polyline Width", Polyline.self) { p in
                    let c = p.clone() as! Polyline
                    c.width = v
                    return c
                }
            }
            addVertexRows(polyline.id, polyline.vertices, noun: "Vertex") { [weak self] index, point in
                self?.edit("Move Vertex", Polyline.self) { p in
                    guard index < p.vertices.count else { return nil }
                    let c = p.clone() as! Polyline
                    c.vertices[index] = point
                    return c
                }
            }

        case let spline as Spline:
            addSection("Spline")
            addCheck("Closed", spline.closed) { [weak self] closed in
                self?.edit("Change Closed", Spline.self) { s in
                    let c = Spline(controlPoints: s.controlPoints, closed: closed, layer: s.layer, color: s.color)
                    return s.copyStyle(to: c)
                }
            }
            addVertexRows(spline.id, spline.controlPoints, noun: "Point") { [weak self] index, point in
                self?.edit("Move Point", Spline.self) { s in
                    guard index < s.controlPoints.count else { return nil }
                    var points = s.controlPoints
                    points[index] = point
                    return s.copyStyle(to: Spline(controlPoints: points, closed: s.closed, layer: s.layer, color: s.color))
                }
            }

        case let ellipse as Ellipse:
            addSection(ellipse.typeName)
            func rebuilt(_ e: Ellipse, center: CGPoint? = nil, major: CGFloat? = nil, minor: CGFloat? = nil,
                         rotation: CGFloat? = nil, start: CGFloat? = nil, end: CGFloat? = nil) -> CADEntity? {
                let a = major ?? e.majorRadius, b = minor ?? e.minorRadius
                guard a > 0, b > 0 else { NSSound.beep(); return nil }
                let angle = rotation ?? e.rotation
                let copy = Ellipse(center: center ?? e.center, majorAxis: CGPoint(x: cos(angle) * a, y: sin(angle) * a),
                                   ratio: b / a, startParam: start ?? e.startParam, endParam: end ?? e.endParam,
                                   layer: e.layer, color: e.color)
                return copy.withStyle(of: e)
            }
            addPointRows("Center X", "Center Y", ellipse.center) { [weak self] p in
                self?.edit("Move Ellipse", Ellipse.self) { e in rebuilt(e, center: p) }
            }
            addNumber("Major r.", ellipse.majorRadius, tip: "Half of the long axis") { [weak self] v in
                self?.edit("Change Ellipse", Ellipse.self) { e in rebuilt(e, major: v) }
            }
            addNumber("Minor r.", ellipse.minorRadius, tip: "Half of the short axis") { [weak self] v in
                self?.edit("Change Ellipse", Ellipse.self) { e in rebuilt(e, minor: v) }
            }
            addNumber(AngleStyle.caption("Rotation", .direction), shownDegrees(ellipse.rotation),
                      tip: "Direction of the major axis \u{2013} " + directionTip.lowercased()) { [weak self] v in
                guard let self = self else { return }
                let world = self.storedAngle(v)
                self.edit("Change Rotation", Ellipse.self) { e in rebuilt(e, rotation: world) }
            }
            if !ellipse.isFull {
                addNumber(AngleStyle.caption("Start", .amount), AngleStyle.shown(ellipse.startParam * 180 / .pi, .amount),
                          tip: "Parametric angle of the start of the arc") { [weak self] v in
                    self?.edit("Change Elliptical Arc", Ellipse.self) { e in rebuilt(e, start: AngleStyle.degrees(v, .amount) * .pi / 180) }
                }
                addNumber(AngleStyle.caption("End", .amount), AngleStyle.shown(ellipse.endParam * 180 / .pi, .amount),
                          tip: "Parametric angle of the end of the arc") { [weak self] v in
                    self?.edit("Change Elliptical Arc", Ellipse.self) { e in rebuilt(e, end: AngleStyle.degrees(v, .amount) * .pi / 180) }
                }
            }

        case let dimension as DimensionEntity:
            addDimensionRows([dimension])

        case let reference as BlockReference:
            addBlockRows(reference)

        case let viewport as ViewportEntity:
            addViewportRows(viewport)

        case let text as TextEntity:
            addTextRows([text])

        case let image as ImageEntity:
            addImageRows([image])

        default:
            break
        }
    }

    /// Images and PDF underlays: the file and the opacity (for all selected ones).
    private func addImageRows(_ images: [ImageEntity]) {
        guard let first = images.first else { return }
        addSection(images.allSatisfy { $0.isPDF } ? "PDF Underlay" : "Image")
        if images.count == 1 {
            addInfo(first.fileName + (first.isPDF ? " · page \(first.page)" : "") + (first.picture == nil ? "\n⚠︎ The picture could not be read" : ""))
        }
        let same = images.allSatisfy { $0.opacity == first.opacity }
        addNumber("Opacity %", same ? first.opacity * 100 : nil, tip: "100 = opaque · less = faded, easier to draw over (5–100)") { [weak self] v in
            guard v >= 5 && v <= 100 else { NSSound.beep(); return }
            self?.edit("Change Opacity", ImageEntity.self) { o in
                guard abs(o.opacity * 100 - v) > 1e-9 else { return nil }
                let c = o.clone() as! ImageEntity
                c.opacity = v / 100
                return c
            }
        }
    }

    private func addBlockRows(_ reference: BlockReference) {
        let definition = reference.definition
        addSection(definition.isExternal ? "External Reference" : "Block")
        if definition.isExternal {
            addInfo("“\(definition.name)” – \(definition.source?.fileName ?? "")" + (definition.source?.error.map { "\n⚠︎ \($0)" } ?? ""))
        } else {
            // replacing a block with another (same insertion point, rotation and scale)
            let popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.controlSize = .small
            popup.font = NSFont.systemFont(ofSize: 11)
            let blocks = blockDefinitions?() ?? [definition]
            popup.addItems(withTitles: blocks.map { $0.name })
            popup.selectItem(withTitle: definition.name)
            let action = ControlAction { [weak self] control in
                guard let popup = control as? NSPopUpButton, blocks.indices.contains(popup.indexOfSelectedItem) else { return }
                let chosen = blocks[popup.indexOfSelectedItem]
                self?.edit("Change Block", BlockReference.self) { r in
                    guard r.definition !== chosen else { return nil }
                    let c = r.clone() as! BlockReference
                    c.definition = chosen
                    return c
                }
            }
            popup.target = action
            popup.action = #selector(ControlAction.run(_:))
            actions.append(action)
            addRow("Block", popup, tip: "Swap for another block – the position, rotation and scale stay")
        }
        addPointRows("X", "Y", reference.position, tip: "Insertion point") { [weak self] p in
            self?.edit("Move Block", BlockReference.self) { r in let c = r.clone() as! BlockReference; c.position = p; return c }
        }
        addNumber(AngleStyle.caption("Rotation", .direction), shownDegrees(reference.rotation)) { [weak self] v in
            guard let self = self else { return }
            let world = self.storedAngle(v)
            self.edit("Change Rotation", BlockReference.self) { r in
                let c = r.clone() as! BlockReference
                c.rotation = world
                return c
            }
        }
        addNumber(reference.isStretched ? "X Scale" : "Scale", reference.scale,
                  tip: reference.isStretched ? "1 = original size \u{2013} the Y scale changes in the same proportion" : "1 = original size") { [weak self] v in
            guard v > 0 else { NSSound.beep(); return }
            self?.edit("Change Scale", BlockReference.self) { r in let c = r.clone() as! BlockReference; c.scale = v; return c }
        }
        if reference.isStretched {
            // a block stretched differently in X and Y (from DXF) – Y Scale = X Scale makes it uniform again
            addNumber("Y Scale", reference.scale * reference.yRatio, tip: "The same value as X Scale makes the block uniform again") { [weak self] v in
                guard v > 0 else { NSSound.beep(); return }
                self?.edit("Change Scale", BlockReference.self) { r in
                    let c = r.clone() as! BlockReference
                    c.yRatio = v / max(c.scale, 1e-12)
                    return c
                }
            }
        }
        addCheck("Mirrored", reference.mirrored) { [weak self] value in
            self?.edit("Change Mirroring", BlockReference.self) { r in
                guard r.mirrored != value else { return nil }
                let c = r.clone() as! BlockReference
                c.mirrored = value
                return c
            }
        }
        if definition.isExternal {
            let reload = NSButton(title: "Reload from File", target: nil, action: nil)
            reload.controlSize = .small
            reload.bezelStyle = .push
            reload.font = NSFont.systemFont(ofSize: 11)
            let reloadAction = ControlAction { [weak self] _ in self?.onReloadXref?(definition) }
            reload.target = reloadAction
            reload.action = #selector(ControlAction.run(_:))
            actions.append(reloadAction)
            addRow("", reload)
            addInfo("Updates by itself when the file is saved · Insert › Block Manager… can bind it as a block")
        } else {
            addInfo("Explode" + (DrawingTool.explode.shortcut.map { " (\($0))" } ?? "") + " turns it back into objects · Insert › Block Manager… renames or deletes blocks")
        }
    }

    /// Editing text in a dialog (double-click / Edit… button) – supplied by the main window.
    var onEditText: ((TextEntity) -> Void)?

    private func addTextRows(_ texts: [TextEntity]) {
        guard let first = texts.first else { return }
        addSection(texts.count == 1 ? "Text" : "Texts")
        let same = { (value: (TextEntity) -> String) in Set(texts.map(value)).count == 1 }
        if texts.count == 1 {
            if !first.text.contains("\n") {
                addText("Content", first.text, placeholder: "Text") { [weak self] value in
                    guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { NSSound.beep(); return }
                    self?.edit("Change Text", TextEntity.self) { t in let c = t.clone() as! TextEntity; c.text = value; return c }
                }
            }
            let editButton = NSButton(title: "Edit on Drawing", target: nil, action: nil)
            editButton.toolTip = "Edit the text where it is – the ☰ menu next to it opens the format"
            editButton.controlSize = .small
            editButton.bezelStyle = .push
            editButton.font = NSFont.systemFont(ofSize: 11)
            let editAction = ControlAction { [weak self] _ in self?.onEditText?(first) }
            editButton.target = editAction
            editButton.action = #selector(ControlAction.run(_:))
            actions.append(editAction)
            addRow("", editButton)
        }

        // font and style
        let familyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        familyPopup.controlSize = .small
        familyPopup.font = NSFont.systemFont(ofSize: 11)
        familyPopup.addItem(withTitle: FontLibrary.systemFamilyTitle)
        familyPopup.menu?.addItem(.separator())
        familyPopup.addItems(withTitles: FontLibrary.families)
        if same({ $0.fontFamily }) {
            if first.fontFamily.isEmpty { familyPopup.selectItem(at: 0) } else { familyPopup.selectItem(withTitle: first.fontFamily) }
        } else {
            familyPopup.selectItem(at: -1)
        }
        let familyAction = ControlAction { [weak self] control in
            guard let popup = control as? NSPopUpButton else { return }
            let family = popup.indexOfSelectedItem <= 0 ? "" : (popup.titleOfSelectedItem ?? "")
            let faces = FontLibrary.faces(of: family)
            self?.edit("Change Font", TextEntity.self) { t in
                let c = t.clone() as! TextEntity
                c.fontFamily = family
                if !faces.contains(c.fontFace) {
                    c.fontFace = faces.first(where: { ["Regular", "Roman", "Book", "Medium"].contains($0) }) ?? faces.first ?? "Regular"
                }
                return c
            }
        }
        familyPopup.target = familyAction
        familyPopup.action = #selector(ControlAction.run(_:))
        actions.append(familyAction)
        addRow("Font", familyPopup)

        let facePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        facePopup.controlSize = .small
        facePopup.font = NSFont.systemFont(ofSize: 11)
        if same({ $0.fontFamily }) {
            facePopup.addItems(withTitles: FontLibrary.faces(of: first.fontFamily))
            if same({ $0.fontFace }) { facePopup.selectItem(withTitle: first.fontFace) } else { facePopup.selectItem(at: -1) }
        } else {
            facePopup.isEnabled = false
        }
        let faceAction = ControlAction { [weak self] control in
            guard let popup = control as? NSPopUpButton, let face = popup.titleOfSelectedItem else { return }
            self?.edit("Change Typeface", TextEntity.self) { t in let c = t.clone() as! TextEntity; c.fontFace = face; return c }
        }
        facePopup.target = faceAction
        facePopup.action = #selector(ControlAction.run(_:))
        actions.append(faceAction)
        addRow("Typeface", facePopup)

        addNumber("Height", same({ LineType.format($0.height) }) ? first.height : nil, tip: "Height of capital letters in drawing units") { [weak self] v in
            guard v > 0 else { NSSound.beep(); return }
            self?.edit("Change Text Height", TextEntity.self) { t in let c = t.clone() as! TextEntity; c.height = v; return c }
        }
        addNumber(AngleStyle.caption("Rotation", .direction), same({ LineType.format($0.rotation * 180 / .pi) }) ? shownDegrees(first.rotation) : nil) { [weak self] v in
            guard let self = self else { return }
            let world = self.storedAngle(v)
            self.edit("Change Rotation", TextEntity.self) { t in
                let c = t.clone() as! TextEntity; c.rotation = world; return c
            }
        }

        let justify = NSSegmentedControl(labels: TextJustify.allCases.map { $0.title }, trackingMode: .selectOne, target: nil, action: nil)
        justify.controlSize = .small
        justify.font = NSFont.systemFont(ofSize: 10)
        justify.selectedSegment = same({ $0.justify.rawValue }) ? (TextJustify.allCases.firstIndex(of: first.justify) ?? 0) : -1
        let justifyAction = ControlAction { [weak self] control in
            guard let segmented = control as? NSSegmentedControl, segmented.selectedSegment >= 0 else { return }
            let value = TextJustify.allCases[segmented.selectedSegment]
            self?.edit("Change Text Alignment", TextEntity.self) { t in let c = t.clone() as! TextEntity; c.justify = value; return c }
        }
        justify.target = justifyAction
        justify.action = #selector(ControlAction.run(_:))
        actions.append(justifyAction)
        addRow("Alignment", justify)

        addCheck("Underline", same({ $0.underline ? "1" : "0" }) ? first.underline : nil) { [weak self] on in
            self?.edit("Change Underline", TextEntity.self) { t in let c = t.clone() as! TextEntity; c.underline = on; return c }
        }
        addNumber("Width", same({ $0.boxWidth.map { LineType.format($0) } ?? "-" }) ? (first.boxWidth ?? 0) : nil,
                  tip: "Paragraph width in drawing units – longer lines wrap. 0 = no wrapping") { [weak self] v in
            self?.edit("Change Text Width", TextEntity.self) { t in let c = t.clone() as! TextEntity; c.boxWidth = v > 0 ? v : nil; return c }
        }
        if texts.count == 1 {
            addPointRows("X", "Y", first.position) { [weak self] p in
                self?.edit("Move Text", TextEntity.self) { t in let c = t.clone() as! TextEntity; c.position = p; return c }
            }
        }
    }

    /// Model bounds (for “Fit model” of a viewport) – supplied by the main window.
    var modelExtents: (() -> CGRect?)?
    /// Model layers (for hiding in a viewport).
    var modelLayerNames: (() -> [String])?
    /// Drawing units per mm on paper at the drawing scale (the arc size of revision clouds, insulation thickness).
    var unitsPerPaperMM: (() -> CGFloat)?
    /// The line type an object is drawn with (by its layer).
    var lineTypeOf: ((CADEntity) -> LineType)?

    private func addViewportRows(_ viewport: ViewportEntity) {
        addSection("Viewport")
        addText("Scale", viewport.scale.title, placeholder: "1:50") { [weak self] text in
            guard let scale = PlotDialog.parseScale(text) else { NSSound.beep(); self?.needsVertexRefresh?(); return }
            self?.edit("Change Viewport Scale", ViewportEntity.self) { v in
                guard !v.isLocked else { return nil }
                let c = v.clone() as! ViewportEntity
                c.scale = scale
                return c
            }
        }
        let presets = NSPopUpButton(frame: .zero, pullsDown: true)
        presets.controlSize = .small
        presets.font = NSFont.systemFont(ofSize: 11)
        presets.addItem(withTitle: "Standard scales")
        for scale in DrawingScale.presets { presets.addItem(withTitle: scale.title) }
        let choose = ControlAction { [weak self] control in
            guard let popup = control as? NSPopUpButton, popup.indexOfSelectedItem > 0 else { return }
            let scale = DrawingScale.presets[popup.indexOfSelectedItem - 1]
            self?.edit("Change Viewport Scale", ViewportEntity.self) { v in
                guard !v.isLocked else { return nil }
                let c = v.clone() as! ViewportEntity
                c.scale = scale
                return c
            }
        }
        presets.target = choose
        presets.action = #selector(ControlAction.run(_:))
        actions.append(choose)
        addRow("", presets)

        addNumber("Model X", viewport.modelCenter.x, tip: "Model point in the middle of the viewport") { [weak self] v in
            self?.edit("Pan Viewport", ViewportEntity.self) { o in
                guard !o.isLocked else { return nil }
                let c = o.clone() as! ViewportEntity; c.modelCenter.x = v; return c
            }
        }
        addNumber("Model Y", viewport.modelCenter.y, tip: "Model point in the middle of the viewport") { [weak self] v in
            self?.edit("Pan Viewport", ViewportEntity.self) { o in
                guard !o.isLocked else { return nil }
                let c = o.clone() as! ViewportEntity; c.modelCenter.y = v; return c
            }
        }
        addNumber("Width mm", viewport.rect.width, tip: "Size on paper – the left edge stays") { [weak self] w in
            guard w > 1 else { NSSound.beep(); return }
            self?.edit("Change Viewport Size", ViewportEntity.self) { o in
                let c = o.clone() as! ViewportEntity
                c.rect.size.width = w
                c.modelCenter.x += (w - o.rect.width) / 2 / max(o.paperMMPerUnit(), 1e-12)
                return c
            }
        }
        addNumber("Height mm", viewport.rect.height, tip: "Size on paper – the bottom edge stays") { [weak self] h in
            guard h > 1 else { NSSound.beep(); return }
            self?.edit("Change Viewport Size", ViewportEntity.self) { o in
                let c = o.clone() as! ViewportEntity
                c.rect.size.height = h
                c.modelCenter.y += (h - o.rect.height) / 2 / max(o.paperMMPerUnit(), 1e-12)
                return c
            }
        }
        addCheck("Locked", viewport.isLocked) { [weak self] locked in
            self?.edit("Change Viewport Lock", ViewportEntity.self) { o in
                let c = o.clone() as! ViewportEntity; c.isLocked = locked; return c
            }
        }

        // layers hidden only in this viewport
        let layers = NSPopUpButton(frame: .zero, pullsDown: true)
        layers.controlSize = .small
        layers.font = NSFont.systemFont(ofSize: 11)
        let hidden = viewport.frozenLayers
        layers.addItem(withTitle: hidden.isEmpty ? "All layers shown" : "\(hidden.count) layer\(hidden.count == 1 ? "" : "s") hidden")
        for name in modelLayerNames?() ?? [] {
            layers.addItem(withTitle: name)
            layers.lastItem?.state = hidden.contains(name) ? .off : .on
            layers.lastItem?.representedObject = name
        }
        layers.toolTip = "Checked layers are shown in this viewport; uncheck to hide a layer here only"
        let toggle = ControlAction { [weak self] control in
            guard let popup = control as? NSPopUpButton, let name = popup.selectedItem?.representedObject as? String else { return }
            self?.edit("Change Viewport Layers", ViewportEntity.self) { o in
                let c = o.clone() as! ViewportEntity
                if c.frozenLayers.contains(name) { c.frozenLayers.remove(name) } else { c.frozenLayers.insert(name) }
                return c
            }
        }
        layers.target = toggle
        layers.action = #selector(ControlAction.run(_:))
        actions.append(toggle)
        addRow("Layers", layers)

        let fit = NSButton(title: "Fit Model", target: nil, action: nil)
        fit.controlSize = .small
        fit.bezelStyle = .push
        fit.font = NSFont.systemFont(ofSize: 11)
        fit.toolTip = "Center the whole model and pick the largest standard scale that fits"
        let fitAction = ControlAction { [weak self] _ in
            guard let box = self?.modelExtents?() else { NSSound.beep(); return }
            self?.edit("Change Viewport Scale", ViewportEntity.self) { o in
                guard !o.isLocked else { return nil }
                let c = o.clone() as! ViewportEntity
                c.modelCenter = CGPoint(x: box.midX, y: box.midY)
                c.scale = ViewportEntity.fittingScale(for: box, in: o.rect, mmPerUnit: o.mmPerUnit)
                return c
            }
        }
        fit.target = fitAction
        fit.action = #selector(ControlAction.run(_:))
        actions.append(fitAction)
        addRow("", fit)
        addInfo("⌥-drag inside the viewport pans the model · double-click opens the model there")
    }

    /// Vertex selection (with arrows) and its coordinates.
    private func addVertexRows(_ id: UUID, _ points: [CGPoint], noun: String,
                               apply: @escaping (Int, CGPoint) -> Void) {
        guard !points.isEmpty else { return }
        if vertexEntityID != id { vertexIndex = 0; vertexEntityID = id }
        vertexIndex = min(vertexIndex, points.count - 1)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.controlSize = .small
        popup.font = NSFont.systemFont(ofSize: 11)
        for i in points.indices { popup.addItem(withTitle: "\(noun) \(i + 1) of \(points.count)") }
        popup.selectItem(at: vertexIndex)
        let choose = ControlAction { [weak self] control in
            guard let self = self, let popup = control as? NSPopUpButton else { return }
            self.vertexIndex = popup.indexOfSelectedItem
            self.needsVertexRefresh?()
        }
        popup.target = choose
        popup.action = #selector(ControlAction.run(_:))
        actions.append(choose)
        addRow(noun, popup)

        let index = vertexIndex
        let point = points[index]
        addPointRows("\(noun) X", "\(noun) Y", point) { p in apply(index, p) }
    }

    /// After the selected vertex changes, the panel needs to be rebuilt (the controller calls update).
    var needsVertexRefresh: (() -> Void)?

    private func addDimensionRows(_ dimensions: [DimensionEntity]) {
        guard let first = dimensions.first else { return }
        addSection(dimensions.count == 1 ? "Dimension" : "Dimensions")
        let same = { (value: (DimensionEntity) -> String) in Set(dimensions.map(value)).count == 1 }
        if dimensions.count == 1 {
            let isLeader = first.kind == .leader
            addText(isLeader ? "Text" : "Above", first.text,
                    placeholder: isLeader ? "Leader text" : "\(first.measuredText) (measured)") { [weak self] text in
                self?.edit("Change Dimension Text", DimensionEntity.self) { d in
                    let c = d.clone() as! DimensionEntity
                    c.text = text
                    return c
                }
            }
        }
        if !dimensions.contains(where: { $0.kind == .leader }) {
            if dimensions.count == 1 {
                addInfo("Above: empty = measured value · <> inserts it (e.g. <> HEB)")
            }
            addText("Below", same({ $0.belowText }) ? first.belowText : "",
                    placeholder: same({ $0.belowText }) ? "e.g. 1500 (window height)" : "*varies*") { [weak self] text in
                self?.edit("Change Text Below Dimension", DimensionEntity.self) { d in
                    let c = d.clone() as! DimensionEntity
                    c.belowText = text.trimmingCharacters(in: .whitespaces)
                    return c
                }
            }
        }
        addNumber("Text height", same({ LineType.format($0.textHeight) }) ? first.textHeight : nil,
                  tip: "Height of capital letters in drawing units") { [weak self] v in
            guard v > 0 else { NSSound.beep(); return }
            self?.edit("Change Text Height", DimensionEntity.self) { d in let c = d.clone() as! DimensionEntity; c.textHeight = v; return c }
        }
        let endsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        endsPopup.controlSize = .small
        endsPopup.font = NSFont.systemFont(ofSize: 11)
        for style in DimArrowStyle.allCases {
            endsPopup.addItem(withTitle: style.title)
            endsPopup.lastItem?.image = ToolIcons.image(for: style, size: 16)
        }
        if same({ $0.arrowStyle.rawValue }) {
            endsPopup.selectItem(at: DimArrowStyle.allCases.firstIndex(of: first.arrowStyle) ?? 0)
        } else {
            endsPopup.selectItem(at: -1)
        }
        let endsAction = ControlAction { [weak self] control in
            guard let popup = control as? NSPopUpButton, popup.indexOfSelectedItem >= 0 else { return }
            let style = DimArrowStyle.allCases[popup.indexOfSelectedItem]
            self?.edit("Change Dimension Ends", DimensionEntity.self) { d in
                guard d.arrowStyle != style else { return nil }
                let c = d.clone() as! DimensionEntity
                c.arrowStyle = style
                return c
            }
        }
        endsPopup.target = endsAction
        endsPopup.action = #selector(ControlAction.run(_:))
        actions.append(endsAction)
        addRow("Ends", endsPopup, tip: "Arrow, oblique tick (architecture), dot…")
        addNumber("Arrow size", same({ LineType.format($0.arrowSize) }) ? first.arrowSize : nil) { [weak self] v in
            guard v >= 0 else { NSSound.beep(); return }
            self?.edit("Change Arrow Size", DimensionEntity.self) { d in let c = d.clone() as! DimensionEntity; c.arrowSize = v; return c }
        }
        addNumber("Decimals", same({ "\($0.precision)" }) ? CGFloat(first.precision) : nil) { [weak self] v in
            guard v.isFinite, v >= 0, v <= 8 else { NSSound.beep(); return }
            let decimals = Int(v.rounded())
            self?.edit("Change Decimals", DimensionEntity.self) { d in let c = d.clone() as! DimensionEntity; c.precision = decimals; return c }
        }
        // associativity: the dimension follows the objects its points are attached to
        let linked = dimensions.filter { !$0.links.isEmpty }.count
        if linked > 0 {
            let release = NSButton(title: "Disassociate", target: nil, action: nil)
            release.controlSize = .small
            release.bezelStyle = .push
            release.font = NSFont.systemFont(ofSize: 11)
            release.toolTip = "The dimension stops following the objects it is snapped to"
            let releaseAction = ControlAction { [weak self] _ in
                self?.edit("Change Dimension Association", DimensionEntity.self) { d in
                    guard !d.links.isEmpty else { return nil }
                    let c = d.clone() as! DimensionEntity
                    c.links = [:]
                    return c
                }
            }
            release.target = releaseAction
            release.action = #selector(ControlAction.run(_:))
            actions.append(releaseAction)
            addRow("Associative", release, tip: "\(linked) of \(dimensions.count) follow the geometry")
        } else {
            addInfo("Not associative – snap the dimension points to objects (endpoints, centers…) and the dimension follows them.")
        }
    }

    /// Rectangle = a closed polyline with 4 vertices and sides parallel to the axes.
    static func rectangleBox(_ polyline: Polyline) -> CGRect? {
        guard polyline.closed, polyline.vertices.count == 4, !polyline.hasArcs else { return nil }
        let v = polyline.vertices
        let tolerance = max(polyline.boundingBox().width, polyline.boundingBox().height, 1) * 1e-9
        for i in 0..<4 {
            let a = v[i], b = v[(i + 1) % 4]
            guard abs(a.x - b.x) <= tolerance || abs(a.y - b.y) <= tolerance else { return nil }
        }
        let box = polyline.boundingBox()
        return box.width > tolerance && box.height > tolerance ? box : nil
    }

    /// Changing a rectangle via its bounds (vertices are recomputed, the order stays).
    private func editRectangle(_ change: @escaping (inout CGRect) -> Void) {
        edit("Change Rectangle", Polyline.self) { p in
            guard let box = PropertiesPanelView.rectangleBox(p) else { return nil }
            var target = box
            change(&target)
            let c = p.clone() as! Polyline
            c.vertices = p.vertices.map { v in
                let fx = box.width > 0 ? (v.x - box.minX) / box.width : 0
                let fy = box.height > 0 ? (v.y - box.minY) / box.height : 0
                return CGPoint(x: target.minX + fx.rounded() * target.width, y: target.minY + fy.rounded() * target.height)
            }
            return c
        }
    }

    // MARK: Popup actions

    private func rebuildHatchPatternPopup() {
        hatchPatternPopup.removeAllItems()
        for pattern in HatchPatternLibrary.all {
            hatchPatternPopup.addItem(withTitle: pattern.name)
            hatchPatternPopup.lastItem?.image = HatchPatternPreview.image(for: pattern, size: 16)
            hatchPatternPopup.lastItem?.representedObject = pattern.name
        }
        hatchPatternPopup.menu?.addItem(.separator())
        hatchPatternPopup.addItem(withTitle: "Custom…")
        hatchPatternPopup.lastItem?.tag = -1
    }

    @objc private func hatchPatternChosen(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.tag == -1 {
            onRequestCustomHatchPattern?()
            return
        }
        guard let name = item.representedObject as? String, let pattern = HatchPatternLibrary.named(name) else { return }
        onChangeHatchPattern?(pattern)
    }

    @objc private func layerChosen(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem, title != "*varies*" else { return }
        onChangeLayer?(title)
    }

    /// ByLayer, all lineweights (including custom ones) and “Custom…”.
    private func rebuildWeightPopup() {
        weightPopup.removeAllItems()
        weightPopup.addItem(withTitle: "ByLayer")
        for weight in LineWeights.all {
            weightPopup.addItem(withTitle: LineWeights.title(weight))
            weightPopup.lastItem?.representedObject = weight
        }
        weightPopup.menu?.addItem(.separator())
        weightPopup.addItem(withTitle: "Custom…")
        weightPopup.lastItem?.tag = -1
    }

    @objc private func weightChosen(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.tag == -1 {
            if let weight = LineWeightDialog.run() {
                rebuildWeightPopup()
                onChangeLineWeight?(weight)
            }
            return
        }
        onChangeLineWeight?(item.representedObject as? CGFloat)
    }

    @objc private func colorChosen(_ sender: NSPopUpButton) {
        guard let title = sender.titleOfSelectedItem else { return }
        if title == "ByLayer" {
            onChangeColor?(nil)
        } else if let entry = ACIColor.table.first(where: { $0.name == title }) {
            onChangeColor?(entry.color)
        } else if title.hasPrefix("Color "), let index = Int(title.dropFirst(6)) {
            onChangeColor?(ACIColor.color(for: index))
        }
    }
}

// MARK: - Status Bar

final class StatusBarView: NSView {
    private let coordinateLabel = NSTextField(labelWithString: "X: 0.000  Y: 0.000")
    /// Toggles at the bottom (status bar).
    var onToggleSnap: (() -> Void)?
    var onToggleOrtho: (() -> Void)?
    var onToggleSnapTracking: (() -> Void)?
    var onToggleAskToClose: (() -> Void)?
    var onToggleLineContinue: (() -> Void)?
    var onToggleLineWeights: (() -> Void)?
    var onSelectScale: ((DrawingScale) -> Void)?
    var onAddCustomScale: (() -> Void)?
    var onClearCustomScales: (() -> Void)?
    var onToggleScreenWeights: (() -> Void)?
    var onToggleGridSnap: (() -> Void)?
    var onTogglePolar: (() -> Void)?
    var onSetGridSize: ((CGFloat) -> Void)?
    var onSetPolarIncrement: ((CGFloat) -> Void)?
    var onToggleShowGrid: (() -> Void)?
    var onToggleShowAxes: (() -> Void)?

    private var snapButton: NSButton!
    private var snapMoreButton: NSButton!
    /// Popup with the choice of snap points (right click on SNAP or ▾).
    var onShowSnapSettings: ((NSView) -> Void)?
    private var orthoButton: NSButton!
    private var trackButton: NSButton!
    private var gridButton: NSButton!
    private var polarButton: NSButton!
    private var fkeysButton: NSButton!
    /// Click on FKEYS: explanation and the way to System Settings.
    var onFunctionKeysInfo: (() -> Void)?
    private var unitSuffix = "mm"
    private var askToCloseButton: NSButton!
    private var lineContinueButton: NSButton!
    private var lineWeightButton: NSButton!
    private let scalePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let promptLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Toggles on the right (left to right) – laid out from the right edge.
    private var rightItems: [NSView] = []
    /// Messages (shows the window as a popup above the drawing).
    var onMessage: ((String) -> Void)?

    private static let promptRowHeight: CGFloat = 30
    /// Free margin at the bottom (so the Dock doesn't open when clicking).
    private static let bottomMargin: CGFloat = 12

    private func setupUI() {
        wantsLayer = true
        layer?.backgroundColor = Theme.statusBarBackground.cgColor

        // row 1: prompt of the active tool
        promptLabel.frame = NSRect(x: 12, y: bounds.height - StatusBarView.promptRowHeight + 7, width: bounds.width - 24, height: 17)
        promptLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        promptLabel.textColor = .white
        promptLabel.lineBreakMode = .byTruncatingTail
        promptLabel.autoresizingMask = [.width, .minYMargin]
        addSubview(promptLabel)

        let divider = NSBox(frame: NSRect(x: 0, y: bounds.height - StatusBarView.promptRowHeight, width: bounds.width, height: 1))
        divider.boxType = .custom
        divider.borderWidth = 0
        divider.fillColor = Theme.statusDivider
        divider.autoresizingMask = [.width, .minYMargin]
        addSubview(divider)

        // row 2: coordinates on the left, toggles on the right
        let rowHeight = bounds.height - StatusBarView.promptRowHeight - StatusBarView.bottomMargin
        let mid = StatusBarView.bottomMargin + rowHeight / 2
        coordinateLabel.frame = NSRect(x: 12, y: mid - 8, width: 320, height: 16)
        coordinateLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        coordinateLabel.textColor = Theme.textSecondary
        coordinateLabel.lineBreakMode = .byTruncatingTail
        addSubview(coordinateLabel)
        // click on the coordinates: drawing ↔ S-JTSK
        coordinateLabel.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(coordinatesClicked(_:))))
        coordinateLabel.toolTip = "Click to switch between drawing coordinates and S-JTSK (Y, X in meters)"

        func toggle(_ title: String, _ tip: String, _ action: Selector, valued: Bool = false, shown: Bool = true) -> NSButton {
            let button = RightClickButton(title: title, target: self, action: action)
            if valued {
                // custom cell: draws the number itself so the system highlight doesn't recolor it
                let cell = ValueToggleCell(textCell: title)
                cell.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
                button.cell = cell
                button.target = self
                button.action = action
            }
            button.setButtonType(.pushOnPushOff)
            button.bezelStyle = .push
            button.controlSize = .mini
            button.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            button.toolTip = tip
            button.sizeToFit()
            button.frame.origin.y = mid - button.frame.height / 2
            if shown {
                addSubview(button)
                rightItems.append(button)
            }
            return button
        }
        func separator() {
            let line = NSBox(frame: NSRect(x: 0, y: mid - 8, width: 1, height: 16))
            line.boxType = .custom
            line.borderWidth = 0
            line.fillColor = Theme.statusSeparator
            addSubview(line)
            rightItems.append(line)
        }

        // drawing: Snap ▾, Ortho, Polar, Grid
        snapButton = toggle("Snap", "Object snap – endpoints, midpoints, centers…\nShortcut: ⌥3 · F3\nRight-click or ▾ = choose which snap points", #selector(snapClicked))
        (snapButton as? RightClickButton)?.onRightClick = { [weak self] in
            guard let self = self else { return }
            self.onShowSnapSettings?(self.snapButton)
        }
        let snapMore = NSButton(title: "", target: self, action: #selector(snapMoreClicked))
        snapMore.isBordered = false
        snapMore.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Snap points")
        snapMore.imageScaling = .scaleProportionallyDown
        snapMore.contentTintColor = Theme.textSecondary
        snapMore.toolTip = "Snap points – choose which points Snap finds"
        snapMore.frame = NSRect(x: 0, y: mid - 8, width: 13, height: 16)
        addSubview(snapMore)
        rightItems.append(snapMore)
        snapMoreButton = snapMore
        trackButton = toggle("Track", "Snap tracking – hold the cursor on a snap point for a moment to track it (a small cross); the cursor then lines up with it horizontally, vertically and at polar angles. Hold it there again to release it\nShortcut: ⌥1 · F11 (when macOS does not use it for Show Desktop)", #selector(trackClicked))
        orthoButton = toggle("Ortho", "Ortho – only horizontal and vertical directions (of the drawing coordinates)\nShortcut: ⌥8 · F8 · or hold Shift", #selector(orthoClicked))
        polarButton = toggle("Polar " + AngleStyle.text(15) + " ", "Polar angles – the direction snaps in steps (the number is the step)\nShortcut: ⌥0 · F10 · right-click = step or Custom…", #selector(polarClicked), valued: true)
        gridButton = toggle("Grid 10 ", "Snap to grid – points jump to the grid (the number is the grid step)\nShortcut: ⌥9 · F9 · right-click = grid size, Custom…, Show Grid or Show Axes", #selector(gridClicked), valued: true)
        rebuildValueMenus(gridSize: 10, polarIncrement: 15)
        separator()

        // display: LWT (the value box at the cursor no longer has a toggle – typing values always works)
        lineWeightButton = toggle("LWT", "Show lineweights\nShortcut: ⌥5 · F5 · ⇧⌘L", #selector(lineWeightClicked))
        askToCloseButton = toggle("CLS", "Ask whether to close polylines and splines when you finish them\nShortcut: ⌥4 · F4", #selector(askToCloseClicked))
        lineContinueButton = toggle("LNC", "Continuous lines – each new line starts at the end of the previous one (separate lines, not a polyline); works also while drawing\nShortcut: ⌥7 · F6 · in the Line tool also the Line key (\(DrawingTool.line.shortcut ?? "–")) again", #selector(lineContinueClicked))
        fkeysButton = toggle("FNK", "", #selector(fkeysClicked))
        setFunctionKeysState(nil)
        separator()

        // drawing scale (a larger drop-down menu – easy to hit)
        scalePopup.controlSize = .small
        scalePopup.font = NSFont.systemFont(ofSize: 11)
        scalePopup.toolTip = "Drawing scale – lineweights are shown true to this scale (or fixed on screen)"
        scalePopup.frame = NSRect(x: 0, y: mid - 11, width: 104, height: 22)
        scalePopup.target = self
        scalePopup.action = #selector(scaleChosen(_:))
        addSubview(scalePopup)
        rightItems.append(scalePopup)
        layoutRow()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutRow()
    }

    /// Toggles from the right edge; the coordinates get the remaining space on the left.
    /// In a narrow window (half of the screen) the coordinates move up to the right end of the prompt row.
    private func layoutRow() {
        var x = bounds.width - 12
        for (index, view) in rightItems.enumerated().reversed() {
            x -= view.frame.width
            view.frame.origin.x = x
            let previous = index > 0 ? rightItems[index - 1] : nil
            if previous === snapButton && view === snapMoreButton {
                x -= 1                      // ▾ right next to Snap
            } else if view is NSBox || previous is NSBox {
                x -= 10                     // spacing around the group separator
            } else {
                x -= 4
            }
        }
        let room = x - 24
        let promptY = bounds.height - StatusBarView.promptRowHeight + 7
        if room >= StatusBarView.coordinateMinWidth {
            let mid = StatusBarView.bottomMargin + (bounds.height - StatusBarView.promptRowHeight - StatusBarView.bottomMargin) / 2
            coordinateLabel.frame = NSRect(x: 12, y: mid - 8, width: min(room, 360), height: 16)
            coordinateLabel.alignment = .left
            promptLabel.frame = NSRect(x: 12, y: promptY, width: bounds.width - 24, height: 17)
        } else {
            let width = StatusBarView.coordinateMinWidth + 20
            coordinateLabel.frame = NSRect(x: bounds.width - 12 - width, y: promptY + 1, width: width, height: 16)
            coordinateLabel.alignment = .right
            promptLabel.frame = NSRect(x: 12, y: promptY, width: max(bounds.width - 36 - width, 0), height: 17)
        }
    }

    /// Below this width the coordinates no longer fit next to the toggles.
    private static let coordinateMinWidth: CGFloat = 200

    /// Zoom and layer are not shown in the status line (the layer is in the Layers panel).
    func setZoom(_ zoom: CGFloat) {}

    func setCurrentLayer(_ layer: String) {}

    func setCoordinates(_ point: CGPoint, unit: String? = nil) {
        if let unit = unit { unitSuffix = unit }
        coordinateLabel.stringValue = String(format: "X: %.3f  Y: %.3f  %@", point.x, point.y, unitSuffix)
    }

    /// Coordinates in another form (S-JTSK).
    func setCoordinateText(_ text: String) {
        coordinateLabel.stringValue = text
    }

    /// Click on the coordinates (toggles drawing / S-JTSK).
    var onCoordinatesClicked: (() -> Void)?

    @objc private func coordinatesClicked(_ sender: Any?) {
        onCoordinatesClicked?()
    }

    // MARK: Right click on GRID / POLAR: presets, custom values, Custom…

    private static let gridPresets: [CGFloat] = [0.1, 0.5, 1, 2, 5, 10, 25, 50, 100, 500, 1000]
    /// The polar steps offered (in degrees) – in gons the same round values as in Document Settings.
    private static var polarPresets: [CGFloat] {
        return AngleStyle.unit == .gons ? [1, 5, 10, 12.5, 25, 50, 100].map { $0 * 360 / 400 } : [1, 5, 10, 15, 22.5, 30, 45, 90]
    }
    private static let customGridKey = "OreMonoCAD.customGridSizes"
    private static let customPolarKey = "OreMonoCAD.customPolarSteps"

    /// Custom values (remembered for the next launch too).
    private static func customValues(_ key: String) -> [CGFloat] {
        return (UserDefaults.standard.array(forKey: key) as? [Double] ?? []).map { CGFloat($0) }
    }

    private static func addCustomValue(_ value: CGFloat, key: String, presets: [CGFloat]) {
        var list = customValues(key)
        guard !presets.contains(where: { abs($0 - value) < 1e-9 }), !list.contains(where: { abs($0 - value) < 1e-9 }) else { return }
        list.append(value)
        list.sort()
        UserDefaults.standard.set(list.map { Double($0) }, forKey: key)
    }

    private enum ValueKind { case grid, polar }

    private func rebuildValueMenus(gridSize: CGFloat, polarIncrement: CGFloat) {
        gridButton.menu = valueMenu(.grid, current: gridSize)
        polarButton.menu = valueMenu(.polar, current: polarIncrement)
    }

    /// Button menu: presets, custom values, Custom… and deleting custom values.
    private func valueMenu(_ kind: ValueKind, current: CGFloat) -> NSMenu {
        let presets = kind == .grid ? StatusBarView.gridPresets : StatusBarView.polarPresets
        let custom = StatusBarView.customValues(kind == .grid ? StatusBarView.customGridKey : StatusBarView.customPolarKey)
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ value: CGFloat) {
            let item = NSMenuItem(title: kind == .grid ? LineType.format(value) : AngleStyle.text(value), action: #selector(valueChosen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.tag = kind == .grid ? 1 : 2
            item.state = abs(value - current) < 1e-9 ? .on : .off
            menu.addItem(item)
        }
        presets.forEach(add)
        let extra = custom + ((presets + custom).contains { abs($0 - current) < 1e-9 } ? [] : [current])
        if !extra.isEmpty {
            menu.addItem(.separator())
            extra.forEach(add)
        }
        menu.addItem(.separator())
        let customItem = NSMenuItem(title: "Custom…", action: #selector(customValueChosen(_:)), keyEquivalent: "")
        customItem.target = self
        customItem.tag = kind == .grid ? 1 : 2
        menu.addItem(customItem)
        let clear = NSMenuItem(title: kind == .grid ? "Clear Custom Grid Sizes" : "Clear Custom Angles",
                               action: #selector(clearCustomValues(_:)), keyEquivalent: "")
        clear.target = self
        clear.tag = kind == .grid ? 1 : 2
        clear.isEnabled = !custom.isEmpty
        menu.addItem(clear)
        if kind == .grid {
            // display of the grid and the axes (saved in the drawing)
            menu.addItem(.separator())
            let showGrid = NSMenuItem(title: "Show Grid  (⌥2, F7)", action: #selector(showGridChosen), keyEquivalent: "")
            showGrid.target = self
            showGrid.state = lastShowGrid ? .on : .off
            menu.addItem(showGrid)
            let showAxes = NSMenuItem(title: "Show Axes", action: #selector(showAxesChosen), keyEquivalent: "")
            showAxes.target = self
            showAxes.state = lastShowAxes ? .on : .off
            menu.addItem(showAxes)
        }
        return menu
    }

    @objc private func showGridChosen() { onToggleShowGrid?() }
    @objc private func showAxesChosen() { onToggleShowAxes?() }

    @objc private func valueChosen(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? CGFloat else { return }
        if sender.tag == 1 { onSetGridSize?(value) } else { onSetPolarIncrement?(value) }
    }

    /// Custom value: asks for it, uses it and remembers it in the menu.
    @objc private func customValueChosen(_ sender: NSMenuItem) {
        let isGrid = sender.tag == 1
        let alert = NSAlert()
        alert.messageText = isGrid ? "Grid – Custom Size" : "Polar – Custom Angle"
        alert.informativeText = isGrid
            ? "Step of the grid in drawing units (an expression works too, e.g. 1000/3):"
            : AngleStyle.unit == .gons ? "Step of the polar angles in gons (from 0 to 200, e.g. 50 or 400/16):"
                : "Step of the polar angles in degrees (from 0 to 180, e.g. 7.5 or 360/24):"
        alert.addButton(withTitle: "Use")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        field.placeholderString = isGrid ? "e.g. 12.5" : AngleStyle.unit == .gons ? "e.g. 50" : "e.g. 7.5"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard var number = ExpressionEvaluator.evaluate(field.stringValue), number > 0 else {
            NSSound.beep()
            showMessage("“\(field.stringValue)” is not a valid \(isGrid ? "grid size" : "angle").")
            return
        }
        // the polar step is kept in degrees
        if !isGrid { number = Double(AngleStyle.degrees(CGFloat(number), .amount)) }
        guard isGrid || number <= 180 else {
            NSSound.beep()
            showMessage("“\(field.stringValue)” is not a valid \(isGrid ? "grid size" : "angle").")
            return
        }
        let value = CGFloat(number)
        if isGrid {
            StatusBarView.addCustomValue(value, key: StatusBarView.customGridKey, presets: StatusBarView.gridPresets)
            onSetGridSize?(value)
        } else {
            StatusBarView.addCustomValue(value, key: StatusBarView.customPolarKey, presets: StatusBarView.polarPresets)
            onSetPolarIncrement?(value)
        }
    }

    @objc private func clearCustomValues(_ sender: NSMenuItem) {
        UserDefaults.standard.removeObject(forKey: sender.tag == 1 ? StatusBarView.customGridKey : StatusBarView.customPolarKey)
        showMessage(sender.tag == 1 ? "Custom grid sizes removed" : "Custom angles removed")
        rebuildValueMenus(gridSize: lastGridSize, polarIncrement: lastPolarIncrement)
    }

    private var lastGridSize: CGFloat = 10
    private var lastPolarIncrement: CGFloat = 15
    private var lastShowGrid = true
    private var lastShowAxes = true
    @objc private func gridClicked() { onToggleGridSnap?() }
    @objc private func fkeysClicked() {
        fkeysButton.state = fkeysOn ? .on : .off     // the state is decided by macOS, not by the click
        onFunctionKeysInfo?()
    }

    private var fkeysOn = false

    /// FKEYS: does the top row send F1–F12 (true), or macOS functions (false)? nil = unknown.
    func setFunctionKeysState(_ standard: Bool?) {
        fkeysOn = standard ?? false
        fkeysButton.state = fkeysOn ? .on : .off
        let state: String
        switch standard {
        case true?: state = "ON – the top row sends F1, F2… (F1–F12 work directly)."
        case false?: state = "OFF – the top row controls brightness, volume…; hold fn (Globe) for F1, F2…"
        case nil: state = "unknown"
        }
        fkeysButton.toolTip = """
        Function keys as F1–F12 (macOS keyboard setting): \(state)
        Every mode also has a shortcut that always works: ⌥ + number (⌥1 Snap tracking, ⌥2 Show grid, ⌥3 Snap, ⌥4 CLS, ⌥5 LWT, ⌥6 value box, ⌥7 LNC, ⌥8 Ortho, ⌥9 Grid snap, ⌥0 Polar).
        Click for how to change the setting
        """
    }
    @objc private func polarClicked() { onTogglePolar?() }

    func setModes(snap: Bool, ortho: Bool, askToClose: Bool, lineContinue: Bool,
                  lineWeights: Bool, scale: DrawingScale, screenWeights: Bool,
                  gridSnap: Bool, gridSize: CGFloat, showGrid: Bool, showAxes: Bool,
                  polar: Bool, polarIncrement: CGFloat, unit: String) {
        unitSuffix = unit
        gridButton.state = gridSnap ? .on : .off
        polarButton.state = polar ? .on : .off
        retitle(gridButton, "Grid", value: LineType.format(gridSize))
        retitle(polarButton, "Polar", value: AngleStyle.text(polarIncrement))
        lastGridSize = gridSize
        lastPolarIncrement = polarIncrement
        lastShowGrid = showGrid
        lastShowAxes = showAxes
        rebuildValueMenus(gridSize: gridSize, polarIncrement: polarIncrement)
        lineContinueButton.state = lineContinue ? .on : .off
        lineWeightButton.state = lineWeights ? .on : .off
        rebuildScaleMenu(current: scale, screenWeights: screenWeights)
        snapButton.state = snap ? .on : .off
        orthoButton.state = ortho ? .on : .off
        askToCloseButton.state = askToClose ? .on : .off
    }

    /// New button title “NAME value” (value in color); buttons to the right shift by the width.
    private func retitle(_ button: NSButton, _ name: String, value: String) {
        guard let cell = button.cell as? ValueToggleCell else { return }
        guard cell.name != name || cell.value != value || button.attributedTitle.length == 0 else { return }
        let oldWidth = button.frame.width
        cell.name = name
        cell.value = value
        // the title is only used to compute the width – ValueToggleCell draws it according to the state
        let title = cell.title(on: false)
        button.attributedTitle = title
        button.attributedAlternateTitle = title
        button.sizeToFit()
        button.needsDisplay = true
        if button.frame.width != oldWidth { layoutRow() }
    }

    @objc private func snapClicked() { onToggleSnap?() }
    @objc private func snapMoreClicked() { onShowSnapSettings?(snapButton) }
    /// The SNAP button (the snap point popup is anchored to it).
    var snapAnchor: NSView { return snapButton }
    @objc private func orthoClicked() { onToggleOrtho?() }
    @objc private func trackClicked() { onToggleSnapTracking?() }

    func setSnapTracking(_ on: Bool) {
        trackButton.state = on ? .on : .off
    }
    @objc private func askToCloseClicked() { onToggleAskToClose?() }
    @objc private func lineContinueClicked() { onToggleLineContinue?() }
    @objc private func lineWeightClicked() { onToggleLineWeights?() }

    /// Scale drop-down: presets, custom, “Custom…” and the fixed lineweight mode.
    private func rebuildScaleMenu(current: DrawingScale, screenWeights: Bool) {
        let menu = NSMenu()
        func add(_ scale: DrawingScale) {
            let item = NSMenuItem(title: scale.title, action: nil, keyEquivalent: "")
            item.representedObject = scale.title
            menu.addItem(item)
        }
        DrawingScale.presets.forEach(add)
        let custom = DrawingScale.custom.filter { !DrawingScale.presets.contains($0) }
        if !custom.isEmpty {
            menu.addItem(.separator())
            custom.forEach(add)
        }
        if !DrawingScale.presets.contains(current) && !custom.contains(current) { add(current) }
        menu.addItem(.separator())
        for (title, tag) in [("Custom…", 1), ("Clear Custom Scales", 2), ("Lineweights Fixed on Screen", 3)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = tag
            if tag == 2 { item.isEnabled = !custom.isEmpty }
            if tag == 3 { item.state = screenWeights ? .on : .off }
            menu.addItem(item)
        }
        menu.autoenablesItems = false
        scalePopup.menu = menu
        if let index = menu.items.firstIndex(where: { ($0.representedObject as? String) == current.title }) {
            scalePopup.selectItem(at: index)
        }
    }

    @objc private func scaleChosen(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        switch item.tag {
        case 1: onAddCustomScale?()
        case 2: onClearCustomScales?()
        case 3: onToggleScreenWeights?()
        default:
            if let title = item.representedObject as? String, let scale = DrawingScale.parse(title) {
                onSelectScale?(scale)
            }
        }
    }

    func setPrompt(_ prompt: String) {
        promptLabel.stringValue = prompt
    }

    /// Messages: a popup above the drawing (without icons and emoji), otherwise the coordinate tooltip.
    func showMessage(_ message: String) {
        onMessage?(message)
    }
}

/// A short message in the corner of the drawing area – disappears by itself after a while. Text only, no icons.
final class ToastView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var hideTimer: Timer?
    private let maxWidth: CGFloat = 640

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.toastBackground.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.popupBorder.cgColor
        label.font = NSFont.systemFont(ofSize: 11.5)
        label.textColor = Theme.textToast
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 2
        label.cell?.wraps = true
        addSubview(label)
        alphaValue = 0
        isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { return nil }

    /// Shows text above point `origin` (bottom left corner) – length according to the text, at most two lines.
    func show(_ text: String, at origin: CGPoint, availableWidth: CGFloat) {
        guard !text.isEmpty else { return }
        label.stringValue = text
        let width = min(maxWidth, max(availableWidth - 24, 160))
        let size = label.sizeThatFits(NSSize(width: width - 20, height: 40))
        let w = min(size.width, width - 20)
        frame = NSRect(x: origin.x, y: origin.y, width: w + 20, height: size.height + 12)
        label.frame = NSRect(x: 10, y: 6, width: w, height: size.height)
        isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        hideTimer?.invalidate()
        // longer text = stays visible longer
        let seconds = min(9, 3.5 + Double(text.count) / 30)
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fadeOut() }
        }
    }

    private func fadeOut() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                if self?.alphaValue == 0 { self?.isHidden = true }
            }
        })
    }
}

/// A button that also handles right click (SNAP → snap point choice).
final class RightClickButton: NSButton {
    var onRightClick: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        if let handler = onRightClick { handler() } else { super.rightMouseDown(with: event) }
    }
}

// MARK: - Document Settings

/// Document settings: units, grid and angle snapping.
enum DocumentSettingsDialog {
    struct Result {
        var units: DrawingUnits
        var convertDrawing: Bool
        var gridSize: CGFloat
        var gridSnap: Bool
        var showGrid: Bool
        var polar: Bool
        var polarIncrement: CGFloat
    }

    static func run(units: DrawingUnits, gridSize: CGFloat, gridSnap: Bool, showGrid: Bool,
                    polar: Bool, polarIncrement: CGFloat) -> Result? {
        let alert = NSAlert()
        alert.messageText = "Document Settings"
        alert.informativeText = "Units, grid and polar angles of this drawing. The units, the grid size and the polar step are saved with the drawing."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let width: CGFloat = 330
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 236))
        var y: CGFloat = 236

        func caption(_ text: String) {
            y -= 26
            let label = NSTextField(labelWithString: text)
            label.alignment = .right
            label.frame = NSRect(x: 0, y: y + 3, width: 120, height: 17)
            view.addSubview(label)
        }
        func section(_ text: String) {
            y -= 22
            let label = NSTextField(labelWithString: text.uppercased())
            label.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            label.textColor = .secondaryLabelColor
            label.frame = NSRect(x: 0, y: y, width: width, height: 15)
            view.addSubview(label)
        }

        section("Units")
        caption("Drawing units")
        let unitPopup = NSPopUpButton(frame: NSRect(x: 128, y: y, width: 200, height: 24), pullsDown: false)
        for unit in DrawingUnits.allCases { unitPopup.addItem(withTitle: unit.title) }
        unitPopup.selectItem(at: DrawingUnits.allCases.firstIndex(of: units) ?? 0)
        view.addSubview(unitPopup)
        y -= 22
        let convert = NSButton(checkboxWithTitle: "Convert the existing drawing", target: nil, action: nil)
        convert.frame = NSRect(x: 128, y: y, width: 200, height: 18)
        convert.toolTip = "On: objects keep their real size (coordinates are recalculated). Off: only the meaning of a unit changes"
        convert.state = .on
        view.addSubview(convert)

        section("Grid")
        caption("Grid size")
        let gridField = NSTextField(frame: NSRect(x: 128, y: y, width: 90, height: 22))
        gridField.stringValue = LineType.format(gridSize)
        gridField.placeholderString = "e.g. 10"
        view.addSubview(gridField)
        y -= 22
        let snapCheck = NSButton(checkboxWithTitle: "Snap to grid  (⌥9, F9)", target: nil, action: nil)
        snapCheck.frame = NSRect(x: 128, y: y, width: 190, height: 18)
        snapCheck.state = gridSnap ? .on : .off
        view.addSubview(snapCheck)
        let showCheck = NSButton(checkboxWithTitle: "Show grid  (⌥2, F7)", target: nil, action: nil)
        y -= 20
        showCheck.frame = NSRect(x: 128, y: y, width: 190, height: 18)
        showCheck.state = showGrid ? .on : .off
        view.addSubview(showCheck)

        section("Angles")
        caption(AngleStyle.caption("Polar step", .amount))
        let polarField = NSComboBox(frame: NSRect(x: 128, y: y, width: 90, height: 24))
        polarField.addItems(withObjectValues: AngleStyle.unit == .gons ? ["1", "5", "10", "12.5", "25", "50", "100"]
                                                                    : ["1", "5", "10", "15", "22.5", "30", "45", "90"])
        polarField.stringValue = LineType.format(AngleStyle.shown(polarIncrement, .amount))
        view.addSubview(polarField)
        let polarCheck = NSButton(checkboxWithTitle: "On  (⌥0, F10)", target: nil, action: nil)
        polarCheck.frame = NSRect(x: 222, y: y + 3, width: 106, height: 18)
        polarCheck.state = polar ? .on : .off
        view.addSubview(polarCheck)

        alert.accessoryView = view
        alert.window.initialFirstResponder = gridField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        guard let grid = ExpressionEvaluator.evaluate(gridField.stringValue), grid > 0,
              case let step = Double(AngleStyle.degrees(CGFloat(ExpressionEvaluator.evaluate(polarField.stringValue) ?? -1), .amount)),
              step > 0, step <= 180 else {
            NSSound.beep()
            return nil
        }
        let chosen = DrawingUnits.allCases[max(0, unitPopup.indexOfSelectedItem)]
        return Result(units: chosen, convertDrawing: convert.state == .on, gridSize: CGFloat(grid),
                      gridSnap: snapCheck.state == .on, showGrid: showCheck.state == .on,
                      polar: polarCheck.state == .on, polarIncrement: CGFloat(step))
    }
}

// MARK: - Layer Bar (top bar with layers)

// MARK: - Dockable Panel (movable panel with a header)

/// Panel wrapper with a header: dragging the header moves the panel,
/// the buttons fold the panel to the side, detach it into its own window, dock it or close it.
final class DockablePanelView: NSView {
    enum HeaderButton { case collapse, detach, dock, close, fold }

    /// Folded to the header (in the side panel) – changes the arrow of the fold button.
    var isFolded = false {
        didSet { headerButtons.first { $0.tag == 4 }?.image = foldImage }
    }
    private var foldImage: NSImage? {
        let name = isFolded ? "chevron.right" : "chevron.down"
        return NSImage(systemSymbolName: name, accessibilityDescription: isFolded ? "Expand" : "Fold")
    }

    var onButton: ((HeaderButton) -> Void)?
    /// Dragging the header: offset in window coordinates since the drag started; isFinished at the end.
    var onDrag: ((_ offset: CGPoint, _ isFinished: Bool) -> Void)?

    static let headerHeight: CGFloat = 24
    let content: NSView
    private let header = PanelHeaderView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var headerButtons: [NSButton] = []

    init(title: String, content: NSView) {
        self.content = content
        super.init(frame: NSRect(x: 0, y: 0, width: content.frame.width,
                                 height: content.frame.height + DockablePanelView.headerHeight))
        wantsLayer = true
        layer?.backgroundColor = Theme.panelBackground.cgColor
        layer?.borderColor = Theme.panelBorder.cgColor
        layer?.borderWidth = 0.5

        content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - DockablePanelView.headerHeight)
        content.autoresizingMask = [.width, .height]
        addSubview(content)

        header.frame = NSRect(x: 0, y: bounds.height - DockablePanelView.headerHeight,
                              width: bounds.width, height: DockablePanelView.headerHeight)
        header.autoresizingMask = [.width, .minYMargin]
        header.onDrag = { [weak self] offset, finished in self?.onDrag?(offset, finished) }
        addSubview(header)

        titleLabel.stringValue = title
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.sizeToFit()
        titleLabel.frame.origin = CGPoint(x: 10, y: (DockablePanelView.headerHeight - titleLabel.frame.height) / 2)
        header.addSubview(titleLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sets which header buttons are visible (according to the panel mode).
    func setButtons(_ kinds: [HeaderButton]) {
        headerButtons.forEach { $0.removeFromSuperview() }
        headerButtons.removeAll()
        var x = header.bounds.width - 6
        for kind in kinds.reversed() {
            let info: (symbol: String, tip: String)
            switch kind {
            case .collapse: info = ("sidebar.right", "Collapse to the side")
            case .detach: info = ("macwindow.on.rectangle", "Detach into its own window")
            case .dock: info = ("rectangle.righthalf.inset.filled", "Dock to the right edge")
            case .close: info = ("xmark", "Close")
            case .fold: info = (isFolded ? "chevron.right" : "chevron.down", "Fold / unfold this panel")
            }
            let symbol = info.symbol, tip = info.tip
            let button = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 18))
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
                ?? NSImage(systemSymbolName: "square", accessibilityDescription: tip)
            button.imageScaling = .scaleProportionallyDown
            button.isBordered = false
            button.contentTintColor = Theme.textSecondary
            button.toolTip = tip
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.tag = [HeaderButton.collapse, .detach, .dock, .close, .fold].firstIndex(of: kind) ?? 0
            x -= 22
            button.frame.origin = CGPoint(x: x, y: (DockablePanelView.headerHeight - 18) / 2)
            button.autoresizingMask = [.minXMargin]
            header.addSubview(button)
            headerButtons.append(button)
        }
    }

    @objc private func buttonClicked(_ sender: NSButton) {
        let kinds: [HeaderButton] = [.collapse, .detach, .dock, .close, .fold]
        guard sender.tag < kinds.count else { return }
        onButton?(kinds[sender.tag])
    }
}

/// A narrow handle for resizing (edge of the side panel, divider between panels).
final class DragHandleView: NSView {
    var cursor: NSCursor = .resizeLeftRight
    /// A horizontal divider draws a fine line in the middle.
    var drawsLine = false
    var onDrag: ((_ offset: CGPoint, _ isFinished: Bool) -> Void)?
    private var dragStart: CGPoint?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard drawsLine else { return }
        Theme.dragHandle.setFill()
        NSRect(x: bounds.midX - 14, y: bounds.midY - 1, width: 28, height: 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = event.locationInWindow
        onDrag?(CGPoint(x: p.x - start.x, y: p.y - start.y), false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        dragStart = nil
        let p = event.locationInWindow
        onDrag?(CGPoint(x: p.x - start.x, y: p.y - start.y), true)
    }
}

/// Panel header – catches mouse drags.
final class PanelHeaderView: NSView {
    var onDrag: ((_ offset: CGPoint, _ isFinished: Bool) -> Void)?
    private var dragStart: CGPoint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.panelHeaderBackground.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = event.locationInWindow
        onDrag?(CGPoint(x: p.x - start.x, y: p.y - start.y), false)
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = dragStart else { return }
        let p = event.locationInWindow
        dragStart = nil
        NSCursor.openHand.set()
        onDrag?(CGPoint(x: p.x - start.x, y: p.y - start.y), true)
    }
}

/// Collapsed side panel: a narrow strip with an arrow and vertical panel names; click to expand.
final class CollapsedStripView: NSView {
    var onExpand: (() -> Void)?
    var titles: [String] = [] { didSet { needsDisplay = true } }
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        toolTip = "Click to expand the panel (⌘0)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        (hovering ? Theme.stripHoverBackground : Theme.stripBackground).setFill()
        bounds.fill()
        Theme.panelBorder.setFill()
        NSRect(x: 0, y: 0, width: 0.5, height: bounds.height).fill()

        // “expand” arrow at the top
        if let chevron = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Expand"),
           let tinted = chevron.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)) {
            let size = tinted.size
            let rect = NSRect(x: (bounds.width - size.width) / 2, y: bounds.maxY - 10 - size.height,
                              width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            tinted.draw(in: rect)
            Theme.iconLight.set()
            rect.fill(using: .sourceAtop)
            NSGraphicsContext.restoreGraphicsState()
        }

        // vertical names from top to bottom (read with the head tilted right), centered in the strip
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: (hovering ? Theme.textBright : Theme.iconOn),
            .kern: 0.6
        ]
        let separator: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Theme.stripSeparator
        ]
        let text = NSMutableAttributedString()
        for (index, title) in titles.enumerated() {
            if index > 0 { text.append(NSAttributedString(string: "   ·   ", attributes: separator)) }
            text.append(NSAttributedString(string: title, attributes: attributes))
        }
        let lineHeight = text.size().height
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        // after rotating by −90° the line height lies horizontally (letter tops to the right): line center = strip center
        context.translateBy(x: bounds.midX - lineHeight / 2, y: bounds.maxY - 34)
        context.rotate(by: -.pi / 2)
        text.draw(at: NSPoint(x: 0, y: 0))
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        onExpand?()
    }
}

// MARK: - Hover Tip (tool help)

/// Help popup: name and shortcut, summary and (after a longer hover) short usage instructions.
final class HoverTipView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(wrappingLabelWithString: "")
    private let usageCaption = NSTextField(labelWithString: "HOW TO USE")
    private let usageLabel = NSTextField(wrappingLabelWithString: "")
    private let separator = NSBox()
    private let width: CGFloat = 250
    private let padding: CGFloat = 10

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.tipBackground.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.popupBorder.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.5
        layer?.shadowRadius = 8
        isHidden = true

        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = .white
        summaryLabel.font = NSFont.systemFont(ofSize: 11)
        summaryLabel.textColor = Theme.textSoft
        usageCaption.font = NSFont.systemFont(ofSize: 9, weight: .bold)
        usageCaption.textColor = Theme.accent
        usageLabel.font = NSFont.systemFont(ofSize: 11)
        usageLabel.textColor = Theme.textLabel
        separator.boxType = .separator
        for view in [titleLabel, summaryLabel, separator, usageCaption, usageLabel] { addSubview(view) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // the help popup must not catch the mouse
    override func hitTest(_ point: NSPoint) -> NSView? { return nil }

    func configure(title: String, summary: String, usage: String, expanded: Bool) {
        titleLabel.stringValue = title
        summaryLabel.stringValue = summary
        usageLabel.stringValue = usage
        separator.isHidden = !expanded
        usageCaption.isHidden = !expanded
        usageLabel.isHidden = !expanded

        let inner = width - 2 * padding
        func height(of label: NSTextField) -> CGFloat {
            return ceil(label.sizeThatFits(NSSize(width: inner, height: .greatestFiniteMagnitude)).height)
        }
        let titleHeight = height(of: titleLabel)
        let summaryHeight = height(of: summaryLabel)
        let usageHeight = expanded ? height(of: usageLabel) : 0
        let captionHeight: CGFloat = expanded ? 12 : 0
        let total = padding + titleHeight + 3 + summaryHeight
            + (expanded ? 8 + 1 + 6 + captionHeight + 2 + usageHeight : 0) + padding
        setFrameSize(NSSize(width: width, height: total))

        // layout from top to bottom
        var y = total - padding - titleHeight
        titleLabel.frame = NSRect(x: padding, y: y, width: inner, height: titleHeight)
        y -= 3 + summaryHeight
        summaryLabel.frame = NSRect(x: padding, y: y, width: inner, height: summaryHeight)
        if expanded {
            y -= 8 + 1
            separator.frame = NSRect(x: padding, y: y, width: inner, height: 1)
            y -= 6 + captionHeight
            usageCaption.frame = NSRect(x: padding, y: y, width: inner, height: captionHeight)
            y -= 2 + usageHeight
            usageLabel.frame = NSRect(x: padding, y: y, width: inner, height: usageHeight)
        }
    }
}

/// Toggle cell with a value (GRID 10, POLAR 15°): name + colored number.
/// It draws the title itself, so in the on state the system highlight doesn't recolor the number to white –
/// instead it gets its own color contrasting with the highlight color (accent color).
final class ValueToggleCell: NSButtonCell {
    var name = ""
    var value = ""

    /// Is the button shown as on (in the active and inactive window – the background just turns gray).
    private var looksOn: Bool { state == .on }

    func title(on: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let result = NSMutableAttributedString(string: name + " ", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: on ? Theme.toggleNameOn : Theme.toggleNameOff,
            .paragraphStyle: paragraph])
        result.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: on ? Theme.toggleValueOn : Theme.toggleValueOff,
            .paragraphStyle: paragraph]))
        return result
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        guard !name.isEmpty else { return super.drawTitle(title, withFrame: frame, in: controlView) }
        var text = self.title(on: looksOn)
        if !isEnabled {
            let dimmed = NSMutableAttributedString(attributedString: text)
            dimmed.addAttribute(.foregroundColor, value: NSColor.disabledControlTextColor,
                                range: NSRange(location: 0, length: dimmed.length))
            text = dimmed
        }
        let size = text.size()
        let rect = NSRect(x: frame.minX, y: frame.midY - size.height / 2, width: frame.width, height: size.height)
        text.draw(in: rect)
        return frame
    }
}
