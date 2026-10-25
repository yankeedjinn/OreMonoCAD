//
//  Walls.swift
//  OreMonoCAD
//
//  Wall drawn with a double line: you click the points of one line (the axis or a face of the wall) and the tool
//  draws both faces at the wall thickness, with mitered corners. The result is ordinary closed polylines –
//  an open wall is one outline (both faces and the ends), a closed wall gives two (the outer and the inner face).
//  A new wall is joined to the walls it touches or crosses (T, L and X joints): their outlines on the same layer
//  are merged into one, as a separate Undo step.
//  Wall from Curve builds the same outlines along selected lines, arcs, polylines and splines.
//

import Cocoa

enum Walls {
    /// Where the wall lies relative to the clicked line (as seen in the direction of drawing).
    enum Justification: CaseIterable {
        case center, left, right

        var title: String {
            switch self {
            case .center: return "centered on the clicked line"
            case .left: return "left of the clicked line"
            case .right: return "right of the clicked line"
            }
        }

        /// The next one for J: centered → left → right → centered.
        var next: Justification {
            switch self {
            case .center: return .left
            case .left: return .right
            case .right: return .center
            }
        }
    }

    /// Thickness of new walls (mm) – the usual brick wall.
    static let defaultThicknessMM: CGFloat = 300
    /// Allowed thickness (mm).
    static let thicknessRangeMM: ClosedRange<CGFloat> = 10...5000

    /// Shift of both faces from the clicked line (positive = to the left of the direction of drawing).
    static func faceOffsets(thickness: CGFloat, justification: Justification) -> (left: CGFloat, right: CGFloat) {
        switch justification {
        case .center: return (thickness / 2, -thickness / 2)
        case .left: return (thickness, 0)
        case .right: return (0, -thickness)
        }
    }

    /// The outline of the wall along the clicked points. Empty = not enough different points.
    static func outlines(along clicked: [CGPoint], closed: Bool, thickness: CGFloat, justification: Justification,
                         layer: String) -> [Polyline] {
        // drop repeated points (and the last one if it closes the line)
        var points: [CGPoint] = []
        for point in clicked where DrawingSafety.isFinite(point) {
            if let last = points.last, Geometry.distance(last, point) < 1e-9 { continue }
            points.append(point)
        }
        var isClosed = closed
        if points.count > 2, let first = points.first, let last = points.last, Geometry.distance(first, last) < 1e-9 {
            points.removeLast()
            isClosed = true
        }
        if points.count < 3 { isClosed = false }
        guard points.count >= 2, thickness > 0, thickness.isFinite else { return [] }

        let offsets = faceOffsets(thickness: thickness, justification: justification)
        let left = face(of: points, closed: isClosed, offset: offsets.left)
        let right = face(of: points, closed: isClosed, offset: offsets.right)
        if isClosed {
            return [Polyline(vertices: left, closed: true, layer: layer), Polyline(vertices: right, closed: true, layer: layer)]
        }
        // one outline: along the left face, across the end, back along the right face and across the start
        return [Polyline(vertices: left + right.reversed(), closed: true, layer: layer)]
    }

    /// Longest miter on the outer side of a corner, as a multiple of the offset; a sharper corner is beveled.
    private static let miterLimit: CGFloat = 3

    /// One face: the clicked line shifted sideways by `offset` (positive = left), its corners mitered
    /// (the shifted segments meet where they cross), very sharp outer corners beveled instead of a long spike.
    static func face(of points: [CGPoint], closed: Bool, offset: CGFloat) -> [CGPoint] {
        let n = points.count
        let segmentCount = closed ? n : n - 1
        // the left normal of each segment
        let normals: [CGPoint] = (0..<segmentCount).map { i in
            let d = (points[(i + 1) % n] - points[i]).normalized
            return CGPoint(x: -d.y, y: d.x)
        }
        return (0..<n).flatMap { j -> [CGPoint] in
            if !closed && j == 0 { return [points[0] + normals[0] * offset] }
            if !closed && j == n - 1 { return [points[j] + normals[segmentCount - 1] * offset] }
            let before = normals[(j - 1 + segmentCount) % segmentCount], after = normals[j % segmentCount]
            // the miter: along the sum of both normals, long enough to keep the distance `offset` from both segments
            let k = 1 + before.dot(after)
            guard k > 1e-6 else { return [points[j] + before * offset] }   // the line turns back on itself
            // miter length = offset · √(2/k); on the outer side of the turn a too long one becomes a bevel
            let isOuter = before.cross(after) * offset < 0
            if isOuter && 2 / k > miterLimit * miterLimit {
                return [points[j] + before * offset, points[j] + after * offset]
            }
            return [points[j] + (before + after) * (offset / k)]
        }
    }
}

