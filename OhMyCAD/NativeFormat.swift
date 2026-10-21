//
//  NativeFormat.swift
//  OhMyCAD
//
//  The native .ohmycad drawing format (JSON). Unlike DXF it remembers everything:
//  exact colors (RGBA), lineweights, line types including their definition, layer plottability,
//  hatches (pattern, angle, scale, origin), dimensions, spline control points, drawing scale and view.
//
//  Principles:
//  - Every field except the entity type is optional → both older and newer versions can read the file.
//  - Unknown entity types are skipped and reported when reading (they don't wipe the whole drawing).
//  - When the structure changes, bump `currentVersion` and keep being able to read old versions.
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - File model
//
// Records are `nonisolated` so they can be JSON-encoded off the main actor; conversions from/to app
// types (layers, line types, hatch patterns) are `@MainActor`.

nonisolated struct OhMyCADFile: Codable {
    static let currentVersion = 1
    static let fileExtension = "ohmycad"
    static var contentType: UTType {
        return UTType(filenameExtension: fileExtension) ?? .json
    }

    var format = "OhMyCAD"
    var version = OhMyCADFile.currentVersion
    var savedAt: Date?
    var settings: DrawingSettingsRecord?
    var currentLayer: String?
    var layers: [LayerRecord]
    var entities: [EntityRecord]
    /// Layouts – paper with viewports into the model.
    var layouts: [LayoutRecord]?
    /// The open layout (nil = Model).
    var activeLayout: Int?
    /// Named plot settings (Page Setups).
    var pageSetups: [PlotSettings]?
    /// Last plot settings of the model.
    var modelPlot: PlotSettings?
    /// Block definitions and external references.
    var blocks: [BlockRecord]?
    /// Saved views (View › Named Views).
    var namedViews: [NamedViewRecord]?
}

/// A saved view: center, zoom and rotation – in the model or on a layout.
nonisolated struct NamedViewRecord: Codable {
    var name: String
    /// Layout name (nil = model).
    var layout: String?
    var zoom: CGFloat
    var pan: CGPoint
    var rotation: CGFloat?
}

/// A block definition (objects) or an external reference (file path only).
nonisolated struct BlockRecord: Codable {
    var name: String
    var base: CGPoint
    var note: String?
    var entities: [EntityRecord]?
    var xrefPath: String?
    var xrefBookmark: Data?
}

/// A layout: paper, margin and objects on paper (mm), including viewports.
nonisolated struct LayoutRecord: Codable {
    var name: String
    var paper: String?
    var landscape: Bool?
    var marginMM: CGFloat?
    var gridSize: CGFloat?
    var viewZoom: CGFloat?
    var viewPan: CGPoint?
    var plot: PlotSettings?
    var entities: [EntityRecord]
}

/// Link of a dimension point to an object's grip.
nonisolated struct LinkRecord: Codable {
    var point: Int
    var entity: Int
    var grip: Int
}

/// A color as sRGB components 0…1.
nonisolated struct RGBARecord: Codable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? .white
        r = Double(c.redComponent)
        g = Double(c.greenComponent)
        b = Double(c.blueComponent)
        a = Double(c.alphaComponent)
    }

    var color: NSColor {
        return NSColor(srgbRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }
}

nonisolated struct LineTypeRecord: Codable {
    var name: String
    var description: String?
    /// mm on paper: + dash, − gap, 0 dot
    var pattern: [CGFloat]
    /// The whole definition with texts and shapes – only for complex line types.
    var definition: String?

    @MainActor init(_ type: LineType) {
        name = type.name
        description = type.description
        pattern = type.pattern
        definition = type.marks.isEmpty ? nil : type.definition
    }

    /// Built-in / known type from the library, otherwise the type straight from the file (available for the session).
    @MainActor var lineType: LineType {
        let marks = definition.flatMap { try? LineType.parse($0).marks } ?? []
        if pattern.isEmpty && marks.isEmpty { return .continuous }
        if let known = LineTypeLibrary.named(name), known.pattern == pattern, known.marks == marks { return known }
        let type = LineType(name: name, description: description ?? "", pattern: pattern, marks: marks)
        if LineTypeLibrary.named(name) == nil {
            LineTypeLibrary.fromDrawing.append(type)
        }
        return type
    }
}

