//
//  Managers.swift
//  OreMonoCAD
//
//  Document, selection, layers, viewport, grid and object snap.
//

import Cocoa

// MARK: - Selection Manager

class SelectionManager {
    private var selectedEntityIds: Set<UUID> = []
    var onSelectionChanged: (() -> Void)?

    var count: Int { return selectedEntityIds.count }
    var isEmpty: Bool { return selectedEntityIds.isEmpty }

    func isSelected(_ entity: CADEntity) -> Bool {
        return selectedEntityIds.contains(entity.id)
    }

    func select(_ entities: [CADEntity], additive: Bool = false) {
        if !additive { selectedEntityIds.removeAll() }
        for entity in entities { selectedEntityIds.insert(entity.id) }
        onSelectionChanged?()
    }

    func deselect(_ entities: [CADEntity]) {
        let before = selectedEntityIds.count
        for entity in entities { selectedEntityIds.remove(entity.id) }
        if selectedEntityIds.count != before { onSelectionChanged?() }
    }

    func toggleSelection(_ entity: CADEntity) {
        if selectedEntityIds.contains(entity.id) {
            selectedEntityIds.remove(entity.id)
        } else {
            selectedEntityIds.insert(entity.id)
        }
        onSelectionChanged?()
    }

    func clearSelection() {
        guard !selectedEntityIds.isEmpty else { return }
        selectedEntityIds.removeAll()
        onSelectionChanged?()
    }

    func getSelectedEntities(from entities: [CADEntity]) -> [CADEntity] {
        return entities.filter { selectedEntityIds.contains($0.id) }
    }
}

// MARK: - CAD Document

class CADDocument {
    private var entities: [UUID: CADEntity] = [:]
    private var entityOrder: [UUID] = []

    var onEntitiesChanged: (() -> Void)?
    /// Incremented on every content change (drawing refreshes its cache based on it).
    private(set) var revision = 0

    var isEmpty: Bool { return entityOrder.isEmpty }

    func addEntity(_ entity: CADEntity) {
        guard entities[entity.id] == nil else { return }
        entities[entity.id] = entity
        entityOrder.append(entity.id)
        revision += 1
        onEntitiesChanged?()
    }

    func removeEntity(_ entity: CADEntity) {
        guard entities.removeValue(forKey: entity.id) != nil else { return }
        entityOrder.removeAll { $0 == entity.id }
        revision += 1
        onEntitiesChanged?()
    }

    /// Removes `removed` and inserts `added` at the position of the first removed entity (keeps the draw order).
    /// One for one (Move, Rotate, Properties… and their Undo): each new object takes the place of its original,
    /// so objects of the same draw order keep lying over and under each other as before.
    /// - Parameter anchors: where each added object belonged before (from `orderAnchors(of:)` when it was removed) –
    ///   Undo of Join, Trim, Explode… puts the objects back in their own places instead of together in one place.
    func replace(_ removed: [CADEntity], with added: [CADEntity], anchors: [OrderAnchor]? = nil) {
        if let anchors = anchors, !added.isEmpty, anchors.count == added.count,
           Set(anchors.map { $0.id }) == Set(added.map { $0.id }), added.allSatisfy({ entities[$0.id] == nil }) {
            restore(added, at: anchors, removing: removed)
            return
        }
        if removed.count == added.count, removed.count > 1,
           removed.allSatisfy({ entities[$0.id] != nil }), added.allSatisfy({ entities[$0.id] == nil }),
           Set(added.map { $0.id }).count == added.count {
            var slot: [UUID: UUID] = [:]
            for (old, new) in zip(removed, added) { slot[old.id] = new.id }
            for old in removed { entities.removeValue(forKey: old.id) }
            for new in added { entities[new.id] = new }
            entityOrder = entityOrder.map { slot[$0] ?? $0 }
            revision += 1
            onEntitiesChanged?()
            return
        }
        let removedIds = Set(removed.map { $0.id }).filter { entities[$0] != nil }
        for id in removedIds { entities.removeValue(forKey: id) }
        // one pass over the order – large edits (Convert Units, Explode) stay fast
        var order: [UUID] = []
        order.reserveCapacity(entityOrder.count + added.count)
        var inserted = false
        func insertAdded() {
            inserted = true
            for entity in added where entities[entity.id] == nil {
                entities[entity.id] = entity
                order.append(entity.id)
            }
        }
        for id in entityOrder {
            if removedIds.contains(id) {
                if !inserted { insertAdded() }
            } else {
                order.append(id)
            }
        }
        if !inserted { insertAdded() }
        entityOrder = order
        revision += 1
        onEntitiesChanged?()
    }

    /// The place of an object in the drawing order: the nearest preceding object that stays (nil = the start).
    struct OrderAnchor {
        let id: UUID
        let after: UUID?
    }

