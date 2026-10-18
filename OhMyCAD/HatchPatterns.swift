//
//  HatchPatterns.swift
//  OhMyCAD
//
//  Hatch patterns: built-in and custom, text definition (same as AutoCAD .pat),
//  pattern line generator, previews and an editor for custom patterns.
//
//  Each definition line is one family of parallel lines:
//      angle, origin X, origin Y, shift along the line, line spacing [, dash, gap, …]
//  Lengths are in mm (at hatch scale 1). Dashes: positive = line, negative = gap, 0 = dot.
//  Example – bricks:   0, 0,0, 0,3
//                     90, 0,0, 3,3, 3,-3
//

import Cocoa

// MARK: - Line Family

/// One family of parallel pattern lines.
struct HatchLineFamily: Equatable {
    var angle: CGFloat          // degrees
    var origin: CGPoint         // origin (pattern units)
    var shift: CGFloat          // shift along the line between adjacent lines
    var spacing: CGFloat        // perpendicular distance between lines
    var dashes: [CGFloat]       // + line, − gap, 0 dot; empty = solid line

    var definition: String {
        let values = [angle, origin.x, origin.y, shift, spacing] + dashes
        return values.map { LineType.format($0) }.joined(separator: ", ")
    }
}

// MARK: - Hatch Pattern

struct HatchPattern: Equatable {
    var name: String
    var description: String
    var families: [HatchLineFamily]
    var isSolid = false
    var isBuiltIn = false

    var title: String { return name }
    var detail: String { return description }

    /// Definition text (one family per line).
    var definition: String {
        return isSolid ? "SOLID" : families.map { $0.definition }.joined(separator: "\n")
    }

    /// Smallest line spacing (pattern units) – for estimating density.
    var smallestSpacing: CGFloat {
        return families.map { abs($0.spacing) }.filter { $0 > 0 }.min() ?? 1
    }

    // MARK: Text definition

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { return message }
    }

    /// Parses a definition. Lines with “;” are comments, the header “*NAME, description” (as in .pat) is skipped.
    static func parseFamilies(_ text: String) throws -> [HatchLineFamily] {
        var families: [HatchLineFamily] = []
        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            var line = rawLine
            if let comment = line.firstIndex(of: ";") { line = String(line[..<comment]) }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("*") { continue }

            var values: [CGFloat] = []
            for token in line.components(separatedBy: CharacterSet(charactersIn: ", \t")) where !token.isEmpty {
                guard let value = ExpressionEvaluator.evaluate(token) else {
                    throw ParseError(message: "Line \(index + 1): “\(token)” is not a number.")
                }
                values.append(CGFloat(value))
            }
            guard values.count >= 5 else {
                throw ParseError(message: "Line \(index + 1): needs at least 5 numbers – angle, origin X, origin Y, shift, spacing.")
            }
            guard abs(values[4]) > 1e-6 else {
                throw ParseError(message: "Line \(index + 1): the spacing (5th number) cannot be 0.")
            }
            let dashes = Array(values.dropFirst(5))
            guard dashes.count <= 12 else {
                throw ParseError(message: "Line \(index + 1): use at most 12 dash values.")
            }
            if !dashes.isEmpty {
                guard dashes.contains(where: { $0 < 0 }) else {
                    throw ParseError(message: "Line \(index + 1): a dashed line needs at least one gap (negative number).")
                }
                guard dashes.reduce(0, { $0 + abs($1) }) > 1e-3 else {
                    throw ParseError(message: "Line \(index + 1): the dash pattern is too short.")
                }
            }
            families.append(HatchLineFamily(angle: values[0], origin: CGPoint(x: values[1], y: values[2]),
                                            shift: values[3], spacing: values[4], dashes: dashes))
        }
        guard !families.isEmpty else { throw ParseError(message: "Enter at least one line.") }
        guard families.count <= 16 else { throw ParseError(message: "Use at most 16 lines.") }
        return families
    }

    /// Name and description from the header “*NAME, description”, if the text contains it (pasted .pat).
    static func header(in text: String) -> (name: String, description: String)? {
        guard let line = text.components(separatedBy: .newlines)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { $0.hasPrefix("*") }) else { return nil }
        let body = String(line.dropFirst())
        let parts = body.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard let name = parts.first, !name.isEmpty else { return nil }
        return (name, parts.count > 1 ? parts[1] : "")
    }

    // MARK: Built-in patterns (sizes in mm)

    private static func builtIn(_ name: String, _ description: String, _ text: String) -> HatchPattern {
        // built-in definitions are fixed and valid
        let families = (try? parseFamilies(text)) ?? []
        return HatchPattern(name: name, description: description, families: families, isBuiltIn: true)
    }

    static let solid = HatchPattern(name: "Solid fill", description: "Fills the area with the layer color",
                                    families: [], isSolid: true, isBuiltIn: true)
    static let lines = builtIn("Lines", "Parallel lines at 45° (classic section hatch)", "45, 0,0, 0,3")

    static let builtIns: [HatchPattern] = [
        solid,
        lines,
        builtIn("Cross-hatch", "Two sets of lines at right angles", "45, 0,0, 0,3\n135, 0,0, 0,3"),
        builtIn("Grid", "Square grid", "0, 0,0, 0,3\n90, 0,0, 0,3"),
        builtIn("Dots", "A regular grid of dots", "0, 0,0, 0,2, 0,-2"),
        builtIn("Brick", "Brick courses, joints offset by half a brick", "0, 0,0, 0,3\n90, 0,0, 3,3, 3,-3"),
        builtIn("Dashed", "Dashed lines at 45°", "45, 0,0, 2,3, 3,-1.5"),
        builtIn("Earth", "Earth / soil (crossed groups of short lines)",
                "0, 0,0, 4,4, 4,-4\n0, 0,1, 4,4, 4,-4\n0, 0,2, 4,4, 4,-4\n90, 0,0, 4,4, 4,-4\n90, 1,0, 4,4, 4,-4\n90, 2,0, 4,4, 4,-4")
    ]
}

