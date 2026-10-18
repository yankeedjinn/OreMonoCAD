//
//  Hatch.swift
//  OhMyCAD
//
//  Hatch / fill. It finds the region boundary from anything that bounds it (lines, arcs,
//  circles, polylines, splines) – the objects need not be joined, it is enough that they intersect.
//  Small gaps are bridged. Exactly the area that was clicked is filled: its outline and, inside it,
//  only the nearest nested shapes as islands (like “Outer” in AutoCAD). Whatever lies inside the islands
//  (further nested outlines, shapes inside them…) is not filled – the hatch never “spills” into another area.
//
//  Procedure: all curves → line segments → split at intersections → planar graph →
//  face traversal → the smallest face containing the clicked point + the nearest islands inside it.
//

import Cocoa

// Hatch patterns (HatchPattern, HatchPatternLibrary, the generator) are in HatchPatterns.swift.

// MARK: - Hatch Entity

final class HatchEntity: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var drawOrder = 0
    /// Loops: the first is the outer boundary, the rest are islands (filled even-odd).
    var loops: [[CGPoint]]
    var pattern: HatchPattern
    var angle: CGFloat      // radians
    /// Pattern size: world units per 1 mm of the pattern (1 = pattern 1:1, 50 = pattern for scale 1:50).
    var scale: CGFloat
    /// Pattern origin in the world (moves with the object).
    var origin: CGPoint = .zero

    init(loops: [[CGPoint]], pattern: HatchPattern, angle: CGFloat, scale: CGFloat,
         layer: String = "0", color: NSColor? = nil) {
        self.loops = loops
        self.pattern = pattern
        self.angle = angle
        self.scale = scale
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Hatch" }

    var area: CGFloat {
        guard let outer = loops.first else { return 0 }
        return abs(HatchEntity.signedArea(outer)) - loops.dropFirst().reduce(0) { $0 + abs(HatchEntity.signedArea($1)) }
    }

    var infoText: String {
        var text = String(format: "Hatch\n%@\n\nPattern: %@\nAngle:   %.1f°\nScale:   %@",
                          commonInfo, pattern.name, Double(angle * 180 / .pi), LineType.format(scale))
        if !pattern.isSolid {
            text += "\nSpacing: " + LineType.format(pattern.smallestSpacing * scale)
        }
        text += String(format: "\nIslands: %ld\nArea:    %.3f", max(loops.count - 1, 0), Double(area))
        return text
    }

    static func signedArea(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i], b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        for loop in loops where loop.count >= 3 {
            path.addLines(between: loop)
            path.closeSubpath()
        }
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        var t = transform
        guard let region = makePath().copy(using: &t) else { return }
        let box = region.boundingBoxOfPath
        guard DrawingSafety.isDrawable(box) else { return }
        let zoom = Geometry.uniformScale(of: transform)

        context.saveGState()
        context.addPath(region)
        context.clip(using: .evenOdd)

        // only the visible part of the hatch (window clipping) – in world coordinates
        let visibleScreen = context.boundingBoxOfClipPath.intersection(box)
        let visibleWorld = visibleScreen.applying(transform.inverted())
        let screenSpacing = pattern.smallestSpacing * scale * zoom

        var output: HatchPatternGenerator.Output?
        if !pattern.isSolid && screenSpacing >= 2.5 && !visibleWorld.isNull {
            output = HatchPatternGenerator.generate(pattern, angle: angle, scale: scale, origin: origin,
                                                    covering: visibleWorld, limit: 40_000)
        }

        if pattern.isSolid {
            context.setFillColor(style.color.withAlphaComponent(0.9).cgColor)
            context.fill(box)
        } else if let output = output {
            context.setStrokeColor(style.color.cgColor)
            context.setFillColor(style.color.cgColor)
            context.setLineWidth(min(style.lineWidth, max(1, screenSpacing / 3)))
            for (a, b) in output.segments {
                context.move(to: a.applying(transform))
                context.addLine(to: b.applying(transform))
            }
            context.strokePath()
            let r = max(0.8, min(style.lineWidth, screenSpacing / 4) * 0.7)
            for p in output.dots {
                let q = p.applying(transform)
                context.addEllipse(in: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r))
            }
            context.fillPath()
        } else {
            // the pattern is too dense on screen – just a light tone
            context.setFillColor(style.color.withAlphaComponent(0.35).cgColor)
            context.fill(box)
        }
        context.restoreGState()
    }

    /// Bounding box of all loops (a hatch from DXF may have several separate regions, not just an outer boundary with islands).
    func boundingBox() -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        for loop in loops {
            for p in loop {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        guard minX <= maxX, minY <= maxY else { return .null }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func contains(_ point: CGPoint) -> Bool {
        var inside = false
        for loop in loops where HatchEntity.pointInPolygon(point, loop) { inside.toggle() }
        return inside
    }

    static func box(of points: [CGPoint]) -> CGRect {
        var rect = CGRect.null
        for p in points { rect = rect.union(CGRect(origin: p, size: .zero)) }
        return rect
    }

    /// A point inside the area (even-odd over all loops), as far from the edges as possible horizontally.
    static func interiorPoint(of loops: [[CGPoint]]) -> CGPoint? {
        var box = CGRect.null
        for loop in loops { for p in loop { box = box.union(CGRect(origin: p, size: .zero)) } }
        guard !box.isNull, box.height > 0 else { return nil }
        var best: (point: CGPoint, width: CGFloat)?
        for fraction: CGFloat in [0.5, 0.37, 0.63, 0.25, 0.75, 0.13, 0.87, 0.06, 0.94, 0.03, 0.97] {
            let y = box.minY + box.height * fraction
            var xs: [CGFloat] = []
            for loop in loops where loop.count >= 3 {
                for i in loop.indices {
                    let a = loop[i], b = loop[(i + 1) % loop.count]
                    if (a.y > y) != (b.y > y) {
                        xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
                    }
                }
            }
            xs.sort()
            var i = 0
            while i + 1 < xs.count {
                let width = xs[i + 1] - xs[i]
                if width > (best?.width ?? 0) { best = (CGPoint(x: (xs[i] + xs[i + 1]) / 2, y: y), width) }
                i += 2
            }
        }
        return best?.point
    }

    static func pointInPolygon(_ p: CGPoint, _ polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.y > p.y) != (b.y > p.y) {
                let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    func distance(to point: CGPoint) -> CGFloat {
        if contains(point) { return 0 }
        var best = CGFloat.infinity
        for loop in loops {
            for i in 0..<loop.count {
                best = min(best, Geometry.distance(from: point, toSegmentFrom: loop[i], to: loop[(i + 1) % loop.count]))
            }
        }
        return best
    }

    func snapPoints() -> [SnapPoint] { return [] }

    func applyTransform(_ transform: CGAffineTransform) {
        loops = loops.map { $0.map { $0.applying(transform) } }
        origin = origin.applying(transform)
        scale *= Geometry.uniformScale(of: transform)
        let direction = CGPoint(x: cos(angle), y: sin(angle))
        let moved = CGPoint(x: transform.a * direction.x + transform.c * direction.y,
                            y: transform.b * direction.x + transform.d * direction.y)
        angle = atan2(moved.y, moved.x)
    }

    func clone() -> CADEntity {
        let copy = HatchEntity(loops: loops, pattern: pattern, angle: angle, scale: scale, layer: layer, color: color)
        copy.origin = origin
        return copyStyle(to: copy)
    }

    /// A hatch is neither a cutting edge nor a boundary.
    func primitives() -> [Primitive] { return [] }

    /// Pattern lines and dots clipped by the boundary (for DXF export).
    func patternGeometry(limit: Int = 20_000) -> HatchPatternGenerator.Output {
        guard !pattern.isSolid,
              let raw = HatchPatternGenerator.generate(pattern, angle: angle, scale: scale, origin: origin,
                                                      covering: boundingBox(), limit: limit) else {
            return HatchPatternGenerator.Output()
        }
        let edges = loops.flatMap { loop in (0..<loop.count).map { (loop[$0], loop[($0 + 1) % loop.count]) } }
        var result = HatchPatternGenerator.Output()
        for (a, b) in raw.segments {
            var ts: [CGFloat] = [0, 1]
            for (p, q) in edges {
                if let hit = Geometry.segmentIntersection(a, b, p, q) { ts.append(hit.ta) }
            }
            ts.sort()
            for i in 0..<(ts.count - 1) where ts[i + 1] - ts[i] > 1e-9 {
                let p = Geometry.lerp(a, b, ts[i]), q = Geometry.lerp(a, b, ts[i + 1])
                if contains(Geometry.midpoint(p, q)) { result.segments.append((p, q)) }
            }
        }
        result.dots = raw.dots.filter { contains($0) }
        return result
    }
}

// MARK: - Region Finder

/// A planar graph of all curves; can find the closed region around a point.
final class HatchRegionFinder {
    private struct Face {
        let points: [CGPoint]
        let area: CGFloat      // signed: positive = a bounded region
        let component: Int
        let box: CGRect
    }

    private var faces: [Face] = []
    private var outerFaces: [Int: Face] = [:]

    /// All closed areas (loops without islands) – for subtracting shapes from a hatch.
    var boundedFaces: [[CGPoint]] {
        return faces.filter { $0.area > 0 }.map { $0.points }
    }

    /// - Parameters:
    ///   - gap: gaps up to this size are bridged (world units)
    ///   - flatness: max. deviation when replacing arcs with line segments
    init(entities: [CADEntity], gap: CGFloat, flatness: CGFloat) {
        build(entities: entities, gap: gap, flatness: flatness)
    }

    // MARK: Search

    /// Loops of the region around a point: [outer boundary, islands…], or nil if the region is not closed.
    func region(at point: CGPoint) -> [[CGPoint]]? {
        var chosen: Face?
        for face in faces where face.area > 0 && face.box.contains(point) {
            if HatchEntity.pointInPolygon(point, face.points), chosen.map({ face.area < $0.area }) ?? true {
                chosen = face
            }
        }
        guard let region = chosen else { return nil }

        // shapes (separate graph components) inside the region that do not contain the clicked point
        var candidates: [Face] = []
        for (component, outer) in outerFaces where component != region.component {
            guard region.box.contains(outer.box), let probe = outer.points.first,
                  HatchEntity.pointInPolygon(probe, region.points),
                  !HatchEntity.pointInPolygon(point, outer.points) else { continue }
            candidates.append(outer)
        }
        // Only the nearest islands count: a shape lying inside another island is not added.
        // (If it were, the even-odd fill would fill it again – with nested loops, e.g.
        // offset polylines, the hatch would “spill” every other band all the way to the center.)
        candidates.sort { abs($0.area) > abs($1.area) }
        var islands: [Face] = []
        for candidate in candidates {
            guard let probe = candidate.points.first else { continue }
            let nested = islands.contains { island in
                island.box.contains(candidate.box) && HatchEntity.pointInPolygon(probe, island.points)
            }
            if !nested { islands.append(candidate) }
        }
        return [region.points] + islands.map { $0.points }
    }

    // MARK: Graph construction

    private func build(entities: [CADEntity], gap: CGFloat, flatness: CGFloat) {
        // 1) curves → line segments (arcs are flattened)
        var segments: [(a: CGPoint, b: CGPoint)] = []
        var owners: [Int] = []
        var openEnds: [(point: CGPoint, owner: Int)] = []

        for (index, entity) in entities.enumerated() {
            let primitives = entity.primitives()
            guard !primitives.isEmpty else { continue }
            var chain: [CGPoint] = []
            for primitive in primitives {
                let points = HatchRegionFinder.flatten(primitive, flatness: flatness)
                for i in 0..<(points.count - 1) where Geometry.distance(points[i], points[i + 1]) > 0 {
                    segments.append((points[i], points[i + 1]))
                    owners.append(index)
                }
                if chain.isEmpty { chain.append(contentsOf: points) } else { chain.append(contentsOf: points.dropFirst()) }
            }
            if let first = chain.first, let last = chain.last, Geometry.distance(first, last) > gap * 0.01 {
                openEnds.append((first, index))
                openEnds.append((last, index))
            }
        }
        guard !segments.isEmpty else { return }

        var extent = CGRect.null
        for s in segments { extent = extent.union(CGRect(origin: s.a, size: .zero)).union(CGRect(origin: s.b, size: .zero)) }
        let size = max(extent.width, extent.height, 1)
        let merge = max(size * 1e-9, gap * 1e-3)

        // 2) bridges over small gaps: free end → nearest point of another object
        var grid = SegmentGrid(extent: extent, cellSize: max(size / 64, gap * 4))
        for (i, s) in segments.enumerated() { grid.insert(i, s.a, s.b) }
        if gap > 0 {
            for end in openEnds {
                var best: (distance: CGFloat, point: CGPoint)?
                for i in grid.candidates(near: end.point, radius: gap) where owners[i] != end.owner {
                    let s = segments[i]
                    let t = max(0, min(1, Geometry.projectionParameter(of: end.point, ontoSegmentFrom: s.a, to: s.b)))
                    let q = Geometry.lerp(s.a, s.b, t)
                    let d = Geometry.distance(end.point, q)
                    if d > merge && d <= gap && d < (best?.distance ?? .infinity) { best = (d, q) }
                }
                if let bridge = best {
                    let index = segments.count
                    segments.append((end.point, bridge.point))
                    owners.append(-1)
                    grid.insert(index, end.point, bridge.point)
                }
            }
        }

        // 3) split points: intersections and ends lying on other segments
        var splits = Array(repeating: [CGFloat(0), 1], count: segments.count)
        for (i, j) in grid.candidatePairs() {
            let s = segments[i], r = segments[j]
            if let hit = Geometry.segmentIntersection(s.a, s.b, r.a, r.b) {
                splits[i].append(hit.ta)
                splits[j].append(hit.tb)
            }
            // touches and collinear overlaps
            for (end, target, list) in [(r.a, s, i), (r.b, s, i), (s.a, r, j), (s.b, r, j)] {
                let t = Geometry.projectionParameter(of: end, ontoSegmentFrom: target.a, to: target.b)
                if t > 0 && t < 1 && Geometry.distance(end, Geometry.lerp(target.a, target.b, t)) < merge {
                    splits[list].append(t)
                }
            }
        }

        // 4) vertices (merged within tolerance) and edges
        var vertices: [CGPoint] = []
        var vertexGrid: [Int64: [Int]] = [:]
        func key(_ x: Int, _ y: Int) -> Int64 { return (Int64(x) << 32) ^ Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: y))) }
        func vertexID(_ p: CGPoint) -> Int {
            let cx = Int((p.x / merge).rounded(.down)), cy = Int((p.y / merge).rounded(.down))
            for dx in -1...1 {
                for dy in -1...1 {
                    for id in vertexGrid[key(cx + dx, cy + dy)] ?? [] where Geometry.distance(vertices[id], p) <= merge {
                        return id
                    }
                }
            }
            vertices.append(p)
            vertexGrid[key(cx, cy), default: []].append(vertices.count - 1)
            return vertices.count - 1
        }

        var edgeSet = Set<Int64>()
        var edges: [(Int, Int)] = []
        for (i, s) in segments.enumerated() {
            let ts = Array(Set(splits[i].map { max(0, min(1, $0)) })).sorted()
            var previous: Int?
            for t in ts {
                let id = vertexID(Geometry.lerp(s.a, s.b, t))
                if let p = previous, p != id {
                    let a = min(p, id), b = max(p, id)
                    if edgeSet.insert((Int64(a) << 32) | Int64(b)).inserted { edges.append((a, b)) }
                }
                previous = id
            }
        }

        // 5) remove dangling edges (they cannot bound a region)
        var degree = Array(repeating: 0, count: vertices.count)
        for (a, b) in edges { degree[a] += 1; degree[b] += 1 }
        var alive = Array(repeating: true, count: edges.count)
        var incident = Array(repeating: [Int](), count: vertices.count)
        for (index, (a, b)) in edges.enumerated() { incident[a].append(index); incident[b].append(index) }
        var queue = (0..<vertices.count).filter { degree[$0] == 1 }
        while let v = queue.popLast() {
            for e in incident[v] where alive[e] {
                alive[e] = false
                let (a, b) = edges[e]
                let other = a == v ? b : a
                degree[v] -= 1
                degree[other] -= 1
                if degree[other] == 1 { queue.append(other) }
            }
        }

        // 6) half-edges sorted by angle
        var outgoing = Array(repeating: [Int](), count: vertices.count)
        for (index, (a, b)) in edges.enumerated() where alive[index] {
            outgoing[a].append(b)
            outgoing[b].append(a)
        }
        for v in 0..<vertices.count where outgoing[v].count > 1 {
            let origin = vertices[v]
            outgoing[v].sort { Geometry.angle(from: origin, to: vertices[$0]) < Geometry.angle(from: origin, to: vertices[$1]) }
        }

        // components (union-find)
        var parent = Array(0..<vertices.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for (index, (a, b)) in edges.enumerated() where alive[index] { parent[find(a)] = find(b) }

        // 7) face traversal: next edge = the nearest clockwise from the reverse one
        var visited = Set<Int64>()
        func code(_ a: Int, _ b: Int) -> Int64 { return (Int64(a) << 32) | Int64(b) }
        for (index, (a, b)) in edges.enumerated() where alive[index] {
            for start in [(a, b), (b, a)] where !visited.contains(code(start.0, start.1)) {
                var cycle: [Int] = []
                var current = start
                var guardSteps = 0
                while !visited.contains(code(current.0, current.1)) && guardSteps < 1_000_000 {
                    visited.insert(code(current.0, current.1))
                    cycle.append(current.0)
                    let list = outgoing[current.1]
                    guard let position = list.firstIndex(of: current.0) else { break }
                    current = (current.1, list[(position - 1 + list.count) % list.count])
                    guardSteps += 1
                }
                guard cycle.count >= 3 else { continue }
                let points = cycle.map { vertices[$0] }
                let area = HatchEntity.signedArea(points)
                var box = CGRect(origin: points[0], size: .zero)
                for p in points { box = box.union(CGRect(origin: p, size: .zero)) }
                let face = Face(points: points, area: area, component: find(cycle[0]), box: box)
                faces.append(face)
                if area < 0, abs(area) > abs(outerFaces[face.component]?.area ?? 0) {
                    outerFaces[face.component] = face
                }
            }
        }
    }

    /// Replacement with line segments at a given maximum deviation.
    static func flatten(_ primitive: Primitive, flatness: CGFloat) -> [CGPoint] {
        switch primitive {
        case let .segment(a, b, _):
            return [a, b]
        case let .arc(center, radius, start, sweep, _):
            let step: CGFloat = radius > flatness ? 2 * acos(max(-1, 1 - flatness / radius)) : abs(sweep)
            let count = min(max(Int((abs(sweep) / max(step, 1e-3)).rounded(.up)), 4), 1440)
            return (0...count).map { Geometry.pointOnCircle(center, radius, start + sweep * CGFloat($0) / CGFloat(count)) }
        }
    }
}

