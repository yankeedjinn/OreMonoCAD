//
//  DXF.swift
//  OhMyCAD
//
//  Reading and writing ASCII DXF (R12).
//  Reads: LINE, CIRCLE, ARC, ELLIPSE, LWPOLYLINE, POLYLINE, SPLINE, TEXT, MTEXT, blocks (BLOCK + INSERT) and the layer table.
//  Writes: LINE, CIRCLE, ARC, POLYLINE; splines as a dense polyline,
//  dimensions as exploded lines, arcs, arrows (SOLID) and TEXT.
//

import Cocoa

struct DXFImportResult {
    var entities: [CADEntity] = []
    var layers: [Layer] = []
    var skippedEntityTypes: [String: Int] = [:]
    /// Blocks from the BLOCKS section (INSERT references point to them).
    var blocks = BlockLibrary()
    /// Drawing units from the header ($INSUNITS), if present.
    var units: DrawingUnits?
}

// MARK: - Reader

class DXFReader {
    private struct Record {
        let type: String
        let section: String?
        var pairs: [(code: Int, value: String)] = []

        func string(_ code: Int) -> String? {
            return pairs.first(where: { $0.code == code })?.value
        }

        func double(_ code: Int) -> CGFloat? {
            guard let s = string(code), let d = Double(s) else { return nil }
            return CGFloat(d)
        }

        func int(_ code: Int) -> Int? {
            guard let s = string(code) else { return nil }
            return Int(s)
        }

        /// All points with coordinates in codes xCode/yCode (in order of appearance).
        func points(xCode: Int, yCode: Int) -> [CGPoint] {
            var result: [CGPoint] = []
            var pendingX: CGFloat?
            for pair in pairs {
                if pair.code == xCode {
                    pendingX = Double(pair.value).map { CGFloat($0) }
                } else if pair.code == yCode, let x = pendingX, let y = Double(pair.value) {
                    result.append(CGPoint(x: x, y: CGFloat(y)))
                    pendingX = nil
                }
            }
            return result
        }
    }

    /// Older DXF files (before AutoCAD 2007) are written in the code page named in $DWGCODEPAGE (ANSI_1250 for Czech).
    static func decodeWithCodePage(_ data: Data) -> String? {
        guard let latin = String(data: data, encoding: .isoLatin1) else { return nil }
        var encoding = String.Encoding.isoLatin1
        if let range = latin.range(of: "$DWGCODEPAGE") {
            // the value follows on the line after group code 3
            let lines = latin[range.upperBound...].prefix(200).split(whereSeparator: \.isNewline)
            let value = lines.count >= 2 ? lines[1].trimmingCharacters(in: .whitespaces).uppercased() : ""
            let windows: [String: String.Encoding] = [
                "ANSI_1250": .windowsCP1250, "ANSI_1251": .windowsCP1251, "ANSI_1252": .windowsCP1252,
                "ANSI_1253": .windowsCP1253, "ANSI_1254": .windowsCP1254
            ]
            if let code = windows[value] { encoding = code }
        }
        return String(data: data, encoding: encoding) ?? latin
    }

    func read(from url: URL) throws -> DXFImportResult {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? DXFReader.decodeWithCodePage(data) else {
            throw EditError(message: "The file could not be read as text.")
        }
        if text.hasPrefix("AutoCAD Binary DXF") {
            throw EditError(message: "Binary DXF is not supported. Please save the file as ASCII DXF.")
        }

        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        // Split into records (each starts with group code 0)
        var records: [Record] = []
        var current: Record?
        var section: String?
        var index = 0
        // MTEXT from newer versions ends with “101 Embedded Object” with its own codes 10/11/40…,
        // which would overwrite the real values (e.g. text rotation) – those are skipped
        var skippingEmbedded = false

        while index + 1 < lines.count {
            let codeText = lines[index].trimmingCharacters(in: .whitespaces)
            let value = lines[index + 1].trimmingCharacters(in: .whitespaces)
            index += 2
            guard let code = Int(codeText) else { continue }

            if code == 0 {
                if let finished = current {
                    if finished.type == "SECTION" { section = finished.string(2) }
                    records.append(finished)
                }
                if value == "ENDSEC" { section = nil }
                current = Record(type: value, section: section)
                skippingEmbedded = false
                if value == "EOF" { break }
            } else if code == 101 {
                skippingEmbedded = true
            } else if !skippingEmbedded {
                // names of layers, blocks and line types may contain \U+XXXX (written so by R12 files, also ours)
                let isName = code == 2 || code == 8 || code == 6
                current?.pairs.append((code, isName && value.contains("+") ? DXFReader.decodeUnicode(value) : value))
            }
        }
        if let finished = current { records.append(finished) }

        var result = DXFImportResult()

        // header: drawing units
        if let header = records.first(where: { $0.type == "SECTION" && $0.string(2) == "HEADER" }),
           let index = header.pairs.firstIndex(where: { $0.code == 9 && $0.value == "$INSUNITS" }),
           index + 1 < header.pairs.count, let code = Int(header.pairs[index + 1].value) {
            switch code {
            case 1: result.units = .inch
            case 2: result.units = .ft
            case 4: result.units = .mm
            case 5: result.units = .cm
            case 6: result.units = .m
            default: break
            }
        }
        // dimension styles and block names by handle (dimension terminators reference a block by handle)
        var dimStyles: [String: DimStyleInfo] = [:]
        var blockNames: [String: String] = [:]
        // text styles → font family (e.g. the style “OSIFONT” with the file osifont.ttf)
        var textFonts: [String: String] = [:]
        var textWidths: [String: CGFloat] = [:]
        for record in records where record.section == "TABLES" && record.type == "STYLE" {
            guard let name = record.string(2) else { continue }
            let file = record.string(3) ?? ""
            if let family = FontLibrary.family(matching: file) ?? FontLibrary.family(matching: name) {
                textFonts[name.uppercased()] = family
            }
            if let width = record.double(41), width > 0.05, width < 20 { textWidths[name.uppercased()] = width }
        }
        /// Font and width factor from the text style (for TEXT its own width, code 41, takes precedence).
        func applyFont(_ text: TextEntity, _ record: Record, ownWidth: CGFloat? = nil) {
            let style = (record.string(7) ?? "STANDARD").uppercased()
            if let family = textFonts[style] { text.fontFamily = family }
            if let width = ownWidth ?? textWidths[style], width > 0.05, width < 20 { text.widthFactor = width }
        }
        for record in records where record.section == "TABLES" {
            if record.type == "BLOCK_RECORD", let handle = record.string(5), let name = record.string(2) {
                blockNames[handle.uppercased()] = name
            } else if record.type == "DIMSTYLE", let name = record.string(2) {
                var style = DimStyleInfo()
                style.apply(code: 140, record.string(140)); style.apply(code: 40, record.string(40))
                style.apply(code: 41, record.string(41)); style.apply(code: 271, record.string(271))
                style.apply(code: 173, record.string(173)); style.apply(code: 342, record.string(342))
                style.apply(code: 343, record.string(343)); style.apply(code: 5, record.string(5))
                dimStyles[name.uppercased()] = style
            }
        }

        var openPolyline: (record: Record, vertices: [CGPoint], bulges: [CGFloat], inBlocks: Bool)?
        // BLOCKS section: the block in progress and its objects
        var currentBlock: BlockDefinition?
        var blockEntities: [CADEntity] = []

        /// Block definition by name (also created ahead – INSERT may come before BLOCK).
        func definition(named name: String) -> BlockDefinition {
            if let existing = result.blocks.named(name) { return existing }
            let created = BlockDefinition(name: name, basePoint: .zero, entities: [])
            result.blocks.add(created)
            return created
        }

        func emit(_ entity: CADEntity, inBlocks: Bool, record: Record? = nil) {
            // these objects lie in object coordinates (OCS); with the extrusion pointing down (230 = −1,
            // e.g. after mirroring in 3D) OCS X runs against world X – the object is mirrored into place
            if let record = record, ["CIRCLE", "ARC", "LWPOLYLINE", "POLYLINE", "TEXT", "INSERT", "HATCH"].contains(record.type),
               (record.double(230) ?? 1) < 0 {
                entity.applyTransform(CGAffineTransform(scaleX: -1, y: 1))
            }
            // the object's lineweight (370: hundredths of a mm; negative = ByLayer / ByBlock / default)
            if let weight = record?.int(370), weight >= 0 { entity.lineWeight = CGFloat(weight) / 100 }
            // the object's linetype scale (48)
            if let scale = record?.double(48), scale > 0, scale != 1 { entity.lineTypeScale = scale }
            if inBlocks {
                if currentBlock != nil { blockEntities.append(entity) }
            } else {
                result.entities.append(entity)
            }
        }

        for record in records {
            let section = record.section ?? ""
            let inBlocks = section == "BLOCKS"

            // old POLYLINE: vertices follow as VERTEX until SEQEND
            if var polyline = openPolyline {
                if record.type == "VERTEX" {
                    polyline.vertices.append(CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0))
                    polyline.bulges.append(record.double(42) ?? 0)
                    openPolyline = polyline
                    continue
                }
                let closed = (polyline.record.int(70) ?? 0) & 1 != 0
                if polyline.vertices.count >= 2 {
                    emit(Polyline(vertices: polyline.vertices, closed: closed, bulges: polyline.bulges,
                                  layer: polyline.record.string(8) ?? "0",
                                  color: entityColor(polyline.record)), inBlocks: polyline.inBlocks, record: polyline.record)
                }
                openPolyline = nil
                if record.type == "SEQEND" { continue }
            }

            if inBlocks {
                switch record.type {
                case "BLOCK":
                    let name = record.string(2) ?? ""
                    let lower = name.lowercased()
                    blockEntities = []
                    // *D… = anonymous dimension blocks (dimensions are read on their own, not as a block)
                    if name.isEmpty || lower.hasPrefix("*model_space") || lower.hasPrefix("*paper_space") || lower.hasPrefix("*d") {
                        currentBlock = nil
                    } else {
                        let block = definition(named: name)
                        block.basePoint = CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0)
                        currentBlock = block
                    }
                    continue
                case "ENDBLK":
                    if let block = currentBlock {
                        // a block must not contain itself
                        block.entities = blockEntities.filter { !(($0 as? BlockReference)?.definition.contains(block) ?? false) }
                    }
                    currentBlock = nil
                    blockEntities = []
                    continue
                default:
                    break
                }
            }

