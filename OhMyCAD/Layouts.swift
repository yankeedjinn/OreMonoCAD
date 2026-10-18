//
//  Layouts.swift
//  OhMyCAD
//
//  Layouts as in AutoCAD: Model = drawing at real size, a layout = paper
//  in millimeters. On the paper there are viewports – windows into the model at their own scale –
//  and everything drawn directly on paper (frame, title block, notes).
//
//  - Each layout has its own CADDocument with entities in paper mm (including ViewportEntity).
//  - Layers are shared by the model and the layouts (the tab's LayerManager).
//  - A viewport draws the model shifted and scaled down by its scale and clips it to its rectangle.
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - Layout

final class DrawingLayout {
    var name: String
    var paper: PaperSize
    var landscape: Bool
    /// Margin of the printable area (only a guide on paper), mm.
    var marginMM: CGFloat = 10
    var document = CADDocument()
    var viewState: (zoom: CGFloat, pan: CGPoint)?
    var gridSize: CGFloat = 10
    /// Last plot settings of this layout (Plot dialog).
    var plotSettings: PlotSettings?

    init(name: String, paper: PaperSize = .a3, landscape: Bool = true) {
        self.name = name
        self.paper = paper == .extents ? .a3 : paper
        self.landscape = landscape
    }

    /// Paper size in mm (according to the orientation).
    var paperSizeMM: CGSize {
        let portrait = paper.portraitMM ?? CGSize(width: 297, height: 420)
        return landscape ? CGSize(width: portrait.height, height: portrait.width) : portrait
    }

    /// Paper in layout coordinates: bottom left corner at the origin.
    var paperRect: CGRect { return CGRect(origin: .zero, size: paperSizeMM) }

    var printableRect: CGRect {
        let m = min(max(0, marginMM), min(paperSizeMM.width, paperSizeMM.height) / 3)
        return paperRect.insetBy(dx: m, dy: m)
    }

    var viewports: [ViewportEntity] {
        return document.getAllEntities().compactMap { $0 as? ViewportEntity }
    }

    /// A copy of the layout including all objects on paper.
    func duplicate(named newName: String) -> DrawingLayout {
        let copy = DrawingLayout(name: newName, paper: paper, landscape: landscape)
        copy.marginMM = marginMM
        copy.gridSize = gridSize
        copy.plotSettings = plotSettings
        for entity in document.getAllEntities() { copy.document.addEntity(entity.clone()) }
        return copy
    }

    /// Paper description for tooltips and menus.
    var paperDescription: String {
        let size = paperSizeMM
        return "\(paper.shortTitle) \(landscape ? "landscape" : "portrait") – \(LineType.format(size.width)) × \(LineType.format(size.height)) mm"
    }
}

// MARK: - Viewport

