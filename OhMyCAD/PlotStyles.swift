//
//  PlotStyles.swift
//  OhMyCAD
//
//  Plot styles: how each color is printed (output color, lineweight, screening, grayscale).
//
//  - Color-dependent plot style tables (.ctb) from AutoCAD can be imported. A .ctb file is a
//    short header followed by zlib-compressed text with one entry per ACI color (1–255).
//  - The built-in styles Color, Monochrome and Grayscale are plot style tables too.
//  - The table is stored in the plot settings, so the drawing plots the same on any Mac.
//  - Not supported (yet): named plot styles (.stb), linetype / end / join / fill overrides, dithering.
//

import Cocoa
import Compression

// MARK: - Plot style table

/// One plot style: what happens to objects of one ACI color.
nonisolated struct PlotStyle: Codable, Equatable {
    /// Output color as 0xRRGGBB; nil = use the object color.
    var color: Int? = nil
    /// Lineweight in mm; nil = use the object lineweight.
    var lineweight: CGFloat? = nil
    /// Screening (intensity) in % – 100 = full color, 0 = white; nil = 100.
    var screen: Int? = nil
    /// Convert the color to gray; nil = no.
    var grayscale: Bool? = nil

    static let object = PlotStyle()
}

/// A color-dependent plot style table (like AutoCAD .ctb).
nonisolated struct PlotStyleTable: Codable, Equatable {
    var name: String
    /// Styles for ACI 1–255 (element 0 = ACI 1). A single element = the same style for every color.
    var styles: [PlotStyle]

    /// True when every color plots the same way (no color lookup needed).
    var isUniform: Bool { return styles.count <= 1 }

    func style(forACI index: Int) -> PlotStyle {
        guard let first = styles.first else { return .object }
        if styles.count == 1 { return first }
        return styles[min(max(index, 1), styles.count) - 1]
    }

    static let color = PlotStyleTable(name: "Color", styles: [.object])
    static let monochrome = PlotStyleTable(name: "Monochrome", styles: [PlotStyle(color: 0)])
    static let grayscale = PlotStyleTable(name: "Grayscale", styles: [PlotStyle(grayscale: true)])
}

// MARK: - Reading .ctb files

nonisolated enum PlotStyleFileError: LocalizedError {
    case notPlotStyleFile
    case namedStyles
    case damaged

    var errorDescription: String? {
        switch self {
        case .notPlotStyleFile: return "The file is not an AutoCAD plot style table (.ctb)."
        case .namedStyles: return "Named plot style tables (.stb) are not supported yet. Use a color-dependent table (.ctb)."
        case .damaged: return "The plot style table is damaged and cannot be read."
        }
    }
}

extension PlotStyleTable {
    /// AutoCAD's standard lineweight table (mm), used when the file has none. 0 = object lineweight.
    nonisolated static let defaultLineweights: [CGFloat] = [
        0, 0.05, 0.09, 0.10, 0.13, 0.15, 0.18, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50,
        0.53, 0.60, 0.65, 0.70, 0.80, 0.90, 1.00, 1.06, 1.20, 1.40, 1.58, 2.00, 2.11
    ]

    /// Reads a .ctb file.
    nonisolated static func readCTB(_ data: Data, name: String) throws -> PlotStyleTable {
        return try parse(try decompress(data), name: name)
    }

