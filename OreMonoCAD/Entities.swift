//
//  Entities.swift
//  OreMonoCAD
//
//  CAD entities: line, circle, arc, polyline (including rectangle), spline and dimensions.
//

import Cocoa

// MARK: - Snap

enum SnapType: String, CaseIterable {
    case endpoint = "Endpoint"
    case midpoint = "Midpoint"
    case center = "Center"
    case geometricCenter = "Geometric Center"
    case quadrant = "Quadrant"
    case intersection = "Intersection"
    case extensionLine = "Extension"
    case perpendicular = "Perpendicular"
    case tangent = "Tangent"
    case nearest = "Nearest"
    case node = "Node"
    case insertion = "Insertion"

    /// Description for the menu and settings.
    var detail: String {
        switch self {
        case .endpoint: return "Ends of lines, arcs and polyline vertices"
        case .midpoint: return "Middle of lines, arcs and polyline segments"
        case .center: return "Center of circles, arcs and ellipses"
        case .geometricCenter: return "Center of gravity of closed polylines and rectangles"
        case .quadrant: return "0°, 90°, 180° and 270° points of circles and ellipses"
        case .intersection: return "Where two objects cross"
        case .extensionLine: return "Along the extension of a line – hover over its end first, then move away"
        case .perpendicular: return "Foot of the perpendicular from the previous point"
        case .tangent: return "Tangent point on a circle or arc from the previous point"
        case .nearest: return "Any point on an object (only when no other snap is close)"
        case .node: return "Fit points of splines"
        case .insertion: return "Insertion point of texts and blocks"
        }
    }

    /// The default set (as after installation).
    static let defaultSet: Set<SnapType> = [.endpoint, .midpoint, .center, .quadrant, .intersection,
                                            .extensionLine, .perpendicular, .node, .insertion]
}

struct SnapPoint {
    let point: CGPoint
    let type: SnapType
    /// Where a construction line leads from (extension, perpendicular, tangent) – drawn dotted.
    var anchor: CGPoint? = nil
}

// MARK: - Draw order (pseudo Z)

/// Higher `drawOrder` = drawn above the others. At the same order the kind of object decides (hatches below lines,
/// texts on top – see `rank`), and otherwise the order in the drawing applies.
enum DrawOrder {
    static func sorted(_ entities: [CADEntity]) -> [CADEntity] {
        let indexed = entities.enumerated().map { (offset: $0.offset, entity: $0.element, rank: rank($0.element)) }
        return indexed.sorted { a, b in
            if a.entity.drawOrder != b.entity.drawOrder { return a.entity.drawOrder < b.entity.drawOrder }
            if a.rank != b.rank { return a.rank < b.rank }
            return a.offset < b.offset
        }.map { $0.entity }
    }

    /// At the same draw order: images and PDF underlays at the bottom, hatches above them, then lines and the rest,
    /// wipeouts above those, and texts and dimensions on top (so a wipeout covers the hatch under a text, not the text).
    private static func rank(_ entity: CADEntity) -> Int {
        if entity is ImageEntity { return 0 }
        if entity is HatchEntity { return 1 }
        if entity is WipeoutEntity { return 3 }
        if entity is TextEntity || entity is DimensionEntity { return 4 }
        return 2
    }
}

// MARK: - Line style

struct StrokeStyle {
    var color: NSColor
    var lineWidth: CGFloat = 1.0
    var dash: [CGFloat] = []
    /// Texts and shapes of a complex line type (nil = none).
    var marks: LineMarks? = nil
}

// MARK: - CAD Entity Protocol

protocol CADEntity: AnyObject {
    var id: UUID { get }
    var layer: String { get set }
    /// nil = color by layer (ByLayer)
    var color: NSColor? { get set }
    /// Lineweight in mm (nil = by layer).
    var lineWeight: CGFloat? { get set }
    /// Linetype scale of the object (nil = 1): multiplies the dashes, texts and shapes of the layer's line type.
    var lineTypeScale: CGFloat? { get set }
    /// Draw order (pseudo Z): a higher number is above a lower one.
    var drawOrder: Int { get set }
    /// The group the object belongs to (nil = none) – a click on one object selects the whole group (Groups.swift).
    var groupID: UUID? { get set }
    var typeName: String { get }
    var infoText: String { get }

    /// The entity's bounds in world coordinates.
    func makePath() -> CGPath
    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle)
    func boundingBox() -> CGRect
    /// Distance of a point from the entity (world).
    func distance(to point: CGPoint) -> CGFloat
    func snapPoints() -> [SnapPoint]
    func applyTransform(_ transform: CGAffineTransform)
    func clone() -> CADEntity
    /// Lines and arcs for intersections (an empty array = the entity is not a cutting edge).
    func primitives() -> [Primitive]
}

extension CADEntity {
    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        strokeWorldPath(makePath(), in: context, transform: transform, style: style)
    }

    func strokeWorldPath(_ path: CGPath, in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        var t = transform
        guard !path.isEmpty, let screenPath = path.copy(using: &t) else { return }
        // safeguard: don't draw invalid coordinates (NaN/∞) or absurdly large shapes at all
        let box = screenPath.boundingBoxOfPath
        guard DrawingSafety.isDrawable(box) else { return }
        context.saveGState()
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth)
        // thick lines (LWT) with rounded ends and joins – as in print
        if style.lineWidth > 1.5 {
            context.setLineCap(.round)
            context.setLineJoin(.round)
        }
        // dashing only for shapes of reasonable size (otherwise the system would compute millions of dashes)
        if !style.dash.isEmpty && DrawingSafety.canDash(box) {
            context.setLineDash(phase: 0, lengths: style.dash)
        }
        if style.marks?.hidesLine != true {
            context.addPath(screenPath)
            context.strokePath()
        }
        context.restoreGState()
        // texts and shapes of a complex line type (only for shapes of reasonable size, like dashing)
        if let marks = style.marks, DrawingSafety.canDash(box) {
            let mirrored = transform.a * transform.d - transform.b * transform.c < 0
            marks.draw(along: screenPath, in: context, mirrored: mirrored, color: style.color.cgColor, lineWidth: style.lineWidth)
        }
    }

    /// Carries the appearance properties (lineweight and draw order) and the group over to a copy / new piece.
    @discardableResult
    func copyStyle<T: CADEntity>(to copy: T) -> T {
        copy.lineWeight = lineWeight
        copy.lineTypeScale = lineTypeScale
        copy.drawOrder = drawOrder
        copy.groupID = groupID
        return copy
    }

    /// Takes over the lineweight, draw order and group of another object (for newly assembled pieces).
    @discardableResult
    func withStyle(of other: CADEntity) -> Self {
        lineWeight = other.lineWeight
        lineTypeScale = other.lineTypeScale
        drawOrder = other.drawOrder
        groupID = other.groupID
        return self
    }

    func distanceToPrimitives(_ point: CGPoint) -> CGFloat {
        return primitives().map { $0.distance(to: point) }.min() ?? .infinity
    }

    var colorDescription: String {
        guard let color = color else { return "ByLayer" }
        return ACIColor.name(for: color)
    }

    var commonInfo: String {
        return "Layer: \(layer)\nColor: \(colorDescription)"
    }
}

// MARK: - Curve Entity (can be trimmed and extended)

/// A curve with parameter = length from the start (0…curveLength).
protocol CurveEntity: CADEntity {
    var isClosedCurve: Bool { get }
    var curveLength: CGFloat { get }
    /// The part of the curve between parameters. For a closed curve `to` may exceed the length (wrapping past the start).
    func subCurve(from: CGFloat, to: CGFloat) -> CADEntity?
}

extension CurveEntity {
    /// Parameter of the nearest point on the curve.
    func parameter(of point: CGPoint) -> CGFloat {
        var best: CGFloat = 0
        var bestDistance = CGFloat.infinity
        for primitive in primitives() {
            let d = primitive.distance(to: point)
            if d < bestDistance {
                bestDistance = d
                best = primitive.closestParameter(to: point)
            }
        }
        return best
    }
}

// MARK: - Line

final class Line: CurveEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    var startPoint: CGPoint
    var endPoint: CGPoint

    init(start: CGPoint, end: CGPoint, layer: String = "0", color: NSColor? = nil) {
        self.startPoint = start
        self.endPoint = end
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Line" }
    var length: CGFloat { return Geometry.distance(startPoint, endPoint) }

    var infoText: String {
        let angle = Geometry.normalizeAngle(Geometry.angle(from: startPoint, to: endPoint)) * 180 / .pi
        return String(format: "Line\n%@\n\nStart:  %.3f, %.3f\nEnd:    %.3f, %.3f\nLength: %.3f\nAngle:  %@",
                      commonInfo, startPoint.x, startPoint.y, endPoint.x, endPoint.y, length, AngleStyle.text(angle, .direction))
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: startPoint)
        path.addLine(to: endPoint)
        return path
    }

    func boundingBox() -> CGRect {
        return CGRect(x: min(startPoint.x, endPoint.x), y: min(startPoint.y, endPoint.y),
                      width: abs(endPoint.x - startPoint.x), height: abs(endPoint.y - startPoint.y))
    }

    func distance(to point: CGPoint) -> CGFloat {
        return Geometry.distance(from: point, toSegmentFrom: startPoint, to: endPoint)
    }

    func snapPoints() -> [SnapPoint] {
        return [SnapPoint(point: startPoint, type: .endpoint),
                SnapPoint(point: endPoint, type: .endpoint),
                SnapPoint(point: Geometry.midpoint(startPoint, endPoint), type: .midpoint)]
    }

    func applyTransform(_ transform: CGAffineTransform) {
        startPoint = startPoint.applying(transform)
        endPoint = endPoint.applying(transform)
    }

    func clone() -> CADEntity {
        return copyStyle(to: Line(start: startPoint, end: endPoint, layer: layer, color: color))
    }

    func primitives() -> [Primitive] {
        return [.segment(a: startPoint, b: endPoint, param: 0)]
    }

    var isClosedCurve: Bool { return false }
    var curveLength: CGFloat { return length }

    func subCurve(from: CGFloat, to: CGFloat) -> CADEntity? {
        let l = length
        guard l > 0, to - from > Geometry.epsilon else { return nil }
        return Line(start: Geometry.lerp(startPoint, endPoint, from / l),
                    end: Geometry.lerp(startPoint, endPoint, to / l),
                    layer: layer, color: color)
    }
}