/// A rectangle on paper in which the model is visible at a given scale.
final class ViewportEntity: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var drawOrder = 0

    /// Viewport rectangle on paper (mm).
    var rect: CGRect
    /// The model point at the center of the viewport.
    var modelCenter: CGPoint
    /// Viewport scale (paper : model) – same as the drawing scale, in drawing units.
    var scale: DrawingScale
    /// Model layers hidden only in this viewport.
    var frozenLayers: Set<String> = []
    /// Locked viewport: the content cannot be panned or rescaled.
    var isLocked = false
    /// mm per model unit (drawing units) – set while working with the layout, not saved.
    var mmPerUnit: CGFloat = 1

    init(rect: CGRect, modelCenter: CGPoint, scale: DrawingScale, layer: String, color: NSColor? = nil) {
        self.rect = rect.standardized
        self.modelCenter = modelCenter
        self.scale = scale
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Viewport" }

    var infoText: String {
        return String(format: "Viewport\n%@\n\nSize:   %.1f × %.1f mm\nScale:  %@\nCenter: %.3f, %.3f%@%@",
                      commonInfo, rect.width, rect.height, scale.title, modelCenter.x, modelCenter.y,
                      frozenLayers.isEmpty ? "" : "\nHidden layers: \(frozenLayers.sorted().joined(separator: ", "))",
                      isLocked ? "\nLocked (the view can't be panned or rescaled)" : "")
    }

    /// How many mm of paper correspond to one model unit.
    func paperMMPerUnit(mmPerUnit: CGFloat? = nil) -> CGFloat {
        let mmPerUnit = mmPerUnit ?? self.mmPerUnit
        return max(scale.paper, 1e-9) / max(scale.model, 1e-9) * mmPerUnit
    }

    /// Model → paper (mm) for the given model center.
    func modelToPaper(mmPerUnit: CGFloat? = nil, center: CGPoint? = nil) -> CGAffineTransform {
        let k = paperMMPerUnit(mmPerUnit: mmPerUnit)
        let c = center ?? modelCenter
        return CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: k, y: k)
            .translatedBy(x: -c.x, y: -c.y)
    }

    /// The part of the model the viewport shows.
    func modelRect(mmPerUnit: CGFloat? = nil, center: CGPoint? = nil) -> CGRect {
        let k = paperMMPerUnit(mmPerUnit: mmPerUnit)
        let c = center ?? modelCenter
        return CGRect(x: c.x - rect.width / 2 / k, y: c.y - rect.height / 2 / k,
                      width: rect.width / k, height: rect.height / k)
    }

    var corners: [CGPoint] {
        return [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
    }

    func makePath() -> CGPath {
        return CGPath(rect: rect, transform: nil)
    }

    func boundingBox() -> CGRect { return rect }

    func distance(to point: CGPoint) -> CGFloat {
        return distanceToPrimitives(point)
    }

    func snapPoints() -> [SnapPoint] {
        let c = corners
        var result = c.map { SnapPoint(point: $0, type: .endpoint) }
        for i in 0..<4 { result.append(SnapPoint(point: Geometry.midpoint(c[i], c[(i + 1) % 4]), type: .midpoint)) }
        result.append(SnapPoint(point: CGPoint(x: rect.midX, y: rect.midY), type: .center))
        return result
    }

    /// Move, rotate and mirror move the rectangle; resizing (Scale) also enlarges the content.
    func applyTransform(_ transform: CGAffineTransform) {
        let moved = corners.map { $0.applying(transform) }
        let xs = moved.map { $0.x }, ys = moved.map { $0.y }
        rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        let factor = sqrt(abs(transform.a * transform.d - transform.b * transform.c))
        if factor.isFinite, factor > 0, abs(factor - 1) > 1e-9 {
            scale = DrawingScale(paper: scale.paper * factor, model: scale.model)
        }
    }

    func clone() -> CADEntity {
        let copy = ViewportEntity(rect: rect, modelCenter: modelCenter, scale: scale, layer: layer, color: color)
        copy.frozenLayers = frozenLayers
        copy.isLocked = isLocked
        copy.mmPerUnit = mmPerUnit
        return copyStyle(to: copy)
    }

    func primitives() -> [Primitive] {
        let c = corners
        return (0..<4).map { .segment(a: c[$0], b: c[($0 + 1) % 4], param: 0) }
    }

    /// The nearest “nice” scale (from the presets) at which the model's `box` fits into the viewport.
    static func fittingScale(for box: CGRect, in rect: CGRect, mmPerUnit: CGFloat) -> DrawingScale {
        guard box.width > 0 || box.height > 0 else { return DrawingScale(paper: 1, model: 1) }
        // required mm of paper per model unit
        let kx = box.width > 0 ? rect.width / box.width : .infinity
        let ky = box.height > 0 ? rect.height / box.height : .infinity
        let k = min(kx, ky) * 0.95
        // paper/model * mmPerUnit <= k → looks for the largest preset that fits
        let large: [CGFloat] = [2000, 2500, 5000, 10000, 20000, 25000, 50000, 100000]
        let candidates = DrawingScale.presets + large.map { DrawingScale(paper: 1, model: $0) }
        let fitting = candidates.filter { $0.paper / $0.model * mmPerUnit <= k }
        if let best = fitting.max(by: { $0.paper / $0.model < $1.paper / $1.model }) { return best }
        return DrawingScale(paper: 1, model: max(1, (mmPerUnit / max(k, 1e-9)).rounded(.up)))
    }
}

// MARK: - Drawing the viewport content

enum ViewportDrawing {
    /// Draws the model in the viewport. `paperTransform` converts paper mm to the target (screen / page).
    /// `printing` = plottable layers only. `center` = temporary center (panning with the mouse).
    static func drawContents(of viewport: ViewportEntity, center: CGPoint? = nil,
                             model: [CADEntity], layerManager: LayerManager, mmPerUnit: CGFloat,
                             paperTransform: CGAffineTransform, in context: CGContext, printing: Bool,
                             style: (CADEntity) -> StrokeStyle) {
        let clip = viewport.makePath()
        var t = paperTransform
        guard let clipPath = clip.copy(using: &t), DrawingSafety.isDrawable(clipPath.boundingBoxOfPath) else { return }
        let visible = viewport.modelRect(mmPerUnit: mmPerUnit, center: center)
        let transform = viewport.modelToPaper(mmPerUnit: mmPerUnit, center: center).concatenating(paperTransform)

        let shown = model.filter { entity in
            guard !(entity is ViewportEntity), !viewport.frozenLayers.contains(entity.layer) else { return false }
            let onLayer = printing ? layerManager.isLayerPrintable(entity.layer) : layerManager.isLayerVisible(entity.layer)
            return onLayer && entity.boundingBox().insetBy(dx: -1e-6, dy: -1e-6).intersects(visible)
        }
        context.saveGState()
        context.addPath(clipPath)
        context.clip()
        for entity in DrawOrder.sorted(shown) { entity.draw(in: context, transform: transform, style: style(entity)) }
        context.restoreGState()
    }
}

// MARK: - Model | Layout1 | … bar

final class LayoutBarView: NSView {
    static let height: CGFloat = 22

    /// nil = Model, a number = layout index.
    var onSelect: ((Int?) -> Void)?
    var onAdd: (() -> Void)?
    var onRename: ((Int) -> Void)?
    var onDuplicate: ((Int) -> Void)?
    var onDelete: ((Int) -> Void)?
    var onPageSetup: ((Int) -> Void)?
    var onAddViewport: ((Int) -> Void)?
    var onMove: ((Int, Int) -> Void)?
    var onPlot: ((Int?) -> Void)?

