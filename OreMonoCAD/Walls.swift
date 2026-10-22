//
//  Walls.swift
//  OreMonoCAD
//
//  Wall drawn with a double line: you click the points of one line (the axis or a face of the wall) and the tool
//  draws both faces at the wall thickness, with mitered corners. The result is ordinary closed polylines –
//  an open wall is one outline (both faces and the ends), a closed wall gives two (the outer and the inner face).
//  Walls are not joined to each other automatically – Trim or MagicTrim cleans up where they meet.
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
