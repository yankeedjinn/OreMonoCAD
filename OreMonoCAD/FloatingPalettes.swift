//
//  FloatingPalettes.swift
//  OreMonoCAD
//
//  Floating tool palettes on top of the drawing area. A tool (or a whole group) dragged out of the
//  tool panel and dropped on the drawing makes a new palette or joins the palette it was dropped on.
//  A tool dragged out of a palette moves to another palette, a new one, or leaves.
//  A whole group dragged out by its heading moves: it leaves the tool panel and comes back
//  when its palette closes or is dragged back onto the tool panel.
//  A palette brought to an edge goes to the palette bar of that edge: at the top above the drawing tabs,
//  at the bottom under the drawing (above the layout tabs), at the left and right edge of the window
//  (beyond the tool panel and the right panel – a palette dropped on the right panel goes to the right bar).
//  The side bars look like the tool panel: two columns of buttons, all groups of one width. Dragging the right or bottom edge
//  of a palette changes the number of columns.
//  The buttons come from the tool panel, so they look and behave the same.
//

import Cocoa

/// The edges a palette can be held to.
/// Top = the palette bar above the drawing tabs, left and right = the palette bars at the left and right edge
/// of the window, bottom = the palette bar under the drawing
/// (above the layout tabs, the status bar and the command line).
nonisolated enum PaletteEdge: String, Codable {
    case top, left, right, bottom
}

/// One saved floating palette: its tools and where it lies.
/// The position is held to the nearest corner of the drawing area, so a palette keeps its place
/// when the window changes size. In a palette bar dx only gives the order along the bar.
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
    /// The name the user gave the palette (nil = the names of its groups, or “Custom Palette”).
    var name: String?
}

extension FloatingPaletteRecord {
    /// The tools of the palette's buttons. A tool dragged out on its own stays exactly that tool
    /// (so Circle and Ellipse can lie side by side); a tool of a group moved here by its heading
    /// stands for its combined button, as in the tool panel.
    @MainActor var drawingTools: [DrawingTool] {
        var result: [DrawingTool] = []
        for title in tools {
            guard let found = DrawingTool.availableTools.first(where: { $0.title == title }) else { continue }
            let tool = isCombined(found) ? found.paletteLeader : found
            if !result.contains(tool) { result.append(tool) }
        }
        return result
    }

    /// Does the tool sit on a combined button here (Trim / Extend, Fillet / Chamfer, …)?
    /// Only in a group moved to the palette – the button then offers the whole family, as in the panel.
    @MainActor func isCombined(_ tool: DrawingTool) -> Bool {
        guard tool.paletteFamily != nil else { return false }
        return (sections ?? []).compactMap { ToolPanelSection(title: $0) }.contains { $0.buttonTools.contains(tool.paletteLeader) }
    }
}

extension ToolPanelSection {
    /// The tools of the section's buttons in the tool panel (a combined button by its first tool).
    @MainActor var buttonTools: [DrawingTool] {
        switch self {
        case .favorites: return ToolPanelLayout.favorites
        case .group(let group): return DrawingTool.tools(in: group).filter { $0.paletteLeader == $0 }
        }
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
    /// The palette bar at the right edge of the window or the right panel next to it.
    case sideBar
    /// The palette bar at the left edge of the window (or the right panel moved to the left).
    case leftBar
    /// The palette bar under the drawing or the layout tabs below it.
    case bottomBar
    /// The tool panel on the left – the palette goes back there.
    case toolPanel
    case drawing
    /// Anywhere else (the status bar) – the palette stays where it was.
    case none
}

/// Transparent layer over the drawing area that holds the palettes.
/// Clicks outside the palettes go through to the drawing.
final class FloatingPaletteLayer: NSView {
    /// Makes a tool button that behaves like those in the tool panel (set by the window controller);
    /// combined = a button that offers the tool's whole family.
    var makeButton: ((DrawingTool, Bool) -> ToolButtonView?)?
    /// A section was hidden in or given back to the tool panel – the panel lays itself out again.
    var onPanelLayoutChanged: (() -> Void)?
    /// The bar at the top of the window for the palettes held to the top (set by the window controller).
    weak var dockBar: PaletteDockBar?
    /// The bar at the right edge of the window for the palettes held to the right (set by the window controller).
    weak var sideBar: PaletteDockBar?
    /// The tool panel on the left – a palette dropped on it goes back there (set by the window controller).
    weak var toolPanel: NSView?
    /// The bar at the left edge of the window for the palettes held to the left (set by the window controller).
    weak var leftBar: PaletteDockBar?
    /// The bar under the drawing for the palettes held to the bottom (set by the window controller).
    weak var bottomBar: PaletteDockBar?