    private var names: [String] = []
    private var selected: Int?
    private var rects: [(index: Int?, rect: NSRect)] = []
    private var plusRect = NSRect.zero

    override var isFlipped: Bool { return false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    func update(layoutNames: [String], selected: Int?, toolTips: [String]) {
        names = layoutNames
        self.selected = selected
        layoutRects()
        removeAllToolTips()
        for item in rects {
            if let index = item.index {
                _ = addToolTip(item.rect, owner: (toolTips.indices.contains(index) ? toolTips[index] : names[index]) as NSString, userData: nil)
            } else {
                _ = addToolTip(item.rect, owner: "Model – draw in real size. Right-click for Plot…" as NSString, userData: nil)
            }
        }
        _ = addToolTip(plusRect, owner: "New layout (a sheet of paper with a viewport onto the model)" as NSString, userData: nil)
        needsDisplay = true
    }

    private let font = NSFont.systemFont(ofSize: 11)

    private func layoutRects() {
        rects.removeAll()
        var x: CGFloat = 6
        let titles: [(Int?, String)] = [(nil, "Model")] + names.enumerated().map { ($0.offset, $0.element) }
        for (index, title) in titles {
            let width = min(160, (title as NSString).size(withAttributes: [.font: font]).width + 22)
            rects.append((index, NSRect(x: x, y: 2, width: width, height: bounds.height - 4)))
            x += width + 2
        }
        plusRect = NSRect(x: x + 2, y: 2, width: 20, height: bounds.height - 4)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutRects()
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.layoutBarBackground.setFill()
        bounds.fill()
        Theme.layoutBarBorder.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail
        for item in rects {
            let isSelected = item.index == selected
            let title = item.index.map { names[$0] } ?? "Model"
            let shape = NSBezierPath(roundedRect: item.rect, xRadius: 4, yRadius: 4)
            if isSelected {
                Theme.canvasBackground.setFill()
                shape.fill()
                Theme.accent.setFill()
                NSRect(x: item.rect.minX + 6, y: item.rect.minY, width: item.rect.width - 12, height: 2).fill()
            } else {
                Theme.layoutTab.setFill()
                shape.fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [
                .font: isSelected ? NSFont.systemFont(ofSize: 11, weight: .semibold) : font,
                .foregroundColor: isSelected ? NSColor.white : Theme.textLayoutTab,
                .paragraphStyle: paragraph]
            let size = (title as NSString).size(withAttributes: attributes)
            (title as NSString).draw(in: NSRect(x: item.rect.minX + 4, y: item.rect.midY - size.height / 2,
                                                width: item.rect.width - 8, height: size.height),
                                     withAttributes: attributes)
        }
        let plus = NSImage(systemSymbolName: "plus", accessibilityDescription: "New layout")
        plus?.isTemplate = true
        if let plus = plus {
            let tinted = NSImage(size: NSSize(width: 11, height: 11), flipped: false) { rect in
                plus.draw(in: rect)
                Theme.textLabel.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: plusRect.midX - 5.5, y: plusRect.midY - 5.5, width: 11, height: 11))
        }
    }

    private func hit(_ point: NSPoint) -> (found: Bool, index: Int?) {
        for item in rects where item.rect.contains(point) { return (true, item.index) }
        return (false, nil)
    }

    private var dragFrom: Int?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if plusRect.contains(point) {
            onAdd?()
            return
        }
        let result = hit(point)
        guard result.found else { return }
        if event.clickCount == 2, let index = result.index {
            onRename?(index)
            return
        }
        dragFrom = result.index
        onSelect?(result.index)
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragFrom = nil }
        guard let from = dragFrom else { return }
        let point = convert(event.locationInWindow, from: nil)
        let result = hit(point)
        if result.found, let to = result.index, to != from { onMove?(from, to) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let result = hit(point)
        let menu = NSMenu()
        guard result.found else {
            menu.addItem(item("New Layout") { [weak self] in self?.onAdd?() })
            return menu
        }
        guard let index = result.index else {
            menu.addItem(item("Plot Model…") { [weak self] in self?.onPlot?(nil) })
            menu.addItem(.separator())
            menu.addItem(item("New Layout") { [weak self] in self?.onAdd?() })
            return menu
        }
        onSelect?(index)
        menu.addItem(item("Plot “\(names[index])”…") { [weak self] in self?.onPlot?(index) })
        menu.addItem(item("Page Setup…") { [weak self] in self?.onPageSetup?(index) })
        menu.addItem(item("Add Viewport") { [weak self] in self?.onAddViewport?(index) })
        menu.addItem(.separator())
        menu.addItem(item("Rename…") { [weak self] in self?.onRename?(index) })
        menu.addItem(item("Duplicate") { [weak self] in self?.onDuplicate?(index) })
        if index > 0 { menu.addItem(item("Move Left") { [weak self] in self?.onMove?(index, index - 1) }) }
        if index < names.count - 1 { menu.addItem(item("Move Right") { [weak self] in self?.onMove?(index, index + 1) }) }
        menu.addItem(.separator())
        menu.addItem(item("Delete Layout…") { [weak self] in self?.onDelete?(index) })
        menu.addItem(.separator())
        menu.addItem(item("New Layout") { [weak self] in self?.onAdd?() })
        return menu
    }