// MARK: - Survey Point

/// A point (POINT from DXF, a point from a coordinate list): a cross of constant size on screen,
/// with an elevation (Z in meters, Bpv), point number and code.
final class SurveyPoint: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    var position: CGPoint
    /// Elevation (m) – does not change when moving or scaling.
    var z: Double?
    var number: String
    var code: String

    init(position: CGPoint, z: Double? = nil, number: String = "", code: String = "", layer: String = "0", color: NSColor? = nil) {
        self.position = position
        self.z = z
        self.number = number
        self.code = code
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Point" }

    var infoText: String {
        var text = "Point\n\(commonInfo)\n"
        if !number.isEmpty { text += "\nNumber: \(number)" }
        if !code.isEmpty { text += "\nCode: \(code)" }
        text += String(format: "\nPosition: %.3f, %.3f", position.x, position.y)
        let geo = GeoReference.active.jtsk(of: position, metersPerUnit: GeoReference.activeMetersPerUnit)
        text += "\nS-JTSK Y: " + GeoReference.format(geo.y) + "\nS-JTSK X: " + GeoReference.format(geo.x)
        if let z = z {
            text += "\nHeight: " + GeoReference.format(z) + " m Bpv"
            if let zero = GeoReference.active.heightZero {
                let relative = z - zero
                text += "\nTo ±0.000: " + (relative >= 0 ? "+" : "") + GeoReference.format(relative) + " m"
            }
        }
        return text
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: position)
        path.addLine(to: position)
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        let p = position.applying(transform)
        guard p.x.isFinite, p.y.isFinite, abs(p.x) < DrawingSafety.maxCoordinate, abs(p.y) < DrawingSafety.maxCoordinate else { return }
        let r: CGFloat = 3.5
        context.saveGState()
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(max(1, min(style.lineWidth, 2)))
        context.move(to: CGPoint(x: p.x - r, y: p.y - r)); context.addLine(to: CGPoint(x: p.x + r, y: p.y + r))
        context.move(to: CGPoint(x: p.x - r, y: p.y + r)); context.addLine(to: CGPoint(x: p.x + r, y: p.y - r))
        context.strokePath()
        context.restoreGState()
    }

    func boundingBox() -> CGRect { return CGRect(origin: position, size: .zero) }

    func distance(to p: CGPoint) -> CGFloat { return Geometry.distance(p, position) }

    func snapPoints() -> [SnapPoint] { return [SnapPoint(point: position, type: .endpoint)] }

    func applyTransform(_ transform: CGAffineTransform) { position = position.applying(transform) }

    func clone() -> CADEntity {
        return copyStyle(to: SurveyPoint(position: position, z: z, number: number, code: code, layer: layer, color: color))
    }

    func primitives() -> [Primitive] { return [] }
}

// MARK: - Construction Line (XLINE)

/// An infinite construction line: a point and a direction. Drawn across the whole screen, used for layout
/// (snapping, intersections, trimming against it).
/// A ray (RAY, `isRay`): starts at point `point` and goes to infinity only in the direction `angle` –
/// created by trimming a construction line on one side; trimmed on both sides it becomes an ordinary line.
final class ConstructionLine: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    /// The point the line passes through.
    var point: CGPoint
    /// Direction (radians).
    var angle: CGFloat
    /// Ray: only from point `point` in the direction `angle`.
    var isRay = false
    /// “Infinity” for intersections and trimming (drawing units).
    static let reach: CGFloat = 1e7
    /// The area the line is drawn across when the context has no clip (set by the drawing area).
    static var drawingArea = CGRect(x: 0, y: 0, width: 4000, height: 3000)

    init(point: CGPoint, angle: CGFloat, isRay: Bool = false, layer: String = "0", color: NSColor? = nil) {
        self.point = point
        self.angle = Geometry.normalizeAngle(angle)
        self.isRay = isRay
        self.layer = layer
        self.color = color
    }

    var direction: CGPoint { return CGPoint(x: cos(angle), y: sin(angle)) }

    var typeName: String { return isRay ? "Ray" : "Construction Line" }

    var infoText: String {
        if isRay {
            let degrees = Geometry.normalizeAngle(angle) * 180 / .pi
            return String(format: "Ray (construction line trimmed on one side)\n%@\n\nStart:   %.3f, %.3f\nAngle:   %@",
                          commonInfo, point.x, point.y, AngleStyle.text(degrees, .direction))
        }
        // direction 0–180° (the line has no start or end)
        var degrees = Geometry.normalizeAngle(angle) * 180 / .pi
        if degrees >= 180 { degrees -= 180 }
        return String(format: "Construction Line\n%@\n\nThrough: %.3f, %.3f\nAngle:   %@", commonInfo, point.x, point.y, AngleStyle.text(degrees, .direction))
    }

    /// Parameter (distance from point `point` along the line) where the line starts: a ray at 0, otherwise “−infinity”.
    var startParameter: CGFloat { return isRay ? 0 : -ConstructionLine.reach }

    /// The line's point at parameter t (distance from `point` along the line).
    func location(at t: CGFloat) -> CGPoint { return point + direction * t }

    private var farEnds: (CGPoint, CGPoint) {
        let d = direction * ConstructionLine.reach
        return (isRay ? point : point - d, point + d)
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        let (a, b) = farEnds
        path.move(to: a)
        path.addLine(to: b)
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        // on screen: a segment across the whole visible area (around the projection of the screen center onto the line)
        let p = point.applying(transform)
        let tip = (point + direction).applying(transform)
        var d = tip - p
        let length = hypot(d.x, d.y)
        guard length > 0, p.x.isFinite, p.y.isFinite else { return }
        d = d * (1 / length)
        // drawn area: the context's clip, and when the context has none (a bitmap returns “infinity”), the view area
        var clip = context.boundingBoxOfClipPath
        if clip.isNull || clip.isInfinite || !clip.width.isFinite || clip.width > 1e6 || clip.height > 1e6 {
            clip = ConstructionLine.drawingArea
        }
        let center = CGPoint(x: clip.midX, y: clip.midY)
        let t = (center - p).dot(d)
        let q = p + d * t
        // the line doesn't cross the screen at all
        let diagonal = hypot(clip.width, clip.height)
        guard Geometry.distance(q, center) <= diagonal else { return }
        // segment across the screen in parameters from point p; a ray starts at p
        var from = t - diagonal
        let to = t + diagonal
        if isRay {
            guard to > 0 else { return }
            from = max(from, 0)
        }
        let path = CGMutablePath()
        path.move(to: p + d * from)
        path.addLine(to: p + d * to)
        context.saveGState()
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(style.lineWidth)
        if !style.dash.isEmpty { context.setLineDash(phase: 0, lengths: style.dash) }
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    /// Infinite – it has no bounds (always drawn and selected by distance).
    func boundingBox() -> CGRect { return .null }

    func distance(to p: CGPoint) -> CGFloat {
        let d = direction
        // ray: behind the origin the nearest point is the origin
        if isRay && (p - point).dot(d) < 0 { return Geometry.distance(p, point) }
        return abs((p - point).x * d.y - (p - point).y * d.x)
    }

    func snapPoints() -> [SnapPoint] {
        return [SnapPoint(point: point, type: isRay ? .endpoint : .midpoint)]
    }

    func applyTransform(_ transform: CGAffineTransform) {
        let d = direction
        let moved = CGPoint(x: transform.a * d.x + transform.c * d.y, y: transform.b * d.x + transform.d * d.y)
        point = point.applying(transform)
        if moved.length > 0 { angle = Geometry.normalizeAngle(atan2(moved.y, moved.x)) }
    }

    func clone() -> CADEntity {
        return copyStyle(to: ConstructionLine(point: point, angle: angle, isRay: isRay, layer: layer, color: color))
    }

    func primitives() -> [Primitive] {
        let (a, b) = farEnds
        return [.segment(a: a, b: b, param: 0)]
    }
}

// MARK: - Circle

final class Circle: CurveEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    var center: CGPoint
    var radius: CGFloat

    init(center: CGPoint, radius: CGFloat, layer: String = "0", color: NSColor? = nil) {
        self.center = center
        self.radius = radius
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Circle" }

    var infoText: String {
        return String(format: "Circle\n%@\n\nCenter:   %.3f, %.3f\nRadius:   %.3f\nDiameter: %.3f\nCircumf.: %.3f",
                      commonInfo, center.x, center.y, radius, radius * 2, 2 * .pi * radius)
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: boundingBox())
        return path
    }

    func boundingBox() -> CGRect {
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    func distance(to point: CGPoint) -> CGFloat {
        return abs(Geometry.distance(point, center) - radius)
    }

    func snapPoints() -> [SnapPoint] {
        var points = [SnapPoint(point: center, type: .center)]
        for i in 0..<4 {
            points.append(SnapPoint(point: Geometry.pointOnCircle(center, radius, CGFloat(i) * .pi / 2), type: .quadrant))
        }
        return points
    }

    func applyTransform(_ transform: CGAffineTransform) {
        center = center.applying(transform)
        radius *= Geometry.uniformScale(of: transform)
    }

    func clone() -> CADEntity {
        return copyStyle(to: Circle(center: center, radius: radius, layer: layer, color: color))
    }

    func primitives() -> [Primitive] {
        return [.arc(center: center, radius: radius, start: 0, sweep: 2 * .pi, param: 0)]
    }

    var isClosedCurve: Bool { return true }
    var curveLength: CGFloat { return 2 * .pi * radius }

    func subCurve(from: CGFloat, to: CGFloat) -> CADEntity? {
        guard radius > 0, to - from > Geometry.epsilon else { return nil }
        return Arc(center: center, radius: radius, startAngle: from / radius, endAngle: to / radius,
                   layer: layer, color: color)
    }
}

// MARK: - Arc (counterclockwise from startAngle to endAngle)

