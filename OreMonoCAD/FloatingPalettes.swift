//
//  FloatingPalettes.swift
//  OreMonoCAD
//
//  Floating tool palettes on top of the drawing area. A tool (or a whole group) dragged out of the
//  tool panel and dropped on the drawing makes a new palette or joins the palette it was dropped on.
//  A tool dragged out of a palette moves to another palette, a new one, or leaves.
//  A whole group dragged out by its heading moves: it leaves the tool panel and comes back
//  when its palette closes or is dragged back onto the tool panel.
//  A palette brought to the left or right edge of the drawing snaps to it; palettes on one edge
//  line up next to each other. A palette brought to the top goes to the palette bar at the top
//  of the window, above the drawing tabs. The grip on the right side changes the number of columns.
//  The buttons come from the tool panel, so they look and behave the same.
//

import Cocoa

/// The edges a palette can be held to (the bottom is left to the status bar and command line).
/// Top = the palette bar above the drawing tabs, left and right = the sides of the drawing.
nonisolated enum PaletteEdge: String, Codable {
    case top, left, right
}

/// One saved floating palette: its tools and where it lies.
/// The position is held to the nearest corner of the drawing area, so a palette keeps its place
/// when the window changes size. In the palette bar dx only gives the order.
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
    /// The edge the palette is held to (nil = it lies freely).
    var edge: PaletteEdge?
    /// Buttons in one row (nil = all in one row, or one column for a vertical palette).
    var columns: Int?
    /// Tool panel sections (titles) moved to this palette – hidden in the panel until the palette closes.
    var sections: [String]?
}