    private var menuActions: [MenuAction] = []

    private func item(_ title: String, _ handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        menuActions.append(action)
        if menuActions.count > 40 { menuActions.removeFirst(menuActions.count - 40) }
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run(_:)), keyEquivalent: "")
        item.target = action
        return item
    }
}

/// A menu item action as a closure.
final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func run(_ sender: Any?) { handler() }
}

// MARK: - Layout page setup

enum LayoutPageSetupDialog {
    /// Paper, orientation and margin of the layout. nil = Cancel.
    static func run(name: String, paper: PaperSize, landscape: Bool, marginMM: CGFloat)
        -> (paper: PaperSize, landscape: Bool, marginMM: CGFloat)? {
        let papers = PaperSize.allCases.filter { $0 != .extents }
        let paperPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        paperPopup.addItems(withTitles: papers.map { $0.title })
        paperPopup.selectItem(at: papers.firstIndex(of: paper) ?? 1)
        let orientation = NSPopUpButton(frame: .zero, pullsDown: false)
        orientation.addItems(withTitles: ["Portrait", "Landscape"])
        orientation.selectItem(at: landscape ? 1 : 0)
        let margin = NSTextField(string: LineType.format(marginMM))
        margin.widthAnchor.constraint(equalToConstant: 60).isActive = true
        margin.toolTip = "The dashed frame on the sheet – where printers can still print"

        let grid = NSGridView(views: [[NSTextField(labelWithString: "Paper:"), paperPopup],
                                      [NSTextField(labelWithString: "Orientation:"), orientation],
                                      [NSTextField(labelWithString: "Margin (mm):"), margin]])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame.size = grid.fittingSize

        let alert = NSAlert()
        alert.messageText = "Page Setup – \(name)"
        alert.informativeText = "Objects on the sheet keep their position (lower-left corner of the paper = 0,0)."
        alert.accessoryView = grid
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let value = ExpressionEvaluator.evaluate(margin.stringValue).map { CGFloat($0) } ?? marginMM
        return (papers[max(0, paperPopup.indexOfSelectedItem)], orientation.indexOfSelectedItem == 1, max(0, min(value, 100)))
    }
}

// MARK: - Blocks and external references
//
// Block = a named group of objects with a base point (BlockDefinition) stored in the drawing.
// It is inserted into the drawing as a reference (BlockReference): position, rotation, scale, mirroring.
// A change of the definition shows up in all references. An external reference (xref) is a definition whose
// objects are loaded from another drawing (.ohmycad or .dxf) and refreshed when the file changes.

/// Source of an external reference.
final class XrefSource {
    var path: String
    /// Security-scoped bookmark (sandbox) – the file can be opened again after the next launch.
    var bookmark: Data?
    /// The file's modification date at the last load.
    var modified: Date?
    /// Error of the last load (nil = loaded).
    var error: String?
    /// The URL that access is open for (startAccessingSecurityScopedResource).
    var accessedURL: URL?

    init(path: String, bookmark: Data?) {
        self.path = path
        self.bookmark = bookmark
    }

    var fileName: String { return (path as NSString).lastPathComponent }
}

final class BlockDefinition {
    var name: String
    var basePoint: CGPoint { didSet { version += 1 } }
    /// The block's objects in its own coordinates (base point = insertion origin).
    var entities: [CADEntity] { didSet { version += 1 } }
    var note: String
    /// External reference – the objects come from another file.
    var source: XrefSource?
    /// Incremented on every change – references then recompute their content.
    private(set) var version = 0

    init(name: String, basePoint: CGPoint, entities: [CADEntity], note: String = "", source: XrefSource? = nil) {
        self.name = name
        self.basePoint = basePoint
        self.entities = entities
        self.note = note
        self.source = source
    }

    var isExternal: Bool { return source != nil }

    /// Does it contain (even nested) a reference to `other`? (A block must not contain itself.)
    func contains(_ other: BlockDefinition, visited: Set<ObjectIdentifier> = []) -> Bool {
        if self === other { return true }
        var seen = visited
        guard seen.insert(ObjectIdentifier(self)).inserted else { return false }
        for case let reference as BlockReference in entities where reference.definition.contains(other, visited: seen) {
            return true
        }
        return false
    }

    func markChanged() { version += 1 }
}

final class BlockLibrary {
    private(set) var definitions: [BlockDefinition] = []
    /// After the list changes (new block, rename, delete).
    var onChange: (() -> Void)?

    func named(_ name: String) -> BlockDefinition? {
        let key = name.lowercased()
        return definitions.first { $0.name.lowercased() == key }
    }

    func add(_ definition: BlockDefinition) {
        if let existing = named(definition.name), existing !== definition {
            definitions.removeAll { $0 === existing }
        }
        if !definitions.contains(where: { $0 === definition }) { definitions.append(definition) }
        onChange?()
    }