final class Arc: CurveEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    var center: CGPoint
    var radius: CGFloat
    var startAngle: CGFloat
    var endAngle: CGFloat

    init(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat,
         layer: String = "0", color: NSColor? = nil) {
        self.center = center
        self.radius = radius
        self.startAngle = Geometry.normalizeAngle(startAngle)
        self.endAngle = Geometry.normalizeAngle(endAngle)
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Arc" }

    /// Arc sweep (0, 2π].
    var sweep: CGFloat {
        let s = Geometry.ccwDelta(from: startAngle, to: endAngle)
        return s < 1e-12 ? 2 * .pi : s
    }

    var startPoint: CGPoint { return Geometry.pointOnCircle(center, radius, startAngle) }
    var endPoint: CGPoint { return Geometry.pointOnCircle(center, radius, startAngle + sweep) }
    var midPoint: CGPoint { return Geometry.pointOnCircle(center, radius, startAngle + sweep / 2) }

    var infoText: String {
        return String(format: "Arc\n%@\n\nCenter: %.3f, %.3f\nRadius: %.3f\nStart:  %@\nEnd:    %@\nAngle:  %@\nLength: %.3f",
                      commonInfo, center.x, center.y, radius,
                      AngleStyle.text(startAngle * 180 / .pi, .direction), AngleStyle.text(endAngle * 180 / .pi, .direction),
                      AngleStyle.text(sweep * 180 / .pi), sweep * radius)
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: startAngle,
                    endAngle: startAngle + sweep, clockwise: false)
        return path
    }

    func boundingBox() -> CGRect {
        var points = [startPoint, endPoint]
        for i in 0..<4 {
            let a = CGFloat(i) * .pi / 2
            if Geometry.ccwDelta(from: startAngle, to: a) <= sweep {
                points.append(Geometry.pointOnCircle(center, radius, a))
            }
        }
        let xs = points.map { $0.x }, ys = points.map { $0.y }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    func distance(to point: CGPoint) -> CGFloat {
        return Geometry.distance(from: point, toArcCenter: center, radius: radius, start: startAngle, sweep: sweep)
    }

    func snapPoints() -> [SnapPoint] {
        return [SnapPoint(point: startPoint, type: .endpoint),
                SnapPoint(point: endPoint, type: .endpoint),
                SnapPoint(point: midPoint, type: .midpoint),
                SnapPoint(point: center, type: .center)]
    }

    func applyTransform(_ transform: CGAffineTransform) {
        let s = startPoint.applying(transform)
        let e = endPoint.applying(transform)
        center = center.applying(transform)
        radius *= Geometry.uniformScale(of: transform)
        var a1 = Geometry.angle(from: center, to: s)
        var a2 = Geometry.angle(from: center, to: e)
        if Geometry.isMirroring(transform) { swap(&a1, &a2) }
        startAngle = Geometry.normalizeAngle(a1)
        endAngle = Geometry.normalizeAngle(a2)
    }

    func clone() -> CADEntity {
        return copyStyle(to: Arc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, layer: layer, color: color))
    }

    func primitives() -> [Primitive] {
        return [.arc(center: center, radius: radius, start: startAngle, sweep: sweep, param: 0)]
    }

    var isClosedCurve: Bool { return false }
    var curveLength: CGFloat { return sweep * radius }

    func subCurve(from: CGFloat, to: CGFloat) -> CADEntity? {
        guard radius > 0, to - from > Geometry.epsilon else { return nil }
        return Arc(center: center, radius: radius,
                   startAngle: startAngle + from / radius, endAngle: startAngle + to / radius,
                   layer: layer, color: color)
    }
}

// MARK: - Polyline (also rectangle)

final class Polyline: CurveEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    var vertices: [CGPoint]
    var closed: Bool
    /// Segment bulges (bulge as in DXF): bulges[i] belongs to the segment from vertex i to i+1
    /// (for a closed one also to the last segment back to the start). 0 = straight segment,
    /// positive = counterclockwise arc, tan(central angle / 4). An empty array = all straight.
    var bulges: [CGFloat]
    /// Width of the whole polyline in drawing units (a wide line, e.g. from DXF); 0 = a thin line drawn with its lineweight.
    var width: CGFloat = 0
    /// An outline drawn by the Wall tools: only these are joined with a new wall (Walls.joined).
    var isWall = false

    init(vertices: [CGPoint], closed: Bool = false, bulges: [CGFloat] = [], layer: String = "0", color: NSColor? = nil) {
        self.vertices = vertices
        self.closed = closed
        self.bulges = bulges
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Polyline" }

    var infoText: String {
        let arcs = (0..<segmentCount).filter { bulge(at: $0) != 0 }.count
        var text = String(format: "Polyline\n%@\n\nVertices: %ld\nArcs:     %ld\nClosed:   %@\nLength:   %.3f",
                          commonInfo, vertices.count, arcs, closed ? "Yes" : "No", curveLength)
        if width > 0 { text += String(format: "\nWidth:    %.3f", width) }
        return text
    }

    // MARK: Segments

    var segmentCount: Int {
        guard vertices.count >= 2 else { return 0 }
        return closed ? vertices.count : vertices.count - 1
    }

    func bulge(at index: Int) -> CGFloat {
        return index >= 0 && index < bulges.count ? bulges[index] : 0
    }

    var hasArcs: Bool { return bulges.contains { abs($0) > 1e-12 } }

    func segmentEnds(_ index: Int) -> (CGPoint, CGPoint) {
        return (vertices[index], vertices[(index + 1) % vertices.count])
    }

    /// Arc of a segment with a bulge: center, radius, start angle, signed sweep (+ = CCW).
    static func arcGeometry(from a: CGPoint, to b: CGPoint, bulge: CGFloat)
        -> (center: CGPoint, radius: CGFloat, start: CGFloat, sweep: CGFloat)? {
        let chord = Geometry.distance(a, b)
        guard abs(bulge) > 1e-12, chord > Geometry.epsilon else { return nil }
        let sweep = 4 * atan(bulge)
        let half = sweep / 2
        let radius = chord / (2 * abs(sin(half)))
        let u = (b - a) * (1 / chord)
        let h = (chord / 2) / tan(half)            // signed: positive = center on the left
        let center = Geometry.midpoint(a, b) + u.perpendicular * h
        return (center, radius, Geometry.angle(from: center, to: a), sweep)
    }

    /// Bulge of an arc given by a signed central angle.
    static func bulge(forSweep sweep: CGFloat) -> CGFloat {
        return tan(sweep / 4)
    }

    // MARK: CADEntity

    func makePath() -> CGPath {
        let path = CGMutablePath()
        guard let first = vertices.first else { return path }
        path.move(to: first)
        for i in 0..<segmentCount {
            let (a, b) = segmentEnds(i)
            if let arc = Polyline.arcGeometry(from: a, to: b, bulge: bulge(at: i)) {
                path.addArc(center: arc.center, radius: arc.radius, startAngle: arc.start,
                            endAngle: arc.start + arc.sweep, clockwise: arc.sweep < 0)
            } else if !(closed && i == segmentCount - 1) {
                path.addLine(to: b)
            }
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// A wide polyline is drawn as a band of its width (scaled with the view) with square ends, as in DXF;
    /// a thinner screen line than the lineweight is never used.
    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        guard width > 0 else {
            strokeWorldPath(makePath(), in: context, transform: transform, style: style)
            return
        }
        var t = transform
        let path = makePath()
        guard !path.isEmpty, let screenPath = path.copy(using: &t) else { return }
        let box = screenPath.boundingBoxOfPath
        guard DrawingSafety.isDrawable(box) else { return }
        context.saveGState()
        context.setStrokeColor(style.color.cgColor)
        context.setLineWidth(max(width * Geometry.uniformScale(of: transform), style.lineWidth))
        context.setLineCap(.butt)
        context.setLineJoin(.miter)
        if !style.dash.isEmpty && DrawingSafety.canDash(box) {
            context.setLineDash(phase: 0, lengths: style.dash)
        }
        context.addPath(screenPath)
        context.strokePath()
        context.restoreGState()
    }

    func boundingBox() -> CGRect {
        guard let first = vertices.first else { return .null }
        let half = width / 2
        if hasArcs {
            let box = makePath().boundingBoxOfPath
            if !box.isNull { return box.insetBy(dx: -half, dy: -half) }
        }
        var rect = CGRect(origin: first, size: .zero)
        for v in vertices.dropFirst() { rect = rect.union(CGRect(origin: v, size: .zero)) }
        return rect.insetBy(dx: -half, dy: -half)
    }

    func distance(to point: CGPoint) -> CGFloat {
        // a click anywhere on a wide band hits it
        return max(distanceToPrimitives(point) - width / 2, 0)
    }

    func snapPoints() -> [SnapPoint] {
        var points = vertices.map { SnapPoint(point: $0, type: .endpoint) }
        for primitive in primitives() {
            switch primitive {
            case let .segment(a, b, _):
                points.append(SnapPoint(point: Geometry.midpoint(a, b), type: .midpoint))
            case let .arc(c, r, start, sweep, _):
                points.append(SnapPoint(point: Geometry.pointOnCircle(c, r, start + sweep / 2), type: .midpoint))
                points.append(SnapPoint(point: c, type: .center))
            }
        }
        if isClosedCurve, let centroid = Polyline.centroid(of: vertices) {
            points.append(SnapPoint(point: centroid, type: .geometricCenter))
        }
        return points
    }

    /// Centroid of the polygon (nil for zero area).
    static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard points.count >= 3 else { return nil }
        var area: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0
        let origin = points[0]
        for i in 0..<points.count {
            let a = points[i] - origin, b = points[(i + 1) % points.count] - origin
            let cross = a.cross(b)
            area += cross
            cx += (a.x + b.x) * cross
            cy += (a.y + b.y) * cross
        }
        guard abs(area) > 1e-12 else { return nil }
        return CGPoint(x: origin.x + cx / (3 * area), y: origin.y + cy / (3 * area))
    }

    func applyTransform(_ transform: CGAffineTransform) {
        vertices = vertices.map { $0.applying(transform) }
        // mirroring reverses the direction of arcs
        if Geometry.isMirroring(transform) { bulges = bulges.map { -$0 } }
        if width > 0 {
            let k = Geometry.uniformScale(of: transform)
            if k.isFinite, k > 0 { width *= k }
        }
    }

    func clone() -> CADEntity {
        let copy = Polyline(vertices: vertices, closed: closed, bulges: bulges, layer: layer, color: color)
        copy.width = width
        copy.isWall = isWall
        return copyStyle(to: copy)
    }

    func primitives() -> [Primitive] {
        guard vertices.count >= 2 else { return [] }
        var result: [Primitive] = []
        var param: CGFloat = 0
        for i in 0..<segmentCount {
            let (a, b) = segmentEnds(i)
            let primitive: Primitive
            if let arc = Polyline.arcGeometry(from: a, to: b, bulge: bulge(at: i)) {
                primitive = .arc(center: arc.center, radius: arc.radius, start: arc.start, sweep: arc.sweep, param: param)
            } else {
                primitive = .segment(a: a, b: b, param: param)
            }
            result.append(primitive)
            param += primitive.length
        }
        return result
    }

    var isClosedCurve: Bool { return closed && vertices.count >= (hasArcs ? 2 : 3) }

    var curveLength: CGFloat {
        return primitives().reduce(0) { $0 + $1.length }
    }

    /// A piece of the polyline between two parameters (for a closed one also past the start) – arcs stay arcs.
    func subCurve(from: CGFloat, to: CGFloat) -> CADEntity? {
        guard to - from > Geometry.epsilon else { return nil }
        let pieces = primitives()
        let total = curveLength
        let laps = isClosedCurve ? 2 : 1
        let tiny = max(total, 1) * 1e-12
        var points: [CGPoint] = []
        var newBulges: [CGFloat] = []
        for lap in 0..<laps {
            for primitive in pieces {
                let start: CGFloat
                switch primitive {
                case let .segment(_, _, p): start = p
                case let .arc(_, _, _, _, p): start = p
                }
                let p0 = start + CGFloat(lap) * total
                let length = primitive.length
                let a = max(from, p0), b = min(to, p0 + length)
                guard b - a > tiny, length > 0 else { continue }
                let ua = a - p0, ub = b - p0
                let first: CGPoint, last: CGPoint, bulgeValue: CGFloat
                switch primitive {
                case let .segment(s, e, _):
                    first = Geometry.lerp(s, e, ua / length)
                    last = Geometry.lerp(s, e, ub / length)
                    bulgeValue = 0
                case let .arc(c, r, st, sw, _):
                    let sign: CGFloat = sw < 0 ? -1 : 1
                    let a1 = st + sign * ua / r, a2 = st + sign * ub / r
                    first = Geometry.pointOnCircle(c, r, a1)
                    last = Geometry.pointOnCircle(c, r, a2)
                    bulgeValue = Polyline.bulge(forSweep: a2 - a1)
                }
                if points.isEmpty { points.append(first) }
                newBulges.append(bulgeValue)
                points.append(last)
            }
        }
        guard points.count >= 2 else { return nil }
        newBulges.append(0)
        let piece = Polyline(vertices: points, closed: false, bulges: newBulges, layer: layer, color: color)
        piece.width = width
        return piece
    }

    /// Polyline points between two parameters (for a closed curve also past the start).
    static func pointsBetween(primitives: [Primitive], closed: Bool, total: CGFloat,
                              from: CGFloat, to: CGFloat) -> [CGPoint] {
        // list of vertices with parameters, twice around for a closed curve
        var nodes: [(param: CGFloat, point: CGPoint)] = []
        let laps = closed ? 2 : 1
        for lap in 0..<laps {
            let offset = CGFloat(lap) * total
            for case let .segment(a, b, param) in primitives {
                if nodes.isEmpty { nodes.append((param + offset, a)) }
                nodes.append((param + offset + Geometry.distance(a, b), b))
            }
        }
        guard nodes.count >= 2 else { return [] }

        func point(at t: CGFloat) -> CGPoint {
            if t <= nodes[0].param { return nodes[0].point }
            for i in 1..<nodes.count where t <= nodes[i].param {
                let span = nodes[i].param - nodes[i - 1].param
                let local = span > 0 ? (t - nodes[i - 1].param) / span : 0
                return Geometry.lerp(nodes[i - 1].point, nodes[i].point, local)
            }
            return nodes[nodes.count - 1].point
        }

        let tolerance: CGFloat = 1e-9
        var result = [point(at: from)]
        for node in nodes where node.param > from + tolerance && node.param < to - tolerance {
            if Geometry.distance(node.point, result[result.count - 1]) > tolerance {
                result.append(node.point)
            }
        }
        let last = point(at: to)
        if Geometry.distance(last, result[result.count - 1]) > tolerance { result.append(last) }
        return result
    }
}

