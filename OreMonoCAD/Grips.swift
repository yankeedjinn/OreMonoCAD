//
//  Grips.swift
//  OreMonoCAD
//
//  Grips of selected objects: click a grip, then click / drag
//  to a new place to move that point of the object (rectangle corner, line end, circle radius…).
//

import Cocoa

enum Grips {

    /// Grip kind – determines how it is drawn (square = point, diamond = segment midpoint, circle = center).
    enum Kind { case point, midpoint, center }

    struct Grip {
        let point: CGPoint
        let kind: Kind
    }

    /// The object's grips, in the order referenced by the index in `moved(_:grip:to:)`.
    static func grips(of entity: CADEntity) -> [Grip] {
        switch entity {
        case let line as Line:
            return [Grip(point: line.startPoint, kind: .point),
                    Grip(point: line.endPoint, kind: .point),
                    Grip(point: Geometry.midpoint(line.startPoint, line.endPoint), kind: .midpoint)]

        case let circle as Circle:
            var result = [Grip(point: circle.center, kind: .center)]
            for i in 0..<4 {
                result.append(Grip(point: Geometry.pointOnCircle(circle.center, circle.radius, CGFloat(i) * .pi / 2), kind: .point))
            }
            return result

        case let arc as Arc:
            return [Grip(point: arc.startPoint, kind: .point),
                    Grip(point: arc.endPoint, kind: .point),
                    Grip(point: arc.midPoint, kind: .midpoint),
                    Grip(point: arc.center, kind: .center)]

        case let polyline as Polyline:
            var result = polyline.vertices.map { Grip(point: $0, kind: .point) }
            for primitive in polyline.primitives() {
                switch primitive {
                case let .segment(a, b, _):
                    result.append(Grip(point: Geometry.midpoint(a, b), kind: .midpoint))
                case let .arc(c, r, start, sweep, _):
                    result.append(Grip(point: Geometry.pointOnCircle(c, r, start + sweep / 2), kind: .midpoint))
                }
            }
            return result

        case let spline as Spline:
            return spline.controlPoints.map { Grip(point: $0, kind: .point) }

        case let ellipse as Ellipse:
            // center, ends of the major and minor axis, plus the ends for an arc
            var result = [Grip(point: ellipse.center, kind: .center)]
            for i in 0..<4 { result.append(Grip(point: ellipse.point(at: CGFloat(i) * .pi / 2), kind: .point)) }
            if !ellipse.isFull {
                result.append(Grip(point: ellipse.startPoint, kind: .point))
                result.append(Grip(point: ellipse.endPoint, kind: .point))
            }
            return result

        case let dimension as DimensionEntity:
            return dimension.points.map { Grip(point: $0, kind: .point) }

        case let text as TextEntity:
            return [Grip(point: text.position, kind: .point)]

        case let reference as BlockReference:
            return [Grip(point: reference.position, kind: .point)]

        case let hatch as HatchEntity:
            // first the vertices of all loops (outer + islands), then the edge midpoints
            var result: [Grip] = []
            for loop in hatch.loops { result += loop.map { Grip(point: $0, kind: .point) } }
            for loop in hatch.loops where loop.count >= 2 {
                for i in loop.indices {
                    result.append(Grip(point: Geometry.midpoint(loop[i], loop[(i + 1) % loop.count]), kind: .midpoint))
                }
            }
            return result

        case let xline as ConstructionLine:
            // ray: grip at the origin (moves the start); construction line: the point it passes through
            return [Grip(point: xline.point, kind: xline.isRay ? .point : .center)]

        case let viewport as ViewportEntity:
            // corners resize (the opposite corner stays), the center moves
            return viewport.corners.map { Grip(point: $0, kind: .point) }
                + [Grip(point: CGPoint(x: viewport.rect.midX, y: viewport.rect.midY), kind: .center)]

        case let image as ImageEntity:
            // corners resize the picture (the opposite corner stays, the proportions too), the center moves it
            return image.corners.map { Grip(point: $0, kind: .point) }
                + [Grip(point: Geometry.midpoint(image.origin, image.oppositeCorner), kind: .center)]

        case let wipeout as WipeoutEntity:
            // the corners, then the edge midpoints (an edge moves as a whole)
            let corners = wipeout.vertices
            return corners.map { Grip(point: $0, kind: .point) }
                + corners.indices.map { Grip(point: Geometry.midpoint(corners[$0], corners[($0 + 1) % corners.count]), kind: .midpoint) }

        default:
            return []
        }
    }