    func remove(_ definition: BlockDefinition) {
        definitions.removeAll { $0 === definition }
        onChange?()
    }

    @discardableResult
    func rename(_ definition: BlockDefinition, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        if let other = named(trimmed), other !== definition { return false }
        definition.name = trimmed
        onChange?()
        return true
    }

    func uniqueName(_ base: String = "Block") -> String {
        if named(base) == nil { return base }
        var i = 2
        while named("\(base) \(i)") != nil { i += 1 }
        return "\(base) \(i)"
    }

    var blocks: [BlockDefinition] { return definitions.filter { !$0.isExternal } }
    var xrefs: [BlockDefinition] { return definitions.filter { $0.isExternal } }

    func removeAll() {
        definitions.removeAll()
        onChange?()
    }

    /// How many times the definition is used in entity lists (including nested in other blocks).
    func useCount(of definition: BlockDefinition, in documents: [[CADEntity]]) -> Int {
        var count = 0
        for list in documents + definitions.filter({ $0 !== definition }).map({ $0.entities }) {
            for case let reference as BlockReference in list where reference.definition === definition { count += 1 }
        }
        return count
    }
}

/// An inserted block or external reference.
final class BlockReference: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var drawOrder = 0
    var definition: BlockDefinition { didSet { cache = nil } }
    var position: CGPoint { didSet { cache = nil } }
    var rotation: CGFloat = 0 { didSet { cache = nil } }
    var scale: CGFloat = 1 { didSet { cache = nil } }
    /// Mirrored across the block's X axis.
    var mirrored = false { didSet { cache = nil } }

    /// Drawn highlighted (selection) – internal colors are not used then.
    static var highlightDrawing = false

    private var cache: (version: Int, entities: [CADEntity])?

    init(definition: BlockDefinition, position: CGPoint, layer: String = "0", color: NSColor? = nil) {
        self.definition = definition
        self.position = position
        self.layer = layer
        self.color = color
    }

    var typeName: String { return definition.isExternal ? "External Reference" : "Block" }

    var infoText: String {
        var text = String(format: "%@ “%@”\n%@\n\nInsertion: %.3f, %.3f\nRotation:  %.2f°\nScale:     %@%@\nObjects:   %ld",
                          typeName, definition.name, commonInfo, position.x, position.y,
                          Geometry.normalizeAngle(rotation) * 180 / .pi, LineType.format(scale),
                          mirrored ? " (mirrored)" : "", definition.entities.count)
        if let source = definition.source {
            text += "\nFile:      \(source.fileName)"
            if let error = source.error { text += "\n⚠︎ \(error)" }
        }
        return text
    }

    /// From the block (base point = origin) to the drawing.
    var blockTransform: CGAffineTransform {
        let s = max(abs(scale), 1e-12)
        return CGAffineTransform(translationX: -definition.basePoint.x, y: -definition.basePoint.y)
            .concatenating(CGAffineTransform(scaleX: s, y: mirrored ? -s : s))
            .concatenating(CGAffineTransform(rotationAngle: rotation))
            .concatenating(CGAffineTransform(translationX: position.x, y: position.y))
    }

    /// The block's objects placed in the drawing (computed once and remembered).
    var resolvedEntities: [CADEntity] {
        if let cache = cache, cache.version == definition.version { return cache.entities }
        let t = blockTransform
        // sorted by draw order once during the computation (not on every redraw)
        let entities = DrawOrder.sorted(definition.entities.map { entity -> CADEntity in
            let copy = entity.clone()
            copy.applyTransform(t)
            return copy
        })
        cache = (definition.version, entities)
        return entities
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        for entity in resolvedEntities { path.addPath(entity.makePath()) }
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        let entities = resolvedEntities
        guard !entities.isEmpty else {
            // unloaded external reference: a cross and the name
            let p = position.applying(transform)
            guard DrawingSafety.isFinite(p) else { return }
            context.saveGState()
            context.setStrokeColor(NSColor.systemOrange.cgColor)
            context.setLineWidth(1)
            context.move(to: CGPoint(x: p.x - 6, y: p.y - 6)); context.addLine(to: CGPoint(x: p.x + 6, y: p.y + 6))
            context.move(to: CGPoint(x: p.x - 6, y: p.y + 6)); context.addLine(to: CGPoint(x: p.x + 6, y: p.y - 6))
            context.strokePath()
            ("⚠︎ " + definition.name as NSString).draw(at: CGPoint(x: p.x + 8, y: p.y + 4),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemOrange])
            context.restoreGState()
            return
        }
        for entity in entities {
            var s = style
            // an object with its own color keeps it (except for selection highlighting)
            if let own = entity.color, !BlockReference.highlightDrawing { s.color = own }
            entity.draw(in: context, transform: transform, style: s)
        }
    }

    func boundingBox() -> CGRect {
        var box = CGRect.null
        for entity in resolvedEntities { box = box.union(entity.boundingBox()) }
        return box.isNull ? CGRect(origin: position, size: .zero) : box
    }

    func distance(to point: CGPoint) -> CGFloat {
        var best = Geometry.distance(point, position)
        for entity in resolvedEntities { best = min(best, entity.distance(to: point)) }
        return best
    }

    func snapPoints() -> [SnapPoint] {
        var points = [SnapPoint(point: position, type: .insertion)]
        for entity in resolvedEntities { points.append(contentsOf: entity.snapPoints()) }
        return points
    }

    func applyTransform(_ transform: CGAffineTransform) {
        let direction = CGPoint(x: cos(rotation), y: sin(rotation))
        let moved = CGPoint(x: transform.a * direction.x + transform.c * direction.y,
                            y: transform.b * direction.x + transform.d * direction.y)
        position = position.applying(transform)
        let k = Geometry.uniformScale(of: transform)
        if k.isFinite, k > 0 { scale *= k }
        if moved.length > 0 { rotation = Geometry.normalizeAngle(atan2(moved.y, moved.x)) }
        if Geometry.isMirroring(transform) { mirrored.toggle() }
    }

    func clone() -> CADEntity {
        let copy = BlockReference(definition: definition, position: position, layer: layer, color: color)
        copy.rotation = rotation
        copy.scale = scale
        copy.mirrored = mirrored
        return copyStyle(to: copy)
    }

    func primitives() -> [Primitive] {
        return resolvedEntities.flatMap { $0.primitives() }
    }

    /// The block's objects as separate pieces (Explode): those on layer 0 move to the block's layer.
    func exploded() -> [CADEntity] {
        return resolvedEntities.map { entity -> CADEntity in
            let copy = entity.clone()
            if copy.layer == "0" { copy.layer = layer }
            if copy.color == nil { copy.color = color }
            if copy.lineWeight == nil { copy.lineWeight = lineWeight }
            return copy
        }
    }
}