            // objects in blocks are read the same way as in ENTITIES
            let kind = inBlocks ? "ENTITIES" : section
            switch (kind, record.type) {
            case ("TABLES", "LTYPE"):
                // a line type from the drawing that is not in the library yet → available for the app session
                guard let name = record.string(2), LineTypeLibrary.named(name) == nil else { continue }
                let elements = DXFReader.lineTypeElements(of: record)
                let description = record.string(3) ?? ""
                LineTypeLibrary.fromDrawing.append(LineType(name: name.capitalized, description: description,
                                                            pattern: elements.pattern, marks: elements.marks))

            case ("TABLES", "LAYER"):
                guard let name = record.string(2) else { continue }
                let colorIndex = record.int(62) ?? 7
                let flags = record.int(70) ?? 0
                result.layers.append(Layer(name: name,
                                           color: DXFReader.trueColor(record) ?? ACIColor.color(for: colorIndex),
                                           isVisible: colorIndex >= 0,
                                           isLocked: flags & 4 != 0,
                                           isPrintable: (record.int(290) ?? 1) != 0,
                                           lineType: LineTypeLibrary.named(record.string(6) ?? "") ?? .continuous,
                                           lineWeight: record.int(370).flatMap { $0 >= 0 ? CGFloat($0) / 100 : nil }
                                               ?? LineWeights.defaultWeight))

            case ("ENTITIES", "LINE"):
                emit(Line(start: CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0),
                          end: CGPoint(x: record.double(11) ?? 0, y: record.double(21) ?? 0),
                          layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "POINT"):
                emit(SurveyPoint(position: CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0),
                                 z: record.double(30).map { Double($0) },
                                 layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "XLINE"), ("ENTITIES", "RAY"):
                // construction line (XLINE) / ray (RAY): point and direction
                let direction = CGPoint(x: record.double(11) ?? 1, y: record.double(21) ?? 0)
                guard direction.length > 0 else { continue }
                emit(ConstructionLine(point: CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0),
                                      angle: atan2(direction.y, direction.x), isRay: record.type == "RAY",
                                      layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "CIRCLE"):
                guard let radius = record.double(40), radius > 0 else { continue }
                emit(Circle(center: CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0),
                            radius: radius, layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "ARC"):
                guard let radius = record.double(40), radius > 0 else { continue }
                let start = (record.double(50) ?? 0) * .pi / 180
                let end = (record.double(51) ?? 360) * .pi / 180
                emit(Arc(center: CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0),
                         radius: radius, startAngle: start, endAngle: end,
                         layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "LWPOLYLINE"):
                // vertices and bulges (42 belongs to the most recently read vertex)
                let vertices = record.points(xCode: 10, yCode: 20)
                guard vertices.count >= 2 else { continue }
                var bulges: [CGFloat] = []
                for pair in record.pairs {
                    if pair.code == 10 {
                        bulges.append(0)
                    } else if pair.code == 42, !bulges.isEmpty, let value = Double(pair.value) {
                        bulges[bulges.count - 1] = CGFloat(value)
                    }
                }
                emit(Polyline(vertices: vertices, closed: (record.int(70) ?? 0) & 1 != 0,
                              bulges: bulges.count == vertices.count ? bulges : [],
                              layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "POLYLINE"):
                openPolyline = (record, [], [], inBlocks)

            case ("ENTITIES", "ELLIPSE"):
                // center, end of the major axis (relative), axis ratio, start and end parameters
                let center = CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0)
                let axis = CGPoint(x: record.double(11) ?? 0, y: record.double(21) ?? 0)
                guard axis.length > 0, let ratio = record.double(40), ratio > 0 else { continue }
                var start = record.double(41) ?? 0
                var end = record.double(42) ?? 2 * .pi
                // center and axis are in world coordinates; an extrusion pointing down (z = -1)
                // only makes the parameters run clockwise
                if (record.double(230) ?? 1) < 0 {
                    let s = start
                    start = -end
                    end = -s
                }
                emit(Ellipse(center: center, majorAxis: axis, ratio: ratio, startParam: start, endParam: end,
                             layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "SPLINE"):
                // preferably the points the curve passes through (fit points), otherwise the control points
                var points = record.points(xCode: 11, yCode: 21)
                if points.count < 2 { points = record.points(xCode: 10, yCode: 20) }
                guard points.count >= 2 else { continue }
                emit(Spline(controlPoints: points, closed: (record.int(70) ?? 0) & 1 != 0,
                            layer: record.string(8) ?? "0", color: entityColor(record)), inBlocks: inBlocks, record: record)

            case ("ENTITIES", "TEXT"):
                guard let rawText = record.string(1), case let value = DXFReader.decodeText(rawText), !value.isEmpty,
                      let height = record.double(40), height > 0 else { continue }
                // alignment: 72 = horizontal (0 left, 1 center, 2 right, 3 aligned, 4 middle, 5 fit),
                // 73 = vertical (0 baseline, 1 bottom, 2 middle, 3 top); then the second point (11/21) applies
                let horizontal = record.int(72) ?? 0
                let vertical = record.int(73) ?? 0
                let rotation = (record.double(50) ?? 0) * .pi / 180
                var position = CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0)
                let usesSecond = (horizontal != 0 && horizontal != 3 && horizontal != 5) || vertical != 0
                if usesSecond, let x = record.double(11), let y = record.double(21) {
                    position = CGPoint(x: x, y: y)
                }
                // baseline offset according to the vertical alignment (perpendicular to the text direction)
                var lift: CGFloat = 0
                switch horizontal == 4 ? 2 : vertical {
                case 1: lift = height * 0.3      // bottom = below the descenders
                case 2: lift = -height * 0.5     // middle of the capitals
                case 3: lift = -height           // top
                default: break
                }
                if lift != 0 {
                    position = CGPoint(x: position.x - sin(rotation) * lift, y: position.y + cos(rotation) * lift)
                }
                let text = TextEntity(position: position, text: value, height: height,
                                      layer: record.string(8) ?? "0", color: entityColor(record))
                text.rotation = rotation
                text.justify = horizontal == 1 || horizontal == 4 ? .center : horizontal == 2 ? .right : .left
                applyFont(text, record, ownWidth: record.double(41))
                emit(text, inBlocks: inBlocks, record: record)

            case ("ENTITIES", "MTEXT"):
                // the text is in codes 3 (continuation) and 1 (end)
                let raw = record.pairs.filter { $0.code == 3 || $0.code == 1 }.map { $0.value }.joined()
                let value = DXFReader.decodeMText(raw)
                guard !value.isEmpty, let height = record.double(40), height > 0 else { continue }
                // attachment 71: 1–3 top, 4–6 middle, 7–9 bottom (columns left / center / right)
                let attachment = min(max(record.int(71) ?? 1, 1), 9)
                let column = (attachment - 1) % 3
                let row = (attachment - 1) / 3
                var rotation: CGFloat = 0
                if let angle = record.double(50) {
                    rotation = angle * .pi / 180
                } else if let dx = record.double(11), let dy = record.double(21), dx != 0 || dy != 0 {
                    rotation = atan2(dy, dx)
                }
                let spacing = record.double(44).map { min(max($0, 0.25), 4) } ?? 1
                // baseline of the first line: lines every 5/3 of the height (AutoCAD) × line spacing
                let lines = CGFloat(value.components(separatedBy: "\n").count)
                let total = height + (lines - 1) * height * 5 / 3 * spacing
                let drop: CGFloat
                switch row {
                case 1: drop = height - total / 2           // middle
                case 2: drop = height - total               // bottom
                default: drop = height                      // top
                }
                let base = CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0)
                let position = CGPoint(x: base.x + sin(rotation) * drop, y: base.y - cos(rotation) * drop)
                let text = TextEntity(position: position, text: value, height: height,
                                      layer: record.string(8) ?? "0", color: entityColor(record))
                text.rotation = rotation
                text.lineSpacing = spacing
                text.justify = column == 1 ? .center : column == 2 ? .right : .left
                if let width = record.double(41), width > 0 { text.boxWidth = width }
                applyFont(text, record)
                emit(text, inBlocks: inBlocks, record: record)

