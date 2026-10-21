//
//  Operations.swift
//  OhMyCAD
//
//  Editing operations: Trim, PowerTrim, Extend, Fillet and Chamfer.
//  They work for lines, circles, arcs, polylines and splines.
//

import Cocoa

struct EditError: LocalizedError {
    let message: String
    var errorDescription: String? { return message }
}

enum EditOperations {

    // MARK: Intersections

    /// Parameters (length from the start) of the curve's intersections with the edges – sorted and without duplicates.
    static func cutParameters(of curve: CurveEntity, edges: [CADEntity]) -> [CGFloat] {
        let own = curve.primitives()
        // bounding boxes skip pairs that cannot meet (dense polylines have thousands of segments)
        let ownBoxes = own.map { $0.bounds }
        let curveBox = ownBoxes.reduce(CGRect.null) { $0.union($1) }
        var params: [CGFloat] = []
        for edge in edges where edge !== curve && mayMeet(edge.boundingBox(), curveBox) {
            for b in edge.primitives() {
                let box = b.bounds
                for (a, aBox) in zip(own, ownBoxes) where mayMeet(aBox, box) {
                    params.append(contentsOf: a.intersections(with: b).map { $0.param })
                }
            }
        }
        // a polyline or spline that crosses itself is cut there too (neighbouring segments only share a vertex)
        let count = own.count
        for i in 0..<count {
            for j in (i + 2)..<max(count, i + 2) where !(curve.isClosedCurve && i == 0 && j == count - 1) {
                guard mayMeet(ownBoxes[i], ownBoxes[j]) else { continue }
                params.append(contentsOf: own[i].intersections(with: own[j]).map { $0.param })
                params.append(contentsOf: own[j].intersections(with: own[i]).map { $0.param })
            }
        }
        params.sort()
        let tolerance = max(curve.curveLength, 1) * 1e-9
        var unique: [CGFloat] = []
        for p in params where unique.last.map({ p - $0 > tolerance }) ?? true {
            unique.append(p)
        }
        return unique
    }

    /// Can two objects with these bounding boxes touch? Boxes that are not finite (construction lines) always can.
    static func mayMeet(_ a: CGRect, _ b: CGRect) -> Bool {
        guard DrawingSafety.isDrawable(a), DrawingSafety.isDrawable(b) else { return true }
        let margin = max(a.width, a.height, b.width, b.height, 1) * 1e-9
        // compared by hand: CGRect.intersects is false for a flat box (a horizontal or vertical segment)
        return a.minX <= b.maxX + margin && b.minX <= a.maxX + margin && a.minY <= b.maxY + margin && b.minY <= a.maxY + margin
    }

    // MARK: Trim

    /// Removes the piece of the curve between adjacent intersections that the user clicked.
    /// Returns the remaining pieces, or nil if nothing intersects the curve.
    static func trim(_ curve: CurveEntity, at click: CGPoint, edges: [CADEntity]) -> [CADEntity]? {
        return trimDetail(curve, at: click, edges: edges)?.kept
    }

    /// Like `trim`, but also returns the piece being removed (for the preview under the cursor).
    /// `extraCuts` are additional cut parameters (PowerTrim passes the polyline's own vertices).
    static func trimDetail(_ curve: CurveEntity, at click: CGPoint, edges: [CADEntity],
                           extraCuts: [CGFloat] = []) -> (kept: [CADEntity], removed: CADEntity?)? {
        guard let result = trimDetailRaw(curve, at: click, edges: edges, extraCuts: extraCuts) else { return nil }
        // the pieces keep the lineweight of the original object
        for piece in result.kept { piece.lineWeight = curve.lineWeight; piece.lineTypeScale = curve.lineTypeScale }
        result.removed?.lineWeight = curve.lineWeight
        result.removed?.lineTypeScale = curve.lineTypeScale
        return result
    }

    private static func trimDetailRaw(_ curve: CurveEntity, at click: CGPoint, edges: [CADEntity],
                                      extraCuts: [CGFloat]) -> (kept: [CADEntity], removed: CADEntity?)? {
        let length = curve.curveLength
        guard length > 0 else { return nil }
        let tolerance = length * 1e-9 + 1e-12
        let clickParam = curve.parameter(of: click)
        var cuts = cutParameters(of: curve, edges: edges)
        if !extraCuts.isEmpty {
            var unique: [CGFloat] = []
            for c in (cuts + extraCuts).sorted() where unique.last.map({ c - $0 > tolerance }) ?? true { unique.append(c) }
            cuts = unique
        }

        if curve.isClosedCurve {
            // parameter L is the same as 0
            cuts = cuts.map { $0 >= length - tolerance ? 0 : max($0, 0) }.sorted()
            var unique: [CGFloat] = []
            for c in cuts where unique.last.map({ c - $0 > tolerance }) ?? true { unique.append(c) }
            cuts = unique
            guard cuts.count >= 2 else { return nil }

            // the default is the interval across the start of the curve
            var low = cuts[cuts.count - 1]
            var high = cuts[0] + length
            for i in 0..<(cuts.count - 1) where clickParam >= cuts[i] && clickParam <= cuts[i + 1] {
                low = cuts[i]
                high = cuts[i + 1]
                break
            }
            let removed = curve.subCurve(from: low, to: high)
            // the rest: from the end of the deleted piece around to its start
            var from = high
            var to = low + length
            if from >= length - tolerance {
                from -= length
                to -= length
            }
            return ([curve.subCurve(from: from, to: to)].compactMap { $0 }, removed)
        }

        cuts = cuts.filter { $0 > tolerance && $0 < length - tolerance }
        guard !cuts.isEmpty else { return nil }
        let bounds: [CGFloat] = [0] + cuts + [length]
        var index = bounds.count - 2
        for i in 0..<(bounds.count - 1) where clickParam <= bounds[i + 1] {
            index = i
            break
        }
        var pieces: [CADEntity] = []
        if index > 0, let piece = curve.subCurve(from: 0, to: bounds[index]) {
            pieces.append(piece)
        }
        if index + 1 < bounds.count - 1, let piece = curve.subCurve(from: bounds[index + 1], to: length) {
            pieces.append(piece)
        }
        return (pieces, curve.subCurve(from: bounds[index], to: bounds[index + 1]))
    }

    /// PowerTrim: trims the entity successively at every point where the dragged line crossed it.
    static func trim(_ entity: CADEntity, atPoints points: [CGPoint], edges: [CADEntity],
                     tolerance: CGFloat) -> [CADEntity]? {
        var pieces: [CADEntity] = [entity]
        var changed = false
        // the original object is not an edge for its own pieces (it lies right on them);
        // its other pieces are, so a curve crossing itself still cuts there
        let others = edges.filter { $0 !== entity }
        for point in points {
            guard let index = pieces.firstIndex(where: { $0.distance(to: point) <= tolerance }) else { continue }
            let piece = pieces[index]
            guard let result = powerTrimAny(piece, at: point, edges: others + pieces.filter { $0 !== piece })?.kept else { continue }
            pieces.replaceSubrange(index...index, with: result)
            changed = true
        }
        return changed ? pieces : nil
    }

    // MARK: Trimming construction lines

    /// Can the object be trimmed? (curves and construction lines / rays)
    static func isTrimmable(_ entity: CADEntity) -> Bool {
        return entity is CurveEntity || entity is ConstructionLine
    }

    /// Trim for curves and construction lines: the remaining pieces and the removed piece (for the preview). nil = nothing intersects.
    static func trimAny(_ entity: CADEntity, at click: CGPoint,
                        edges: [CADEntity]) -> (kept: [CADEntity], removed: CADEntity?)? {
        if let xline = entity as? ConstructionLine { return trimConstruction(xline, at: click, edges: edges) }
        if let curve = entity as? CurveEntity { return trimDetail(curve, at: click, edges: edges) }
        return nil
    }

    /// PowerTrim for one click: a polyline is also cut at its corners (one side of a U can be removed,
    /// leaving an L), and an object that crosses nothing is removed whole.
    static func powerTrimAny(_ entity: CADEntity, at click: CGPoint,
                             edges: [CADEntity]) -> (kept: [CADEntity], removed: CADEntity?)? {
        if let polyline = entity as? Polyline {
            let pieces = polyline.primitives()
            var corners: [CGFloat] = []
            for i in pieces.indices where i > 0 || polyline.isClosedCurve {
                let previous = pieces[i > 0 ? i - 1 : pieces.count - 1]
                if isCorner(previous, pieces[i]) { corners.append(startParameter(of: pieces[i])) }
            }
            if let result = trimDetail(polyline, at: click, edges: edges, extraCuts: corners) { return result }
        } else if let result = trimAny(entity, at: click, edges: edges) {
            return result
        }
        guard isTrimmable(entity) else { return nil }
        return ([], entity)
    }

    /// A vertex between two straight segments that turns by less than this is not a corner – a trimmed spline
    /// is stored as a dense polyline and must be trimmed as one smooth curve, like an arc.
    private static let smoothTurn: CGFloat = 15 * .pi / 180