// MARK: - Wall from Curve

extension Walls {
    /// Where a wall made from a curve lies: on the curve, outside it or inside it.
    enum CurveAlignment: CaseIterable {
        case center, outside, inside

        var title: String {
            switch self {
            case .center: return "centered on the curve"
            case .outside: return "outside the curve"
            case .inside: return "inside the curve"
            }
        }

        /// The next one for J: centered → outside → inside → centered.
        var next: CurveAlignment {
            switch self {
            case .center: return .outside
            case .outside: return .inside
            case .inside: return .center
            }
        }
    }

    /// Can a wall follow this object?
    static func canFollow(_ entity: CADEntity) -> Bool {
        return entity is Line || entity is Arc || entity is Polyline || entity is Spline || entity is Circle || entity is Ellipse
    }

    /// Walls along existing curves. Curves whose ends touch become one wall with mitered corners;
    /// arcs and splines are followed by short straight pieces. Empty = nothing a wall can follow.
    static func outlines(alongCurves curves: [CADEntity], thickness: CGFloat, alignment: CurveAlignment,
                         layer: String) -> [Polyline] {
        guard thickness > 0, thickness.isFinite else { return [] }
        var result: [Polyline] = []
        for chain in chains(of: curves, flatness: thickness / 100) {
            let justification: Justification
            switch alignment {
            case .center:
                justification = .center
            case .outside, .inside:
                // inside = the side the curve bends toward: the left one when it runs counterclockwise
                // (an open curve is judged as if closed by a straight line; a straight line counts as counterclockwise)
                let counterclockwise = HatchEntity.signedArea(chain.points) >= 0
                justification = (alignment == .inside) == counterclockwise ? .left : .right
            }
            result += outlines(along: chain.points, closed: chain.closed, thickness: thickness,
                               justification: justification, layer: layer)
        }
        return result
    }

    /// The curves as point chains – the ones whose ends touch joined into one (as Join does).
    private static func chains(of curves: [CADEntity], flatness: CGFloat) -> [(points: [CGPoint], closed: Bool)] {
        var result: [(points: [CGPoint], closed: Bool)] = []
        var pool: [[CGPoint]] = []
        var extent = CGRect.null
        for curve in curves where canFollow(curve) {
            var points: [CGPoint] = []
            for primitive in curve.primitives() {
                for point in HatchRegionFinder.flatten(primitive, flatness: flatness) where DrawingSafety.isFinite(point) {
                    if let last = points.last, Geometry.distance(last, point) < 1e-9 { continue }
                    points.append(point)
                }
            }
            guard points.count >= 2 else { continue }
            extent = extent.union(curve.boundingBox())
            if (curve as? CurveEntity)?.isClosedCurve ?? false {
                result.append((points, true))
            } else {
                pool.append(points)
            }
        }

        let tolerance = extent.isNull ? 1e-6 : max(hypot(extent.width, extent.height) * 1e-9, 1e-6)
        func same(_ a: CGPoint, _ b: CGPoint) -> Bool { return Geometry.distance(a, b) <= tolerance }

        while !pool.isEmpty {
            var current = pool.removeFirst()
            var grew = true
            while grew, !(current.count > 2 && same(current[0], current[current.count - 1])) {
                grew = false
                for (index, other) in pool.enumerated() {
                    if same(current[current.count - 1], other[0]) {
                        current += other.dropFirst()
                    } else if same(current[current.count - 1], other[other.count - 1]) {
                        current += Array(other.reversed()).dropFirst()
                    } else if same(current[0], other[other.count - 1]) {
                        current = other + current.dropFirst()
                    } else if same(current[0], other[0]) {
                        current = Array(other.reversed()) + current.dropFirst()
                    } else {
                        continue
                    }
                    pool.remove(at: index)
                    grew = true
                    break
                }
            }
            let closed = current.count > 2 && same(current[0], current[current.count - 1])
            result.append((current, closed))
        }
        return result
    }
}