nonisolated struct HatchFamilyRecord: Codable {
    var angle: CGFloat
    var origin: CGPoint
    var shift: CGFloat
    var spacing: CGFloat
    var dashes: [CGFloat]?
}

nonisolated struct HatchPatternRecord: Codable {
    var name: String
    var description: String?
    var isSolid: Bool?
    var families: [HatchFamilyRecord]?

    @MainActor init(_ pattern: HatchPattern) {
        name = pattern.name
        description = pattern.description
        isSolid = pattern.isSolid ? true : nil
        families = pattern.families.map {
            HatchFamilyRecord(angle: $0.angle, origin: $0.origin, shift: $0.shift, spacing: $0.spacing,
                              dashes: $0.dashes.isEmpty ? nil : $0.dashes)
        }
    }

    @MainActor var pattern: HatchPattern {
        let families = (self.families ?? []).map {
            HatchLineFamily(angle: $0.angle, origin: $0.origin, shift: $0.shift, spacing: $0.spacing,
                            dashes: $0.dashes ?? [])
        }
        let solid = isSolid ?? false
        if let known = HatchPatternLibrary.named(name), known.isSolid == solid, known.families == families {
            return known
        }
        return HatchPattern(name: name, description: description ?? "", families: families, isSolid: solid)
    }
}

nonisolated struct LayerRecord: Codable {
    var name: String
    var color: RGBARecord
    var visible: Bool?
    var locked: Bool?
    var printable: Bool?
    var lineType: LineTypeRecord?
    var lineWeight: CGFloat?

    @MainActor init(_ layer: Layer) {
        name = layer.name
        color = RGBARecord(layer.color)
        visible = layer.isVisible
        locked = layer.isLocked
        printable = layer.isPrintable
        lineType = LineTypeRecord(layer.lineType)
        lineWeight = layer.lineWeight
    }

    @MainActor var layer: Layer {
        return Layer(name: name,
                     color: color.color,
                     isVisible: visible ?? true,
                     isLocked: locked ?? false,
                     isPrintable: printable ?? true,
                     lineType: lineType?.lineType ?? .continuous,
                     lineWeight: lineWeight ?? LineWeights.defaultWeight)
    }
}

nonisolated struct DrawingSettingsRecord: Codable {
    var scalePaper: CGFloat?
    var scaleModel: CGFloat?
    var showLineWeights: Bool?
    var lineWeightOnScreen: Bool?
    var smoothLines: Bool?
    var hatchPattern: HatchPatternRecord?
    var hatchAngle: CGFloat?
    /// nil = from the drawing scale
    var hatchScale: CGFloat?
    var viewZoom: CGFloat?
    var viewPan: CGPoint?
    /// drawing units (mm, cm, m, in, ft)
    var units: String?
    var gridSize: CGFloat?
    var polarIncrement: CGFloat?
    /// view rotation (radians) and drawing coordinates
    var viewRotation: CGFloat?
    var ucsAngle: CGFloat?
    var ucsOrigin: CGPoint?
    /// geodetic base point: drawing point ↔ Y, X in S-JTSK (m), ±0.000 (m Bpv)
    var geoLocal: CGPoint?
    var geoY: Double?
    var geoX: Double?
    var geoHeightZero: Double?
    /// display of the background grid and the X/Y axes (always written; nil in older files = the app setting)
    var showGrid: Bool?
    var showAxes: Bool?
}