    /// Does the polyline turn at the vertex between these two segments? A vertex next to an arc always counts.
    private static func isCorner(_ before: Primitive, _ after: Primitive) -> Bool {
        guard case let .segment(a0, a1, _) = before, case let .segment(b0, b1, _) = after else { return true }
        let u = a1 - a0, v = b1 - b0
        let lengths = hypot(u.x, u.y) * hypot(v.x, v.y)
        guard lengths > 0 else { return true }
        return u.dot(v) / lengths < cos(smoothTurn)
    }

    private static func startParameter(of primitive: Primitive) -> CGFloat {
        switch primitive {
        case let .segment(_, _, p): return p
        case let .arc(_, _, _, _, p): return p
        }
    }

    /// Trimming a construction line (XLINE) or ray (RAY) between the adjacent intersections that were clicked.
    /// A construction line trimmed on one side becomes a ray; when a finite piece remains, it becomes
    /// an ordinary line (and behaves like any other line from then on).
    static func trimConstruction(_ xline: ConstructionLine, at click: CGPoint,
                                 edges: [CADEntity]) -> (kept: [CADEntity], removed: CADEntity?)? {
        let reach = ConstructionLine.reach
        let start = xline.startParameter
        guard let own = xline.primitives().first else { return nil }
        // intersections as a distance from the line's point along the line's direction
        var cuts: [CGFloat] = []
        for edge in edges where edge !== xline {
            for b in edge.primitives() {
                cuts.append(contentsOf: own.intersections(with: b).map { $0.param + start })
            }
        }
        let tolerance: CGFloat = 1e-7 * max(1, abs(start))
        // ray: a cut at its origin divides nothing
        cuts = cuts.filter { $0.isFinite && $0 > start + tolerance && $0 < reach - tolerance }.sorted()
        var unique: [CGFloat] = []
        for c in cuts where unique.last.map({ c - $0 > tolerance }) ?? true { unique.append(c) }
        guard !unique.isEmpty else { return nil }

        let d = xline.direction
        let t = (click - xline.point).dot(d)
        // interval containing the click: lower bound (nil = start of the line), upper bound (nil = infinity)
        let lower = unique.last(where: { $0 < t })
        let upper = unique.first(where: { $0 > t })

        func ray(from parameter: CGFloat, forward: Bool) -> ConstructionLine {
            let piece = ConstructionLine(point: xline.location(at: parameter), angle: forward ? xline.angle : xline.angle + .pi,
                                         isRay: true, layer: xline.layer, color: xline.color)
            piece.lineWeight = xline.lineWeight
            piece.lineTypeScale = xline.lineTypeScale
            piece.drawOrder = xline.drawOrder
            return piece
        }
        func segment(_ from: CGFloat, _ to: CGFloat) -> Line? {
            guard to - from > tolerance else { return nil }
            let line = Line(start: xline.location(at: from), end: xline.location(at: to), layer: xline.layer, color: xline.color)
            line.lineWeight = xline.lineWeight
            line.lineTypeScale = xline.lineTypeScale
            line.drawOrder = xline.drawOrder
            return line
        }

        var kept: [CADEntity] = []
        // what remains before the removed piece
        if let low = lower {
            if xline.isRay {
                if let piece = segment(0, low) { kept.append(piece) }       // from the ray's origin: a line
            } else {
                kept.append(ray(from: low, forward: false))                  // to “−infinity”: a ray
            }
        }
        // what remains after it (always to infinity)
        if let high = upper { kept.append(ray(from: high, forward: true)) }

        // the removed piece (red preview)
        let removed: CADEntity?
        switch (lower, upper) {
        case let (low?, high?):
            removed = segment(low, high)
        case let (low?, nil):
            removed = ray(from: low, forward: true)
        case let (nil, high?):
            removed = xline.isRay ? segment(0, high) : ray(from: high, forward: false)
        case (nil, nil):
            removed = nil
        }
        return (kept, removed)
    }

    // MARK: Break

    /// Break: removes the piece of the curve between points `first` and `second` (the points are projected onto the curve).
    /// For a closed curve, the piece from the first point to the second counterclockwise is removed.
    /// `second` = nil or the same point → split at the point without a gap (Break at Point).
    static func breakCurve(_ curve: CurveEntity, first: CGPoint,
                           second: CGPoint?) throws -> (kept: [CADEntity], removed: CADEntity?) {
        let length = curve.curveLength
        guard length > 0, length.isFinite else { throw EditError(message: "This object has no length to break.") }
        let tolerance = max(length * 1e-9, 1e-9)
        let t1 = min(max(curve.parameter(of: first), 0), length)
        let t2 = second.map { min(max(curve.parameter(of: $0), 0), length) } ?? t1
        var kept: [CADEntity] = []
        var removed: CADEntity?

        if curve.isClosedCurve {
            let gap = abs(t2 - t1)
            if gap <= tolerance || abs(gap - length) <= tolerance {
                // a closed polyline can be “opened” at a point, a circle or ellipse cannot (the whole perimeter would remain)
                guard !(curve is Circle), !(curve is Ellipse),
                      let opened = curve.subCurve(from: t1, to: t1 + length) else {
                    throw EditError(message: "A circle or an ellipse cannot be broken at a single point – use two points (Break).")
                }
                kept = [opened]
            } else {
                // the piece from the first point to the second is removed, the rest from the second around to the first remains
                removed = curve.subCurve(from: t1, to: t2 > t1 ? t2 : t2 + length)
                guard let rest = curve.subCurve(from: t2, to: t1 > t2 ? t1 : t1 + length) else {
                    throw EditError(message: "Nothing would be left of the object – use Delete instead.")
                }
                kept = [rest]
            }
        } else {
            let a = min(t1, t2), b = max(t1, t2)
            if b - a <= tolerance {
                guard a > tolerance, a < length - tolerance else {
                    throw EditError(message: "Click inside the object – at its end there is nothing to split.")
                }
                kept = [curve.subCurve(from: 0, to: a), curve.subCurve(from: a, to: length)].compactMap { $0 }
                guard kept.count == 2 else { throw EditError(message: "The object could not be split there.") }
            } else {
                if a > tolerance, let piece = curve.subCurve(from: 0, to: a) { kept.append(piece) }
                if b < length - tolerance, let piece = curve.subCurve(from: b, to: length) { kept.append(piece) }
                guard !kept.isEmpty else {
                    throw EditError(message: "That would remove the whole object – use Delete instead.")
                }
                removed = curve.subCurve(from: a, to: b)
            }
        }
        // the pieces keep the lineweight of the original object
        for piece in kept { piece.lineWeight = curve.lineWeight; piece.lineTypeScale = curve.lineTypeScale }
        removed?.lineWeight = curve.lineWeight
        removed?.lineTypeScale = curve.lineTypeScale
        return (kept, removed)
    }

    // MARK: Extend

    /// Extends a line, arc or open polyline to the nearest boundary.
    /// The end nearer to the click point is extended.
    static func extend(_ entity: CADEntity, near click: CGPoint, boundaries: [CADEntity]) -> CADEntity? {
        let result = extendRaw(entity, near: click, boundaries: boundaries)
        result?.lineWeight = entity.lineWeight
        result?.lineTypeScale = entity.lineTypeScale
        return result
    }

    private static func extendRaw(_ entity: CADEntity, near click: CGPoint, boundaries: [CADEntity]) -> CADEntity? {
        var edges = boundaries.filter { $0 !== entity }.flatMap { $0.primitives() }
        guard !edges.isEmpty || entity is Polyline else { return nil }

        var extent = entity.boundingBox()
        for edge in boundaries { extent = extent.union(edge.boundingBox()) }
        let reach = (hypot(extent.width, extent.height) + 1) * 4

        /// The nearest intersection of a ray from point `from` in the direction `direction`.
        func rayHit(from: CGPoint, direction: CGPoint) -> CGPoint? {
            let ray = Primitive.segment(a: from, b: from + direction * reach, param: 0)
            let minimum = reach * 1e-10
            let hits = edges.flatMap { ray.intersections(with: $0) }.filter { $0.param > minimum }
            return hits.min(by: { $0.param < $1.param })?.point
        }

        if let line = entity as? Line {
            let extendEnd = Geometry.distance(click, line.endPoint) < Geometry.distance(click, line.startPoint)
            let fixed = extendEnd ? line.startPoint : line.endPoint
            let moving = extendEnd ? line.endPoint : line.startPoint
            let direction = (moving - fixed).normalized
            guard direction != .zero, let hit = rayHit(from: moving, direction: direction) else { return nil }
            return Line(start: extendEnd ? line.startPoint : hit, end: extendEnd ? hit : line.endPoint,
                        layer: line.layer, color: line.color)
        }

        if let polyline = entity as? Polyline, !polyline.closed, polyline.vertices.count >= 2 {
            var vertices = polyline.vertices
            let n = vertices.count
            let extendEnd = Geometry.distance(click, vertices[n - 1]) < Geometry.distance(click, vertices[0])
            let movingIndex = extendEnd ? n - 1 : 0
            let neighbourIndex = extendEnd ? n - 2 : 1
            // an end arc segment is not extended
            guard polyline.bulge(at: extendEnd ? n - 2 : 0) == 0 else { return nil }
            // the polyline's other segments are boundaries too (it can be extended to itself)
            let own = polyline.primitives()
            edges += own.indices.filter { $0 != (extendEnd ? own.count - 1 : 0) }.map { own[$0] }
            let direction = (vertices[movingIndex] - vertices[neighbourIndex]).normalized
            guard direction != .zero, let hit = rayHit(from: vertices[movingIndex], direction: direction) else { return nil }
            vertices[movingIndex] = hit
            return Polyline(vertices: vertices, closed: false, bulges: polyline.bulges, layer: polyline.layer, color: polyline.color)
        }

        if let arc = entity as? Arc {
            let sweep = arc.sweep
            let gap = 2 * .pi - sweep
            guard gap > 1e-9, arc.radius > 0 else { return nil }
            let extendEnd = Geometry.distance(click, arc.endPoint) < Geometry.distance(click, arc.startPoint)
            let minimum = 1e-9 * arc.radius

            if extendEnd {
                let end = arc.startAngle + sweep
                let region = Primitive.arc(center: arc.center, radius: arc.radius, start: end, sweep: gap, param: 0)
                let hits = edges.flatMap { region.intersections(with: $0) }.filter { $0.param > minimum }
                guard let best = hits.min(by: { $0.param < $1.param }) else { return nil }
                return Arc(center: arc.center, radius: arc.radius, startAngle: arc.startAngle,
                           endAngle: end + best.param / arc.radius, layer: arc.layer, color: arc.color)
            } else {
                let regionStart = arc.startAngle - gap
                let region = Primitive.arc(center: arc.center, radius: arc.radius, start: regionStart, sweep: gap, param: 0)
                let regionLength = gap * arc.radius
                let hits = edges.flatMap { region.intersections(with: $0) }.filter { $0.param < regionLength - minimum }
                guard let best = hits.max(by: { $0.param < $1.param }) else { return nil }
                return Arc(center: arc.center, radius: arc.radius,
                           startAngle: regionStart + best.param / arc.radius,
                           endAngle: arc.startAngle + sweep, layer: arc.layer, color: arc.color)
            }
        }

        return nil
    }

