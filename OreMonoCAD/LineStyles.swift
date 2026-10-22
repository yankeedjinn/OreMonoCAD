//
//  LineStyles.swift
//  OreMonoCAD
//
//  Line types (built-in and custom), their text definition, previews
//  and dialogs for a custom line type and a custom lineweight.
//
//  The pattern definition uses the common .lin text format: numbers in mm on paper,
//  positive = dash, negative = gap, 0 = dot. E.g. “10, -3, 0, -3” = dash-dot.
//  Complex line types add texts and shapes in brackets, also as in .lin:
//  “12.7, -5.08, ["GAS", S=2.54, X=-2.54, Y=-1.27], -6.35”. The shapes (TRACK1, ZIG, BOX, CIRC1, BAT)
//  are drawn by the app itself – SHX files are not read.
//

import Cocoa

// MARK: - Line Type

struct LineType: Equatable {
    var name: String
    var description: String
    /// Pattern in mm on paper: + dash, − gap, 0 dot.
    var pattern: [CGFloat]
    var isBuiltIn = false
    /// Texts and shapes placed along the line (complex line type).
    var marks: [LineMark] = []

    /// Name in DXF (uppercase, no spaces).
    var dxfName: String {
        if let known = LineType.builtInDXFNames[name] { return known }
        return name.uppercased().replacingOccurrences(of: " ", with: "_")
    }

    var isContinuous: Bool { return pattern.isEmpty && marks.isEmpty }

    /// Only the marks are drawn, not the line itself (the pattern has no dash, e.g. Batting).
    var hidesBaseLine: Bool { return !marks.isEmpty && !pattern.contains(where: { $0 >= 0 }) }

    /// Width of the Batting shape in mm on paper (nil = the type has no Batting shape).
    var battingWidth: CGFloat? {
        return marks.first(where: { $0.content == .shape(.batting) }).map { abs($0.size) }
    }

    /// The pattern that can be written to DXF R12 (it knows no texts and shapes): dashes and gaps only,
    /// empty (solid) when the pattern has no dash or no gap.
    var plainPattern: [CGFloat] {
        return pattern.contains(where: { $0 >= 0 }) && pattern.contains(where: { $0 < 0 }) ? pattern : []
    }

    /// Total length of one pattern period (mm).
    var patternLength: CGFloat { return pattern.reduce(0) { $0 + abs($1) } }

    /// Text notation of the pattern, e.g. “10, -3, 0, -3” (marks in brackets where they lie).
    var definition: String {
        var parts: [String] = []
        for index in 0...pattern.count {
            parts += marks.filter { $0.index == index }.map { $0.definition }
            if index < pattern.count { parts.append(LineType.format(pattern[index])) }
        }
        return parts.joined(separator: ", ")
    }

