//
//  RevisionCloud.swift
//  OhMyCAD
//
//  Revision cloud (like REVCLOUD in AutoCAD): a closed polyline of outward arcs that marks a changed part of a drawing.
//  The result is an ordinary polyline with arc segments – it can be edited, offset, exported to DXF, etc.
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