    // MARK: Fillet and Chamfer

    /// How the corner between two lines is modified.
    enum CornerShape {
        /// Rounding with an arc (Fillet). Radius 0 = sharp corner.
        case round(radius: CGFloat)
        /// Beveling with a line (Chamfer): distance from the corner on the first and the second line. Both 0 = sharp corner.
        case bevel(first: CGFloat, second: CGFloat)

        var name: String {
            switch self {
            case .round: return "Fillet"
            case .bevel: return "Chamfer"
            }
        }

        /// Sharp corner – the lines are just extended / shortened to the intersection.
        var isSharp: Bool {
            switch self {
            case .round(let radius): return radius <= Geometry.epsilon
            case .bevel(let first, let second): return first <= Geometry.epsilon && second <= Geometry.epsilon
            }
        }
    }

    /// Result of modifying the corner of two lines: the new ends of both lines (in the original orientation, nil = the line disappears)
    /// and the connecting piece – an arc (Fillet) or a line (Chamfer).
    private struct CornerParts {
        var kept1: (start: CGPoint, end: CGPoint)?
        var kept2: (start: CGPoint, end: CGPoint)?
        var arc: (center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat)?
        var bevel: (start: CGPoint, end: CGPoint)?
    }

    /// Corner geometry of two lines (a1→b1, a2→b2). The side of each line that the user clicked is kept.
    private static func cornerParts(_ a1: CGPoint, _ b1: CGPoint, click1: CGPoint,
                                    _ a2: CGPoint, _ b2: CGPoint, click2: CGPoint,
                                    shape: CornerShape) throws -> CornerParts {
        guard let corner = Geometry.lineIntersection(a1, b1, a2, b2) else {
            throw EditError(message: "The lines are parallel.")
        }

        func keptSide(_ s: CGPoint, _ e: CGPoint, _ click: CGPoint) -> (direction: CGPoint, farIsStart: Bool, far: CGPoint)? {
            let t = Geometry.projectionParameter(of: click, ontoSegmentFrom: s, to: e)
            let projected = Geometry.lerp(s, e, t)
            var direction = (projected - corner).normalized
            if direction == .zero {
                let farther = Geometry.distance(s, corner) > Geometry.distance(e, corner) ? s : e
                direction = (farther - corner).normalized
            }
            let startAlong = (s - corner).dot(direction)
            let endAlong = (e - corner).dot(direction)
            let farIsStart = startAlong >= endAlong
            guard max(startAlong, endAlong) > Geometry.epsilon else { return nil }
            return (direction, farIsStart, farIsStart ? s : e)
        }

        guard let side1 = keptSide(a1, b1, click1), let side2 = keptSide(a2, b2, click2) else {
            throw EditError(message: "Could not determine which side of the lines to keep.")
        }

        func kept(_ side: (direction: CGPoint, farIsStart: Bool, far: CGPoint), to point: CGPoint) -> (start: CGPoint, end: CGPoint) {
            return side.farIsStart ? (side.far, point) : (point, side.far)
        }

        if shape.isSharp {
            return CornerParts(kept1: kept(side1, to: corner), kept2: kept(side2, to: corner), arc: nil, bevel: nil)
        }

        let cosine = max(-1, min(1, side1.direction.dot(side2.direction)))
        let theta = acos(cosine)
        guard theta > 1e-6, theta < .pi - 1e-6 else {
            throw EditError(message: "The lines are (almost) parallel.")
        }
        let room1 = (side1.far - corner).dot(side1.direction)
        let room2 = (side2.far - corner).dot(side2.direction)

        switch shape {
        case .round(let radius):
            let tangentDistance = radius / tan(theta / 2)
            guard tangentDistance <= room1 + 1e-9, tangentDistance <= room2 + 1e-9 else {
                throw EditError(message: "The radius is too large for these lines.")
            }

            let tangent1 = corner + side1.direction * tangentDistance
            let tangent2 = corner + side2.direction * tangentDistance
            let bisector = (side1.direction + side2.direction).normalized
            let center = corner + bisector * (radius / sin(theta / 2))

            let t1 = Geometry.angle(from: center, to: tangent1)
            let t2 = Geometry.angle(from: center, to: tangent2)
            let arc: (center: CGPoint, radius: CGFloat, start: CGFloat, end: CGFloat) = Geometry.ccwDelta(from: t1, to: t2) <= .pi
                ? (center: center, radius: radius, start: t1, end: t2)
                : (center: center, radius: radius, start: t2, end: t1)

            return CornerParts(kept1: room1 - tangentDistance > 1e-9 ? kept(side1, to: tangent1) : nil,
                               kept2: room2 - tangentDistance > 1e-9 ? kept(side2, to: tangent2) : nil,
                               arc: arc, bevel: nil)

        case .bevel(let first, let second):
            let d1 = max(0, first), d2 = max(0, second)
            guard d1 <= room1 + 1e-9, d2 <= room2 + 1e-9 else {
                throw EditError(message: "The chamfer distances are too large for these lines.")
            }
            let point1 = corner + side1.direction * d1
            let point2 = corner + side2.direction * d2
            return CornerParts(kept1: room1 - d1 > 1e-9 ? kept(side1, to: point1) : nil,
                               kept2: room2 - d2 > 1e-9 ? kept(side2, to: point2) : nil,
                               arc: nil,
                               bevel: Geometry.distance(point1, point2) > 1e-9 ? (point1, point2) : nil)
        }
    }

    /// The connecting piece of the corner (an arc or a chamfer line) with properties taken from a template.
    private static func connector(_ parts: CornerParts, like source: CADEntity) -> CADEntity? {
        if let a = parts.arc {
            let arc = Arc(center: a.center, radius: a.radius, startAngle: a.start, endAngle: a.end,
                          layer: source.layer, color: source.color)
            arc.lineWeight = source.lineWeight
            arc.lineTypeScale = source.lineTypeScale
            return arc
        }
        if let b = parts.bevel {
            let line = Line(start: b.start, end: b.end, layer: source.layer, color: source.color)
            line.lineWeight = source.lineWeight
            line.lineTypeScale = source.lineTypeScale
            return line
        }
        return nil
    }

    /// Rounds the corner between two lines. The side of each line that the user clicked is kept.
    /// Radius 0 = sharp corner (the lines are extended/shortened to the intersection).
    static func fillet(_ line1: Line, click1: CGPoint, _ line2: Line, click2: CGPoint,
                       radius: CGFloat) throws -> [CADEntity] {
        return try corner(line1, click1: click1, line2, click2: click2, shape: .round(radius: radius))
    }

    /// Modifies the corner between two lines (fillet or chamfer).
    static func corner(_ line1: Line, click1: CGPoint, _ line2: Line, click2: CGPoint,
                       shape: CornerShape) throws -> [CADEntity] {
        guard line1 !== line2 else { throw EditError(message: "Select two different lines.") }
        let parts = try cornerParts(line1.startPoint, line1.endPoint, click1: click1,
                                    line2.startPoint, line2.endPoint, click2: click2, shape: shape)
        var result: [CADEntity] = []
        if let kept = parts.kept1 {
            let piece = Line(start: kept.start, end: kept.end, layer: line1.layer, color: line1.color)
            piece.lineWeight = line1.lineWeight
            piece.lineTypeScale = line1.lineTypeScale
            result.append(piece)
        }
        if let piece = connector(parts, like: line1) { result.append(piece) }
        if let kept = parts.kept2 {
            let piece = Line(start: kept.start, end: kept.end, layer: line2.layer, color: line2.color)
            piece.lineWeight = line2.lineWeight
            piece.lineTypeScale = line2.lineTypeScale
            result.append(piece)
        }
        return result
    }

