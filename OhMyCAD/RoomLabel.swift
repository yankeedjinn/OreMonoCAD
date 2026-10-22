//
//  RoomLabel.swift
//  OhMyCAD
//
//  Room label: an ordinary text (TextEntity.isRoomLabel) with the room name and, on its last line, the floor area in m².
//  The area is the closed outline around the label's insertion point – found like the outline of a hatch – and it is
//  measured again whenever the walls around change (MainViewController.applyChange), in the same undo step.
//

import Cocoa

enum RoomLabels {
    /// Gaps up to this size (mm on paper) are bridged when looking for the outline of a room.
    static let gapMM: CGFloat = 0.5
    /// Max. deviation when arcs are replaced with segments (mm on paper) – small enough that a curved wall
    /// changes the area by less than 0.01 m² (0.05 mm made a room with a 3 m round bay 0.03 m² smaller at 1:100).
    static let flatnessMM: CGFloat = 0.002
    /// Without a known outline (e.g. just opened) the room of a label is looked for this far around it (real mm).
    static let searchRadiusMM: CGFloat = 100_000
    /// The line with the area ends with this unit.
    static let unit = "m²"

    /// Objects that bound rooms: walls, lines, polylines, blocks… – not texts, dimensions, hatches, construction lines,
    /// wipeouts or images.
    static func isBoundary(_ entity: CADEntity) -> Bool {
        return !(entity is TextEntity) && !(entity is DimensionEntity) && !(entity is HatchEntity) && !(entity is ConstructionLine)
            && !(entity is WipeoutEntity) && !(entity is ImageEntity)
    }

    /// The finder of closed outlines among the visible boundary objects.
    static func finder(for entities: [CADEntity], unitsPerPaperMM: CGFloat) -> HatchRegionFinder {
        let scale = max(unitsPerPaperMM, 1e-9)
        return HatchRegionFinder(entities: entities.filter { isBoundary($0) }, gap: gapMM * scale, flatness: flatnessMM * scale)
    }

    /// The outline of the room around a point (without the objects standing free inside it), nil = not closed there.
    static func outline(at point: CGPoint, finder: HatchRegionFinder) -> [CGPoint]? {
        guard let loops = finder.region(at: point), let outer = loops.first, outer.count >= 3 else { return nil }
        return outer
    }

    /// The floor area of an outline in m².
    static func squareMeters(of outline: [CGPoint], mmPerUnit: CGFloat) -> CGFloat {
        let metersPerUnit = mmPerUnit / 1000
        return abs(HatchEntity.signedArea(outline)) * metersPerUnit * metersPerUnit
    }

    /// The area line: “24,35 m²” with the decimal separator of the system settings, “? m²” when no room was found.
    static func areaLine(_ squareMeters: CGFloat?) -> String {
        guard let value = squareMeters, value.isFinite else { return "? " + unit }
        let formatter = NumberFormatter()
        formatter.locale = Locale.current
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let number = formatter.string(from: NSNumber(value: Double(value))) ?? String(format: "%.2f", Double(value))
        return number + " " + unit
    }

    /// Is the line the area line of a room label (so it gets replaced)?
    static func isAreaLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(unit) else { return false }
        let number = trimmed.dropLast(unit.count)
        return number.allSatisfy { "0123456789.,?- \u{00A0}\u{202F}".contains($0) }
    }

    /// The label text with the area line replaced – or added below the name when there is none.
    static func text(_ text: String, withAreaLine area: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let last = lines.last, isAreaLine(last) {
            lines[lines.count - 1] = area
        } else if lines.count == 1 && lines[0].trimmingCharacters(in: .whitespaces).isEmpty {
            lines = [area]
        } else {
            lines.append(area)
        }
        return lines.joined(separator: "\n")
    }

    /// The text of a new label: the name (may be empty) and the area below it.
    static func newText(name: String, squareMeters: CGFloat?) -> String {
        return text(name, withAreaLine: areaLine(squareMeters))
    }

    /// Room labels whose area may have changed after objects were removed and added.
    /// - Returns: labels to replace (with updated copies) – the labels in `added` are updated in place.
    static func updates(documentEntities: [CADEntity], removed: [CADEntity], added: [CADEntity],
                        isVisible: (CADEntity) -> Bool, unitsPerPaperMM: CGFloat, mmPerUnit: CGFloat)
        -> (removed: [CADEntity], added: [CADEntity]) {
        let removedIDs = Set(removed.map { $0.id })
        let after = documentEntities.filter { !removedIDs.contains($0.id) } + added
        let labels = after.compactMap { $0 as? TextEntity }.filter { $0.isRoomLabel }
        guard !labels.isEmpty else { return ([], []) }

        // where the walls changed (a label without a known outline – e.g. just opened – is measured again)
        var changedBoxes: [CGRect] = []
        for entity in removed + added where isBoundary(entity) {
            let box = entity.boundingBox()
            if DrawingSafety.isValidWorld(box) { changedBoxes.append(box) }
        }
        let addedIDs = Set(added.map { $0.id })
        let affected = labels.filter { label in
            if addedIDs.contains(label.id) { return true }
            guard !changedBoxes.isEmpty else { return false }
            guard let bounds = label.roomBounds else { return true }
            let margin = max(bounds.width, bounds.height) * 0.01
            let area = bounds.insetBy(dx: -margin, dy: -margin)
            return changedBoxes.contains { $0.intersects(area) }
        }
        guard !affected.isEmpty else { return ([], []) }

        // only the objects around those labels can bound their rooms (a big drawing has a hundred thousand objects):
        // the last outline with half its size around it, or a wide square around a label not measured yet
        let areas = affected.map { label -> CGRect in
            if let bounds = label.roomBounds { return bounds.insetBy(dx: -bounds.width / 2 - 1, dy: -bounds.height / 2 - 1) }
            let r = searchRadiusMM / max(mmPerUnit, 1e-9)
            return CGRect(x: label.position.x - r, y: label.position.y - r, width: 2 * r, height: 2 * r)
        }
        let nearby = after.filter { entity in
            guard isBoundary(entity), isVisible(entity) else { return false }
            let box = entity.boundingBox()
            // compared by hand (mayMeet): CGRect.intersects is false for the flat box of a straight horizontal wall
            return areas.contains { EditOperations.mayMeet($0, box) }
        }
        let finder = self.finder(for: nearby, unitsPerPaperMM: unitsPerPaperMM)
        var replacedOld: [CADEntity] = []
        var replacedNew: [CADEntity] = []
        for label in affected {
            let outline = self.outline(at: label.position, finder: finder)
            let area = outline.map { squareMeters(of: $0, mmPerUnit: mmPerUnit) }
            let bounds = outline.map { points -> CGRect in
                points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
            }
            let updated = text(label.text, withAreaLine: areaLine(area))
            if addedIDs.contains(label.id) {
                // a new or just edited label is not in the drawing yet – it can change directly
                if updated != label.text { label.text = updated }
                label.roomBounds = bounds
            } else if updated != label.text, let copy = label.clone() as? TextEntity {
                copy.text = updated
                copy.roomBounds = bounds
                replacedOld.append(label)
                replacedNew.append(copy)
            } else {
                label.roomBounds = bounds
            }
        }
        return (replacedOld, replacedNew)
    }
}
