//
//  DynamicInput.swift
//  OhMyCAD
//
//  Dynamic value entry at the cursor (like “Dynamic Input” in AutoCAD)
//  and a simple expression calculator: 15*7 or 15x7, 100/10, (20+5)*2, 2^3, 1,5 …
//

import Cocoa

// MARK: - Expression Evaluator

/// Evaluates a simple mathematical expression.
/// Supports + − * / (multiplication also as x and ×; division also as ÷ and :), ^ (power), parentheses, unary minus and a decimal comma.
enum ExpressionEvaluator {

    static func evaluate(_ input: String) -> Double? {
        var text = input.lowercased()
        for (from, to) in [(",", "."), ("×", "*"), ("x", "*"), ("÷", "/"), (":", "/"), ("−", "-")] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        var parser = Parser(characters: Array(text.filter { !$0.isWhitespace }))
        guard !parser.characters.isEmpty,
              let value = parser.parseExpression(),
              parser.index == parser.characters.count,
              value.isFinite else { return nil }
        return value
    }

    private struct Parser {
        let characters: [Character]
        var index = 0

        init(characters: [Character]) {
            self.characters = characters
        }

        private var current: Character? {
            return index < characters.count ? characters[index] : nil
        }

        // expression = term (('+' | '-') term)*
        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let c = current, c == "+" || c == "-" {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = c == "+" ? value + rhs : value - rhs
            }
            return value
        }

        // term = factor (('*' | '/') factor)*
        mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while let c = current, c == "*" || c == "/" {
                index += 1
                guard let rhs = parseUnary() else { return nil }
                if c == "*" {
                    value *= rhs
                } else {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                }
            }
            return value
        }

        // unary sign
        mutating func parseUnary() -> Double? {
            if let c = current, c == "-" || c == "+" {
                index += 1
                guard let value = parseUnary() else { return nil }
                return c == "-" ? -value : value
            }
            return parsePower()
        }

        // power = base ('^' unary)?
        mutating func parsePower() -> Double? {
            guard let base = parsePrimary() else { return nil }
            if current == "^" {
                index += 1
                guard let exponent = parseUnary() else { return nil }
                return pow(base, exponent)
            }
            return base
        }

        // base = number | '(' expression ')'
        mutating func parsePrimary() -> Double? {
            if current == "(" {
                index += 1
                guard let value = parseExpression(), current == ")" else { return nil }
                index += 1
                return value
            }
            let start = index
            while let c = current, c.isNumber || c == "." { index += 1 }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]))
        }
    }
}

// MARK: - Input Modes

/// Which fields the box at the cursor offers (depending on the tool and step).
enum DynamicInputMode: Equatable {
    case none
    case coordinates     // X, Y
    case lengthAngle     // length, angle
    case distanceAngle   // distance, angle (move, copy)
    case radius
    case includedAngle   // arc angle
    case widthHeight     // rectangle
    case angle           // rotate, mirror
    case factor          // scale
    case filletRadius
    case chamferDistances  // chamfer distances on the first and second object
    case offsetDistance  // offset distance
    case hatchSettings   // hatch angle and spacing
    case polygon(PolygonMethod)  // polygon size, rotation and number of sides

    var labels: [String] {
        switch self {
        case .none: return []
        case .coordinates: return ["X", "Y"]
        case .lengthAngle: return ["Length", "Angle °"]
        case .distanceAngle: return ["Distance", "Angle °"]
        case .radius: return ["Radius"]
        case .includedAngle: return ["Angle °"]
        case .widthHeight: return ["Width", "Height"]
        case .angle: return ["Angle °"]
        case .factor: return ["Factor"]
        case .filletRadius: return ["Fillet radius"]
        case .chamferDistances: return ["1st distance", "2nd distance"]
        case .offsetDistance: return ["Distance"]
        case .hatchSettings: return ["Angle °", "Scale"]
        case .polygon(let method):
            switch method {
            case .inscribed: return ["Radius", "Angle °", "Sides"]
            case .circumscribed: return ["Inner radius", "Angle °", "Sides"]
            case .edge: return ["Side", "Angle °", "Sides"]
            }
        }
    }
}

// MARK: - Dynamic Input View

/// A small box at the cursor with fields for numeric entry.
/// A field the user has typed into is “locked” – the preview and clicks then respect that value.
final class DynamicInputView: NSView, NSTextFieldDelegate {

    var onChange: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    /// A letter typed into a field as a command (e.g. C = close). Returns true if the tool used it.
    var onLetterCommand: ((String) -> Bool)?

