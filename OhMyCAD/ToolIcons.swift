//
//  ToolIcons.swift
//  OhMyCAD
//
//  Tool icons drawn in code in the style of SF Symbols (thin strokes, rounded ends).
//  No image files – each icon is a few lines in a 24 × 24 grid (y axis up).
//  The icons are “templates”: the system gives them their color (light/dark mode, selected button).
//

import Cocoa

enum ToolIcons {
    private static var cache: [String: NSImage] = [:]

    /// Tool icon at a given size (points). Drawn once, then taken from the cache.
    static func image(for tool: DrawingTool, size: CGFloat) -> NSImage {
        let key = "\(tool.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(tool, size: size)
        cache[key] = image
        return image
    }

    /// Icon for an arc construction method (circle = the starting point).
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
        let image = render(size: size, description: name) { drawPattern(icon, $0) }
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

    private static func render(_ tool: DrawingTool, size: CGFloat) -> NSImage {
        return render(size: size, description: tool.title) { draw(tool, $0) }
    }

    private static func render(size: CGFloat, description: String, _ paint: (IconPainter) -> Void) -> NSImage {
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
        NSColor.black.set()
        paint(IconPainter(scale: CGFloat(pixels) / 24))
        NSGraphicsContext.current = previous

        if let cgImage = context.makeImage() {
            let representation = NSBitmapImageRep(cgImage: cgImage)
            representation.size = NSSize(width: size, height: size)
            image.addRepresentation(representation)
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    private static func draw(_ tool: DrawingTool, _ p: IconPainter) {
        switch tool {
        case .select:
            p.polyline([(6, 20.5), (6, 4.5), (9.8, 8.3), (12.4, 2.8), (14.9, 3.9), (12.4, 9.3), (17.6, 9.5)], closed: true)
        case .line:
            p.line(5.5, 5.5, 18.5, 18.5)
            p.dot(5.5, 5.5)
            p.dot(18.5, 18.5)
        case .xline:
            drawXLine(.twoPoints, p)
        case .circle:
            p.circle(12, 12, 8)
            p.dot(12, 12)
        case .arc:
            p.arc(12, 5, 9.5, from: 25, to: 155)
            p.dot(20.61, 9.015)
            p.dot(3.39, 9.015)
            p.dot(12, 14.5)
        case .polygon:
            p.polyline(hexagon(12, 12, 9), closed: true)
            p.dot(12, 12)
        case .ellipse:
            p.ellipse(12, 12, 9, 5.2, angle: 25)
            p.dot(12, 12)
            p.line(12, 12, 20.16, 15.8, dashed: true)
        case .stretch:
            // a rectangle whose right side is “stretched” by a dashed window
            p.polyline([(10, 4), (3, 4), (3, 14), (10, 14)])
            p.polyline([(10, 4), (19, 4), (19, 14), (10, 14)], dashed: false)
            p.rect(15, 2, 7.5, 14.5, dashed: true)
            p.line(13, 19.5, 20.5, 19.5)
            p.arrowhead(21.3, 19.5, 1, 0)
        case .measure:
            drawMeasure(.distance, p)
        case .array:
            drawArray(.rectangular, p)
        case .zoomIn:
            drawMagnifier(p)
            p.line(7, 14.5, 13, 14.5)
            p.line(10, 11.5, 10, 17.5)
        case .zoomOut:
            drawMagnifier(p)
            p.line(7, 14.5, 13, 14.5)
        case .zoomExtents:
            // magnifier and four corners, “everything in the window”
            drawMagnifier(p)
            p.polyline([(2.5, 7), (2.5, 2.5), (7, 2.5)])
            p.polyline([(17, 2.5), (21.5, 2.5), (21.5, 7)])
            p.polyline([(2.5, 17), (2.5, 21.5), (7, 21.5)])
        case .zoomSelected:
            // magnifier, four corners and a small selected shape with grips
            drawMagnifier(p)
            p.polyline([(2.5, 7), (2.5, 2.5), (7, 2.5)])
            p.polyline([(17, 2.5), (21.5, 2.5), (21.5, 7)])
            p.polyline([(2.5, 17), (2.5, 21.5), (7, 21.5)])
            p.rect(7.5, 12, 5, 5, dashed: true)
        case .zoomWindow:
            drawMagnifier(p)
            p.rect(7.2, 11.7, 5.6, 5.6, dashed: true)
        case .blockCreate:
            // shapes enclosed in a dashed block frame with a base point
            p.rect(2.5, 2.5, 19, 19, dashed: true)
            p.circle(9, 14, 3.5)
            p.polyline([(12.5, 6), (18.5, 6), (15.5, 11.5)], closed: true)
            p.ring(5, 5)
        case .blockInsert:
            // block and an arrow to the insertion point
            p.rect(9, 9, 12, 12)
            p.circle(15, 15, 3)
            p.line(3, 3, 8, 8)
            p.arrowhead(8.6, 8.6, 0.707, 0.707)
            p.dot(9, 9)
        case .xref:
            // sheet with a folded corner and a paper clip (reference to another drawing)
            p.polyline([(5, 3), (5, 21), (15, 21), (19, 17), (19, 3)], closed: true)
            p.polyline([(15, 21), (15, 17), (19, 17)])
            p.line(8, 6, 16, 6)
            p.line(8, 8.8, 16, 8.8)
            p.arc(10, 14, 2, from: 90, to: 270)
            p.arc(14, 14, 2, from: -90, to: 90)
            p.line(10, 16, 14, 16)
            p.line(10, 12, 14, 12)
        case .rectangle:
            p.rect(4, 6.5, 16, 11)
            p.dot(4, 6.5)
            p.dot(20, 17.5)
        case .polyline:
            p.polyline([(4, 7), (9, 17.5), (14.5, 8.5), (20, 16)])
            p.dot(4, 7)
            p.dot(9, 17.5)
            p.dot(14.5, 8.5)
            p.dot(20, 16)
        case .spline:
            p.curve([(4, 8), (7, 19), (11, 19), (12, 12), (13, 5), (17, 5), (20, 16)])
            p.dot(4, 8)
            p.dot(12, 12)
            p.dot(20, 16)
        case .hatch:
            p.rect(4.5, 4.5, 15, 15)
            p.line(14.5, 4.5, 19.5, 9.5)
            p.line(9.5, 4.5, 19.5, 14.5)
            p.line(4.5, 4.5, 19.5, 19.5)
            p.line(4.5, 9.5, 14.5, 19.5)
            p.line(4.5, 14.5, 9.5, 19.5)
        case .breakObject:
            // line with a gap: the piece between two points disappears
            p.line(2, 12, 9, 12)
            p.line(15, 12, 22, 12)
            p.line(9, 12, 15, 12, dashed: true)
            p.dot(9, 12)
            p.dot(15, 12)
        case .breakAtPoint:
            // line split at one point (no gap)
            p.line(2, 12, 11, 12)
            p.line(13, 12, 22, 12)
            p.dot(12, 12)
            p.line(12, 6, 12, 9.5)
            p.line(12, 14.5, 12, 18)
        case .trim:
            p.line(13, 3.5, 13, 20.5)
            p.line(3.5, 12, 13, 12)
            p.line(13, 12, 20.5, 12, dashed: true)
            p.line(16.5, 15, 19.5, 18)
            p.line(16.5, 18, 19.5, 15)
        case .extend:
            p.line(19.5, 3.5, 19.5, 20.5)
            p.line(3.5, 12, 10, 12)
            p.line(10, 12, 17.5, 12, dashed: true)
            p.arrowhead(19.3, 12, 1, 0)
        case .fillet:
            p.line(5, 21, 5, 13)
            p.arc(13, 13, 8, from: 180, to: 270)
            p.line(13, 5, 21, 5)
            p.polyline([(5, 13), (5, 5), (13, 5)], dashed: true)
            p.line(13, 13, 7.909, 7.909)
            p.arrowhead(7.343, 7.343, -0.707, -0.707)
            p.dot(13, 13)
        case .chamfer:
            // two lines and a beveled corner; the original corner dashed
            p.line(5, 21, 5, 13)
            p.line(5, 13, 13, 5)
            p.line(13, 5, 21, 5)
            p.polyline([(5, 13), (5, 5), (13, 5)], dashed: true)
            p.dot(5, 13)
            p.dot(13, 5)
        case .offset:
            p.line(3.5, 11.5, 11, 19)
            p.dot(3.5, 11.5)
            p.dot(11, 19)
            p.line(11.5, 3.5, 19, 11, dashed: true)
            p.line(8.2, 13.8, 12.4, 9.6)
            p.arrowhead(13.2, 8.8, 0.707, -0.707)
        case .editPoints:
            // polyline with two marked vertices and a move arrow
            p.polyline([(3.5, 15), (8.5, 6), (13.5, 13), (19, 4.5)])
            p.fill(7, 4.5, 3, 3)
            p.fill(12, 11.5, 3, 3)
            p.line(14.5, 14.5, 18.5, 18.5)
            p.arrowhead(19.8, 19.8, 0.707, 0.707)
        case .explode:
            // rectangle broken into separate sides
            p.line(7, 3.5, 17, 3.5)
            p.line(20.5, 7, 20.5, 17)
            p.line(17, 20.5, 7, 20.5)
            p.line(3.5, 17, 3.5, 7)
            p.line(5.2, 5.2, 3, 3)
            p.line(18.8, 5.2, 21, 3)
            p.line(18.8, 18.8, 21, 21)
            p.line(5.2, 18.8, 3, 21)
        case .matchProperties:
            // a brush that transfers “paint” to a line
            p.polyline([(13.2, 11.6), (20.6, 19), (19, 20.6), (11.6, 13.2)], closed: true)
            p.polyline([(11.6, 13.2), (8.6, 10.6), (4, 4), (10.6, 8.6), (13.2, 11.6)], closed: true)
            p.line(3.5, 20.5, 10, 20.5)
            p.line(3.5, 16.5, 7, 16.5, dashed: true)
        case .join:
            // two pieces joining at one point
            p.line(3.5, 4.5, 10.4, 14.6)
            p.arrowhead(11, 15.5, 0.56, 0.83)
            p.line(20.5, 4.5, 13.6, 14.6)
            p.arrowhead(13, 15.5, -0.56, 0.83)
            p.dot(12, 19)
        case .powerTrim:
            p.line(11, 3.5, 11, 20.5)
            p.line(3.5, 8, 11, 8)
            p.line(11, 8, 20.5, 8, dashed: true)
            p.line(3.5, 16, 11, 16)
            p.line(11, 16, 20.5, 16, dashed: true)
            p.curve([(17.5, 20.5), (14, 16), (19.5, 12), (16.5, 3.5)])
        case .move:
            p.line(12, 3, 12, 21)
            p.line(3, 12, 21, 12)
            p.arrowhead(12, 3, 0, -1)
            p.arrowhead(12, 21, 0, 1)
            p.arrowhead(3, 12, -1, 0)
            p.arrowhead(21, 12, 1, 0)
        case .copy:
            p.polyline([(15, 9.5), (20, 9.5), (20, 20), (9.5, 20), (9.5, 15)])
            p.rect(4, 4, 11, 11)
            p.line(9.5, 7, 9.5, 12)
            p.line(7, 9.5, 12, 9.5)
        case .rotate:
            p.arc(12, 12, 8, from: 110, to: 385)
            p.arrowhead(19.25, 15.381, -0.423, 0.906)
            p.dot(12, 12)
        case .scale:
            p.rect(4, 4, 7, 7)
            p.rect(4, 4, 16, 16, dashed: true)
            p.line(11, 11, 19, 19)
            p.arrowhead(19.5, 19.5, 0.707, 0.707)
        case .mirror:
            p.line(12, 3, 12, 21, dashed: true)
            p.polyline([(3.5, 6), (9.5, 6), (9.5, 18)], closed: true)
            p.polyline([(20.5, 6), (14.5, 6), (14.5, 18)], closed: true)
        case .dimLinear:
            p.line(5, 4, 5, 19)
            p.line(19, 4, 19, 19)
            p.line(5, 14, 19, 14)
            p.arrowhead(5, 14, -1, 0)
            p.arrowhead(19, 14, 1, 0)
            p.line(9.5, 18, 14.5, 18)
        case .dimAligned:
            p.dot(9, 3)
            p.dot(21, 15)
            p.line(7.939, 4.061, 3.697, 8.303)
            p.line(19.939, 16.061, 15.697, 20.303)
            p.line(4.757, 7.243, 16.757, 19.243)
            p.arrowhead(4.757, 7.243, -0.707, -0.707)
            p.arrowhead(16.757, 19.243, 0.707, 0.707)
        case .dimContinue:
            // chain of three dimensions with oblique ticks
            p.line(2.5, 6, 2.5, 18)
            p.line(9, 6, 9, 18)
            p.line(14.5, 6, 14.5, 18)
            p.line(21.5, 6, 21.5, 18)
            p.line(1.5, 13, 22.5, 13)
            for x in [2.5, 9, 14.5, 21.5] as [CGFloat] { p.line(x - 1.5, 11.5, x + 1.5, 14.5) }
        case .dimAngular:
            p.line(4, 5, 21, 5)
            p.line(4, 5, 14.927, 18.023)
            p.arc(4, 5, 11, from: 0, to: 50)
            p.dot(4, 5)
        case .dimRadius:
            p.circle(11, 11, 8.5)
            p.dot(11, 11)
            p.line(11, 11, 17.511, 16.464)
            p.arrowhead(17.511, 16.464, 0.766, 0.643)
            p.line(17.511, 16.464, 21, 19.5)
        case .dimDiameter:
            p.circle(12, 12, 8.5)
            p.line(5.489, 6.536, 18.511, 17.464)
            p.arrowhead(18.511, 17.464, 0.766, 0.643)
            p.arrowhead(5.489, 6.536, -0.766, -0.643)
        case .leader:
            p.line(4, 4, 10, 14)
            p.arrowhead(4, 4, -0.514, -0.857)
            p.line(10, 14, 12.5, 14)
            p.line(14.5, 16.5, 20.5, 16.5)
            p.line(14.5, 12, 19, 12)
        case .text:
            drawText(.simple, p)
        case .roomLabel:
            // a room with its name and, below it, the area
            p.rect(3, 3, 18, 18)
            p.line(7, 13.5, 17, 13.5)
            p.line(8.5, 9, 15.5, 9)
        case .revisionCloud:
            drawCloud([(4, 6), (20, 6), (20, 18), (4, 18)], step: 4, p)
        case .hatchRebuild:
            // hatched “L” shape and a circular arrow (new boundary)
            p.polyline([(3, 3), (14, 3), (14, 8), (8, 8), (8, 14), (3, 14)], closed: true)
            p.line(3, 8, 8, 3)
            p.line(3, 12.5, 12.5, 3)
            p.line(5.5, 14, 8, 11.5)
            p.arc(16, 15, 5, from: 200, to: 470)
            p.arrowhead(14.29, 19.7, -0.94, -0.34)
        case .hatchCut:
            // hatched wall with a cut-out opening (dashed rectangle)
            p.rect(2.5, 7, 19, 10)
            p.line(2.5, 11, 6.5, 7)
            p.line(2.5, 15.5, 8, 10)
            p.line(16, 17, 21.5, 11.5)
            p.line(19.5, 17, 21.5, 15)
            p.rect(9.5, 4.5, 5, 15, dashed: true)
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
                p.arc(cx, cy, chord / 2 / sin(half), from: start, to: start + 120)
            }
        }
    }

    /// Magnifier: ring at top left, handle down to the right.
    private static func drawMagnifier(_ p: IconPainter) {
        p.circle(10, 14.5, 6)
        p.line(14.3, 10.2, 20, 4.5)
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
                    p.fillTriangle((x, 12), (x - dir * 4.5, 13.6), (x - dir * 4.5, 10.4))
                case .open:
                    p.polyline([(x - dir * 4.5, 14), (x, 12), (x - dir * 4.5, 10)])
                case .oblique:
                    p.line(x - 2.2, 9.8, x + 2.2, 14.2)
                case .architectural:
                    p.line(x - 2.2, 9.8, x + 2.2, 14.2)
                    p.line(x - 1.8, 9.8, x + 2.6, 14.2)
                    p.line(x - 2.6, 9.8, x + 1.8, 14.2)
                case .dot:
                    p.dot(x, 12)
                    p.dot(x, 12)
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
            for row in 0..<3 {
                for column in 0..<3 {
                    let x = 3 + CGFloat(column) * 6.5, y = 3 + CGFloat(row) * 6.5
                    if row == 0 && column == 0 { p.fill(x, y, 4.5, 4.5) } else { p.rect(x, y, 4.5, 4.5) }
                }
            }
        case .polar:
            p.circle(12, 12, 7.5)
            for k in 0..<6 {
                let a = CGFloat(k) * .pi / 3 + .pi / 2
                let x = 12 + 7.5 * cos(a), y = 12 + 7.5 * sin(a)
                if k == 0 { p.fill(x - 2, y - 2, 4, 4) } else { p.rect(x - 2, y - 2, 4, 4) }
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
                p.polyline(hexagon(12, 12, 9), closed: true)
                p.dot(12, 12)
                p.dot(12, 21)
            case .circumscribed:
                // sides touch the circle: center → side midpoint
                let r: CGFloat = 9
                p.circle(12, 12, r * cos(.pi / 6), dashed: true)
                p.polyline(hexagon(12, 12, r, rotation: 0), closed: true)
                p.dot(12, 12)
                p.dot(12, 12 + r * cos(.pi / 6))
            case .edge:
                // two given corners of one side, the polygon above it
                let corners = hexagon(12, 11, 8.5, rotation: 30)
                p.polyline(corners, closed: true, dashed: true)
                p.line(corners[3].0, corners[3].1, corners[4].0, corners[4].1)
                p.dot(corners[3].0, corners[3].1)
                p.dot(corners[4].0, corners[4].1)
            }
        }
        cache[key] = image
        return image
    }

