//
//  ToolIcons.swift
//  OhMyCAD
//
//  Tool icons drawn in code: bold strokes with rounded ends, few details, readable at 22 pt.
//  No image files – each icon is a few lines in a 24 × 24 grid (y axis up).
//  Two colors: what the tool creates or changes is drawn in the accent color, the rest in gray
//  (dashed = what disappears or only helps, dot = a clicked point, ring = the first of several clicked points).
//  image(...) returns a one-color template (menus); colored(_:selected:) gives the tool panel
//  the two-color version, or a one-color dark/white one for the selected button.
//

import Cocoa

enum ToolIcons {
    private static var cache: [String: NSImage] = [:]

    /// How each icon was drawn, so it can be drawn again in color.
    private struct Painting {
        let size: CGFloat
        let bold: Bool
        let paint: (IconPainter) -> Void
    }
    private static var paintings: [ObjectIdentifier: Painting] = [:]
    private static var coloredCache: [String: NSImage] = [:]

    /// Tool icon at a given size (points). Drawn once, then taken from the cache.
    static func image(for tool: DrawingTool, size: CGFloat) -> NSImage {
        let key = "\(tool.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(tool, size: size)
        cache[key] = image
        return image
    }

    /// Icon for an arc construction method (ring = the starting point).
    static func image(for method: ArcMethod, size: CGFloat) -> NSImage {
        let key = "arc\(method.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: method.title) { drawArc(method, $0) }
        cache[key] = image
        return image
    }

    /// Hand-drawn icon of a built-in hatch pattern (nil = the pattern has none, a preview is used).
    static func image(forPatternNamed name: String, size: CGFloat) -> NSImage? {
        guard let icon = PatternIcon(name: name) else { return nil }
        let key = "hatch-\(name)-\(size)"
        if let cached = cache[key] { return cached }
        // patterns stay thin – the icon shows the pattern itself
        let image = render(size: size, description: name, bold: false) { drawPattern(icon, $0) }
        cache[key] = image
        return image
    }

    /// Built-in patterns that have a hand-drawn icon.
    enum PatternIcon {
        case solid, lines, cross, dots, brick

        init?(name: String) {
            switch name {
            case HatchPattern.solid.name: self = .solid
            case "Lines": self = .lines
            case "Cross-hatch": self = .cross
            case "Dots": self = .dots
            case "Brick": self = .brick
            default: return nil
            }
        }
    }

    /// Two-color version of an icon made here (nil for any other image).
    /// selected = the icon sits on the accent-colored button: one color that reads on it.
    static func colored(_ image: NSImage, selected: Bool) -> NSImage? {
        guard let painting = paintings[ObjectIdentifier(image)] else { return nil }
        let base = resolved(selected ? Theme.selectedInk : Theme.iconBase)
        let accent = resolved(selected ? Theme.selectedInk : Theme.accent)
        let key = "\(ObjectIdentifier(image).hashValue)-\(hex(base))-\(hex(accent))"
        if let cached = coloredCache[key] { return cached }
        let result = bitmap(size: painting.size, base: base, accent: accent, bold: painting.bold, painting.paint)
        result.accessibilityDescription = image.accessibilityDescription
        coloredCache[key] = result
        return result
    }

    private static func resolved(_ color: NSColor) -> NSColor {
        return color.usingColorSpace(.sRGB) ?? color
    }

    private static func hex(_ color: NSColor) -> String {
        guard let c = color.usingColorSpace(.sRGB) else { return color.description }
        return String(format: "%02x%02x%02x%02x", Int(c.redComponent * 255), Int(c.greenComponent * 255),
                      Int(c.blueComponent * 255), Int(c.alphaComponent * 255))
    }

    private static func render(_ tool: DrawingTool, size: CGFloat) -> NSImage {
        return render(size: size, description: tool.title) { draw(tool, $0) }
    }

    /// One-color template (the system gives it its color); remembers how to draw it in color.
    private static func render(size: CGFloat, description: String, bold: Bool = true,
                               _ paint: @escaping (IconPainter) -> Void) -> NSImage {
        let image = bitmap(size: size, base: .black, accent: .black, bold: bold, paint)
        image.isTemplate = true
        image.accessibilityDescription = description
        paintings[ObjectIdentifier(image)] = Painting(size: size, bold: bold, paint: paint)
        return image
    }

    private static func bitmap(size: CGFloat, base: NSColor, accent: NSColor, bold: Bool,
                               _ paint: (IconPainter) -> Void) -> NSImage {
        let pixelScale: CGFloat = 3     // sharp on Retina displays too
        let pixels = Int((size * pixelScale).rounded(.up))
        let image = NSImage(size: NSSize(width: size, height: size))
        guard pixels > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        paint(IconPainter(scale: CGFloat(pixels) / 24, base: base, accent: accent, bold: bold))
        NSGraphicsContext.current = previous

        if let cgImage = context.makeImage() {
            let representation = NSBitmapImageRep(cgImage: cgImage)
            representation.size = NSSize(width: size, height: size)
            image.addRepresentation(representation)
        }
        return image
    }