    /// Places of the objects in the drawing order (in that order), relative to the objects that are not among them.
    func orderAnchors(of objects: [CADEntity]) -> [OrderAnchor] {
        let ids = Set(objects.map { $0.id })
        guard !ids.isEmpty else { return [] }
        var anchors: [OrderAnchor] = []
        var previous: UUID?
        for id in entityOrder {
            if ids.contains(id) {
                anchors.append(OrderAnchor(id: id, after: previous))
            } else {
                previous = id
            }
        }
        return anchors
    }

    /// Removes `removed` and puts `added` back after their anchors (objects with the same anchor keep their order).
    /// An anchor that is no longer in the drawing puts its objects at the end.
    private func restore(_ added: [CADEntity], at anchors: [OrderAnchor], removing removed: [CADEntity]) {
        let removedIds = Set(removed.map { $0.id }).filter { entities[$0] != nil }
        for id in removedIds { entities.removeValue(forKey: id) }
        for entity in added { entities[entity.id] = entity }
        var following: [UUID?: [UUID]] = [:]
        for anchor in anchors { following[anchor.after, default: []].append(anchor.id) }
        var order: [UUID] = []
        order.reserveCapacity(entityOrder.count + added.count)
        order += following.removeValue(forKey: nil) ?? []
        for id in entityOrder where !removedIds.contains(id) {
            order.append(id)
            if let next = following.removeValue(forKey: id) { order += next }
        }
        // anchors that disappeared meanwhile – keep the objects, at the end
        for anchor in anchors where following[anchor.after] != nil { order.append(anchor.id) }
        entityOrder = order
        revision += 1
        onEntitiesChanged?()
    }

    func getAllEntities() -> [CADEntity] {
        return entityOrder.compactMap { entities[$0] }
    }

    func getEntity(byId id: UUID) -> CADEntity? {
        return entities[id]
    }

    func contains(_ entity: CADEntity) -> Bool {
        return entities[entity.id] != nil
    }
}

// Line types (LineType, LineTypeLibrary) are in LineStyles.swift.

// MARK: - Layer Manager

struct Layer {
    var name: String
    var color: NSColor
    var isVisible: Bool = true
    var isLocked: Bool = false
    /// Plottable layer – non-plotting layers are displayed but not plotted.
    var isPrintable: Bool = true
    var lineType: LineType = .continuous
    /// Lineweight in mm.
    var lineWeight: CGFloat = LineWeights.defaultWeight
}

// MARK: - Line Weights

enum LineWeights {
    static let defaultWeight: CGFloat = 0.25
    /// Series of lineweights (mm) per ISO.
    static let standard: [CGFloat] = [0, 0.05, 0.09, 0.13, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40,
                                      0.50, 0.53, 0.60, 0.70, 0.80, 0.90, 1.00, 1.06, 1.20, 1.40, 1.58, 2.00, 2.11]

    static func title(_ mm: CGFloat) -> String {
        return String(format: "%.2f mm", Double(mm))
    }

    /// Standard and custom lineweights, sorted.
    static var all: [CGFloat] {
        return Array(Set(standard + custom)).sorted()
    }

    // The user's custom lineweights (remembered between launches)
    private static let customKey = "OreMonoCAD.customLineWeights"

    static var custom: [CGFloat] {
        get { return (UserDefaults.standard.array(forKey: customKey) as? [Double] ?? []).map { CGFloat($0) } }
        set { UserDefaults.standard.set(newValue.map { Double($0) }, forKey: customKey) }
    }

    /// Adds a custom lineweight (rounded to hundredths of a mm).
    @discardableResult
    static func addCustom(_ mm: CGFloat) -> CGFloat {
        let rounded = (mm * 100).rounded() / 100
        if !all.contains(rounded) { custom = custom + [rounded] }
        return rounded
    }
}

// MARK: - Drawing Scale

/// Paper : model scale, e.g. 1:50. The drawing is in millimeters.
struct DrawingScale: Equatable {
    var paper: CGFloat
    var model: CGFloat

    /// How many model units correspond to 1 mm on paper.
    var factor: CGFloat { return model / paper }

    var title: String {
        return "\(DrawingScale.format(paper)):\(DrawingScale.format(model))"
    }

    private static func format(_ value: CGFloat) -> String {
        let text = String(format: "%.4f", Double(value))
        var trimmed = text
        while trimmed.contains(".") && (trimmed.hasSuffix("0") || trimmed.hasSuffix(".")) { trimmed.removeLast() }
        return trimmed
    }