    private(set) var labels: [String] = []
    /// Hint below the fields (e.g. “C = close the polyline”).
    private(set) var hint: String?
    private(set) var lockedValues: [CGFloat?] = []
    private var fields: [NSTextField] = []
    private var invalid: Set<Int> = []

    private let lockedColor = Theme.inputFieldLocked
    private let normalColor = Theme.inputField

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.inputBackground.cgColor
        layer?.cornerRadius = 5
        layer?.borderWidth = 0.5
        layer?.borderColor = Theme.popupBorder.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasLockedValue: Bool { return lockedValues.contains { $0 != nil } }
    var hasInvalidField: Bool { return !invalid.isEmpty }

    /// The text of the first field with an invalid value (for the message).
    var invalidFieldText: String? {
        guard let index = invalid.min(), index < fields.count else { return nil }
        return fields[index].stringValue.trimmingCharacters(in: .whitespaces)
    }

    /// Is any field currently being edited?
    var isEditing: Bool {
        guard let responder = window?.firstResponder as? NSTextView else { return false }
        return fields.contains { $0.currentEditor() === responder }
    }

    func lockedValue(_ index: Int) -> CGFloat? {
        return index < lockedValues.count ? lockedValues[index] : nil
    }

    /// Sets the fields (only when the labels changed – otherwise keeps the values being typed).
    func configure(labels newLabels: [String], hint newHint: String? = nil) {
        guard newLabels != labels || newHint != hint else { return }
        labels = newLabels
        hint = newHint
        subviews.forEach { $0.removeFromSuperview() }
        fields.removeAll()
        lockedValues = Array(repeating: nil, count: newLabels.count)
        invalid.removeAll()

        // fields stacked: label on the left, value on the right – as compact as possible
        let padding: CGFloat = 4
        let rowHeight: CGFloat = 17
        let rowGap: CGFloat = 2
        let fieldWidth: CGFloat = 66
        let captionFont = NSFont.systemFont(ofSize: 9.5, weight: .medium)
        let captionWidth = newLabels.map {
            ($0 as NSString).size(withAttributes: [.font: captionFont]).width
        }.max().map { ceil($0) + 4 } ?? 0
        // optional hint row below the fields
        let hintFont = NSFont.systemFont(ofSize: 9.5, weight: .regular)
        let hintHeight: CGFloat = newHint == nil ? 0 : 14
        let hintWidth = newHint.map { ceil(($0 as NSString).size(withAttributes: [.font: hintFont]).width) + 4 } ?? 0
        let fieldsHeight = CGFloat(newLabels.count) * rowHeight + CGFloat(max(newLabels.count - 1, 0)) * rowGap
        let height = padding * 2 + fieldsHeight + (newHint == nil ? 0 : hintHeight + rowGap)
        let width = max(padding * 2 + captionWidth + fieldWidth, padding * 2 + hintWidth)

        if let newHint = newHint {
            let label = NSTextField(labelWithString: newHint)
            label.font = hintFont
            label.textColor = Theme.inputHint
            label.frame = NSRect(x: padding, y: padding - 1, width: width - padding * 2, height: hintHeight)
            label.toolTip = "Press the key on the drawing area – or type it into a field"
            addSubview(label)
        }

        for (index, label) in newLabels.enumerated() {
            let y = height - padding - CGFloat(index + 1) * rowHeight - CGFloat(index) * rowGap

            let caption = NSTextField(labelWithString: label)
            caption.font = captionFont
            caption.textColor = Theme.textMuted
            caption.alignment = .right
            caption.frame = NSRect(x: padding, y: y + 1, width: captionWidth - 4, height: rowHeight - 3)
            addSubview(caption)

            let field = NSTextField(string: "")
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .regular)
            field.textColor = .white
            field.backgroundColor = normalColor
            field.drawsBackground = true
            field.isBordered = false
            field.isBezeled = false
            field.focusRingType = .none
            field.frame = NSRect(x: padding + captionWidth, y: y, width: fieldWidth, height: rowHeight)
            field.tag = index
            field.delegate = self
            field.cell?.isScrollable = true
            field.wantsLayer = true
            field.layer?.cornerRadius = 3
            addSubview(field)
            fields.append(field)
        }
        setFrameSize(NSSize(width: width, height: height))
    }

    /// Shows the current values under the cursor in fields the user is neither editing nor has locked.
    func setLiveValues(_ values: [CGFloat]) {
        let editing = window?.firstResponder as? NSTextView
        for (index, field) in fields.enumerated() where index < values.count {
            if lockedValues[index] != nil || invalid.contains(index) { continue }
            if let editing = editing, field.currentEditor() === editing { continue }
            field.stringValue = DynamicInputView.format(values[index])
        }
    }

    /// Clears locked values and text being typed.
    func reset() {
        for (index, field) in fields.enumerated() {
            lockedValues[index] = nil
            field.backgroundColor = normalColor
            field.textColor = .white
        }
        invalid.removeAll()
        if isEditing { window?.makeFirstResponder(superview) }
    }

    /// Starts typing into a field (the first character typed on the drawing area).
    func beginTyping(_ text: String, fieldIndex: Int = 0) {
        guard fieldIndex < fields.count else { return }
        let field = fields[fieldIndex]
        window?.makeFirstResponder(field)
        field.stringValue = text
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (text as NSString).length, length: 0)
        }
        valueChanged(in: field)
    }

    func focusFirstField() {
        guard let field = fields.first else { return }
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    static func format(_ value: CGFloat) -> String {
        guard value.isFinite else { return "" }
        var text = String(format: "%.3f", Double(value))
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    // MARK: Text field delegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        valueChanged(in: field)
    }

    private func valueChanged(in field: NSTextField) {
        let index = field.tag
        guard index < lockedValues.count else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        // a single letter (e.g. C = close) is a command for the tool, not a value
        if text.count == 1, text.first?.isLetter == true, onLetterCommand?(text.lowercased()) == true {
            field.stringValue = ""
            return
        }
        if text.isEmpty {
            lockedValues[index] = nil
            invalid.remove(index)
            field.backgroundColor = normalColor
            field.textColor = .white
        } else if let value = ExpressionEvaluator.evaluate(text) {
            lockedValues[index] = CGFloat(value)
            invalid.remove(index)
            field.backgroundColor = lockedColor
            field.textColor = .white
        } else {
            lockedValues[index] = nil
            invalid.insert(index)
            field.backgroundColor = normalColor
            field.textColor = .systemRed
        }
        onChange?()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            onCommit?()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onCancel?()
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            guard !fields.isEmpty else { return true }
            let step = commandSelector == #selector(NSResponder.insertTab(_:)) ? 1 : fields.count - 1
            let next = fields[(control.tag + step) % fields.count]
            window?.makeFirstResponder(next)
            next.currentEditor()?.selectAll(nil)
            return true
        default:
            return false
        }
    }
}

