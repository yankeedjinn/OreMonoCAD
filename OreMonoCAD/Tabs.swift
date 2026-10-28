//
//  Tabs.swift
//  OreMonoCAD
//
//  Several open drawings at once – tabs above the drawing area (like in a browser).
//
//  Each tab (DrawingTab) has its own drawing, layers, selection, Undo history, file,
//  unsaved-changes flag, view (zoom/pan) and drawing settings (scale, LWT, hatch).
//  Tools, SNAP, ORTHO and similar modes are shared by the whole window.
//

import Cocoa

// MARK: - Tab = one open drawing

final class DrawingTab {
    var document = CADDocument()
    let layerManager = LayerManager()
    let selectionManager = SelectionManager()
    let undoer = UndoManager()

    var fileURL: URL?
    var isEdited = false

    // auto-save and recovery (Recovery.swift)
    /// File name of this tab's auto-save (kept even after recovery).
    var autosaveID = UUID().uuidString
    /// Change counter – auto-save only happens when something was added since the last backup.
    var changeCount = 0
    var autosavedChangeCount = 0
    var lastAutosave = Date()
    /// An auto-save of the current unsaved work exists (false after saving, opening or closing).
    var hasAutosave = false
    /// Name of a recovered drawing or a backup that does not have its own file yet.
    var customTitle: String?
    /// Where to offer saving (recovered drawing, opened backup) – Save asks and pre-fills this location.
    var suggestedSaveURL: URL?
    /// Name for Save when the drawing has no location (recovered, never saved drawing).
    var suggestedName: String?
    /// Sequence number for “Untitled 2”, “Untitled 3”… (new drawings only).
    let untitledNumber: Int

    // state stored when switching to another tab
    var viewState: (zoom: CGFloat, pan: CGPoint)?
    var drawingScale = DrawingScale(paper: 1, model: 1)
    var showLineWeights = false
    var lineWeightOnScreen = false
    var hatchPattern: HatchPattern = .lines
    var hatchAngle: CGFloat = 0
    var hatchScale: CGFloat?
    var units: DrawingUnits = .mm
    var gridSize: CGFloat = 10
    var showGrid = AppSettings.showGrid
    var showAxes = AppSettings.showAxes
    /// Rotation of the model view and the drawing coordinates (UCS).
    var viewRotation: CGFloat = 0
    var ucsAngle: CGFloat = 0
    var ucsOrigin: CGPoint = .zero
    /// Geodetic base point (tie to S-JTSK), nil = not set.
    var geoReference: GeoReference?
    var polarIncrement: CGFloat = 15
    /// Colors new layers take (Layers panel); a new drawing gets the default from Settings.
    var layerColorScheme = LayerColorScheme.defaultScheme

    // sheets (layouts) and plotting
    var layouts: [DrawingLayout] = []
    /// The open layout (nil = Model).
    var activeLayoutIndex: Int?
    /// Named plot settings (Page Setups) – stored in the drawing.
    var pageSetups: [PlotSettings] = []
    /// Last plot settings of the model.
    var modelPlotSettings: PlotSettings?
    /// The drawing's blocks and external references.
    var blocks = BlockLibrary()
    /// Saved views (View › Named Views).
    var namedViews: [NamedViewRecord] = []

    var activeLayout: DrawingLayout? {
        guard let index = activeLayoutIndex, layouts.indices.contains(index) else { return nil }
        return layouts[index]
    }

    /// A block edit in progress (BlockEdit.swift) – while it runs, drawing goes into the block's content.
    var blockEdit: BlockEditSession?

    /// Document of the space currently being edited (edited block, layout or model).
    var activeDocument: CADDocument {
        return blockEdit?.document ?? activeLayout?.document ?? document
    }

    /// Undo of the content currently being edited (a block edit has its own).
    var activeUndoer: UndoManager {
        return blockEdit?.undoer ?? undoer
    }

    /// The model and all layouts.
    var allDocuments: [CADDocument] {
        return [document] + layouts.map { $0.document }
    }

    /// Before saving: blocks still used by objects (e.g. brought back by Undo after Purge) return to the library.
    func restoreReferencedBlocks() {
        blocks.restoreReferenced(by: allDocuments.map { $0.getAllEntities() })
    }

    /// A free name for a new layout (“Layout1”, “Layout2”…).
    func uniqueLayoutName(_ base: String = "Layout") -> String {
        var i = 1
        while layouts.contains(where: { $0.name == "\(base)\(i)" }) { i += 1 }
        return "\(base)\(i)"
    }

    init(untitledNumber: Int) {
        self.untitledNumber = untitledNumber
    }

    var title: String {
        if let url = fileURL { return url.deletingPathExtension().lastPathComponent }
        if let custom = customTitle { return custom }
        return untitledNumber <= 1 ? "Untitled" : "Untitled \(untitledNumber)"
    }