    /// A copy of the object with grip `index` moved to point `target` (nil = not possible).
    static func moved(_ entity: CADEntity, grip index: Int, to target: CGPoint) -> CADEntity? {
        let grips = grips(of: entity)
        guard index >= 0, index < grips.count else { return nil }
        let base = grips[index].point
        let delta = target - base

        switch entity {
        case let xline as ConstructionLine:
            let copy = xline.clone() as! ConstructionLine
            copy.point = target
            return copy

        case let line as Line:
            let copy = line.clone() as! Line
            switch index {
            case 0: copy.startPoint = target
            case 1: copy.endPoint = target
            default:
                copy.startPoint = line.startPoint + delta
                copy.endPoint = line.endPoint + delta
            }
            guard Geometry.distance(copy.startPoint, copy.endPoint) > Geometry.epsilon else { return nil }
            return copy

        case let circle as Circle:
            let copy = circle.clone() as! Circle
            if index == 0 {
                copy.center = target
            } else {
                let radius = Geometry.distance(circle.center, target)
                guard radius > Geometry.epsilon else { return nil }
                copy.radius = radius
            }
            return copy

        case let arc as Arc:
            let copy = arc.clone() as! Arc
            switch index {
            case 0, 1:
                // the end moves along the circle – the other end stays, the arc passes through its midpoint
                let start = index == 0 ? target : arc.startPoint
                let end = index == 1 ? target : arc.endPoint
                return arcThrough(start, arc.midPoint, end, like: arc) ?? {
                    // collinear points → at least the angle on the original circle
                    let angle = Geometry.angle(from: arc.center, to: target)
                    if index == 0 { copy.startAngle = Geometry.normalizeAngle(angle) } else { copy.endAngle = Geometry.normalizeAngle(angle) }
                    return copy
                }()
            case 2:
                // arc midpoint: the arc passes through both ends and the new point
                return arcThrough(arc.startPoint, target, arc.endPoint, like: arc)
            default:
                copy.center = target
                return copy
            }

        case let polyline as Polyline:
            let n = polyline.vertices.count
            var vertices = polyline.vertices
            var bulges = (0..<n).map { polyline.bulge(at: $0) }
            if index < n {
                vertices[index] = target
            } else {
                let segment = index - n
                let (a, b) = polyline.segmentEnds(segment)
                let next = (segment + 1) % n
                if polyline.bulge(at: segment) == 0 {
                    // straight segment: moves as a whole (both its vertices)
                    vertices[segment] = a + delta
                    vertices[next] = b + delta
                } else {
                    // arc segment: the arc will pass through the new point
                    let chord = Geometry.distance(a, b)
                    guard chord > Geometry.epsilon else { return nil }
                    let u = (b - a) * (1 / chord)
                    // height above the chord: positive to the right of the direction = positive bulge
                    let height = -(target - Geometry.midpoint(a, b)).dot(u.perpendicular)
                    guard abs(height) > Geometry.epsilon else {
                        bulges[segment] = 0
                        return rebuilt(polyline, vertices, bulges)
                    }
                    bulges[segment] = 2 * height / chord
                }
            }
            return rebuilt(polyline, vertices, bulges)

        case let spline as Spline:
            var points = spline.controlPoints
            points[index] = target
            let copy = Spline(controlPoints: points, closed: spline.closed, layer: spline.layer, color: spline.color)
            return spline.copyStyle(to: copy)

        case let ellipse as Ellipse:
            let copy = ellipse.clone() as! Ellipse
            switch index {
            case 0:
                copy.center = target
            case 1, 3:
                // end of the major axis: new direction and length, the minor semi-axis stays
                let b = ellipse.minorRadius
                var axis = target - ellipse.center
                if index == 3 { axis = axis * -1 }
                guard axis.length > Geometry.epsilon else { return nil }
                return Ellipse(center: ellipse.center, majorAxis: axis, ratio: b / axis.length,
                               startParam: ellipse.startParam, endParam: ellipse.endParam,
                               layer: ellipse.layer, color: ellipse.color).withStyle(of: ellipse)
            case 2, 4:
                // end of the minor axis: new length of the minor semi-axis
                let u = ellipse.majorAxis.normalized.perpendicular
                let b = abs((target - ellipse.center).dot(u))
                guard b > Geometry.epsilon, ellipse.majorRadius > 0 else { return nil }
                return Ellipse(center: ellipse.center, majorAxis: ellipse.majorAxis, ratio: b / ellipse.majorRadius,
                               startParam: ellipse.startParam, endParam: ellipse.endParam,
                               layer: ellipse.layer, color: ellipse.color).withStyle(of: ellipse)
            case 5:
                copy.startParam = Geometry.normalizeAngle(ellipse.parameter(atPoint: target))
            default:
                copy.endParam = Geometry.normalizeAngle(ellipse.parameter(atPoint: target))
            }
            return copy

        case let dimension as DimensionEntity:
            let copy = dimension.clone() as! DimensionEntity
            copy.points[index] = target
            return copy

        case let text as TextEntity:
            let copy = text.clone() as! TextEntity
            copy.position = target
            return copy

        case let reference as BlockReference:
            let copy = reference.clone() as! BlockReference
            copy.position = target
            return copy

        case let hatch as HatchEntity:
            var loops = hatch.loops
            let vertexCount = loops.reduce(0) { $0 + $1.count }
            // index → (loop, vertex); for an edge midpoint both end vertices move
            func locate(_ flat: Int) -> (loop: Int, vertex: Int)? {
                var rest = flat
                for (l, loop) in loops.enumerated() {
                    if rest < loop.count { return (l, rest) }
                    rest -= loop.count
                }
                return nil
            }
            if index < vertexCount {
                guard let at = locate(index) else { return nil }
                loops[at.loop][at.vertex] = target
            } else {
                guard let at = locate(index - vertexCount) else { return nil }
                let n = loops[at.loop].count
                loops[at.loop][at.vertex] = loops[at.loop][at.vertex] + delta
                loops[at.loop][(at.vertex + 1) % n] = loops[at.loop][(at.vertex + 1) % n] + delta
            }
            // the loop must not collapse into a line
            guard let outer = loops.first, abs(HatchEntity.signedArea(outer)) > Geometry.epsilon else { return nil }
            let copy = hatch.clone() as! HatchEntity
            copy.loops = loops
            return copy

        case let viewport as ViewportEntity:
            let copy = viewport.clone() as! ViewportEntity
            if index < 4 {
                let opposite = viewport.corners[(index + 2) % 4]
                let rect = CGRect(x: min(opposite.x, target.x), y: min(opposite.y, target.y),
                                  width: abs(target.x - opposite.x), height: abs(target.y - opposite.y))
                guard rect.width > 1, rect.height > 1 else { return nil }
                copy.rect = rect
                // the model stays in place: the viewport center moves together with the rectangle
                let k = 1 / max(viewport.paperMMPerUnit(), 1e-12)
                let shift = CGPoint(x: rect.midX - viewport.rect.midX, y: rect.midY - viewport.rect.midY)
                copy.modelCenter = viewport.modelCenter + shift * k
            } else {
                copy.rect = viewport.rect.offsetBy(dx: delta.x, dy: delta.y)
            }
            return copy

        case let image as ImageEntity:
            let copy = image.clone() as! ImageEntity
            if index < 4 {
                let corners = image.corners
                let opposite = corners[(index + 2) % 4]
                let diagonal = corners[index] - opposite
                let length2 = diagonal.dot(diagonal)
                guard length2 > 1e-18 else { return nil }
                let factor = (target - opposite).dot(diagonal) / length2
                guard factor > 1e-6, factor.isFinite else { return nil }
                copy.applyTransform(CGAffineTransform(translationX: opposite.x, y: opposite.y)
                    .scaledBy(x: factor, y: factor).translatedBy(x: -opposite.x, y: -opposite.y))
            } else {
                copy.applyTransform(CGAffineTransform(translationX: delta.x, y: delta.y))
            }
            return copy

        case let wipeout as WipeoutEntity:
            var corners = wipeout.vertices
            let n = corners.count
            guard n >= 3 else { return nil }
            if index < n {
                corners[index] = target
            } else {
                let edge = index - n
                corners[edge] = corners[edge] + delta
                corners[(edge + 1) % n] = corners[(edge + 1) % n] + delta
            }
            // the area must not collapse into a line
            guard abs(HatchEntity.signedArea(corners)) > Geometry.epsilon else { return nil }
            let copy = wipeout.clone() as! WipeoutEntity
            copy.vertices = corners
            return copy

        default:
            return nil
        }
    }

