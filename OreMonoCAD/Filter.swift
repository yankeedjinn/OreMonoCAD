//
//  Filter.swift
//  OreMonoCAD
//
//  Edit › Filter…: selects the objects that match the properties you tick –
//  object type, layer, color, linetype, lineweight, block name, hatch pattern, text, text height, length and area.
//  An object must match all ticked ones.
//  It searches the open space (visible objects on unlocked layers) or only the current selection;
//  the result is an ordinary selection that the other tools work with.
//

import Cocoa

/// What the objects must match. nil = the property is not ticked.
struct FilterCriteria {
    enum Scope {
        case drawing, selection
    }

    /// A number the object's value is compared with (length, area, text height – in drawing units).
    struct NumberCondition {
        enum Comparison: Int, CaseIterable {
            case atLeast, atMost, equal

            var title: String {
                switch self {
                case .atLeast: return "at least"
                case .atMost: return "at most"
                case .equal: return "equal to"
                }
            }
        }

        var comparison: Comparison
        var value: CGFloat

        func holds(_ number: CGFloat) -> Bool {
            switch comparison {
            case .atLeast: return number >= value - tolerance
            case .atMost: return number <= value + tolerance
            case .equal: return abs(number - value) <= tolerance
            }
        }

        /// Values are shown with 3 decimals – what rounds to the typed number counts as equal.
        private var tolerance: CGFloat { return max(0.0005, abs(value) * 1e-9) }

        var summary: String { return comparison.title + " " + LineType.format(value) }
    }

    var type: String?
    var layer: String?
    /// Color as SelectSimilar.colorKey writes it (“bylayer” or sRGB in whole steps).
    var color: String?
    /// Linetype name – objects have no linetype of their own, it is the one of their layer.
    var lineType: String?
    /// Lineweight as ObjectFilter.lineWeightKey writes it (“bylayer” or mm).
    var lineWeight: String?
    var blockName: String?
    /// A piece of the text (texts, labels, dimension and leader texts), without regard to case.
    var text: String?
    var hatchPattern: String?
    /// Height of capital letters of a text, a label or a dimension text.
    var textHeight: NumberCondition?
    /// Length of a line, arc, polyline, spline… (a closed one: its perimeter).
    var length: NumberCondition?
    /// Area of a closed object or a hatch.
    var area: NumberCondition?
    var scope: Scope = .drawing
    /// The ticked properties in words, for the message (“layer Walls, color Red”).
    var summary = ""

    var isEmpty: Bool {
        return type == nil && layer == nil && color == nil && lineType == nil && lineWeight == nil
            && blockName == nil && text == nil && hatchPattern == nil && textHeight == nil && length == nil && area == nil
    }

    func matches(_ entity: CADEntity, layers: LayerManager) -> Bool {
        if let type = type, ObjectFilter.typeTitle(entity) != type { return false }
        if let layer = layer, entity.layer.caseInsensitiveCompare(layer) != .orderedSame { return false }
        if let color = color, SelectSimilar.colorKey(entity.color) != color { return false }
        if let lineType = lineType, layers.getLayer(entity.layer)?.lineType.name != lineType { return false }
        if let lineWeight = lineWeight, ObjectFilter.lineWeightKey(entity.lineWeight) != lineWeight { return false }
        if let blockName = blockName, (entity as? BlockReference)?.definition.name != blockName { return false }
        if let text = text, !ObjectFilter.texts(of: entity).contains(where: { $0.localizedCaseInsensitiveContains(text) }) {
            return false
        }
        if let pattern = hatchPattern, (entity as? HatchEntity)?.pattern.name != pattern { return false }
        if let condition = textHeight {
            guard let height = ObjectFilter.textHeight(of: entity), condition.holds(height) else { return false }
        }
        if let condition = length {
            guard let curve = entity as? CurveEntity, condition.holds(curve.curveLength) else { return false }
        }
        if let condition = area {
            guard let measured = Measure.areaAndPerimeter(of: entity), condition.holds(measured.area) else { return false }
        }
        return true
    }
}

enum ObjectFilter {
    /// The object type as the dialog lists it – leaders apart from dimensions.
    static func typeTitle(_ entity: CADEntity) -> String {
        if let dimension = entity as? DimensionEntity, dimension.kind == .leader { return "Leader" }
        return entity.typeName
    }

    /// The texts of an object that Text contains looks in (the same ones Find and Replace searches).
    static func texts(of entity: CADEntity) -> [String] {
        if let text = entity as? TextEntity { return [text.text] }
        if let dimension = entity as? DimensionEntity { return [dimension.text, dimension.belowText] }
        return []
    }

