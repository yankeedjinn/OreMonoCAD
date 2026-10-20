//
//  RevisionCloud.swift
//  OhMyCAD
//
//  Revision cloud (like REVCLOUD in AutoCAD): a closed polyline of outward arcs that marks a changed part of a drawing.
//  The result is an ordinary polyline with arc segments – it can be edited, offset, exported to DXF, etc.
//  Properties recognizes a cloud by its arcs (all the same 120° bulge) and changes their size (Scale).
//

import Cocoa

enum RevisionCloud {
    /// How the outline is drawn: corner by corner, or as a rectangle from two corners.
    enum Shape {
        case polygon, rectangle
    }

    /// Central angle of each arc – 120° gives the familiar scalloped look.
    static let arcSweep: CGFloat = 2 * .pi / 3
    /// Default distance between the arc ends, in mm on paper.
    static let defaultArcSizeMM: CGFloat = 8
    /// Allowed range of the arc size (mm on paper).
    static let arcSizeRangeMM: ClosedRange<CGFloat> = 1...50
    /// Upper limit of arcs in one cloud (a huge outline with tiny arcs gets larger arcs instead).
    static let maximumArcs = 4000

    /// The cloud along a closed outline: every side is split into equal parts of about `arcSize`,
    /// each part becomes an arc that bulges outward. nil = the outline has no area.
    static func polyline(around outline: [CGPoint], arcSize: CGFloat, layer: String) -> Polyline? {
        // drop repeated points (also the last one if it closes the outline)
        var corners: [CGPoint] = []
        for point in outline where DrawingSafety.isFinite(point) {
            if let last = corners.last, Geometry.distance(last, point) < 1e-9 { continue }
            corners.append(point)
        }
        if corners.count > 1, let first = corners.first, let last = corners.last, Geometry.distance(first, last) < 1e-9 {
            corners.removeLast()
        }
        guard corners.count >= 3 else { return nil }
        let area = HatchEntity.signedArea(corners)
        guard abs(area) > 1e-12 else { return nil }

        var perimeter: CGFloat = 0
        for i in 0..<corners.count {
            perimeter += Geometry.distance(corners[i], corners[(i + 1) % corners.count])
        }
        guard perimeter > 0, arcSize > 0 else { return nil }
        let size = max(arcSize, perimeter / CGFloat(maximumArcs))

        var vertices: [CGPoint] = []
        for i in 0..<corners.count {
            let a = corners[i], b = corners[(i + 1) % corners.count]
            let parts = max(1, Int((Geometry.distance(a, b) / size).rounded()))
            for k in 0..<parts {
                vertices.append(a + (b - a) * (CGFloat(k) / CGFloat(parts)))
            }
        }
        // a positive bulge bulges to the right of the direction of travel: outward for a counterclockwise outline
        let bulge = Polyline.bulge(forSweep: area > 0 ? arcSweep : -arcSweep)
        return Polyline(vertices: vertices, closed: true, bulges: Array(repeating: bulge, count: vertices.count), layer: layer)
    }

    // MARK: Changing the arc size of a drawn cloud (Properties › Scale)

    /// Is the polyline a revision cloud – closed, with every segment the same 120° arc, as this tool draws it?
    /// Works for clouds from older drawings and from DXF too (nothing extra is stored).
    static func isCloud(_ polyline: Polyline) -> Bool {
        let n = polyline.vertices.count
        let bulge = Polyline.bulge(forSweep: arcSweep)
        guard polyline.closed, n >= 3, polyline.bulges.count >= n, let first = polyline.bulges.first,
              abs(abs(first) - bulge) < 1e-6 else { return false }
        return polyline.bulges.prefix(n).allSatisfy { abs($0 - first) < 1e-6 }
    }

    /// The sides of the outline the cloud was drawn around and how many arcs each has
    /// (a vertex in the middle of a straight run is not a corner).
    private static func sides(of polyline: Polyline) -> [(start: CGPoint, end: CGPoint, arcs: Int)] {
        let points = polyline.vertices
        let n = points.count
        let corners = (0..<n).filter { i in
            let incoming = points[i] - points[(i + n - 1) % n], outgoing = points[(i + 1) % n] - points[i]
            let cross = incoming.x * outgoing.y - incoming.y * outgoing.x
            return abs(cross) > 1e-6 * incoming.length * outgoing.length || incoming.dot(outgoing) <= 0
        }
        guard corners.count >= 3 else { return [] }
        return corners.indices.map { k -> (start: CGPoint, end: CGPoint, arcs: Int) in
            let i = corners[k], j = corners[(k + 1) % corners.count]
            return (points[i], points[j], (j - i + n) % n)
        }
    }

    /// The cloud's scale: its arc size compared with `unit` (the default arc at the drawing scale).
    /// Each side was split into a whole number of arcs, so a range of sizes gives the same cloud –
    /// the roundest number in that range is shown (a cloud drawn with the default arcs shows 1, not 0.97).
    static func scale(of polyline: Polyline, unit: CGFloat) -> CGFloat {
        let sides = self.sides(of: polyline)
        let arcs = sides.reduce(0) { $0 + $1.arcs }
        guard arcs > 0, unit > 0 else { return 1 }
        let perimeter = sides.reduce(CGFloat(0)) { $0 + Geometry.distance($1.start, $1.end) }
        let average = perimeter / CGFloat(arcs) / unit
        // sizes that split every side into the same number of arcs (see polyline(around:))
        var lower: CGFloat = 0, upper = CGFloat.infinity
        for side in sides {
            let length = Geometry.distance(side.start, side.end) / unit
            lower = max(lower, length / (CGFloat(side.arcs) + 0.5))
            if side.arcs > 1 { upper = min(upper, length / (CGFloat(side.arcs) - 0.5)) }
        }
        for step: CGFloat in [1, 0.1, 0.01, 0.001] {
            let first = (lower / step + 1e-9).rounded(.up), last = (upper / step - 1e-9).rounded(.down)
            guard first <= last else { continue }
            return min(max((average / step).rounded(), first), last) * step
        }
        return average
    }

    /// The same cloud with arcs of `arcSize` – the outline, layer and look stay. nil = not a cloud, or no change.
    static func rescaled(_ polyline: Polyline, arcSize: CGFloat) -> Polyline? {
        guard isCloud(polyline), arcSize > 0, arcSize.isFinite else { return nil }
        let outline = sides(of: polyline).map { $0.start }
        guard let cloud = self.polyline(around: outline, arcSize: arcSize, layer: polyline.layer),
              let copy = polyline.clone() as? Polyline else { return nil }
        if cloud.vertices.count == polyline.vertices.count,
           zip(cloud.vertices, polyline.vertices).allSatisfy({ Geometry.distance($0, $1) < 1e-9 }) { return nil }
        copy.vertices = cloud.vertices
        copy.bulges = cloud.bulges
        return copy
    }
}

extension AppSettings {
    /// Arc size of new revision clouds (mm on paper).
    static var revisionCloudArcMM: CGFloat {
        get {
            let value = UserDefaults.standard.object(forKey: "OhMyCAD.revisionCloudArc") as? Double
            return clampedArcSize(value.map { CGFloat($0) } ?? RevisionCloud.defaultArcSizeMM)
        }
        set { UserDefaults.standard.set(Double(clampedArcSize(newValue)), forKey: "OhMyCAD.revisionCloudArc") }
    }

    private static func clampedArcSize(_ value: CGFloat) -> CGFloat {
        let range = RevisionCloud.arcSizeRangeMM
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