    /// Can the object be filleted / chamfered? (a line or a polyline)
    static func canFillet(_ entity: CADEntity) -> Bool {
        return entity is Line || entity is Polyline
    }

    /// Index of the polyline segment nearest to the point.
    static func nearestSegment(of polyline: Polyline, to point: CGPoint) -> Int {
        var best = 0
        var bestDistance = CGFloat.infinity
        for (index, primitive) in polyline.primitives().enumerated() {
            let d = primitive.distance(to: point)
            if d < bestDistance { bestDistance = d; best = index }
        }
        return best
    }

    /// Fillet for lines and polylines.
    static func fillet(_ entity1: CADEntity, click1: CGPoint, _ entity2: CADEntity, click2: CGPoint,
                       radius: CGFloat) throws -> (removed: [CADEntity], added: [CADEntity]) {
        return try corner(entity1, click1: click1, entity2, click2: click2, shape: .round(radius: radius))
    }

    /// Chamfer for lines and polylines: `first` is measured on the first object, `second` on the second.
    static func chamfer(_ entity1: CADEntity, click1: CGPoint, _ entity2: CADEntity, click2: CGPoint,
                        first: CGFloat, second: CGFloat) throws -> (removed: [CADEntity], added: [CADEntity]) {
        return try corner(entity1, click1: click1, entity2, click2: click2, shape: .bevel(first: first, second: second))
    }

    /// Corner modification (Fillet / Chamfer) for lines and polylines.
    /// - two adjacent straight segments of the same polyline → the corner is modified directly in it,
    /// - an end segment of a polyline + a line / another polyline → everything is joined into one polyline,
    /// - two lines → lines + a separate arc / chamfer line.
    static func corner(_ entity1: CADEntity, click1: CGPoint, _ entity2: CADEntity, click2: CGPoint,
                       shape: CornerShape) throws -> (removed: [CADEntity], added: [CADEntity]) {
        let name = shape.name
        if let line1 = entity1 as? Line, let line2 = entity2 as? Line {
            return ([line1, line2], try corner(line1, click1: click1, line2, click2: click2, shape: shape))
        }

        // corner inside a single polyline
        if let polyline = entity1 as? Polyline, entity1 === entity2 {
            let result = try polylineCorner(polyline, click1: click1, click2: click2, shape: shape)
            return ([polyline], [result])
        }

        // line / end segment of a polyline ↔ line / end segment of another polyline
        func virtualLine(_ entity: CADEntity, _ click: CGPoint) throws -> (a: CGPoint, b: CGPoint, segment: Int) {
            if let line = entity as? Line { return (line.startPoint, line.endPoint, -1) }
            guard let polyline = entity as? Polyline else { throw EditError(message: "\(name) works with lines and polylines.") }
            guard !polyline.closed else {
                throw EditError(message: "A closed polyline can only be changed between two of its own segments.")
            }
            let index = nearestSegment(of: polyline, to: click)
            guard polyline.bulge(at: index) == 0 else { throw EditError(message: "\(name) needs straight segments – this one is an arc.") }
            guard index == 0 || index == polyline.segmentCount - 1 else {
                throw EditError(message: "With another object, click an end segment of the polyline.")
            }
            let (a, b) = polyline.segmentEnds(index)
            return (a, b, index)
        }

        let v1 = try virtualLine(entity1, click1)
        let v2 = try virtualLine(entity2, click2)
        let parts = try cornerParts(v1.a, v1.b, click1: click1, v2.a, v2.b, click2: click2, shape: shape)

        /// The modified object (nil = it disappeared entirely).
        func rebuilt(_ entity: CADEntity, _ v: (a: CGPoint, b: CGPoint, segment: Int),
                     _ kept: (start: CGPoint, end: CGPoint)?) throws -> CADEntity? {
            if let line = entity as? Line {
                guard let kept = kept else { return nil }
                let piece = Line(start: kept.start, end: kept.end, layer: line.layer, color: line.color)
                piece.lineWeight = line.lineWeight
                piece.lineTypeScale = line.lineTypeScale
                return piece
            }
            guard let polyline = entity as? Polyline else { return nil }
            var vertices = polyline.vertices
            var bulges = (0..<vertices.count).map { polyline.bulge(at: $0) }
            let i = v.segment
            let tolerance = max(Geometry.distance(v.a, v.b), 1) * 1e-7
            if polyline.segmentCount == 1 {
                guard let kept = kept else { return nil }
                vertices = [kept.start, kept.end]
            } else if i == polyline.segmentCount - 1, kept.map({ Geometry.distance($0.start, v.a) <= tolerance }) ?? true {
                // end of the polyline
                if let kept = kept { vertices[i + 1] = kept.end } else { vertices.removeLast(); bulges.removeLast() }
            } else if i == 0, kept.map({ Geometry.distance($0.end, v.b) <= tolerance }) ?? true {
                // start of the polyline
                if let kept = kept { vertices[0] = kept.start } else { vertices.removeFirst(); bulges.removeFirst() }
            } else {
                throw EditError(message: "Click the polyline on the side you want to keep.")
            }
            let piece = Polyline(vertices: vertices, closed: false, bulges: bulges, layer: polyline.layer, color: polyline.color)
            piece.lineWeight = polyline.lineWeight
            piece.lineTypeScale = polyline.lineTypeScale
            return piece
        }

        var pieces: [CADEntity] = []
        if let first = try rebuilt(entity1, v1, parts.kept1) { pieces.append(first) }
        if let piece = connector(parts, like: entity1) { pieces.append(piece) }
        if let second = try rebuilt(entity2, v2, parts.kept2) { pieces.append(second) }

        // with a polyline everything is joined into one polyline (as in AutoCAD)
        let joined = join(pieces)
        var added = pieces.filter { piece in !joined.removed.contains { $0 === piece } }
        added.append(contentsOf: joined.added)
        if let first = added.first(where: { $0 is Polyline }), entity1 is Polyline || entity2 is Polyline {
            first.layer = entity1.layer
            first.color = entity1.color
            first.lineWeight = entity1.lineWeight
            first.lineTypeScale = entity1.lineTypeScale
        }
        return ([entity1, entity2], added)
    }

    /// Fillet / chamfer of the corner between two adjacent straight segments of the same polyline.
    private static func polylineCorner(_ polyline: Polyline, click1: CGPoint, click2: CGPoint,
                                       shape: CornerShape) throws -> Polyline {
        let name = shape.name
        let count = polyline.segmentCount
        let n = polyline.vertices.count
        let s1 = nearestSegment(of: polyline, to: click1)
        let s2 = nearestSegment(of: polyline, to: click2)
        // shared vertex k: segment (k−1) ends at k, segment k starts there
        let k: Int
        if s2 == s1 + 1 { k = s2 }
        else if s1 == s2 + 1 { k = s1 }
        else if polyline.closed && count > 2 && ((s1 == 0 && s2 == count - 1) || (s2 == 0 && s1 == count - 1)) { k = 0 }
        else if s1 == s2 { throw EditError(message: "Click two different segments of the polyline.") }
        else { throw EditError(message: "Click two adjacent segments of the polyline.") }

        let before = (k - 1 + n) % n          // the segment before vertex k
        guard polyline.bulge(at: before) == 0, polyline.bulge(at: k % n) == 0 else {
            throw EditError(message: "\(name) needs straight segments – one of them is an arc.")
        }
        let corner = polyline.vertices[k]
        let previous = polyline.vertices[before]
        let next = polyline.vertices[(k + 1) % n]
        guard !shape.isSharp else {
            throw EditError(message: shape.name == "Fillet" ? "With radius 0 the corner stays sharp."
                                                             : "With both distances 0 the corner stays sharp.")
        }

        let dir1 = (previous - corner).normalized, dir2 = (next - corner).normalized
        let len1 = Geometry.distance(previous, corner), len2 = Geometry.distance(next, corner)
        let theta = acos(max(-1, min(1, dir1.dot(dir2))))
        guard theta > 1e-6, theta < .pi - 1e-6 else { throw EditError(message: "The segments are (almost) in line.") }

        // lengths cut off the segment before the corner (1) and after it (2), and the bulge of the new segment
        let cut1: CGFloat, cut2: CGFloat, bulge: CGFloat
        switch shape {
        case .round(let radius):
            let tangentDistance = radius / tan(theta / 2)
            guard tangentDistance <= len1 + 1e-9, tangentDistance <= len2 + 1e-9 else {
                throw EditError(message: "The radius is too large for these segments.")
            }
            cut1 = tangentDistance
            cut2 = tangentDistance
            // if the path turns left, the arc goes counterclockwise
            let turn = (corner - previous).cross(next - corner)
            bulge = Polyline.bulge(forSweep: (.pi - theta) * (turn >= 0 ? 1 : -1))
        case .bevel(let first, let second):
            // the first distance belongs to the segment that was clicked first
            let firstIsBefore = s1 == before
            cut1 = max(0, firstIsBefore ? first : second)
            cut2 = max(0, firstIsBefore ? second : first)
            guard cut1 <= len1 + 1e-9, cut2 <= len2 + 1e-9 else {
                throw EditError(message: "The chamfer distances are too large for these segments.")
            }
            bulge = 0
        }
        let point1 = corner + dir1 * cut1
        let point2 = corner + dir2 * cut2

        var vertices = polyline.vertices
        var bulges = (0..<n).map { polyline.bulge(at: $0) }
        vertices.replaceSubrange(k...k, with: [point1, point2])
        bulges.replaceSubrange(k...k, with: [bulge, 0])
        let cleaned = removeDuplicateVertices(vertices, bulges, closed: polyline.closed)
        let result = Polyline(vertices: cleaned.vertices, closed: polyline.closed, bulges: cleaned.bulges,
                              layer: polyline.layer, color: polyline.color)
        result.lineWeight = polyline.lineWeight
        result.lineTypeScale = polyline.lineTypeScale
        return result
    }

