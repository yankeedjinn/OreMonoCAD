//
//  Wipeout.swift
//  OhMyCAD
//
//  Wipeout (like WIPEOUT in AutoCAD): an area filled with the background color that covers what lies below it,
//  so that a text or a dimension placed over a hatch or over lines stays readable.
//  At the same draw order a wipeout lies above lines and hatches but below texts and dimensions (DrawOrder).
//  Its frame is shown on screen only (to find and select it); it is not printed and not exported to DXF.
//

import Cocoa

final class WipeoutEntity: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var drawOrder = 0
    var groupID: UUID?

    /// Corners of the covered area (a closed outline, at least three corners).
    var vertices: [CGPoint]

    init(vertices: [CGPoint], layer: String = "0", color: NSColor? = nil) {
        self.vertices = vertices
        self.layer = layer
        self.color = color
    }

    /// A wipeout over a drawn outline – repeated corners are dropped. nil = the outline has no area.
    static func make(outline: [CGPoint], layer: String) -> WipeoutEntity? {
        var corners: [CGPoint] = []
        for point in outline where DrawingSafety.isFinite(point) {
            if let last = corners.last, Geometry.distance(last, point) < 1e-9 { continue }
            corners.append(point)
        }
        if corners.count > 1, let first = corners.first, let last = corners.last, Geometry.distance(first, last) < 1e-9 {
            corners.removeLast()
        }
        guard corners.count >= 3, abs(HatchEntity.signedArea(corners)) > 1e-12 else { return nil }
        return WipeoutEntity(vertices: corners, layer: layer)
    }

    /// The color it covers with: the drawing area on screen, white paper when plotted.
    static var fillColor: NSColor {
        return RenderMode.plotting ? .white : Theme.canvasBackground
    }

    var typeName: String { return "Wipeout" }

    var infoText: String {
        return String(format: "Wipeout\n%@\n\nCorners: %ld\nArea:    %.3f", commonInfo, vertices.count,
                      Double(abs(HatchEntity.signedArea(vertices))))
    }

    // MARK: CADEntity

    func makePath() -> CGPath {
        let path = CGMutablePath()
        guard vertices.count >= 3 else { return path }
        path.addLines(between: vertices)
        path.closeSubpath()
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        var t = transform
        let path = makePath()
        guard !path.isEmpty, let screenPath = path.copy(using: &t),
              DrawingSafety.isDrawable(screenPath.boundingBoxOfPath) else { return }
        context.saveGState()
        context.setFillColor(WipeoutEntity.fillColor.cgColor)
        context.addPath(screenPath)
        context.fillPath()
        context.restoreGState()
        // the frame only on screen
        if !RenderMode.plotting {
            strokeWorldPath(path, in: context, transform: transform, style: style)
        }
    }

    func boundingBox() -> CGRect {
        return HatchEntity.box(of: vertices)
    }

    /// 0 inside the area, otherwise the distance to its frame.
    func distance(to point: CGPoint) -> CGFloat {
        guard vertices.count >= 3 else { return .infinity }
        if HatchEntity.pointInPolygon(point, vertices) { return 0 }
        return vertices.indices.map { i in
            Geometry.distance(from: point, toSegmentFrom: vertices[i], to: vertices[(i + 1) % vertices.count])
        }.min() ?? .infinity
    }

    func snapPoints() -> [SnapPoint] {
        var result = vertices.map { SnapPoint(point: $0, type: .endpoint) }
        for i in vertices.indices {
            result.append(SnapPoint(point: Geometry.midpoint(vertices[i], vertices[(i + 1) % vertices.count]), type: .midpoint))
        }
        return result
    }

    func applyTransform(_ transform: CGAffineTransform) {
        vertices = vertices.map { $0.applying(transform) }
    }

    func clone() -> CADEntity {
        return copyStyle(to: WipeoutEntity(vertices: vertices, layer: layer, color: color))
    }

    /// Not a cutting edge or a boundary – hatches, trimming and room outlines ignore it.
    func primitives() -> [Primitive] { return [] }
}