    private static func draw(_ tool: DrawingTool, _ p: IconPainter) {
        switch tool {
        case .select:
            p.polyline([(5.5, 21), (5.5, 3.5), (10, 8), (13, 2.5), (16, 3.8), (13.2, 9.3), (19, 9.6)], closed: true)
        case .line:
            p.line(4.5, 4.5, 19.5, 19.5, accent: true)
            p.dot(4.5, 4.5)
            p.dot(19.5, 19.5)
        case .xline:
            drawXLine(.twoPoints, p)
        case .circle:
            p.circle(12, 12, 8.8, accent: true)
            p.dot(12, 12)
        case .arc:
            // the default method – the panel button shows the chosen one
            drawArc(.threePoint, p)
        case .polygon:
            p.polyline(hexagon(12, 12, 9.5), closed: true, accent: true)
            p.dot(12, 12)
        case .ellipse:
            p.ellipse(12, 12, 9.5, 5.5, angle: 25, accent: true)
            p.dot(12, 12)
        case .stretch:
            // a rectangle whose right part is stretched to the right
            p.polyline([(11, 5), (3, 5), (3, 14), (11, 14)])
            p.polyline([(11, 5), (21, 5), (21, 14), (11, 14)], accent: true)
            p.line(12, 19.5, 18.5, 19.5)
            p.arrowhead(19.2, 19.5, 1, 0)
        case .measure:
            drawMeasure(.distance, p)
        case .array:
            drawArray(.rectangular, p)
        case .zoomIn:
            drawMagnifier(p)
            p.line(6.5, 14, 13.5, 14)
            p.line(10, 10.5, 10, 17.5)
        case .zoomOut:
            drawMagnifier(p)
            p.line(6.5, 14, 13.5, 14)
        case .zoomExtents:
            // four corners, “everything in the window”, and a small magnifier
            drawCorners(p)
            p.circle(11, 13, 4.5)
            p.line(14.2, 9.8, 17, 7)
        case .zoomSelected:
            // four corners around a selected shape
            drawCorners(p)
            p.rect(8, 8, 8, 8, accent: true)
        case .zoomWindow:
            drawMagnifier(p)
            p.rect(7, 11, 6, 6, accent: true)
        case .blockCreate:
            // shapes enclosed in a dashed block frame, a plus at the base point
            p.rect(5, 5, 16.5, 16.5, dashed: true, accent: true)
            p.circle(11.5, 15.5, 3)
            p.polyline([(13.5, 8.5), (18.5, 8.5), (16, 13)], closed: true)
            p.line(1.5, 4.5, 7.5, 4.5)
            p.line(4.5, 1.5, 4.5, 7.5)
        case .blockInsert:
            // the same block and an arrow to its base point
            p.rect(8, 8, 13.5, 13.5, accent: true)
            p.circle(12.9, 16.6, 2.4)
            p.polyline([(14.8, 10.9), (19, 10.9), (16.9, 14.5)], closed: true)
            p.line(2.5, 2.5, 5.2, 5.2)
            p.arrowhead(6, 6, 0.707, 0.707)
        case .image:
            // a picture frame with mountains and the sun
            p.rect(3, 4.5, 18, 15)
            p.polyline([(3, 8), (9, 14), (13, 10), (15.5, 12.5), (21, 7)], accent: true)
            p.dot(16, 15.5, accent: true)
        case .xref:
            // sheet with a folded corner and a paper clip (reference to another drawing)
            p.polyline([(5, 3), (5, 21), (15, 21), (19, 17), (19, 3)], closed: true)
            p.polyline([(15, 21), (15, 17), (19, 17)])
            p.arc(10, 10, 2.5, from: 90, to: 270, accent: true)
            p.arc(14, 10, 2.5, from: -90, to: 90, accent: true)
            p.line(10, 12.5, 14, 12.5, accent: true)
            p.line(10, 7.5, 14, 7.5, accent: true)
        case .rectangle:
            p.rect(3.5, 5.5, 17, 13, accent: true)
            p.dot(3.5, 5.5)
            p.dot(20.5, 18.5)
        case .polyline:
            p.polyline([(3.5, 6), (9, 18), (15, 7), (20.5, 17)], accent: true)
            p.dot(3.5, 6)
            p.dot(20.5, 17)
        case .spline:
            p.curve([(3.5, 7), (7, 20), (11, 20), (12, 12), (13, 4), (17, 4), (20.5, 17)], accent: true)
            p.dot(3.5, 7)
            p.dot(20.5, 17)
        case .wall:
            // an L-shaped wall: both faces with the mitered corner, the clicked line dashed inside
            p.polyline([(3, 21), (3, 3), (21, 3), (21, 9), (9, 9), (9, 21)], closed: true, accent: true)
            p.polyline([(6, 21), (6, 6), (21, 6)], dashed: true)
        case .hatch:
            p.rect(3.5, 3.5, 17, 17)
            p.line(3.5, 10, 10, 3.5, accent: true)
            p.line(3.5, 20.5, 20.5, 3.5, accent: true)
            p.line(14, 20.5, 20.5, 14, accent: true)
        case .breakObject:
            // line with a gap: the piece between two points disappears
            p.line(2.5, 12, 8.5, 12)
            p.line(15.5, 12, 21.5, 12)
            p.line(8.5, 12, 15.5, 12, dashed: true, accent: true)
            p.dot(8.5, 12)
            p.dot(15.5, 12)
        case .breakAtPoint:
            // line split at one point (no gap)
            p.line(2.5, 12, 10, 12)
            p.line(14, 12, 21.5, 12)
            p.dot(12, 12, accent: true)
            p.line(12, 5, 12, 8.5, accent: true)
            p.line(12, 15.5, 12, 19, accent: true)
        case .trim:
            p.line(12, 2.5, 12, 21.5)
            p.line(2.5, 12, 12, 12)
            p.line(12, 12, 21.5, 12, dashed: true, accent: true)
        case .extend:
            p.line(20.5, 2.5, 20.5, 21.5)
            p.line(2.5, 12, 9, 12)
            p.line(9, 12, 17.5, 12, accent: true)
            p.arrowhead(17.8, 12, 1, 0, accent: true)
        case .fillet:
            p.line(4, 21, 4, 12)
            p.arc(12, 12, 8, from: 180, to: 270, accent: true)
            p.line(12, 4, 21, 4)
        case .chamfer:
            // two lines and a beveled corner
            p.line(4, 21, 4, 12)
            p.line(4, 12, 12, 4, accent: true)
            p.line(12, 4, 21, 4)
        case .offset:
            // a line, its parallel copy and the offset distance between them
            p.line(3, 13, 11, 21)
            p.line(11, 3, 21, 13, accent: true)
            p.line(8.4, 15.6, 13.1, 10.9)
            p.arrowhead(13.8, 10.2, 0.707, -0.707)
        case .editPoints:
            // polyline with two marked vertices
            p.polyline([(3, 16), (8.5, 6), (14, 14), (20.5, 4)])
            p.fill(6.5, 4, 4, 4, accent: true)
            p.fill(12, 12, 4, 4, accent: true)
        case .explode:
            // the sides of a rectangle flying apart from a burst in the middle
            p.line(5.5, 3.6, 14.8, 2.2, accent: true)
            p.line(20.2, 5.2, 21.8, 14.2, accent: true)
            p.line(18.4, 19.2, 9.6, 21.8, accent: true)
            p.line(3.6, 18.8, 2.2, 10.2, accent: true)
            p.dot(12, 12)
            p.line(14.3, 14.3, 15.8, 15.8)
            p.line(9.7, 14.3, 8.2, 15.8)
            p.line(14.3, 9.7, 15.8, 8.2)
            p.line(9.7, 9.7, 8.2, 8.2)
        case .matchProperties:
            // a brush that transfers “paint” to a line
            p.polyline([(13.2, 11.6), (20.6, 19), (19, 20.6), (11.6, 13.2)], closed: true)
            p.polyline([(11.6, 13.2), (8.6, 10.6), (4, 4), (10.6, 8.6), (13.2, 11.6)], closed: true)
            p.line(3, 20.5, 10.5, 20.5, accent: true)
        case .filter:
            // a funnel – only some objects get through
            p.polyline([(3, 20), (21, 20), (14, 11.5), (14, 4.5), (10, 2.5), (10, 11.5)], closed: true)
        case .join:
            // two chain links: the original piece and the joined one
            p.roundedRect(8.7, 8.7, 12, 6.4, radius: 3.2, angle: 45)
            p.roundedRect(15.3, 15.3, 12, 6.4, radius: 3.2, angle: 45, accent: true)
        case .powerTrim:
            // a fence drawn across two lines cuts both at the boundary
            p.line(11, 2.5, 11, 21.5)
            p.line(2.5, 7.5, 11, 7.5)
            p.line(11, 7.5, 21.5, 7.5, dashed: true, accent: true)
            p.line(2.5, 16.5, 11, 16.5)
            p.line(11, 16.5, 21.5, 16.5, dashed: true, accent: true)
            p.curve([(17.5, 21.5), (14, 16), (20, 12), (16.5, 2.5)])
        case .move:
            p.rect(12, 12, 9, 9, accent: true)
            p.line(3.5, 3.5, 9.4, 9.4)
            p.arrowhead(10, 10, 0.707, 0.707)
        case .copy:
            p.rect(3, 3, 9, 9)
            p.rect(12, 12, 9, 9, accent: true)
        case .rotate:
            // a rectangle turned about its corner, with the direction of the turn
            p.polyline([(7, 3.5), (19, 15.5), (14, 20.5), (2, 8.5)], closed: true, accent: true)
            p.arc(7, 3.5, 13, from: 0, to: 25)
            p.arrowhead(18.8, 9, -0.42, 0.91)
        case .scale:
            // the original, the enlarged copy, the direction of growth and the base point
            p.rect(3.5, 3.5, 17, 17, accent: true)
            p.rect(3.5, 3.5, 8.5, 8.5)
            p.line(13.5, 13.5, 16.6, 16.6)
            p.arrowhead(17.4, 17.4, 0.707, 0.707)
            p.dot(3.5, 3.5)
        case .mirror:
            p.line(12, 2.5, 12, 21.5, dashed: true)
            p.polyline([(2.5, 5), (9, 5), (9, 19)], closed: true)
            p.polyline([(21.5, 5), (15, 5), (15, 19)], closed: true, accent: true)
        case .dimLinear:
            p.line(4, 3, 4, 20)
            p.line(20, 3, 20, 20)
            p.line(4, 13, 20, 13, accent: true)
            p.arrowhead(4.3, 13, -1, 0, accent: true)
            p.arrowhead(19.7, 13, 1, 0, accent: true)
        case .dimAligned:
            p.dot(9, 3)
            p.dot(21, 15)
            p.line(7.939, 4.061, 3.697, 8.303)
            p.line(19.939, 16.061, 15.697, 20.303)
            p.line(4.757, 7.243, 16.757, 19.243, accent: true)
            p.arrowhead(4.957, 7.443, -0.707, -0.707, accent: true)
            p.arrowhead(16.557, 19.043, 0.707, 0.707, accent: true)
        case .dimContinue:
            // chain of two dimensions with oblique ticks
            for x in [3, 12, 21] as [CGFloat] { p.line(x, 6, x, 19) }
            p.line(2, 13, 22, 13, accent: true)
            for x in [3, 12, 21] as [CGFloat] { p.line(x - 1.8, 11.2, x + 1.8, 14.8, accent: true) }
        case .dimAngular:
            p.line(4, 5, 21, 5)
            p.line(4, 5, 14.927, 18.023)
            p.arc(4, 5, 11, from: 0, to: 50, accent: true)
            p.dot(4, 5)
        case .dimRadius:
            p.circle(11, 11, 8.5)
            p.dot(11, 11)
            p.line(11, 11, 17.2, 16.2, accent: true)
            p.arrowhead(17.511, 16.464, 0.766, 0.643, accent: true)
        case .dimDiameter:
            p.circle(12, 12, 8.5)
            p.line(5.9, 6.9, 18.1, 17.1, accent: true)
            p.arrowhead(18.511, 17.464, 0.766, 0.643, accent: true)
            p.arrowhead(5.489, 6.536, -0.766, -0.643, accent: true)
        case .leader:
            p.line(4, 4, 10, 14, accent: true)
            p.arrowhead(4, 4, -0.514, -0.857, accent: true)
            p.line(10, 14, 12.5, 14, accent: true)
            p.line(15, 16.5, 21, 16.5)
            p.line(15, 11.5, 19.5, 11.5)
        case .text:
            drawText(.simple, p)
        case .scaleBar:
            // a bar of alternating filled and empty parts with ticks for the labels
            p.rect(2.5, 9, 19, 5)
            p.fill(2.5, 9, 4.75, 5, accent: true)
            p.fill(12, 9, 4.75, 5, accent: true)
            p.line(2.5, 17, 2.5, 20)
            p.line(12, 17, 12, 20)
            p.line(21.5, 17, 21.5, 20)
        case .northArrow:
            // an arrowhead pointing up, its right half filled
            p.polyline([(12, 21.5), (17.5, 3), (12, 8), (6.5, 3)], closed: true)
            p.fillTriangle((12, 21.5), (17.5, 3), (12, 8), accent: true)
        case .roomLabel:
            // a room with its name and, below it, the area
            p.rect(3, 3, 18, 18)
            p.line(7, 14, 17, 14, accent: true)
            p.line(8.5, 9, 15.5, 9, accent: true)
        case .revisionCloud:
            drawCloud([(4, 6), (20, 6), (20, 18), (4, 18)], step: 4, p)
        case .wipeout:
            // a hatched square with a clear area in the middle
            p.rect(3.5, 3.5, 17, 17)
            p.line(3.5, 7.5, 7.5, 3.5)
            p.line(16.5, 20.5, 20.5, 16.5)
            p.rect(7, 8.5, 10, 7, accent: true)
        case .hatchRebuild:
            // hatched “L” shape and a circular arrow (new boundary)
            p.polyline([(3, 3), (14, 3), (14, 8), (8, 8), (8, 14), (3, 14)], closed: true)
            p.line(3, 8, 8, 3, accent: true)
            p.line(3, 13, 13, 3, accent: true)
            p.arc(16.5, 15.5, 5, from: 200, to: 470)
            p.arrowhead(14.79, 20.2, -0.94, -0.34)
        case .hatchCut:
            // hatched wall with a cut-out opening (dashed rectangle)
            p.rect(2.5, 7, 19, 10)
            p.line(2.5, 12, 7.5, 7)
            p.line(16.5, 17, 21.5, 12)
            p.rect(9.5, 4, 5, 16, dashed: true, accent: true)
        }
    }