    /// The dashes and the marks for drawing at the given size of 1 mm of the pattern (points).
    /// A pattern shorter than `minimumPeriod` points is drawn solid, without marks.
    func strokeParts(pointsPerMM: CGFloat, minimumPeriod: CGFloat) -> (dash: [CGFloat], marks: LineMarks?) {
        guard !isContinuous, pointsPerMM > 0, pointsPerMM.isFinite, patternLength * pointsPerMM >= minimumPeriod else {
            return ([], nil)
        }
        let dash = plainPattern.isEmpty ? [] : dashPattern(pointsPerMM: pointsPerMM)
        return (dash, marks.isEmpty ? nil : LineMarks(type: self, pointsPerMM: pointsPerMM))
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

    /// An angle in degrees for prompts and messages: at most 2 decimals, without trailing zeros.
    static func formatAngle(_ degrees: CGFloat) -> String {
        var text = String(format: "%.2f", Double(degrees))
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    // MARK: Text definition

    struct ParseError: LocalizedError {
        let message: String
        var errorDescription: String? { return message }
    }

    /// Parses a pattern notation. Numbers are separated by a comma, semicolon or space; they may also be expressions (2*3).
    /// Texts and shapes are in brackets (see LineMark.parse). A leading “A,” from a .lin file is skipped.
    static func parse(_ text: String) throws -> (pattern: [CGFloat], marks: [LineMark]) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return ([], []) }
        if trimmed.uppercased().hasPrefix("A,") { trimmed.removeFirst(2) }
        var values: [CGFloat] = []
        var marks: [LineMark] = []
        for token in tokens(trimmed) {
            if token.hasPrefix("[") {
                var mark = try LineMark.parse(token)
                mark.index = values.count
                marks.append(mark)
                continue
            }
            // ExpressionEvaluator must not treat a negative number as a decimal comma – we split on commas first
            guard let value = ExpressionEvaluator.evaluate(token) else {
                throw ParseError(message: "“\(token)” is not a number.")
            }
            values.append(CGFloat(value))
        }
        if marks.isEmpty {
            guard values.contains(where: { $0 > 0 }) || values.contains(0) else {
                throw ParseError(message: "The pattern needs at least one dash (positive number) or dot (0).")
            }
            guard values.contains(where: { $0 < 0 }) else {
                throw ParseError(message: "The pattern needs at least one gap (negative number).")
            }
        }
        guard values.count <= 12 else {
            throw ParseError(message: "Use at most 12 numbers.")
        }
        guard marks.count <= 12 else {
            throw ParseError(message: "Use at most 12 texts or shapes.")
        }
        guard values.reduce(0, { $0 + abs($1) }) >= 0.5 else {
            throw ParseError(message: "The pattern is too short (at least 0.5 mm in total).")
        }
        return (values, marks)
    }

    /// Splits a definition at commas, semicolons and spaces – except inside brackets and quotes.
    private static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        var quoted = false
        for character in text {
            if LineMark.quotes.contains(character) { quoted.toggle() }
            if !quoted {
                if character == "[" { depth += 1 }
                if character == "]" { depth = max(0, depth - 1) }
            }
            if depth == 0 && !quoted && (character == "," || character == ";" || character.isWhitespace) {
                if !current.isEmpty { result.append(current) }
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
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
        LineType(name: "Phantom", description: "Long dash and two short dashes", pattern: [7, -1.75, 1.75, -1.75, 1.75, -1.75], isBuiltIn: true),
        // complex line types (texts and shapes)
        complex("Batting", "Thermal insulation – set its thickness in Properties", "[BAT, S=2.5], -1.25"),
        complex("Zigzag", "Zigzag line", "[ZIG, S=2], -4"),
        complex("Gas Line", "Gas line ----GAS----", "12.7, -5.08, [\"GAS\", S=2.54, X=-2.54, Y=-1.27], -6.35"),
        complex("Hot Water", "Hot water supply ----HW----", "12.7, -5.08, [\"HW\", S=2.54, X=-2.54, Y=-1.27], -5.08"),
        complex("Fence (Circles)", "Fence line with circles", "12, -1, [CIRC1, S=2], -3"),
        complex("Fence (Boxes)", "Fence line with squares", "12, -1, [BOX, S=2], -3"),
        complex("Tracks", "Railroad tracks", "[TRACK1, S=3], 3")
    ]

    /// A built-in complex type (the definitions are fixed and valid).
    private static func complex(_ name: String, _ description: String, _ definition: String) -> LineType {
        let parsed = (try? parse(definition)) ?? (pattern: [], marks: [])
        return LineType(name: name, description: description, pattern: parsed.pattern, isBuiltIn: true, marks: parsed.marks)
    }

    private static let builtInDXFNames: [String: String] = [
        "Continuous": "CONTINUOUS", "Dashed": "DASHED", "Dotted": "DOT", "Dash-Dot": "DASHDOT",
        "Dash-Dot-Dot": "DIVIDE", "Hidden": "HIDDEN", "Center": "CENTER", "Phantom": "PHANTOM",
        "Batting": "BATTING", "Zigzag": "ZIGZAG", "Gas Line": "GAS_LINE", "Hot Water": "HOT_WATER_SUPPLY",
        "Fence (Circles)": "FENCELINE1", "Fence (Boxes)": "FENCELINE2", "Tracks": "TRACKS"
    ]
}

// MARK: - Line Type Library

/// All available line types: built-in, custom (remembered) and loaded from the open drawing.
enum LineTypeLibrary {
    private static let customKey = "OreMonoCAD.customLineTypes"
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
                      let parsed = try? LineType.parse(text) else { return nil }
                return LineType(name: name, description: entry["description"] ?? "", pattern: parsed.pattern, marks: parsed.marks)
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
            stroke(type, from: CGPoint(x: 1, y: rect.midY), to: CGPoint(x: rect.maxX - 1, y: rect.midY),
                   width: 1.2, color: .labelColor)
            return true
        }
    }

    /// Draws a straight sample of the line type (true size on screen) into the current graphics context.
    static func stroke(_ type: LineType, from start: CGPoint, to end: CGPoint, width: CGFloat, color: NSColor) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let parts = type.strokeParts(pointsPerMM: 72 / 25.4, minimumPeriod: 0)
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        context.saveGState()
        if parts.marks?.hidesLine != true {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            if !parts.dash.isEmpty { context.setLineDash(phase: 0, lengths: parts.dash) }
            context.addPath(path)
            context.strokePath()
        }
        context.restoreGState()
        parts.marks?.draw(along: path, in: context, mirrored: false, color: color.cgColor, lineWidth: min(width, 1.2))
    }
}