// MARK: - Loading an external reference

enum XrefLoader {
    /// Loads the model objects from a drawing (.ohmycad or .dxf). Layer colors are applied to the objects,
    /// hidden layers are skipped. Nested external references are not loaded (to avoid a cycle).
    static func load(_ source: XrefSource) -> [CADEntity] {
        var url = URL(fileURLWithPath: source.path)
        if source.accessedURL == nil, let bookmark = source.bookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope],
                                       relativeTo: nil, bookmarkDataIsStale: &stale) {
                if resolved.startAccessingSecurityScopedResource() { source.accessedURL = resolved }
                url = resolved
                source.path = resolved.path
                if stale, let fresh = try? resolved.bookmarkData(options: [.withSecurityScope],
                                                                 includingResourceValuesForKeys: nil, relativeTo: nil) {
                    source.bookmark = fresh
                }
            }
        } else if let accessed = source.accessedURL {
            url = accessed
        }
        do {
            let entities: [CADEntity]
            let layers: [Layer]
            if NativeFormat.isNative(url) {
                let document = try NativeFormat.read(from: url)
                entities = document.entities
                layers = document.layers
            } else {
                let result = try DXFReader().read(from: url)
                entities = result.entities
                layers = result.layers
            }
            var byName: [String: Layer] = [:]
            for layer in layers { byName[layer.name] = layer }
            var result: [CADEntity] = []
            for entity in entities {
                if let reference = entity as? BlockReference, reference.definition.isExternal { continue }
                let layer = byName[entity.layer]
                if layer?.isVisible == false { continue }
                if entity.color == nil, let color = layer?.color { entity.color = color }
                if entity.lineWeight == nil, let weight = layer?.lineWeight { entity.lineWeight = weight }
                result.append(entity)
            }
            source.modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            source.error = nil
            return result
        } catch {
            // remember the date even on error – it is loaded again once the file changes
            source.modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            source.error = FileManager.default.fileExists(atPath: url.path)
                ? "Can't read the file: \(error.localizedDescription)"
                : "File not found – use Block Manager › Browse… to find it"
            return []
        }
    }

    /// Has the file changed since the last load?
    static func hasChanged(_ source: XrefSource) -> Bool {
        let url = source.accessedURL ?? URL(fileURLWithPath: source.path)
        guard let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else {
            return false
        }
        guard let known = source.modified else { return true }
        return date > known
    }
}

extension BlockLibrary {
    /// Takes the blocks nested in the definition into the library (e.g. after Bind of an external reference),
    /// so the drawing can be saved and reopened. Name collisions are resolved by renaming.
    func adoptNested(of definition: BlockDefinition) {
        var stack = [definition]
        var visited = Set<ObjectIdentifier>()
        while let current = stack.popLast() {
            guard visited.insert(ObjectIdentifier(current)).inserted else { continue }
            for case let reference as BlockReference in current.entities {
                let nested = reference.definition
                if !definitions.contains(where: { $0 === nested }) {
                    if named(nested.name) != nil { nested.name = uniqueName(nested.name) }
                    add(nested)
                }
                stack.append(nested)
            }
        }
    }

    /// Reloads the external reference from the file. true = it succeeded.
    @discardableResult
    func reload(_ definition: BlockDefinition) -> Bool {
        guard let source = definition.source else { return false }
        definition.entities = XrefLoader.load(source)
        return source.error == nil
    }