    static let presets: [DrawingScale] = [
        DrawingScale(paper: 10, model: 1), DrawingScale(paper: 5, model: 1), DrawingScale(paper: 2, model: 1),
        DrawingScale(paper: 1, model: 1), DrawingScale(paper: 1, model: 2), DrawingScale(paper: 1, model: 5),
        DrawingScale(paper: 1, model: 10), DrawingScale(paper: 1, model: 20), DrawingScale(paper: 1, model: 25),
        DrawingScale(paper: 1, model: 50), DrawingScale(paper: 1, model: 100), DrawingScale(paper: 1, model: 200),
        DrawingScale(paper: 1, model: 500), DrawingScale(paper: 1, model: 1000)
    ]

    /// “1:75”, “2:1” or just “75” (= 1:75); both sides may be expressions.
    static func parse(_ text: String) -> DrawingScale? {
        let parts = text.replacingOccurrences(of: " ", with: "").split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 1, let model = ExpressionEvaluator.evaluate(String(parts[0])), model > 0 {
            return DrawingScale(paper: 1, model: CGFloat(model))
        }
        guard parts.count == 2,
              let paper = ExpressionEvaluator.evaluate(String(parts[0])), paper > 0,
              let model = ExpressionEvaluator.evaluate(String(parts[1])), model > 0 else { return nil }
        return DrawingScale(paper: CGFloat(paper), model: CGFloat(model))
    }

    // The user's custom scales (remembered between launches)
    private static let customKey = "OreMonoCAD.customScales"

    static var custom: [DrawingScale] {
        get {
            let titles = UserDefaults.standard.stringArray(forKey: customKey) ?? []
            return titles.compactMap { parse($0) }
        }
        set {
            UserDefaults.standard.set(newValue.map { $0.title }, forKey: customKey)
        }
    }
}

class LayerManager {
    private var layers: [String: Layer] = [:]
    private var layerOrder: [String] = []
    private(set) var currentLayerName: String = "0"

    var onLayersChanged: (() -> Void)?
    var onCurrentLayerChanged: (() -> Void)?

    init() {
        addLayer(Layer(name: "0", color: .white))
    }

    var count: Int { return layerOrder.count }

    func addLayer(_ layer: Layer) {
        layers[layer.name] = layer
        if !layerOrder.contains(layer.name) {
            layerOrder.append(layer.name)
        }
        onLayersChanged?()
    }

    /// Suggests a free name for a new layer ("Layer1", "Layer2", …).
    func uniqueLayerName() -> String {
        var i = 1
        while layers["Layer\(i)"] != nil { i += 1 }
        return "Layer\(i)"
    }

    func updateLayer(_ name: String, _ change: (inout Layer) -> Void) {
        guard var layer = layers[name] else { return }
        change(&layer)
        layer.name = name   // renaming only via renameLayer
        layers[name] = layer
        onLayersChanged?()
    }

    @discardableResult
    func renameLayer(_ oldName: String, to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard oldName != "0", !trimmed.isEmpty, layers[trimmed] == nil,
              var layer = layers[oldName], let index = layerOrder.firstIndex(of: oldName) else { return false }
        layers.removeValue(forKey: oldName)
        layer.name = trimmed
        layers[trimmed] = layer
        layerOrder[index] = trimmed
        if currentLayerName == oldName { currentLayerName = trimmed }
        onLayersChanged?()
        return true
    }

    @discardableResult
    func removeLayer(_ name: String) -> Bool {
        guard name != "0", layers[name] != nil else { return false }
        layers.removeValue(forKey: name)
        layerOrder.removeAll { $0 == name }
        if currentLayerName == name {
            currentLayerName = "0"
            onCurrentLayerChanged?()
        }
        onLayersChanged?()
        return true
    }

    /// Replaces all layers (e.g. after opening a file). Layer "0" always exists.
    func reset(with newLayers: [Layer]) {
        layers.removeAll()
        layerOrder.removeAll()
        if !newLayers.contains(where: { $0.name == "0" }) {
            layers["0"] = Layer(name: "0", color: .white)
            layerOrder.append("0")
        }
        for layer in newLayers where layers[layer.name] == nil {
            layers[layer.name] = layer
            layerOrder.append(layer.name)
        }
        currentLayerName = "0"
        onLayersChanged?()
        onCurrentLayerChanged?()
    }

    func getLayer(_ name: String) -> Layer? {
        return layers[name]
    }

    func getAllLayers() -> [Layer] {
        return layerOrder.compactMap { layers[$0] }
    }

    @discardableResult
    func setCurrentLayer(_ name: String) -> Bool {
        guard layers[name] != nil else { return false }
        currentLayerName = name
        onCurrentLayerChanged?()
        return true
    }

    /// An unknown layer is treated as visible (so entities don't disappear).
    func isLayerVisible(_ name: String) -> Bool {
        return layers[name]?.isVisible ?? true
    }

    func isLayerPrintable(_ name: String) -> Bool {
        guard let layer = layers[name] else { return true }
        return layer.isPrintable && layer.isVisible
    }