            case ("ENTITIES", "INSERT"):
                // inserted block: X / Y scale (negative = mirroring), rotation
                guard let name = record.string(2), !name.isEmpty else { continue }
                let reference = BlockReference(definition: definition(named: name),
                                               position: CGPoint(x: record.double(10) ?? 0, y: record.double(20) ?? 0),
                                               layer: record.string(8) ?? "0", color: entityColor(record))
                let sx = record.double(41) ?? 1
                let sy = record.double(42) ?? sx
                reference.scale = abs(sx) > 0 ? abs(sx) : 1
                reference.mirrored = sx * sy < 0
                var rotation = (record.double(50) ?? 0) * .pi / 180
                if sx < 0 { rotation += .pi }      // mirroring across Y = rotation by 180° and mirroring across X
                reference.rotation = Geometry.normalizeAngle(rotation)
                emit(reference, inBlocks: inBlocks, record: record)

            case ("ENTITIES", "HATCH"):
                guard let hatch = DXFReader.hatch(from: record, color: entityColor(record)) else { continue }
                emit(hatch, inBlocks: inBlocks, record: record)

            case ("ENTITIES", "DIMENSION"):
                var style = dimStyles[(record.string(3) ?? "STANDARD").uppercased()] ?? DimStyleInfo()
                style.applyOverrides(record)
                guard let dimension = DXFReader.dimension(from: record, style: style, blockNames: blockNames,
                                                          blocks: result.blocks, color: entityColor(record)) else {
                    if !inBlocks { result.skippedEntityTypes["DIMENSION (ordinate)", default: 0] += 1 }
                    continue
                }
                emit(dimension, inBlocks: inBlocks, record: record)

            case ("ENTITIES", "MULTILEADER"), ("ENTITIES", "MLEADER"):
                for leader in DXFReader.multileaders(from: record, color: entityColor(record)) {
                    emit(leader, inBlocks: inBlocks, record: record)
                }

            case ("ENTITIES", "LEADER"):
                // old leader: only a line with an arrow, the text is a separate MTEXT
                let vertices = record.points(xCode: 10, yCode: 20)
                guard vertices.count >= 2 else { continue }
                var style = dimStyles[(record.string(3) ?? "STANDARD").uppercased()] ?? DimStyleInfo()
                style.applyOverrides(record)
                let leader = DimensionEntity(kind: .leader, points: vertices, textHeight: style.textHeight,
                                             layer: record.string(8) ?? "0", color: entityColor(record))
                leader.arrowSize = style.textHeight
                leader.arrowStyle = (record.int(71) ?? 1) == 0 ? .none : .arrow
                emit(leader, inBlocks: inBlocks, record: record)

            case ("ENTITIES", "SEQEND"), ("ENTITIES", "VERTEX"), ("ENTITIES", "ATTRIB"), ("ENTITIES", "ATTDEF"):
                break

            case ("ENTITIES", let type):
                if !inBlocks { result.skippedEntityTypes[type, default: 0] += 1 }