/// A single entity. Fields are filled according to the type, the rest stay nil (and are not written to JSON).
nonisolated struct EntityRecord: Codable {
    var type: String
    var layer: String?
    /// nil = color by layer
    var color: RGBARecord?
    /// nil = lineweight by layer
    var lineWeight: CGFloat?
    /// Linetype scale of the object, nil = 1.
    var lineTypeScale: CGFloat?
    /// Draw order (pseudo Z), nil = 0.
    var drawOrder: Int?
    /// The group the object belongs to.
    var group: UUID?

    // geometry
    /// point elevation (m, Bpv)
    var z: Double?
    var start: CGPoint?
    var end: CGPoint?
    var center: CGPoint?
    var radius: CGFloat?
    var startAngle: CGFloat?
    var endAngle: CGFloat?
    /// polyline vertices / spline control points / dimension points
    var points: [CGPoint]?
    var closed: Bool?
    /// bulges of polyline segments (only when it has arcs)
    var bulges: [CGFloat]?

    // dimension
    var kind: String?
    var text: String?
    var textHeight: CGFloat?
    var arrowSize: CGFloat?
    var precision: Int?

    // hatch
    var loops: [[CGPoint]]?
    var pattern: HatchPatternRecord?
    /// A construction line clipped on one side (ray).
    var ray: Bool?
    var angle: CGFloat?
    var scale: CGFloat?
    var origin: CGPoint?

    // viewport on a layout: points = rectangle corners, center = model center
    var scalePaper: CGFloat?
    var scaleModel: CGFloat?
    var hiddenLayers: [String]?
    var locked: Bool?

    // text (start = insertion point, text, textHeight, angle = rotation) and the text below a dimension
    var fontFamily: String?
    var fontFace: String?
    var justify: String?
    var underline: Bool?
    var width: CGFloat?
    var lineSpacing: CGFloat?
    /// text width factor (nil = 1)
    var widthFactor: CGFloat?
    var belowText: String?

    // ellipse: center, end = major semi-axis vector, ratio, startAngle / endAngle = parameters
    var ratio: CGFloat?

    /// Associative dimension: points attached to grips of other objects (index in the same entity list).
    var links: [LinkRecord]?

    // block reference: blockName, start = insertion point, angle = rotation, scale, mirrored
    var blockName: String?
    var mirrored: Bool?

    // dimension: terminator (arrow, oblique…) and the fixed direction of a linear dimension (radians)
    var arrowStyle: String?
    var dimAngle: CGFloat?

    // image / PDF underlay: points = lower-left, lower-right and upper-left corner, kind = "pdf", text = file name
    var imageData: Data?
    var page: Int?
    var opacity: CGFloat?

    init(type: String) {
        self.type = type
    }
}

// MARK: - Entity conversion

enum NativeEntityCoder {
    /// Block library of the drawing currently being read (references are linked by name).
    static var blocks: BlockLibrary?