    /// Revision cloud: 120° arcs bulging outward along a counterclockwise outline (as RevisionCloud draws them).
    private static func drawCloud(_ outline: [(CGFloat, CGFloat)], step: CGFloat, _ p: IconPainter) {
        let half = CGFloat.pi / 3
        for i in 0..<outline.count {
            let a = outline[i], b = outline[(i + 1) % outline.count]
            let length = hypot(b.0 - a.0, b.1 - a.1)
            let parts = max(1, Int((length / step).rounded()))
            let chord = length / CGFloat(parts)
            let ux = (b.0 - a.0) / length, uy = (b.1 - a.1) / length
            for k in 0..<parts {
                let sx = a.0 + ux * chord * CGFloat(k), sy = a.1 + uy * chord * CGFloat(k)
                // the center lies inside (left of the direction of travel)
                let h = chord / 2 / tan(half)
                let cx = sx + ux * chord / 2 - uy * h, cy = sy + uy * chord / 2 + ux * h
                let start = atan2(sy - cy, sx - cx) * 180 / .pi
                p.arc(cx, cy, chord / 2 / sin(half), from: start, to: start + 120, accent: true)
            }
        }
    }

    /// Magnifier: ring at top left, handle down to the right.
    private static func drawMagnifier(_ p: IconPainter) {
        p.circle(10, 14, 7)
        p.line(15, 9, 21, 3)
    }