    func isLayerLocked(_ name: String) -> Bool {
        return layers[name]?.isLocked ?? false
    }

    /// The entity's resulting color (ByLayer → layer color).
    func resolvedColor(for entity: CADEntity) -> NSColor {
        return entity.color ?? layers[entity.layer]?.color ?? .white
    }

    func lineType(for entity: CADEntity) -> LineType {
        return layers[entity.layer]?.lineType ?? .continuous
    }

    /// The resulting lineweight in mm (object → layer → default).
    func lineWeight(for entity: CADEntity) -> CGFloat {
        return entity.lineWeight ?? layers[entity.layer]?.lineWeight ?? LineWeights.defaultWeight
    }
}

// MARK: - Drawing units

/// What one drawing coordinate unit means.
enum DrawingUnits: String, CaseIterable {
    case mm, cm, m, inch = "in", ft

    var title: String {
        switch self {
        case .mm: return "Millimeters (mm)"
        case .cm: return "Centimeters (cm)"
        case .m: return "Meters (m)"
        case .inch: return "Inches (in)"
        case .ft: return "Feet (ft)"
        }
    }

    var suffix: String { return rawValue }

    /// How many millimeters one unit is.
    var mmPerUnit: CGFloat {
        switch self {
        case .mm: return 1
        case .cm: return 10
        case .m: return 1000
        case .inch: return 25.4
        case .ft: return 304.8
        }
    }

    /// $INSUNITS code for DXF.
    var dxfCode: Int {
        switch self {
        case .mm: return 4
        case .cm: return 5
        case .m: return 6
        case .inch: return 1
        case .ft: return 2
        }
    }
}

// MARK: - Geodetic base point (S-JTSK)

/// Tie of the project to S-JTSK (Křovák, EPSG 5514): project point `local` (drawing units)
/// corresponds to point Y, X in S-JTSK (meters, positive numbers as surveyors use them). Drawn “north up”
/// (drawing x axis = −Y, y axis = −X), without rotation. `heightZero` = ±0.000 in m a.s.l. (Bpv).
struct GeoReference {
    var local: CGPoint = .zero
    var y: Double = 0
    var x: Double = 0
    var heightZero: Double?

    /// A drawing without a base point: drawing coordinates (in m) = −Y, −X.
    static let identity = GeoReference()

    /// Base point of the currently open drawing (for Info on geodetic points).
    static var active = GeoReference.identity
    static var activeMetersPerUnit: Double = 0.001

    /// Drawing point → S-JTSK (Y, X in meters).
    func jtsk(of p: CGPoint, metersPerUnit: Double) -> (y: Double, x: Double) {
        let dx = Double(p.x - local.x) * metersPerUnit
        let dy = Double(p.y - local.y) * metersPerUnit
        return (y - dx, x - dy)
    }

    /// S-JTSK (Y, X in meters) → drawing point.
    func local(ofY yValue: Double, x xValue: Double, metersPerUnit: Double) -> CGPoint {
        return CGPoint(x: local.x + CGFloat((y - yValue) / metersPerUnit),
                       y: local.y + CGFloat((x - xValue) / metersPerUnit))
    }

    /// Transform of geodetic DXF coordinates (meters, x = −Y, y = −X) into the drawing.
    func fromSurveyDXF(metersPerUnit: Double) -> CGAffineTransform {
        let k = CGFloat(1 / metersPerUnit)
        // E = −Y, N = −X; local = local + (E − E0, N − N0) · k
        return CGAffineTransform(translationX: CGFloat(y), y: CGFloat(x))
            .concatenating(CGAffineTransform(scaleX: k, y: k))
            .concatenating(CGAffineTransform(translationX: local.x, y: local.y))
    }

    /// Back: from the drawing to geodetic DXF coordinates (meters, negative numbers).
    func toSurveyDXF(metersPerUnit: Double) -> CGAffineTransform {
        return fromSurveyDXF(metersPerUnit: metersPerUnit).inverted()
    }

    /// Does the point (DXF coordinates in meters) lie within the S-JTSK extent of the Czech Republic / Slovakia?
    static func looksLikeSurveyDXF(_ p: CGPoint) -> Bool {
        return p.x > -950_000 && p.x < -400_000 && p.y > -1_350_000 && p.y < -900_000
    }

    static func format(_ value: Double) -> String {
        return String(format: "%.3f", value)
    }
}

// MARK: - Viewport

class Viewport {
    private var zoom: CGFloat = 1.0
    private var panOffset: CGPoint = .zero
    private var viewSize: CGSize = .zero
    /// View rotation (radians, counterclockwise): the drawing rotates on screen,
    /// object coordinates stay the same. 0 = north (Y axis) up.
    private(set) var rotation: CGFloat = 0