    static func record(for entity: CADEntity) -> EntityRecord? {
        var r: EntityRecord
        switch entity {
        case let point as SurveyPoint:
            r = EntityRecord(type: "point")
            r.center = point.position
            r.z = point.z
            r.text = point.number.isEmpty ? nil : point.number
            r.kind = point.code.isEmpty ? nil : point.code
        case let xline as ConstructionLine:
            r = EntityRecord(type: "xline")
            r.center = xline.point
            r.angle = xline.angle
            r.ray = xline.isRay ? true : nil
        case let line as Line:
            r = EntityRecord(type: "line")
            r.start = line.startPoint
            r.end = line.endPoint
        case let circle as Circle:
            r = EntityRecord(type: "circle")
            r.center = circle.center
            r.radius = circle.radius
        case let arc as Arc:
            r = EntityRecord(type: "arc")
            r.center = arc.center
            r.radius = arc.radius
            r.startAngle = arc.startAngle
            r.endAngle = arc.endAngle
        case let polyline as Polyline:
            r = EntityRecord(type: "polyline")
            r.points = polyline.vertices
            r.closed = polyline.closed
            if polyline.hasArcs { r.bulges = polyline.bulges }
        case let spline as Spline:
            r = EntityRecord(type: "spline")
            r.points = spline.controlPoints
            r.closed = spline.closed
        case let ellipse as Ellipse:
            r = EntityRecord(type: "ellipse")
            r.center = ellipse.center
            r.end = ellipse.majorAxis
            r.ratio = ellipse.ratio
            if !ellipse.isFull {
                r.startAngle = ellipse.startParam
                r.endAngle = ellipse.endParam
            }
        case let dimension as DimensionEntity:
            r = EntityRecord(type: "dimension")
            r.kind = dimension.kind.rawValue
            r.points = dimension.points
            r.radius = dimension.radius
            r.text = dimension.text.isEmpty ? nil : dimension.text
            r.textHeight = dimension.textHeight
            r.arrowSize = dimension.arrowSize
            r.precision = dimension.precision
            r.belowText = dimension.belowText.isEmpty ? nil : dimension.belowText
            r.arrowStyle = dimension.arrowStyle == .arrow ? nil : dimension.arrowStyle.rawValue
            r.dimAngle = dimension.fixedAngle
        case let hatch as HatchEntity:
            r = EntityRecord(type: "hatch")
            r.loops = hatch.loops
            r.pattern = HatchPatternRecord(hatch.pattern)
            r.angle = hatch.angle
            r.scale = hatch.scale
            r.origin = hatch.origin
        case let text as TextEntity:
            r = EntityRecord(type: "text")
            r.start = text.position
            r.text = text.text
            r.textHeight = text.height
            r.angle = text.rotation == 0 ? nil : text.rotation
            r.fontFamily = text.fontFamily.isEmpty ? nil : text.fontFamily
            r.fontFace = text.fontFace
            r.justify = text.justify == .left ? nil : text.justify.rawValue
            r.underline = text.underline ? true : nil
            r.width = text.boxWidth
            r.lineSpacing = text.lineSpacing == 1 ? nil : text.lineSpacing
            r.widthFactor = text.widthFactor == 1 ? nil : text.widthFactor
            r.kind = text.isRoomLabel ? "room" : nil
        case let reference as BlockReference:
            r = EntityRecord(type: "block")
            r.blockName = reference.definition.name
            r.start = reference.position
            r.angle = reference.rotation == 0 ? nil : reference.rotation
            r.scale = reference.scale == 1 ? nil : reference.scale
            r.mirrored = reference.mirrored ? true : nil
        case let viewport as ViewportEntity:
            r = EntityRecord(type: "viewport")
            r.points = [CGPoint(x: viewport.rect.minX, y: viewport.rect.minY), CGPoint(x: viewport.rect.maxX, y: viewport.rect.maxY)]
            r.center = viewport.modelCenter
            r.scalePaper = viewport.scale.paper
            r.scaleModel = viewport.scale.model
            r.hiddenLayers = viewport.frozenLayers.isEmpty ? nil : viewport.frozenLayers.sorted()
            r.locked = viewport.isLocked ? true : nil
        case let image as ImageEntity:
            r = EntityRecord(type: "image")
            r.points = [image.origin, image.xCorner, image.yCorner]
            r.imageData = image.data
            r.kind = image.isPDF ? "pdf" : nil
            r.page = image.isPDF ? image.page : nil
            r.text = image.fileName
            r.opacity = image.opacity == 1 ? nil : image.opacity
        case let wipeout as WipeoutEntity:
            r = EntityRecord(type: "wipeout")
            r.points = wipeout.vertices
        default:
            return nil
        }
        r.layer = entity.layer
        r.color = entity.color.map { RGBARecord($0) }
        r.lineWeight = entity.lineWeight
        r.lineTypeScale = entity.lineTypeScale
        r.drawOrder = entity.drawOrder == 0 ? nil : entity.drawOrder
        r.group = entity.groupID
        return r
    }