    static func textHeight(of entity: CADEntity) -> CGFloat? {
        if let text = entity as? TextEntity { return text.height }
        if let dimension = entity as? DimensionEntity { return dimension.textHeight }
        return nil
    }

    static func lineWeightKey(_ weight: CGFloat?) -> String {
        return weight.map { String(format: "%.4f", Double($0)) } ?? "bylayer"
    }

    /// One value to choose in the dialog.
    struct Choice {
        let title: String
        let key: String
        var image: NSImage? = nil
    }

    /// The values found in the objects, for each property of the dialog.
    static func typeChoices(_ entities: [CADEntity]) -> [Choice] {
        let names = Set(entities.map { typeTitle($0) })
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { Choice(title: $0, key: $0) }
    }

    /// Layers in the order of the layer list, only those that have objects.
    static func layerChoices(_ entities: [CADEntity], layers: LayerManager) -> [Choice] {
        var used: [String: String] = [:]   // lowercased → name as written on the object
        for entity in entities where used[entity.layer.lowercased()] == nil { used[entity.layer.lowercased()] = entity.layer }
        var result: [Choice] = []
        for layer in layers.getAllLayers() {
            guard used.removeValue(forKey: layer.name.lowercased()) != nil else { continue }
            result.append(Choice(title: layer.name, key: layer.name, image: PropertiesPanelView.swatch(layer.color)))
        }
        // objects on a layer that is not in the list (should not happen)
        for name in used.values.sorted() { result.append(Choice(title: name, key: name)) }
        return result
    }

    static func colorChoices(_ entities: [CADEntity]) -> [Choice] {
        var byLayer = false
        var colors: [String: NSColor] = [:]
        for entity in entities {
            guard let color = entity.color else { byLayer = true; continue }
            let key = SelectSimilar.colorKey(color)
            if colors[key] == nil { colors[key] = color }
        }
        var result: [Choice] = byLayer ? [Choice(title: "ByLayer", key: SelectSimilar.colorKey(nil))] : []
        // in the order of the color numbers (red, yellow, green… as in the color list)
        let sorted = colors.map { (key: $0.key, color: $0.value, index: ACIColor.index(for: $0.value)) }
            .sorted { ($0.index, $0.key) < ($1.index, $1.key) }
        let names = sorted.map { ACIColor.name(for: $0.color) }
        for (position, entry) in sorted.enumerated() {
            var title = names[position]
            // two different colors closest to the same named one – tell them apart by RGB
            if names.filter({ $0 == title }).count > 1 {
                title += " (" + entry.key.split(separator: ",").prefix(3).joined(separator: ", ") + ")"
            }
            result.append(Choice(title: title, key: entry.key, image: PropertiesPanelView.swatch(entry.color)))
        }
        return result
    }

    static func lineTypeChoices(_ entities: [CADEntity], layers: LayerManager) -> [Choice] {
        let names = Set(entities.compactMap { layers.getLayer($0.layer)?.lineType.name })
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { Choice(title: $0, key: $0) }
    }

    static func lineWeightChoices(_ entities: [CADEntity]) -> [Choice] {
        var byLayer = false
        var weights: [String: CGFloat] = [:]
        for entity in entities {
            guard let weight = entity.lineWeight else { byLayer = true; continue }
            weights[lineWeightKey(weight)] = weight
        }
        var result: [Choice] = byLayer ? [Choice(title: "ByLayer", key: lineWeightKey(nil))] : []
        for entry in weights.sorted(by: { $0.value < $1.value }) {
            result.append(Choice(title: LineWeights.title(entry.value), key: entry.key))
        }
        return result
    }

    static func hatchPatternChoices(_ entities: [CADEntity]) -> [Choice] {
        var names = Set<String>()
        for case let hatch as HatchEntity in entities { names.insert(hatch.pattern.name) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { Choice(title: $0, key: $0) }
    }

    static func blockChoices(_ entities: [CADEntity]) -> [Choice] {
        var names = Set<String>()
        for case let reference as BlockReference in entities { names.insert(reference.definition.name) }
        return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { Choice(title: $0, key: $0) }
    }
}

// MARK: - Dialog

/// The Edit › Filter… dialog: a row per property (tick box + value), and where to search.
final class FilterDialog: NSObject, NSTextFieldDelegate {
    /// The last settings – offered again next time (until the app quits).
    private static var last = FilterCriteria()

    private enum Property: Int, CaseIterable {
        case type, layer, color, lineType, lineWeight, blockName, hatchPattern, text, textHeight, length, area

        /// A number compared with the object's value (a comparison and a field instead of a list of values).
        var isNumber: Bool { return self == .textHeight || self == .length || self == .area }

