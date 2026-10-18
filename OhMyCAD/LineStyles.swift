//
//  LineStyles.swift
//  OhMyCAD
//
//  Line types (built-in and custom), their text definition, previews
//  and dialogs for a custom line type and a custom lineweight.
//
//  The pattern definition is the same as in AutoCAD (.lin): numbers in mm on paper,
//  positive = dash, negative = gap, 0 = dot. E.g. “10, -3, 0, -3” = dash-dot.
//

import Cocoa

// MARK: - Line Type

struct LineType: Equatable {
    var name: String
    var description: String
    /// Pattern in mm on paper: + dash, − gap, 0 dot.
    var pattern: [CGFloat]
    var isBuiltIn = false

    /// Name in DXF (uppercase, no spaces).
    var dxfName: String {
        if let known = LineType.builtInDXFNames[name] { return known }
        return name.uppercased().replacingOccurrences(of: " ", with: "_")
    }

    var isContinuous: Bool { return pattern.isEmpty }

    /// Total length of one pattern period (mm).
    var patternLength: CGFloat { return pattern.reduce(0) { $0 + abs($1) } }

    /// Text notation of the pattern, e.g. “10, -3, 0, -3”.
    var definition: String {
        return pattern.map { LineType.format($0) }.joined(separator: ", ")
    }

    /// Pattern for on-screen drawing (points) at true size 1 mm = 2.83 points.
    var screenPattern: [CGFloat] {
        return dashPattern(pointsPerMM: 72 / 25.4)
    }

    /// Pattern for drawing (points): alternating dash, gap; `pointsPerMM` = how many points make 1 mm of the pattern.
    func dashPattern(pointsPerMM: CGFloat) -> [CGFloat] {
        guard !pattern.isEmpty, pointsPerMM > 0, pointsPerMM.isFinite else { return [] }
        var result: [CGFloat] = []
        var expectDash = true
        for element in pattern {
            let isDash = element >= 0
            let length = element == 0 ? 0.7 : abs(element) * pointsPerMM   // dot = short dash (0.7 points)
            if isDash == expectDash {
                result.append(length)
                expectDash.toggle()
            } else if let last = result.popLast() {
                result.append(last + length)                                // merge two consecutive dashes/gaps
            } else {
                result.append(0.01)                                         // the pattern starts with a gap
                result.append(length)
                expectDash = true
            }
        }
        if result.count % 2 == 1 { result.append(result.count > 1 ? 0.01 : result[0]) }
        return result.map { max($0, 0.01) }
    }

    static func format(_ value: CGFloat) -> String {
        var text = String(format: "%.3f", Double(value))
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    // MARK: Text definition

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { return message }
    }

    /// Parses a pattern notation. Numbers are separated by a comma, semicolon or space; they may also be expressions (2*3).
    static func parsePattern(_ text: String) throws -> [CGFloat] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        let separators = CharacterSet(charactersIn: ",; \t\n")
        var values: [CGFloat] = []
        for token in trimmed.components(separatedBy: separators) where !token.isEmpty {
            // ExpressionEvaluator must not treat a negative number as a decimal comma – we split on commas above
            guard let value = ExpressionEvaluator.evaluate(token) else {
                throw ParseError(message: "“\(token)” is not a number.")
            }
            values.append(CGFloat(value))
        }
        guard values.contains(where: { $0 > 0 }) || values.contains(0) else {
            throw ParseError(message: "The pattern needs at least one dash (positive number) or dot (0).")
        }
        guard values.contains(where: { $0 < 0 }) else {
            throw ParseError(message: "The pattern needs at least one gap (negative number).")
        }
        guard values.count <= 12 else {
            throw ParseError(message: "Use at most 12 elements.")
        }
        guard values.reduce(0, { $0 + abs($1) }) >= 0.5 else {
            throw ParseError(message: "The pattern is too short (at least 0.5 mm in total).")
        }
        return values
    }

    // MARK: Built-in types

    static let continuous = LineType(name: "Continuous", description: "Solid line", pattern: [], isBuiltIn: true)

    static let builtIns: [LineType] = [
        continuous,
        LineType(name: "Dashed", description: "Dashed line (dashes and gaps)", pattern: [3.5, -1.75], isBuiltIn: true),
        LineType(name: "Dotted", description: "Dotted line", pattern: [0, -1.05], isBuiltIn: true),
        LineType(name: "Dash-Dot", description: "Long dash and dot", pattern: [3.5, -1.75, 0, -1.75], isBuiltIn: true),
        LineType(name: "Dash-Dot-Dot", description: "Long dash and two dots", pattern: [3.5, -1.75, 0, -1.75, 0, -1.75], isBuiltIn: true),
        LineType(name: "Hidden", description: "Short dashes – hidden edges", pattern: [1.75, -1.75], isBuiltIn: true),
        LineType(name: "Center", description: "Long and short dash – center lines (ISO 128)", pattern: [7, -1.75, 1.75, -1.75], isBuiltIn: true),
        LineType(name: "Phantom", description: "Long dash and two short dashes", pattern: [7, -1.75, 1.75, -1.75, 1.75, -1.75], isBuiltIn: true)
    ]

    private static let builtInDXFNames: [String: String] = [
        "Continuous": "CONTINUOUS", "Dashed": "DASHED", "Dotted": "DOT", "Dash-Dot": "DASHDOT",
        "Dash-Dot-Dot": "DIVIDE", "Hidden": "HIDDEN", "Center": "CENTER", "Phantom": "PHANTOM"
    ]
}