    /// Removes zero-length segments (two identical consecutive vertices) – the bulge stays with the segment that continues.
    private static func removeDuplicateVertices(_ vertices: [CGPoint], _ bulges: [CGFloat],
                                                closed: Bool) -> (vertices: [CGPoint], bulges: [CGFloat]) {
        var v: [CGPoint] = []
        var b: [CGFloat] = []
        for (index, point) in vertices.enumerated() {
            if let last = v.last, Geometry.distance(last, point) <= 1e-9 {
                b[b.count - 1] = bulges[index]      // zero-length segment removed, the next segment's bulge applies
                continue
            }
            v.append(point)
            b.append(index < bulges.count ? bulges[index] : 0)
        }
        if closed, v.count > 2, let first = v.first, let last = v.last, Geometry.distance(first, last) <= 1e-9 {
            v.removeLast()
            b.removeLast()
        }
        return (v, b)
    }

    // MARK: Explode and Join

    /// Explodes a polyline into lines and arcs. nil = the object cannot be exploded.
    static func explode(_ entity: CADEntity) -> [CADEntity]? {
        if let reference = entity as? BlockReference {
            let parts = reference.exploded()
            return parts.isEmpty ? nil : parts
        }
        guard let polyline = entity as? Polyline, polyline.segmentCount > 0 else { return nil }
        var result: [CADEntity] = []
        for primitive in polyline.primitives() {
            switch primitive {
            case let .segment(a, b, _):
                guard Geometry.distance(a, b) > Geometry.epsilon else { continue }
                result.append(Line(start: a, end: b, layer: polyline.layer, color: polyline.color))
            case let .arc(c, r, start, sweep, _):
                let f = Primitive.ccwForm(start: start, sweep: sweep)
                result.append(Arc(center: c, radius: r, startAngle: f.start, endAngle: f.start + f.sweep,
                                  layer: polyline.layer, color: polyline.color))
            }
        }
        for piece in result { piece.lineWeight = polyline.lineWeight; piece.lineTypeScale = polyline.lineTypeScale }
        return result.isEmpty ? nil : result
    }

    /// A chain of points with segment bulges (bulges.count == points.count − 1).
    private struct Chain {
        var points: [CGPoint]
        var bulges: [CGFloat]
        var sources: [CADEntity]

        var start: CGPoint { return points[0] }
        var end: CGPoint { return points[points.count - 1] }

        var reversed: Chain {
            return Chain(points: points.reversed(), bulges: bulges.reversed().map { -$0 }, sources: sources)
        }

        mutating func append(_ other: Chain) {
            points.append(contentsOf: other.points.dropFirst())
            bulges.append(contentsOf: other.bulges)
            sources.append(contentsOf: other.sources)
        }
    }

    private static func chain(for entity: CADEntity) -> Chain? {
        switch entity {
        case let line as Line:
            guard Geometry.distance(line.startPoint, line.endPoint) > Geometry.epsilon else { return nil }
            return Chain(points: [line.startPoint, line.endPoint], bulges: [0], sources: [line])
        case let arc as Arc:
            guard arc.sweep < 2 * .pi - 1e-9 else { return nil }
            return Chain(points: [arc.startPoint, arc.endPoint], bulges: [Polyline.bulge(forSweep: arc.sweep)], sources: [arc])
        case let polyline as Polyline:
            guard !polyline.closed, polyline.vertices.count >= 2 else { return nil }
            return Chain(points: polyline.vertices,
                         bulges: (0..<(polyline.vertices.count - 1)).map { polyline.bulge(at: $0) },
                         sources: [polyline])
        default:
            return nil
        }
    }

    /// Joins connected lines, arcs and open polylines into polylines.
    /// A standalone line or arc is converted to a polyline. Closed loops are closed.
    static func join(_ entities: [CADEntity]) -> (removed: [CADEntity], added: [CADEntity]) {
        var pool = entities.compactMap { chain(for: $0) }
        guard !pool.isEmpty else { return ([], []) }

        var extent = CGRect.null
        for entity in entities { extent = extent.union(entity.boundingBox()) }
        let tolerance = max(hypot(extent.width, extent.height) * 1e-9, 1e-6)
        func same(_ a: CGPoint, _ b: CGPoint) -> Bool { return Geometry.distance(a, b) <= tolerance }

        var removed: [CADEntity] = []
        var added: [CADEntity] = []
        while !pool.isEmpty {
            var current = pool.removeFirst()
            var grew = true
            while grew && !(current.points.count > 2 && same(current.start, current.end)) {
                grew = false
                for (index, other) in pool.enumerated() {
                    if same(current.end, other.start) {
                        current.append(other)
                    } else if same(current.end, other.end) {
                        current.append(other.reversed)
                    } else if same(current.start, other.end) {
                        var joined = other
                        joined.append(current)
                        current = joined
                    } else if same(current.start, other.start) {
                        var joined = other.reversed
                        joined.append(current)
                        current = joined
                    } else {
                        continue
                    }
                    pool.remove(at: index)
                    grew = true
                    break
                }
            }

            // a single polyline that nothing was joined to stays unchanged
            if current.sources.count == 1, current.sources[0] is Polyline { continue }

            var points = current.points
            var bulges = current.bulges
            var closed = false
            if points.count > 2, same(current.start, current.end) {
                points.removeLast()       // the last segment becomes the closing one
                closed = true
            } else {
                bulges.append(0)
            }
            let style = current.sources[0]
            let polyline = Polyline(vertices: points, closed: closed, bulges: bulges, layer: style.layer, color: style.color)
            _ = polyline.withStyle(of: style)      // lineweight, line type scale, draw order, group
            removed.append(contentsOf: current.sources)
            added.append(polyline)
        }
        return (removed, added)
    }

    // MARK: Offset

    /// Can the object be offset?
    static func canOffset(_ entity: CADEntity) -> Bool {
        return entity is Line || entity is Circle || entity is Arc || entity is Polyline || entity is Spline || entity is Ellipse
    }

    /// Distance of a point from the object for the “Through” mode (for a line, from the infinite line).
    static func offsetDistance(of entity: CADEntity, to point: CGPoint) -> CGFloat {
        if let line = entity as? Line {
            let n = (line.endPoint - line.startPoint).normalized.perpendicular
            return abs((point - line.startPoint).dot(n))
        }
        if let circle = entity as? Circle { return abs(Geometry.distance(point, circle.center) - circle.radius) }
        if let arc = entity as? Arc { return abs(Geometry.distance(point, arc.center) - arc.radius) }
        return entity.distance(to: point)
    }

    /// A parallel copy of the object at `distance` toward the side of point `side`.
    static func offset(_ entity: CADEntity, distance: CGFloat, toward side: CGPoint) -> CADEntity? {
        guard distance > 0, distance.isFinite else { return nil }
        let result: CADEntity?

        switch entity {
        case let line as Line:
            let n = (line.endPoint - line.startPoint).normalized.perpendicular
            guard n != .zero else { return nil }
            let sign: CGFloat = (side - line.startPoint).dot(n) >= 0 ? 1 : -1
            let shift = n * (distance * sign)
            result = Line(start: line.startPoint + shift, end: line.endPoint + shift, layer: line.layer, color: line.color)

        case let circle as Circle:
            let outside = Geometry.distance(side, circle.center) >= circle.radius
            let radius = circle.radius + (outside ? distance : -distance)
            guard radius > Geometry.epsilon else { return nil }
            result = Circle(center: circle.center, radius: radius, layer: circle.layer, color: circle.color)

        case let arc as Arc:
            let outside = Geometry.distance(side, arc.center) >= arc.radius
            let radius = arc.radius + (outside ? distance : -distance)
            guard radius > Geometry.epsilon else { return nil }
            result = Arc(center: arc.center, radius: radius, startAngle: arc.startAngle, endAngle: arc.startAngle + arc.sweep,
                         layer: arc.layer, color: arc.color)

        case let polyline as Polyline where polyline.hasArcs:
            result = offsetWithArcs(polyline, distance: distance, side: side)

        case let polyline as Polyline:
            guard let points = offsetPath(polyline.vertices, closed: polyline.isClosedCurve,
                                          distance: distance, side: side) else { return nil }
            result = Polyline(vertices: points, closed: polyline.isClosedCurve, layer: polyline.layer, color: polyline.color)

        case let spline as Spline:
            // a spline is offset via a dense approximation – the result is a polyline that follows it faithfully
            var path = spline.flattened
            let closed = spline.isClosedCurve
            if closed, let first = path.first, let last = path.last, Geometry.distance(first, last) < 1e-9 { path.removeLast() }
            guard let points = offsetPath(path, closed: closed, distance: distance, side: side) else { return nil }
            result = Polyline(vertices: points, closed: closed, layer: spline.layer, color: spline.color)

        case let ellipse as Ellipse:
            // an offset ellipse is no longer an ellipse – a faithful polyline
            var path = ellipse.flattened
            let closed = ellipse.isFull
            if closed, let first = path.first, let last = path.last, Geometry.distance(first, last) < 1e-9 { path.removeLast() }
            guard let points = offsetPath(path, closed: closed, distance: distance, side: side) else { return nil }
            result = Polyline(vertices: points, closed: closed, layer: ellipse.layer, color: ellipse.color)

        default:
            return nil
        }
        result?.lineWeight = entity.lineWeight
        result?.lineTypeScale = entity.lineTypeScale
        return result
    }