        var title: String {
            switch self {
            case .type: return "Object type"
            case .layer: return "Layer"
            case .color: return "Color"
            case .lineType: return "Linetype (of the layer)"
            case .lineWeight: return "Lineweight"
            case .blockName: return "Block name"
            case .hatchPattern: return "Hatch pattern"
            case .text: return "Text contains"
            case .textHeight: return "Text height"
            case .length: return "Length"
            case .area: return "Area"
            }
        }

        /// The word in the message after filtering.
        var word: String {
            switch self {
            case .type: return "type"
            case .layer: return "layer"
            case .color: return "color"
            case .lineType: return "linetype"
            case .lineWeight: return "lineweight"
            case .blockName: return "block"
            case .hatchPattern: return "hatch pattern"
            case .text: return "text"
            case .textHeight: return "text height"
            case .length: return "length"
            case .area: return "area"
            }
        }

        var tip: String? {
            switch self {
            case .textHeight: return "Height of capital letters of texts, labels and dimension texts, in drawing units"
            case .length: return "Length of lines, arcs, polylines and other curves (of a closed one its perimeter), in drawing units"
            case .area: return "Area of closed shapes and hatches, in square drawing units"
            default: return nil
            }
        }
    }

    private var boxes: [Property: NSButton] = [:]
    private var popups: [Property: NSPopUpButton] = [:]
    private let textField = NSTextField(string: "")
    private var comparisons: [Property: NSPopUpButton] = [:]
    private var numberFields: [Property: NSTextField] = [:]
    private let scopePopup = NSPopUpButton()

    /// nil = Cancel.
    static func run(candidates: [CADEntity], selected: [CADEntity], layers: LayerManager) -> FilterCriteria? {
        let dialog = FilterDialog()
        return dialog.show(candidates: candidates, selected: selected, layers: layers)
    }

    private func show(candidates: [CADEntity], selected: [CADEntity], layers: LayerManager) -> FilterCriteria? {
        // values to choose from: everything that can be searched (the selection may hold locked objects too)
        let ids = Set(candidates.map { $0.id })
        let pool = candidates + selected.filter { !ids.contains($0.id) }
        let choices: [Property: [ObjectFilter.Choice]] = [
            .type: ObjectFilter.typeChoices(pool),
            .layer: ObjectFilter.layerChoices(pool, layers: layers),
            .color: ObjectFilter.colorChoices(pool),
            .lineType: ObjectFilter.lineTypeChoices(pool, layers: layers),
            .lineWeight: ObjectFilter.lineWeightChoices(pool),
            .blockName: ObjectFilter.blockChoices(pool),
            .hatchPattern: ObjectFilter.hatchPatternChoices(pool)
        ]
        let last = FilterDialog.last
        let lastKeys: [Property: String?] = [.type: last.type, .layer: last.layer, .color: last.color,
                                             .lineType: last.lineType, .lineWeight: last.lineWeight, .blockName: last.blockName,
                                             .hatchPattern: last.hatchPattern]
        let lastNumbers: [Property: FilterCriteria.NumberCondition?] = [.textHeight: last.textHeight, .length: last.length,
                                                                        .area: last.area]

        var rows: [[NSView]] = []
        for property in Property.allCases {
            let box = NSButton(checkboxWithTitle: property.title, target: nil, action: nil)
            box.toolTip = property.tip
            boxes[property] = box
            if property.isNumber {
                // a comparison and a number, side by side in the width of the other values
                let comparison = NSPopUpButton()
                for kind in FilterCriteria.NumberCondition.Comparison.allCases { comparison.addItem(withTitle: kind.title) }
                comparison.widthAnchor.constraint(equalToConstant: 100).isActive = true
                comparison.tag = property.rawValue
                comparison.target = self
                comparison.action = #selector(valueChosen(_:))
                let field = NSTextField(string: "")
                field.placeholderString = "number"
                field.toolTip = (property.tip.map { $0 + "\n" } ?? "") + "Type a value or an expression (e.g. 2*25)"
                field.delegate = self
                field.widthAnchor.constraint(equalToConstant: 122).isActive = true
                if let condition = lastNumbers[property] ?? nil {
                    comparison.selectItem(at: condition.comparison.rawValue)
                    field.stringValue = LineType.format(condition.value)
                    box.state = .on
                }
                comparisons[property] = comparison
                numberFields[property] = field
                let pair = NSStackView(views: [comparison, field])
                pair.spacing = 8
                rows.append([box, pair])
                continue
            }
            if property == .text {
                textField.placeholderString = "part of a text, label or dimension text"
                textField.stringValue = last.text ?? ""
                textField.delegate = self
                textField.widthAnchor.constraint(equalToConstant: 230).isActive = true
                box.state = last.text == nil ? .off : .on
                rows.append([box, textField])
                continue
            }
            let popup = NSPopUpButton()
            popup.autoenablesItems = false
            popup.widthAnchor.constraint(equalToConstant: 230).isActive = true
            let values = choices[property] ?? []
            for choice in values {
                popup.addItem(withTitle: choice.title)
                popup.lastItem?.representedObject = choice.key
                popup.lastItem?.image = choice.image
            }
            if values.isEmpty {
                popup.addItem(withTitle: property == .blockName ? "(no blocks here)" : property == .hatchPattern ? "(no hatches here)" : "(none)")
                popup.isEnabled = false
                box.isEnabled = false
            } else if let key = lastKeys[property] ?? nil, let index = values.firstIndex(where: { $0.key == key }) {
                popup.selectItem(at: index)
                box.state = .on
            }
            popup.tag = property.rawValue
            popup.target = self
            popup.action = #selector(valueChosen(_:))
            popups[property] = popup
            rows.append([box, popup])
        }

        // where to search – the selection, if there is one (so a second Filter narrows the result of the first)
        scopePopup.autoenablesItems = false
        scopePopup.addItem(withTitle: "Whole drawing (\(candidates.count) object\(candidates.count == 1 ? "" : "s"))")
        scopePopup.addItem(withTitle: "Current selection (\(selected.count) object\(selected.count == 1 ? "" : "s"))")
        scopePopup.lastItem?.isEnabled = !selected.isEmpty
        scopePopup.selectItem(at: selected.isEmpty ? 0 : 1)
        rows.append([NSTextField(labelWithString: "Search in:"), scopePopup])

        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline
        grid.row(at: rows.count - 1).topPadding = 10
        grid.frame.size = grid.fittingSize

        let alert = NSAlert()
        alert.messageText = "Filter"
        alert.informativeText = "Selects the objects that match all ticked properties. "
            + "Whole drawing = its visible objects on unlocked layers · Current selection = all selected objects."
        alert.addButton(withTitle: "Select")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = grid

        while alert.runModal() == .alertFirstButtonReturn {
            let criteria = read()
            guard !criteria.isEmpty else {
                alert.informativeText = "Tick at least one property (and type the text or the number next to it)."
                NSSound.beep()
                continue
            }
            FilterDialog.last = criteria
            return criteria
        }
        return nil
    }