    /// Rotation stored together with the pan (tab, file) – the pan does not change.
    func restoreRotation(_ angle: CGFloat) {
        guard angle.isFinite else { return }
        rotation = Geometry.normalizeAngle(angle)
        onViewChanged?()
    }

    /// Rotates the view about the screen center (the point in the middle stays in place).
    func setRotation(_ angle: CGFloat) {
        guard angle.isFinite else { return }
        let center = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let before = screenToWorld(center)
        rotation = Geometry.normalizeAngle(angle)
        if abs(rotation - 2 * .pi) < 1e-12 { rotation = 0 }
        let after = screenToWorld(center)
        panOffset.x += after.x - before.x
        panOffset.y += after.y - before.y
        onViewChanged?()
    }

    var onViewChanged: (() -> Void)?

    func setViewSize(_ size: CGSize) {
        viewSize = size
        onViewChanged?()
    }

    /// World → screen: pan → scale (zoom) → shift to the view center.
    func getTransform() -> CGAffineTransform {
        return CGAffineTransform(translationX: viewSize.width / 2, y: viewSize.height / 2)
            .scaledBy(x: zoom, y: zoom)
            .rotated(by: rotation)
            .translatedBy(x: panOffset.x, y: panOffset.y)
    }

    func screenToWorld(_ screenPoint: CGPoint) -> CGPoint {
        return screenPoint.applying(getTransform().inverted())
    }

    func worldToScreen(_ worldPoint: CGPoint) -> CGPoint {
        return worldPoint.applying(getTransform())
    }

    func zoomAt(screenPoint: CGPoint, factor: CGFloat) {
        guard factor > 0, factor.isFinite else { return }
        let worldPointBefore = screenToWorld(screenPoint)
        zoom = max(0.0001, min(10000.0, zoom * factor))
        let worldPointAfter = screenToWorld(screenPoint)
        panOffset.x += (worldPointAfter.x - worldPointBefore.x)
        panOffset.y += (worldPointAfter.y - worldPointBefore.y)
        onViewChanged?()
    }

    func zoomIn() {
        zoomAt(screenPoint: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), factor: 1.25)
    }

    func zoomOut() {
        zoomAt(screenPoint: CGPoint(x: viewSize.width / 2, y: viewSize.height / 2), factor: 1.0 / 1.25)
    }

    func pan(by screenOffset: CGPoint) {
        // screen offset → drawing offset (rotated back for a rotated view)
        let d = screenOffset.applying(CGAffineTransform(rotationAngle: -rotation))
        panOffset.x += d.x / zoom
        panOffset.y += d.y / zoom
        onViewChanged?()
    }

    func zoomToFit(entities: [CADEntity]) {
        guard viewSize.width > 0, viewSize.height > 0 else { return }
        var box = CGRect.null
        for entity in entities { box = box.union(entity.boundingBox()) }
        guard !box.isNull, box.minX.isFinite, box.minY.isFinite, box.maxX.isFinite, box.maxY.isFinite else { return }
        let center = CGPoint(x: box.midX, y: box.midY)
        if rotation != 0 {
            // bounding box size as it lies on the rotated screen
            let r = CGAffineTransform(rotationAngle: rotation)
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)].map { $0.applying(r) }
            let xs = corners.map { $0.x }, ys = corners.map { $0.y }
            box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        }

        let padding: CGFloat = 40
        let availableWidth = max(viewSize.width - 2 * padding, 10)
        let availableHeight = max(viewSize.height - 2 * padding, 10)

        var newZoom: CGFloat
        switch (box.width > 0, box.height > 0) {
        case (true, true): newZoom = min(availableWidth / box.width, availableHeight / box.height)
        case (true, false): newZoom = availableWidth / box.width
        case (false, true): newZoom = availableHeight / box.height
        case (false, false): newZoom = zoom
        }

        zoom = max(0.0001, min(10000.0, newZoom))
        panOffset = CGPoint(x: -center.x, y: -center.y)
        onViewChanged?()
    }

    func getCurrentZoom() -> CGFloat { return zoom }

    /// View state for saving to a file (.oremono).
    var viewState: (zoom: CGFloat, pan: CGPoint) {
        get { return (zoom, panOffset) }
        set {
            guard newValue.zoom.isFinite, newValue.zoom > 0,
                  newValue.pan.x.isFinite, newValue.pan.y.isFinite else { return }
            zoom = max(0.0001, min(10000.0, newValue.zoom))
            panOffset = newValue.pan
            onViewChanged?()
        }
    }
}

// MARK: - Grid Renderer

class GridRenderer {
    var showGrid = true
    /// The colored X and Y axes of the drawing coordinates.
    var showAxes = true
    var gridSpacing: CGFloat = 10.0
    /// When snapping to the grid, no lines finer than the snap step are drawn.
    var snapActive = false
    /// Drawing coordinates (UCS): the grid and axes lie in them. From UCS to the drawing.
    var ucsToWorld = CGAffineTransform.identity

