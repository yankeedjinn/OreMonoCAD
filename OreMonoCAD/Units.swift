//
//  Units.swift
//  OreMonoCAD
//
//  How angles and lengths are written and typed (OreMonoCAD › Settings › Drawing):
//  angles in degrees or gons, directions as usual (counter-clockwise from the X axis) or as bearings
//  (clockwise from north, the Y axis), and in drawings in feet or inches lengths as 12'-6 1/2".
//  Inside the app angles stay in radians and degrees; only what is shown and typed is converted here.
//

import Cocoa

/// The unit angles are shown and typed in.
enum AngleUnit: String, CaseIterable {
    case degrees, gons

    var title: String {
        switch self {
        case .degrees: return "Degrees (360°)"
        case .gons: return "Gons (400 gon)"
        }
    }

    /// After a number: “45°”, “50 gon”.
    var symbol: String {
        switch self {
        case .degrees: return "°"
        case .gons: return " gon"
        }
    }

    /// In a field caption: “Angle °”, “Angle gon”.
    var caption: String {
        switch self {
        case .degrees: return "°"
        case .gons: return "gon"
        }
    }

    /// How many of these units one degree is.
    var perDegree: CGFloat {
        switch self {
        case .degrees: return 1
        case .gons: return 400 / 360
        }
    }
}

/// What an angle means: a direction (of a line, a point, an object's rotation) or a size (rotate by, arc angle, steps).
/// Bearings change only directions; the unit changes both.
enum AngleKind {
    case direction, amount
}

enum AngleStyle {
    /// Posted when the settings change – the drawing, the panels and the value box show the new form.
    static let didChange = Notification.Name("OreMonoCAD.angleStyleDidChange")

    static var unit: AngleUnit {
        get { return UserDefaults.standard.string(forKey: "OreMonoCAD.angleUnit").flatMap { AngleUnit(rawValue: $0) } ?? .degrees }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "OreMonoCAD.angleUnit")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Directions as bearings: clockwise from north (the Y axis of the drawing coordinates), as surveyors give them.
    static var bearings: Bool {
        get { return UserDefaults.standard.bool(forKey: "OreMonoCAD.angleBearings") }
        set {
            UserDefaults.standard.set(newValue, forKey: "OreMonoCAD.angleBearings")
            NotificationCenter.default.post(name: didChange, object: nil)
        }
    }

    /// Degrees as the app uses them (a direction counter-clockwise from the X axis) → the number shown.
    static func shown(_ degrees: CGFloat, _ kind: AngleKind) -> CGFloat {
        guard degrees.isFinite else { return degrees }
        var value = degrees
        if kind == .direction && bearings {
            value = 90 - value
            value = value.truncatingRemainder(dividingBy: 360)
            if value < 0 { value += 360 }
        }
        return value * unit.perDegree
    }

    /// The number typed → degrees as the app uses them.
    static func degrees(_ shown: CGFloat, _ kind: AngleKind) -> CGFloat {
        guard shown.isFinite else { return shown }
        let value = shown / unit.perDegree
        return kind == .direction && bearings ? 90 - value : value
    }

    /// An angle for prompts, messages and Info: “45.5°”, “50.5556 gon” (gons with 4 decimals, as surveyors write them).
    static func text(_ degrees: CGFloat, _ kind: AngleKind = .amount) -> String {
        let value = shown(degrees, kind)
        let decimals = unit == .gons ? 4 : 2
        var text = String(format: "%.\(decimals)f", Double(value))
        while text.contains(".") && (text.hasSuffix("0") || text.hasSuffix(".")) { text.removeLast() }
        if text == "-0" { text = "0" }
        return text + unit.symbol
    }

    /// A field caption: “Angle °”, “Angle gon”, for a direction with bearings “Bearing gon”.
    static func caption(_ name: String, _ kind: AngleKind) -> String {
        let word = kind == .direction && bearings && name == "Angle" ? "Bearing" : name
        return word + " " + unit.caption
    }