    /// Header: "PIAFILEVERSION_2.0,CTBVER1,compress\r\npmzlibcodec", then three little-endian UInt32
    /// (checksum, text length, compressed length), then a zlib stream with the text.
    nonisolated static func decompress(_ data: Data) throws -> String {
        let bytes = [UInt8](data)
        guard bytes.count > 60, bytes.starts(with: Array("PIAFILEVERSION".utf8)) else { throw PlotStyleFileError.notPlotStyleFile }
        let marker = Array("pmzlibcodec".utf8)
        guard let start = (0...(min(bytes.count, 200) - marker.count)).first(where: { Array(bytes[$0..<($0 + marker.count)]) == marker })
        else { throw PlotStyleFileError.notPlotStyleFile }
        let header = String(decoding: bytes[0..<start], as: UTF8.self)
        if header.contains("STB") { throw PlotStyleFileError.namedStyles }

        let fieldsStart = start + marker.count
        let bodyStart = fieldsStart + 12
        guard bodyStart + 6 < bytes.count else { throw PlotStyleFileError.damaged }
        func uint32(_ at: Int) -> Int {
            return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
        }
        let textLength = uint32(fieldsStart + 4)
        let compressedLength = min(uint32(fieldsStart + 8), bytes.count - bodyStart)
        guard textLength > 0, textLength < 20_000_000, compressedLength > 6 else { throw PlotStyleFileError.damaged }

        // a zlib stream = 2 header bytes + raw deflate + 4 checksum bytes; Compression decodes raw deflate
        let deflate = Array(bytes[(bodyStart + 2)..<(bodyStart + compressedLength - 4)])
        var output = [UInt8](repeating: 0, count: textLength + 16)
        let written = output.withUnsafeMutableBufferPointer { out in
            deflate.withUnsafeBufferPointer { input in
                compression_decode_buffer(out.baseAddress!, out.count, input.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0 else { throw PlotStyleFileError.damaged }
        var text = Array(output[0..<written])
        while text.last == 0 { text.removeLast() }
        return String(bytes: text, encoding: .utf8) ?? String(bytes: text, encoding: .windowsCP1252) ?? ""
    }

    /// Parses the text: `name=value` lines and `name{ … }` blocks. The styles are in
    /// `plot_style{ 0{ … } 1{ … } … }`, lineweights in `custom_lineweight_table{ 0=0.0 … }`.
    nonisolated static func parse(_ text: String, name: String) throws -> PlotStyleTable {
        var lineweights: [Int: CGFloat] = [:]
        var entries: [Int: [String: String]] = [:]
        var path: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasSuffix("{") && !line.contains("=") {
                path.append(String(line.dropLast()).trimmingCharacters(in: .whitespaces))
                continue
            }
            if line == "}" {
                _ = path.popLast()
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") { value.removeFirst() }      // strings have only an opening quote
            if path == ["custom_lineweight_table"], let index = Int(key) {
                // numbers may carry an appendix like "0.0076 (+7.Z+)"
                let number = value.split(separator: " ").first.map(String.init) ?? value
                lineweights[index] = CGFloat(Double(number) ?? 0)
            } else if path.count == 2, path[0] == "plot_style", let index = Int(path[1]) {
                entries[index, default: [:]][key] = value
            }
        }
        if text.contains("aci_table_available=FALSE") { throw PlotStyleFileError.namedStyles }
        guard !entries.isEmpty else { throw PlotStyleFileError.damaged }

        func lineweight(_ index: Int) -> CGFloat {
            if let mm = lineweights[index] { return mm }
            return defaultLineweights.indices.contains(index) ? defaultLineweights[index] : 0
        }
        var styles: [PlotStyle] = []
        for index in 0..<255 {
            let entry = entries[index] ?? [:]
            var style = PlotStyle()
            if let text = entry["mode_color"] ?? entry["color"], let value = Int(text) {
                let bits = UInt32(truncatingIfNeeded: value)
                let type = bits >> 24
                // 0xC0 by layer, 0xC1 by block, 0xC3FFFFFF and -1 = object color
                if bits != 0xFFFF_FFFF && bits != 0xC3FF_FFFF && type != 0xC0 && type != 0xC1 {
                    style.color = Int(bits & 0xFF_FFFF)
                }
            }
            if let policy = entry["color_policy"].flatMap({ Int($0) }), policy & 2 != 0 { style.grayscale = true }
            if let screen = entry["screen"].flatMap({ Int($0) }), screen < 100 { style.screen = max(0, screen) }
            if let index = entry["lineweight"].flatMap({ Int($0) }) {
                let mm = lineweight(index)
                if mm > 0 { style.lineweight = mm }
            }
            styles.append(style)
        }
        if styles.allSatisfy({ $0 == styles[0] }) { styles = [styles[0]] }
        return PlotStyleTable(name: name, styles: styles)
    }
}

// MARK: - Applying a table

/// Finds the plot style of a color (the ACI number is looked up once per color).
final class PlotStyleResolver {
    let table: PlotStyleTable
    private var indexByColor: [Int: Int] = [:]

    init(_ table: PlotStyleTable) {
        self.table = table
    }

    func style(for color: NSColor) -> PlotStyle {
        if table.isUniform { return table.style(forACI: 7) }
        let c = color.usingColorSpace(.sRGB) ?? color
        let key = Int((c.redComponent * 255).rounded()) << 16 | Int((c.greenComponent * 255).rounded()) << 8
            | Int((c.blueComponent * 255).rounded())
        if let index = indexByColor[key] { return table.style(forACI: index) }
        let index = ACIColor.index(for: c)
        indexByColor[key] = index
        return table.style(forACI: index)
    }

    /// The color an object is printed with.
    static func plotColor(_ color: NSColor, style: PlotStyle) -> NSColor {
        let c = color.usingColorSpace(.sRGB) ?? color
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        if let rgb = style.color {
            r = CGFloat((rgb >> 16) & 0xFF) / 255
            g = CGFloat((rgb >> 8) & 0xFF) / 255
            b = CGFloat(rgb & 0xFF) / 255
        } else if !(c.brightnessComponent > 0.85 && c.saturationComponent < 0.2) {
            // (white – ACI 7 – and near-white colors stay 0 = black on white paper)
            r = c.redComponent
            g = c.greenComponent
            b = c.blueComponent
        }
        if style.grayscale == true {
            // darker than plain luminance, so light colors (yellow) do not fade to near white
            let gray = (0.299 * r + 0.587 * g + 0.114 * b) * 0.6
            r = gray
            g = gray
            b = gray
        }
        if let screen = style.screen, screen < 100 {
            let f = CGFloat(screen) / 100
            r = 1 - (1 - r) * f
            g = 1 - (1 - g) * f
            b = 1 - (1 - b) * f
        }
        return NSColor(srgbRed: r, green: g, blue: b, alpha: c.alphaComponent)
    }
}