    /// The bar that holds the palettes of an edge (nil = the palette lies on the drawing).
    private func bar(for edge: PaletteEdge?) -> PaletteDockBar? {
        switch edge {
        case .top?: return dockBar
        case .right?: return sideBar
        case .bottom?: return bottomBar
        case .left?: return leftBar
        case nil: return nil
        }
    }

    /// Compact view: palettes without titles, only a thin strip to hold them by (kept in the app's settings).
    static var isCompact: Bool {
        get { return UserDefaults.standard.bool(forKey: "FloatingPalettesCompact") }
        set { UserDefaults.standard.set(newValue, forKey: "FloatingPalettesCompact") }
    }

    /// All palettes – those on the drawing and those in the palette bars.
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
        // palettes in a side bar have as many icons in a row as the bar is set to
        var records = FloatingPaletteStore.records
        let wrong: (FloatingPaletteRecord) -> Bool = { record in
            guard let edge = record.edge, edge == .right || edge == .left else { return false }
            return record.columns != PaletteDockBar.iconsPerRow(for: edge) || record.vertical
        }
        if records.contains(where: wrong) {
            for index in records.indices where wrong(records[index]) {
                records[index].columns = PaletteDockBar.iconsPerRow(for: records[index].edge ?? .right)
                records[index].vertical = false
            }
            FloatingPaletteStore.records = records
        }
        palettes.forEach { $0.removeFromSuperview() }
        palettes = FloatingPaletteStore.records.map { makePalette($0) }
        for palette in palettes where bar(for: palette.record.edge) == nil { addSubview(palette) }
        dockBar?.setPalettes(palettes.filter { $0.record.edge == .top })
        sideBar?.setPalettes(palettes.filter { $0.record.edge == .right })
        leftBar?.setPalettes(palettes.filter { $0.record.edge == .left })
        bottomBar?.setPalettes(palettes.filter { $0.record.edge == .bottom })
        layoutPalettes()
    }

    /// The palette (on the drawing or in a palette bar) under a point in window coordinates.
    private func palette(atWindowPoint windowPoint: NSPoint) -> FloatingPaletteView? {
        return palettes.first { palette in
            guard let parent = palette.superview else { return false }
            return palette.frame.contains(parent.convert(windowPoint, from: nil))
        }
    }