// MARK: - Spline (Catmull-Rom through the given points, drawn with Bézier segments)

struct CubicBezierSegment {
    var p0: CGPoint
    var p1: CGPoint
    var p2: CGPoint
    var p3: CGPoint

    func point(at t: CGFloat) -> CGPoint {
        let mt = 1 - t
        let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * p1.x + c * p2.x + d * p3.x,
                       y: a * p0.y + b * p1.y + c * p2.y + d * p3.y)
    }
}

final class Spline: CurveEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    private(set) var controlPoints: [CGPoint]
    private(set) var segments: [CubicBezierSegment] = []
    private(set) var flattened: [CGPoint] = []
    var closed: Bool

    private static let samplesPerSegment = 24

    init(controlPoints: [CGPoint], closed: Bool = false, layer: String = "0", color: NSColor? = nil) {
        self.controlPoints = controlPoints
        self.closed = closed
        self.layer = layer
        self.color = color
        rebuild()
    }

    var typeName: String { return "Spline" }

    var infoText: String {
        return String(format: "Spline\n%@\n\nFit points: %ld\nClosed:     %@\nLength:     %.3f",
                      commonInfo, controlPoints.count, closed ? "Yes" : "No", curveLength)
    }

    func setControlPoints(_ points: [CGPoint]) {
        controlPoints = points
        rebuild()
    }

    /// Catmull-Rom → cubic Bézier segments (tangent = (next − previous) / 2).
    private func rebuild() {
        segments.removeAll()
        let pts = controlPoints
        let n = pts.count
        guard n >= 2 else { flattened = pts; return }
        let isClosed = closed && n > 2

        func tangent(_ i: Int) -> CGPoint {
            let prev: CGPoint, next: CGPoint
            if isClosed {
                prev = pts[(i - 1 + n) % n]
                next = pts[(i + 1) % n]
            } else {
                prev = pts[max(i - 1, 0)]
                next = pts[min(i + 1, n - 1)]
            }
            return (next - prev) * 0.5
        }

        let count = isClosed ? n : n - 1
        for i in 0..<count {
            let j = (i + 1) % n
            let p0 = pts[i], p3 = pts[j]
            let m0 = tangent(i), m1 = tangent(j)
            segments.append(CubicBezierSegment(p0: p0, p1: p0 + m0 * (1.0 / 3.0),
                                               p2: p3 - m1 * (1.0 / 3.0), p3: p3))
        }

        flattened = [segments[0].p0]
        for segment in segments {
            for k in 1...Spline.samplesPerSegment {
                flattened.append(segment.point(at: CGFloat(k) / CGFloat(Spline.samplesPerSegment)))
            }
        }
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        guard let first = segments.first else { return path }
        path.move(to: first.p0)
        for s in segments { path.addCurve(to: s.p3, control1: s.p1, control2: s.p2) }
        return path
    }

    func boundingBox() -> CGRect {
        guard let first = flattened.first else { return .null }
        var rect = CGRect(origin: first, size: .zero)
        for p in flattened.dropFirst() { rect = rect.union(CGRect(origin: p, size: .zero)) }
        return rect
    }

    func distance(to point: CGPoint) -> CGFloat {
        return distanceToPrimitives(point)
    }

    func snapPoints() -> [SnapPoint] {
        guard let first = controlPoints.first, let last = controlPoints.last else { return [] }
        var points = [SnapPoint(point: first, type: .endpoint)]
        if !(closed && controlPoints.count > 2) { points.append(SnapPoint(point: last, type: .endpoint)) }
        for p in controlPoints.dropFirst().dropLast() { points.append(SnapPoint(point: p, type: .node)) }
        return points
    }

    func applyTransform(_ transform: CGAffineTransform) {
        setControlPoints(controlPoints.map { $0.applying(transform) })
    }

    func clone() -> CADEntity {
        return copyStyle(to: Spline(controlPoints: controlPoints, closed: closed, layer: layer, color: color))
    }

    func primitives() -> [Primitive] {
        guard flattened.count >= 2 else { return [] }
        var result: [Primitive] = []
        var param: CGFloat = 0
        for i in 0..<(flattened.count - 1) {
            result.append(.segment(a: flattened[i], b: flattened[i + 1], param: param))
            param += Geometry.distance(flattened[i], flattened[i + 1])
        }
        return result
    }

    var isClosedCurve: Bool { return closed && controlPoints.count > 2 }

    var curveLength: CGFloat {
        return primitives().reduce(0) { $0 + $1.length }
    }

    /// A trimmed part of a spline is stored as a dense polyline (it looks the same).
    func subCurve(from: CGFloat, to: CGFloat) -> CADEntity? {
        guard to - from > Geometry.epsilon else { return nil }
        let points = Polyline.pointsBetween(primitives: primitives(), closed: isClosedCurve,
                                            total: curveLength, from: from, to: to)
        guard points.count >= 2 else { return nil }
        return Polyline(vertices: points, closed: false, layer: layer, color: color)
    }
}

// MARK: - Ellipse (including elliptical arc)