    /// Offset of a polyline with arc segments: straight segments are shifted, arcs change their radius.
    /// Adjacent straight segments are joined at their intersection, otherwise the ends are connected by a straight segment.
    private static func offsetWithArcs(_ polyline: Polyline, distance: CGFloat, side: CGPoint) -> Polyline? {
        let primitives = polyline.primitives()
        guard !primitives.isEmpty else { return nil }

        // side from the nearest piece: + = left of the curve direction
        var nearest = 0
        var nearestDistance = CGFloat.infinity
        for (index, primitive) in primitives.enumerated() {
            let d = primitive.distance(to: side)
            if d < nearestDistance { nearestDistance = d; nearest = index }
        }
        let onLeft: Bool
        switch primitives[nearest] {
        case let .segment(a, b, _):
            onLeft = (b - a).cross(side - a) >= 0
        case let .arc(c, r, _, sweep, _):
            let inside = Geometry.distance(side, c) < r
            onLeft = sweep > 0 ? inside : !inside       // for a counterclockwise arc the center is on the left
        }
        let d = onLeft ? distance : -distance

        struct Piece { var start: CGPoint; var end: CGPoint; var bulge: CGFloat; var isLine: Bool }
        var pieces: [Piece] = []
        for (index, primitive) in primitives.enumerated() {
            switch primitive {
            case let .segment(a, b, _):
                let n = (b - a).normalized.perpendicular
                pieces.append(Piece(start: a + n * d, end: b + n * d, bulge: 0, isLine: true))
            case let .arc(c, r, start, sweep, _):
                let radius = sweep > 0 ? r - d : r + d
                guard radius > Geometry.epsilon else { return nil }     // offset larger than the arc radius
                pieces.append(Piece(start: Geometry.pointOnCircle(c, radius, start),
                                    end: Geometry.pointOnCircle(c, radius, start + sweep),
                                    bulge: polyline.bulge(at: index), isLine: false))
            }
        }

        let closed = polyline.isClosedCurve
        let count = pieces.count
        let tolerance = max(distance, 1) * 1e-9
        for k in 0..<(closed ? count : count - 1) {
            let m = (k + 1) % count
            guard Geometry.distance(pieces[k].end, pieces[m].start) > tolerance,
                  pieces[k].isLine, pieces[m].isLine,
                  let hit = Geometry.lineIntersection(pieces[k].start, pieces[k].end, pieces[m].start, pieces[m].end),
                  Geometry.distance(hit, polyline.vertices[m % polyline.vertices.count]) <= abs(d) * 4 else { continue }
            pieces[k].end = hit
            pieces[m].start = hit
        }

        var vertices: [CGPoint] = []
        var bulges: [CGFloat] = []
        for piece in pieces {
            if let last = vertices.last {
                if Geometry.distance(last, piece.start) > tolerance {
                    bulges.append(0)                 // connection with a straight segment
                    vertices.append(piece.start)
                }
            } else {
                vertices.append(piece.start)
            }
            bulges.append(piece.bulge)
            vertices.append(piece.end)
        }
        if closed {
            if let first = vertices.first, let last = vertices.last, Geometry.distance(first, last) <= tolerance {
                vertices.removeLast()
            } else {
                bulges.append(0)
            }
        } else {
            bulges.append(0)
        }
        guard vertices.count >= 2 else { return nil }
        return Polyline(vertices: vertices, closed: closed, bulges: bulges, layer: polyline.layer, color: polyline.color)
    }

    /// Offset of a polyline: shift each segment and join at intersections (with overly sharp corners beveled).
    private static func offsetPath(_ input: [CGPoint], closed: Bool, distance: CGFloat, side: CGPoint) -> [CGPoint]? {
        // without repeated points
        var points: [CGPoint] = []
        for p in input where points.last.map({ Geometry.distance($0, p) > 1e-9 }) ?? true { points.append(p) }
        if closed, points.count > 2, Geometry.distance(points[0], points[points.count - 1]) < 1e-9 { points.removeLast() }
        guard points.count >= 2 else { return nil }

        let segmentCount = closed ? points.count : points.count - 1
        var segments: [(a: CGPoint, b: CGPoint, n: CGPoint)] = []
        for i in 0..<segmentCount {
            let a = points[i], b = points[(i + 1) % points.count]
            segments.append((a, b, (b - a).normalized.perpendicular))
        }

        // side from the nearest segment (left/right of the curve direction)
        var nearest = 0
        var nearestDistance = CGFloat.infinity
        for (index, s) in segments.enumerated() {
            let d = Geometry.distance(from: side, toSegmentFrom: s.a, to: s.b)
            if d < nearestDistance { nearestDistance = d; nearest = index }
        }
        let sign: CGFloat = (side - segments[nearest].a).dot(segments[nearest].n) >= 0 ? 1 : -1
        let d = distance * sign
        let shifted = segments.map { (a: $0.a + $0.n * d, b: $0.b + $0.n * d) }

        /// Join of two adjacent offset segments at the original vertex `corner`.
        func join(_ s1: (a: CGPoint, b: CGPoint), _ s2: (a: CGPoint, b: CGPoint), corner: CGPoint) -> [CGPoint] {
            guard let hit = Geometry.lineIntersection(s1.a, s1.b, s2.a, s2.b) else { return [s1.b] }
            // spike too long (very sharp corner) → bevel it
            if Geometry.distance(hit, corner) > abs(d) * 4 { return [s1.b, s2.a] }
            return [hit]
        }

        var result: [CGPoint] = []
        if closed {
            for i in 0..<shifted.count {
                let previous = shifted[(i - 1 + shifted.count) % shifted.count]
                result.append(contentsOf: join(previous, shifted[i], corner: points[i]))
            }
        } else {
            result.append(shifted[0].a)
            for i in 1..<shifted.count {
                result.append(contentsOf: join(shifted[i - 1], shifted[i], corner: points[i]))
            }
            result.append(shifted[shifted.count - 1].b)
        }
        return result.count >= 2 ? result : nil
    }
}

// MARK: - Measure

/// What the Measure tool measures (menu at the icon).
enum MeasureKind: Int, CaseIterable {
    case distance, angle, radius, areaPoints, areaBoundary, areaObject, point, length

    var title: String {
        switch self {
        case .distance: return "Distance"
        case .angle: return "Angle"
        case .radius: return "Radius"
        case .areaPoints: return "Area – by Points"
        case .areaBoundary: return "Area – Inside a Boundary"
        case .areaObject: return "Area – of an Object"
        case .point: return "Point Coordinates"
        case .length: return "Length of Objects"
        }
    }

    var detail: String {
        switch self {
        case .distance: return "Two points – distance, ΔX, ΔY and angle"
        case .angle: return "Vertex, then a point on each leg"
        case .radius: return "Click a circle, arc or ellipse"
        case .areaPoints: return "Click the corners, ↩ finishes – area and perimeter"
        case .areaBoundary: return "Click inside a closed area (islands are left out)"
        case .areaObject: return "Click a closed object – circle, rectangle, polyline, hatch…"
        case .point: return "X and Y of a point"
        case .length: return "Click objects – their lengths are added up"
        }
    }

    var prompt: String {
        switch self {
        case .distance: return "Measure distance: first point"
        case .angle: return "Measure angle: vertex"
        case .radius: return "Measure radius: click a circle, arc or ellipse"
        case .areaPoints: return "Measure area: first corner"
        case .areaBoundary: return "Measure area: click inside a closed area"
        case .areaObject: return "Measure area: click a closed object"
        case .point: return "Measure point: click a point (snap works)"
        case .length: return "Measure length: click objects to add them up"
        }
    }

    /// Is it entered by points (snap, ortho)?
    var usesPoints: Bool {
        switch self {
        case .distance, .angle, .areaPoints, .point: return true
        default: return false
        }
    }
}

enum Measure {
    static func format(_ value: CGFloat) -> String {
        return LineType.format(value)
    }

    static func polygonArea(_ points: [CGPoint]) -> CGFloat {
        return abs(HatchEntity.signedArea(points))
    }

