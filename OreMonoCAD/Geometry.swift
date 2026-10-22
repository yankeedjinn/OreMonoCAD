//
//  Geometry.swift
//  OreMonoCAD
//
//  Geometry helpers: distances, transforms, angles and intersections.
//

import Foundation
import CoreGraphics

// MARK: - Vector helpers

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { return CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { return CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, s: CGFloat) -> CGPoint { return CGPoint(x: a.x * s, y: a.y * s) }

    var length: CGFloat { return hypot(x, y) }

    var normalized: CGPoint {
        let l = length
        return l > 0 ? CGPoint(x: x / l, y: y / l) : .zero
    }

    /// Perpendicular vector (rotated by +90°).
    var perpendicular: CGPoint { return CGPoint(x: -y, y: x) }

    func dot(_ other: CGPoint) -> CGFloat { return x * other.x + y * other.y }
    func cross(_ other: CGPoint) -> CGFloat { return x * other.y - y * other.x }
}

// MARK: - Geometry

enum Geometry {
    static let epsilon: CGFloat = 1e-9

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        return hypot(b.x - a.x, b.y - a.y)
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    static func angle(from center: CGPoint, to point: CGPoint) -> CGFloat {
        return atan2(point.y - center.y, point.x - center.x)
    }

    static func pointOnCircle(_ center: CGPoint, _ radius: CGFloat, _ angle: CGFloat) -> CGPoint {
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    /// Angle normalized to the interval [0, 2π).
    static func normalizeAngle(_ angle: CGFloat) -> CGFloat {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a < 0 { a += 2 * .pi }
        return a
    }

    /// Positive counterclockwise angular distance from `from` to `to`, in [0, 2π).
    static func ccwDelta(from: CGFloat, to: CGFloat) -> CGFloat {
        return normalizeAngle(to - from)
    }

    /// Parameter t of the perpendicular projection of a point onto a segment (0 = a, 1 = b, may be outside).
    static func projectionParameter(of p: CGPoint, ontoSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let d = b - a
        let l2 = d.dot(d)
        guard l2 > 0 else { return 0 }
        return (p - a).dot(d) / l2
    }

    static func distance(from p: CGPoint, toSegmentFrom a: CGPoint, to b: CGPoint) -> CGFloat {
        let t = max(0, min(1, projectionParameter(of: p, ontoSegmentFrom: a, to: b)))
        return distance(p, lerp(a, b, t))
    }

    /// Distance of a point from an arc (start angle, positive sweep).
    static func distance(from p: CGPoint, toArcCenter c: CGPoint, radius r: CGFloat,
                         start: CGFloat, sweep: CGFloat) -> CGFloat {
        let a = angle(from: c, to: p)
        if ccwDelta(from: start, to: a) <= sweep + epsilon {
            return abs(distance(p, c) - r)
        }
        let s = pointOnCircle(c, r, start)
        let e = pointOnCircle(c, r, start + sweep)
        return min(distance(p, s), distance(p, e))
    }

    // MARK: Transforms

    /// Rotation about a point: translate to origin → rotate → translate back.
    static func rotation(by angle: CGFloat, around p: CGPoint) -> CGAffineTransform {
        return CGAffineTransform(translationX: -p.x, y: -p.y)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
    }

    static func scaling(by factor: CGFloat, around p: CGPoint) -> CGAffineTransform {
        return CGAffineTransform(translationX: -p.x, y: -p.y)
            .concatenating(CGAffineTransform(scaleX: factor, y: factor))
            .concatenating(CGAffineTransform(translationX: p.x, y: p.y))
    }

    /// Mirroring across the line through points a, b.
    static func mirror(acrossLineFrom a: CGPoint, to b: CGPoint) -> CGAffineTransform? {
        let u = (b - a).normalized
        guard u != .zero else { return nil }
        let cos2 = u.x * u.x - u.y * u.y
        let sin2 = 2 * u.x * u.y
        let reflection = CGAffineTransform(a: cos2, b: sin2, c: sin2, d: -cos2, tx: 0, ty: 0)
        return CGAffineTransform(translationX: -a.x, y: -a.y)
            .concatenating(reflection)
            .concatenating(CGAffineTransform(translationX: a.x, y: a.y))
    }

    /// Length scale of a uniform transform.
    static func uniformScale(of t: CGAffineTransform) -> CGFloat {
        return sqrt(abs(t.a * t.d - t.b * t.c))
    }

    /// True if the transform flips orientation (mirroring).
    static func isMirroring(_ t: CGAffineTransform) -> Bool {
        return t.a * t.d - t.b * t.c < 0
    }

    // MARK: Intersections of basic shapes

    /// Intersection of two segments. Returns the point and the parameters on both segments (0…1).
    static func segmentIntersection(_ a1: CGPoint, _ a2: CGPoint,
                                    _ b1: CGPoint, _ b2: CGPoint) -> (point: CGPoint, ta: CGFloat, tb: CGFloat)? {
        let r = a2 - a1
        let s = b2 - b1
        let denominator = r.cross(s)
        guard abs(denominator) > epsilon * max(1, r.length * s.length) else { return nil }
        let q = b1 - a1
        let ta = q.cross(s) / denominator
        let tb = q.cross(r) / denominator
        let tolerance: CGFloat = 1e-9
        guard ta >= -tolerance, ta <= 1 + tolerance, tb >= -tolerance, tb <= 1 + tolerance else { return nil }
        return (point: lerp(a1, a2, ta), ta: ta, tb: tb)
    }

    /// Intersection of two infinite lines.
    static func lineIntersection(_ a1: CGPoint, _ a2: CGPoint,
                                 _ b1: CGPoint, _ b2: CGPoint) -> CGPoint? {
        let r = a2 - a1
        let s = b2 - b1
        let denominator = r.cross(s)
        guard abs(denominator) > epsilon * max(1, r.length * s.length) else { return nil }
        let t = (b1 - a1).cross(s) / denominator
        return lerp(a1, a2, t)
    }

    /// Intersections of a segment with a circle. Returns the points and parameters t on the segment.
    static func segmentCircleIntersections(_ a: CGPoint, _ b: CGPoint,
                                           center c: CGPoint, radius r: CGFloat) -> [(point: CGPoint, t: CGFloat)] {
        let d = b - a
        let f = a - c
        let qa = d.dot(d)
        guard qa > 0 else { return [] }
        let qb = 2 * f.dot(d)
        let qc = f.dot(f) - r * r
        var discriminant = qb * qb - 4 * qa * qc
        if discriminant < 0 {
            // tangent with numerical error
            if discriminant > -1e-9 * qb * qb { discriminant = 0 } else { return [] }
        }
        let sq = sqrt(discriminant)
        var ts = [(-qb - sq) / (2 * qa)]
        if sq > 0 { ts.append((-qb + sq) / (2 * qa)) }
        let tolerance: CGFloat = 1e-9
        return ts.filter { $0 >= -tolerance && $0 <= 1 + tolerance }.map { (point: lerp(a, b, $0), t: $0) }
    }

    /// Circle through three points (nil if they are collinear).
    static func circleThrough(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> (center: CGPoint, radius: CGFloat)? {
        let d = 2 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y))
        let scale = max(1, (b - a).length * (c - a).length)
        guard abs(d) > 1e-12 * scale else { return nil }
        let a2 = a.dot(a), b2 = b.dot(b), c2 = c.dot(c)
        let center = CGPoint(x: (a2 * (b.y - c.y) + b2 * (c.y - a.y) + c2 * (a.y - b.y)) / d,
                             y: (a2 * (c.x - b.x) + b2 * (a.x - c.x) + c2 * (b.x - a.x)) / d)
        return (center, distance(center, a))
    }