// MARK: - Pattern Library

/// All available patterns: built-in + custom (remembered between launches).
enum HatchPatternLibrary {
    private static let customKey = "OhMyCAD.customHatchPatterns"

    static var all: [HatchPattern] {
        var result = HatchPattern.builtIns
        for pattern in custom where !result.contains(where: { $0.name.caseInsensitiveCompare(pattern.name) == .orderedSame }) {
            result.append(pattern)
        }
        return result
    }

    static var custom: [HatchPattern] {
        get {
            let stored = UserDefaults.standard.array(forKey: customKey) as? [[String: String]] ?? []
            return stored.compactMap { entry in
                guard let name = entry["name"], let text = entry["definition"],
                      let families = try? HatchPattern.parseFamilies(text) else { return nil }
                return HatchPattern(name: name, description: entry["description"] ?? "", families: families)
            }
        }
        set {
            let stored = newValue.map { ["name": $0.name, "description": $0.description, "definition": $0.definition] }
            UserDefaults.standard.set(stored, forKey: customKey)
        }
    }

    static func addCustom(_ pattern: HatchPattern) {
        var list = custom.filter { $0.name.caseInsensitiveCompare(pattern.name) != .orderedSame }
        list.append(pattern)
        custom = list
    }

    static func removeCustom(named name: String) {
        custom = custom.filter { $0.name.caseInsensitiveCompare(name) != .orderedSame }
    }