    /// An empty, unsaved and unchanged drawing – can be replaced directly when opening a file.
    var isPristine: Bool {
        return fileURL == nil && customTitle == nil && !isEdited && document.isEmpty && layouts.isEmpty && blocks.definitions.isEmpty
    }
}

// MARK: - Tab bar

final class DrawingTabBarView: NSView {
    static let height: CGFloat = 28

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onNewTab: (() -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var onCloseOthers: ((Int) -> Void)?
    var onRevealInFinder: ((Int) -> Void)?

    private struct Item {
        var title: String
        var toolTip: String
        var edited: Bool
    }

    private var items: [Item] = []
    private var selectedIndex = 0
    private var hoverIndex: Int?
    private var hoverClose: Int?
    private var pressedClose: Int?
    private var dragIndex: Int?
    private var dragStartX: CGFloat = 0
    private var dragOffset: CGFloat = 0
    private var trackingArea: NSTrackingArea?

    private let plusWidth: CGFloat = 28
    private let maxTabWidth: CGFloat = 200
    private let minTabWidth: CGFloat = 70

    override var isFlipped: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    func update(titles: [(title: String, toolTip: String, edited: Bool)], selected: Int) {
        items = titles.map { Item(title: $0.title, toolTip: $0.toolTip, edited: $0.edited) }
        selectedIndex = selected
        if let hover = hoverIndex, hover >= items.count { hoverIndex = nil }
        rebuildToolTips()
        needsDisplay = true
    }

    // MARK: Dimensions

    private var tabWidth: CGFloat {
        guard !items.isEmpty else { return maxTabWidth }
        let available = bounds.width - plusWidth - 8
        return max(minTabWidth, min(maxTabWidth, available / CGFloat(items.count)))
    }

    private func tabRect(_ index: Int) -> NSRect {
        var rect = NSRect(x: 4 + CGFloat(index) * tabWidth, y: 0, width: tabWidth, height: bounds.height - 3)
        if index == dragIndex { rect.origin.x += dragOffset }
        return rect
    }

    private func closeRect(_ index: Int) -> NSRect {
        let tab = tabRect(index)
        return NSRect(x: tab.minX + 6, y: tab.midY - 7, width: 14, height: 14)
    }

    private var plusRect: NSRect {
        let x = min(4 + CGFloat(items.count) * tabWidth, bounds.width - plusWidth) + 2
        return NSRect(x: x, y: (bounds.height - 3) / 2 - 10, width: 22, height: 20)
    }

    private func index(at point: NSPoint) -> Int? {
        for i in items.indices where tabRect(i).contains(point) { return i }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // the bar is a shade lighter than the drawing area, the selected tab blends with the area
        Theme.tabBarBackground.setFill()
        bounds.fill()

        let font = NSFont.systemFont(ofSize: 11.5)
        let order = items.indices.filter { $0 != dragIndex } + (dragIndex.map { [$0] } ?? [])
        for i in order {
            let rect = tabRect(i)
            let selected = i == selectedIndex
            let shape = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 0).offsetBy(dx: 0, dy: 3),
                                     xRadius: 6, yRadius: 6)
            if selected {
                Theme.canvasBackground.setFill()
                shape.fill()
                // the bottom edge blends with the drawing area
                NSRect(x: rect.minX + 1, y: 0, width: rect.width - 2, height: 6).fill()
                Theme.accent.withAlphaComponent(0.9).setFill()
                NSRect(x: rect.minX + 8, y: rect.maxY + 1, width: rect.width - 16, height: 2).fill()
            } else if i == hoverIndex {
                Theme.tabHover.setFill()
                shape.fill()
            }
            // separator between unselected tabs
            if !selected && i + 1 != selectedIndex && i + 1 < items.count {
                Theme.tabSeparator.setFill()
                NSRect(x: rect.maxX - 0.5, y: 7, width: 1, height: rect.height - 12).fill()
            }

            // close cross (on the selected and hovered tab), otherwise an unsaved-changes dot
            let close = closeRect(i)
            let showClose = selected || i == hoverIndex
            if showClose && hoverClose == i {
                (pressedClose == i ? Theme.tabClosePressed : Theme.tabCloseHover).setFill()
                NSBezierPath(roundedRect: close, xRadius: 3, yRadius: 3).fill()
            }
            if showClose && !(items[i].edited && hoverClose != i) {
                let cross = NSBezierPath()
                let c = close.insetBy(dx: 4, dy: 4)
                cross.move(to: NSPoint(x: c.minX, y: c.minY)); cross.line(to: NSPoint(x: c.maxX, y: c.maxY))
                cross.move(to: NSPoint(x: c.minX, y: c.maxY)); cross.line(to: NSPoint(x: c.maxX, y: c.minY))
                cross.lineWidth = 1.3
                Theme.iconLight.setStroke()
                cross.stroke()
            } else if items[i].edited {
                Theme.textSecondary.setFill()
                NSBezierPath(ovalIn: NSRect(x: close.midX - 3.5, y: close.midY - 3.5, width: 7, height: 7)).fill()
            }

            // name
            let attributes: [NSAttributedString.Key: Any] = [
                .font: selected ? NSFont.systemFont(ofSize: 11.5, weight: .medium) : font,
                .foregroundColor: (selected ? Theme.textBright : Theme.textMuted),
                .paragraphStyle: {
                    let style = NSMutableParagraphStyle()
                    style.lineBreakMode = .byTruncatingMiddle
                    return style
                }()
            ]
            let textRect = NSRect(x: close.maxX + 5, y: rect.midY - 8, width: rect.maxX - close.maxX - 12, height: 16)
            (items[i].title as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                              attributes: attributes)
        }