    static func entity(from r: EntityRecord) -> CADEntity? {
        let layer = r.layer ?? "0"
        let color = r.color?.color
        let entity: CADEntity?

        switch r.type {
        case "point":
            guard let position = r.center else { return nil }
            entity = SurveyPoint(position: position, z: r.z, number: r.text ?? "", code: r.kind ?? "", layer: layer, color: color)
        case "image":
            guard let corners = r.points, corners.count == 3, let data = r.imageData, !data.isEmpty else { return nil }
            let image = ImageEntity(data: data, isPDF: r.kind == "pdf", page: max(r.page ?? 1, 1), fileName: r.text ?? "",
                                    origin: corners[0], xCorner: corners[1], yCorner: corners[2], layer: layer, color: color)
            image.opacity = min(max(r.opacity ?? 1, 0.05), 1)
            entity = image
        case "wipeout":
            guard let corners = r.points, corners.count >= 3 else { return nil }
            entity = WipeoutEntity(vertices: corners, layer: layer, color: color)
        case "xline":
            guard let point = r.center, let angle = r.angle else { return nil }
            entity = ConstructionLine(point: point, angle: angle, isRay: r.ray ?? false, layer: layer, color: color)
        case "line":
            guard let start = r.start, let end = r.end else { return nil }
            entity = Line(start: start, end: end, layer: layer, color: color)
        case "circle":
            guard let center = r.center, let radius = r.radius, radius > 0 else { return nil }
            entity = Circle(center: center, radius: radius, layer: layer, color: color)
        case "arc":
            guard let center = r.center, let radius = r.radius, radius > 0,
                  let a1 = r.startAngle, let a2 = r.endAngle else { return nil }
            entity = Arc(center: center, radius: radius, startAngle: a1, endAngle: a2, layer: layer, color: color)
        case "polyline":
            guard let points = r.points, points.count >= 2 else { return nil }
            entity = Polyline(vertices: points, closed: r.closed ?? false, bulges: r.bulges ?? [], layer: layer, color: color)
        case "spline":
            guard let points = r.points, points.count >= 2 else { return nil }
            entity = Spline(controlPoints: points, closed: r.closed ?? false, layer: layer, color: color)
        case "ellipse":
            guard let center = r.center, let axis = r.end, axis.length > 0, let ratio = r.ratio, ratio > 0 else { return nil }
            entity = Ellipse(center: center, majorAxis: axis, ratio: ratio, startParam: r.startAngle ?? 0,
                             endParam: r.endAngle ?? 2 * .pi, layer: layer, color: color)
        case "dimension":
            guard let kindName = r.kind, let kind = DimensionKind(rawValue: kindName),
                  let points = r.points, !points.isEmpty else { return nil }
            let dimension = DimensionEntity(kind: kind, points: points, radius: r.radius ?? 0, text: r.text ?? "",
                                            textHeight: r.textHeight ?? 2.5, layer: layer, color: color)
            if let arrow = r.arrowSize { dimension.arrowSize = arrow }
            if let precision = r.precision { dimension.precision = precision }
            dimension.belowText = r.belowText ?? ""
            dimension.arrowStyle = r.arrowStyle.flatMap { DimArrowStyle(rawValue: $0) } ?? .arrow
            dimension.fixedAngle = r.dimAngle
            entity = dimension
        case "hatch":
            guard let loops = r.loops, !loops.isEmpty else { return nil }
            let hatch = HatchEntity(loops: loops, pattern: r.pattern?.pattern ?? .lines,
                                    angle: r.angle ?? 0, scale: r.scale ?? 1, layer: layer, color: color)
            if let origin = r.origin { hatch.origin = origin }
            entity = hatch
        case "text":
            guard let position = r.start, let value = r.text, !value.isEmpty, let height = r.textHeight, height > 0 else { return nil }
            let text = TextEntity(position: position, text: value, height: height, layer: layer, color: color)
            text.rotation = r.angle ?? 0
            text.fontFamily = r.fontFamily ?? ""
            text.fontFace = r.fontFace ?? "Regular"
            text.justify = r.justify.flatMap { TextJustify(rawValue: $0) } ?? .left
            text.underline = r.underline ?? false
            text.boxWidth = r.width.flatMap { $0 > 0 ? $0 : nil }
            text.lineSpacing = r.lineSpacing ?? 1
            text.widthFactor = r.widthFactor.flatMap { $0 > 0.05 && $0 < 20 ? $0 : nil } ?? 1
            text.isRoomLabel = r.kind == "room"
            entity = text
        case "block":
            guard let name = r.blockName, let definition = blocks?.named(name), let position = r.start else { return nil }
            let reference = BlockReference(definition: definition, position: position, layer: layer, color: color)
            reference.rotation = r.angle ?? 0
            reference.scale = (r.scale ?? 1) > 0 ? (r.scale ?? 1) : 1
            reference.mirrored = r.mirrored ?? false
            entity = reference
        case "viewport":
            guard let points = r.points, points.count == 2, let center = r.center else { return nil }
            let rect = CGRect(x: min(points[0].x, points[1].x), y: min(points[0].y, points[1].y),
                              width: abs(points[1].x - points[0].x), height: abs(points[1].y - points[0].y))
            guard rect.width > 0, rect.height > 0 else { return nil }
            let paper = r.scalePaper ?? 1, model = r.scaleModel ?? 1
            let viewport = ViewportEntity(rect: rect, modelCenter: center,
                                          scale: DrawingScale(paper: paper > 0 ? paper : 1, model: model > 0 ? model : 1),
                                          layer: layer, color: color)
            viewport.frozenLayers = Set(r.hiddenLayers ?? [])
            viewport.isLocked = r.locked ?? false
            entity = viewport
        default:
            entity = nil
        }
        entity?.lineWeight = r.lineWeight
        entity?.lineTypeScale = r.lineTypeScale
        entity?.drawOrder = r.drawOrder ?? 0
        entity?.groupID = r.group
        return entity
    }
}