    /// The angle of a dimension with the given number of decimals (the angular dimension's text).
    static func dimensionText(_ degrees: CGFloat, precision: Int) -> String {
        let decimals = max(0, min(precision + (unit == .gons ? 2 : 0), 8))
        return String(format: "%.\(decimals)f", Double(shown(degrees, .amount))) + (unit == .gons ? "g" : "°")
    }
}

// MARK: - Feet and inches

enum LengthStyle {
    /// In drawings in feet or inches, lengths shown and typed as 12'-6 1/2" (Settings › Drawing).
    static var feetAndInches: Bool {
        get { return UserDefaults.standard.bool(forKey: "OreMonoCAD.feetAndInches") }
        set {
            UserDefaults.standard.set(newValue, forKey: "OreMonoCAD.feetAndInches")
            NotificationCenter.default.post(name: AngleStyle.didChange, object: nil)
        }
    }

    /// The units of the drawing being edited (set by the drawing area).
    static var drawingUnits: DrawingUnits = .mm

    /// Inches in one drawing unit – nil when the drawing is not in feet or inches.
    static var inchesPerUnit: CGFloat? {
        switch drawingUnits {
        case .ft: return 12
        case .inch: return 1
        default: return nil
        }
    }

    /// Feet and inches are in use now.
    static var isActive: Bool { return feetAndInches && inchesPerUnit != nil }

    /// A length as 12'-6 1/2" (inches rounded to 1/2^precision, e.g. precision 3 = 1/8"); nil = not in use.
    static func feetInches(_ length: CGFloat, precision: Int = 4) -> String? {
        guard isActive, let perUnit = inchesPerUnit, length.isFinite else { return nil }
        let denominator = 1 << max(0, min(precision, 6))
        var steps = Int((abs(length) * perUnit * CGFloat(denominator)).rounded())
        let sign = length < 0 && steps > 0 ? "-" : ""
        let feet = steps / (12 * denominator)
        steps -= feet * 12 * denominator
        let wholeInches = steps / denominator
        var numerator = steps % denominator
        var fractionDenominator = denominator
        while numerator > 0 && numerator % 2 == 0 { numerator /= 2; fractionDenominator /= 2 }
        let fraction = numerator > 0 ? "\(numerator)/\(fractionDenominator)" : ""
        let inches = wholeInches > 0 && !fraction.isEmpty ? "\(wholeInches) \(fraction)" : wholeInches > 0 ? "\(wholeInches)" : fraction.isEmpty ? "0" : fraction
        return feet > 0 ? "\(sign)\(feet)'-\(inches)\"" : "\(sign)\(inches)\""
    }

    /// 12'6", 12'-6 1/2", 12', 6 1/2", 1/2" → drawing units; nil = not a feet-and-inches value (or not in use).
    static func parse(_ input: String) -> Double? {
        guard let perUnit = inchesPerUnit else { return nil }
        var text = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "″", with: "\"")
            .replacingOccurrences(of: "′", with: "'").replacingOccurrences(of: "”", with: "\"").replacingOccurrences(of: "’", with: "'")
        guard text.contains("'") || text.contains("\"") else { return nil }
        var negative = false
        if text.hasPrefix("-") { negative = true; text.removeFirst() }
        var feet: Double = 0
        if let mark = text.firstIndex(of: "'") {
            guard let value = Double(text[..<mark].replacingOccurrences(of: ",", with: ".")) else { return nil }
            feet = value
            text = String(text[text.index(after: mark)...]).trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("-") { text.removeFirst() }
        }
        text = text.replacingOccurrences(of: "\"", with: "").trimmingCharacters(in: .whitespaces)
        var inches: Double = 0
        for part in text.split(separator: " ") where !part.isEmpty {
            if part.contains("/") {
                let pieces = part.split(separator: "/")
                guard pieces.count == 2, let a = Double(pieces[0]), let b = Double(pieces[1]), b != 0 else { return nil }
                inches += a / b
            } else {
                guard let value = Double(part.replacingOccurrences(of: ",", with: ".")) else { return nil }
                inches += value
            }
        }
        let total = (feet * 12 + inches) / Double(perUnit)
        return negative ? -total : total
    }
}