/// Ellipse: center, major semi-axis vector and the minor/major semi-axis ratio.
/// An elliptical arc runs counterclockwise from `startParam` to `endParam`
/// (parametric angle: point = center + major·cos t + minor·sin t).
final class Ellipse: CurveEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    var center: CGPoint { didSet { invalidate() } }
    /// From the center to the end of the major semi-axis.
    var majorAxis: CGPoint { didSet { invalidate() } }
    /// Minor / major semi-axis (0 < ratio ≤ 1).
    var ratio: CGFloat { didSet { invalidate() } }
    var startParam: CGFloat { didSet { invalidate() } }
    var endParam: CGFloat { didSet { invalidate() } }

    private static let fullSegments = 120
    private var cache: (points: [CGPoint], params: [CGFloat], lengths: [CGFloat])?

    init(center: CGPoint, majorAxis: CGPoint, ratio: CGFloat, startParam: CGFloat = 0, endParam: CGFloat = 2 * .pi,
         layer: String = "0", color: NSColor? = nil) {
        self.center = center
        self.majorAxis = majorAxis
        self.ratio = ratio
        self.startParam = startParam
        self.endParam = endParam
        self.layer = layer
        self.color = color
        normalize()
    }

    /// An ellipse from two semi-axes (length b perpendicular to the major axis).
    convenience init(center: CGPoint, axisEnd: CGPoint, minorRadius b: CGFloat, layer: String = "0") {
        let major = axisEnd - center
        self.init(center: center, majorAxis: major, ratio: major.length > 0 ? b / major.length : 1, layer: layer)
    }

    private func invalidate() { cache = nil }

    /// The major semi-axis is always the longer one (otherwise the axes are swapped) and the parameters are in a sane range.
    private func normalize() {
        if ratio > 1 + 1e-12, ratio.isFinite {
            let minor = minorAxis
            let full = isFull
            majorAxis = minor
            ratio = 1 / ratio
            if !full {
                startParam -= .pi / 2
                endParam -= .pi / 2
            }
        }
        ratio = max(min(ratio, 1), 1e-6)
        if isFull {
            startParam = 0
            endParam = 2 * .pi
        } else {
            startParam = Geometry.normalizeAngle(startParam)
            endParam = Geometry.normalizeAngle(endParam)
        }
    }

    var typeName: String { return isFull ? "Ellipse" : "Elliptical Arc" }

    var majorRadius: CGFloat { return majorAxis.length }
    var minorRadius: CGFloat { return majorAxis.length * ratio }
    /// From the center to the end of the minor semi-axis (the major one rotated by +90°).
    var minorAxis: CGPoint { return majorAxis.perpendicular * ratio }
    var rotation: CGFloat { return atan2(majorAxis.y, majorAxis.x) }

    var sweep: CGFloat {
        let s = Geometry.ccwDelta(from: startParam, to: endParam)
        return s < 1e-9 ? 2 * .pi : s
    }

    var isFull: Bool {
        let d = endParam - startParam
        return abs(d) < 1e-9 || abs(abs(d) - 2 * .pi) < 1e-9
    }

    func point(at t: CGFloat) -> CGPoint {
        return center + majorAxis * cos(t) + minorAxis * sin(t)
    }

    /// Parameter of a point (the angle in ellipse coordinates).
    func parameter(atPoint p: CGPoint) -> CGFloat {
        let a = majorRadius, b = minorRadius
        guard a > 0, b > 0 else { return 0 }
        let u = majorAxis * (1 / a), v = u.perpendicular
        let d = p - center
        return atan2(d.dot(v) / b, d.dot(u) / a)
    }

    var startPoint: CGPoint { return point(at: startParam) }
    var endPoint: CGPoint { return point(at: startParam + sweep) }

    var area: CGFloat { return .pi * majorRadius * minorRadius }

    var infoText: String {
        var text = String(format: "%@\n%@\n\nCenter:   %.3f, %.3f\nMajor r.: %.3f\nMinor r.: %.3f\nRotation: %@",
                          typeName, commonInfo, center.x, center.y, majorRadius, minorRadius,
                          AngleStyle.text(Geometry.normalizeAngle(rotation) * 180 / .pi, .direction))
        if isFull {
            text += String(format: "\nArea:     %.3f\nCircumf.: %.3f", area, curveLength)
        } else {
            text += String(format: "\nStart:    %@\nEnd:      %@\nLength:   %.3f",
                           AngleStyle.text(startParam * 180 / .pi), AngleStyle.text(endParam * 180 / .pi), curveLength)
        }
        return text
    }

    /// A dense approximation of the curve: points, their parameters and the length from the start.
    private var samples: (points: [CGPoint], params: [CGFloat], lengths: [CGFloat]) {
        if let cache = cache { return cache }
        let count = max(8, Int((CGFloat(Ellipse.fullSegments) * sweep / (2 * .pi)).rounded(.up)))
        var points: [CGPoint] = []
        var params: [CGFloat] = []
        var lengths: [CGFloat] = []
        var total: CGFloat = 0
        for i in 0...count {
            let t = startParam + sweep * CGFloat(i) / CGFloat(count)
            let p = point(at: t)
            if let last = points.last { total += Geometry.distance(last, p) }
            points.append(p)
            params.append(t)
            lengths.append(total)
        }
        let result = (points, params, lengths)
        cache = result
        return result
    }

    /// Approximation points (for export and offset).
    var flattened: [CGPoint] { return samples.points }

    /// From unit circle coordinates to the world.
    private var unitTransform: CGAffineTransform {
        let a = max(majorRadius, 1e-12)
        return CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: rotation)
            .scaledBy(x: a, y: a * ratio)
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        guard majorRadius > 0 else { return path }
        let t = unitTransform
        if isFull {
            path.addEllipse(in: CGRect(x: -1, y: -1, width: 2, height: 2), transform: t)
        } else {
            path.addArc(center: .zero, radius: 1, startAngle: startParam, endAngle: startParam + sweep,
                        clockwise: false, transform: t)
        }
        return path
    }

    func boundingBox() -> CGRect {
        let box = makePath().boundingBoxOfPath
        if !box.isNull { return box }
        return CGRect(origin: center, size: .zero)
    }

    func distance(to point: CGPoint) -> CGFloat {
        return distanceToPrimitives(point)
    }

    /// Is the parameter on the arc?
    func contains(param t: CGFloat) -> Bool {
        return isFull || Geometry.ccwDelta(from: startParam, to: t) <= sweep + 1e-9
    }

    func snapPoints() -> [SnapPoint] {
        var points = [SnapPoint(point: center, type: .center)]
        for i in 0..<4 {
            let t = CGFloat(i) * .pi / 2
            if contains(param: t) { points.append(SnapPoint(point: point(at: t), type: .quadrant)) }
        }
        if !isFull {
            points.append(SnapPoint(point: startPoint, type: .endpoint))
            points.append(SnapPoint(point: endPoint, type: .endpoint))
            points.append(SnapPoint(point: point(at: startParam + sweep / 2), type: .midpoint))
        }
        return points
    }

    func applyTransform(_ transform: CGAffineTransform) {
        let linear = CGAffineTransform(a: transform.a, b: transform.b, c: transform.c, d: transform.d, tx: 0, ty: 0)
        let newMajor = majorAxis.applying(linear)
        let newMinor = minorAxis.applying(linear)
        center = center.applying(transform)
        majorAxis = newMajor
        if newMajor.length > 0 { ratio = newMinor.length / newMajor.length }
        if Geometry.isMirroring(transform) && !isFull {
            // mirroring reverses the parameter direction
            let s = startParam, e = endParam
            startParam = -e
            endParam = -s
        }
        normalize()
    }

    func clone() -> CADEntity {
        return copyStyle(to: Ellipse(center: center, majorAxis: majorAxis, ratio: ratio, startParam: startParam,
                                     endParam: endParam, layer: layer, color: color))
    }

    func primitives() -> [Primitive] {
        let s = samples
        guard s.points.count >= 2 else { return [] }
        return (0..<(s.points.count - 1)).map { .segment(a: s.points[$0], b: s.points[$0 + 1], param: s.lengths[$0]) }
    }

    var isClosedCurve: Bool { return isFull }
    var curveLength: CGFloat { return samples.lengths.last ?? 0 }

    /// Ellipse parameter at a given length from the start (for a full ellipse also past the start).
    private func param(atLength length: CGFloat) -> CGFloat {
        let s = samples
        let total = s.lengths.last ?? 0
        guard total > 0 else { return startParam }
        var l = length, laps: CGFloat = 0
        if isFull {
            while l > total { l -= total; laps += 1 }
        }
        l = max(0, min(l, total))
        var low = 0, high = s.lengths.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if s.lengths[mid] < l { low = mid } else { high = mid }
        }
        let span = s.lengths[high] - s.lengths[low]
        let f = span > 0 ? (l - s.lengths[low]) / span : 0
        return s.params[low] + (s.params[high] - s.params[low]) * f + laps * 2 * .pi
    }

    func subCurve(from: CGFloat, to: CGFloat) -> CADEntity? {
        guard to - from > Geometry.epsilon else { return nil }
        let a = param(atLength: from), b = param(atLength: to)
        guard b - a > 1e-9, b - a < 2 * .pi - 1e-9 else { return nil }
        let piece = Ellipse(center: center, majorAxis: majorAxis, ratio: ratio, startParam: a, endParam: b,
                            layer: layer, color: color)
        return piece
    }
}

// MARK: - Dimensions

enum DimensionKind: String {
    case linear = "Linear"
    case aligned = "Aligned"
    case angular = "Angular"
    case radius = "Radius"
    case diameter = "Diameter"
    case leader = "Leader"
}

enum TextAlignment {
    case left, center, right
}

/// Dimension line terminator.
enum DimArrowStyle: String, CaseIterable {
    case arrow, open, oblique, architectural, dot, none

    var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .open: return "Open Arrow"
        case .oblique: return "Oblique Tick"
        case .architectural: return "Architectural Tick"
        case .dot: return "Dot"
        case .none: return "None"
        }
    }

    var detail: String {
        switch self {
        case .arrow: return "Filled arrowhead (engineering drawings)"
        case .open: return "Two short lines – an open arrowhead"
        case .oblique: return "Thin slash at 45° – usual in architecture"
        case .architectural: return "Heavy slash at 45°"
        case .dot: return "Filled dot"
        case .none: return "Just the line"
        }
    }

    /// Oblique tick (the dimension line then slightly overshoots the extension lines).
    var isTick: Bool { return self == .oblique || self == .architectural }
}