// MARK: - Reading / writing

struct NativeDocument {
    var entities: [CADEntity] = []
    var layers: [Layer] = []
    var currentLayer: String?
    var settings: DrawingSettingsRecord?
    var skippedEntityTypes: [String: Int] = [:]
    var layouts: [DrawingLayout] = []
    var activeLayout: Int?
    var pageSetups: [PlotSettings] = []
    var modelPlot: PlotSettings?
    var blocks = BlockLibrary()
    var namedViews: [NamedViewRecord] = []
}

enum NativeFormatError: LocalizedError {
    case notOhMyCAD
    case newerVersion(Int)
    /// An OhMyCAD drawing whose content could not be read (the detail says where).
    case damaged(String)

    var errorDescription: String? {
        switch self {
        case .notOhMyCAD:
            return "The file is not an OhMyCAD drawing."
        case .damaged(let detail):
            return "The drawing is damaged and could not be opened (\(detail)). Try File › Open Backup…"
        case .newerVersion(let version):
            return "The drawing was saved by a newer version of OhMyCAD (format \(version)). Please update the app."
        }
    }
}

enum NativeFormat {

    /// Entity list records including associative dimension links (to an index in the list).
    static func records(for entities: [CADEntity]) -> [EntityRecord] {
        var index: [UUID: Int] = [:]
        var records: [EntityRecord] = []
        var owners: [CADEntity] = []
        for entity in entities {
            guard let record = NativeEntityCoder.record(for: entity) else { continue }
            index[entity.id] = records.count
            records.append(record)
            owners.append(entity)
        }
        for (position, entity) in owners.enumerated() {
            guard let dimension = entity as? DimensionEntity, !dimension.links.isEmpty else { continue }
            let links = dimension.links.sorted { $0.key < $1.key }.compactMap { entry -> LinkRecord? in
                guard let target = index[entry.value.entityID] else { return nil }
                return LinkRecord(point: entry.key, entity: target, grip: entry.value.grip)
            }
            records[position].links = links.isEmpty ? nil : links
        }
        return records
    }

