//
//  SnapTracking.swift
//  OreMonoCAD
//
//  Snap tracking: hold the cursor on a snap point for a moment and the point is tracked
//  (a small cross). The cursor then lines up with it horizontally, vertically and at polar angles, and snaps
//  where two alignments cross. Holding the cursor on a tracked point again releases it.
//

import Cocoa

final class SnapTracker {
    /// How long the cursor has to stay on a snap point before it is tracked (or released).
    static let dwell: TimeInterval = 0.5
    static let maxPoints = 7

    var enabled = true {
        didSet { if !enabled { clear() } }
    }
    /// Tracked points, the newest first.
    private(set) var points: [CGPoint] = []

    /// An alignment line: through `origin` in `direction` (unit vector).
    struct Alignment {
        let origin: CGPoint
        let direction: CGPoint
    }
    /// The current alignment of the cursor point (nil = the point is not aligned).
    private(set) var hit: (point: CGPoint, alignments: [Alignment])?

    /// Called when a point was tracked or released (the view redraws).
    var onChange: (() -> Void)?

    private var dwellTimer: Timer?
    private var dwellPoint: CGPoint?
    /// The point toggled during the current hover – toggling it again needs moving away first.
    private var toggledPoint: CGPoint?

    func clear() {
        cancelDwell()
        toggledPoint = nil
        hit = nil
        points.removeAll()
    }

    func clearHit() { hit = nil }

    private static func same(_ a: CGPoint, _ b: CGPoint) -> Bool {
        return Geometry.distance(a, b) <= max(1e-9, (abs(a.x) + abs(a.y)) * 1e-12)
    }

    // MARK: Tracking by hovering