/// A dimension. Meaning of the points:
/// - linear/aligned: [point1, point2, dimension line position]
/// - angular: [vertex, point on the 1st arm, point on the 2nd arm, arc position]
/// - radius/diameter: [center, text position] + `radius`
/// - leader: [arrow tip, bend(s)…] + `text`
final class DimensionEntity: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?
    let kind: DimensionKind
    var points: [CGPoint]
    var radius: CGFloat
    var text: String
    var textHeight: CGFloat
    var arrowSize: CGFloat
    var precision: Int = 2
    /// Text below the dimension line (Czech convention – e.g. for windows the height below the width).
    var belowText: String = ""
    /// Associative dimension: dimension point index → the grip of the object the point is attached to.
    var links: [Int: DimensionLink] = [:]
    /// Dimension line terminator (arrow, oblique tick, dot…).
    var arrowStyle: DimArrowStyle = .arrow
    /// A linear dimension with a fixed measuring direction (radians, e.g. from a chained dimension or from DXF); nil = horizontal / vertical by position.
    var fixedAngle: CGFloat?

    init(kind: DimensionKind, points: [CGPoint], radius: CGFloat = 0, text: String = "",
         textHeight: CGFloat, layer: String = "0", color: NSColor? = nil) {
        self.kind = kind
        self.points = points
        self.radius = radius
        self.text = text
        self.textHeight = textHeight
        self.arrowSize = textHeight
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Dimension" }

    // MARK: Measurement

    /// For a linear dimension: horizontal if the line position is farther away vertically.
    private var linearDirection: CGPoint {
        if kind == .linear, let angle = fixedAngle, angle.isFinite { return CGPoint(x: cos(angle), y: sin(angle)) }
        guard points.count >= 3 else { return CGPoint(x: 1, y: 0) }
        if kind == .aligned {
            let d = (points[1] - points[0]).normalized
            return d == .zero ? CGPoint(x: 1, y: 0) : d
        }
        let mid = Geometry.midpoint(points[0], points[1])
        let place = points[2]
        let box = CGRect(x: min(points[0].x, points[1].x), y: min(points[0].y, points[1].y),
                         width: abs(points[1].x - points[0].x), height: abs(points[1].y - points[0].y))
        // outside the X range → vertical dimension, outside the Y range → horizontal
        if place.x < box.minX || place.x > box.maxX {
            if place.y >= box.minY && place.y <= box.maxY { return CGPoint(x: 0, y: 1) }
        }
        return abs(place.y - mid.y) >= abs(place.x - mid.x) ? CGPoint(x: 1, y: 0) : CGPoint(x: 0, y: 1)
    }

    /// The direction in which a linear / aligned dimension measures (for a chained dimension).
    var measureDirection: CGPoint { return linearDirection }

    /// Angular dimension: (start angle, sweep) of the arc that contains the position point.
    private var angularSpan: (start: CGFloat, sweep: CGFloat)? {
        guard points.count >= 4 else { return nil }
        let v = points[0]
        let a1 = Geometry.angle(from: v, to: points[1])
        let a2 = Geometry.angle(from: v, to: points[2])
        let ap = Geometry.angle(from: v, to: points[3])
        let sweep12 = Geometry.ccwDelta(from: a1, to: a2)
        if Geometry.ccwDelta(from: a1, to: ap) <= sweep12 {
            return (a1, sweep12)
        }
        return (a2, 2 * .pi - sweep12)
    }

    var measurement: CGFloat {
        switch kind {
        case .linear, .aligned:
            guard points.count >= 2 else { return 0 }
            return abs((points[1] - points[0]).dot(linearDirection))
        case .angular:
            return (angularSpan?.sweep ?? 0) * 180 / .pi
        case .radius:
            return radius
        case .diameter:
            return radius * 2
        case .leader:
            return 0
        }
    }

    /// Measured value with a prefix (R, Ø) or the angle unit; in feet and inches 12'-6 1/2" (2 decimals = 1/16").
    var measuredText: String {
        let value = LengthStyle.feetInches(measurement, precision: precision + 2)
            ?? String(format: "%.\(precision)f", Double(measurement))
        switch kind {
        case .linear, .aligned: return value
        case .angular: return AngleStyle.dimensionText(measurement, precision: precision)
        case .radius: return "R" + value
        case .diameter: return "Ø" + value
        case .leader: return text
        }
    }

    /// Text above the line: custom text (<> = measured value), otherwise the measured value.
    var displayText: String {
        guard kind != .leader, !text.isEmpty else { return measuredText }
        return text.contains("<>") ? text.replacingOccurrences(of: "<>", with: measuredText) : text
    }

    var infoText: String {
        var info = "Dimension (\(kind.rawValue))\n\(commonInfo)\n\n"
        if kind == .leader {
            info += "Text: \(text)"
        } else {
            info += "Value: \(measuredText)"
            if displayText != measuredText { info += "\nShown: \(displayText)" }
            if !belowText.isEmpty { info += "\nBelow: \(belowText)" }
        }
        info += links.isEmpty ? "\nNot associative" : "\nAssociative (follows \(links.count) point\(links.count == 1 ? "" : "s"))"
        info += String(format: "\nText height: %.3f", textHeight)
        return info
    }

    // MARK: Dimension geometry

    struct Parts {
        var lines: [(CGPoint, CGPoint)] = []
        var arcs: [(center: CGPoint, radius: CGFloat, start: CGFloat, sweep: CGFloat)] = []
        var arrows: [(tip: CGPoint, direction: CGPoint)] = []
        var textAnchor: CGPoint = .zero
        var textAngle: CGFloat = 0
        var textAlignment: TextAlignment = .center
        var textAbove = true
    }

    /// Text angle rotated so that the text is not upside down.
    private static func readableAngle(_ angle: CGFloat) -> CGFloat {
        let a = Geometry.normalizeAngle(angle)
        return (a > .pi / 2 + 1e-6 && a <= 3 * .pi / 2 + 1e-6) ? a - .pi : a
    }

    func buildParts() -> Parts {
        var parts = Parts()
        let gap = textHeight * 0.4
        let overshoot = textHeight * 0.6

        switch kind {
        case .linear, .aligned:
            guard points.count >= 3 else { return parts }
            let d = linearDirection
            let place = points[2]
            let q1 = place + d * (points[0] - place).dot(d)
            let q2 = place + d * (points[1] - place).dot(d)
            // extension lines
            for (p, q) in [(points[0], q1), (points[1], q2)] {
                let e = (q - p).normalized
                if e != .zero && Geometry.distance(p, q) > gap {
                    parts.lines.append((p + e * gap, q + e * overshoot))
                }
            }
            // with oblique ticks / dots the dimension line slightly overshoots the extension lines
            let reach = (q2 - q1).normalized * (arrowStyle == .arrow || arrowStyle == .open ? 0 : arrowSize * 0.75)
            parts.lines.append((q1 - reach, q2 + reach))
            let u = (q2 - q1).normalized
            if u != .zero {
                parts.arrows.append((q1, u * -1))
                parts.arrows.append((q2, u))
            }
            parts.textAngle = DimensionEntity.readableAngle(atan2(d.y, d.x))
            parts.textAnchor = Geometry.midpoint(q1, q2)

        case .angular:
            guard let span = angularSpan else { return parts }
            let v = points[0]
            let r = max(Geometry.distance(v, points[3]), textHeight)
            parts.arcs.append((v, r, span.start, span.sweep))
            for (index, angle) in [span.start, span.start + span.sweep].enumerated() {
                let arcPoint = Geometry.pointOnCircle(v, r, angle)
                let defining = points[index == 0 ? 1 : 2]
                // an extension line only when the arc is farther than the given point
                let definingDistance = Geometry.distance(v, defining)
                if r > definingDistance + gap {
                    let e = (arcPoint - v).normalized
                    parts.lines.append((v + e * (definingDistance + gap), arcPoint + e * overshoot))
                }
                let tangentDirection = CGPoint(x: -sin(angle), y: cos(angle))
                parts.arrows.append((arcPoint, index == 0 ? tangentDirection * -1 : tangentDirection))
            }
            let midAngle = span.start + span.sweep / 2
            parts.textAnchor = Geometry.pointOnCircle(v, r, midAngle)
            parts.textAngle = DimensionEntity.readableAngle(midAngle - .pi / 2)
            if Geometry.normalizeAngle(midAngle) > .pi { parts.textAbove = false }

        case .radius, .diameter:
            guard points.count >= 2, radius > 0 else { return parts }
            let c = points[0]
            var u = (points[1] - c).normalized
            if u == .zero { u = CGPoint(x: 1, y: 0) }
            let onCircle = c + u * radius
            let outer = Geometry.distance(c, points[1]) > radius ? points[1] : onCircle
            let inner = kind == .diameter ? c - u * radius : c
            parts.lines.append((inner, outer))
            parts.arrows.append((onCircle, u))
            if kind == .diameter { parts.arrows.append((inner, u * -1)) }
            parts.textAngle = DimensionEntity.readableAngle(atan2(u.y, u.x))
            parts.textAnchor = Geometry.midpoint(onCircle, outer == onCircle ? inner : outer)

        case .leader:
            guard points.count >= 2 else { return parts }
            for i in 0..<(points.count - 1) { parts.lines.append((points[i], points[i + 1])) }
            parts.arrows.append((points[0], (points[0] - points[1]).normalized))
            let last = points[points.count - 1]
            let goesRight = last.x >= points[points.count - 2].x
            parts.textAnchor = last + CGPoint(x: goesRight ? gap : -gap, y: 0)
            parts.textAlignment = goesRight ? .left : .right
            parts.textAbove = false
        }
        return parts
    }

    /// Arrow triangle (tip, two back corners).
    func arrowPolygon(_ tip: CGPoint, _ direction: CGPoint) -> [CGPoint] {
        let back = tip - direction * arrowSize
        let side = direction.perpendicular * (arrowSize * 0.3)
        return [tip, back + side, back - side]
    }

    /// The terminator that is actually drawn (a leader always has an arrow, a dot or nothing).
    var effectiveArrowStyle: DimArrowStyle {
        if kind == .leader && (arrowStyle.isTick) { return .arrow }
        return arrowStyle
    }

    /// The line part of a terminator (open arrow, oblique ticks).
    func terminatorLines(_ tip: CGPoint, _ direction: CGPoint) -> [(CGPoint, CGPoint)] {
        switch effectiveArrowStyle {
        case .open:
            let corners = arrowPolygon(tip, direction)
            return [(corners[1], tip), (tip, corners[2])]
        case .oblique, .architectural:
            // tick at 45° to the line, width and height = terminator size
            let w = (direction + direction.perpendicular) * (arrowSize * 0.5)
            return [(tip - w, tip + w)]
        default:
            return []
        }
    }

    /// The filled part of a terminator (arrow, dot).
    func terminatorFill(_ tip: CGPoint, _ direction: CGPoint) -> CGPath? {
        switch effectiveArrowStyle {
        case .arrow:
            let path = CGMutablePath()
            path.addLines(between: arrowPolygon(tip, direction))
            path.closeSubpath()
            return path
        case .dot:
            let r = arrowSize * 0.25
            return CGPath(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: 2 * r, height: 2 * r), transform: nil)
        default:
            return nil
        }
    }

    func makePath() -> CGPath {
        let parts = buildParts()
        let path = CGMutablePath()
        for (a, b) in parts.lines {
            path.move(to: a)
            path.addLine(to: b)
        }
        for arc in parts.arcs {
            path.move(to: Geometry.pointOnCircle(arc.center, arc.radius, arc.start))
            path.addArc(center: arc.center, radius: arc.radius, startAngle: arc.start,
                        endAngle: arc.start + arc.sweep, clockwise: false)
        }
        for arrow in parts.arrows {
            for (a, b) in terminatorLines(arrow.tip, arrow.direction) {
                path.move(to: a)
                path.addLine(to: b)
            }
            if let fill = terminatorFill(arrow.tip, arrow.direction) { path.addPath(fill) }
        }
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        let parts = buildParts()
        var plain = style
        plain.dash = []
        // lines and arcs (without terminators)
        let body = CGMutablePath()
        for (a, b) in parts.lines {
            body.move(to: a)
            body.addLine(to: b)
        }
        for arc in parts.arcs {
            body.move(to: Geometry.pointOnCircle(arc.center, arc.radius, arc.start))
            body.addArc(center: arc.center, radius: arc.radius, startAngle: arc.start,
                        endAngle: arc.start + arc.sweep, clockwise: false)
        }
        strokeWorldPath(body, in: context, transform: transform, style: plain)

        // terminators: ticks (the architectural one heavier) and filled arrows / dots
        let ticks = CGMutablePath()
        let fills = CGMutablePath()
        for arrow in parts.arrows {
            for (a, b) in terminatorLines(arrow.tip, arrow.direction) {
                ticks.move(to: a)
                ticks.addLine(to: b)
            }
            if let fill = terminatorFill(arrow.tip, arrow.direction) { fills.addPath(fill) }
        }
        if !ticks.isEmpty {
            var tickStyle = plain
            if effectiveArrowStyle == .architectural { tickStyle.lineWidth = max(2.5, plain.lineWidth * 2.5) }
            strokeWorldPath(ticks, in: context, transform: transform, style: tickStyle)
        }
        var t = transform
        if !fills.isEmpty, let p = fills.copy(using: &t), DrawingSafety.isDrawable(p.boundingBoxOfPath) {
            context.saveGState()
            context.setFillColor(style.color.cgColor)
            context.addPath(p)
            context.fillPath()
            context.restoreGState()
        }

        TextRenderer.draw(displayText, at: parts.textAnchor, angle: parts.textAngle,
                          height: textHeight, alignment: parts.textAlignment, above: parts.textAbove,
                          gap: textHeight * 0.25, color: style.color, in: context, transform: transform)
        if !belowText.isEmpty && kind != .leader {
            TextRenderer.draw(belowText, at: parts.textAnchor, angle: parts.textAngle,
                              height: textHeight, alignment: parts.textAlignment, above: false,
                              gap: textHeight * 0.25, color: style.color, in: context, transform: transform, below: true)
        }
    }

    func boundingBox() -> CGRect {
        var rect = makePath().boundingBoxOfPath
        let parts = buildParts()
        let approxWidth = CGFloat(max(displayText.count, belowText.count)) * textHeight * 0.9
        let r = max(approxWidth, textHeight * 1.5)
        rect = rect.union(CGRect(x: parts.textAnchor.x - r, y: parts.textAnchor.y - r, width: 2 * r, height: 2 * r))
        return rect
    }

    func distance(to point: CGPoint) -> CGFloat {
        let parts = buildParts()
        var best = CGFloat.infinity
        for (a, b) in parts.lines { best = min(best, Geometry.distance(from: point, toSegmentFrom: a, to: b)) }
        for arc in parts.arcs {
            best = min(best, Geometry.distance(from: point, toArcCenter: arc.center, radius: arc.radius,
                                               start: arc.start, sweep: arc.sweep))
        }
        best = min(best, Geometry.distance(point, parts.textAnchor) - textHeight * 0.5)
        return max(best, 0)
    }

    func snapPoints() -> [SnapPoint] { return [] }

    func applyTransform(_ transform: CGAffineTransform) {
        points = points.map { $0.applying(transform) }
        if let angle = fixedAngle {
            // the fixed measuring direction rotates with the dimension
            let d = CGPoint(x: cos(angle), y: sin(angle))
            let moved = CGPoint(x: transform.a * d.x + transform.c * d.y, y: transform.b * d.x + transform.d * d.y)
            if moved.length > 0 { fixedAngle = atan2(moved.y, moved.x) }
        }
        let scale = Geometry.uniformScale(of: transform)
        radius *= scale
        textHeight *= scale
        arrowSize *= scale
    }

    func clone() -> CADEntity {
        let copy = DimensionEntity(kind: kind, points: points, radius: radius, text: text,
                             textHeight: textHeight, layer: layer, color: color)
        copy.arrowSize = arrowSize
        copy.precision = precision
        copy.belowText = belowText
        copy.links = links
        copy.arrowStyle = arrowStyle
        copy.fixedAngle = fixedAngle
        return copyStyle(to: copy)
    }

    func primitives() -> [Primitive] { return [] }
}