    /// Entities from records; dimension links are attached to the newly created objects.
    static func entities(from records: [EntityRecord], skipped: inout [String: Int]) -> [CADEntity] {
        var created: [CADEntity?] = []
        for record in records {
            if let entity = NativeEntityCoder.entity(from: record),
               entity is ConstructionLine || DrawingSafety.isDrawable(entity.boundingBox()) {
                created.append(entity)
            } else {
                created.append(nil)
                skipped[record.type, default: 0] += 1
            }
        }
        for (position, record) in records.enumerated() {
            guard let links = record.links, let dimension = created[position] as? DimensionEntity else { continue }
            for link in links where created.indices.contains(link.entity) {
                guard let target = created[link.entity] else { continue }
                dimension.links[link.point] = DimensionLink(entityID: target.id, grip: link.grip)
            }
        }
        return created.compactMap { $0 }
    }

    static func write(entities: [CADEntity], layers: [Layer], currentLayer: String,
                      settings: DrawingSettingsRecord, layouts: [DrawingLayout] = [], activeLayout: Int? = nil,
                      pageSetups: [PlotSettings] = [], modelPlot: PlotSettings? = nil,
                      blocks: BlockLibrary? = nil, namedViews: [NamedViewRecord] = [], to url: URL) throws {
        let file = makeFile(entities: entities, layers: layers, currentLayer: currentLayer, settings: settings,
                            layouts: layouts, activeLayout: activeLayout, pageSetups: pageSetups,
                            modelPlot: modelPlot, blocks: blocks, namedViews: namedViews)
        let data = try encode(file, compact: false)
        try data.write(to: url, options: .atomic)
    }

    /// Record of the whole drawing (on the main thread – it reads the drawing's objects).
    static func makeFile(entities: [CADEntity], layers: [Layer], currentLayer: String,
                         settings: DrawingSettingsRecord, layouts: [DrawingLayout] = [], activeLayout: Int? = nil,
                         pageSetups: [PlotSettings] = [], modelPlot: PlotSettings? = nil,
                         blocks: BlockLibrary? = nil, namedViews: [NamedViewRecord] = []) -> OhMyCADFile {
        let blockRecords = (blocks?.definitions ?? []).map { definition -> BlockRecord in
            BlockRecord(name: definition.name, base: definition.basePoint,
                        note: definition.note.isEmpty ? nil : definition.note,
                        entities: definition.isExternal ? nil : NativeFormat.records(for: definition.entities),
                        xrefPath: definition.source?.path, xrefBookmark: definition.source?.bookmark)
        }
        let layoutRecords = layouts.map { layout in
            LayoutRecord(name: layout.name, paper: layout.paper.rawValue, landscape: layout.landscape,
                         marginMM: layout.marginMM, gridSize: layout.gridSize,
                         viewZoom: layout.viewState?.zoom, viewPan: layout.viewState?.pan, plot: layout.plotSettings,
                         entities: NativeFormat.records(for: layout.document.getAllEntities()))
        }
        let file = OhMyCADFile(savedAt: Date(),
                               settings: settings,
                               currentLayer: currentLayer,
                               layers: layers.map { LayerRecord($0) },
                               entities: NativeFormat.records(for: entities),
                               layouts: layoutRecords.isEmpty ? nil : layoutRecords,
                               activeLayout: activeLayout,
                               pageSetups: pageSetups.isEmpty ? nil : pageSetups,
                               modelPlot: modelPlot,
                               blocks: blockRecords.isEmpty ? nil : blockRecords,
                               namedViews: namedViews.isEmpty ? nil : namedViews)
        return file
    }

