//
//  FloatingPalettes.swift
//  OhMyCAD
//
//  Floating tool palettes on top of the drawing area. A tool (or a whole group) dragged out of the
//  tool panel and dropped on the drawing makes a new palette or joins the palette it was dropped on.
//  A tool dragged out of a palette moves to another palette, a new one, or leaves.
//  The buttons come from the tool panel, so they look and behave the same.
//

import Cocoa

/// One saved floating palette: its tools and where it lies.
/// The position is held to the nearest corner of the drawing area, so a palette keeps its place
/// when the window changes size.
nonisolated struct FloatingPaletteRecord: Codable {
    var id = UUID()
    /// Tool titles (titles survive adding new tools).
    var tools: [String]
    var vertical = false
    var anchorRight = false
    var anchorBottom = false
    /// Distance from the anchored corner to the palette's nearest corner.
    var dx: CGFloat = 0
    var dy: CGFloat = 0
}

extension FloatingPaletteRecord {
    @MainActor var drawingTools: [DrawingTool] {
        return tools.compactMap { title in DrawingTool.availableTools.first { $0.title == title } }
    }
}

/// The palettes, kept in the app's settings on this Mac (like the tool panel layout).
enum FloatingPaletteStore {
    private static let key = "FloatingPalettes"

    static var records: [FloatingPaletteRecord] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let records = try? JSONDecoder().decode([FloatingPaletteRecord].self, from: data) else { return [] }
            return records.filter { !$0.drawingTools.isEmpty }
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }
        }
    }
}

/// Transparent layer over the drawing area that holds the palettes.
/// Clicks outside the palettes go through to the drawing.
final class FloatingPaletteLayer: NSView {
    /// Makes a tool button that behaves like those in the tool panel (set by the window controller).
    var makeButton: ((DrawingTool) -> ToolButtonView?)?

    private var palettes: [FloatingPaletteView] = []

    override var isFlipped: Bool { return true }

    // only the palettes take the mouse, the empty layer does not
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Is the point (in window coordinates) over a palette? Over a palette the drawing hides its crosshair.
    func isOverPalette(_ windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        return palettes.contains { $0.frame.contains(point) }
    }

    /// Builds all palettes again from the saved records.
    func reload() {
        palettes.forEach { $0.removeFromSuperview() }
        palettes = FloatingPaletteStore.records.map { makePalette($0) }
        layoutPalettes()
    }

    /// Tools dropped from the tool panel or from a palette (source): over a palette they join it at the place
    /// under the mouse, over an empty place of the drawing they start a new palette, elsewhere a tool from
    /// a palette just leaves it. A palette left without tools disappears.
    func dropTools(_ tools: [DrawingTool], atWindowPoint windowPoint: NSPoint, from source: UUID? = nil) {
        let point = convert(windowPoint, from: nil)
        let titles = tools.map { $0.title }
        var records = FloatingPaletteStore.records
        let target = bounds.contains(point) ? palettes.first { $0.frame.contains(point) } : nil
        // the place in the target palette, counted without the tools that are being moved
        var slot = 0
        if let target = target {
            let raw = target.slot(at: convert(point, to: target))
            slot = raw - target.record.tools.prefix(raw).filter { titles.contains($0) }.count
        }
        if let source = source, let index = records.firstIndex(where: { $0.id == source }) {
            records[index].tools.removeAll { titles.contains($0) }
        }
        if let target = target, let index = records.firstIndex(where: { $0.id == target.record.id }) {
            records[index].tools.removeAll { titles.contains($0) }
            records[index].tools.insert(contentsOf: titles, at: min(slot, records[index].tools.count))
        } else if bounds.contains(point) {
            var record = FloatingPaletteRecord(tools: titles)
            let size = FloatingPaletteView.size(toolCount: titles.count, vertical: false)
            anchor(&record, frame: NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                          width: size.width, height: size.height))
            records.append(record)
        } else if source == nil {
            return
        }
        records.removeAll { $0.tools.isEmpty }
        FloatingPaletteStore.records = records
        // the drag that brought the tools is still finishing on the old buttons – rebuild right after it
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    private func makePalette(_ record: FloatingPaletteRecord) -> FloatingPaletteView {
        var buttons: [ToolButtonView] = []
        for tool in record.drawingTools {
            guard let button = makeButton?(tool) else { continue }
            // a tool dragged out of the palette goes to another palette, a new one, or away
            button.onDrag = { [weak self, weak button] phase, event in
                guard let self = self else { return }
                switch phase {
                case .moved:
                    ToolDragGhost.shared.show(button?.image, for: event)
                case .ended:
                    ToolDragGhost.shared.hide()
                    self.dropTools([tool], atWindowPoint: event.locationInWindow, from: record.id)
                }
            }
            buttons.append(button)
        }
        let palette = FloatingPaletteView(record: record, buttons: buttons)
        palette.onDrag = { [weak self, weak palette] phase, offset in
            guard let self = self, let palette = palette else { return }
            self.paletteDragged(palette, phase: phase, offset: offset)
        }
        palette.menuProvider = { [weak self, weak palette] in
            guard let self = self, let palette = palette else { return nil }
            return self.makePaletteMenu(palette)
        }
        addSubview(palette)
        return palette
    }