    /// Tools dropped from the tool panel or from a palette (source): over a palette they join it at the place
    /// under the mouse, over an empty place of the drawing or a palette bar they start a new palette,
    /// elsewhere a tool from a palette just leaves it. A palette left without tools disappears.
    /// A whole tool panel section (its title) moves: it is hidden in the panel while it lies in a palette.
    func dropTools(_ tools: [DrawingTool], atWindowPoint windowPoint: NSPoint, from source: UUID? = nil, section: String? = nil) {
        let point = convert(windowPoint, from: nil)
        let titles = tools.map { $0.title }
        var records = FloatingPaletteStore.records
        let target = palette(atWindowPoint: windowPoint)
        let zone = dropZone(atWindowPoint: windowPoint)
        let overBar = zone == .topBar, overSide = zone == .sideBar, overBottom = zone == .bottomBar, overLeft = zone == .leftBar
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
        } else if bounds.contains(point) || overBar || overSide || overBottom || overLeft {
            var record = FloatingPaletteRecord(tools: titles)
            record.sections = section.map { [$0] }
            if overBar, let bar = dockBar {
                record.edge = .top
                record.dx = bar.convert(windowPoint, from: nil).x
            } else if overSide, let bar = sideBar {
                record.edge = .right
                record.dx = bar.convert(windowPoint, from: nil).y
                record.columns = PaletteDockBar.iconsPerRow(for: .right)
            } else if overLeft, let bar = leftBar {
                record.edge = .left
                record.dx = bar.convert(windowPoint, from: nil).y
                record.columns = PaletteDockBar.iconsPerRow(for: .left)
            } else if overBottom, let bar = bottomBar {
                record.edge = .bottom
                record.dx = bar.convert(windowPoint, from: nil).x
            } else {
                let size = FloatingPaletteView.size(toolCount: titles.count, columns: titles.count)
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
            guard let button = makeButton?(tool, record.isCombined(tool)) else { continue }
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
        palette.onRename = { [weak self] name in self?.renamePalette(record.id, to: name) }
        return palette
    }

    /// Gives the palette a name of the user's (an empty one brings back the default title).
    private func renamePalette(_ id: UUID, to name: String) {
        var records = FloatingPaletteStore.records
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        records[index].name = trimmed.isEmpty ? nil : trimmed
        FloatingPaletteStore.records = records
        // the name field is still finishing its editing – rebuild right after it
        DispatchQueue.main.async { [weak self] in self?.reload() }
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
            sideBar?.isHighlighted = highlightedEdge == .right
            bottomBar?.isHighlighted = highlightedEdge == .bottom
            leftBar?.isHighlighted = highlightedEdge == .left
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let edge = highlightedEdge else { return }
        let thickness: CGFloat = 3
        let line: NSRect
        switch edge {
        case .top: line = NSRect(x: 0, y: 0, width: bounds.width, height: thickness)
        case .left:
            guard (leftBar?.frame.width ?? 0) == 0 else { return }
            line = NSRect(x: 0, y: 0, width: thickness, height: bounds.height)
        case .right:
            // the right palette bar lights up itself; while it is empty the drawing's right edge does
            guard (sideBar?.frame.width ?? 0) == 0 else { return }
            line = NSRect(x: bounds.maxX - thickness, y: 0, width: thickness, height: bounds.height)
        case .bottom:
            guard (bottomBar?.frame.height ?? 0) == 0 else { return }
            line = NSRect(x: 0, y: bounds.maxY - thickness, width: bounds.width, height: thickness)
        }
        Theme.accent.setFill()
        line.fill()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPalettes()
    }

    /// Places every palette on the drawing from its record, always fully inside the drawing area.
    private func layoutPalettes() {
        for palette in drawingPalettes {
            let record = palette.record
            let size = palette.frame.size
            var origin = NSPoint(x: record.anchorRight ? bounds.maxX - record.dx - size.width : record.dx,
                                 y: record.anchorBottom ? bounds.maxY - record.dy - size.height : record.dy)
            origin.x = max(0, min(origin.x, bounds.maxX - size.width))
            origin.y = max(0, min(origin.y, bounds.maxY - size.height))
            palette.setFrameOrigin(origin)
        }
        dockBar?.layoutPalettes()
        leftBar?.layoutPalettes()
        sideBar?.layoutPalettes()
        bottomBar?.layoutPalettes()
    }

    /// The edge a palette with this frame would snap to – the nearest one within the snap distance.
    private func edgeCandidate(for frame: NSRect) -> PaletteEdge? {
        let distances: [(PaletteEdge, CGFloat)] = [(.top, frame.minY), (.left, frame.minX), (.right, bounds.maxX - frame.maxX),
                                                   (.bottom, bounds.maxY - frame.maxY)]
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
        if let bar = sideBar, !bar.isHidden, bar.bounds.contains(bar.convert(windowPoint, from: nil)) { return .sideBar }
        if let bar = bottomBar, !bar.isHidden, bar.bounds.contains(bar.convert(windowPoint, from: nil)) { return .bottomBar }
        let point = convert(windowPoint, from: nil)
        if bounds.contains(point) { return .drawing }
        // the drawing tabs lie right above the drawing (the layer is flipped: above = negative y)
        if point.y < 0 && point.y > -DrawingTabBarView.height && point.x >= 0 && point.x <= bounds.maxX { return .topBar }
        if let panel = toolPanel {
            if !panel.isHidden && panel.bounds.contains(panel.convert(windowPoint, from: nil)) { return .toolPanel }
        } else if point.x < 0 {
            return .toolPanel
        }
        // left of the drawing (the right panel moved to the left, or no tool panel): the left palette bar
        if leftBar != nil && point.x < 0 && point.y >= -DrawingTabBarView.height && point.y <= bounds.maxY { return .leftBar }
        // the layout tabs lie right under the drawing (and under the bottom palette bar)
        let below = point.y - bounds.maxY - (bottomBar?.frame.height ?? 0)
        if below > 0 && below < LayoutBarView.height && point.x <= bounds.maxX { return .bottomBar }
        // the right panel lies between the drawing and the right palette bar
        if point.x > bounds.maxX && point.y >= -DrawingTabBarView.height && point.y <= bounds.maxY { return .sideBar }
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
    /// lights up and on release the palette snaps to it (to the top or right = into that palette bar).
    /// In a palette bar it moves along the bar. Outside its own area a picture of it follows the mouse:
    /// released on the tool panel the palette closes and its groups go back to the panel.
    private func paletteDragged(_ palette: FloatingPaletteView, phase: ToolDragPhase, offset: CGSize, event: NSEvent) {
        let barEdge: PaletteEdge? = palette.superview === dockBar ? .top : palette.superview === sideBar ? .right
                                  : palette.superview === bottomBar ? .bottom : palette.superview === leftBar ? .left : nil
        let inBar = barEdge != nil
        let zone = dropZone(atWindowPoint: event.locationInWindow)
        // the palette moves itself only inside its own area, elsewhere its picture follows the mouse
        let ownArea: Bool
        switch barEdge {
        case .top?: ownArea = zone == .topBar
        case .right?: ownArea = zone == .sideBar
        case .bottom?: ownArea = zone == .bottomBar
        case .left?: ownArea = zone == .leftBar
        default: ownArea = zone == .drawing
        }
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
                if ownArea, let bar = palette.superview {
                    if barEdge == .top || barEdge == .bottom {
                        let x = max(0, min(dragStartOrigin.x + offset.width, bar.bounds.maxX - palette.frame.width))
                        palette.setFrameOrigin(NSPoint(x: x, y: palette.frame.minY))
                    } else {
                        // the bar is flipped (y down), the offset is not
                        let y = max(0, min(dragStartOrigin.y - offset.height, bar.bounds.maxY - palette.frame.height))
                        palette.setFrameOrigin(NSPoint(x: palette.frame.minX, y: y))
                    }
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
            let edge: PaletteEdge? = ownArea ? edgeCandidate(for: palette.frame)
                                             : zone == .topBar ? .top : zone == .sideBar ? .right
                                             : zone == .bottomBar ? .bottom : zone == .leftBar ? .left : nil
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
                moveToBar(palette, edge: .top, at: barEdge == .top ? palette.frame.minX : x - palette.frame.width / 2)
            case .sideBar:
                let y = sideBar?.convert(event.locationInWindow, from: nil).y ?? 0
                moveToBar(palette, edge: .right, at: barEdge == .right ? palette.frame.minY : y - palette.frame.height / 2)
            case .leftBar:
                let y = leftBar?.convert(event.locationInWindow, from: nil).y ?? 0
                moveToBar(palette, edge: .left, at: barEdge == .left ? palette.frame.minY : y - palette.frame.height / 2)
            case .bottomBar:
                let x = bottomBar?.convert(event.locationInWindow, from: nil).x ?? 0
                moveToBar(palette, edge: .bottom, at: barEdge == .bottom ? palette.frame.minX : x - palette.frame.width / 2)
            case .drawing where inBar:
                // out of the bar onto the drawing: the palette lies where it was dropped
                let point = convert(event.locationInWindow, from: nil)
                let size = palette.frame.size
                let frame = NSRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
                place(palette, frame: frame, edge: nil)
            case .drawing:
                let edge = edgeCandidate(for: palette.frame)
                if edge == .top {
                    moveToBar(palette, edge: .top, at: palette.frame.minX)
                } else if edge == .right {
                    let y = sideBar?.convert(palette.frame.origin, from: self).y ?? 0
                    moveToBar(palette, edge: .right, at: y)
                } else if edge == .bottom {
                    moveToBar(palette, edge: .bottom, at: palette.frame.minX)
                } else if edge == .left {
                    let y = leftBar?.convert(palette.frame.origin, from: self).y ?? 0
                    moveToBar(palette, edge: .left, at: y)
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

    /// Puts the palette into the palette bar of the edge at a place along it (x in the top and bottom bar,
    /// y in the side ones). In the top and bottom bar a column becomes a row; in a side bar the palette
    /// gets as many icons in a row as the bar is set to.
    private func moveToBar(_ palette: FloatingPaletteView, edge: PaletteEdge, at place: CGFloat) {
        var records = FloatingPaletteStore.records
        guard let index = records.firstIndex(where: { $0.id == palette.record.id }) else { return }
        // the order in the bar: the others by their place now, the moved one by the place it was dropped at
        for i in records.indices where i != index && records[i].edge == edge {
            if let view = palettes.first(where: { $0.record.id == records[i].id }) {
                records[i].dx = edge == .right || edge == .left ? view.frame.minY : view.frame.minX
            }
        }
        records[index].edge = edge
        records[index].dx = place
        let side = edge == .right || edge == .left
        if !side && palette.frame.height > palette.frame.width {
            records[index].columns = records[index].tools.count
            records[index].vertical = false
        } else if side {
            records[index].columns = PaletteDockBar.iconsPerRow(for: edge)
            records[index].vertical = false
        }
        FloatingPaletteStore.records = records
    }

    /// Lays the palette freely on the drawing.
    private func place(_ palette: FloatingPaletteView, frame: NSRect, edge: PaletteEdge?) {
        var records = FloatingPaletteStore.records
        guard let index = records.firstIndex(where: { $0.id == palette.record.id }) else { return }
        records[index].edge = nil
        var frame = frame
        frame.origin.x = max(0, min(frame.origin.x, bounds.maxX - frame.width))
        frame.origin.y = max(0, min(frame.origin.y, bounds.maxY - frame.height))
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
        let reset = NSMenuItem(title: "Reset All Palettes to Default View", action: #selector(resetAllPalettes(_:)),
                               keyEquivalent: "")
        reset.target = self
        reset.subtitle = "The tool panel and all palettes as at the start"
        menu.addItem(reset)
        menu.addItem(.separator())
        if palette.superview === sideBar || palette.superview === leftBar {
            let columns = NSMenuItem(title: "Add Columns When Groups Don't Fit", action: #selector(sideColumnsToggled(_:)),
                                     keyEquivalent: "")
            columns.target = self
            columns.state = PaletteDockBar.sideBarsAddColumns ? .on : .off
            columns.subtitle = "Otherwise the bar scrolls"
            menu.addItem(columns)
        }
        let compact = NSMenuItem(title: "Compact View", action: #selector(compactViewToggled(_:)), keyEquivalent: "")
        compact.target = self
        compact.state = FloatingPaletteLayer.isCompact ? .on : .off
        menu.addItem(compact)
        return menu
    }

    /// The side palette bars: another column or scrolling when their palettes don't fit the height.
    @objc private func sideColumnsToggled(_ sender: NSMenuItem) {
        PaletteDockBar.sideBarsAddColumns.toggle()
        sideBar?.layoutPalettes()
        leftBar?.layoutPalettes()
    }

    /// Compact view on or off for all palettes: without titles, the palettes take less room.
    @objc private func compactViewToggled(_ sender: NSMenuItem) {
        FloatingPaletteLayer.isCompact.toggle()
        // the menu is still closing – rebuild right after it
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    /// Reset All Palettes to Default View was chosen – the window resets the tool panel and the palettes together.
    var onResetAll: (() -> Void)?

    @objc private func resetAllPalettes(_ sender: NSMenuItem) {
        onResetAll?()
    }

    /// Closes all palettes (their groups go back to the tool panel) and sets their options back:
    /// no compact view, two icons in a row and another column in the side bars.
    func resetPalettes() {
        closePalettes { _ in true }
        FloatingPaletteLayer.isCompact = false
        for edge in [PaletteEdge.left, .right] { PaletteDockBar.setIconsPerRow(2, for: edge) }
        PaletteDockBar.sideBarsAddColumns = true
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

    /// A section was shown in the tool panel again: it leaves the palette holding it
    /// (with its tools), and a palette left without tools closes.
    func takeBackSection(_ section: ToolPanelSection) {
        var records = FloatingPaletteStore.records
        let titles = Set(section.buttonTools.flatMap { $0.paletteFamily ?? [$0] }.map { $0.title })
        for index in records.indices where (records[index].sections ?? []).contains(section.title) {
            records[index].sections?.removeAll { $0 == section.title }
            records[index].tools.removeAll { titles.contains($0) }
        }
        records.removeAll { $0.tools.isEmpty }
        FloatingPaletteStore.records = records
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

/// A bar for the palettes held to an edge of the window: at the top above the drawing tabs (a row),
/// or at the right edge beyond the right panel (a column). The palettes stand one after another
/// (in more rows or columns when they don't fit); without palettes the bar has no thickness.
final class PaletteDockBar: NSView {
    /// .top = a row above the drawing tabs, .left / .right = a column at the left / right edge of the window,
    /// .bottom = a row under the drawing.
    let edge: PaletteEdge
    /// The bar's thickness (height of the top bar, width of the right one) changed –
    /// the window lays out its parts again.
    var onThicknessChanged: ((CGFloat) -> Void)?
    /// Lit up while a palette is brought to this edge – on release it goes into the bar.
    var isHighlighted = false {
        didSet { if isHighlighted != oldValue { needsDisplay = true } }
    }

    private var palettes: [FloatingPaletteView] = []
    private(set) var thickness: CGFloat = 0
    private let padding: CGFloat = 3
    private let gap: CGFloat = 4
    /// How far a side bar is scrolled (when it scrolls instead of adding columns).
    private var scrollOffset: CGFloat = 0

    /// The side bars, when their palettes don't fit the height: true = another column, false = they scroll
    /// (kept in the app's settings; the top and bottom bars always go on in another row).
    static var sideBarsAddColumns: Bool {
        get { return UserDefaults.standard.object(forKey: "RightPaletteBarAddsColumns") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "RightPaletteBarAddsColumns") }
    }

    /// Icons in a row in the left or right bar, 1 to 4 – set by dragging the bar's inner edge
    /// (kept in the app's settings).
    static func iconsPerRow(for edge: PaletteEdge) -> Int {
        let saved = UserDefaults.standard.integer(forKey: "PaletteBarIcons-" + edge.rawValue)
        return saved == 0 ? 2 : min(4, max(1, saved))
    }

    static func setIconsPerRow(_ count: Int, for edge: PaletteEdge) {
        UserDefaults.standard.set(min(4, max(1, count)), forKey: "PaletteBarIcons-" + edge.rawValue)
    }

    /// A bar along a side of the window (a column of palettes).
    private var isSide: Bool {
        return edge == .right || edge == .left
    }

    private var scrolls: Bool {
        return isSide && !PaletteDockBar.sideBarsAddColumns
    }

    init(edge: PaletteEdge, frame: NSRect) {
        self.edge = edge
        super.init(frame: frame)
        // palettes scrolled out of the bar must not show over its neighbours
        clipsToBounds = true
    }

    override func scrollWheel(with event: NSEvent) {
        guard scrolls else { return super.scrollWheel(with: event) }
        scrollOffset -= event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        layoutPalettes()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { return true }

    /// Takes over the palettes held to this edge (in the order of their saved places).
    /// In the right bar they look like the groups of the tool panel: all of the same width, two columns
    /// of buttons, no resizing.
    func setPalettes(_ newPalettes: [FloatingPaletteView]) {
        palettes = newPalettes.sorted { $0.record.dx < $1.record.dx }
        for palette in palettes {
            palette.shadow = nil
            // in a bar the palettes have no frame of their own – thin lines part them, as in the tool panel
            palette.isFlat = true
            if isSide {
                palette.isResizable = false
                let icons = PaletteDockBar.iconsPerRow(for: edge)
                palette.minimumWidth = FloatingPaletteView.size(toolCount: icons, columns: icons).width
            }
            addSubview(palette)
        }
        layoutPalettes()
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutPalettes()
    }

    /// Puts the palettes one after another from the start of the bar (left, or top for the right bar),
    /// going on in a new row (column) when the bar is full.
    func layoutPalettes() {
        let vertical = isSide
        let room = vertical ? bounds.height : bounds.width
        let shown = palettes.filter { $0.superview === self }
        // a scrolling bar: one column, scrolled at most so far that its end reaches the bottom
        let length = shown.reduce(padding) { $0 + (vertical ? $1.frame.height : $1.frame.width) + gap }
        scrollOffset = scrolls ? max(0, min(scrollOffset, length - room)) : 0
        var along = padding - scrollOffset, across = padding, line: CGFloat = 0
        for palette in shown {
            let size = palette.frame.size
            let length = vertical ? size.height : size.width
            if !scrolls && along > padding && along + length > room - padding {
                along = padding
                across += line + gap
                line = 0
            }
            if !palette.isMoving {
                palette.setFrameOrigin(vertical ? NSPoint(x: across, y: along) : NSPoint(x: along, y: across))
            }
            along += length + gap
            line = max(line, vertical ? size.width : size.height)
        }
        needsDisplay = true
        // buttons that moved away from under the mouse must not stay lit up
        for palette in shown {
            palette.subviews.compactMap { $0 as? ToolButtonView }.forEach { $0.refreshHover() }
        }
        let newThickness = line > 0 ? across + line + padding : 0
        if newThickness != thickness {
            thickness = newThickness
            onThicknessChanged?(newThickness)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.toolbarBackground.setFill()
        bounds.fill()
        // a line along the side facing the drawing, an accent one while a palette is brought here
        (isHighlighted ? Theme.accent : Theme.panelBorder).setFill()
        let width: CGFloat = isHighlighted ? 3 : 1
        // a thin line between neighbouring palettes of one row (column), like the separators of the tool panel
        NSColor.separatorColor.setFill()
        let shown = palettes.filter { $0.superview === self }
        for (previous, next) in zip(shown, shown.dropFirst()) {
            if isSide && abs(previous.frame.minX - next.frame.minX) < 1 {
                let y = ((previous.frame.maxY + next.frame.minY) / 2).rounded(.down)
                NSRect(x: previous.frame.minX + 8, y: y, width: previous.frame.width - 16, height: 1).fill()
            } else if !isSide && abs(previous.frame.minY - next.frame.minY) < 1 {
                let x = ((previous.frame.maxX + next.frame.minX) / 2).rounded(.down)
                NSRect(x: x, y: previous.frame.minY + 6, width: 1, height: max(previous.frame.height, next.frame.height) - 12).fill()
            }
        }
        (isHighlighted ? Theme.accent : Theme.panelBorder).setFill()
        switch edge {
        case .right: NSRect(x: 0, y: 0, width: width, height: bounds.height).fill()
        case .left: NSRect(x: bounds.maxX - width, y: 0, width: width, height: bounds.height).fill()
        case .bottom: NSRect(x: 0, y: 0, width: bounds.width, height: width).fill()
        default: NSRect(x: 0, y: bounds.maxY - width, width: bounds.width, height: width).fill()
        }
    }
}

/// Holds the texts of a view's tooltip areas. AppKit does not keep the owner passed to addToolTip,
/// so a string passed there directly can be freed before its tooltip shows (and the app crashes);
/// the view keeps this object instead and it hands out the texts.
final class ToolTipTexts: NSObject, NSViewToolTipOwner {
    private var texts: [NSView.ToolTipTag: String] = [:]

    func add(_ text: String, rect: NSRect, to view: NSView) {
        texts[view.addToolTip(rect, owner: self, userData: nil)] = text
    }

    func removeAll(from view: NSView) {
        view.removeAllToolTips()
        texts = [:]
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        return texts[tag] ?? ""
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

/// One floating palette: tool buttons in rows on a dark rounded background under a top strip
/// (on a palette made of groups it shows their names). Dragging the background moves the palette
/// (close to another one it merges, close to an edge it snaps), dragging its right or bottom edge
/// changes the number of columns, right-click opens its menu.
final class FloatingPaletteView: NSView, NSTextFieldDelegate {
    var record: FloatingPaletteRecord
    /// The user renamed the palette by double-clicking its title (an empty name = the default title).
    var onRename: ((String) -> Void)?
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

    /// Height of the top strip – the same on every palette, so palettes side by side keep their buttons
    /// in line; it shows the palette's title, in the compact view it is only a thin strip to hold.
    static var topHeight: CGFloat {
        return FloatingPaletteLayer.isCompact ? 7 : 15
    }
    static let padding: CGFloat = 4
    /// Width of the band along the right and bottom edge that changes the number of columns.
    static let resizeBand: CGFloat = 5
    static let buttonSize = NSSize(width: 34, height: 32)
    static let gap: CGFloat = 2

    static func size(toolCount: Int, columns: Int) -> NSSize {
        let count = max(1, toolCount)
        let columns = max(1, min(columns, count))
        let rows = (count + columns - 1) / columns
        let width = CGFloat(columns) * buttonSize.width + CGFloat(columns - 1) * gap
        let height = CGFloat(rows) * buttonSize.height + CGFloat(rows - 1) * gap
        return NSSize(width: width + 2 * padding, height: topHeight + height + padding)
    }

    /// Which edge a resize drag holds: the right edge and the corner set the columns by the width,
    /// the bottom edge sets the rows by the height.
    private enum ResizeEdge {
        case right, bottom, corner
    }

    /// The palette is never narrower than this (its buttons stay at the left) – palettes in a side bar
    /// are all of one width.
    var minimumWidth: CGFloat = 0 {
        didSet { if minimumWidth != oldValue { layoutButtons() } }
    }
    /// A palette in a bar: no frame, no rounded corners, no background of its own (the bar draws the lines between).
    var isFlat = false {
        didSet {
            guard isFlat != oldValue else { return }
            layer?.borderWidth = isFlat ? 0 : 1
            layer?.cornerRadius = isFlat ? 0 : 8
            layer?.backgroundColor = isFlat ? NSColor.clear.cgColor : Theme.toolbarBackground.cgColor
        }
    }
    /// Can the number of columns be changed by dragging the edges? (Not in the side bars.)
    var isResizable = true {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private let buttons: [ToolButtonView]
    private var mouseDownPoint: NSPoint?
    /// The edge the drag started on (nil = the drag moves the palette).
    private var resizeEdge: ResizeEdge?
    private var resizeStartSize: NSSize = .zero

    /// Buttons in one row: the saved count, or all in one row (one column for a vertical palette).
    var columnCount: Int {
        let count = max(1, buttons.count)
        if let columns = record.columns { return max(1, min(columns, count)) }
        return record.vertical ? 1 : count
    }

    /// The title in the top strip: the user's name, or the names of the groups the palette was made of,
    /// or “Custom Palette” for a palette put together tool by tool.
    private var title: String {
        if let name = record.name, !name.isEmpty { return name.uppercased() }
        let sections = record.sections ?? []
        if sections.isEmpty { return FloatingPaletteView.defaultName.uppercased() }
        return sections.map { $0.uppercased() }.joined(separator: " · ")
    }

    static let defaultName = "Custom Palette"
    /// The field for typing a new name, shown in the top strip while renaming.
    private var nameField: NSTextField?
    private var renameCancelled = false
    private let toolTips = ToolTipTexts()

    private var topHeight: CGFloat {
        return FloatingPaletteView.topHeight
    }

    private var rightEdgeRect: NSRect {
        let band = FloatingPaletteView.resizeBand
        return NSRect(x: bounds.maxX - band, y: 0, width: band, height: bounds.height)
    }

    private var bottomEdgeRect: NSRect {
        let band = FloatingPaletteView.resizeBand
        return NSRect(x: 0, y: bounds.maxY - band, width: bounds.width, height: band)
    }

    private var cornerRect: NSRect {
        let size = 2 * FloatingPaletteView.resizeBand
        return NSRect(x: bounds.maxX - size, y: bounds.maxY - size, width: size, height: size)
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
        var size = FloatingPaletteView.size(toolCount: buttons.count, columns: columns)
        // a narrower palette is widened to the minimum, its buttons stay at the left (as in the tool panel)
        size.width = max(size.width, minimumWidth)
        setFrameSize(size)
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
        if nameField == nil && !FloatingPaletteLayer.isCompact { drawTitle() }
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
        let rect = NSRect(x: FloatingPaletteView.padding, y: 2, width: available, height: FloatingPaletteView.topHeight - 2)
        (title as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attributes)
    }

    // an arrow over the palette, not the drawing's crosshair; an open hand on the top strip,
    // resize cursors on the right and bottom edge and on the corner between them
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        addCursorRect(NSRect(x: 0, y: 0, width: bounds.width, height: topHeight), cursor: .openHand)
        toolTips.removeAll(from: self)
        if isResizable {
            addCursorRect(rightEdgeRect, cursor: .resizeLeftRight)
            addCursorRect(bottomEdgeRect, cursor: .resizeUpDown)
            addCursorRect(cornerRect, cursor: .frameResize(position: .bottomRight, directions: .all))
            let help = "Drag the edge to change the number of columns"
            toolTips.add(help, rect: rightEdgeRect, to: self)
            toolTips.add(help, rect: bottomEdgeRect, to: self)
        }
        toolTips.add(FloatingPaletteLayer.isCompact ? "Drag to move the palette"
                                                    : "Drag to move the palette, double-click the title to rename it",
                     rect: NSRect(x: 0, y: 0, width: bounds.width, height: topHeight), to: self)
    }

    // MARK: Renaming

    /// Shows a field over the title for typing a new name: ↩ keeps it, Esc cancels.
    private func startRenaming() {
        guard nameField == nil else { return }
        let field = NSTextField(frame: NSRect(x: FloatingPaletteView.padding, y: 1,
                                              width: max(60, bounds.width - 2 * FloatingPaletteView.padding),
                                              height: topHeight - 1))
        field.stringValue = record.name ?? ""
        field.placeholderString = FloatingPaletteView.defaultName
        field.font = NSFont.systemFont(ofSize: 9.5, weight: .semibold)
        field.alignment = .center
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = true
        field.backgroundColor = Theme.panelBorder
        field.textColor = Theme.textHeading
        field.cell?.isScrollable = true
        field.delegate = self
        renameCancelled = false
        nameField = field
        addSubview(field)
        needsDisplay = true
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            renameCancelled = true
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = nameField else { return }
        nameField = nil
        let name = field.stringValue
        field.removeFromSuperview()
        needsDisplay = true
        if !renameCancelled { onRename?(name) }
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
        let point = convert(event.locationInWindow, from: nil)
        // a double click on the title renames the palette
        if event.clickCount == 2 && point.y < topHeight && !FloatingPaletteLayer.isCompact {
            mouseDownPoint = nil
            startRenaming()
            return
        }
        mouseDownPoint = event.locationInWindow
        if !isResizable {
            resizeEdge = nil
        } else if cornerRect.contains(point) {
            resizeEdge = .corner
        } else if rightEdgeRect.contains(point) {
            resizeEdge = .right
        } else if bottomEdgeRect.contains(point) {
            resizeEdge = .bottom
        } else {
            resizeEdge = nil
        }
        resizeStartSize = bounds.size
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let offset = CGSize(width: event.locationInWindow.x - start.x, height: event.locationInWindow.y - start.y)
        if let edge = resizeEdge {
            let count = max(1, buttons.count)
            let columns: Int
            if edge == .bottom {
                // the wanted height, rounded to whole rows (the window offset goes up, the palette grows down)
                let step = FloatingPaletteView.buttonSize.height + FloatingPaletteView.gap
                let inner = resizeStartSize.height - offset.height - topHeight - FloatingPaletteView.padding + FloatingPaletteView.gap
                let rows = max(1, min(Int((inner / step).rounded()), count))
                columns = (count + rows - 1) / rows
            } else {
                // the wanted width, rounded to whole columns
                let step = FloatingPaletteView.buttonSize.width + FloatingPaletteView.gap
                let inner = resizeStartSize.width + offset.width - 2 * FloatingPaletteView.padding + FloatingPaletteView.gap
                columns = max(1, min(Int((inner / step).rounded()), count))
            }
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
        if resizeEdge != nil {
            resizeEdge = nil
            onResize?(.ended)
        } else if isMoving {
            onDrag?(.ended, .zero, event)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        return menuProvider?()
    }
}