            default:
                break
            }
        }
        // the last open POLYLINE at the end of the file
        if let polyline = openPolyline, polyline.vertices.count >= 2 {
            emit(Polyline(vertices: polyline.vertices, closed: (polyline.record.int(70) ?? 0) & 1 != 0, bulges: polyline.bulges,
                          layer: polyline.record.string(8) ?? "0", color: entityColor(polyline.record)), inBlocks: polyline.inBlocks, record: polyline.record)
        }

        return result
    }

    /// AutoCAD special characters: %%c = Ø, %%d = °, %%p = ±, %%u/%%o = underline/overline (skipped).
    nonisolated static func decodeText(_ text: String) -> String {
        var result = decodeUnicode(decodeCaret(text))
        for (code, value) in [("%%c", "Ø"), ("%%C", "Ø"), ("%%d", "°"), ("%%D", "°"), ("%%p", "±"), ("%%P", "±"),
                              ("%%u", ""), ("%%U", ""), ("%%o", ""), ("%%O", ""), ("%%%", "%")] {
            result = result.replacingOccurrences(of: code, with: value)
        }
        return result
    }

    /// \U+XXXX (a Unicode character – older DXF files write even Czech that way), \M+nXXXX (a multi-byte character) and %%nnn (character code).
    nonisolated static func decodeUnicode(_ text: String) -> String {
        guard text.contains("\\U+") || text.contains("\\u+") || text.contains("%%") || text.contains("\\M+") else { return text }
        var result = ""
        let chars = Array(text)
        var i = 0
        func hex(_ start: Int, _ count: Int) -> UInt32? {
            guard start >= 0, start + count <= chars.count else { return nil }
            return UInt32(String(chars[start..<(start + count)]), radix: 16)
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 2 < chars.count, chars[i + 1] == "U" || chars[i + 1] == "u", chars[i + 2] == "+",
               let code = hex(i + 3, 4), let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
                i += 7
                continue
            }
            if c == "\\", i + 2 < chars.count, chars[i + 1] == "M" || chars[i + 1] == "m", chars[i + 2] == "+",
               let code = hex(i + 4, 4) {
                // \M+1XXXX: a double-byte character – used only if it is a valid character
                if let scalar = Unicode.Scalar(code) { result.append(Character(scalar)) }
                i += 8
                continue
            }
            if c == "%", i + 4 < chars.count, chars[i + 1] == "%",
               chars[i + 2].isASCII, chars[i + 2].isNumber, chars[i + 3].isASCII, chars[i + 3].isNumber,
               chars[i + 4].isASCII, chars[i + 4].isNumber,
               let code = Int(String(chars[(i + 2)...(i + 4)])), code > 31, code < 256, let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
                i += 5
                continue
            }
            result.append(c)
            i += 1
        }
        return result
    }

    /// Control characters written with a caret (DXF): ^I = tab, ^J = new line, ^M is skipped, “^ ” = caret.
    nonisolated static func decodeCaret(_ text: String) -> String {
        guard text.contains("^") else { return text }
        var result = ""
        var chars = Array(text)[...]
        while let c = chars.popFirst() {
            guard c == "^", let next = chars.first else { result.append(c); continue }
            switch next {
            case "I": result.append("\t"); chars.removeFirst()
            case "J": result.append("\n"); chars.removeFirst()
            case "M": chars.removeFirst()
            case " ": result.append("^"); chars.removeFirst()
            default:
                // other control characters (^@ … ^_) are skipped
                if let ascii = next.asciiValue, ascii >= 64, ascii <= 95 {
                    chars.removeFirst()
                } else {
                    result.append(c)
                }
            }
        }
        return result
    }

    /// MTEXT without formatting codes: \P = new line, {…} and \f…; \H…; etc. are skipped.
    nonisolated static func decodeMText(_ text: String) -> String {
        var result = ""
        // \U+XXXX first – otherwise the “code up to the semicolon” branch below would swallow it
        var chars = Array(decodeUnicode(text))
        var i = 0
        chars.append(" ")
        while i < chars.count - 1 {
            let c = chars[i]
            if c == "\\" {
                let next = chars[i + 1]
                switch next {
                case "P", "n":
                    result.append("\n"); i += 2
                case "~":
                    result.append(" "); i += 2
                case "\\", "{", "}":
                    result.append(next); i += 2
                case "L", "l", "O", "o", "K", "k":
                    i += 2
                case "S":
                    // fraction / superscript and subscript: \S1/2;  \S1^2;  \S1#2;  → 1/2
                    var j = i + 2
                    var stacked = ""
                    while j < chars.count - 1 && chars[j] != ";" {
                        stacked.append(chars[j] == "^" || chars[j] == "#" ? "/" : chars[j])
                        j += 1
                    }
                    result.append(stacked)
                    i = j + 1
                default:
                    // \fArial|b0;  \H2.5;  \C1;  … up to the semicolon
                    var j = i + 1
                    while j < chars.count - 1 && chars[j] != ";" { j += 1 }
                    i = j + 1
                }
            } else if c == "{" || c == "}" {
                i += 1
            } else {
                result.append(c)
                i += 1
            }
        }
        return decodeText(result).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Code 420: true color 0xRRGGBB.
    private static func trueColor(_ record: Record) -> NSColor? {
        guard let rgb = record.int(420), rgb >= 0 else { return nil }
        return NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                       blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// Entity color: code 420 (true color 0xRRGGBB), 62 (1–255), otherwise ByLayer (nil).
    private func entityColor(_ record: Record) -> NSColor? {
        if let color = DXFReader.trueColor(record) { return color }
        if let index = record.int(62), index > 0, index < 256 {
            return ACIColor.color(for: index)
        }
        return nil
    }
}

// MARK: - Reader: hatches, dimensions, leaders

extension DXFReader {
    /// Dimension style values (DIMSTYLE + overrides in the XDATA “DSTYLE”).
    private struct DimStyleInfo {
        var textSize: CGFloat = 2.5      // DIMTXT
        var scale: CGFloat = 1           // DIMSCALE
        var arrowSize: CGFloat = 2.5     // DIMASZ
        var decimals = 2                 // DIMDEC
        var separateArrows = false       // DIMSAH
        var arrowHandle: String?         // DIMBLK (handle of the block record)
        var arrow1Handle: String?        // DIMBLK1
        var arrowName: String?           // DIMBLK by name (older DXF)

        var effectiveScale: CGFloat { return scale > 0 ? scale : 1 }
        var textHeight: CGFloat { return textSize * effectiveScale }

        mutating func apply(code: Int, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return }
            let number = Double(value).map { CGFloat($0) }
            switch code {
            case 140: if let n = number, n > 0 { textSize = n }
            case 40: if let n = number { scale = n }
            case 41: if let n = number, n > 0 { arrowSize = n }
            case 271: if let n = number { decimals = max(0, min(8, Int(n))) }
            case 173: separateArrows = (number ?? 0) != 0
            case 342: arrowHandle = value.uppercased()
            case 343: arrow1Handle = value.uppercased()
            case 5: arrowName = value
            default: break
            }
        }

        /// Style override directly on the object: 1000 DSTYLE, 1002 {, then pairs of 1070 code + value.
        mutating func applyOverrides(_ record: Record) {
            guard let start = record.pairs.firstIndex(where: { $0.code == 1000 && $0.value.uppercased() == "DSTYLE" }) else { return }
            var i = start + 1
            while i + 1 < record.pairs.count {
                let pair = record.pairs[i]
                if pair.code == 1002 && pair.value == "}" { break }
                if pair.code == 1070, let code = Int(pair.value) {
                    apply(code: code, record.pairs[i + 1].value)
                    i += 2
                } else {
                    i += 1
                }
            }
        }
    }

    // MARK: Hatch

    /// Sequential reading of pairs (hatch data is ordered, codes repeat).
    private struct Cursor {
        let pairs: [(code: Int, value: String)]
        var i: Int

        mutating func take(_ code: Int) -> CGFloat? {
            guard i < pairs.count, pairs[i].code == code, let d = Double(pairs[i].value) else { return nil }
            i += 1
            return CGFloat(d)
        }

        mutating func takeInt(_ code: Int) -> Int? {
            return take(code).map { Int($0) }
        }

        mutating func point(_ x: Int, _ y: Int) -> CGPoint? {
            guard let px = take(x), let py = take(y) else { return nil }
            return CGPoint(x: px, y: py)
        }

        var nextCode: Int? { return i < pairs.count ? pairs[i].code : nil }
    }

    /// Arc points from the start angle with the given sweep (negative = clockwise).
    private static func arcPoints(_ c: CGPoint, _ r: CGFloat, _ start: CGFloat, _ sweep: CGFloat) -> [CGPoint] {
        let steps = max(2, Int(abs(sweep) / (.pi / 36)))
        return (0...steps).map { k in
            let a = start + sweep * CGFloat(k) / CGFloat(steps)
            return CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
    }

    /// Sweep of a hatch edge arc (angles in degrees; for clockwise edges they are written with a negative sign).
    private static func edgeSweep(start: CGFloat, end: CGFloat, ccw: Bool) -> (start: CGFloat, sweep: CGFloat) {
        let s = start * .pi / 180, e = end * .pi / 180
        if abs(end - start) >= 360 - 1e-6 { return (ccw ? s : -s, ccw ? 2 * .pi : -2 * .pi) }
        if ccw { return (s, Geometry.ccwDelta(from: s, to: e)) }
        return (-s, -Geometry.ccwDelta(from: -e, to: -s))
    }

    /// A polyline with bulges → points.
    static func flattenBulges(_ vertices: [CGPoint], _ bulges: [CGFloat], closed: Bool) -> [CGPoint] {
        guard vertices.count >= 2 else { return vertices }
        var out: [CGPoint] = []
        let n = vertices.count
        for k in 0..<(closed ? n : n - 1) {
            let p = vertices[k], q = vertices[(k + 1) % n]
            out.append(p)
            let b = k < bulges.count ? bulges[k] : 0
            guard abs(b) > 1e-9, p != q else { continue }
            let chord = CGPoint(x: q.x - p.x, y: q.y - p.y)
            let f = (1 - b * b) / (4 * b)
            let c = CGPoint(x: (p.x + q.x) / 2 - chord.y * f, y: (p.y + q.y) / 2 + chord.x * f)
            let r = hypot(p.x - c.x, p.y - c.y)
            let points = arcPoints(c, r, atan2(p.y - c.y, p.x - c.x), 4 * atan(b))
            out.append(contentsOf: points.dropFirst().dropLast())
        }
        if !closed, let last = vertices.last { out.append(last) }
        return out
    }

    /// A B-spline point (de Boor, possibly rational with weights).
    private static func splinePoints(degree: Int, knots: [CGFloat], controls: [CGPoint], weights: [CGFloat]) -> [CGPoint] {
        let n = controls.count
        guard degree >= 1, n > degree, knots.count >= n + degree + 1 else { return controls }
        let w = weights.count == n ? weights : Array(repeating: 1, count: n)
        let t0 = knots[degree], t1 = knots[n]
        guard t1 > t0 else { return controls }
        let samples = max(16, n * 8)
        var result: [CGPoint] = []
        for s in 0...samples {
            let t = t0 + (t1 - t0) * CGFloat(s) / CGFloat(samples)
            var k = degree
            while k < n - 1 && t >= knots[k + 1] { k += 1 }
            // homogeneous coordinates
            var d: [(x: CGFloat, y: CGFloat, w: CGFloat)] = (0...degree).map { j in
                let c = controls[j + k - degree], wj = w[j + k - degree]
                return (c.x * wj, c.y * wj, wj)
            }
            if degree >= 1 {
                for r in 1...degree {
                    for j in stride(from: degree, through: r, by: -1) {
                        let i = j + k - degree
                        let denom = knots[i + degree - r + 1] - knots[i]
                        let alpha = denom == 0 ? 0 : (t - knots[i]) / denom
                        d[j] = ((1 - alpha) * d[j - 1].x + alpha * d[j].x,
                                (1 - alpha) * d[j - 1].y + alpha * d[j].y,
                                (1 - alpha) * d[j - 1].w + alpha * d[j].w)
                    }
                }
            }
            let p = d[degree]
            result.append(p.w != 0 ? CGPoint(x: p.x / p.w, y: p.y / p.w) : CGPoint(x: p.x, y: p.y))
        }
        return result
    }

    private static func signedArea(_ loop: [CGPoint]) -> CGFloat {
        guard loop.count >= 3 else { return 0 }
        var sum: CGFloat = 0
        for k in 0..<loop.count {
            let a = loop[k], b = loop[(k + 1) % loop.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    /// LTYPE: dashes (49) and the texts of complex line types. Each element can carry an embedded text or shape
    /// (74: 2 = text, 4 = shape, 1 = absolute rotation; 46 size, 50 rotation, 44/45 offset, 9 text) that sits
    /// after it. Shapes from SHX files cannot be read – only the built-in complex types (matched by name) have them.
    private static func lineTypeElements(of record: Record) -> (pattern: [CGFloat], marks: [LineMark]) {
        var pattern: [CGFloat] = []
        var marks: [LineMark] = []
        var flags = 0
        var mark = LineMark(content: .text(""))
        func finishMark() {
            if flags & 2 != 0, case .text(let text) = mark.content, !text.isEmpty, mark.size > 0 {
                mark.index = pattern.count
                marks.append(mark)
            }
            flags = 0
        }
        for pair in record.pairs {
            let number = Double(pair.value.trimmingCharacters(in: .whitespaces)).map { CGFloat($0) }
            switch pair.code {
            case 49:
                finishMark()
                if let value = number { pattern.append(value) }
            case 74:
                flags = Int(pair.value.trimmingCharacters(in: .whitespaces)) ?? 0
                mark = LineMark(content: .text(""))
                mark.absolute = flags & 1 != 0
            case 46: if let value = number { mark.size = value }
            case 50: if let value = number { mark.rotation = value }
            case 44: if let value = number { mark.offset.x = value }
            case 45: if let value = number { mark.offset.y = value }
            case 9: mark.content = .text(pair.value)
            default: break
            }
        }
        finishMark()
        return (pattern, marks)
    }

    /// HATCH: boundary (polylines and edges – lines, arcs, ellipses, splines) and pattern.
    /// The pattern lines in DXF are already converted to angle and scale, so the hatch is created with angle 0 and scale 1.
    private static func hatch(from record: Record, color: NSColor?) -> HatchEntity? {
        guard let countIndex = record.pairs.firstIndex(where: { $0.code == 91 }) else { return nil }
        var cursor = Cursor(pairs: record.pairs, i: countIndex)
        let pathCount = cursor.takeInt(91) ?? 0
        var loops: [[CGPoint]] = []

        for _ in 0..<max(0, pathCount) {
            // skip unknown codes before the path starts
            while let code = cursor.nextCode, code != 92 { cursor.i += 1; if code == 75 { break } }
            guard let flags = cursor.takeInt(92) else { break }
            var loop: [CGPoint] = []
            if flags & 2 != 0 {
                let hasBulge = (cursor.takeInt(72) ?? 0) != 0
                _ = cursor.takeInt(73)
                let count = cursor.takeInt(93) ?? 0
                var vertices: [CGPoint] = [], bulges: [CGFloat] = []
                for _ in 0..<max(0, count) {
                    guard let p = cursor.point(10, 20) else { break }
                    vertices.append(p)
                    bulges.append(hasBulge ? (cursor.take(42) ?? 0) : 0)
                }
                loop = flattenBulges(vertices, bulges, closed: true)
            } else {
                let edgeCount = cursor.takeInt(93) ?? 0
                for _ in 0..<max(0, edgeCount) {
                    guard let type = cursor.takeInt(72) else { break }
                    var points: [CGPoint] = []
                    switch type {
                    case 1:
                        if let a = cursor.point(10, 20), let b = cursor.point(11, 21) { points = [a, b] }
                    case 2:
                        guard let c = cursor.point(10, 20), let r = cursor.take(40) else { break }
                        let s = cursor.take(50) ?? 0, e = cursor.take(51) ?? 360
                        let ccw = (cursor.takeInt(73) ?? 1) != 0
                        let span = edgeSweep(start: s, end: e, ccw: ccw)
                        points = arcPoints(c, r, span.start, span.sweep)
                    case 3:
                        guard let c = cursor.point(10, 20), let major = cursor.point(11, 21) else { break }
                        let ratio = cursor.take(40) ?? 1
                        let s = cursor.take(50) ?? 0, e = cursor.take(51) ?? 360
                        let ccw = (cursor.takeInt(73) ?? 1) != 0
                        let span = edgeSweep(start: s, end: e, ccw: ccw)
                        let minor = CGPoint(x: -major.y * ratio, y: major.x * ratio)
                        points = arcPoints(.zero, 1, span.start, span.sweep).map {
                            CGPoint(x: c.x + major.x * $0.x + minor.x * $0.y, y: c.y + major.y * $0.x + minor.y * $0.y)
                        }
                    case 4:
                        let degree = cursor.takeInt(94) ?? 3
                        let rational = (cursor.takeInt(73) ?? 0) != 0
                        _ = cursor.takeInt(74)
                        let knotCount = cursor.takeInt(95) ?? 0
                        let controlCount = cursor.takeInt(96) ?? 0
                        var knots: [CGFloat] = [], controls: [CGPoint] = [], weights: [CGFloat] = []
                        for _ in 0..<max(0, knotCount) { if let k = cursor.take(40) { knots.append(k) } }
                        for _ in 0..<max(0, controlCount) {
                            guard let p = cursor.point(10, 20) else { break }
                            controls.append(p)
                            if rational, let w = cursor.take(42) { weights.append(w) }
                        }
                        // R2010+: fit points (+ tangents); must not be confused with the number of source objects (97) at the end of the path
                        if cursor.nextCode == 97, cursor.i + 1 < cursor.pairs.count,
                           [11, 97].contains(cursor.pairs[cursor.i + 1].code) || (cursor.pairs[cursor.i].value.trimmingCharacters(in: .whitespaces) == "0") {
                            let fitCount = cursor.takeInt(97) ?? 0
                            for _ in 0..<max(0, fitCount) { _ = cursor.point(11, 21) }
                            if fitCount > 0 { _ = cursor.point(12, 22); _ = cursor.point(13, 23) }
                        }
                        points = splinePoints(degree: degree, knots: knots, controls: controls, weights: weights)
                    default:
                        break
                    }
                    // chaining edges (an edge's first point = the end of the previous one → skip it)
                    if let last = loop.last, let first = points.first, hypot(last.x - first.x, last.y - first.y) < 1e-9 {
                        points.removeFirst()
                    }
                    loop.append(contentsOf: points)
                }
            }
            // references to source objects
            if let sources = cursor.takeInt(97) {
                for _ in 0..<max(0, sources) where cursor.nextCode == 330 { cursor.i += 1 }
            }
            if let first = loop.first, let last = loop.last, loop.count > 1, hypot(first.x - last.x, first.y - last.y) < 1e-9 {
                loop.removeLast()
            }
            if loop.count >= 3 { loops.append(loop) }
        }
        guard !loops.isEmpty else { return nil }
        // outer boundary first (largest area)
        loops.sort { abs(signedArea($0)) > abs(signedArea($1)) }

        let name = record.string(2) ?? "SOLID"
        let isSolid = (record.int(70) ?? 0) == 1 || name.uppercased() == "SOLID" || (record.int(450) ?? 0) == 1
        let pattern: HatchPattern
        var angle: CGFloat = 0
        var scale: CGFloat = 1
        if isSolid {
            pattern = .solid
        } else {
            // pattern lines
            var families: [HatchLineFamily] = []
            if let lineIndex = record.pairs.indices.first(where: { $0 >= cursor.i && record.pairs[$0].code == 78 }) {
                var c = Cursor(pairs: record.pairs, i: lineIndex)
                let lineCount = c.takeInt(78) ?? 0
                for _ in 0..<max(0, lineCount) {
                    guard let degrees = c.take(53) else { break }
                    let base = c.point(43, 44) ?? .zero
                    let offset = c.point(45, 46) ?? .zero
                    let dashCount = c.takeInt(79) ?? 0
                    var dashes: [CGFloat] = []
                    for _ in 0..<max(0, dashCount) { if let d = c.take(49) { dashes.append(d) } }
                    let a = degrees * .pi / 180
                    let along = offset.x * cos(a) + offset.y * sin(a)
                    let across = -offset.x * sin(a) + offset.y * cos(a)
                    guard abs(across) > 1e-9 else { continue }
                    families.append(HatchLineFamily(angle: degrees, origin: base, shift: along, spacing: across, dashes: dashes))
                }
            }
            if !families.isEmpty {
                pattern = HatchPattern(name: name, description: "From DXF", families: families)
            } else if let known = HatchPatternLibrary.named(name) {
                pattern = known
                angle = (record.double(52) ?? 0) * .pi / 180
                scale = record.double(41) ?? 1
            } else {
                pattern = .solid
            }
        }
        return HatchEntity(loops: loops, pattern: pattern, angle: angle, scale: scale,
                           layer: record.string(8) ?? "0", color: color)
    }

    // MARK: Dimension

    /// Terminator by the arrow block name (_Oblique, _ArchTick, _Dot, _Open, _None …; empty = filled arrow).
    private static func arrowStyle(named name: String?) -> DimArrowStyle {
        let n = (name ?? "").uppercased()
        if n.isEmpty { return .arrow }
        if n.contains("ARCHTICK") { return .architectural }
        if n.contains("OBLIQUE") { return .oblique }
        if n.contains("NONE") { return .none }
        if n.contains("DOT") || n.contains("ORIGIN") || n.contains("SMALL") { return .dot }
        if n.contains("OPEN") { return .open }
        return .arrow
    }

    private static func dimension(from record: Record, style: DimStyleInfo, blockNames: [String: String],
                                  blocks: BlockLibrary, color: NSColor?) -> DimensionEntity? {
        func point(_ code: Int) -> CGPoint? {
            guard let x = record.double(code), let y = record.double(code + 10) else { return nil }
            return CGPoint(x: x, y: y)
        }
        let type = (record.int(70) ?? 0) & 7
        let height = style.textHeight
        let layer = record.string(8) ?? "0"
        let dimension: DimensionEntity

        switch type {
        case 0, 1:
            guard let p1 = point(13), let p2 = point(14), let place = point(10) else { return nil }
            dimension = DimensionEntity(kind: type == 0 ? .linear : .aligned, points: [p1, p2, place],
                                        textHeight: height, layer: layer, color: color)
            if type == 0 { dimension.fixedAngle = (record.double(50) ?? 0) * .pi / 180 }
        case 2:
            // two lines: 13–14 and 15–10, the arc passes through point 16
            guard let a1 = point(13), let a2 = point(14), let b1 = point(15), let b2 = point(10) else { return nil }
            let arc = point(16) ?? b2
            let da = CGPoint(x: a2.x - a1.x, y: a2.y - a1.y), db = CGPoint(x: b2.x - b1.x, y: b2.y - b1.y)
            let cross = da.x * db.y - da.y * db.x
            guard abs(cross) > 1e-12 else { return nil }
            let t = ((b1.x - a1.x) * db.y - (b1.y - a1.y) * db.x) / cross
            let v = CGPoint(x: a1.x + da.x * t, y: a1.y + da.y * t)
            // on each line the end that lies in the direction of the arc
            func ray(_ p: CGPoint, _ q: CGPoint) -> CGPoint {
                let toArc = CGPoint(x: arc.x - v.x, y: arc.y - v.y)
                let dp = (p.x - v.x) * toArc.x + (p.y - v.y) * toArc.y
                let dq = (q.x - v.x) * toArc.x + (q.y - v.y) * toArc.y
                let best = dp >= dq ? p : q
                return Geometry.distance(best, v) > 1e-9 ? best : (best == p ? q : p)
            }
            dimension = DimensionEntity(kind: .angular, points: [v, ray(a1, a2), ray(b1, b2), arc],
                                        textHeight: height, layer: layer, color: color)
        case 5:
            guard let v = point(15), let p1 = point(13), let p2 = point(14), let arc = point(10) else { return nil }
            dimension = DimensionEntity(kind: .angular, points: [v, p1, p2, arc], textHeight: height, layer: layer, color: color)
        case 3:
            guard let p = point(15), let q = point(10) else { return nil }
            let center = Geometry.midpoint(p, q)
            dimension = DimensionEntity(kind: .diameter, points: [center, p], radius: Geometry.distance(p, q) / 2,
                                        textHeight: height, layer: layer, color: color)
        case 4:
            guard let center = point(10), let p = point(15) else { return nil }
            let radius = Geometry.distance(center, p)
            var outer = p
            // text outside the circle in the same direction → the dimension line extends to the text
            if let text = point(11), Geometry.distance(center, text) > radius {
                let u = CGPoint(x: (p.x - center.x) / max(radius, 1e-12), y: (p.y - center.y) / max(radius, 1e-12))
                let along = (text.x - center.x) * u.x + (text.y - center.y) * u.y
                if along > radius { outer = CGPoint(x: center.x + u.x * along, y: center.y + u.y * along) }
            }
            dimension = DimensionEntity(kind: .radius, points: [center, outer], radius: radius,
                                        textHeight: height, layer: layer, color: color)
        default:
            return nil      // ordinate dimensions not yet
        }

        // text: <> = measured value, \X separates the text below the line
        let raw = record.string(1) ?? ""
        let parts = raw.components(separatedBy: "\\X")
        let above = decodeMText(parts[0])
        dimension.text = above == "<>" ? "" : above
        if parts.count > 1 { dimension.belowText = decodeMText(parts.dropFirst().joined(separator: "\n")) }

        // terminator and its size (a custom arrow block is scaled by its own size)
        let handle = style.separateArrows ? (style.arrow1Handle ?? style.arrowHandle) : style.arrowHandle
        let blockName = handle.flatMap { blockNames[$0] } ?? style.arrowName
        let arrow = arrowStyle(named: blockName)
        var extent: CGFloat = 1
        if arrow.isTick, let name = blockName, let block = blocks.named(name), !block.entities.isEmpty {
            let box = block.entities.reduce(CGRect.null) { $0.union($1.boundingBox()) }
            let size = max(box.width, box.height)
            if size.isFinite && size > 0 { extent = size }
        }
        dimension.arrowStyle = arrow
        dimension.arrowSize = style.arrowSize * style.effectiveScale * extent
        dimension.precision = style.decimals
        return dimension
    }

    // MARK: Multileader

    /// MULTILEADER: text (first 304 in CONTEXT_DATA), text height (41), each leader line (LEADER_LINE{ … }) + attachment point.
    private static func multileaders(from record: Record, color: NSColor?) -> [DimensionEntity] {
        let pairs = record.pairs
        guard let contextStart = pairs.firstIndex(where: { $0.code == 300 && $0.value.uppercased().hasPrefix("CONTEXT_DATA") }) else { return [] }
        var text = ""
        var textHeight: CGFloat?
        var arrowSize: CGFloat?
        var leaders: [[CGPoint]] = []
        var landing: CGPoint?
        var inLeader = false, inLine = false
        var line: [CGPoint] = []
        var pendingX: CGFloat?
        var dogleg = CGPoint.zero, doglegLength: CGFloat = 0, pendingDX: CGFloat?
        var i = contextStart + 1
        while i < pairs.count {
            let (code, value) = pairs[i]
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            switch code {
            case 302 where trimmed.uppercased().hasPrefix("LEADER{"):
                inLeader = true; landing = nil; dogleg = .zero; doglegLength = 0
            case 304 where trimmed.uppercased().hasPrefix("LEADER_LINE{"):
                inLine = true; line = []
            case 304 where !inLeader && text.isEmpty:
                text = decodeMText(value)
            case 41 where !inLeader && textHeight == nil:
                textHeight = Double(trimmed).map { CGFloat($0) }
            case 140 where !inLeader && arrowSize == nil:
                arrowSize = Double(trimmed).map { CGFloat($0) }
            case 10 where inLeader:
                pendingX = Double(trimmed).map { CGFloat($0) }
            case 20 where inLeader:
                if let x = pendingX, let y = Double(trimmed) {
                    let p = CGPoint(x: x, y: CGFloat(y))
                    if inLine { line.append(p) } else if landing == nil { landing = p }
                }
                pendingX = nil
            case 11 where inLeader && !inLine:
                pendingDX = Double(trimmed).map { CGFloat($0) }
            case 21 where inLeader && !inLine:
                if let x = pendingDX, let y = Double(trimmed) { dogleg = CGPoint(x: x, y: CGFloat(y)) }
                pendingDX = nil
            case 40 where inLeader && !inLine:
                doglegLength = Double(trimmed).map { CGFloat($0) } ?? 0
            case 305 where inLine:
                inLine = false
                var points = line
                if let land = landing, points.last.map({ Geometry.distance($0, land) > 1e-9 }) ?? true { points.append(land) }
                // horizontal part (dogleg) up to the text
                if let land = landing, doglegLength > 0, dogleg.length > 0 {
                    points.append(land + dogleg.normalized * doglegLength)
                }
                if points.count >= 2 { leaders.append(points) }
            case 303 where inLeader:
                inLeader = false
            case 301 where trimmed.uppercased().hasPrefix("}"):
                i = pairs.count     // end of CONTEXT_DATA
            default:
                break
            }
            i += 1
        }
        let height = (textHeight ?? 0) > 0 ? textHeight! : 2.5
        return leaders.enumerated().map { index, points in
            let leader = DimensionEntity(kind: .leader, points: points, text: index == 0 ? text : "",
                                         textHeight: height, layer: record.string(8) ?? "0", color: color)
            leader.arrowSize = (arrowSize ?? 0) > 0 ? arrowSize! : height
            return leader
        }
    }
}

// MARK: - Writer

class DXFWriter {
    private var out: [String] = []

    private func pair(_ code: Int, _ value: String) {
        out.append(String(code))
        out.append(DXFWriter.asciiOnly(value))
    }

    /// R12 (AC1009) has no UTF-8 – characters outside ASCII are written as \U+XXXX, which AutoCAD and other programs read.
    nonisolated static func asciiOnly(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { !$0.isASCII }) else { return value }
        var result = ""
        for scalar in value.unicodeScalars {
            if scalar.isASCII {
                result.unicodeScalars.append(scalar)
            } else if scalar.value <= 0xFFFF {
                result += String(format: "\\U+%04X", scalar.value)
            } else {
                result += "?"       // \U+ has only four digits
            }
        }
        return result
    }

    private func number(_ code: Int, _ value: CGFloat) {
        pair(code, String(format: "%.6f", Double(value)))
    }

    private func point(_ xCode: Int, _ p: CGPoint) {
        number(xCode, p.x)
        number(xCode + 10, p.y)
        number(xCode + 20, 0)
    }

    private func header(_ type: String, _ entity: CADEntity, color: NSColor?) {
        pair(0, type)
        pair(8, entity.layer)
        if let color = color { pair(62, String(ACIColor.index(for: color))) }
    }

    private func writePolyline(_ vertices: [CGPoint], closed: Bool, bulges: [CGFloat] = [], entity: CADEntity) {
        header("POLYLINE", entity, color: entity.color)
        pair(66, "1")
        point(10, .zero)
        pair(70, closed ? "1" : "0")
        for (index, v) in vertices.enumerated() {
            pair(0, "VERTEX")
            pair(8, entity.layer)
            point(10, v)
            if index < bulges.count, bulges[index] != 0 { number(42, bulges[index]) }
        }
        pair(0, "SEQEND")
        pair(8, entity.layer)
    }

    func write(document: CADDocument, layerManager: LayerManager, units: DrawingUnits = .mm, to url: URL) throws {
        out = []

        // HEADER
        pair(0, "SECTION"); pair(2, "HEADER")
        pair(9, "$ACADVER"); pair(1, "AC1009")
        pair(9, "$INSUNITS"); pair(70, String(units.dxfCode))
        pair(0, "ENDSEC")

        // TABLES – line types and layers
        let layers = layerManager.getAllLayers()
        pair(0, "SECTION"); pair(2, "TABLES")

        let lineTypes = LineTypeLibrary.all
        pair(0, "TABLE"); pair(2, "LTYPE"); pair(70, String(lineTypes.count))
        for type in lineTypes {
            pair(0, "LTYPE"); pair(2, type.dxfName); pair(70, "0")
            pair(3, type.description.isEmpty ? type.name : type.description); pair(72, "65")
            // R12 knows no texts and shapes in line types – only the dashes are written
            let pattern = type.plainPattern
            pair(73, String(pattern.count))
            number(40, pattern.reduce(0) { $0 + abs($1) })
            for element in pattern { number(49, element) }   // + dash, − gap, 0 dot
        }
        pair(0, "ENDTAB")

        pair(0, "TABLE"); pair(2, "LAYER"); pair(70, String(layers.count))
        for layer in layers {
            let colorIndex = ACIColor.index(for: layer.color)
            pair(0, "LAYER")
            pair(2, layer.name)
            pair(70, layer.isLocked ? "4" : "0")
            pair(62, String(layer.isVisible ? colorIndex : -colorIndex))
            pair(6, layer.lineType.dxfName)
            pair(290, layer.isPrintable ? "1" : "0")
            pair(370, String(Int((layer.lineWeight * 100).rounded())))
        }
        pair(0, "ENDTAB")
        pair(0, "ENDSEC")

        // ENTITIES
        pair(0, "SECTION"); pair(2, "ENTITIES")
        // sorted by draw order: other CAD programs draw later objects on top
        for entity in DrawOrder.sorted(document.getAllEntities()) {
            writeEntity(entity, layerManager: layerManager)
        }
        pair(0, "ENDSEC")
        pair(0, "EOF")

        try (out.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// A single object into the ENTITIES section.
    private func writeEntity(_ entity: CADEntity, layerManager: LayerManager) {
        switch entity {
        case let surveyPoint as SurveyPoint:
            header("POINT", surveyPoint, color: surveyPoint.color)
            pair(10, String(format: "%.6f", Double(surveyPoint.position.x)))
            pair(20, String(format: "%.6f", Double(surveyPoint.position.y)))
            pair(30, String(format: "%.3f", surveyPoint.z ?? 0))

        case let line as Line:
            header("LINE", line, color: line.color)
            point(10, line.startPoint)
            point(11, line.endPoint)

        case let circle as Circle:
            header("CIRCLE", circle, color: circle.color)
            point(10, circle.center)
            number(40, circle.radius)

        case let arc as Arc:
            header("ARC", arc, color: arc.color)
            point(10, arc.center)
            number(40, arc.radius)
            number(50, arc.startAngle * 180 / .pi)
            number(51, Geometry.normalizeAngle(arc.startAngle + arc.sweep) * 180 / .pi)

        case let polyline as Polyline:
            writePolyline(polyline.vertices, closed: polyline.closed, bulges: polyline.bulges, entity: polyline)

        case let spline as Spline:
            writePolyline(spline.flattened, closed: false, entity: spline)

        case let ellipse as Ellipse:
            // R12 has no ELLIPSE – a dense polyline
            var points = ellipse.flattened
            if ellipse.isFull, points.count > 2 { points.removeLast() }
            writePolyline(points, closed: ellipse.isFull, entity: ellipse)

        case let dimension as DimensionEntity:
            writeExploded(dimension, layerManager: layerManager)

        case let text as TextEntity:
            writeText(text)

        case let hatch as HatchEntity:
            // R12 has no HATCH: the boundary as closed polylines + the pattern lines
            for loop in hatch.loops where loop.count >= 3 {
                writePolyline(loop, closed: true, entity: hatch)
            }
            let geometry = hatch.patternGeometry()
            for (a, b) in geometry.segments {
                header("LINE", hatch, color: hatch.color)
                point(10, a)
                point(11, b)
            }
            for dot in geometry.dots {
                header("POINT", hatch, color: hatch.color)
                point(10, dot)
            }

        case let reference as BlockReference:
            // R12 without blocks: the block's content as separate objects
            for child in reference.exploded() { writeEntity(child, layerManager: layerManager) }

        default:
            break
        }
    }

    /// A dimension is saved as plain lines, arcs, arrows and text.
    private func writeExploded(_ dimension: DimensionEntity, layerManager: LayerManager) {
        let parts = dimension.buildParts()
        let color = dimension.color

        for (a, b) in parts.lines {
            header("LINE", dimension, color: color)
            point(10, a)
            point(11, b)
        }
        for arc in parts.arcs {
            header("ARC", dimension, color: color)
            point(10, arc.center)
            number(40, arc.radius)
            number(50, Geometry.normalizeAngle(arc.start) * 180 / .pi)
            number(51, Geometry.normalizeAngle(arc.start + arc.sweep) * 180 / .pi)
        }
        for arrow in parts.arrows {
            // ticks and open arrows as lines, a filled arrow as SOLID, a dot as a small circle
            for (a, b) in dimension.terminatorLines(arrow.tip, arrow.direction) {
                header("LINE", dimension, color: color)
                point(10, a)
                point(11, b)
            }
            switch dimension.effectiveArrowStyle {
            case .arrow:
                let corners = dimension.arrowPolygon(arrow.tip, arrow.direction)
                header("SOLID", dimension, color: color)
                point(10, corners[0])
                point(11, corners[1])
                point(12, corners[2])
                point(13, corners[2])
            case .dot:
                header("CIRCLE", dimension, color: color)
                point(10, arrow.tip)
                number(40, dimension.arrowSize * 0.25)
            default:
                break
            }
        }

        let text = dimension.displayText
        guard !text.isEmpty else { return }
        let gap = dimension.textHeight * 0.25
        let up = CGPoint(x: -sin(parts.textAngle), y: cos(parts.textAngle))
        let anchor = parts.textAbove ? parts.textAnchor + up * gap : parts.textAnchor
        header("TEXT", dimension, color: color)
        point(10, anchor)
        number(40, dimension.textHeight)
        pair(1, text)
        number(50, Geometry.normalizeAngle(parts.textAngle) * 180 / .pi)
        let horizontal: String
        switch parts.textAlignment {
        case .left: horizontal = "0"
        case .center: horizontal = "1"
        case .right: horizontal = "2"
        }
        pair(72, horizontal)
        point(11, anchor)
        pair(73, parts.textAbove ? "1" : "2")

        // text below the line
        guard !dimension.belowText.isEmpty, dimension.kind != .leader else { return }
        let below = parts.textAnchor - up * gap
        header("TEXT", dimension, color: color)
        point(10, below)
        number(40, dimension.textHeight)
        pair(1, dimension.belowText)
        number(50, Geometry.normalizeAngle(parts.textAngle) * 180 / .pi)
        pair(72, horizontal)
        point(11, below)
        pair(73, "3")
    }

    /// Text as TEXT lines (R12 has no MTEXT); the font is not transferred.
    private func writeText(_ text: TextEntity) {
        let up = CGPoint(x: -sin(text.rotation), y: cos(text.rotation))
        // lines every 5/3 of the cap height (like MTEXT in AutoCAD) × line spacing
        let step = text.height * 5 / 3 * max(text.lineSpacing, 0.5)
        let horizontal: String
        switch text.justify {
        case .left: horizontal = "0"
        case .center: horizontal = "1"
        case .right: horizontal = "2"
        }
        // a paragraph is written as the lines it wraps into
        for (index, line) in text.wrappedLines.enumerated() where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let base = text.position - up * (CGFloat(index) * step)
            header("TEXT", text, color: text.color)
            point(10, base)
            number(40, text.height)
            // a tab is written with a caret in DXF
            pair(1, line.replacingOccurrences(of: "^", with: "^ ").replacingOccurrences(of: "\t", with: "^I"))
            if text.rotation != 0 { number(50, Geometry.normalizeAngle(text.rotation) * 180 / .pi) }
            if text.widthFactor != 1 { number(41, text.widthFactor) }
            if horizontal != "0" {
                pair(72, horizontal)
                point(11, base)
            }
        }
    }
}

// MARK: - Point coordinate list (surveyor, TXT/CSV)

/// Lines “number  Y  X  [Z]  [code]” in S-JTSK (meters, positive numbers). Separators: spaces, tabs,
/// semicolons (with those a decimal comma is allowed). Lines that are not points are skipped.
enum SurveyPointList {
    struct Entry {
        var number: String
        var y: Double
        var x: Double
        var z: Double?
        var code: String
    }

    static func read(from url: URL) throws -> [Entry] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1250)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw EditError(message: "The file could not be read as text.")
        }
        var entries: [Entry] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), !line.hasPrefix(";") else { continue }
            var separators = CharacterSet.whitespaces.union(CharacterSet(charactersIn: ";\t"))
            // commas only (CSV without semicolons): the comma separates columns
            if !line.contains(";") && !line.contains("\t") && line.contains(",") && !line.contains(" ") {
                separators = CharacterSet(charactersIn: ",")
            }
            let tokens = line.components(separatedBy: separators).filter { !$0.isEmpty }
            guard tokens.count >= 3 else { continue }
            func number(_ token: String) -> Double? {
                return Double(token.replacingOccurrences(of: ",", with: "."))
            }
            guard var y = number(tokens[1]), var x = number(tokens[2]) else { continue }
            // in the Czech Republic / Slovakia Y < X always – a reversed column order is swapped
            if y > x { swap(&y, &x) }
            guard y > 100_000, x > 100_000 else { continue }
            let z = tokens.count > 3 ? number(tokens[3]) : nil
            var code = tokens.count > (z == nil ? 3 : 4) ? tokens[z == nil ? 3 : 4] : ""
            while code.hasSuffix("*") { code.removeLast() }
            entries.append(Entry(number: tokens[0], y: y, x: x, z: z, code: code))
        }
        guard !entries.isEmpty else {
            throw EditError(message: "No points found. Expected lines like “number  Y  X  Z  code” in S-JTSK (meters).")
        }
        return entries
    }
}