/// A simple grid for quickly finding nearby segments.
private struct SegmentGrid {
    private let origin: CGPoint
    private let cellSize: CGFloat
    private var cells: [Int64: [Int]] = [:]

    init(extent: CGRect, cellSize: CGFloat) {
        self.origin = CGPoint(x: extent.minX, y: extent.minY)
        self.cellSize = max(cellSize, 1e-9)
    }

    private func cell(_ v: CGFloat, _ o: CGFloat) -> Int {
        let raw = ((v - o) / cellSize).rounded(.down)
        return Int(max(-1_000_000, min(1_000_000, raw)))
    }

    private func key(_ x: Int, _ y: Int) -> Int64 {
        return (Int64(x) << 32) ^ Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: y)))
    }

    mutating func insert(_ index: Int, _ a: CGPoint, _ b: CGPoint) {
        let x0 = cell(min(a.x, b.x), origin.x), x1 = cell(max(a.x, b.x), origin.x)
        let y0 = cell(min(a.y, b.y), origin.y), y1 = cell(max(a.y, b.y), origin.y)
        guard (x1 - x0 + 1) * (y1 - y0 + 1) < 200_000 else { return }
        for x in x0...x1 {
            for y in y0...y1 { cells[key(x, y), default: []].append(index) }
        }
    }

    func candidates(near p: CGPoint, radius: CGFloat) -> Set<Int> {
        var result = Set<Int>()
        let x0 = cell(p.x - radius, origin.x), x1 = cell(p.x + radius, origin.x)
        let y0 = cell(p.y - radius, origin.y), y1 = cell(p.y + radius, origin.y)
        for x in x0...x1 {
            for y in y0...y1 { result.formUnion(cells[key(x, y)] ?? []) }
        }
        return result
    }

    /// Pairs of segments sharing a cell (each pair only once).
    func candidatePairs() -> [(Int, Int)] {
        var seen = Set<Int64>()
        var pairs: [(Int, Int)] = []
        for list in cells.values where list.count > 1 {
            for i in 0..<list.count {
                for j in (i + 1)..<list.count {
                    let a = min(list[i], list[j]), b = max(list[i], list[j])
                    if a != b && seen.insert((Int64(a) << 32) | Int64(b)).inserted { pairs.append((a, b)) }
                }
            }
        }
        return pairs
    }
}