    func draw(in context: CGContext, viewport: Viewport, viewSize: CGSize) {
        guard viewSize.width > 0, viewSize.height > 0, gridSpacing > 0 else { return }

        let zoom = viewport.getCurrentZoom()
        // the grid is computed in drawing coordinates and drawn through them
        let transform = ucsToWorld.concatenating(viewport.getTransform())
        let toLocal = transform.inverted()
        let corners = [CGPoint.zero, CGPoint(x: viewSize.width, y: 0),
                       CGPoint(x: viewSize.width, y: viewSize.height), CGPoint(x: 0, y: viewSize.height)].map { $0.applying(toLocal) }
        let minX = corners.map { $0.x }.min()!, maxX = corners.map { $0.x }.max()!
        let minY = corners.map { $0.y }.min()!, maxY = corners.map { $0.y }.max()!

        context.saveGState()

        if showGrid {
            // Adaptive spacing – lines are never closer than ~8 px nor farther apart than ~120 px
            var spacing = gridSpacing
            var guardCount = 0
            while spacing * zoom < 8 && guardCount < 40 { spacing *= 10; guardCount += 1 }
            while !snapActive && spacing * zoom > 120 && guardCount < 80 { spacing /= 10; guardCount += 1 }
            // safeguard: never more than ~1000 lines in one direction
            let lineLimit = 1000
            guard spacing > 0, spacing.isFinite, minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite,
                  (maxX - minX) / spacing < CGFloat(lineLimit), (maxY - minY) / spacing < CGFloat(lineLimit),
                  abs(minX / spacing) < 1e12, abs(minY / spacing) < 1e12 else {
                context.restoreGState()
                return
            }

            let minor = CGMutablePath()
            let major = CGMutablePath()

            var i = Int((minX / spacing).rounded(.down))
            var x = CGFloat(i) * spacing
            while x <= maxX {
                let path = (i % 10 == 0) ? major : minor
                path.move(to: CGPoint(x: x, y: minY), transform: transform)
                path.addLine(to: CGPoint(x: x, y: maxY), transform: transform)
                i += 1
                x = CGFloat(i) * spacing
            }

            var j = Int((minY / spacing).rounded(.down))
            var y = CGFloat(j) * spacing
            while y <= maxY {
                let path = (j % 10 == 0) ? major : minor
                path.move(to: CGPoint(x: minX, y: y), transform: transform)
                path.addLine(to: CGPoint(x: maxX, y: y), transform: transform)
                j += 1
                y = CGFloat(j) * spacing
            }

            context.setLineWidth(0.5)
            context.setStrokeColor(NSColor.gray.withAlphaComponent(0.12).cgColor)
            context.addPath(minor)
            context.strokePath()
            context.setStrokeColor(NSColor.gray.withAlphaComponent(0.28).cgColor)
            context.addPath(major)
            context.strokePath()
        }

        // X (red) and Y (green) axes of the drawing coordinates – lines across the whole screen
        let origin = CGPoint.zero.applying(transform)
        let reach = (viewSize.width + viewSize.height) * 2
        context.setLineWidth(1.0)
        for (axis, color) in [(CGPoint(x: 1, y: 0), NSColor.systemRed), (CGPoint(x: 0, y: 1), NSColor.systemGreen)] where showAxes {
            let tip = axis.applying(transform)
            let d = CGPoint(x: tip.x - origin.x, y: tip.y - origin.y)
            let length = hypot(d.x, d.y)
            guard length > 0, origin.x.isFinite, origin.y.isFinite else { continue }
            let u = CGPoint(x: d.x / length * reach, y: d.y / length * reach)
            context.setStrokeColor(color.withAlphaComponent(0.45).cgColor)
            context.move(to: CGPoint(x: origin.x - u.x, y: origin.y - u.y))
            context.addLine(to: CGPoint(x: origin.x + u.x, y: origin.y + u.y))
            context.strokePath()
        }
        context.restoreGState()
    }
}

// MARK: - Snap Manager

class SnapManager {
    var enabledSnaps: Set<SnapType> = AppSettings.enabledSnaps

    /// Line ends the cursor has hovered over – extensions lead from them.
    private(set) var acquired: [(point: CGPoint, direction: CGPoint)] = []
    private let maxAcquired = 4

    func clearAcquired() { acquired.removeAll() }