extension AppSettings {
    /// Thickness of new walls in mm.
    static var wallThicknessMM: CGFloat {
        get {
            let value = UserDefaults.standard.object(forKey: "OreMonoCAD.wallThickness") as? Double
            return clampedWallThickness(value.map { CGFloat($0) } ?? Walls.defaultThicknessMM)
        }
        set { UserDefaults.standard.set(Double(clampedWallThickness(newValue)), forKey: "OreMonoCAD.wallThickness") }
    }

    private static func clampedWallThickness(_ value: CGFloat) -> CGFloat {
        let range = Walls.thicknessRangeMM
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

// MARK: - Joining walls

extension Walls {
    /// Joins new wall outlines with the walls they touch or cross: closed straight polylines on the same layer
    /// (and the faces nested in them – the inner face of a closed wall). Returns the merged outlines
    /// and the objects they replace; nil = the new walls touch nothing.
    static func joined(_ new: [Polyline], with existing: [CADEntity]) -> (removed: [Polyline], added: [Polyline])? {
        guard let style = new.first else { return nil }
        let newLoops = new.map { $0.vertices }
        var newBox = CGRect.null
        for loop in newLoops { newBox = newBox.union(HatchEntity.box(of: loop)) }
        guard !newBox.isNull else { return nil }
        let tolerance = max(newBox.width, newBox.height, 1) * 1e-7
        let others = existing.compactMap { $0 as? Polyline }.filter { polyline in
            polyline.closed && !polyline.hasArcs && polyline.vertices.count >= 3 && polyline.layer == style.layer
                && !new.contains { $0 === polyline }
        }
        // the walls the new ones touch or cross
        let reach = newBox.insetBy(dx: -tolerance, dy: -tolerance)
        var touched = others.filter { other in
            reach.intersects(other.boundingBox().insetBy(dx: -tolerance, dy: -tolerance))
                && newLoops.contains { loopsMeet($0, other.vertices, tolerance: tolerance) }
        }
        guard !touched.isEmpty else { return nil }
        // the faces nested in a touched wall, or around it (the outer and inner face of a closed wall)
        for other in others where !touched.contains(where: { $0 === other }) {
            let box = other.boundingBox()
            let nested = touched.contains { wall in
                let wallBox = wall.boundingBox()
                return (wallBox.contains(box) && HatchEntity.pointInPolygon(other.vertices[0], wall.vertices))
                    || (box.contains(wallBox) && HatchEntity.pointInPolygon(wall.vertices[0], other.vertices))
            }
            if nested { touched.append(other) }
        }
        let oldLoops = touched.map { $0.vertices }
        func inside(_ p: CGPoint) -> Bool {
            return evenOdd(p, newLoops) || evenOdd(p, oldLoops)
        }
        let loops = boundary(of: newLoops + oldLoops, inside: inside, tolerance: tolerance)
        guard !loops.isEmpty else { return nil }
        let merged = loops.map { loop -> Polyline in
            let polyline = Polyline(vertices: loop, closed: true, layer: style.layer, color: style.color)
            return polyline.withStyle(of: style)
        }
        return (touched, merged)
    }

    private static func evenOdd(_ p: CGPoint, _ loops: [[CGPoint]]) -> Bool {
        var inside = false
        for loop in loops where HatchEntity.pointInPolygon(p, loop) { inside.toggle() }
        return inside
    }

    /// Do two outlines touch, cross or lie one inside the other?
    private static func loopsMeet(_ a: [CGPoint], _ b: [CGPoint], tolerance: CGFloat) -> Bool {
        for i in a.indices {
            let a1 = a[i], a2 = a[(i + 1) % a.count]
            for j in b.indices {
                let b1 = b[j], b2 = b[(j + 1) % b.count]
                if Geometry.segmentIntersection(a1, a2, b1, b2) != nil { return true }
                // touching along a face (parallel edges have no single intersection)
                if Geometry.distance(from: b1, toSegmentFrom: a1, to: a2) <= tolerance
                    || Geometry.distance(from: a1, toSegmentFrom: b1, to: b2) <= tolerance { return true }
            }
        }
        return HatchEntity.pointInPolygon(a[0], b) || HatchEntity.pointInPolygon(b[0], a)
    }

    /// The outline of a region given by `inside`, built from the edges of the loops: every edge is cut where it meets
    /// another one, a piece stays when the region is on exactly one side of it, and the pieces are chained into loops
    /// (the region on their left). Straight runs are merged into one segment.
    static func boundary(of loops: [[CGPoint]], inside: (CGPoint) -> Bool, tolerance: CGFloat) -> [[CGPoint]] {
        let edges = loops.flatMap { loop in loop.indices.map { (loop[$0], loop[($0 + 1) % loop.count]) } }
            .filter { Geometry.distance($0.0, $0.1) > tolerance }
        // the vertices of the result, merged when closer than the tolerance
        var pool: [CGPoint] = []
        var cells: [Int64: [Int]] = [:]
        let cellSize = tolerance * 4
        func key(_ cx: Int64, _ cy: Int64) -> Int64 { return cx &* 73_856_093 ^ cy &* 19_349_663 }
        func cellOf(_ value: CGFloat) -> Int64 {
            let c = (value / cellSize).rounded(.down)
            return c.isFinite ? Int64(max(min(c, 1e15), -1e15)) : 0
        }
        func vertex(_ p: CGPoint) -> Int {
            let cx = cellOf(p.x), cy = cellOf(p.y)
            for dx: Int64 in -1...1 {
                for dy: Int64 in -1...1 {
                    for index in cells[key(cx + dx, cy + dy)] ?? [] where Geometry.distance(pool[index], p) <= tolerance {
                        return index
                    }
                }
            }
            pool.append(p)
            cells[key(cx, cy), default: []].append(pool.count - 1)
            return pool.count - 1
        }

        var pieces: [(from: Int, to: Int)] = []
        var seen = Set<Int64>()
        for (i, (a, b)) in edges.enumerated() {
            let length = Geometry.distance(a, b)
            var ts: [CGFloat] = [0, 1]
            for (j, (c, d)) in edges.enumerated() where j != i {
                if let hit = Geometry.segmentIntersection(a, b, c, d) { ts.append(hit.ta) }
                // the ends of an edge lying on this one (overlapping faces)
                for q in [c, d] where Geometry.distance(from: q, toSegmentFrom: a, to: b) <= tolerance {
                    ts.append((q - a).dot(b - a) / (length * length))
                }
            }
            ts = ts.map { min(max($0, 0), 1) }.sorted()
            for k in 0..<(ts.count - 1) where (ts[k + 1] - ts[k]) * length > tolerance {
                let p = Geometry.lerp(a, b, ts[k]), q = Geometry.lerp(a, b, ts[k + 1])
                let middle = Geometry.midpoint(p, q)
                let normal = (q - p).normalized.perpendicular * (tolerance * 10)
                let left = inside(middle + normal), right = inside(middle - normal)
                guard left != right else { continue }
                // the region on the left of the piece
                let (from, to) = left ? (vertex(p), vertex(q)) : (vertex(q), vertex(p))
                guard from != to, seen.insert(Int64(from) << 32 | Int64(to)).inserted else { continue }
                pieces.append((from, to))
            }
        }

        // chain the pieces into loops
        var outgoing: [Int: [Int]] = [:]
        for (index, piece) in pieces.enumerated() { outgoing[piece.from, default: []].append(index) }
        var used = Array(repeating: false, count: pieces.count)
        var result: [[CGPoint]] = []
        for start in pieces.indices where !used[start] {
            var loop: [Int] = []
            var current = start
            while !used[current] {
                used[current] = true
                loop.append(pieces[current].from)
                if pieces[current].to == pieces[start].from { break }      // back at the start
                guard let next = outgoing[pieces[current].to]?.first(where: { !used[$0] }) else { break }
                current = next
            }
            guard pieces[current].to == pieces[start].from else { continue }      // not closed
            var points = loop.map { pool[$0] }
            // straight runs: a vertex in line with its neighbours is dropped
            var changed = true
            while changed && points.count > 3 {
                changed = false
                for k in points.indices {
                    let before = points[(k - 1 + points.count) % points.count], after = points[(k + 1) % points.count]
                    if Geometry.distance(from: points[k], toSegmentFrom: before, to: after) <= tolerance {
                        points.remove(at: k)
                        changed = true
                        break
                    }
                }
            }
            if points.count >= 3 { result.append(points) }
        }
        return result
    }
}