    /// Called on every mouse movement with the object snap point under the cursor (nil = none).
    func hover(over snap: SnapPoint?) {
        let usable: Set<SnapType> = [.endpoint, .midpoint, .center, .geometricCenter, .quadrant,
                                     .intersection, .node, .insertion, .origin]
        guard enabled, let snap = snap, usable.contains(snap.type) else {
            cancelDwell()
            toggledPoint = nil
            return
        }
        let p = snap.point
        if let toggled = toggledPoint, SnapTracker.same(toggled, p) { return }
        toggledPoint = nil
        if let waiting = dwellPoint, SnapTracker.same(waiting, p) { return }
        cancelDwell()
        dwellPoint = p
        dwellTimer = Timer.scheduledTimer(withTimeInterval: SnapTracker.dwell, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dwellFinished() }
        }
    }

    private func cancelDwell() {
        dwellTimer?.invalidate()
        dwellTimer = nil
        dwellPoint = nil
    }

    private func dwellFinished() {
        dwellTimer = nil
        guard let p = dwellPoint else { return }
        dwellPoint = nil
        toggledPoint = p
        if let index = points.firstIndex(where: { SnapTracker.same($0, p) }) {
            points.remove(at: index)
        } else {
            points.insert(p, at: 0)
            if points.count > SnapTracker.maxPoints { points.removeLast() }
        }
        onChange?()
    }

    // MARK: Alignment

    /// Aligns the point with the tracked points. `cursor` = the mouse position in the drawing, `point` = after
    /// grid / ortho / polar, `constraint` = the direction ortho or polar keeps from `reference` (the previous point).
    /// `directions` = unit vectors of the alignments (horizontal, vertical, polar angles). Returns nil when not aligned.
    func align(cursor: CGPoint, point: CGPoint, reference: CGPoint?, constraint: CGPoint?,
               directions: [CGPoint], tolerance: CGFloat) -> CGPoint? {
        hit = nil
        guard enabled, !points.isEmpty, !directions.isEmpty else { return nil }
        var lines: [Alignment] = []
        for p in points {
            for d in directions where !(reference.map { SnapTracker.same($0, p) } ?? false) {
                lines.append(Alignment(origin: p, direction: d))
            }
        }
        guard !lines.isEmpty else { return nil }

        // ortho / polar: the point stays on its direction from the previous point and snaps where it crosses an alignment
        if let r = reference, let c = constraint, c.length > 0 {
            var best: (point: CGPoint, line: Alignment)?
            var bestDistance = tolerance
            for line in lines {
                guard let x = Geometry.lineIntersection(r, r + c, line.origin, line.origin + line.direction),
                      (x - r).dot(c) > 0 else { continue }
                let d = Geometry.distance(x, point)
                if d <= bestDistance {
                    bestDistance = d
                    best = (x, line)
                }
            }
            guard let found = best else { return nil }
            hit = (found.point, [found.line])
            return found.point
        }

        // two alignments crossing near the cursor (also with the directions from the previous point)
        var others = lines
        if let r = reference { others += directions.map { Alignment(origin: r, direction: $0) } }
        var crossing: (point: CGPoint, alignments: [Alignment])?
        var crossingDistance = tolerance
        for (i, a) in lines.enumerated() {
            for b in others[(i + 1)...] where !SnapTracker.same(a.origin, b.origin) {
                guard let x = Geometry.lineIntersection(a.origin, a.origin + a.direction, b.origin, b.origin + b.direction)
                else { continue }
                let d = Geometry.distance(x, cursor)
                if d <= crossingDistance {
                    crossingDistance = d
                    crossing = (x, [a, b])
                }
            }
        }
        if let found = crossing {
            hit = found
            return found.point
        }

        // a single alignment
        var best: (point: CGPoint, line: Alignment)?
        var bestDistance = tolerance
        for line in lines {
            let foot = line.origin + line.direction * (cursor - line.origin).dot(line.direction)
            let d = Geometry.distance(foot, cursor)
            if d <= bestDistance {
                bestDistance = d
                best = (foot, line)
            }
        }
        guard let found = best else { return nil }
        hit = (found.point, [found.line])
        return found.point
    }

    /// Directions of the alignments: the axes of the drawing coordinates and, with polar angles on, every step.
    static func directions(ucsAngle: CGFloat, polarIncrement: CGFloat?) -> [CGPoint] {
        var angles: [CGFloat] = [0, .pi / 2]
        if let increment = polarIncrement, increment >= 1 {
            let step = increment * .pi / 180
            var a = step
            while a < .pi - 1e-9 && angles.count < 180 {
                if abs(a - .pi / 2) > 1e-9 { angles.append(a) }
                a += step
            }
        }
        return angles.map { CGPoint(x: cos($0 + ucsAngle), y: sin($0 + ucsAngle)) }
    }

    // MARK: Drawing

    /// Crosses at the tracked points, dashed alignment lines and the label “distance < angle”.
    func draw(in context: CGContext, bounds: CGRect, ucsAngle: CGFloat, toScreen: (CGPoint) -> CGPoint) {
        let color = NSColor.systemGreen
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        for p in points {
            let s = toScreen(p)
            guard DrawingSafety.isFinite(s) else { continue }
            context.move(to: CGPoint(x: s.x - 4, y: s.y))
            context.addLine(to: CGPoint(x: s.x + 4, y: s.y))
            context.move(to: CGPoint(x: s.x, y: s.y - 4))
            context.addLine(to: CGPoint(x: s.x, y: s.y + 4))
        }
        context.strokePath()

        guard let hit = hit else {
            context.restoreGState()
            return
        }
        let target = toScreen(hit.point)
        guard DrawingSafety.isFinite(target) else {
            context.restoreGState()
            return
        }
        // the line runs from the tracked point through the cursor point to the edge of the view
        let reach = hypot(bounds.width, bounds.height)
        context.setStrokeColor(color.withAlphaComponent(0.8).cgColor)
        context.setLineDash(phase: 0, lengths: [4, 4])
        var labels: [String] = []
        for alignment in hit.alignments {
            let origin = toScreen(alignment.origin)
            guard DrawingSafety.isFinite(origin) else { continue }
            let d = target - origin
            let length = d.length
            context.move(to: origin)
            context.addLine(to: length > 1e-9 ? target + d.normalized * reach : target)
            let distance = Geometry.distance(alignment.origin, hit.point)
            let v = hit.point - alignment.origin
            var angle = (atan2(v.y, v.x) - ucsAngle) * 180 / .pi
            angle = angle.truncatingRemainder(dividingBy: 360)
            if angle < 0 { angle += 360 }
            if angle >= 359.995 { angle = 0 }
            labels.append("\(LengthStyle.feetInches(distance) ?? LineType.format(distance)) < \(AngleStyle.text(angle, .direction))")
        }
        context.strokePath()
        context.restoreGState()
        SnapMarker.draw(.intersection, at: target, size: 4, color: color, in: context)
        ("Tracking: " + labels.joined(separator: ", ") as NSString)
            .draw(at: CGPoint(x: target.x + 10, y: target.y - 18),
                  withAttributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 10)])
    }
}