    private static func rebuilt(_ polyline: Polyline, _ vertices: [CGPoint], _ bulges: [CGFloat]) -> Polyline {
        let copy = Polyline(vertices: vertices, closed: polyline.closed, bulges: bulges, layer: polyline.layer, color: polyline.color)
        copy.width = polyline.width
        return polyline.copyStyle(to: copy)
    }

    /// An arc from `start` through `through` to `end` (in the direction those points give).
    private static func arcThrough(_ start: CGPoint, _ through: CGPoint, _ end: CGPoint, like arc: Arc) -> Arc? {
        guard let circle = Geometry.circleThrough(start, through, end), circle.radius > Geometry.epsilon else { return nil }
        let a1 = Geometry.angle(from: circle.center, to: start)
        let am = Geometry.angle(from: circle.center, to: through)
        let a2 = Geometry.angle(from: circle.center, to: end)
        // counterclockwise from start to end if it passes through `through`, otherwise the other way
        let ccw = Geometry.ccwDelta(from: a1, to: am) <= Geometry.ccwDelta(from: a1, to: a2)
        let result = ccw
            ? Arc(center: circle.center, radius: circle.radius, startAngle: a1, endAngle: a2, layer: arc.layer, color: arc.color)
            : Arc(center: circle.center, radius: circle.radius, startAngle: a2, endAngle: a1, layer: arc.layer, color: arc.color)
        return arc.copyStyle(to: result)
    }
}