        // + button
        let plus = plusRect
        if hoverIndex == -1 {
            Theme.tabPlusHover.setFill()
            NSBezierPath(roundedRect: plus, xRadius: 4, yRadius: 4).fill()
        }
        let sign = NSBezierPath()
        sign.move(to: NSPoint(x: plus.midX - 5, y: plus.midY)); sign.line(to: NSPoint(x: plus.midX + 5, y: plus.midY))
        sign.move(to: NSPoint(x: plus.midX, y: plus.midY - 5)); sign.line(to: NSPoint(x: plus.midX, y: plus.midY + 5))
        sign.lineWidth = 1.4
        Theme.textLabel.setStroke()
        sign.stroke()

    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        hoverIndex = nil
        hoverClose = nil
        needsDisplay = true
    }

    private func updateHover(_ point: NSPoint) {
        let newHover = plusRect.contains(point) ? -1 : index(at: point)
        let newClose = newHover.flatMap { $0 >= 0 && closeRect($0).contains(point) ? $0 : nil }
        if newHover != hoverIndex || newClose != hoverClose {
            hoverIndex = newHover
            hoverClose = newClose
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if plusRect.contains(point) {
            onNewTab?()
            return
        }
        guard let i = index(at: point) else {
            // double-click in an empty part of the bar = new drawing (like in a browser)
            if event.clickCount == 2 { onNewTab?() }
            return
        }
        if closeRect(i).contains(point) {
            pressedClose = i
            needsDisplay = true
            return
        }
        if i != selectedIndex { onSelect?(i) }
        dragIndex = i
        dragStartX = point.x
        dragOffset = 0
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if pressedClose != nil {
            hoverClose = pressedClose.flatMap { closeRect($0).contains(point) ? $0 : nil }
            needsDisplay = true
            return
        }
        guard let from = dragIndex, items.count > 1 else { return }
        dragOffset = point.x - dragStartX
        // move the tab once it is dragged past the middle of its neighbor
        let slot = Int(((tabRect(from).midX - 4) / tabWidth).rounded(.down))
        let target = max(0, min(items.count - 1, slot))
        if target != from {
            onMove?(from, target)
            dragStartX += CGFloat(target - from) * tabWidth
            dragOffset = point.x - dragStartX
            dragIndex = target
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let i = pressedClose {
            pressedClose = nil
            if i < items.count, closeRect(i).contains(point) { onClose?(i) }
        }
        dragIndex = nil
        dragOffset = 0
        updateHover(point)
        needsDisplay = true
    }

    /// The middle mouse button closes a tab (like in a browser).
    override func otherMouseUp(with event: NSEvent) {
        guard event.buttonNumber == 2, let i = index(at: convert(event.locationInWindow, from: nil)) else { return }
        onClose?(i)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = index(at: convert(event.locationInWindow, from: nil)) else { return nil }
        let menu = NSMenu()
        func add(_ title: String, _ handler: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let action = MenuAction(handler)
            item.target = action
            item.representedObject = action      // keeps the action alive while the menu is open
            menu.addItem(item)
        }
        add("Close Tab") { [weak self] in self?.onClose?(i) }
        if items.count > 1 { add("Close Other Tabs") { [weak self] in self?.onCloseOthers?(i) } }
        menu.addItem(.separator())
        add("New Tab") { [weak self] in self?.onNewTab?() }
        if !items[i].toolTip.isEmpty && items[i].toolTip.hasPrefix("/") {
            menu.addItem(.separator())
            add("Show in Finder") { [weak self] in self?.onRevealInFinder?(i) }
        }
        return menu
    }

    private final class MenuAction: NSObject {
        let handler: () -> Void
        init(_ handler: @escaping () -> Void) { self.handler = handler }
        @objc func run() { handler() }
    }

    // MARK: Tooltip (with the file path)

    private let toolTips = ToolTipTexts()

    private func rebuildToolTips() {
        toolTips.removeAll(from: self)
        for i in items.indices {
            toolTips.add(items[i].toolTip, rect: tabRect(i), to: self)
        }
        toolTips.add("New drawing in a new tab (⌘T)", rect: plusRect, to: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildToolTips()
        needsDisplay = true
    }
}