    /// Loads external references whose file has changed since the last load.
    func reloadChangedXrefs() -> [BlockDefinition] {
        var changed: [BlockDefinition] = []
        for definition in xrefs {
            guard let source = definition.source, XrefLoader.hasChanged(source) else { continue }
            reload(definition)
            changed.append(definition)
        }
        return changed
    }
}

// MARK: - Block preview (icon in menus)

enum BlockPreview {
    /// Outline of the block's objects scaled into a square (template – the system gives the color).
    static func image(of definition: BlockDefinition, size: CGFloat) -> NSImage {
        let entities = definition.entities
        var box = CGRect.null
        for entity in entities { box = box.union(entity.boundingBox()) }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            guard !box.isNull, box.width.isFinite, box.height.isFinite, max(box.width, box.height) > 0 else {
                context.setStrokeColor(NSColor.black.cgColor)
                context.stroke(rect.insetBy(dx: 3, dy: 3))
                return true
            }
            let inset: CGFloat = 2
            let k = (size - 2 * inset) / max(box.width, box.height)
            let t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
                .scaledBy(x: k, y: k)
                .translatedBy(x: -box.midX, y: -box.midY)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1)
            for entity in entities.prefix(400) {
                var transform = t
                if let path = entity.makePath().copy(using: &transform) { context.addPath(path) }
            }
            context.strokePath()
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Block Manager

/// List of the drawing's blocks and external references: insert, rename, delete unused,
/// reload, locate a moved file or convert a reference to a block (Bind).
final class BlockManagerController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let library: BlockLibrary
    private let useCount: (BlockDefinition) -> Int
    var onInsert: ((BlockDefinition) -> Void)?
    /// Edit the block's content (standalone, in its own coordinates).
    var onEdit: ((BlockDefinition) -> Void)?
    /// A library change (rename, delete, reload…) – redraw and mark the drawing as changed.
    var onChanged: (() -> Void)?
    var onAttach: (() -> Void)?

    private let panel: NSPanel
    private let table = NSTableView()
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var buttons: [String: NSButton] = [:]
    private var rows: [BlockDefinition] = []
    private weak var parent: NSWindow?