    private func acquire(_ point: CGPoint, of entity: CADEntity) {
        guard enabledSnaps.contains(.extensionLine) else { return }
        for primitive in entity.primitives() {
            guard case let .segment(a, b, _) = primitive else { continue }
            let tiny = max(Geometry.distance(a, b) * 1e-9, 1e-9)
            let direction: CGPoint
            if Geometry.distance(b, point) <= tiny { direction = (b - a).normalized }
            else if Geometry.distance(a, point) <= tiny { direction = (a - b).normalized }
            else { continue }
            guard direction != .zero else { continue }
            if acquired.contains(where: { Geometry.distance($0.point, point) <= tiny && Geometry.distance($0.direction, direction) < 1e-9 }) { continue }
            acquired.insert((point, direction), at: 0)
            if acquired.count > maxAcquired { acquired.removeLast() }
        }
    }

    /// The objects of a block (nested blocks too) near the cursor; any other object is itself.
    private static func intersectionParts(of entity: CADEntity, near point: CGPoint, tolerance: CGFloat,
                                          depth: Int = 0) -> [CADEntity] {
        guard let block = entity as? BlockReference, depth < 8 else { return [entity] }
        return block.resolvedEntities
            .filter { $0.distance(to: point) <= tolerance }
            .flatMap { intersectionParts(of: $0, near: point, tolerance: tolerance, depth: depth + 1) }
    }

    /// Where a polyline or spline crosses itself near the cursor. Neighbouring pieces only share a vertex,
    /// so they are skipped (zero-length pieces of repeated vertices are left out, as in Trim).
    private static func selfIntersections(of entity: CADEntity, near point: CGPoint, tolerance: CGFloat) -> [CGPoint] {
        guard let curve = entity as? CurveEntity else { return [] }
        let own = curve.primitives()
        guard own.count >= 3 else { return [] }
        let tiny = max(curve.curveLength, 1) * 1e-12
        let live = own.indices.filter { own[$0].length > tiny }
        let count = live.count
        // only the pieces near the cursor (a dense polyline has thousands)
        let near = live.enumerated().filter { own[$0.element].distance(to: point) <= tolerance }
        var hits: [CGPoint] = []
        for (m, first) in near.enumerated() {
            for second in near[(m + 1)...] {
                let x = first.offset, y = second.offset
                guard abs(x - y) >= 2, !(curve.isClosedCurve && min(x, y) == 0 && max(x, y) == count - 1) else { continue }
                hits += own[first.element].intersections(with: own[second.element]).map { $0.point }
            }
        }
        return hits
    }

    /// Finds the nearest snap point within tolerance (in world coordinates).
    /// `reference` = the previous point (for perpendicular and tangent).
    func findSnapPoint(near point: CGPoint, in entities: [CADEntity], tolerance: CGFloat,
                       from reference: CGPoint? = nil) -> SnapPoint? {
        var best: SnapPoint?
        var bestEntity: CADEntity?
        var bestDistance = tolerance

        func consider(_ snap: SnapPoint, _ entity: CADEntity? = nil) {
            let d = Geometry.distance(point, snap.point)
            // an intersection takes priority over equally distant points
            if d < bestDistance || (d <= bestDistance && snap.type == .intersection) {
                bestDistance = d
                best = snap
                bestEntity = entity
            }
        }

        // only entities near the cursor
        let nearby = entities.filter { entity in
            let box = entity.boundingBox()
            // infinite objects (construction lines) have no bounding box – distance decides
            if box.isNull { return entity.distance(to: point) <= tolerance * 4 }
            return box.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }

        for entity in nearby {
            for snap in entity.snapPoints() where enabledSnaps.contains(snap.type) {
                consider(snap, entity)
            }
        }

        if enabledSnaps.contains(.intersection) {
            // a block takes part through its own objects, so lines crossing inside one block snap too
            let close = nearby.filter { $0.distance(to: point) <= tolerance }.prefix(12)
            let candidates = Array(close.flatMap { SnapManager.intersectionParts(of: $0, near: point, tolerance: tolerance) }.prefix(24))
            for candidate in candidates {
                for hit in SnapManager.selfIntersections(of: candidate, near: point, tolerance: tolerance) {
                    consider(SnapPoint(point: hit, type: .intersection))
                }
            }
            for i in 0..<candidates.count {
                let pa = candidates[i].primitives()
                for j in (i + 1)..<max(candidates.count, i + 1) {
                    let pb = candidates[j].primitives()
                    for a in pa {
                        for b in pb {
                            for hit in a.intersections(with: b) {
                                consider(SnapPoint(point: hit.point, type: .intersection))
                            }
                        }
                    }
                }
            }
        }

        // perpendicular and tangent from the previous point
        if let from = reference, enabledSnaps.contains(.perpendicular) || enabledSnaps.contains(.tangent) {
            for entity in nearby where entity.distance(to: point) <= tolerance * 3 {
                for primitive in entity.primitives() {
                    if enabledSnaps.contains(.perpendicular), let foot = SnapManager.perpendicularFoot(from: from, to: primitive),
                       Geometry.distance(foot, from) > 1e-9 {
                        consider(SnapPoint(point: foot, type: .perpendicular, anchor: from), entity)
                    }
                    if enabledSnaps.contains(.tangent) {
                        for tangent in SnapManager.tangentPoints(from: from, to: primitive) {
                            consider(SnapPoint(point: tangent, type: .tangent, anchor: from), entity)
                        }
                    }
                }
            }
        }

        if let snap = best {
            if snap.type == .endpoint, let entity = bestEntity { acquire(snap.point, of: entity) }
            return snap
        }

        // weaker points: extension and nearest point on an object
        if enabledSnaps.contains(.extensionLine) {
            var feet: [(point: CGPoint, anchor: CGPoint, direction: CGPoint)] = []
            for line in acquired {
                let t = (point - line.point).dot(line.direction)
                guard t > tolerance * 0.5 else { continue }
                let foot = line.point + line.direction * t
                if Geometry.distance(foot, point) <= tolerance { feet.append((foot, line.point, line.direction)) }
            }
            // two extensions close to each other → their intersection
            if feet.count >= 2,
               let cross = Geometry.lineIntersection(feet[0].anchor, feet[0].anchor + feet[0].direction,
                                                     feet[1].anchor, feet[1].anchor + feet[1].direction),
               Geometry.distance(cross, point) <= tolerance {
                return SnapPoint(point: cross, type: .extensionLine, anchor: feet[0].anchor)
            }
            if let foot = feet.min(by: { Geometry.distance($0.point, point) < Geometry.distance($1.point, point) }) {
                return SnapPoint(point: foot.point, type: .extensionLine, anchor: foot.anchor)
            }
        }
        if enabledSnaps.contains(.nearest) {
            var nearest: CGPoint?
            var nearestDistance = tolerance
            for entity in nearby {
                for primitive in entity.primitives() {
                    let p = SnapManager.closestPoint(on: primitive, to: point)
                    let d = Geometry.distance(p, point)
                    if d <= nearestDistance {
                        nearestDistance = d
                        nearest = p
                    }
                }
            }
            if let p = nearest { return SnapPoint(point: p, type: .nearest) }
        }
        return nil
    }