    static func perimeter(_ points: [CGPoint], closed: Bool) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<(points.count - 1) { total += Geometry.distance(points[i], points[i + 1]) }
        if closed { total += Geometry.distance(points[points.count - 1], points[0]) }
        return total
    }

    /// Outline points from segments and arcs (arcs are replaced by a dense polyline).
    static func outline(of primitives: [Primitive]) -> [CGPoint] {
        var result: [CGPoint] = []
        for primitive in primitives {
            switch primitive {
            case let .segment(a, b, _):
                if result.isEmpty { result.append(a) }
                result.append(b)
            case let .arc(c, r, start, sweep, _):
                let steps = max(4, Int((abs(sweep) / (.pi / 36)).rounded(.up)))
                if result.isEmpty { result.append(Geometry.pointOnCircle(c, r, start)) }
                for i in 1...steps {
                    result.append(Geometry.pointOnCircle(c, r, start + sweep * CGFloat(i) / CGFloat(steps)))
                }
            }
        }
        if result.count > 2, let first = result.first, let last = result.last, Geometry.distance(first, last) < 1e-9 {
            result.removeLast()
        }
        return result
    }

    /// Area and perimeter of a closed object (nil = the object is not closed).
    static func areaAndPerimeter(of entity: CADEntity) -> (area: CGFloat, perimeter: CGFloat, outline: [[CGPoint]])? {
        switch entity {
        case let circle as Circle:
            return (.pi * circle.radius * circle.radius, 2 * .pi * circle.radius, [outline(of: circle.primitives())])
        case let ellipse as Ellipse where ellipse.isFull:
            return (ellipse.area, ellipse.curveLength, [ellipse.flattened])
        case let hatch as HatchEntity:
            let perimeter = hatch.loops.reduce(0) { $0 + Measure.perimeter($1, closed: true) }
            return (hatch.area, perimeter, hatch.loops)
        case let viewport as ViewportEntity:
            return (viewport.rect.width * viewport.rect.height, 2 * (viewport.rect.width + viewport.rect.height), [viewport.corners])
        case let curve as CurveEntity where curve.isClosedCurve:
            let points = outline(of: curve.primitives())
            guard points.count >= 3 else { return nil }
            return (polygonArea(points), curve.curveLength, [points])
        default:
            return nil
        }
    }

    /// Area of a region with islands (the first loop is the outer one).
    static func area(ofLoops loops: [[CGPoint]]) -> CGFloat {
        guard let outer = loops.first else { return 0 }
        return polygonArea(outer) - loops.dropFirst().reduce(0) { $0 + polygonArea($1) }
    }

    /// Radius of the object under the cursor (circle, arc, arc segment of a polyline, ellipse).
    static func radiusText(of entity: CADEntity, near point: CGPoint, unit: String) -> (text: String, center: CGPoint, onCurve: CGPoint)? {
        func circleText(_ r: CGFloat) -> String {
            return "Radius \(format(r)) \(unit) · Diameter \(format(2 * r)) \(unit) · Circumference \(format(2 * .pi * r)) \(unit)"
        }
        switch entity {
        case let circle as Circle:
            let p = Geometry.pointOnCircle(circle.center, circle.radius, Geometry.angle(from: circle.center, to: point))
            return (circleText(circle.radius), circle.center, p)
        case let arc as Arc:
            let p = Geometry.pointOnCircle(arc.center, arc.radius, Geometry.angle(from: arc.center, to: point))
            return (circleText(arc.radius) + " · Arc length \(format(arc.curveLength)) \(unit)", arc.center, p)
        case let ellipse as Ellipse:
            return ("Major radius \(format(ellipse.majorRadius)) \(unit) · Minor radius \(format(ellipse.minorRadius)) \(unit)",
                    ellipse.center, ellipse.point(at: 0))
        case let polyline as Polyline:
            let index = EditOperations.nearestSegment(of: polyline, to: point)
            let (a, b) = polyline.segmentEnds(index)
            guard let arc = Polyline.arcGeometry(from: a, to: b, bulge: polyline.bulge(at: index)) else { return nil }
            let p = Geometry.pointOnCircle(arc.center, arc.radius, Geometry.angle(from: arc.center, to: point))
            return (circleText(arc.radius), arc.center, p)
        default:
            return nil
        }
    }
}

// MARK: - Array

enum ArrayKind: Int, CaseIterable {
    case rectangular, polar

    var title: String {
        switch self {
        case .rectangular: return "Rectangular Array"
        case .polar: return "Polar Array"
        }
    }

    var detail: String {
        switch self {
        case .rectangular: return "Copies in rows and columns"
        case .polar: return "Copies around a center point"
        }
    }
}

struct ArraySettings {
    var columns = 4
    var rows = 3
    /// nil = from the size of the selection
    var columnSpacing: CGFloat?
    var rowSpacing: CGFloat?
    var count = 6
    /// The angle over which the copies are spread (360 = full circle).
    var fillAngle: CGFloat = 360
    var rotateItems = true

    static let maxCopies = 20_000
}

extension EditOperations {
    /// Copies of the array objects (without the original at the starting position).
    static func arrayCopies(of originals: [CADEntity], kind: ArrayKind, settings: ArraySettings,
                            center: CGPoint, columnSpacing: CGFloat, rowSpacing: CGFloat) -> [CADEntity] {
        guard !originals.isEmpty else { return [] }
        var transforms: [CGAffineTransform] = []
        switch kind {
        case .rectangular:
            let columns = max(1, settings.columns), rows = max(1, settings.rows)
            guard columns * rows - 1 <= ArraySettings.maxCopies / originals.count else { return [] }
            for row in 0..<rows {
                for column in 0..<columns where row > 0 || column > 0 {
                    transforms.append(CGAffineTransform(translationX: CGFloat(column) * columnSpacing,
                                                        y: CGFloat(row) * rowSpacing))
                }
            }
        case .polar:
            let count = max(2, settings.count)
            guard count - 1 <= ArraySettings.maxCopies / originals.count else { return [] }
            let fill = settings.fillAngle * .pi / 180
            let fullCircle = abs(settings.fillAngle) >= 360 - 1e-9
            let step = fullCircle ? fill / CGFloat(count) : fill / CGFloat(count - 1)
            var box = CGRect.null
            for entity in originals { box = box.union(entity.boundingBox()) }
            let reference = CGPoint(x: box.midX, y: box.midY)
            for k in 1..<count {
                let rotation = Geometry.rotation(by: step * CGFloat(k), around: center)
                if settings.rotateItems {
                    transforms.append(rotation)
                } else {
                    let moved = reference.applying(rotation)
                    transforms.append(CGAffineTransform(translationX: moved.x - reference.x, y: moved.y - reference.y))
                }
            }
        }
        var copies: [CADEntity] = []
        for transform in transforms {
            // each copy of a group becomes a group of its own
            var groups: [UUID: UUID] = [:]
            for entity in originals {
                let copy = entity.clone()
                copy.applyTransform(transform)
                if let group = entity.groupID {
                    let fresh = groups[group] ?? UUID()
                    groups[group] = fresh
                    copy.groupID = fresh
                }
                copies.append(copy)
            }
        }
        return copies
    }
}


// MARK: - Match properties

/// Groups of properties that the Match Properties tool transfers.
enum MatchProperty: String, CaseIterable {
    case layer, color, lineWeight, style

    var title: String {
        switch self {
        case .layer: return "Layer"
        case .color: return "Color"
        case .lineWeight: return "Lineweight"
        case .style: return "Text, dimension and hatch style"
        }
    }

    var detail: String {
        switch self {
        case .layer: return "Moves the objects to the layer of the source (and so its linetype)"
        case .color: return "Same color – or ByLayer, if the source has it"
        case .lineWeight: return "Same lineweight – or ByLayer"
        case .style: return "Only between objects of the same kind: text height and font · dimension ends, text and arrow size, decimals · hatch pattern, angle and scale"
        }
    }
}

enum MatchProperties {
    /// Does the object have its own style that can be transferred to the same kind of object?
    static func hasStyle(_ entity: CADEntity) -> Bool {
        return entity is TextEntity || entity is DimensionEntity || entity is HatchEntity
    }

    /// A copy of the target with the source's properties (nil = nothing would change).
    static func apply(from source: CADEntity, to target: CADEntity, properties: Set<MatchProperty>) -> CADEntity? {
        let copy = target.clone()
        var changed = false
        if properties.contains(.layer), copy.layer != source.layer {
            copy.layer = source.layer
            changed = true
        }
        if properties.contains(.color), !sameColor(copy.color, source.color) {
            copy.color = source.color
            changed = true
        }
        if properties.contains(.lineWeight), copy.lineWeight != source.lineWeight {
            copy.lineWeight = source.lineWeight
            changed = true
        }
        if properties.contains(.style) {
            switch (source, copy) {
            case let (s as TextEntity, t as TextEntity):
                if t.height != s.height || t.fontFamily != s.fontFamily || t.fontFace != s.fontFace
                    || t.underline != s.underline || t.lineSpacing != s.lineSpacing {
                    t.height = s.height
                    t.fontFamily = s.fontFamily
                    t.fontFace = s.fontFace
                    t.underline = s.underline
                    t.lineSpacing = s.lineSpacing
                    changed = true
                }
            case let (s as DimensionEntity, t as DimensionEntity):
                if t.textHeight != s.textHeight || t.arrowSize != s.arrowSize || t.arrowStyle != s.arrowStyle
                    || t.precision != s.precision {
                    t.textHeight = s.textHeight
                    t.arrowSize = s.arrowSize
                    t.arrowStyle = s.arrowStyle
                    t.precision = s.precision
                    changed = true
                }
            case let (s as HatchEntity, t as HatchEntity):
                if t.pattern != s.pattern || t.angle != s.angle || t.scale != s.scale {
                    t.pattern = s.pattern
                    t.angle = s.angle
                    t.scale = s.scale
                    changed = true
                }
            default:
                break
            }
        }
        return changed ? copy : nil
    }