    // MARK: Position

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPalettes()
    }

    /// Places every palette from its record, always fully inside the drawing area.
    private func layoutPalettes() {
        for palette in palettes {
            let record = palette.record
            let size = palette.frame.size
            var origin = NSPoint(x: record.anchorRight ? bounds.maxX - record.dx - size.width : record.dx,
                                 y: record.anchorBottom ? bounds.maxY - record.dy - size.height : record.dy)
            origin.x = max(0, min(origin.x, bounds.maxX - size.width))
            origin.y = max(0, min(origin.y, bounds.maxY - size.height))
            palette.setFrameOrigin(origin)
        }
    }

    /// Holds the frame to the nearest corner of the layer.
    private func anchor(_ record: inout FloatingPaletteRecord, frame: NSRect) {
        record.anchorRight = frame.midX > bounds.midX
        record.anchorBottom = frame.midY > bounds.midY
        record.dx = max(0, record.anchorRight ? bounds.maxX - frame.maxX : frame.minX)
        record.dy = max(0, record.anchorBottom ? bounds.maxY - frame.maxY : frame.minY)
    }

    private var dragStartOrigin: NSPoint = .zero
    /// How close (points) a moved palette must come to another one to merge with it.
    private let mergeDistance: CGFloat = 12

    /// The palette a moved palette would merge with – the nearest one within the merge distance.
    private func mergeTarget(for moved: FloatingPaletteView) -> FloatingPaletteView? {
        let reach = moved.frame.insetBy(dx: -mergeDistance, dy: -mergeDistance)
        return palettes.filter { $0 !== moved && $0.frame.intersects(reach) }.min { a, b in
            hypot(a.frame.midX - moved.frame.midX, a.frame.midY - moved.frame.midY)
                < hypot(b.frame.midX - moved.frame.midX, b.frame.midY - moved.frame.midY)
        }
    }

    /// Moving a palette by its background: it follows the mouse inside the drawing area and remembers the place.
    /// Brought close to another palette, that one lights up and on release the two merge into one.
    private func paletteDragged(_ palette: FloatingPaletteView, phase: ToolDragPhase, offset: CGSize) {
        switch phase {
        case .moved:
            if !palette.isMoving {
                palette.isMoving = true
                dragStartOrigin = palette.frame.origin
            }
            // the offset is in window coordinates (y up), the layer is flipped (y down)
            var origin = NSPoint(x: dragStartOrigin.x + offset.width, y: dragStartOrigin.y - offset.height)
            origin.x = max(0, min(origin.x, bounds.maxX - palette.frame.width))
            origin.y = max(0, min(origin.y, bounds.maxY - palette.frame.height))
            palette.setFrameOrigin(origin)
            let target = mergeTarget(for: palette)
            palettes.forEach { $0.isMergeTarget = $0 === target }
        case .ended:
            palette.isMoving = false
            let target = mergeTarget(for: palette)
            palettes.forEach { $0.isMergeTarget = false }
            var records = FloatingPaletteStore.records
            guard let index = records.firstIndex(where: { $0.id == palette.record.id }) else { return }
            if let target = target, let targetIndex = records.firstIndex(where: { $0.id == target.record.id }) {
                // the tools of the moved palette go to the side it came from
                let moved = records[index].tools.filter { !records[targetIndex].tools.contains($0) }
                let before = target.record.vertical ? palette.frame.midY < target.frame.midY
                                                    : palette.frame.midX < target.frame.midX
                records[targetIndex].tools.insert(contentsOf: moved, at: before ? 0 : records[targetIndex].tools.count)
                records.remove(at: index)
                FloatingPaletteStore.records = records
                // the drag is still finishing on the old palette – rebuild right after it
                DispatchQueue.main.async { [weak self] in self?.reload() }
                return
            }
            anchor(&records[index], frame: palette.frame)
            palette.record = records[index]
            FloatingPaletteStore.records = records
        }
    }

    // MARK: Menu

    private func makePaletteMenu(_ palette: FloatingPaletteView) -> NSMenu {
        let menu = NSMenu(title: "Palette")
        let close = NSMenuItem(title: "Close Palette", action: #selector(closePalette(_:)), keyEquivalent: "")
        close.target = self
        close.representedObject = palette.record.id.uuidString
        menu.addItem(close)
        let closeAll = NSMenuItem(title: "Close All Palettes", action: #selector(closeAllPalettes(_:)), keyEquivalent: "")
        closeAll.target = self
        menu.addItem(closeAll)
        return menu
    }

    @objc private func closeAllPalettes(_ sender: NSMenuItem) {
        FloatingPaletteStore.records = []
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    @objc private func closePalette(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        FloatingPaletteStore.records.removeAll { $0.id.uuidString == id }
        // the menu is still closing – rebuild right after it
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }
}

/// One floating palette: a row of tool buttons on a dark rounded background with a handle on top.
/// Dragging the background moves the palette (close to another one it merges), right-click opens its menu.
final class FloatingPaletteView: NSView {
    var record: FloatingPaletteRecord
    /// Dragging: offset in window coordinates since the drag started.
    var onDrag: ((ToolDragPhase, CGSize) -> Void)?
    var menuProvider: (() -> NSMenu?)?
    var isMoving = false
    /// Lit up while another palette is brought close – on release they merge.
    var isMergeTarget = false {
        didSet {
            guard isMergeTarget != oldValue else { return }
            layer?.borderWidth = isMergeTarget ? 2 : 1
            layer?.borderColor = (isMergeTarget ? Theme.accent : Theme.panelBorder).cgColor
        }
    }

    static let handleHeight: CGFloat = 9
    static let padding: CGFloat = 4
    static let buttonSize = NSSize(width: 34, height: 32)
    static let gap: CGFloat = 2

    static func size(toolCount: Int, vertical: Bool) -> NSSize {
        let count = CGFloat(max(1, toolCount))
        let along = count * (vertical ? buttonSize.height : buttonSize.width) + (count - 1) * gap
        return vertical
            ? NSSize(width: buttonSize.width + 2 * padding, height: handleHeight + along + padding)
            : NSSize(width: along + 2 * padding, height: handleHeight + buttonSize.height + padding)
    }

    private var mouseDownPoint: NSPoint?

    init(record: FloatingPaletteRecord, buttons: [ToolButtonView]) {
        self.record = record
        super.init(frame: NSRect(origin: .zero, size: FloatingPaletteView.size(toolCount: buttons.count, vertical: record.vertical)))
        wantsLayer = true
        layer?.backgroundColor = Theme.toolbarBackground.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = Theme.panelBorder.cgColor
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        self.shadow = shadow
        for (index, button) in buttons.enumerated() {
            let step = CGFloat(index)
            button.setFrameOrigin(record.vertical
                ? NSPoint(x: FloatingPaletteView.padding, y: FloatingPaletteView.handleHeight + step * (FloatingPaletteView.buttonSize.height + FloatingPaletteView.gap))
                : NSPoint(x: FloatingPaletteView.padding + step * (FloatingPaletteView.buttonSize.width + FloatingPaletteView.gap), y: FloatingPaletteView.handleHeight))
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // the handle: a short bar in the middle of the top edge
        let bar = NSRect(x: bounds.midX - 12, y: 3, width: 24, height: 3)
        Theme.dragHandle.setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
    }

    // an arrow over the palette, not the drawing's crosshair; an open hand on the handle
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: FloatingPaletteView.handleHeight), cursor: .openHand)
    }

    /// Index of the button place nearest to the point (in the palette's coordinates), 0…tool count.
    func slot(at point: NSPoint) -> Int {
        let step = record.vertical ? FloatingPaletteView.buttonSize.height + FloatingPaletteView.gap
                                   : FloatingPaletteView.buttonSize.width + FloatingPaletteView.gap
        let along = record.vertical ? point.y - FloatingPaletteView.handleHeight : point.x - FloatingPaletteView.padding
        return max(0, min(Int((along / step).rounded()), record.tools.count))
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        onDrag?(.moved, CGSize(width: event.locationInWindow.x - start.x, height: event.locationInWindow.y - start.y))
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        if isMoving { onDrag?(.ended, .zero) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return menuProvider?()
    }
}