// MARK: - Associative dimensions

/// Link of a dimension point to an object's grip (grip = index in Grips.grips; −1 = the whole circle / arc: center and radius).
struct DimensionLink: Equatable {
    var entityID: UUID
    var grip: Int
}

/// Dimensions follow the geometry: when an object changes, the dimension points attached to it move with it.
enum Associativity {
    /// The object's grip exactly at point `p` (only snapped points match this way).
    static func link(at p: CGPoint, in entities: [CADEntity]) -> DimensionLink? {
        for entity in entities where !(entity is DimensionEntity) && !(entity is TextEntity) && !(entity is HatchEntity) {
            let box = entity.boundingBox()
            let tolerance = max(box.width, box.height, 1) * 1e-9
            guard box.insetBy(dx: -tolerance, dy: -tolerance).contains(p) else { continue }
            for (index, grip) in Grips.grips(of: entity).enumerated() where Geometry.distance(grip.point, p) <= tolerance {
                return DimensionLink(entityID: entity.id, grip: index)
            }
        }
        return nil
    }

    /// The dimension points that define it (the others are the position of the dimension line / text).
    static func definingPoints(of dimension: DimensionEntity) -> [Int] {
        switch dimension.kind {
        case .linear, .aligned: return [0, 1]
        case .angular: return [0, 1, 2]
        case .radius, .diameter: return [0]
        case .leader: return [0]
        }
    }

    /// A new dimension: attaches the points that lie exactly on object grips (radius/diameter to the measured object).
    static func attach(_ dimension: DimensionEntity, to entities: [CADEntity], measured: CADEntity? = nil) {
        dimension.links = [:]
        if dimension.kind == .radius || dimension.kind == .diameter {
            if let source = measured, source is Circle || source is Arc {
                dimension.links[0] = DimensionLink(entityID: source.id, grip: -1)
            }
            return
        }
        for index in definingPoints(of: dimension) where index < dimension.points.count {
            if let link = link(at: dimension.points[index], in: entities) { dimension.links[index] = link }
        }
    }

    /// The grip point in the new object (nil = the object changed so that the grip no longer matches).
    private static func gripPoint(_ grip: Int, new: CADEntity, old: CADEntity?) -> CGPoint? {
        let grips = Grips.grips(of: new)
        guard grip >= 0, grip < grips.count else { return nil }
        if let old = old, Grips.grips(of: old).count != grips.count { return nil }
        return grips[grip].point
    }