    private static func sameColor(_ a: NSColor?, _ b: NSColor?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?):
            guard let p = x.usingColorSpace(.sRGB), let q = y.usingColorSpace(.sRGB) else { return x == y }
            return abs(p.redComponent - q.redComponent) < 0.002 && abs(p.greenComponent - q.greenComponent) < 0.002
                && abs(p.blueComponent - q.blueComponent) < 0.002
        default: return false
        }
    }
}


// MARK: - Construction lines

/// Construction line input method.
enum XLineKind: Int, CaseIterable {
    case twoPoints, horizontal, vertical, angle

    var title: String {
        switch self {
        case .twoPoints: return "Through Two Points"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .angle: return "At an Angle…"
        }
    }

    var detail: String {
        switch self {
        case .twoPoints: return "A point, then the direction – more lines through the same point (B)"
        case .horizontal: return "Every click places a horizontal line (H)"
        case .vertical: return "Every click places a vertical line (V)"
        case .angle: return "Every click places a line at the chosen angle (A)"
        }
    }
}

// MARK: - Regular polygon

/// How a regular polygon is entered (like POLYGON in AutoCAD).
enum PolygonMethod: Int, CaseIterable {
    /// Center and corner – the corners lie on the circle.
    case inscribed
    /// Center and side midpoint – the sides touch the circle.
    case circumscribed
    /// Two corners of one side – the polygon is built to its left.
    case edge

    var title: String {
        switch self {
        case .inscribed: return "Inscribed in Circle"
        case .circumscribed: return "Circumscribed about Circle"
        case .edge: return "By One Side"
        }
    }

    /// Short label for the prompt.
    var shortTitle: String {
        switch self {
        case .inscribed: return "inscribed"
        case .circumscribed: return "circumscribed"
        case .edge: return "by side"
        }
    }

    var detail: String {
        switch self {
        case .inscribed: return "Center, then a corner – the corners lie on the circle (I)"
        case .circumscribed: return "Center, then the middle of a side – the sides touch the circle (C)"
        case .edge: return "The two corners of one side – the polygon is built to its left (E)"
        }
    }

    /// The letter that switches the method while drawing.
    var letter: String {
        switch self {
        case .inscribed: return "i"
        case .circumscribed: return "c"
        case .edge: return "e"
        }
    }
}

extension AppSettings {
    /// Number of sides of a new polygon (3–1024).
    static var polygonSides: Int {
        get {
            let value = UserDefaults.standard.object(forKey: "OhMyCAD.polygonSides") as? Int ?? 6
            return min(max(value, RegularPolygon.minimumSides), RegularPolygon.maximumSides)
        }
        set {
            UserDefaults.standard.set(min(max(newValue, RegularPolygon.minimumSides), RegularPolygon.maximumSides),
                                      forKey: "OhMyCAD.polygonSides")
        }
    }

    static var polygonMethod: PolygonMethod {
        get { return PolygonMethod(rawValue: UserDefaults.standard.integer(forKey: "OhMyCAD.polygonMethod")) ?? .inscribed }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "OhMyCAD.polygonMethod") }
    }
}

enum RegularPolygon {
    static let minimumSides = 3
    static let maximumSides = 1024

    /// Corners of a regular polygon (counterclockwise).
    /// inscribed: a = center, b = corner · circumscribed: a = center, b = side midpoint · edge: a, b = corners of one side.
    static func vertices(sides: Int, method: PolygonMethod, _ a: CGPoint, _ b: CGPoint) -> [CGPoint]? {
        guard sides >= minimumSides, sides <= maximumSides else { return nil }
        let distance = Geometry.distance(a, b)
        guard distance > 1e-9, distance.isFinite else { return nil }
        let n = CGFloat(sides)
        let step = 2 * CGFloat.pi / n
        let direction = Geometry.angle(from: a, to: b)
        switch method {
        case .inscribed:
            return (0..<sides).map { Geometry.pointOnCircle(a, distance, direction + step * CGFloat($0)) }
        case .circumscribed:
            // b is a side midpoint: the corners lie half a step to the side, farther from the center
            let radius = distance / cos(.pi / n)
            return (0..<sides).map { Geometry.pointOnCircle(a, radius, direction - step / 2 + step * CGFloat($0)) }
        case .edge:
            var result = [a, b]
            var angle = direction
            for _ in 2..<sides {
                angle += step
                result.append(Geometry.pointOnCircle(result[result.count - 1], distance, angle))
            }
            return result
        }
    }
}

// MARK: - Select Similar

/// What similar objects are matched by.
enum SimilarProperty: String, CaseIterable {
    case type, layer, color, lineWeight, style

    var title: String {
        switch self {
        case .type: return "Object Type"
        case .layer: return "Layer"
        case .color: return "Color"
        case .lineWeight: return "Lineweight"
        case .style: return "Name and Style"
        }
    }

    var detail: String {
        switch self {
        case .type: return "Line, circle, polyline, text, dimension of the same kind…"
        case .layer: return "On the same layer"
        case .color: return "The same color (ByLayer counts as its own value)"
        case .lineWeight: return "The same lineweight (ByLayer counts as its own value)"
        case .style: return "Blocks with the same name, hatches with the same pattern, texts with the same font and height, dimensions with the same text height"
        }
    }
}

extension AppSettings {
    /// What objects must have in common with the selected ones (default as in AutoCAD: kind, layer, name / style).
    static var similarProperties: Set<SimilarProperty> {
        get {
            guard let names = UserDefaults.standard.stringArray(forKey: "OhMyCAD.similarProperties") else {
                return [.type, .layer, .style]
            }
            return Set(names.compactMap { SimilarProperty(rawValue: $0) })
        }
        set {
            UserDefaults.standard.set(SimilarProperty.allCases.filter { newValue.contains($0) }.map { $0.rawValue },
                                      forKey: "OhMyCAD.similarProperties")
        }
    }
}

enum SelectSimilar {
    /// Objects from `candidates` that match one of `selected` in the chosen properties.
    static func matches(of selected: [CADEntity], in candidates: [CADEntity],
                        properties: Set<SimilarProperty>) -> [CADEntity] {
        // without criteria everything would be selected – at least the object kind
        let used = properties.isEmpty ? [SimilarProperty.type] : properties
        let keys = Set(selected.map { key(of: $0, properties: used) })
        return candidates.filter { keys.contains(key(of: $0, properties: used)) }
    }

    /// Description of the criteria used, for the message (“type, layer and style”).
    static func describe(_ properties: Set<SimilarProperty>) -> String {
        let used = properties.isEmpty ? [SimilarProperty.type] : properties
        let names = SimilarProperty.allCases.filter { used.contains($0) }.map { $0.title.lowercased() }
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    static func key(of entity: CADEntity, properties: Set<SimilarProperty>) -> String {
        var parts: [String] = []
        if properties.contains(.type) { parts.append("t:" + typeKey(entity)) }
        if properties.contains(.layer) { parts.append("l:" + entity.layer.lowercased()) }
        if properties.contains(.color) { parts.append("c:" + colorKey(entity.color)) }
        if properties.contains(.lineWeight) {
            parts.append("w:" + (entity.lineWeight.map { String(format: "%.4f", Double($0)) } ?? "bylayer"))
        }
        if properties.contains(.style) { parts.append("s:" + styleKey(entity)) }
        return parts.joined(separator: "|")
    }

    private static func typeKey(_ entity: CADEntity) -> String {
        if let dimension = entity as? DimensionEntity { return "Dimension." + dimension.kind.rawValue }
        return entity.typeName
    }

    private static func styleKey(_ entity: CADEntity) -> String {
        if let reference = entity as? BlockReference { return "block:" + reference.definition.name.lowercased() }
        if let hatch = entity as? HatchEntity { return "hatch:" + hatch.pattern.name.lowercased() }
        if let text = entity as? TextEntity {
            return "text:\(text.fontFamily.lowercased())/\(text.fontFace.lowercased())/" + String(format: "%.4f", Double(text.height))
        }
        if let dimension = entity as? DimensionEntity { return "dim:" + String(format: "%.4f", Double(dimension.textHeight)) }
        return ""
    }

    /// Color as text (sRGB in whole steps) – the same colors from different color spaces match.
    static func colorKey(_ color: NSColor?) -> String {
        guard let color = color else { return "bylayer" }
        guard let rgb = color.usingColorSpace(.sRGB) else { return color.description }
        let parts = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
        return parts.map { String(Int(($0 * 255).rounded())) }.joined(separator: ",")
    }
}

extension Primitive {
    /// Bounding box (an arc is given the box of its whole circle – enough for skipping far-away pieces).
    var bounds: CGRect {
        switch self {
        case let .segment(a, b, _):
            return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        case let .arc(c, r, _, _, _):
            return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        }
    }
}