    /// Foot of the perpendicular from a point to a segment / arc (nil if it lies outside it).
    static func perpendicularFoot(from p: CGPoint, to primitive: Primitive) -> CGPoint? {
        switch primitive {
        case let .segment(a, b, _):
            let t = Geometry.projectionParameter(of: p, ontoSegmentFrom: a, to: b)
            guard t >= -1e-9, t <= 1 + 1e-9 else { return nil }
            return Geometry.lerp(a, b, t)
        case let .arc(c, r, start, sweep, _):
            let d = Geometry.distance(p, c)
            guard d > 1e-9 else { return nil }
            let f = Primitive.ccwForm(start: start, sweep: sweep)
            let angle = Geometry.angle(from: c, to: p)
            for candidate in [angle, angle + .pi] where Primitive.isAngle(candidate, onArcStart: f.start, sweep: f.sweep) {
                return Geometry.pointOnCircle(c, r, candidate)
            }
            return nil
        }
    }

    /// Tangent points from a point to the arc's circle (only those lying on the arc).
    static func tangentPoints(from p: CGPoint, to primitive: Primitive) -> [CGPoint] {
        guard case let .arc(c, r, start, sweep, _) = primitive else { return [] }
        let d = Geometry.distance(p, c)
        guard d > r * (1 + 1e-9), r > 0 else { return [] }
        let base = Geometry.angle(from: c, to: p)
        let spread = acos(r / d)
        let f = Primitive.ccwForm(start: start, sweep: sweep)
        return [base + spread, base - spread]
            .filter { Primitive.isAngle($0, onArcStart: f.start, sweep: f.sweep) }
            .map { Geometry.pointOnCircle(c, r, $0) }
    }

    /// Nearest point of a segment / arc.
    static func closestPoint(on primitive: Primitive, to p: CGPoint) -> CGPoint {
        switch primitive {
        case let .segment(a, b, _):
            let t = max(0, min(1, Geometry.projectionParameter(of: p, ontoSegmentFrom: a, to: b)))
            return Geometry.lerp(a, b, t)
        case let .arc(c, r, start, sweep, _):
            let f = Primitive.ccwForm(start: start, sweep: sweep)
            let angle = Geometry.angle(from: c, to: p)
            if Primitive.isAngle(angle, onArcStart: f.start, sweep: f.sweep) { return Geometry.pointOnCircle(c, r, angle) }
            let s = Geometry.pointOnCircle(c, r, f.start), e = Geometry.pointOnCircle(c, r, f.start + f.sweep)
            return Geometry.distance(p, s) <= Geometry.distance(p, e) ? s : e
        }
    }
}