/// Line type preview in the editor (several lengths and weights).
final class LineTypePreviewView: NSView {
    var type = LineType(name: "", description: "", pattern: []) { didSet { needsDisplay = true } }
    var isValid = true { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        Theme.swatchBackground.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        guard isValid else { return }
        for (index, width) in [CGFloat(1), 2, 3.5].enumerated() {
            let y = bounds.height - CGFloat(index + 1) * bounds.height / 4
            LineStylePreview.stroke(type, from: CGPoint(x: 10, y: y), to: CGPoint(x: bounds.width - 10, y: y),
                                    width: width, color: .white)
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
        Texts and shapes go in brackets, as in .lin files:
        ["GAS", S=2.5, X=-2.5, Y=-1.25] or [BOX, S=2] (S = size, R = rotation °, X/Y = offset in mm).
        Shapes: TRACK1, ZIG, BOX, CIRC1, BAT.
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
                let parsed = try LineType.parse(patternField.stringValue)
                guard !parsed.pattern.isEmpty else { throw LineType.ParseError(message: "Enter a pattern.") }
                return LineType(name: name, description: descriptionField.stringValue, pattern: parsed.pattern, marks: parsed.marks)
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
            let parsed = try LineType.parse(patternField.stringValue)
            preview.type = LineType(name: "", description: "", pattern: parsed.pattern, marks: parsed.marks)
            preview.isValid = true
            let period = parsed.pattern.reduce(0) { $0 + abs($1) }
            errorLabel.stringValue = parsed.pattern.isEmpty ? "" : "Period \(LineType.format(period)) mm"
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
        alert.informativeText = "Width of the line in mm (from 0 to 5, e.g. 0.45 or 1/4):"
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
            alert.informativeText = "“\(field.stringValue)” is not a valid lineweight – enter a number from 0 to 5 mm."
            NSSound.beep()
        }
        return nil
    }
}

// MARK: - Complex line types: texts and shapes

/// Shapes for complex line types. The names are the usual shape names used in .lin files; the app draws them itself.
enum LineShape: String, CaseIterable {
    case track = "TRACK1", zigzag = "ZIG", box = "BOX", circle = "CIRC1", batting = "BAT"