    /// Picking a value ticks its property.
    @objc private func valueChosen(_ sender: NSPopUpButton) {
        guard let property = Property(rawValue: sender.tag) else { return }
        boxes[property]?.state = .on
    }

    /// Typing a text ticks Text contains, typing a number ticks its property.
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === textField {
            boxes[.text]?.state = textField.stringValue.isEmpty ? .off : .on
        } else if let property = numberFields.first(where: { $0.value === field })?.key {
            boxes[property]?.state = field.stringValue.isEmpty ? .off : .on
        }
    }

    private func read() -> FilterCriteria {
        var criteria = FilterCriteria()
        var parts: [String] = []
        for property in Property.allCases where boxes[property]?.state == .on {
            if property == .text {
                let text = textField.stringValue
                guard !text.isEmpty else { continue }
                criteria.text = text
                parts.append("text \u{201C}\(text)\u{201D}")
                continue
            }
            if property.isNumber {
                guard let field = numberFields[property],
                      let number = ExpressionEvaluator.evaluate(field.stringValue.trimmingCharacters(in: .whitespaces)),
                      number.isFinite else { continue }
                let kind = FilterCriteria.NumberCondition.Comparison(rawValue: comparisons[property]?.indexOfSelectedItem ?? 0) ?? .atLeast
                let condition = FilterCriteria.NumberCondition(comparison: kind, value: CGFloat(number))
                switch property {
                case .textHeight: criteria.textHeight = condition
                case .length: criteria.length = condition
                default: criteria.area = condition
                }
                parts.append(property.word + " " + condition.summary)
                continue
            }
            guard let item = popups[property]?.selectedItem, let key = item.representedObject as? String else { continue }
            switch property {
            case .type: criteria.type = key
            case .layer: criteria.layer = key
            case .color: criteria.color = key
            case .lineType: criteria.lineType = key
            case .lineWeight: criteria.lineWeight = key
            case .blockName: criteria.blockName = key
            case .hatchPattern: criteria.hatchPattern = key
            case .text, .textHeight, .length, .area: break
            }
            parts.append(property.word + " " + item.title)
        }
        criteria.scope = scopePopup.indexOfSelectedItem == 1 ? .selection : .drawing
        criteria.summary = parts.joined(separator: ", ")
        return criteria
    }
}