    init(library: BlockLibrary, useCount: @escaping (BlockDefinition) -> Int) {
        self.library = library
        self.useCount = useCount
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 400), styleMask: [.titled, .resizable],
                        backing: .buffered, defer: false)
        super.init()
        panel.title = "Blocks and External References"
        build()
    }

    private func column(_ id: String, _ title: String, _ width: CGFloat) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
        column.title = title
        column.width = width
        table.addTableColumn(column)
    }

    private func build() {
        guard let content = panel.contentView else { return }
        column("preview", "", 30)
        column("name", "Name", 170)
        column("type", "Type", 120)
        column("objects", "Objects", 60)
        column("used", "Used", 50)
        column("file", "File / status", 190)
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 26
        table.usesAlternatingRowBackgroundColors = true
        table.target = self
        table.doubleAction = #selector(insertClicked)
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        detail.font = NSFont.systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor

        func button(_ key: String, _ title: String, _ action: Selector, tip: String) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .push
            b.toolTip = tip
            buttons[key] = b
            return b
        }
        let left = NSStackView(views: [
            button("insert", "Insert", #selector(insertClicked), tip: "Place the block (or reference) in the drawing"),
            button("edit", "Edit…", #selector(editClicked), tip: "Change the objects of the block – every copy changes. In the drawing you can also double-click a block to edit it in place"),
            button("rename", "Rename…", #selector(renameClicked), tip: "New name – all references keep working"),
            button("delete", "Delete", #selector(deleteClicked), tip: "Remove a block that is not used anywhere"),
            button("purge", "Purge Unused", #selector(purgeClicked), tip: "Remove all blocks and references that are not used")])
        left.spacing = 6
        let right = NSStackView(views: [
            button("reload", "Reload", #selector(reloadClicked), tip: "Read the external reference from its file again"),
            button("browse", "Browse…", #selector(browseClicked), tip: "Find the file of an external reference that was moved or renamed"),
            button("bind", "Bind", #selector(bindClicked), tip: "Copy the external reference into this drawing as an ordinary block"),
            button("attach", "Attach…", #selector(attachClicked), tip: "Attach another drawing as an external reference")])
        right.spacing = 6
        let close = NSButton(title: "Close", target: self, action: #selector(closeClicked))
        close.bezelStyle = .push
        close.keyEquivalent = "\u{1b}"
        let bottom = NSStackView(views: [detail, close])
        bottom.spacing = 12
        detail.setContentHuggingPriority(.defaultLow, for: .horizontal)
        detail.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let stack = NSStackView(views: [scroll, left, right, bottom])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 220),
            bottom.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28)
        ])
    }

    func show(in window: NSWindow) {
        parent = window
        reload()
        window.beginSheet(panel, completionHandler: nil)
    }

    private func reload() {
        rows = library.blocks + library.xrefs
        table.reloadData()
        updateButtons()
    }

    private var selected: BlockDefinition? {
        let row = table.selectedRow
        return rows.indices.contains(row) ? rows[row] : nil
    }

    private func updateButtons() {
        let definition = selected
        let external = definition?.isExternal ?? false
        buttons["insert"]?.isEnabled = definition != nil
        buttons["edit"]?.isEnabled = definition != nil && !external
        buttons["rename"]?.isEnabled = definition != nil
        buttons["delete"]?.isEnabled = definition != nil
        buttons["purge"]?.isEnabled = !rows.isEmpty
        buttons["reload"]?.isEnabled = external
        buttons["browse"]?.isEnabled = external
        buttons["bind"]?.isEnabled = external
        if let definition = definition {
            var text = definition.note.isEmpty ? "" : definition.note + " · "
            if let source = definition.source {
                text += source.path
                if let error = source.error { text += " – ⚠︎ \(error)" }
            } else {
                text += "Base point \(LineType.format(definition.basePoint.x)), \(LineType.format(definition.basePoint.y))"
            }
            detail.stringValue = text
        } else {
            detail.stringValue = rows.isEmpty
                ? "No blocks yet. Select objects and use Create Block, or attach another drawing."
                : "Double-click a row to insert it. To change a block, use Edit… – or double-click the block in the drawing."
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { return rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard rows.indices.contains(row), let id = tableColumn?.identifier.rawValue else { return nil }
        let definition = rows[row]
        if id == "preview" {
            let view = NSImageView(image: BlockPreview.image(of: definition, size: 22))
            view.contentTintColor = .labelColor
            return view
        }
        let text: String
        switch id {
        case "name": text = definition.name
        case "type": text = definition.isExternal ? "External reference" : "Block"
        case "objects": text = "\(definition.entities.count)"
        case "used": text = "\(useCount(definition))"
        default:
            if let source = definition.source {
                text = source.error.map { "⚠︎ \($0)" } ?? source.fileName
            } else {
                text = definition.note
            }
        }
        let field = NSTextField(labelWithString: text)
        field.lineBreakMode = .byTruncatingMiddle
        field.toolTip = definition.source?.path
        if id == "file", definition.source?.error != nil { field.textColor = .systemOrange }
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
    }

    // MARK: Actions

    private func close() {
        parent?.endSheet(panel)
    }

    @objc private func closeClicked() { close() }

    @objc private func insertClicked() {
        guard let definition = selected else { return }
        close()
        onInsert?(definition)
    }

    @objc private func editClicked() {
        guard let definition = selected, !definition.isExternal else { return }
        close()
        onEdit?(definition)
    }

    @objc private func attachClicked() {
        close()
        onAttach?()
    }

    @objc private func renameClicked() {
        guard let definition = selected else { return }
        let alert = NSAlert()
        alert.messageText = "Rename “\(definition.name)”"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: definition.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: panel) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            if self.library.rename(definition, to: field.stringValue) {
                self.onChanged?()
                self.reload()
            } else {
                NSSound.beep()
            }
        }
    }

    @objc private func deleteClicked() {
        guard let definition = selected else { return }
        let count = useCount(definition)
        guard count == 0 else {
            let alert = NSAlert()
            alert.messageText = "“\(definition.name)” is used \(count)×"
            alert.informativeText = "Delete or explode its references in the drawing first."
            alert.beginSheetModal(for: panel, completionHandler: nil)
            return
        }
        library.remove(definition)
        definition.source?.accessedURL?.stopAccessingSecurityScopedResource()
        onChanged?()
        reload()
    }

    @objc private func purgeClicked() {
        var removed = 0
        // repeatedly – after deleting a block, a block nested in it may become unused too
        var again = true
        while again {
            again = false
            for definition in library.definitions where useCount(definition) == 0 {
                library.remove(definition)
                definition.source?.accessedURL?.stopAccessingSecurityScopedResource()
                removed += 1
                again = true
            }
        }
        if removed > 0 { onChanged?() }
        reload()
        detail.stringValue = removed == 0 ? "Everything is in use." : "Removed \(removed) unused block(s) and reference(s)."
    }

    @objc private func reloadClicked() {
        guard let definition = selected else { return }
        library.reload(definition)
        onChanged?()
        reload()
    }

    @objc private func browseClicked() {
        guard let definition = selected, let source = definition.source else { return }
        let open = NSOpenPanel()
        open.allowedContentTypes = [OhMyCADFile.contentType, UTType(filenameExtension: "dxf") ?? .data]
        open.message = "Find the drawing of the external reference “\(definition.name)”"
        open.beginSheetModal(for: panel) { [weak self] response in
            guard let self = self, response == .OK, let url = open.url else { return }
            source.accessedURL?.stopAccessingSecurityScopedResource()
            source.path = url.path
            source.bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            source.accessedURL = url
            source.modified = nil
            self.library.reload(definition)
            self.onChanged?()
            self.reload()
        }
    }

    @objc private func bindClicked() {
        guard let definition = selected, definition.isExternal else { return }
        definition.source?.accessedURL?.stopAccessingSecurityScopedResource()
        definition.source = nil
        library.adoptNested(of: definition)
        definition.markChanged()
        onChanged?()
        reload()
        detail.stringValue = "“\(definition.name)” is now an ordinary block of this drawing."
    }
}