    /// Record → JSON. Can be called off the main thread too (background auto-save).
    /// compact = no indentation (smaller and faster – for auto-save).
    nonisolated static func encode(_ file: OhMyCADFile, compact: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = compact ? [] : [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        // invalid numbers (NaN, ∞) would break writing – they are written as text and the entity is skipped when reading
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf",
                                                                      negativeInfinity: "-inf", nan: "nan")
        return try encoder.encode(file)
    }

    /// A short description of a decoding error for the user: where in the file and what.
    static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return error.localizedDescription }
        let path: [CodingKey]
        let what: String
        switch decoding {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
            what = context.debugDescription
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
            what = "missing value"
        @unknown default:
            return error.localizedDescription
        }
        let place = path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
        return place.isEmpty ? what : "\(place): \(what)"
    }

    static func read(from url: URL) throws -> NativeDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf",
                                                                        negativeInfinity: "-inf", nan: "nan")
        let file: OhMyCADFile
        do {
            file = try decoder.decode(OhMyCADFile.self, from: data)
        } catch {
            Log.error("Reading \(url.lastPathComponent) failed: \(error)")
            // a JSON file that says it is OhMyCAD is a damaged drawing, not some other file
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               object["format"] as? String == "OhMyCAD" {
                throw NativeFormatError.damaged(NativeFormat.describe(error))
            }
            throw NativeFormatError.notOhMyCAD
        }
        guard file.format == "OhMyCAD" else { throw NativeFormatError.notOhMyCAD }
        guard file.version <= OhMyCADFile.currentVersion else { throw NativeFormatError.newerVersion(file.version) }

        var result = NativeDocument()
        // blocks: first all definitions (empty), then their content – references inside blocks are linked by name
        let previousBlocks = NativeEntityCoder.blocks
        NativeEntityCoder.blocks = result.blocks
        defer { NativeEntityCoder.blocks = previousBlocks }
        for record in file.blocks ?? [] where result.blocks.named(record.name) == nil {
            let source = record.xrefPath.map { XrefSource(path: $0, bookmark: record.xrefBookmark) }
            result.blocks.add(BlockDefinition(name: record.name, basePoint: record.base, entities: [],
                                              note: record.note ?? "", source: source))
        }
        for record in file.blocks ?? [] {
            guard let definition = result.blocks.named(record.name), !definition.isExternal else { continue }
            var skipped: [String: Int] = [:]
            // a block must not contain itself (not even through another block)
            definition.entities = NativeFormat.entities(from: record.entities ?? [], skipped: &skipped).filter { entity in
                guard let reference = entity as? BlockReference else { return true }
                return !reference.definition.contains(definition)
            }
        }
        result.layers = file.layers.map { $0.layer }
        result.currentLayer = file.currentLayer
        result.settings = file.settings
        result.entities = NativeFormat.entities(from: file.entities, skipped: &result.skippedEntityTypes)
        for record in file.layouts ?? [] {
            let layout = DrawingLayout(name: record.name, paper: record.paper.flatMap { PaperSize(rawValue: $0) } ?? .a3,
                                       landscape: record.landscape ?? true)
            if let margin = record.marginMM { layout.marginMM = margin }
            if let grid = record.gridSize, grid > 0 { layout.gridSize = grid }
            if let zoom = record.viewZoom, let pan = record.viewPan { layout.viewState = (zoom, pan) }
            layout.plotSettings = record.plot
            for entity in NativeFormat.entities(from: record.entities, skipped: &result.skippedEntityTypes) {
                layout.document.addEntity(entity)
            }
            result.layouts.append(layout)
        }
        if let active = file.activeLayout, result.layouts.indices.contains(active) { result.activeLayout = active }
        result.pageSetups = file.pageSetups ?? []
        result.namedViews = file.namedViews ?? []
        result.modelPlot = file.modelPlot
        return result
    }

    static func isNative(_ url: URL) -> Bool {
        return url.pathExtension.lowercased() == OhMyCADFile.fileExtension
    }
}