    static func named(_ name: String) -> HatchPattern? {
        return all.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    static func isBuiltInName(_ name: String) -> Bool {
        return HatchPattern.builtIns.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

// MARK: - Pattern Generator

/// Creates the pattern lines and dots covering a rectangle (in world coordinates).
enum HatchPatternGenerator {
    struct Output {
        var segments: [(CGPoint, CGPoint)] = []
        var dots: [CGPoint] = []
    }

    /// - Parameters:
    ///   - angle: rotation of the whole pattern (radians)
    ///   - scale: world units per pattern unit (mm)
    ///   - origin: pattern origin in the world
    ///   - limit: maximum number of elements; returns nil when exceeded (the pattern is too dense)
    static func generate(_ pattern: HatchPattern, angle: CGFloat, scale: CGFloat, origin: CGPoint = .zero,
                         covering rect: CGRect, limit: Int = 60_000) -> Output? {
        guard !pattern.isSolid, scale > 0, scale.isFinite, !rect.isNull, rect.width > 0 || rect.height > 0 else {
            return Output()
        }
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
        let rotation = CGAffineTransform(rotationAngle: angle)
        var output = Output()

        for family in pattern.families where abs(family.spacing) > 1e-9 {
            let a = family.angle * .pi / 180 + angle
            let u = CGPoint(x: cos(a), y: sin(a))
            let n = u.perpendicular
            let o = CGPoint(x: family.origin.x * scale, y: family.origin.y * scale).applying(rotation)
            let base = origin + o
            let step = u * (family.shift * scale) + n * (family.spacing * scale)
            let spacing = family.spacing * scale

            let ks = corners.map { ($0 - base).dot(n) / spacing }
            guard ks.allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else { return nil }
            let kMin = Int(floor(ks.min()!)), kMax = Int(ceil(ks.max()!))
            guard kMax - kMin < limit else { return nil }

            let period = family.dashes.reduce(0) { $0 + abs($1) } * scale
            for k in kMin...kMax {
                let p = base + step * CGFloat(k)
                let ts = corners.map { ($0 - p).dot(u) }
                let tMin = ts.min()!, tMax = ts.max()!

                if family.dashes.isEmpty || period <= 1e-12 {
                    output.segments.append((p + u * tMin, p + u * tMax))
                } else {
                    guard (tMax - tMin) / period < CGFloat(limit) else { return nil }
                    var t = floor(tMin / period) * period
                    while t < tMax {
                        for element in family.dashes {
                            let length = abs(element) * scale
                            if element > 0 {
                                let a1 = max(t, tMin), b1 = min(t + length, tMax)
                                if b1 > a1 { output.segments.append((p + u * a1, p + u * b1)) }
                            } else if element == 0, t >= tMin, t <= tMax {
                                output.dots.append(p + u * t)
                            }
                            t += length
                        }
                    }
                }
                if output.segments.count + output.dots.count > limit { return nil }
            }
        }
        return output
    }
}

// MARK: - Previews

enum HatchPatternPreview {
    /// A small image of the pattern (for menus). Built-in patterns have a hand-drawn icon.
    static func image(for pattern: HatchPattern, size: CGFloat = 22) -> NSImage {
        if let icon = ToolIcons.image(forPatternNamed: pattern.name, size: size), pattern.isBuiltIn {
            return icon
        }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let frame = rect.insetBy(dx: size * 0.19, dy: size * 0.19)
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(pattern, in: context, rect: frame, angle: 0, pointsPerUnit: frame.width / max(pattern.smallestSpacing * 4, 1e-3),
                 color: .black, lineWidth: 0.8)
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(1)
            context.stroke(frame)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Draws the pattern into a rectangle (screen coordinates).
    static func draw(_ pattern: HatchPattern, in context: CGContext, rect: CGRect, angle: CGFloat,
                     pointsPerUnit: CGFloat, color: NSColor, lineWidth: CGFloat) {
        context.saveGState()
        context.clip(to: rect)
        if pattern.isSolid {
            context.setFillColor(color.cgColor)
            context.fill(rect)
        } else if let output = HatchPatternGenerator.generate(pattern, angle: angle, scale: pointsPerUnit,
                                                              origin: CGPoint(x: rect.minX, y: rect.minY),
                                                              covering: rect, limit: 20_000) {
            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)
            context.setLineWidth(lineWidth)
            context.setLineCap(.butt)
            for (a, b) in output.segments {
                context.move(to: a)
                context.addLine(to: b)
            }
            context.strokePath()
            let r = max(0.6, lineWidth * 0.8)
            for p in output.dots { context.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)) }
            context.fillPath()
        }
        context.restoreGState()
    }
}

/// Large preview in the pattern editor.
final class HatchPatternPreviewView: NSView {
    var pattern: HatchPattern? { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        Theme.swatchBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        guard let pattern = pattern, let context = NSGraphicsContext.current?.cgContext else { return }
        let frame = bounds.insetBy(dx: 8, dy: 8)
        // about 6 repetitions of the smallest spacing across the preview height
        let pointsPerUnit = frame.height / max(pattern.smallestSpacing * 12, 1e-3)
        HatchPatternPreview.draw(pattern, in: context, rect: frame, angle: 0, pointsPerUnit: pointsPerUnit,
                                 color: .white, lineWidth: 1)
        Theme.swatchStroke.setStroke()
        NSBezierPath(rect: frame).stroke()
    }
}

// MARK: - Pattern Editor

/// The “Custom hatch pattern” dialog: name, description, line-by-line definition + live preview.
final class HatchPatternEditor: NSObject, NSTextViewDelegate {
    private let nameField = NSTextField()
    private let descriptionField = NSTextField()
    private let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 90))
    private let preview = HatchPatternPreviewView(frame: NSRect(x: 0, y: 0, width: 130, height: 130))
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    /// Shows the dialog; returns the new pattern, or nil if cancelled. `basedOn` pre-fills the definition.
    func run(basedOn template: HatchPattern? = nil) -> HatchPattern? {
        let alert = NSAlert()
        alert.messageText = "Custom Hatch Pattern"
        alert.informativeText = """
        One line per family of parallel lines (the common .pat pattern format, sizes in mm):
        angle, origin X, origin Y, shift along the line, spacing [, dash, gap, …]
        Dash: positive = line, negative = gap, 0 = dot. You can paste a whole .pat definition.
        """
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let width: CGFloat = 470
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: 230))
        var y: CGFloat = 230

        func row(_ caption: String, _ field: NSTextField, placeholder: String) {
            y -= 26
            let label = NSTextField(labelWithString: caption)
            label.frame = NSRect(x: 0, y: y + 3, width: 80, height: 17)
            label.alignment = .right
            container.addSubview(label)
            field.frame = NSRect(x: 86, y: y, width: width - 86, height: 22)
            field.placeholderString = placeholder
            container.addSubview(field)
        }
        row("Name:", nameField, placeholder: "e.g. Tiles")
        row("Description:", descriptionField, placeholder: "optional")

        // definition (multi-line) on the left, preview on the right
        y -= 8
        let previewSize: CGFloat = min(140, y - 30)
        let caption = NSTextField(labelWithString: "Definition:")
        caption.frame = NSRect(x: 0, y: y - 17, width: 80, height: 17)
        caption.alignment = .right
        container.addSubview(caption)

        let textWidth = width - 86 - previewSize - 10
        let scroll = NSScrollView(frame: NSRect(x: 86, y: y - previewSize, width: textWidth, height: previewSize))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        textView.frame = NSRect(x: 0, y: 0, width: textWidth, height: previewSize)
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.autoresizingMask = [.width]
        textView.delegate = self
        textView.string = template?.isSolid == false ? template!.definition : "0, 0,0, 0,4\n90, 0,0, 0,4, 2,-2"
        scroll.documentView = textView
        container.addSubview(scroll)

        preview.frame = NSRect(x: width - previewSize, y: y - previewSize, width: previewSize, height: previewSize)
        container.addSubview(preview)

        statusLabel.frame = NSRect(x: 86, y: 0, width: width - 86, height: y - previewSize - 4)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(statusLabel)

        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField
        updatePreview()

        while alert.runModal() == .alertFirstButtonReturn {
            do {
                let header = HatchPattern.header(in: textView.string)
                var name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
                if name.isEmpty, let fromHeader = header?.name { name = fromHeader }
                guard !name.isEmpty else { throw HatchPattern.ParseError(message: "Enter a name.") }
                guard !HatchPatternLibrary.isBuiltInName(name) else {
                    throw HatchPattern.ParseError(message: "A built-in pattern already uses this name.")
                }
                let families = try HatchPattern.parseFamilies(textView.string)
                var description = descriptionField.stringValue
                if description.isEmpty { description = header?.description ?? "" }
                return HatchPattern(name: name, description: description, families: families)
            } catch {
                statusLabel.stringValue = error.localizedDescription
                statusLabel.textColor = .systemRed
                NSSound.beep()
            }
        }
        return nil
    }

    func textDidChange(_ notification: Notification) {
        updatePreview()
    }

    private func updatePreview() {
        do {
            let families = try HatchPattern.parseFamilies(textView.string)
            preview.pattern = HatchPattern(name: "", description: "", families: families)
            let lineCount = families.count
            statusLabel.stringValue = "\(lineCount) line famil\(lineCount == 1 ? "y" : "ies") – preview on the right."
            statusLabel.textColor = .secondaryLabelColor
        } catch {
            preview.pattern = nil
            statusLabel.stringValue = error.localizedDescription
            statusLabel.textColor = .systemRed
        }
    }
}