    /// Four corner brackets of the window.
    private static func drawCorners(_ p: IconPainter) {
        p.polyline([(2.5, 7.5), (2.5, 2.5), (7.5, 2.5)])
        p.polyline([(16.5, 2.5), (21.5, 2.5), (21.5, 7.5)])
        p.polyline([(21.5, 16.5), (21.5, 21.5), (16.5, 21.5)])
        p.polyline([(7.5, 21.5), (2.5, 21.5), (2.5, 16.5)])
    }

    /// Dimension terminator icon (menu of the dimension tools).
    static func image(for style: DimArrowStyle, size: CGFloat) -> NSImage {
        let key = "dimend-\(style.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: style.title) { p in
            p.line(4, 7, 4, 19)
            p.line(20, 7, 20, 19)
            p.line(4, 12, 20, 12)
            for (x, dir) in [(CGFloat(4), CGFloat(-1)), (CGFloat(20), CGFloat(1))] {
                switch style {
                case .arrow:
                    p.fillTriangle((x, 12), (x - dir * 5, 14), (x - dir * 5, 10), accent: true)
                case .open:
                    p.polyline([(x - dir * 4.5, 14.5), (x, 12), (x - dir * 4.5, 9.5)], accent: true)
                case .oblique:
                    p.line(x - 2.2, 9.8, x + 2.2, 14.2, accent: true)
                case .architectural:
                    p.line(x - 2.2, 9.6, x + 2.2, 14.4, accent: true)
                    p.line(x - 1.6, 9.6, x + 2.8, 14.4, accent: true)
                case .dot:
                    p.dot(x, 12, accent: true)
                case .none:
                    break
                }
            }
        }
        cache[key] = image
        return image
    }

    /// Array kind icon (menu of the Array tool).
    static func image(for kind: ArrayKind, size: CGFloat) -> NSImage {
        let key = "array\(kind.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: kind.title) { drawArray(kind, $0) }
        cache[key] = image
        return image
    }

    private static func drawArray(_ kind: ArrayKind, _ p: IconPainter) {
        switch kind {
        case .rectangular:
            // the original (filled) and its copies in rows and columns
            for row in 0..<2 {
                for column in 0..<2 {
                    let x = 3 + CGFloat(column) * 10.5, y = 3 + CGFloat(row) * 10.5
                    if row == 0 && column == 0 { p.fill(x, y, 7.5, 7.5) } else { p.rect(x, y, 7.5, 7.5, accent: true) }
                }
            }
        case .polar:
            p.circle(12, 12, 7.5, dashed: true)
            for k in 0..<6 {
                let a = CGFloat(k) * .pi / 3 + .pi / 2
                let x = 12 + 7.5 * cos(a), y = 12 + 7.5 * sin(a)
                if k == 0 { p.fill(x - 2.2, y - 2.2, 4.4, 4.4) } else { p.rect(x - 2, y - 2, 4, 4, accent: true) }
            }
            p.dot(12, 12)
        }
    }

    /// Hexagon corners (point up) for the polygon icons.
    private static func hexagon(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, rotation: CGFloat = 90) -> [(CGFloat, CGFloat)] {
        return (0..<6).map { i in
            let a = (rotation + CGFloat(i) * 60) * .pi / 180
            return (cx + r * cos(a), cy + r * sin(a))
        }
    }

    /// Icon for the polygon input method (menu of the Circle button).
    static func image(for method: PolygonMethod, size: CGFloat) -> NSImage {
        let key = "polygon\(method.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: method.title) { p in
            switch method {
            case .inscribed:
                // corners on the circle: center → corner
                p.circle(12, 12, 9, dashed: true)
                p.polyline(hexagon(12, 12, 9), closed: true, accent: true)
                p.dot(12, 12)
                p.dot(12, 21)
            case .circumscribed:
                // sides touch the circle: center → side midpoint
                let r: CGFloat = 9.5
                p.circle(12, 12, r * cos(.pi / 6), dashed: true)
                p.polyline(hexagon(12, 12, r, rotation: 0), closed: true, accent: true)
                p.dot(12, 12)
                p.dot(12, 12 + r * cos(.pi / 6))
            case .edge:
                // two given corners of one side, the polygon above it
                let corners = hexagon(12, 11, 8.5, rotation: 30)
                p.polyline(corners, closed: true, accent: true)
                p.line(corners[3].0, corners[3].1, corners[4].0, corners[4].1)
                p.dot(corners[3].0, corners[3].1)
                p.dot(corners[4].0, corners[4].1)
            }
        }
        cache[key] = image
        return image
    }

    /// Construction line method icon.
    static func image(for kind: XLineKind, size: CGFloat) -> NSImage {
        let key = "xline\(kind.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: kind.title) { drawXLine(kind, $0) }
        cache[key] = image
        return image
    }

    /// Construction line: a line across the whole icon (infinite), dashed – and how it is entered.
    private static func drawXLine(_ kind: XLineKind, _ p: IconPainter) {
        switch kind {
        case .twoPoints:
            p.line(1.5, 3.5, 22.5, 20.5, dashed: true, accent: true)
            p.dot(8, 8.76)
            p.dot(16, 15.24)
        case .horizontal:
            p.line(1, 10, 23, 10, dashed: true, accent: true)
            p.dot(12, 10)
            p.line(12, 14.5, 12, 20)
            p.line(9.5, 17.2, 14.5, 17.2)
        case .vertical:
            p.line(10, 1, 10, 23, dashed: true, accent: true)
            p.dot(10, 12)
            p.line(14.5, 12, 20, 12)
            p.line(17.2, 9.5, 17.2, 14.5)
        case .angle:
            p.line(1.5, 6, 22.5, 18, dashed: true, accent: true)
            p.line(4, 7.4, 20, 7.4)
            p.arc(4, 7.4, 10, from: 0, to: 29.7)
        }
    }

    /// Measurement kind icon (menu of the Measure tool).
    static func image(for kind: MeasureKind, size: CGFloat) -> NSImage {
        let key = "measure\(kind.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: kind.title) { drawMeasure(kind, $0) }
        cache[key] = image
        return image
    }

    /// Measuring creates nothing: the measured quantity is in the accent color.
    private static func drawMeasure(_ kind: MeasureKind, _ p: IconPainter) {
        switch kind {
        case .distance:
            // ruler with ticks
            p.polyline([(2.5, 7.5), (21.5, 7.5), (21.5, 16), (2.5, 16)], closed: true)
            for x in [6, 12, 18] as [CGFloat] { p.line(x, 16, x, 10.5, accent: true) }
            for x in [9, 15] as [CGFloat] { p.line(x, 16, x, 13, accent: true) }
        case .angle:
            p.line(4, 5, 21, 5)
            p.line(4, 5, 15, 19)
            p.arc(4, 5, 10, from: 0, to: 52, accent: true)
        case .radius:
            p.circle(11, 11, 8)
            p.line(11, 11, 16.2, 16.2, accent: true)
            p.arrowhead(16.66, 16.66, 0.707, 0.707, accent: true)
            p.dot(11, 11)
        case .areaPoints:
            p.polyline([(4, 5), (19, 4), (20, 16), (9, 20)], closed: true)
            p.line(7, 12, 13, 5.5, accent: true)
            p.line(10, 17, 18, 9, accent: true)
            p.dot(4, 5)
            p.dot(19, 4)
            p.dot(20, 16)
            p.dot(9, 20)
        case .areaBoundary:
            p.rect(3.5, 3.5, 17, 17)
            p.line(3.5, 11, 11, 3.5, accent: true)
            p.line(13, 20.5, 20.5, 13, accent: true)
            p.dot(12, 12)
        case .areaObject:
            p.circle(12, 12, 8.5)
            p.line(6, 18, 18, 6, accent: true)
            p.line(4.5, 12.5, 12.5, 4.5, accent: true)
            p.line(11.5, 19.5, 19.5, 11.5, accent: true)
        case .point:
            p.line(12, 2.5, 12, 8)
            p.line(12, 16, 12, 21.5)
            p.line(2.5, 12, 8, 12)
            p.line(16, 12, 21.5, 12)
            p.dot(12, 12, accent: true)
        case .length:
            p.curve([(3, 7), (7, 18), (12, 18), (13, 12), (14, 6), (18, 6), (21, 15)])
            p.line(3.5, 2.5, 20.5, 2.5, accent: true)
            p.arrowhead(3, 2.5, -1, 0, accent: true)
            p.arrowhead(21, 2.5, 1, 0, accent: true)
        }
    }

    /// Text kind icon (menu of the Text tool).
    static func image(for kind: TextKind, size: CGFloat) -> NSImage {
        let key = "text\(kind.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: kind.title) { drawText(kind, $0) }
        cache[key] = image
        return image
    }

    private static func drawText(_ kind: TextKind, _ p: IconPainter) {
        switch kind {
        case .simple:
            // a large serif T
            p.line(4.5, 20, 19.5, 20, accent: true)
            p.line(4.5, 20, 4.5, 17, accent: true)
            p.line(19.5, 20, 19.5, 17, accent: true)
            p.line(12, 20, 12, 4, accent: true)
            p.line(9, 4, 15, 4, accent: true)
        case .multiline:
            // a smaller T and paragraph lines in a frame
            p.rect(2.5, 2.5, 19, 19, dashed: true)
            p.line(6, 17.5, 12, 17.5, accent: true)
            p.line(9, 17.5, 9, 11.5, accent: true)
            p.line(14.5, 17.5, 18, 17.5, accent: true)
            p.line(6, 7, 18, 7, accent: true)
        case .formatted:
            // T and next to it a slanted, underlined “a” (font, style)
            p.line(3, 20, 13, 20, accent: true)
            p.line(8, 20, 8, 6.5, accent: true)
            p.circle(16.5, 9.5, 3, accent: true)
            p.line(19.5, 12.5, 19, 6.5, accent: true)
            p.line(3, 3, 21, 3)
        }
    }

    private static func drawArc(_ method: ArcMethod, _ p: IconPainter) {
        switch method {
        case .threePoint:
            p.arc(12, 6, 9.5, from: 12, to: 168, accent: true)
            p.dot(12, 15.5)
            p.dot(2.71, 7.98)
            p.ring(21.29, 7.98)
        case .startCenterEnd:
            p.arc(12, 6, 9.5, from: 12, to: 168, accent: true)
            p.line(12, 6, 21.29, 7.98, dashed: true)
            p.line(12, 6, 2.71, 7.98, dashed: true)
            p.dot(12, 6)
            p.dot(2.71, 7.98)
            p.ring(21.29, 7.98)
        case .startCenterAngle:
            p.arc(12, 6, 9.5, from: 12, to: 168, accent: true)
            p.line(12, 6, 21.29, 7.98, dashed: true)
            p.line(12, 6, 2.71, 7.98, dashed: true)
            p.arc(12, 6, 4, from: 12, to: 168)
            p.dot(12, 6)
            p.ring(21.29, 7.98)
        case .centerStartEnd:
            p.arc(12, 6, 9.5, from: 12, to: 168, accent: true)
            p.line(12, 6, 21.29, 7.98, dashed: true)
            p.line(12, 6, 2.71, 7.98, dashed: true)
            p.dot(21.29, 7.98)
            p.dot(2.71, 7.98)
            p.ring(12, 6)
        case .centerStartAngle:
            p.arc(12, 6, 9.5, from: 12, to: 168, accent: true)
            p.line(12, 6, 21.29, 7.98, dashed: true)
            p.line(12, 6, 2.71, 7.98, dashed: true)
            p.arc(12, 6, 4, from: 12, to: 168)
            p.dot(21.29, 7.98)
            p.ring(12, 6)
        case .startEndRadius:
            p.arc(12, 6, 9.5, from: 12, to: 168, accent: true)
            p.line(21.29, 7.98, 2.71, 7.98, dashed: true)
            p.line(12, 6, 12, 14.4)
            p.arrowhead(12, 15.2, 0, 1)
            p.dot(2.71, 7.98)
            p.ring(21.29, 7.98)
        case .startEndAngle:
            p.arc(12, 6, 9.5, from: 12, to: 168, accent: true)
            p.line(21.29, 7.98, 2.71, 7.98, dashed: true)
            p.arc(12, 6, 4, from: 12, to: 168)
            p.dot(2.71, 7.98)
            p.ring(21.29, 7.98)
        }
    }

    private static func drawPattern(_ pattern: PatternIcon, _ p: IconPainter) {
        switch pattern {
        case .solid:
            p.rect(4.5, 4.5, 15, 15)
            p.fill(4.5, 4.5, 15, 15)
        case .lines:
            p.rect(4.5, 4.5, 15, 15)
            p.line(14.5, 4.5, 19.5, 9.5)
            p.line(9.5, 4.5, 19.5, 14.5)
            p.line(4.5, 4.5, 19.5, 19.5)
            p.line(4.5, 9.5, 14.5, 19.5)
            p.line(4.5, 14.5, 9.5, 19.5)
        case .cross:
            p.rect(4.5, 4.5, 15, 15)
            p.line(14.5, 4.5, 19.5, 9.5)
            p.line(9.5, 4.5, 19.5, 14.5)
            p.line(4.5, 4.5, 19.5, 19.5)
            p.line(4.5, 9.5, 14.5, 19.5)
            p.line(4.5, 14.5, 9.5, 19.5)
            p.line(4.5, 9.5, 9.5, 4.5)
            p.line(4.5, 14.5, 14.5, 4.5)
            p.line(4.5, 19.5, 19.5, 4.5)
            p.line(9.5, 19.5, 19.5, 9.5)
            p.line(14.5, 19.5, 19.5, 14.5)
        case .dots:
            p.rect(4.5, 4.5, 15, 15)
            p.dot(8, 8)
            p.dot(8, 12)
            p.dot(8, 16)
            p.dot(12, 8)
            p.dot(12, 12)
            p.dot(12, 16)
            p.dot(16, 8)
            p.dot(16, 12)
            p.dot(16, 16)
        case .brick:
            p.rect(4.5, 4.5, 15, 15)
            p.line(4.5, 9.5, 19.5, 9.5)
            p.line(4.5, 14.5, 19.5, 14.5)
            p.line(12, 4.5, 12, 9.5)
            p.line(8.5, 9.5, 8.5, 14.5)
            p.line(15.5, 9.5, 15.5, 14.5)
            p.line(12, 14.5, 12, 19.5)
        }
    }
}