extension FloatingPaletteRecord {
    @MainActor var drawingTools: [DrawingTool] {
        var result: [DrawingTool] = []
        for title in tools {
            // a tool that is no longer first of its combined button stands for that button (as in Favorites)
            if let tool = DrawingTool.availableTools.first(where: { $0.title == title })?.paletteLeader,
               !result.contains(tool) {
                result.append(tool)
            }
        }
        return result
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

/// Where a dragged palette is over: the window parts it can be dropped on.
private enum PaletteDropZone {
    /// The palette bar at the top or the drawing tabs below it.
    case topBar
    /// The tool panel on the left – the palette goes back there.
    case toolPanel
    case drawing
    /// Anywhere else (the right panel, the status bar) – the palette stays where it was.
    case none
}

/// Transparent layer over the drawing area that holds the palettes.
/// Clicks outside the palettes go through to the drawing.
final class FloatingPaletteLayer: NSView {
    /// Makes a tool button that behaves like those in the tool panel (set by the window controller).
    var makeButton: ((DrawingTool) -> ToolButtonView?)?
    /// A section was hidden in or given back to the tool panel – the panel lays itself out again.
    var onPanelLayoutChanged: (() -> Void)?
    /// The bar at the top of the window for the palettes held to the top (set by the window controller).
    weak var dockBar: PaletteDockBar?

    /// All palettes – those on the drawing and those in the palette bar.
    private var palettes: [FloatingPaletteView] = []
    private var drawingPalettes: [FloatingPaletteView] { return palettes.filter { $0.superview === self } }

    override var isFlipped: Bool { return true }

    // only the palettes take the mouse, the empty layer does not
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Is the point (in window coordinates) over a palette? Over a palette the drawing hides its crosshair.
    func isOverPalette(_ windowPoint: NSPoint) -> Bool {
        let point = convert(windowPoint, from: nil)
        return drawingPalettes.contains { $0.frame.contains(point) }
    }

    /// Builds all palettes again from the saved records.
    func reload() {
        palettes.forEach { $0.removeFromSuperview() }
        palettes = FloatingPaletteStore.records.map { makePalette($0) }
        let barPalettes = palettes.filter { $0.record.edge == .top }
        for palette in palettes where palette.record.edge != .top { addSubview(palette) }
        dockBar?.setPalettes(barPalettes)
        layoutPalettes()
    }

    /// The palette (on the drawing or in the palette bar) under a point in window coordinates.
    private func palette(atWindowPoint windowPoint: NSPoint) -> FloatingPaletteView? {
        return palettes.first { palette in
            guard let parent = palette.superview else { return false }
            return palette.frame.contains(parent.convert(windowPoint, from: nil))
        }
    }

    /// Tools dropped from the tool panel or from a palette (source): over a palette they join it at the place
    /// under the mouse, over an empty place of the drawing or the palette bar they start a new palette,
    /// elsewhere a tool from a palette just leaves it. A palette left without tools disappears.
    /// A whole tool panel section (its title) moves: it is hidden in the panel while it lies in a palette.
    func dropTools(_ tools: [DrawingTool], atWindowPoint windowPoint: NSPoint, from source: UUID? = nil, section: String? = nil) {
        let point = convert(windowPoint, from: nil)
        let titles = tools.map { $0.title }
        var records = FloatingPaletteStore.records
        let target = palette(atWindowPoint: windowPoint)
        let overBar = dockBar.map { !$0.isHidden && $0.bounds.contains($0.convert(windowPoint, from: nil)) } ?? false
        // the place in the target palette, counted without the tools that are being moved
        var slot = 0
        if let target = target {
            let raw = target.slot(at: target.convert(windowPoint, from: nil))
            slot = raw - target.record.tools.prefix(raw).filter { titles.contains($0) }.count
        }
        if let source = source, let index = records.firstIndex(where: { $0.id == source }) {
            records[index].tools.removeAll { titles.contains($0) }
        }
        if let target = target, let index = records.firstIndex(where: { $0.id == target.record.id }) {
            records[index].tools.removeAll { titles.contains($0) }
            records[index].tools.insert(contentsOf: titles, at: min(slot, records[index].tools.count))
            if let section = section { records[index].sections = (records[index].sections ?? []) + [section] }
        } else if bounds.contains(point) || overBar {
            var record = FloatingPaletteRecord(tools: titles)
            record.sections = section.map { [$0] }
            if overBar, let bar = dockBar {
                record.edge = .top
                record.dx = bar.convert(windowPoint, from: nil).x
            } else {
                let size = FloatingPaletteView.size(toolCount: titles.count, columns: titles.count, titled: section != nil)
                anchor(&record, frame: NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                              width: size.width, height: size.height))
            }
            records.append(record)
        } else if source == nil {
            return
        }
        if let section = section.flatMap({ ToolPanelSection(title: $0) }) {
            ToolPanelLayout.hidden.insert(section)
            onPanelLayoutChanged?()
        }
        // a palette left without tools gives its sections back to the panel
        giveBack(records.filter { $0.tools.isEmpty })
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
        palette.onDrag = { [weak self, weak palette] phase, offset, event in
            guard let self = self, let palette = palette else { return }
            self.paletteDragged(palette, phase: phase, offset: offset, event: event)
        }
        palette.onResize = { [weak self, weak palette] phase in
            guard let self = self, let palette = palette else { return }
            self.paletteResized(palette, phase: phase)
        }
        palette.menuProvider = { [weak self, weak palette] in
            guard let self = self, let palette = palette else { return nil }
            return self.makePaletteMenu(palette)
        }
        return palette
    }

    // MARK: Position

    /// How close (points) a palette must come to a drawing edge, or to the palette before it on an edge, to snap.
    private let snapDistance: CGFloat = 16
    /// The edge a moved palette will snap to – drawn as a highlighted line.
    private var highlightedEdge: PaletteEdge? {
        didSet {
            guard highlightedEdge != oldValue else { return }
            needsDisplay = true
            dockBar?.isHighlighted = highlightedEdge == .top
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let edge = highlightedEdge else { return }
        let thickness: CGFloat = 3
        let line: NSRect
        switch edge {
        case .top: line = NSRect(x: 0, y: 0, width: bounds.width, height: thickness)
        case .left: line = NSRect(x: 0, y: 0, width: thickness, height: bounds.height)
        case .right: line = NSRect(x: bounds.maxX - thickness, y: 0, width: thickness, height: bounds.height)
        }
        Theme.accent.setFill()
        line.fill()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPalettes()
    }

    /// Places every palette on the drawing from its record, always fully inside the drawing area.
    /// Palettes held to a side touch it and line up along it without overlapping.
    private func layoutPalettes() {
        for palette in drawingPalettes {
            let record = palette.record
            let size = palette.frame.size
            var origin = NSPoint(x: record.anchorRight ? bounds.maxX - record.dx - size.width : record.dx,
                                 y: record.anchorBottom ? bounds.maxY - record.dy - size.height : record.dy)
            origin.x = max(0, min(origin.x, bounds.maxX - size.width))
            origin.y = max(0, min(origin.y, bounds.maxY - size.height))
            switch record.edge {
            case .left?: origin.x = 0
            case .right?: origin.x = bounds.maxX - size.width
            case .top?, nil: break
            }
            palette.setFrameOrigin(origin)
        }
        lineUp(on: .left)
        lineUp(on: .right)
        dockBar?.layoutPalettes()
    }

    /// Lines up the palettes held to one side: each starts where the one before it ends,
    /// or a bit later when the user left a gap larger than the snap distance.
    private func lineUp(on edge: PaletteEdge) {
        let docked = drawingPalettes.filter { $0.record.edge == edge }.sorted { $0.frame.minY < $1.frame.minY }
        var end: CGFloat = 0
        for palette in docked {
            var origin = palette.frame.origin
            if origin.y < end || origin.y - end < snapDistance { origin.y = end }
            palette.setFrameOrigin(origin)
            end = palette.frame.maxY
        }
    }

    /// The edge a palette with this frame would snap to – the nearest one within the snap distance.
    private func edgeCandidate(for frame: NSRect) -> PaletteEdge? {
        let distances: [(PaletteEdge, CGFloat)] = [(.top, frame.minY), (.left, frame.minX), (.right, bounds.maxX - frame.maxX)]
        return distances.filter { $0.1 <= snapDistance }.min { $0.1 < $1.1 }?.0
    }

    /// Holds the frame to the nearest corner of the layer.
    private func anchor(_ record: inout FloatingPaletteRecord, frame: NSRect) {
        record.anchorRight = frame.midX > bounds.midX
        record.anchorBottom = frame.midY > bounds.midY
        record.dx = max(0, record.anchorRight ? bounds.maxX - frame.maxX : frame.minX)
        record.dy = max(0, record.anchorBottom ? bounds.maxY - frame.maxY : frame.minY)
    }

    /// The window part under a point in window coordinates.
    private func dropZone(atWindowPoint windowPoint: NSPoint) -> PaletteDropZone {
        if let bar = dockBar, !bar.isHidden, bar.bounds.contains(bar.convert(windowPoint, from: nil)) { return .topBar }
        let point = convert(windowPoint, from: nil)
        if bounds.contains(point) { return .drawing }
        // the drawing tabs lie right above the drawing (the layer is flipped: above = negative y)
        if point.y < 0 && point.y > -DrawingTabBarView.height && point.x >= 0 && point.x <= bounds.maxX { return .topBar }
        if point.x < 0 { return .toolPanel }
        return .none
    }

    private var dragStartOrigin: NSPoint = .zero
    /// How close (points) a moved palette must come to another one to merge with it.
    private let mergeDistance: CGFloat = 12

    /// The palette a moved palette would merge with – the nearest one within the merge distance.
    /// At an edge the palettes line up instead, so there the moved palette must cover the middle of the other one.
    private func mergeTarget(for moved: FloatingPaletteView, atEdge edge: PaletteEdge?) -> FloatingPaletteView? {
        let reach = moved.frame.insetBy(dx: -mergeDistance, dy: -mergeDistance)
        return drawingPalettes.filter { other in
            guard other !== moved, other.frame.intersects(reach) else { return false }
            return edge == nil || moved.frame.contains(NSPoint(x: other.frame.midX, y: other.frame.midY))
        }.min { a, b in
            hypot(a.frame.midX - moved.frame.midX, a.frame.midY - moved.frame.midY)
                < hypot(b.frame.midX - moved.frame.midX, b.frame.midY - moved.frame.midY)
        }
    }

    /// Moving a palette by its background. On the drawing it follows the mouse and remembers the place;
    /// close to another palette that one lights up and on release the two merge; close to an edge the edge
    /// lights up and on release the palette snaps to it (to the top = into the palette bar).
    /// In the palette bar it moves along the bar. Outside its own area a picture of it follows the mouse:
    /// released on the tool panel the palette closes and its groups go back to the panel.
    private func paletteDragged(_ palette: FloatingPaletteView, phase: ToolDragPhase, offset: CGSize, event: NSEvent) {
        let inBar = palette.superview !== self
        let zone = dropZone(atWindowPoint: event.locationInWindow)
        // the palette moves itself only inside its own area, elsewhere its picture follows the mouse
        let ownArea = inBar ? zone == .topBar : zone == .drawing
        switch phase {
        case .moved:
            if !palette.isMoving {
                palette.isMoving = true
                dragStartOrigin = palette.frame.origin
            }
            palette.alphaValue = ownArea ? 1 : 0.35
            if ownArea {
                PaletteDragGhost.shared.hide()
            } else {
                PaletteDragGhost.shared.show(palette, for: event)
            }
            if inBar {
                if ownArea, let bar = dockBar {
                    let x = max(0, min(dragStartOrigin.x + offset.width, bar.bounds.maxX - palette.frame.width))
                    palette.setFrameOrigin(NSPoint(x: x, y: palette.frame.minY))
                }
                highlightedEdge = nil
                return
            }
            if ownArea {
                // the offset is in window coordinates (y up), the layer is flipped (y down)
                var origin = NSPoint(x: dragStartOrigin.x + offset.width, y: dragStartOrigin.y - offset.height)
                origin.x = max(0, min(origin.x, bounds.maxX - palette.frame.width))
                origin.y = max(0, min(origin.y, bounds.maxY - palette.frame.height))
                palette.setFrameOrigin(origin)
            }
            let edge: PaletteEdge? = ownArea ? edgeCandidate(for: palette.frame) : (zone == .topBar ? .top : nil)
            let target = ownArea ? mergeTarget(for: palette, atEdge: edge) : nil
            drawingPalettes.forEach { $0.isMergeTarget = $0 === target }
            highlightedEdge = target == nil ? edge : nil
        case .ended:
            palette.isMoving = false
            palette.alphaValue = 1
            PaletteDragGhost.shared.hide()
            highlightedEdge = nil
            drawingPalettes.forEach { $0.isMergeTarget = false }
            switch zone {
            case .toolPanel:
                closePalettes { $0.id == palette.record.id }
            case .topBar:
                let x = dockBar?.convert(event.locationInWindow, from: nil).x ?? 0
                moveToBar(palette, at: inBar ? palette.frame.minX : x - palette.frame.width / 2)
            case .drawing where inBar:
                // out of the bar onto the drawing: the palette lies where it was dropped
                let point = convert(event.locationInWindow, from: nil)
                let size = palette.frame.size
                let frame = NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                place(palette, frame: frame, edge: nil)
            case .drawing:
                let edge = edgeCandidate(for: palette.frame)
                if edge == .top {
                    moveToBar(palette, at: palette.frame.minX)
                } else if let target = mergeTarget(for: palette, atEdge: edge) {
                    merge(palette, into: target)
                } else {
                    place(palette, frame: palette.frame, edge: edge)
                }
            case .none:
                break
            }
            // the drag is still finishing on the old palette – rebuild right after it
            DispatchQueue.main.async { [weak self] in self?.reload() }
        }
    }

    /// Puts the palette into the palette bar at a place along it (x in the bar); a column becomes a row.
    private func moveToBar(_ palette: FloatingPaletteView, at x: CGFloat) {
        var records = FloatingPaletteStore.records
        guard let index = records.firstIndex(where: { $0.id == palette.record.id }) else { return }
        // the order in the bar: the others by their place now, the moved one by the place it was dropped at
        for i in records.indices where i != index && records[i].edge == .top {
            if let view = palettes.first(where: { $0.record.id == records[i].id }) { records[i].dx = view.frame.minX }
        }
        records[index].edge = .top
        records[index].dx = x
        if palette.frame.height > palette.frame.width {
            records[index].columns = records[index].tools.count
            records[index].vertical = false
        }
        FloatingPaletteStore.records = records
    }

    /// Lays the palette on the drawing (or at a side): a row put on a side becomes a column.
    private func place(_ palette: FloatingPaletteView, frame: NSRect, edge: PaletteEdge?) {
        var records = FloatingPaletteStore.records
        guard let index = records.firstIndex(where: { $0.id == palette.record.id }) else { return }
        records[index].edge = edge
        var frame = frame
        if (edge == .left || edge == .right) && frame.width > frame.height {
            records[index].columns = 1
            records[index].vertical = true
            frame.size = FloatingPaletteView.size(toolCount: records[index].tools.count, columns: 1,
                                                  titled: !(records[index].sections ?? []).isEmpty)
        }
        frame.origin.x = max(0, min(frame.origin.x, bounds.maxX - frame.width))
        frame.origin.y = max(0, min(frame.origin.y, bounds.maxY - frame.height))
        switch edge {
        case .left?: frame.origin.x = 0
        case .right?: frame.origin.x = bounds.maxX - frame.width
        case .top?, nil: break
        }
        anchor(&records[index], frame: frame)
        FloatingPaletteStore.records = records
    }

    /// The tools (and groups) of the moved palette join the target, on the side the moved one came from.
    private func merge(_ palette: FloatingPaletteView, into target: FloatingPaletteView) {
        var records = FloatingPaletteStore.records
        guard let index = records.firstIndex(where: { $0.id == palette.record.id }),
              let targetIndex = records.firstIndex(where: { $0.id == target.record.id }) else { return }
        let moved = records[index].tools.filter { !records[targetIndex].tools.contains($0) }
        let before = target.frame.height > target.frame.width ? palette.frame.midY < target.frame.midY
                                                              : palette.frame.midX < target.frame.midX
        records[targetIndex].tools.insert(contentsOf: moved, at: before ? 0 : records[targetIndex].tools.count)
        if let sections = records[index].sections {
            records[targetIndex].sections = (records[targetIndex].sections ?? []) + sections
        }
        records.remove(at: index)
        FloatingPaletteStore.records = records
    }

    /// Changing the number of columns by the grip: the palette keeps the corner it is held to,
    /// on release the new layout is remembered.
    private func paletteResized(_ palette: FloatingPaletteView, phase: ToolDragPhase) {
        layoutPalettes()
        guard phase == .ended else { return }
        var records = FloatingPaletteStore.records
        guard let index = records.firstIndex(where: { $0.id == palette.record.id }) else { return }
        records[index].columns = palette.record.columns
        records[index].vertical = palette.record.columns == 1 && records[index].tools.count > 1
        if palette.superview === self { anchor(&records[index], frame: palette.frame) }
        palette.record = records[index]
        FloatingPaletteStore.records = records
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
        closePalettes { _ in true }
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    @objc private func closePalette(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        closePalettes { $0.id.uuidString == id }
        // the menu is still closing – rebuild right after it
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    /// Closes the palettes; their groups go back to the tool panel.
    private func closePalettes(where matches: (FloatingPaletteRecord) -> Bool) {
        var records = FloatingPaletteStore.records
        giveBack(records.filter(matches))
        records.removeAll(where: matches)
        FloatingPaletteStore.records = records
    }

    /// The tool panel layout was reset: its sections are all shown again, so the palettes holding them close.
    func closeGroupPalettes() {
        FloatingPaletteStore.records.removeAll { !($0.sections ?? []).isEmpty }
        reload()
    }

    /// Shows the sections of these palettes in the tool panel again (at their old places).
    private func giveBack(_ records: [FloatingPaletteRecord]) {
        let sections = records.flatMap { $0.sections ?? [] }.compactMap { ToolPanelSection(title: $0) }
        guard !sections.isEmpty else { return }
        ToolPanelLayout.hidden.subtract(sections)
        onPanelLayoutChanged?()
    }
}

/// The bar at the top of the window, above the drawing tabs, for the palettes held to the top.
/// The palettes stand in a row (in more rows when they don't fit); without palettes the bar has no height.
final class PaletteDockBar: NSView {
    /// The bar's height changed – the window lays out its parts again.
    var onHeightChanged: ((CGFloat) -> Void)?
    /// Lit up while a palette is brought to the top – on release it goes into the bar.
    var isHighlighted = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    private var palettes: [FloatingPaletteView] = []
    private(set) var barHeight: CGFloat = 0
    private let padding: CGFloat = 3
    private let gap: CGFloat = 4

    override var isFlipped: Bool { return true }

    /// Takes over the palettes held to the top (in the order of their saved places).
    func setPalettes(_ newPalettes: [FloatingPaletteView]) {
        palettes = newPalettes.sorted { $0.record.dx < $1.record.dx }
        for palette in palettes {
            palette.shadow = nil
            addSubview(palette)
        }
        layoutPalettes()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPalettes()
    }

    /// Puts the palettes in a row from the left, wrapping to a new row when the bar is full.
    func layoutPalettes() {
        var x = padding, y = padding, rowHeight: CGFloat = 0
        for palette in palettes where palette.superview === self {
            let size = palette.frame.size
            if x > padding && x + size.width > bounds.width - padding {
                x = padding
                y += rowHeight + gap
                rowHeight = 0
            }
            if !palette.isMoving { palette.setFrameOrigin(NSPoint(x: x, y: y)) }
            x += size.width + gap
            rowHeight = max(rowHeight, size.height)
        }
        let height = rowHeight > 0 ? y + rowHeight + padding : 0
        if height != barHeight {
            barHeight = height
            onHeightChanged?(height)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.toolbarBackground.setFill()
        bounds.fill()
        // a line along the bottom, an accent one while a palette is brought here
        (isHighlighted ? Theme.accent : Theme.panelBorder).setFill()
        NSRect(x: 0, y: bounds.maxY - (isHighlighted ? 3 : 1), width: bounds.width, height: isHighlighted ? 3 : 1).fill()
    }
}

/// The picture of a dragged palette that follows the mouse across the whole window.
private final class PaletteDragGhost {
    static let shared = PaletteDragGhost()
    private let imageView = NSImageView()

    private init() {
        imageView.alphaValue = 0.8
        imageView.imageScaling = .scaleNone
    }

    /// Shows the palette's picture centered on the mouse of the event.
    func show(_ palette: NSView, for event: NSEvent) {
        guard let content = event.window?.contentView else { return }
        if imageView.superview !== content {
            if let rep = palette.bitmapImageRepForCachingDisplay(in: palette.bounds) {
                palette.cacheDisplay(in: palette.bounds, to: rep)
                let image = NSImage(size: palette.bounds.size)
                image.addRepresentation(rep)
                imageView.image = image
            }
            imageView.frame.size = palette.bounds.size
            content.addSubview(imageView, positioned: .above, relativeTo: nil)
        }
        let point = content.convert(event.locationInWindow, from: nil)
        imageView.setFrameOrigin(NSPoint(x: point.x - imageView.frame.width / 2, y: point.y - imageView.frame.height / 2))
    }

    func hide() {
        imageView.removeFromSuperview()
    }
}

/// One floating palette: tool buttons in rows on a dark rounded background, a handle on top
/// (on a palette made of groups their names instead) and a grip on the right side. Dragging the background moves the palette (close to another one
/// it merges, close to an edge it snaps), dragging the grip changes the number of columns,
/// right-click opens its menu.
final class FloatingPaletteView: NSView {
    var record: FloatingPaletteRecord
    /// Dragging: offset in window coordinates since the drag started, and the mouse event.
    var onDrag: ((ToolDragPhase, CGSize, NSEvent) -> Void)?
    /// Resizing by the grip: called after every change of the column count and on release.
    var onResize: ((ToolDragPhase) -> Void)?
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
    /// Height of the top of a palette made of tool panel groups – it shows their names (like the panel headings).
    static let titleHeight: CGFloat = 15
    static let padding: CGFloat = 4
    /// Width of the grip on the right side (in addition to the padding).
    static let gripWidth: CGFloat = 6
    static let buttonSize = NSSize(width: 34, height: 32)
    static let gap: CGFloat = 2

    /// titled = a palette made of tool panel groups (its top shows their names).
    static func topHeight(titled: Bool) -> CGFloat {
        return titled ? titleHeight : handleHeight
    }

    static func size(toolCount: Int, columns: Int, titled: Bool = false) -> NSSize {
        let count = max(1, toolCount)
        let columns = max(1, min(columns, count))
        let rows = (count + columns - 1) / columns
        let width = CGFloat(columns) * buttonSize.width + CGFloat(columns - 1) * gap
        let height = CGFloat(rows) * buttonSize.height + CGFloat(rows - 1) * gap
        return NSSize(width: width + 2 * padding + gripWidth, height: topHeight(titled: titled) + height + padding)
    }

    private let buttons: [ToolButtonView]
    private var mouseDownPoint: NSPoint?
    /// The drag started on the grip – it resizes, it does not move.
    private var isResizing = false
    private var resizeStartWidth: CGFloat = 0

    /// Buttons in one row: the saved count, or all in one row (one column for a vertical palette).
    var columnCount: Int {
        let count = max(1, buttons.count)
        if let columns = record.columns { return max(1, min(columns, count)) }
        return record.vertical ? 1 : count
    }

    /// The names of the groups the palette was made of (empty for a palette put together tool by tool).
    private var title: String {
        return (record.sections ?? []).map { $0.uppercased() }.joined(separator: " · ")
    }

    /// The top part: the group names, or just a handle.
    private var topHeight: CGFloat {
        return FloatingPaletteView.topHeight(titled: !title.isEmpty)
    }

    private var gripRect: NSRect {
        return NSRect(x: bounds.maxX - FloatingPaletteView.padding - FloatingPaletteView.gripWidth, y: topHeight,
                      width: FloatingPaletteView.padding + FloatingPaletteView.gripWidth, height: bounds.height - topHeight)
    }

    init(record: FloatingPaletteRecord, buttons: [ToolButtonView]) {
        self.record = record
        self.buttons = buttons
        super.init(frame: .zero)
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
        buttons.forEach { addSubview($0) }
        layoutButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Puts the buttons in rows of the current column count and sizes the palette to them.
    func layoutButtons() {
        let columns = columnCount
        setFrameSize(FloatingPaletteView.size(toolCount: buttons.count, columns: columns, titled: !title.isEmpty))
        for (index, button) in buttons.enumerated() {
            let column = CGFloat(index % columns)
            let row = CGFloat(index / columns)
            button.setFrameOrigin(NSPoint(x: FloatingPaletteView.padding + column * (FloatingPaletteView.buttonSize.width + FloatingPaletteView.gap),
                                          y: topHeight + row * (FloatingPaletteView.buttonSize.height + FloatingPaletteView.gap)))
        }
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override var isFlipped: Bool { return true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        Theme.dragHandle.setFill()
        if title.isEmpty {
            // the handle: a short bar in the middle of the top edge
            let bar = NSRect(x: bounds.midX - 12, y: 3, width: 24, height: 3)
            NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()
        } else {
            drawTitle()
        }
        // the grip: three dots in the middle of the right side
        let x = bounds.maxX - FloatingPaletteView.padding - FloatingPaletteView.gripWidth / 2
        let middle = (topHeight + bounds.maxY) / 2
        for step in -1...1 {
            NSBezierPath(ovalIn: NSRect(x: x - 1.5, y: middle + CGFloat(step) * 5 - 1.5, width: 3, height: 3)).fill()
        }
    }

    /// The group names centered in the top part, in the style of the tool panel headings;
    /// a long name gets a smaller font, and when even that is too wide the end is cut off.
    private func drawTitle() {
        let available = bounds.width - 2 * FloatingPaletteView.padding
        var fontSize: CGFloat = 9.5
        var attributes: [NSAttributedString.Key: Any] = [:]
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        repeat {
            attributes = [.font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                          .foregroundColor: Theme.textHeading, .paragraphStyle: paragraph]
            fontSize -= 0.5
        } while (title as NSString).size(withAttributes: attributes).width > available && fontSize >= 7
        let rect = NSRect(x: FloatingPaletteView.padding, y: 2, width: available, height: FloatingPaletteView.titleHeight - 2)
        (title as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    // an arrow over the palette, not the drawing's crosshair; an open hand on the handle, a resize cursor on the grip
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: topHeight), cursor: .openHand)
        addCursorRect(gripRect, cursor: .resizeLeftRight)
        removeAllToolTips()
        addToolTip(gripRect, owner: "Drag to change the number of columns" as NSString, userData: nil)
    }

    /// Index of the button place nearest to the point (in the palette's coordinates), 0…tool count.
    func slot(at point: NSPoint) -> Int {
        let columns = columnCount
        let column = Int(((point.x - FloatingPaletteView.padding) / (FloatingPaletteView.buttonSize.width + FloatingPaletteView.gap)).rounded())
        let row = Int((point.y - topHeight) / (FloatingPaletteView.buttonSize.height + FloatingPaletteView.gap))
        let slot = max(0, row) * columns + max(0, min(column, columns))
        return max(0, min(slot, record.tools.count))
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        isResizing = gripRect.contains(convert(event.locationInWindow, from: nil))
        resizeStartWidth = bounds.width
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let offset = CGSize(width: event.locationInWindow.x - start.x, height: event.locationInWindow.y - start.y)
        if isResizing {
            // the wanted width, rounded to whole columns
            let step = FloatingPaletteView.buttonSize.width + FloatingPaletteView.gap
            let inner = resizeStartWidth + offset.width - 2 * FloatingPaletteView.padding - FloatingPaletteView.gripWidth + FloatingPaletteView.gap
            let columns = max(1, min(Int((inner / step).rounded()), max(1, buttons.count)))
            guard columns != columnCount else { return }
            record.columns = columns
            layoutButtons()
            onResize?(.moved)
        } else {
            onDrag?(.moved, offset, event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard mouseDownPoint != nil else { return }
        mouseDownPoint = nil
        if isResizing {
            isResizing = false
            onResize?(.ended)
        } else if isMoving {
            onDrag?(.ended, .zero, event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return menuProvider?()
    }
}