// MARK: - Line Type Library

/// All available line types: built-in, custom (remembered) and loaded from the open drawing.
enum LineTypeLibrary {
    private static let customKey = "OhMyCAD.customLineTypes"
    /// Line types read from DXF that were not in the library (for this app session only).
    static var fromDrawing: [LineType] = []

    static var all: [LineType] {
        var result = LineType.builtIns
        for type in custom + fromDrawing where !result.contains(where: { $0.name.caseInsensitiveCompare(type.name) == .orderedSame }) {
            result.append(type)
        }
        return result
    }

    static var custom: [LineType] {
        get {
            let stored = UserDefaults.standard.array(forKey: customKey) as? [[String: String]] ?? []
            return stored.compactMap { entry in
                guard let name = entry["name"], let text = entry["pattern"],
                      let pattern = try? LineType.parsePattern(text) else { return nil }
                return LineType(name: name, description: entry["description"] ?? "", pattern: pattern)
            }
        }
        set {
            let stored = newValue.map { ["name": $0.name, "description": $0.description, "pattern": $0.definition] }
            UserDefaults.standard.set(stored, forKey: customKey)
        }
    }

    static func addCustom(_ type: LineType) {
        var list = custom.filter { $0.name.caseInsensitiveCompare(type.name) != .orderedSame }
        list.append(type)
        custom = list
    }

    /// Finds a type by name or DXF name (case-insensitive).
    static func named(_ name: String) -> LineType? {
        return all.first {
            $0.name.caseInsensitiveCompare(name) == .orderedSame || $0.dxfName.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    static func isNameTaken(_ name: String) -> Bool {
        return named(name) != nil
    }
}

// MARK: - Previews

enum LineStylePreview {
    /// A small image of the line pattern for menus.
    static func image(for type: LineType, width: CGFloat = 54, height: CGFloat = 10) -> NSImage {
        return NSImage(size: NSSize(width: width, height: height), flipped: false) { rect in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 1, y: rect.midY))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.midY))
            path.lineWidth = 1.2
            var dash = type.screenPattern
            if !dash.isEmpty { path.setLineDash(&dash, count: dash.count, phase: 0) }
            NSColor.labelColor.setStroke()
            path.stroke()
            return true
        }
    }
}

/// Line type preview in the editor (several lengths and weights).
final class LineTypePreviewView: NSView {
    var pattern: [CGFloat] = [] { didSet { needsDisplay = true } }
    var isValid = true { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        Theme.swatchBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        guard isValid else { return }
        let type = LineType(name: "", description: "", pattern: pattern)
        var dash = type.screenPattern
        for (index, width) in [CGFloat(1), 2, 3.5].enumerated() {
            let y = bounds.height - CGFloat(index + 1) * bounds.height / 4
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 10, y: y))
            path.line(to: NSPoint(x: bounds.width - 10, y: y))
            path.lineWidth = width
            if !dash.isEmpty { path.setLineDash(&dash, count: dash.count, phase: 0) }
            NSColor.white.setStroke()
            path.stroke()
        }
    }
}