/// Drawing in a 24 × 24 grid. accent: true draws in the accent color (what the tool creates or changes).
struct IconPainter {
    let scale: CGFloat
    let base: NSColor
    let accent: NSColor
    private let lineWidth: CGFloat
    private let dash: [CGFloat]
    private let headLength: CGFloat
    private let headAngle: CGFloat = 38
    private let dotRadius: CGFloat
    private let ringRadius: CGFloat

    /// bold = tool icons (readable at 22 pt); thin = hatch pattern icons.
    init(scale: CGFloat, base: NSColor, accent: NSColor, bold: Bool) {
        self.scale = scale
        self.base = base
        self.accent = accent
        lineWidth = bold ? 2.2 : 1.45
        dash = bold ? [2.8, 2.6] : [2, 2.4]
        headLength = bold ? 4.2 : 3.4
        dotRadius = bold ? 2.0 : 1.35
        ringRadius = bold ? 2.6 : 2.4
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x * scale, y: y * scale)
    }

    private func color(_ isAccent: Bool) -> NSColor {
        return isAccent ? accent : base
    }

    private func stroke(_ path: NSBezierPath, dashed: Bool = false, accent isAccent: Bool = false) {
        color(isAccent).setStroke()
        path.lineWidth = lineWidth * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if dashed {
            var pattern = dash.map { $0 * scale }
            path.setLineDash(&pattern, count: pattern.count, phase: 0)
        }
        path.stroke()
    }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, dashed: Bool = false, accent: Bool = false) {
        let path = NSBezierPath()
        path.move(to: pt(x1, y1))
        path.line(to: pt(x2, y2))
        stroke(path, dashed: dashed, accent: accent)
    }

    func polyline(_ points: [(CGFloat, CGFloat)], closed: Bool = false, dashed: Bool = false, accent: Bool = false) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: pt(first.0, first.1))
        for point in points.dropFirst() { path.line(to: pt(point.0, point.1)) }
        if closed { path.close() }
        stroke(path, dashed: dashed, accent: accent)
    }

    /// Ellipse with semi-axes rx, ry rotated by an angle (degrees).
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat, accent: Bool = false) {
        let path = NSBezierPath(ovalIn: NSRect(x: -rx * scale, y: -ry * scale, width: 2 * rx * scale, height: 2 * ry * scale))
        var t = AffineTransform(translationByX: cx * scale, byY: cy * scale)
        t.rotate(byDegrees: angle)
        path.transform(using: t)
        stroke(path, accent: accent)
    }

    /// Rounded rectangle centered at (cx, cy), rotated by an angle (degrees).
    func roundedRect(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat, radius: CGFloat, angle: CGFloat, accent: Bool = false) {
        let path = NSBezierPath(roundedRect: NSRect(x: -w / 2 * scale, y: -h / 2 * scale, width: w * scale, height: h * scale),
                                xRadius: radius * scale, yRadius: radius * scale)
        var t = AffineTransform(translationByX: cx * scale, byY: cy * scale)
        t.rotate(byDegrees: angle)
        path.transform(using: t)
        stroke(path, accent: accent)
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, dashed: Bool = false, accent: Bool = false) {
        stroke(NSBezierPath(ovalIn: NSRect(x: (cx - r) * scale, y: (cy - r) * scale,
                                           width: 2 * r * scale, height: 2 * r * scale)), dashed: dashed, accent: accent)
    }

    /// Counterclockwise arc, angles in degrees.
    func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from start: CGFloat, to end: CGFloat, accent: Bool = false) {
        let path = NSBezierPath()
        path.appendArc(withCenter: pt(cx, cy), radius: r * scale, startAngle: start, endAngle: end, clockwise: false)
        stroke(path, accent: accent)
    }

    /// Connected cubic Bézier segments: [start, c1, c2, end, c1, c2, end, …].
    func curve(_ points: [(CGFloat, CGFloat)], accent: Bool = false) {
        guard points.count >= 4 else { return }
        let path = NSBezierPath()
        path.move(to: pt(points[0].0, points[0].1))
        var i = 1
        while i + 2 < points.count {
            path.curve(to: pt(points[i + 2].0, points[i + 2].1),
                       controlPoint1: pt(points[i].0, points[i].1),
                       controlPoint2: pt(points[i + 1].0, points[i + 1].1))
            i += 3
        }
        stroke(path, accent: accent)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dashed: Bool = false, accent: Bool = false) {
        stroke(NSBezierPath(rect: NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)),
               dashed: dashed, accent: accent)
    }

    /// Open arrow with its tip at (x, y) pointing along (dx, dy).
    func arrowhead(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat, accent: Bool = false) {
        let path = NSBezierPath()
        var wings: [NSPoint] = []
        for side in [1, -1] as [CGFloat] {
            let a = (180 + side * headAngle) * .pi / 180
            let vx = dx * cos(a) - dy * sin(a)
            let vy = dx * sin(a) + dy * cos(a)
            wings.append(pt(x + vx * headLength, y + vy * headLength))
        }
        path.move(to: wings[0])
        path.line(to: pt(x, y))
        path.line(to: wings[1])
        stroke(path, accent: accent)
    }

    /// Filled triangle (arrow).
    func fillTriangle(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ c: (CGFloat, CGFloat), accent: Bool = false) {
        let path = NSBezierPath()
        path.move(to: pt(a.0, a.1))
        path.line(to: pt(b.0, b.1))
        path.line(to: pt(c.0, c.1))
        path.close()
        color(accent).setFill()
        path.fill()
    }

    /// Filled rectangle.
    func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, accent: Bool = false) {
        color(accent).setFill()
        NSBezierPath(rect: NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)).fill()
    }

    /// Ring – marks the first of several clicked points.
    func ring(_ x: CGFloat, _ y: CGFloat, accent: Bool = false) {
        stroke(NSBezierPath(ovalIn: NSRect(x: (x - ringRadius) * scale, y: (y - ringRadius) * scale,
                                           width: 2 * ringRadius * scale, height: 2 * ringRadius * scale)), accent: accent)
    }

    /// Dot – a clicked point.
    func dot(_ x: CGFloat, _ y: CGFloat, accent: Bool = false) {
        color(accent).setFill()
        NSBezierPath(ovalIn: NSRect(x: (x - dotRadius) * scale, y: (y - dotRadius) * scale,
                                    width: 2 * dotRadius * scale, height: 2 * dotRadius * scale)).fill()
    }
}
