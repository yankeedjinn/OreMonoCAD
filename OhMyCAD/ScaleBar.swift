//
//  ScaleBar.swift
//  OhMyCAD
//
//  Graphic scale bar and north arrow. Both are ordinary blocks drawn in mm on paper and inserted with the scale
//  “drawing units per paper mm”, so they have the same size on paper at any drawing scale.
//  The drawing is always drawn north-up (only the view and the drawing coordinates rotate), so north = +Y.
//

import Cocoa

enum AnnotationSymbols {
    /// Name of the north arrow block (an existing block of this name is used – it can be edited to change the look).
    static let northArrowName = "North Arrow"
    /// The scale bar is about this long on paper (mm).
    static let scaleBarTargetMM: CGFloat = 50
    /// Height of the bar and of its labels on paper (mm).
    static let barHeightMM: CGFloat = 2
    static let labelHeightMM: CGFloat = 2.5

    /// The north arrow: an arrowhead pointing up, half filled, with the letter N above it; base point = its center.
    static func northArrow() -> BlockDefinition {
        let tip = CGPoint(x: 0, y: 7), right = CGPoint(x: 3, y: -5), notch = CGPoint(x: 0, y: -2.5), left = CGPoint(x: -3, y: -5)
        let outline = Polyline(vertices: [tip, right, notch, left], closed: true, layer: "0")
        let fill = HatchEntity(loops: [[tip, right, notch]], pattern: .solid, angle: 0, scale: 1, layer: "0")
        let letter = TextEntity(position: CGPoint(x: 0, y: 8.5), text: "N", height: 3.5, layer: "0")
        letter.justify = .center
        return BlockDefinition(name: northArrowName, basePoint: .zero, entities: [fill, outline, letter],
                               note: "North arrow (mm on paper) – placed by the North Arrow tool")
    }

    /// A round length close to the target: 1, 2 or 5 × 10ⁿ meters.
    static func niceLength(near meters: CGFloat) -> CGFloat {
        guard meters > 0, meters.isFinite else { return 1 }
        let exponent = floor(log10(meters))
        let base = pow(10, exponent)
        let candidates = [1, 2, 5, 10].map { CGFloat($0) * base }
        return candidates.min { abs(log($0 / meters)) < abs(log($1 / meters)) } ?? base
    }

    /// The scale bar for the given scale: `metersPerPaperMM` = how many meters of the model one mm of paper shows.
    /// Base point = the lower left corner (the “0” end).
    static func scaleBar(metersPerPaperMM: CGFloat, scaleTitle: String) -> BlockDefinition {
        let total = niceLength(near: scaleBarTargetMM * metersPerPaperMM)
        let base = pow(10, floor(log10(total) + 1e-9))
        let leading = Int((total / base).rounded())
        // 1 → five parts of 0.2, 2 → four parts of 0.5, 5 → five parts of 1 (× 10ⁿ)
        let parts = leading == 2 ? 4 : 5
        let lengthMM = total / metersPerPaperMM
        let step = lengthMM / CGFloat(parts)
        let unit = labelUnit(for: total)

        var entities: [CADEntity] = []
        for i in 0..<parts {
            let x0 = step * CGFloat(i), x1 = step * CGFloat(i + 1)
            let corners = [CGPoint(x: x0, y: 0), CGPoint(x: x1, y: 0), CGPoint(x: x1, y: barHeightMM), CGPoint(x: x0, y: barHeightMM)]
            if i % 2 == 0 {
                entities.append(HatchEntity(loops: [corners], pattern: .solid, angle: 0, scale: 1, layer: "0"))
            }
            entities.append(Polyline(vertices: corners, closed: true, layer: "0"))
        }
        for i in 0...parts {
            let value = total * CGFloat(i) / CGFloat(parts) / unit.meters
            let text = format(value) + (i == parts ? " " + unit.name : "")
            let label = TextEntity(position: CGPoint(x: step * CGFloat(i), y: barHeightMM + 1.2), text: text,
                                   height: labelHeightMM, layer: "0")
            label.justify = .center
            entities.append(label)
        }
        return BlockDefinition(name: "Scale Bar \(scaleTitle)", basePoint: .zero, entities: entities,
                               note: "Scale bar \(scaleTitle), 0–\(format(total / unit.meters)) \(unit.name) (mm on paper)")
    }

    /// The unit of the labels: km, m, cm or mm by the length of the bar.
    private static func labelUnit(for meters: CGFloat) -> (name: String, meters: CGFloat) {
        if meters >= 1000 { return ("km", 1000) }
        if meters >= 1 { return ("m", 1) }
        if meters >= 0.01 { return ("cm", 0.01) }
        return ("mm", 0.001)
    }

    /// A label number with the decimal separator of the system settings (up to 2 decimals).
    private static func format(_ value: CGFloat) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: Double(value))) ?? String(format: "%g", Double(value))
    }
}