    /// The shape at size 1: x runs along the line, y to its left; the origin is the mark's position.
    var path: CGPath {
        let path = CGMutablePath()
        switch self {
        case .track:
            // a tie across the line
            path.move(to: CGPoint(x: 0, y: -0.5))
            path.addLine(to: CGPoint(x: 0, y: 0.5))
        case .zigzag:
            // one zigzag two units long (it continues seamlessly with the next one)
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0.5, y: 0.5))
            path.addLine(to: CGPoint(x: 1.5, y: -0.5))
            path.addLine(to: CGPoint(x: 2, y: 0))
        case .box:
            path.addRect(CGRect(x: 0, y: -0.5, width: 1, height: 1))
        case .circle:
            path.addEllipse(in: CGRect(x: 0, y: -0.5, width: 1, height: 1))
        case .batting:
            // one loop of the insulation symbol, 1 wide and 0.5 long: the arc over the top, a slanted line
            // down, the arc under the bottom and a slanted line up to the start of the next loop
            let r: CGFloat = 0.25
            path.move(to: CGPoint(x: -r, y: r))
            path.addArc(center: CGPoint(x: 0, y: r), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
            path.addLine(to: CGPoint(x: 0, y: -r))
            path.addArc(center: CGPoint(x: r, y: -r), radius: r, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
            path.addLine(to: CGPoint(x: r, y: r))
        }
        return path
    }
}

/// A text or shape placed along a complex line type (like the bracketed elements in a .lin file).
struct LineMark: Equatable {
    enum Content: Equatable {
        case text(String)
        case shape(LineShape)
    }

    var content: Content
    /// The number of pattern elements before the mark (the mark sits where they end).
    var index = 0
    /// S: text height of capital letters / shape size, in mm on paper.
    var size: CGFloat = 1
    /// R (or A = absolute): rotation in degrees, relative to the line unless `absolute`.
    var rotation: CGFloat = 0
    var absolute = false
    /// U: the text turns so that it never reads upside down.
    var upright = false
    /// X, Y: offset in mm along the line and to its left.
    var offset = CGPoint.zero

    /// Quote characters accepted around a text (typing may turn " into curly quotes).
    static let quotes: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "\u{201E}"]

    /// Notation in brackets, e.g. ["GAS", S=2.54, X=-2.54, Y=-1.27].
    var definition: String {
        var parts: [String]
        switch content {
        case .text(let text): parts = ["\"\(text)\""]
        case .shape(let shape): parts = [shape.rawValue]
        }
        parts.append("S=\(LineType.format(size))")
        if rotation != 0 || absolute || upright {
            parts.append("\(upright ? "U" : absolute ? "A" : "R")=\(LineType.format(rotation))")
        }
        if offset.x != 0 { parts.append("X=\(LineType.format(offset.x))") }
        if offset.y != 0 { parts.append("Y=\(LineType.format(offset.y))") }
        return "[" + parts.joined(separator: ", ") + "]"
    }

    /// Parses “[…]”: a text in quotes or a shape name, optionally a font or shape file (ignored), then S=, R=, A=, U=, X=, Y=.
    static func parse(_ token: String) throws -> LineMark {
        var body = token.trimmingCharacters(in: .whitespaces)
        guard body.hasPrefix("["), body.hasSuffix("]") else {
            throw LineType.ParseError(message: "“\(token)” – a text or shape must be in brackets [ ].")
        }
        body = String(body.dropFirst().dropLast())
        // the text may contain commas – take it before splitting
        var mark: LineMark
        var rest: Substring
        if let first = body.first, quotes.contains(first) {
            guard let close = body.dropFirst().firstIndex(where: { quotes.contains($0) }) else {
                throw LineType.ParseError(message: "The text in “\(token)” has no closing quote.")
            }
            let text = String(body[body.index(after: body.startIndex)..<close])
            guard !text.isEmpty else { throw LineType.ParseError(message: "The text in “\(token)” is empty.") }
            mark = LineMark(content: .text(text))
            rest = body[body.index(after: close)...]
        } else {
            let name = body.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces)
            guard let shape = LineShape(rawValue: name.uppercased()) else {
                throw LineType.ParseError(message: "Unknown shape “\(name)” – use TRACK1, ZIG, BOX, CIRC1 or BAT, or a text in quotes.")
            }
            mark = LineMark(content: .shape(shape))
            rest = body.drop { $0 != "," }
        }
        for part in rest.split(separator: ",") {
            let item = part.trimmingCharacters(in: .whitespaces)
            guard let equals = item.firstIndex(of: "=") else { continue }   // font / shape file name
            let key = item[..<equals].trimmingCharacters(in: .whitespaces).uppercased()
            var valueText = item[item.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key == "R" || key == "A" || key == "U", valueText.lowercased().hasSuffix("d") { valueText.removeLast() }
            guard let value = ExpressionEvaluator.evaluate(valueText).map({ CGFloat($0) }) else {
                throw LineType.ParseError(message: "“\(valueText)” in “\(token)” is not a number.")
            }
            switch key {
            case "S": mark.size = value
            case "R": mark.rotation = value
            case "A": mark.rotation = value; mark.absolute = true
            case "U": mark.rotation = value; mark.upright = true
            case "X": mark.offset.x = value
            case "Y": mark.offset.y = value
            default: throw LineType.ParseError(message: "Unknown setting “\(key)=” in “\(token)” – use S, R, A, U, X or Y.")
            }
        }
        guard mark.size > 0 else { throw LineType.ParseError(message: "The size S in “\(token)” must be greater than 0.") }
        return mark
    }

    /// The mark at size 1 (shape outline or text glyphs, baseline at y = 0).
    var unitPath: CGPath {
        switch content {
        case .shape(let shape): return shape.path
        case .text(let text): return LineMark.textPath(text)
        }
    }

    private static var textPaths: [String: CGPath] = [:]

    /// The text as glyph outlines in the drawing font (osifont), capital letters 1 high.
    static func textPath(_ text: String) -> CGPath {
        if let cached = textPaths[text] { return cached }
        let font = FontLibrary.font(family: "osifont", face: "Regular", size: 100)
        let ctFont = font as CTFont
        let characters = Array(text.utf16)
        var glyphs = [CGGlyph](repeating: 0, count: characters.count)
        CTFontGetGlyphsForCharacters(ctFont, characters, &glyphs, characters.count)
        var advances = [CGSize](repeating: .zero, count: characters.count)
        CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, characters.count)
        let outlines = CGMutablePath()
        var x: CGFloat = 0
        for (glyph, advance) in zip(glyphs, advances) {
            if glyph != 0, let outline = CTFontCreatePathForGlyph(ctFont, glyph, nil) {
                outlines.addPath(outline, transform: CGAffineTransform(translationX: x, y: 0))
            }
            x += advance.width
        }
        let capHeight = font.capHeight > 1 ? font.capHeight : 70
        var scale = CGAffineTransform(scaleX: 1 / capHeight, y: 1 / capHeight)
        let result = outlines.copy(using: &scale) ?? outlines
        textPaths[text] = result
        return result
    }
}