    /// Adds the edited dimensions attached to the changed objects to the change.
    static func update(documentEntities: [CADEntity], removed: [CADEntity], added: [CADEntity])
        -> (removed: [CADEntity], added: [CADEntity]) {
        let removedIDs = Set(removed.map { $0.id })
        var removedByID: [UUID: CADEntity] = [:]
        for entity in removed { removedByID[entity.id] = entity }

        // original object → new one (same order and type; otherwise the only new object of the same type)
        var replacement: [UUID: CADEntity] = [:]
        let oldGeometry = removed.filter { !($0 is DimensionEntity) }
        let newGeometry = added.filter { !($0 is DimensionEntity) }
        if oldGeometry.count == newGeometry.count {
            for (old, new) in zip(oldGeometry, newGeometry) where type(of: old) == type(of: new) { replacement[old.id] = new }
        } else {
            for old in oldGeometry {
                let same = newGeometry.filter { type(of: $0) == type(of: old) }
                if same.count == 1 { replacement[old.id] = same[0] }
            }
        }

        // drawing state after the change (for checking the links)
        var finalByID: [UUID: CADEntity] = [:]
        for entity in documentEntities where !removedIDs.contains(entity.id) { finalByID[entity.id] = entity }
        for entity in added { finalByID[entity.id] = entity }

        /// Updates the points and links of dimension `copy`; true = something changed.
        func refresh(_ copy: DimensionEntity) -> Bool {
            var changed = false
            var deltas: [CGPoint] = []
            for (index, link) in copy.links.sorted(by: { $0.key < $1.key }) {
                guard index < copy.points.count else {
                    copy.links[index] = nil
                    changed = true
                    continue
                }
                let old = copy.points[index]
                if removedIDs.contains(link.entityID) {
                    if let target = replacement[link.entityID] {
                        if link.grip == -1 {
                            // radius / diameter: center and radius of the measured object
                            let circle: (center: CGPoint, radius: CGFloat)?
                            if let c = target as? Circle { circle = (c.center, c.radius) }
                            else if let a = target as? Arc { circle = (a.center, a.radius) }
                            else { circle = nil }
                            if let circle = circle {
                                let delta = circle.center - old
                                copy.points[index] = circle.center
                                if copy.points.count > 1 { copy.points[1] = copy.points[1] + delta }
                                copy.radius = circle.radius
                                copy.links[index] = DimensionLink(entityID: target.id, grip: -1)
                                changed = true
                                continue
                            }
                        } else if let point = gripPoint(link.grip, new: target, old: removedByID[link.entityID]) {
                            copy.points[index] = point
                            copy.links[index] = DimensionLink(entityID: target.id, grip: link.grip)
                            deltas.append(point - old)
                            changed = true
                            continue
                        }
                    }
                    // the object was exploded / joined: find a new grip at the same place
                    if link.grip >= 0, let relinked = Associativity.link(at: old, in: added) {
                        copy.links[index] = relinked
                    } else {
                        copy.links[index] = nil
                    }
                    changed = true
                } else if let target = finalByID[link.entityID] {
                    // a link to an object that remains: valid only while the point still lies on the grip
                    if link.grip >= 0 {
                        let grips = Grips.grips(of: target)
                        let tolerance = max(target.boundingBox().width, target.boundingBox().height, 1) * 1e-9
                        if link.grip >= grips.count || Geometry.distance(grips[link.grip].point, old) > tolerance {
                            copy.links[index] = nil
                            changed = true
                        }
                    }
                } else {
                    copy.links[index] = nil
                    changed = true
                }
            }
            // if all defining points moved the same way, the dimension line moves too
            let defining = definingPoints(of: copy)
            if copy.kind != .radius, copy.kind != .diameter, copy.kind != .leader, !deltas.isEmpty, deltas.count == defining.count,
               let first = deltas.first, deltas.allSatisfy({ Geometry.distance($0, first) < max(first.length, 1) * 1e-9 }) {
                for index in copy.points.indices where !defining.contains(index) {
                    copy.points[index] = copy.points[index] + first
                }
            }
            return changed
        }

        var extraRemoved: [CADEntity] = []
        var extraAdded: [CADEntity] = []
        // dimensions that are part of the change (e.g. moved together with the geometry): just reconnect the links
        for case let dimension as DimensionEntity in added where !dimension.links.isEmpty {
            var relinked: [Int: DimensionLink] = [:]
            for (index, link) in dimension.links {
                if let target = replacement[link.entityID] {
                    relinked[index] = DimensionLink(entityID: target.id, grip: link.grip)
                } else {
                    relinked[index] = link
                }
            }
            dimension.links = relinked
            // the points already match the moved geometry – check them and drop links that no longer fit
            for (index, link) in dimension.links where link.grip >= 0 {
                guard let target = finalByID[link.entityID], index < dimension.points.count else {
                    dimension.links[index] = nil
                    continue
                }
                let grips = Grips.grips(of: target)
                let tolerance = max(target.boundingBox().width, target.boundingBox().height, 1) * 1e-9
                if link.grip >= grips.count || Geometry.distance(grips[link.grip].point, dimension.points[index]) > tolerance {
                    dimension.links[index] = nil
                }
            }
        }
        guard !removedIDs.isEmpty else { return (removed, added) }
        // dimensions in the drawing that refer to the changed objects
        for case let dimension as DimensionEntity in documentEntities
            where !removedIDs.contains(dimension.id) && dimension.links.values.contains(where: { removedIDs.contains($0.entityID) }) {
            guard let copy = dimension.clone() as? DimensionEntity else { continue }
            if refresh(copy) {
                extraRemoved.append(dimension)
                extraAdded.append(copy)
            }
        }
        return (removed + extraRemoved, added + extraAdded)
    }
}

// MARK: - Text Renderer

enum TextRenderer {
    /// Draws text in world coordinates (text height in world units).
    static func draw(_ string: String, at anchor: CGPoint, angle: CGFloat, height: CGFloat,
                     alignment: TextAlignment, above: Bool, gap: CGFloat, color: NSColor,
                     in context: CGContext, transform: CGAffineTransform, below: Bool = false) {
        guard !string.isEmpty else { return }
        let scale = Geometry.uniformScale(of: transform)
        // text height = cap height (as in CAD)
        let fontSize = height * scale / FontLibrary.capRatio(family: "", face: "Regular")
        guard fontSize >= 3, fontSize < 2000 else { return }

        // laid out at a fixed size and scaled when drawn, so the text follows the zoom exactly
        // (the system font changes its letter spacing with the point size)
        let reference: CGFloat = 100
        let s = fontSize / reference
        let attributed = NSAttributedString(string: string, attributes: [
            .font: NSFont.systemFont(ofSize: reference),
            .foregroundColor: color
        ])
        let size = attributed.size()
        let screenAnchor = anchor.applying(transform)
        guard screenAnchor.x.isFinite, screenAnchor.y.isFinite, angle.isFinite,
              abs(screenAnchor.x) < DrawingSafety.maxCoordinate, abs(screenAnchor.y) < DrawingSafety.maxCoordinate else { return }

        let x: CGFloat
        switch alignment {
        case .left: x = 0
        case .center: x = -size.width / 2
        case .right: x = -size.width
        }
        // above the line / below the line / centered (gap converted to the reference size)
        let g = gap * scale / s
        let y = below ? -g - size.height : (above ? g : -size.height / 2)

        // on-screen angle (for a rotated view the rotation is added to the drawing angle)
        let screenAngle = atan2(transform.b * cos(angle) + transform.d * sin(angle),
                                transform.a * cos(angle) + transform.c * sin(angle))
        context.saveGState()
        context.translateBy(x: screenAnchor.x, y: screenAnchor.y)
        context.rotate(by: screenAngle)
        context.scaleBy(x: s, y: s)
        attributed.draw(at: CGPoint(x: x, y: y))
        context.restoreGState()
    }
}

// MARK: - DXF Colors (color index, ACI)

enum ACIColor {
    static let table: [(index: Int, name: String, color: NSColor)] = [
        (1, "Red", .red), (2, "Yellow", .yellow), (3, "Green", .green), (4, "Cyan", .cyan),
        (5, "Blue", .blue), (6, "Magenta", .magenta), (7, "White", .white), (8, "Gray", .gray)
    ]

    /// The whole DXF color index palette (1–255): 1–9 basic, 10–249 hues in 15° steps at five brightnesses (even full,
    /// odd half saturation), 250–255 grays. A negative number = layer turned off (same color).
    static func color(for index: Int) -> NSColor {
        let i = abs(index)
        if let named = table.first(where: { $0.index == i }) { return named.color }
        switch i {
        case 9:
            return NSColor(srgbRed: 192 / 255, green: 192 / 255, blue: 192 / 255, alpha: 1)
        case 10...249:
            let hue = CGFloat((i - 10) / 10) * 15 / 360
            let step = (i % 10) / 2
            let values: [CGFloat] = [255, 204, 153, 127, 76]
            let saturation: CGFloat = i % 2 == 0 ? 1 : 0.5
            return NSColor(hue: hue, saturation: saturation, brightness: values[step] / 255, alpha: 1)
        case 250...255:
            let gray: [CGFloat] = [51, 91, 132, 173, 214, 255]
            let v = gray[i - 250] / 255
            return NSColor(srgbRed: v, green: v, blue: v, alpha: 1)
        default:
            return .white
        }
    }

    /// The nearest color number (1–255) – for writing to DXF.
    static func index(for color: NSColor) -> Int {
        guard let c = color.usingColorSpace(.sRGB) else { return 7 }
        var bestIndex = 7
        var bestDistance = CGFloat.infinity
        for index in 1...255 {
            guard let t = self.color(for: index).usingColorSpace(.sRGB) else { continue }
            let d = pow(c.redComponent - t.redComponent, 2)
                + pow(c.greenComponent - t.greenComponent, 2)
                + pow(c.blueComponent - t.blueComponent, 2)
            if d < bestDistance {
                bestDistance = d
                bestIndex = index
            }
            if d == 0 { break }
        }
        return bestIndex
    }

    static func name(for color: NSColor) -> String {
        let index = self.index(for: color)
        return table.first(where: { $0.index == index })?.name ?? "Color \(index)"
    }
}

// MARK: - Drawing Safety

/// Drawing safeguards – Core Graphics can crash the app on invalid or huge shapes.
enum DrawingSafety {
    static let maxCoordinate: CGFloat = 1e7
    static let maxDashedSize: CGFloat = 20_000

    static func isDrawable(_ box: CGRect) -> Bool {
        guard !box.isNull, box.minX.isFinite, box.minY.isFinite, box.maxX.isFinite, box.maxY.isFinite else { return false }
        return abs(box.minX) < maxCoordinate && abs(box.maxX) < maxCoordinate
            && abs(box.minY) < maxCoordinate && abs(box.maxY) < maxCoordinate
    }

    static func canDash(_ box: CGRect) -> Bool {
        return box.width < maxDashedSize && box.height < maxDashedSize
    }

    static func isFinite(_ p: CGPoint) -> Bool {
        return p.x.isFinite && p.y.isFinite && abs(p.x) < maxCoordinate && abs(p.y) < maxCoordinate
    }

    /// The largest coordinate a drawing can hold. `maxCoordinate` is a limit for the screen only – drawing coordinates
    /// are much larger in S-JTSK kept in mm or cm (about −1.3e9 mm), so they are checked against this one.
    static let maxWorldCoordinate: CGFloat = 1e13

    /// Valid bounds of an object in the drawing: finite numbers within `maxWorldCoordinate`.
    static func isValidWorld(_ box: CGRect) -> Bool {
        guard !box.isNull, box.minX.isFinite, box.minY.isFinite, box.maxX.isFinite, box.maxY.isFinite else { return false }
        return abs(box.minX) < maxWorldCoordinate && abs(box.maxX) < maxWorldCoordinate
            && abs(box.minY) < maxWorldCoordinate && abs(box.maxY) < maxWorldCoordinate
    }
}