// MARK: - Close Prompt

/// A small panel at the cursor: “Close the polyline?” – answer Y / N (or with a button),
/// the checkbox decides whether to ask next time too.
final class ClosePromptView: NSView {
    var onAnswer: ((Bool) -> Void)?
    var onAskChanged: ((Bool) -> Void)?

    private let label = NSTextField(labelWithString: "")
    private var yesButton: NSButton!
    private var noButton: NSButton!
    private var askCheckbox: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.confirmBackground.cgColor
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = Theme.confirmBorder.cgColor

        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .white
        addSubview(label)

        yesButton = NSButton(title: "Yes (Y)", target: self, action: #selector(yesClicked))
        noButton = NSButton(title: "No (N)", target: self, action: #selector(noClicked))
        for button in [yesButton!, noButton!] {
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = NSFont.systemFont(ofSize: 11)
            button.refusesFirstResponder = true
            button.sizeToFit()
            addSubview(button)
        }

        askCheckbox = NSButton(checkboxWithTitle: "Ask when finishing", target: self, action: #selector(askChanged))
        askCheckbox.controlSize = .small
        askCheckbox.font = NSFont.systemFont(ofSize: 10)
        askCheckbox.refusesFirstResponder = true
        askCheckbox.contentTintColor = .white
        askCheckbox.sizeToFit()
        addSubview(askCheckbox)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Sets the question text and lays out the panel.
    func configure(question: String, askEveryTime: Bool) {
        label.stringValue = question
        label.sizeToFit()
        askCheckbox.state = askEveryTime ? .on : .off

        let padding: CGFloat = 8
        let buttonsWidth = yesButton.frame.width + 4 + noButton.frame.width
        let width = max(label.frame.width, buttonsWidth, askCheckbox.frame.width) + 2 * padding
        let height: CGFloat = 78

        askCheckbox.frame.origin = CGPoint(x: padding, y: 6)
        yesButton.frame.origin = CGPoint(x: padding, y: 26)
        noButton.frame.origin = CGPoint(x: padding + yesButton.frame.width + 4, y: 26)
        label.frame.origin = CGPoint(x: padding, y: height - label.frame.height - 6)
        setFrameSize(NSSize(width: width, height: height))
    }

    @objc private func yesClicked() { onAnswer?(true) }
    @objc private func noClicked() { onAnswer?(false) }
    @objc private func askChanged() { onAskChanged?(askCheckbox.state == .on) }
}