/// Drawing the texts and shapes of a complex line type along a path (on screen, in print and in previews).
struct LineMarks {
    let type: LineType
    /// Points per 1 mm of the pattern (the same as for its dashes).
    let pointsPerMM: CGFloat

    var hidesLine: Bool { return type.hidesBaseLine }

    /// - Parameters:
    ///   - path: the path in the coordinates of the context (already transformed from the world)
    ///   - mirrored: the world → context transform flips y (the marks are then flipped back so texts read normally)
    func draw(along path: CGPath, in context: CGContext, mirrored: Bool, color: CGColor, lineWidth: CGFloat) {
        // where each pattern element starts within one period – measured exactly like the dash pattern
        var starts: [CGFloat] = []
        var period: CGFloat = 0
        for element in type.pattern {
            starts.append(period)
            period += element == 0 ? 0.7 : abs(element) * pointsPerMM
        }
        guard period > 0.5, period.isFinite else { return }
        let marks = type.marks.sorted { $0.index < $1.index }
        let offsets = marks.map { $0.index < starts.count ? starts[$0.index] : period }
        let shapes = marks.map { $0.unitPath }

        context.saveGState()
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: [])
        var budget = 20_000     // safeguard against a huge number of marks on a long line
        for polyline in LineMarks.flatten(path) where polyline.count > 1 {
            var lengths: [CGFloat] = [0]
            for i in 1..<polyline.count {
                lengths.append(lengths[i - 1] + hypot(polyline[i].x - polyline[i - 1].x, polyline[i].y - polyline[i - 1].y))
            }
            let total = lengths[lengths.count - 1]
            guard total > 0, total / period < CGFloat(budget) else { continue }
            var segment = 1
            var start: CGFloat = 0
            periods: while start <= total {
                for (i, mark) in marks.enumerated() {
                    let distance = start + offsets[i]
                    if distance > total { break periods }
                    while segment < lengths.count - 1 && lengths[segment] < distance { segment += 1 }
                    let a = polyline[segment - 1], b = polyline[segment]
                    let length = lengths[segment] - lengths[segment - 1]
                    let f = length > 0 ? (distance - lengths[segment - 1]) / length : 0
                    let point = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
                    let angle = atan2(b.y - a.y, b.x - a.x)
                    draw(mark, shape: shapes[i], at: point, angle: angle, mirrored: mirrored, in: context)
                    budget -= 1
                    if budget <= 0 { break periods }
                }
                start += period
            }
        }
        context.restoreGState()
    }

    private func draw(_ mark: LineMark, shape: CGPath, at point: CGPoint, angle: CGFloat, mirrored: Bool, in context: CGContext) {
        let size = mark.size * pointsPerMM
        var transform = CGAffineTransform(translationX: point.x, y: point.y).rotated(by: angle)
        if mirrored { transform = transform.scaledBy(x: 1, y: -1) }
        transform = transform.translatedBy(x: mark.offset.x * pointsPerMM, y: mark.offset.y * pointsPerMM)
        // the line's direction as seen in the drawing (the local frame is flipped back when mirrored)
        let lineAngle = mirrored ? -angle : angle
        let rotation = mark.rotation * .pi / 180 - (mark.absolute ? lineAngle : 0)
        if mark.upright, cos(lineAngle + rotation) < 0 {
            // upside down: turn the text half around its middle
            let box = shape.boundingBoxOfPath
            transform = transform.rotated(by: rotation)
                .translatedBy(x: box.midX * size, y: box.midY * size).rotated(by: .pi)
                .translatedBy(x: -box.midX * size, y: -box.midY * size)
        } else {
            transform = transform.rotated(by: rotation)
        }
        transform = transform.scaledBy(x: size, y: size)
        guard let placed = shape.copy(using: &transform) else { return }
        context.addPath(placed)
        if case .text = mark.content {
            context.fillPath()
        } else {
            context.strokePath()
        }
    }

    /// The path as polylines (one per subpath), curves divided into short straight pieces.
    static func flatten(_ path: CGPath) -> [[CGPoint]] {
        var result: [[CGPoint]] = []
        var current: [CGPoint] = []
        var subpathStart = CGPoint.zero
        func steps(_ points: [CGPoint]) -> Int {
            var length: CGFloat = 0
            for i in 1..<points.count { length += hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y) }
            return min(max(Int(length / 3), 4), 64)
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            let p = element.points
            switch element.type {
            case .moveToPoint:
                if current.count > 1 { result.append(current) }
                current = [p[0]]
                subpathStart = p[0]
            case .addLineToPoint:
                current.append(p[0])
            case .addQuadCurveToPoint:
                let a = current.last ?? p[0]
                let n = steps([a, p[0], p[1]])
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    current.append(CGPoint(x: u * u * a.x + 2 * u * t * p[0].x + t * t * p[1].x,
                                           y: u * u * a.y + 2 * u * t * p[0].y + t * t * p[1].y))
                }
            case .addCurveToPoint:
                let a = current.last ?? p[0]
                let n = steps([a, p[0], p[1], p[2]])
                for i in 1...n {
                    let t = CGFloat(i) / CGFloat(n), u = 1 - t
                    let b0 = u * u * u, b1 = 3 * u * u * t, b2 = 3 * u * t * t, b3 = t * t * t
                    current.append(CGPoint(x: b0 * a.x + b1 * p[0].x + b2 * p[1].x + b3 * p[2].x,
                                           y: b0 * a.y + b1 * p[0].y + b2 * p[1].y + b3 * p[2].y))
                }
            case .closeSubpath:
                current.append(subpathStart)
            @unknown default:
                break
            }
        }
        if current.count > 1 { result.append(current) }
        return result
    }
}