// MARK: - Hatch Settings Dialog

/// Dialog for hatch angle and scale (for new hatches).
enum HatchSettingsDialog {
    /// Returns (angle in degrees, scale or nil = from the drawing scale).
    static func run(angle: CGFloat, scale: CGFloat?, drawingScale: DrawingScale) -> (angle: CGFloat, scale: CGFloat?)? {
        let alert = NSAlert()
        alert.messageText = "Hatch Angle & Scale"
        alert.informativeText = """
        Pattern sizes are in mm; the scale multiplies them.
        Leave Scale empty to follow the drawing scale (\(drawingScale.title) → \(LineType.format(drawingScale.factor))).
        Expressions work: 2*25, 100/4 …
        """
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        let angleField = NSTextField(frame: NSRect(x: 80, y: 30, width: 120, height: 22))
        let scaleField = NSTextField(frame: NSRect(x: 80, y: 2, width: 120, height: 22))
        angleField.stringValue = LineType.format(angle)
        scaleField.stringValue = scale.map { LineType.format($0) } ?? ""
        scaleField.placeholderString = "auto (\(LineType.format(drawingScale.factor)))"
        for (caption, field, y) in [("Angle °:", angleField, CGFloat(30)), ("Scale:", scaleField, 2)] {
            let label = NSTextField(labelWithString: caption)
            label.frame = NSRect(x: 0, y: y + 3, width: 74, height: 17)
            label.alignment = .right
            container.addSubview(label)
            container.addSubview(field)
        }
        alert.accessoryView = container
        alert.window.initialFirstResponder = angleField

        while alert.runModal() == .alertFirstButtonReturn {
            guard let newAngle = ExpressionEvaluator.evaluate(angleField.stringValue) else {
                alert.informativeText = "The angle is not a valid number."
                NSSound.beep()
                continue
            }
            let scaleText = scaleField.stringValue.trimmingCharacters(in: .whitespaces)
            if scaleText.isEmpty { return (CGFloat(newAngle), nil) }
            guard let newScale = ExpressionEvaluator.evaluate(scaleText), newScale > 0 else {
                alert.informativeText = "The scale must be a number greater than 0."
                NSSound.beep()
                continue
            }
            return (CGFloat(newAngle), CGFloat(newScale))
        }
        return nil
    }
}