    /// Intersections of two circles.
    static func circleCircleIntersections(_ c1: CGPoint, _ r1: CGFloat,
                                          _ c2: CGPoint, _ r2: CGFloat) -> [CGPoint] {
        let d = distance(c1, c2)
        guard d > epsilon, d <= r1 + r2 + 1e-9, d >= abs(r1 - r2) - 1e-9 else { return [] }
        let a = (r1 * r1 - r2 * r2 + d * d) / (2 * d)
        let h = sqrt(max(0, r1 * r1 - a * a))
        let u = (c2 - c1) * (1 / d)
        let base = c1 + u * a
        if h < 1e-9 { return [base] }
        let n = u.perpendicular
        return [base + n * h, base - n * h]
    }
}

// MARK: - Primitives (lines and arcs that make up every curve)

/// A piece of a curve. `param` is the length from the start of the whole curve to the start of this piece.
/// A piece of a curve. An arc has a positive `sweep` (counterclockwise) or a negative one
/// (clockwise – arcs in a polyline); the parameter always increases along the curve from `start`.
enum Primitive {
    case segment(a: CGPoint, b: CGPoint, param: CGFloat)
    case arc(center: CGPoint, radius: CGFloat, start: CGFloat, sweep: CGFloat, param: CGFloat)

    var length: CGFloat {
        switch self {
        case let .segment(a, b, _): return Geometry.distance(a, b)
        case let .arc(_, r, _, sweep, _): return r * abs(sweep)
        }
    }

    /// The same arc written counterclockwise (start, positive sweep).
    static func ccwForm(start: CGFloat, sweep: CGFloat) -> (start: CGFloat, sweep: CGFloat) {
        return sweep >= 0 ? (start, sweep) : (start + sweep, -sweep)
    }