// MARK: - Dialogs

/// The “Custom linetype” dialog: name, description, pattern + live preview and help.
final class LineTypeEditor: NSObject, NSTextFieldDelegate {
    private let nameField = NSTextField()
    private let descriptionField = NSTextField()
    private let patternField = NSTextField()
    private let preview = LineTypePreviewView(frame: NSRect(x: 0, y: 0, width: 360, height: 70))
    private let errorLabel = NSTextField(labelWithString: "")

    /// Shows the dialog; returns the new line type, or nil if cancelled.
    func run(suggestedName: String = "") -> LineType? {
        let alert = NSAlert()
        alert.messageText = "Custom Linetype"
        alert.informativeText = """
        Pattern in mm on paper: positive number = dash, negative = gap, 0 = dot.
        Separate the numbers with commas, use a dot for decimals (1.5).
        Example: 10, -3, 0, -3  →  ——— · ——— ·
        """
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 190))
        var y: CGFloat = 190
        func row(_ caption: String, _ field: NSTextField, placeholder: String) {
            y -= 26
            let label = NSTextField(labelWithString: caption)
            label.frame = NSRect(x: 0, y: y + 3, width: 80, height: 17)
            label.alignment = .right
            container.addSubview(label)
            field.frame = NSRect(x: 86, y: y, width: 274, height: 22)
            field.placeholderString = placeholder
            container.addSubview(field)
        }
        row("Name:", nameField, placeholder: "e.g. Border")
        row("Description:", descriptionField, placeholder: "optional")
        row("Pattern:", patternField, placeholder: "10, -3, 0, -3")
        nameField.stringValue = suggestedName
        patternField.delegate = self

        y -= 22
        errorLabel.frame = NSRect(x: 86, y: y, width: 274, height: 17)
        errorLabel.textColor = .systemRed
        errorLabel.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(errorLabel)

        preview.frame = NSRect(x: 0, y: 0, width: 360, height: y - 6)
        container.addSubview(preview)
        alert.accessoryView = container
        alert.window.initialFirstResponder = nameField
        updatePreview()

        while alert.runModal() == .alertFirstButtonReturn {
            let name = nameField.stringValue.trimmingCharacters(in: .whitespaces)
            do {
                guard !name.isEmpty else { throw LineType.ParseError(message: "Enter a name.") }
                guard !LineTypeLibrary.isNameTaken(name) || LineTypeLibrary.custom.contains(where: { $0.name == name }) else {
                    throw LineType.ParseError(message: "A built-in linetype already uses this name.")
                }
                let pattern = try LineType.parsePattern(patternField.stringValue)
                guard !pattern.isEmpty else { throw LineType.ParseError(message: "Enter a pattern.") }
                return LineType(name: name, description: descriptionField.stringValue, pattern: pattern)
            } catch {
                errorLabel.stringValue = error.localizedDescription
                NSSound.beep()
            }
        }
        return nil
    }

    func controlTextDidChange(_ obj: Notification) {
        updatePreview()
    }

    private func updatePreview() {
        do {
            let pattern = try LineType.parsePattern(patternField.stringValue)
            preview.pattern = pattern
            preview.isValid = true
            errorLabel.stringValue = pattern.isEmpty ? "" : String(format: "Period %.2f mm", Double(pattern.reduce(0) { $0 + abs($1) }))
            errorLabel.textColor = .secondaryLabelColor
        } catch {
            preview.isValid = false
            errorLabel.stringValue = error.localizedDescription
            errorLabel.textColor = .systemRed
        }
    }
}

/// The “Custom lineweight” dialog: a single number in mm (may be an expression).
enum LineWeightDialog {
    static func run() -> CGFloat? {
        let alert = NSAlert()
        alert.messageText = "Custom Lineweight"
        alert.informativeText = "Lineweight in millimeters (0 – 5 mm), e.g. 0.45 or 1/4."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "0.45"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        while alert.runModal() == .alertFirstButtonReturn {
            if let value = ExpressionEvaluator.evaluate(field.stringValue), value >= 0, value <= 5 {
                return LineWeights.addCustom(CGFloat(value))
            }
            alert.informativeText = "“\(field.stringValue)” is not a valid weight – enter a number between 0 and 5 mm."
            NSSound.beep()
        }
        return nil
    }
}