// MARK: - Menu Builder

/// Shared pattern menu (tool panel and Tools menu): patterns, custom pattern, settings, removal.
enum HatchMenuBuilder {
    struct Actions {
        let target: AnyObject
        let choose: Selector        // representedObject = pattern name
        let newCustom: Selector
        let settings: Selector
        let removeCustom: Selector  // representedObject = pattern name
    }

    static func populate(_ menu: NSMenu, current: HatchPattern, angle: CGFloat, scaleText: String,
                         actions: Actions, imageSize: CGFloat, header: String?) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        if let header = header {
            let item = NSMenuItem(title: header, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        let custom = HatchPatternLibrary.custom
        for pattern in HatchPatternLibrary.all {
            if !pattern.isBuiltIn && pattern.name == custom.first?.name { menu.addItem(.separator()) }
            let item = NSMenuItem(title: pattern.name, action: actions.choose, keyEquivalent: "")
            item.target = actions.target
            item.representedObject = pattern.name
            item.image = HatchPatternPreview.image(for: pattern, size: imageSize)
            item.subtitle = pattern.description.isEmpty ? nil : pattern.description
            item.toolTip = pattern.isSolid ? nil : pattern.definition
            item.state = pattern.name == current.name ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let newItem = NSMenuItem(title: "Custom Pattern…", action: actions.newCustom, keyEquivalent: "")
        newItem.target = actions.target
        newItem.subtitle = "Define your own pattern as text, with a live preview"
        menu.addItem(newItem)

        let settingsItem = NSMenuItem(title: "Angle & Scale…", action: actions.settings, keyEquivalent: "")
        settingsItem.target = actions.target
        settingsItem.subtitle = "Now \(LineType.format(angle))°, scale \(scaleText)"
        menu.addItem(settingsItem)

        if !custom.isEmpty {
            let removeMenu = NSMenu(title: "Remove Custom Pattern")
            for pattern in custom {
                let item = NSMenuItem(title: pattern.name, action: actions.removeCustom, keyEquivalent: "")
                item.target = actions.target
                item.representedObject = pattern.name
                removeMenu.addItem(item)
            }
            let removeItem = NSMenuItem(title: "Remove Custom Pattern", action: nil, keyEquivalent: "")
            removeItem.submenu = removeMenu
            menu.addItem(removeItem)
        }
    }
}