    /// Angular distance of a point from the arc start in the arc's direction, in [0, 2π).
    static func arcDelta(start: CGFloat, sweep: CGFloat, to angle: CGFloat) -> CGFloat {
        return sweep >= 0 ? Geometry.ccwDelta(from: start, to: angle) : Geometry.ccwDelta(from: angle, to: start)
    }

    func distance(to p: CGPoint) -> CGFloat {
        switch self {
        case let .segment(a, b, _):
            return Geometry.distance(from: p, toSegmentFrom: a, to: b)
        case let .arc(c, r, start, sweep, _):
            let f = Primitive.ccwForm(start: start, sweep: sweep)
            return Geometry.distance(from: p, toArcCenter: c, radius: r, start: f.start, sweep: f.sweep)
        }
    }

    /// Nearest point and its parameter (length from the start of the curve).
    func closestParameter(to p: CGPoint) -> CGFloat {
        switch self {
        case let .segment(a, b, param):
            let t = max(0, min(1, Geometry.projectionParameter(of: p, ontoSegmentFrom: a, to: b)))
            return param + t * Geometry.distance(a, b)
        case let .arc(c, r, start, sweep, param):
            let delta = Primitive.arcDelta(start: start, sweep: sweep, to: Geometry.angle(from: c, to: p))
            let w = abs(sweep)
            if delta <= w { return param + delta * r }
            // outside the arc – the nearer end
            let toStart = Geometry.distance(p, Geometry.pointOnCircle(c, r, start))
            let toEnd = Geometry.distance(p, Geometry.pointOnCircle(c, r, start + sweep))
            return toStart <= toEnd ? param : param + w * r
        }
    }

    /// Intersections with another piece. Returns the points and parameters on THIS piece.
    func intersections(with other: Primitive) -> [(point: CGPoint, param: CGFloat)] {
        switch (self, other) {
        case let (.segment(a1, a2, p), .segment(b1, b2, _)):
            guard let hit = Geometry.segmentIntersection(a1, a2, b1, b2) else { return [] }
            return [(point: hit.point, param: p + hit.ta * Geometry.distance(a1, a2))]

        case let (.segment(a1, a2, p), .arc(c, r, start, sweep, _)):
            let length = Geometry.distance(a1, a2)
            let f = Primitive.ccwForm(start: start, sweep: sweep)
            return Geometry.segmentCircleIntersections(a1, a2, center: c, radius: r)
                .filter { Primitive.isAngle(Geometry.angle(from: c, to: $0.point), onArcStart: f.start, sweep: f.sweep) }
                .map { (point: $0.point, param: p + $0.t * length) }

        case let (.arc(c, r, start, sweep, p), .segment(b1, b2, _)):
            let w = abs(sweep)
            return Geometry.segmentCircleIntersections(b1, b2, center: c, radius: r)
                .compactMap { hit -> (point: CGPoint, param: CGFloat)? in
                    let delta = Primitive.arcDelta(start: start, sweep: sweep, to: Geometry.angle(from: c, to: hit.point))
                    guard Primitive.isDelta(delta, withinSweep: w) else { return nil }
                    return (hit.point, p + Primitive.clampedDelta(delta, sweep: w) * r)
                }

        case let (.arc(c1, r1, s1, w1, p), .arc(c2, r2, s2, w2, _)):
            let sweep1 = abs(w1)
            let f2 = Primitive.ccwForm(start: s2, sweep: w2)
            return Geometry.circleCircleIntersections(c1, r1, c2, r2)
                .compactMap { point -> (point: CGPoint, param: CGFloat)? in
                    let delta = Primitive.arcDelta(start: s1, sweep: w1, to: Geometry.angle(from: c1, to: point))
                    guard Primitive.isDelta(delta, withinSweep: sweep1),
                          Primitive.isAngle(Geometry.angle(from: c2, to: point), onArcStart: f2.start, sweep: f2.sweep) else { return nil }
                    return (point, p + Primitive.clampedDelta(delta, sweep: sweep1) * r1)
                }
        }
    }

    static func isAngle(_ angle: CGFloat, onArcStart start: CGFloat, sweep: CGFloat) -> Bool {
        return isDelta(Geometry.ccwDelta(from: start, to: angle), withinSweep: sweep)
    }

    /// Angular distance from the arc start clamped to [0, sweep] (values just below 2π = start).
    static func clampedDelta(_ delta: CGFloat, sweep: CGFloat) -> CGFloat {
        if delta <= sweep { return delta }
        return delta > (sweep + 2 * .pi) / 2 ? 0 : sweep
    }

    /// Delta in [0, 2π); tolerance around both the start and the end of the arc.
    static func isDelta(_ delta: CGFloat, withinSweep sweep: CGFloat) -> Bool {
        let tolerance: CGFloat = 1e-7
        return delta <= sweep + tolerance || delta >= 2 * .pi - tolerance
    }
}