    /// Measurement kind icon (menu of the Measure tool).
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
            p.line(1.5, 3.5, 22.5, 20.5, dashed: true)
            p.dot(8, 8.76)
            p.dot(16, 15.24)
        case .horizontal:
            p.line(1, 12, 23, 12, dashed: true)
            p.dot(12, 12)
            p.line(12, 15.5, 12, 19)
            p.line(10, 17.2, 14, 17.2)
        case .vertical:
            p.line(12, 1, 12, 23, dashed: true)
            p.dot(12, 12)
            p.line(15.5, 12, 19, 12)
            p.line(17.2, 10, 17.2, 14)
        case .angle:
            p.line(1.5, 6, 22.5, 18, dashed: true)
            p.line(4, 7.4, 20, 7.4)
            p.arc(4, 7.4, 9, from: 0, to: 29.7)
        }
    }

    static func image(for kind: MeasureKind, size: CGFloat) -> NSImage {
        let key = "measure\(kind.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        let image = render(size: size, description: kind.title) { drawMeasure(kind, $0) }
        cache[key] = image
        return image
    }

    private static func drawMeasure(_ kind: MeasureKind, _ p: IconPainter) {
        switch kind {
        case .distance:
            // ruler with ticks
            p.polyline([(2.5, 8), (21.5, 8), (21.5, 15), (2.5, 15)], closed: true)
            for x in stride(from: CGFloat(5.5), through: 18.5, by: 3.25) {
                p.line(x, 15, x, x == 5.5 || x == 18.5 || x == 12 ? 10.5 : 12.5)
            }
        case .angle:
            p.line(4, 5, 21, 5)
            p.line(4, 5, 15, 19)
            p.arc(4, 5, 9, from: 0, to: 52)
            p.arrowhead(9.55, 12.1, -0.79, 0.62)
        case .radius:
            p.circle(11, 11, 8)
            p.line(11, 11, 16.66, 16.66)
            p.arrowhead(16.66, 16.66, 0.707, 0.707)
            p.dot(11, 11)
        case .areaPoints:
            p.polyline([(4, 5), (19, 4), (20, 16), (9, 20)], closed: true)
            p.dot(4, 5)
            p.dot(19, 4)
            p.dot(20, 16)
            p.dot(9, 20)
            p.line(8, 9, 12, 5.5)
            p.line(8, 14, 16, 6)
            p.line(10, 17, 18, 9)
        case .areaBoundary:
            p.rect(3.5, 3.5, 17, 17)
            p.line(3.5, 9, 9, 3.5)
            p.line(3.5, 15, 15, 3.5)
            p.line(5.5, 20.5, 20.5, 5.5)
            p.line(11.5, 20.5, 20.5, 11.5)
            p.polyline([(12, 12), (12, 4.5), (14.5, 7), (16.5, 3), (18, 3.8), (16, 7.8), (19.4, 8)], closed: true)
        case .areaObject:
            p.circle(12, 12, 8.5)
            p.line(6, 18, 18, 6)
            p.line(4.5, 13, 13, 4.5)
            p.line(11, 19.5, 19.5, 11)
        case .point:
            p.line(12, 3, 12, 9)
            p.line(12, 15, 12, 21)
            p.line(3, 12, 9, 12)
            p.line(15, 12, 21, 12)
            p.dot(12, 12)
        case .length:
            p.curve([(3, 8), (7, 18), (12, 18), (13, 12), (14, 6), (18, 6), (21, 15)])
            p.line(3, 3, 21, 3)
            p.arrowhead(3, 3, -1, 0)
            p.arrowhead(21, 3, 1, 0)
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
            p.line(5, 19.5, 19, 19.5)
            p.line(5, 19.5, 5, 17)
            p.line(19, 19.5, 19, 17)
            p.line(12, 19.5, 12, 4.5)
            p.line(9.5, 4.5, 14.5, 4.5)
        case .multiline:
            // a smaller T and paragraph lines in a frame
            p.rect(3, 3, 18, 18, dashed: true)
            p.line(6, 17.5, 12, 17.5)
            p.line(9, 17.5, 9, 11.5)
            p.line(14, 17.5, 18, 17.5)
            p.line(14, 14.5, 18, 14.5)
            p.line(6, 9, 18, 9)
            p.line(6, 6, 15, 6)
        case .formatted:
            // T and next to it a slanted, underlined “a” (font, style)
            p.line(3.5, 19.5, 13, 19.5)
            p.line(8.25, 19.5, 8.25, 6)
            p.circle(16.5, 9, 3)
            p.line(19.5, 12, 19, 6)
            p.line(3, 3.5, 21, 3.5)
        }
    }

    private static func drawArc(_ method: ArcMethod, _ p: IconPainter) {
        switch method {
        case .threePoint:
            p.arc(12, 7, 9, from: 12, to: 168)
            p.dot(12, 16)
            p.dot(3.197, 8.871)
            p.ring(20.803, 8.871)
        case .startCenterEnd:
            p.arc(12, 7, 9, from: 12, to: 168)
            p.line(12, 7, 20.803, 8.871, dashed: true)
            p.line(12, 7, 3.197, 8.871, dashed: true)
            p.dot(12, 7)
            p.dot(3.197, 8.871)
            p.ring(20.803, 8.871)
        case .startCenterAngle:
            p.arc(12, 7, 9, from: 12, to: 168)
            p.line(12, 7, 20.803, 8.871, dashed: true)
            p.line(12, 7, 3.197, 8.871, dashed: true)
            p.arc(12, 7, 3.6, from: 12, to: 168)
            p.dot(12, 7)
            p.ring(20.803, 8.871)
        case .centerStartEnd:
            p.arc(12, 7, 9, from: 12, to: 168)
            p.line(12, 7, 20.803, 8.871, dashed: true)
            p.line(12, 7, 3.197, 8.871, dashed: true)
            p.dot(20.803, 8.871)
            p.dot(3.197, 8.871)
            p.ring(12, 7)
        case .centerStartAngle:
            p.arc(12, 7, 9, from: 12, to: 168)
            p.line(12, 7, 20.803, 8.871, dashed: true)
            p.line(12, 7, 3.197, 8.871, dashed: true)
            p.arc(12, 7, 3.6, from: 12, to: 168)
            p.dot(20.803, 8.871)
            p.ring(12, 7)
        case .startEndRadius:
            p.arc(12, 7, 9, from: 12, to: 168)
            p.line(20.803, 8.871, 3.197, 8.871, dashed: true)
            p.line(12, 7, 12, 14.8)
            p.arrowhead(12, 15.6, 0, 1)
            p.dot(3.197, 8.871)
            p.ring(20.803, 8.871)
        case .startEndAngle:
            p.arc(12, 7, 9, from: 12, to: 168)
            p.line(20.803, 8.871, 3.197, 8.871, dashed: true)
            p.line(12, 7, 20.803, 8.871, dashed: true)
            p.line(12, 7, 3.197, 8.871, dashed: true)
            p.arc(12, 7, 3.6, from: 12, to: 168)
            p.dot(3.197, 8.871)
            p.ring(20.803, 8.871)
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

/// Drawing in a 24 × 24 grid in a style similar to SF Symbols.
struct IconPainter {
    let scale: CGFloat
    private let lineWidth: CGFloat = 1.45
    private let dash: [CGFloat] = [2, 2.4]
    private let headLength: CGFloat = 3.4
    private let headAngle: CGFloat = 38
    private let dotRadius: CGFloat = 1.35

    init(scale: CGFloat) {
        self.scale = scale
    }

    private func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        return NSPoint(x: x * scale, y: y * scale)
    }

    private func stroke(_ path: NSBezierPath, dashed: Bool = false) {
        path.lineWidth = lineWidth * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        if dashed {
            var pattern = dash.map { $0 * scale }
            path.setLineDash(&pattern, count: pattern.count, phase: 0)
        }
        path.stroke()
    }

    func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, dashed: Bool = false) {
        let path = NSBezierPath()
        path.move(to: pt(x1, y1))
        path.line(to: pt(x2, y2))
        stroke(path, dashed: dashed)
    }

    func polyline(_ points: [(CGFloat, CGFloat)], closed: Bool = false, dashed: Bool = false) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: pt(first.0, first.1))
        for point in points.dropFirst() { path.line(to: pt(point.0, point.1)) }
        if closed { path.close() }
        stroke(path, dashed: dashed)
    }

    /// Ellipse with semi-axes rx, ry rotated by an angle (degrees).
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, angle: CGFloat) {
        let path = NSBezierPath(ovalIn: NSRect(x: -rx * scale, y: -ry * scale, width: 2 * rx * scale, height: 2 * ry * scale))
        var t = AffineTransform(translationByX: cx * scale, byY: cy * scale)
        t.rotate(byDegrees: angle)
        path.transform(using: t)
        stroke(path)
    }

    func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, dashed: Bool = false) {
        stroke(NSBezierPath(ovalIn: NSRect(x: (cx - r) * scale, y: (cy - r) * scale,
                                           width: 2 * r * scale, height: 2 * r * scale)), dashed: dashed)
    }

    /// Counterclockwise arc, angles in degrees.
    func arc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, from start: CGFloat, to end: CGFloat) {
        let path = NSBezierPath()
        path.appendArc(withCenter: pt(cx, cy), radius: r * scale, startAngle: start, endAngle: end, clockwise: false)
        stroke(path)
    }

    /// Connected cubic Bézier segments: [start, c1, c2, end, c1, c2, end, …].
    func curve(_ points: [(CGFloat, CGFloat)]) {
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
        stroke(path)
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, dashed: Bool = false) {
        stroke(NSBezierPath(rect: NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)),
               dashed: dashed)
    }

    /// Open arrow (as in SF Symbols) with its tip at (x, y) pointing along (dx, dy).
    func arrowhead(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
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
        stroke(path)
    }

    /// Filled triangle (arrow).
    func fillTriangle(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat), _ c: (CGFloat, CGFloat)) {
        let path = NSBezierPath()
        path.move(to: pt(a.0, a.1))
        path.line(to: pt(b.0, b.1))
        path.line(to: pt(c.0, c.1))
        path.close()
        path.fill()
    }

    /// Filled rectangle.
    func fill(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        NSBezierPath(rect: NSRect(x: x * scale, y: y * scale, width: w * scale, height: h * scale)).fill()
    }

    /// Ring – marks the starting point.
    func ring(_ x: CGFloat, _ y: CGFloat) {
        stroke(NSBezierPath(ovalIn: NSRect(x: (x - 2.4) * scale, y: (y - 2.4) * scale,
                                           width: 4.8 * scale, height: 4.8 * scale)))
    }

    func dot(_ x: CGFloat, _ y: CGFloat) {
        NSBezierPath(ovalIn: NSRect(x: (x - dotRadius) * scale, y: (y - dotRadius) * scale,
                                    width: 2 * dotRadius * scale, height: 2 * dotRadius * scale)).fill()
    }
}
