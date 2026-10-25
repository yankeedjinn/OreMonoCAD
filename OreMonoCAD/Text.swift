//
//  Text.swift
//  OreMonoCAD
//
//  Text in the drawing: single-line and multi-line, with font, style, height, rotation,
//  alignment, underline and paragraph width (wrapping).
//
//  - Text height is in world units (font size); a new text gets its height
//    from the paper height (mm) and the drawing scale – like line types and hatches.
//  - Insertion point = baseline of the first line (left / center / right according to the alignment),
//    further lines go down.
//  - The text layout is computed at a reference size and cached,
//    drawn via AppKit (NSAttributedString) – works on screen, in PDF and on a printer.
//

import Cocoa
import CoreText

// MARK: - Alignment and text kinds

enum TextJustify: String, CaseIterable {
    case left, center, right

    var title: String {
        switch self {
        case .left: return "Left"
        case .center: return "Center"
        case .right: return "Right"
        }
    }

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        }
    }
}

/// Text insertion method (menu of the Text tool – like for the arc).
enum TextKind: Int, CaseIterable {
    case simple, multiline, formatted

    var title: String {
        switch self {
        case .simple: return "Simple Text"
        case .multiline: return "Paragraph Text"
        case .formatted: return "Formatted Text"
        }
    }

    var detail: String {
        switch self {
        case .simple: return "Click and type · the ☰ menu next to the text adds font, height, rotation…"
        case .multiline: return "Drag or click a box – the lines wrap to its width"
        case .formatted: return "Click a point – the format panel opens right away"
        }
    }

    var prompt: String {
        switch self {
        case .simple: return "Text: click where the text starts (its baseline)"
        case .multiline: return "Paragraph text: click the first corner of the text box"
        case .formatted: return "Formatted text: click where the text starts"
        }
    }
}

// MARK: - Default style of new text

struct TextStyleDefaults {
    /// Font family ("" = system font).
    var family = ""
    /// Style (“Regular”, “Bold”, “Italic”…).
    var face = "Regular"
    /// Height on paper in mm.
    var heightMM: CGFloat = 3.5
    var justify: TextJustify = .left
    var underline = false

    private static let key = "OreMonoCAD.textStyle"

    static func load() -> TextStyleDefaults {
        var style = TextStyleDefaults()
        guard let saved = UserDefaults.standard.dictionary(forKey: key) else { return style }
        style.family = saved["family"] as? String ?? style.family
        style.face = saved["face"] as? String ?? style.face
        if let height = saved["heightMM"] as? Double, height > 0 { style.heightMM = CGFloat(height) }
        style.justify = (saved["justify"] as? String).flatMap { TextJustify(rawValue: $0) } ?? style.justify
        style.underline = saved["underline"] as? Bool ?? style.underline
        return style
    }

    func save() {
        UserDefaults.standard.set(["family": family, "face": face, "heightMM": Double(heightMM),
                                   "justify": justify.rawValue, "underline": underline],
                                  forKey: TextStyleDefaults.key)
    }
}

// MARK: - Fonts

enum FontLibrary {
    static let systemFamilyTitle = "System Font"
    private static let systemFaces = ["Regular", "Medium", "Semibold", "Bold", "Italic", "Bold Italic"]

    /// Fonts that are part of the app (they are at the top of the menu).
    static let bundledFamilies = ["osifont"]
    private static var bundledRegistered = false

    /// Registers the fonts bundled with the app (*.ttf / *.otf in the bundle) – for this app only.
    static func registerBundledFonts() {
        guard !bundledRegistered else { return }
        bundledRegistered = true
        var urls: [URL] = []
        for ext in ["ttf", "otf"] {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: "Fonts") ?? []
        }
        for url in Set(urls) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        baseFonts.removeAll()
        capRatios.removeAll()
    }

    static var families: [String] {
        registerBundledFonts()
        let all = NSFontManager.shared.availableFontFamilies
        // bundled fonts first, then the others
        let bundled = all.filter { family in bundledFamilies.contains { $0.caseInsensitiveCompare(family) == .orderedSame } }
        return bundled + all.filter { !bundled.contains($0) }
    }

    /// Font family by the style name / font file from DXF (e.g. “osifont.ttf”) – nil = unknown.
    static func family(matching name: String) -> String? {
        registerBundledFonts()
        let base = (name as NSString).deletingPathExtension.lowercased()
        guard !base.isEmpty else { return nil }
        let all = NSFontManager.shared.availableFontFamilies
        if base.hasPrefix("osifont"), let osi = all.first(where: { $0.lowercased().hasPrefix("osifont") }) { return osi }
        return all.first { $0.lowercased() == base }
    }

    /// Font styles (names as in the system font panel).
    static func faces(of family: String) -> [String] {
        guard !family.isEmpty else { return systemFaces }
        let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
        let names = members.compactMap { $0.count > 1 ? $0[1] as? String : nil }
        return names.isEmpty ? ["Regular"] : names
    }

    /// Font of the given family and style (unknown → system).
    /// Base font of the family and style (looked up once), then only the size changes.
    private static var baseFonts: [String: NSFont] = [:]
    private static var capRatios: [String: CGFloat] = [:]

    private static func baseFont(family: String, face: String) -> NSFont {
        let key = "\(family)|\(face)"
        if let cached = baseFonts[key] { return cached }
        var font: NSFont?
        if family.isEmpty {
            let lower = face.lowercased()
            let weight: NSFont.Weight = lower.contains("bold") ? .bold : lower.contains("semibold") ? .semibold
                : lower.contains("medium") ? .medium : .regular
            var system = NSFont.systemFont(ofSize: 100, weight: weight)
            if lower.contains("italic") { system = NSFontManager.shared.convert(system, toHaveTrait: .italicFontMask) }
            font = system
        } else {
            registerBundledFonts()
            let members = NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []
            let member = members.first { ($0.count > 1 ? $0[1] as? String : nil) == face } ?? members.first
            if let name = member?.first as? String { font = NSFont(name: name, size: 100) }
            if font == nil { font = NSFont(name: family, size: 100) }
        }
        let result = font ?? NSFont.systemFont(ofSize: 100)
        baseFonts[key] = result
        return result
    }

    /// Font of the given family and style (unknown → system).
    static func font(family: String, face: String, size: CGFloat) -> NSFont {
        let base = baseFont(family: family, face: face)
        let safe = size.isFinite ? min(max(size, 0.5), 4000) : 12
        return NSFont(descriptor: base.fontDescriptor, size: safe) ?? base
    }

    /// Cap height relative to the font size (text height in CAD = height of capital letters).
    static func capRatio(family: String, face: String) -> CGFloat {
        let key = "\(family)|\(face)"
        if let cached = capRatios[key] { return cached }
        let font = baseFont(family: family, face: face)
        var ratio = font.capHeight / max(font.pointSize, 1)
        if !ratio.isFinite || ratio < 0.4 || ratio > 0.95 { ratio = 0.7 }
        capRatios[key] = ratio
        return ratio
    }
}

// MARK: - Text entity

final class TextEntity: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?

    /// Insertion point: baseline of the first line (according to left / center / right alignment).
    var position: CGPoint { didSet { invalidate() } }
    var text: String { didSet { invalidate() } }
    /// Font size in world units.
    var height: CGFloat { didSet { invalidate() } }
    /// Rotation in radians (counterclockwise).
    var rotation: CGFloat = 0 { didSet { invalidate() } }
    /// Font family ("" = system).
    var fontFamily = "" { didSet { invalidate() } }
    /// Font style (Regular, Bold, Italic…).
    var fontFace = "Regular" { didSet { invalidate() } }
    var justify: TextJustify = .left { didSet { invalidate() } }
    var underline = false { didSet { invalidate() } }
    /// Paragraph width in world units (nil = no wrapping).
    var boxWidth: CGFloat? { didSet { invalidate() } }
    /// Line spacing (1 = normal).
    var lineSpacing: CGFloat = 1 { didSet { invalidate() } }
    /// Font width (1 = normal, 0.8 = condensed – the “width factor”).
    var widthFactor: CGFloat = 1 { didSet { invalidate() } }
    /// Room label: the last line holds the floor area of the room around the insertion point, kept up to date (RoomLabel.swift).
    var isRoomLabel = false
    /// The outline bounds of the room last measured (not saved – only to know which changes concern the label).
    var roomBounds: CGRect?

    /// Font size (em) for the cap height `height`: the text height is, as in CAD, the height of capital letters.
    var emScale: CGFloat {
        return 1 / FontLibrary.capRatio(family: fontFamily, face: fontFace)
    }

    init(position: CGPoint, text: String, height: CGFloat, layer: String = "0", color: NSColor? = nil) {
        self.position = position
        self.text = text
        self.height = max(height, 1e-6)
        self.layer = layer
        self.color = color
    }

    var typeName: String { return "Text" }

    var infoText: String {
        let lines = text.components(separatedBy: "\n").count
        var info = String(format: "Text\n%@\n\nPosition: %.3f, %.3f\nHeight:   %.3f\nRotation: %@\nFont:     %@ %@\nLines:    %ld",
                          commonInfo, position.x, position.y, height, AngleStyle.text(rotation * 180 / .pi, .direction),
                          fontFamily.isEmpty ? FontLibrary.systemFamilyTitle : fontFamily, fontFace, lines)
        if widthFactor != 1 { info += String(format: "\nWidth:    %.2f×", widthFactor) }
        if let width = boxWidth { info += String(format: "\nBox:      %.3f", width) }
        if isRoomLabel { info += "\nRoom label: the area (last line) follows the walls" }
        return info
    }

    // MARK: Layout (in drawing units, text coordinates: x right, y up, origin = insertion point)

    private static let referenceSize: CGFloat = 100
    private var cachedLayout: (box: CGRect, ascent: CGFloat)?
    /// The text measured at the reference size (measuring is the most expensive part of drawing).
    private var cachedMeasure: (color: NSColor, attributed: NSAttributedString, size: CGRect)?

    private func invalidate() {
        cachedLayout = nil
        cachedMeasure = nil
        cachedWrapWidth = nil
    }

    private var cachedWrapWidth: CGFloat??

    /// The width at which the paragraph wraps: it never breaks in the middle of a word –
    /// a word longer than the box “stretches” the box (otherwise words would fall apart letter by letter).
    var wrapWidth: CGFloat? {
        if let cached = cachedWrapWidth { return cached }
        guard let box = boxWidth else {
            cachedWrapWidth = .some(nil)
            return nil
        }
        let k = height * emScale / TextEntity.referenceSize
        let font = FontLibrary.font(family: fontFamily, face: fontFace, size: TextEntity.referenceSize)
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let longest = words.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let needed = ceil(longest * 1.03 + 2) * k * max(widthFactor, 0.05)
        let result = max(box, needed.isFinite ? needed : box)
        cachedWrapWidth = .some(result)
        return result
    }

    /// The lines as drawn: a paragraph (box width) broken where it wraps. DXF TEXT can't wrap, so the export needs them.
    var wrappedLines: [String] {
        guard let wrap = wrapWidth else { return text.components(separatedBy: "\n") }
        let k = height * emScale / TextEntity.referenceSize
        let storage = NSTextStorage(attributedString: attributedString(fontSize: TextEntity.referenceSize, color: .white))
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(wrap / (k * max(widthFactor, 0.05)), 1),
                                                     height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let string = storage.string as NSString
        var lines: [String] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, glyphRange, _ in
            let range = manager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            lines.append(string.substring(with: range).trimmingCharacters(in: .newlines))
        }
        return lines
    }

    func attributedString(fontSize: CGFloat, color: NSColor) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = justify.nsAlignment
        paragraph.lineHeightMultiple = max(0.5, lineSpacing)
        // tabs (e.g. room tables from DXF): tab stops every 4 font heights
        paragraph.tabStops = []
        paragraph.defaultTabInterval = fontSize * 4
        var attributes: [NSAttributedString.Key: Any] = [
            .font: FontLibrary.font(family: fontFamily, face: fontFace, size: fontSize),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: text.isEmpty ? " " : text, attributes: attributes)
    }

    /// Text box and height above the baseline (world).
    private var layout: (box: CGRect, ascent: CGFloat) {
        if let cached = cachedLayout { return cached }
        // k: drawing units per font point at size referenceSize; width additionally × widthFactor
        let k = height * emScale / TextEntity.referenceSize
        let wf = max(widthFactor, 0.05)
        let reference = attributedString(fontSize: TextEntity.referenceSize, color: .white)
        let wrap = wrapWidth.map { max($0 / (k * wf), 1) } ?? CGFloat.greatestFiniteMagnitude
        let size = reference.boundingRect(with: CGSize(width: wrap, height: .greatestFiniteMagnitude),
                                          options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let font = FontLibrary.font(family: fontFamily, face: fontFace, size: TextEntity.referenceSize)
        // Box = the width the text actually occupies, not the paragraph width. A paragraph from DXF (MTEXT) is often much
        // wider than the text (even thousands of units) – the box would then reach far beyond the text: selection by clicking
        // “into empty space”, a wrong Zoom Extents and, when zoomed out, long lines instead of text. Lines inside
        // the paragraph are aligned to the insertion point (left / center / right), so the paragraph width
        // does not change the text position – only where it wraps.
        let width = ceil(size.width) * wf
        let ascent = font.ascender
        let x: CGFloat
        switch justify {
        case .left: x = 0
        case .center: x = -width / 2
        case .right: x = -width
        }
        let box = CGRect(x: x * k, y: (ascent - ceil(size.height)) * k, width: width * k, height: ceil(size.height) * k)
        let result = (box, ascent * k)
        cachedLayout = result
        return result
    }

    /// From the text's local coordinates to the world.
    private var localToWorld: CGAffineTransform {
        return CGAffineTransform(translationX: position.x, y: position.y).rotated(by: rotation)
    }

    /// Corners of the text box in the world.
    var corners: [CGPoint] {
        let b = layout.box
        let t = localToWorld
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY),
                CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)].map { $0.applying(t) }
    }

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: corners)
        path.closeSubpath()
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        let scale = Geometry.uniformScale(of: transform)
        let fontSize = height * emScale * scale
        guard fontSize.isFinite, fontSize > 0 else { return }
        if fontSize < 3.5 {
            // text too small: instead of each line a dash the length of the text (fast and readable as “there is text here”)
            let b = layout.box
            // font line height (as when drawing): from the font at the reference size
            let reference = FontLibrary.font(family: fontFamily, face: fontFace, size: TextEntity.referenceSize)
            let k = height * emScale / TextEntity.referenceSize
            let rowHeight = (reference.ascender - reference.descender + reference.leading) * k * max(lineSpacing, 0.5)
            let rows = max(1, min(200, Int((b.height / max(rowHeight, 1e-9)).rounded())))
            let step = b.height / CGFloat(rows)
            let path = CGMutablePath()
            for row in 0..<rows {
                let y = b.maxY - (CGFloat(row) + 0.5) * step
                path.move(to: CGPoint(x: b.minX, y: y).applying(localToWorld))
                path.addLine(to: CGPoint(x: b.maxX, y: y).applying(localToWorld))
            }
            var thin = style
            thin.dash = []
            thin.lineWidth = max(0.5, min(style.lineWidth, fontSize * 0.6))
            strokeWorldPath(path, in: context, transform: transform, style: thin)
            return
        }
        guard fontSize < 4000 else { return }
        let anchor = position.applying(transform)
        guard DrawingSafety.isFinite(anchor), abs(anchor.x) < DrawingSafety.maxCoordinate,
              abs(anchor.y) < DrawingSafety.maxCoordinate else { return }
        // direction of the text's x axis on screen (because of view mirroring and rotation)
        let dir = CGPoint(x: cos(rotation), y: sin(rotation))
        let screenDir = CGPoint(x: transform.a * dir.x + transform.c * dir.y, y: transform.b * dir.x + transform.d * dir.y)
        let screenAngle = atan2(screenDir.y, screenDir.x)

        // The text is always laid out at the reference size and only the drawing is scaled. Laid out at the
        // on-screen size, the glyph widths would not follow the zoom exactly (the system font changes its letter
        // spacing and design with the point size, and small sizes are rounded to whole pixels), so the text would
        // shift against the drawing and rewrap differently at every zoom. This way it scales exactly with the drawing
        // and matches the box from `layout`, which is measured at the same reference size.
        let wf = max(widthFactor, 0.05)
        let reference = TextEntity.referenceSize
        let s = fontSize / reference
        let font = FontLibrary.font(family: fontFamily, face: fontFace, size: reference)
        let ascent = font.ascender
        // wrapping happens at the width before the font is condensed (it is then drawn condensed)
        let k = height * emScale / reference
        let wrapWidth: CGFloat = self.wrapWidth.map { max($0 / (k * wf), 1) } ?? 10_000_000
        let attributed: NSAttributedString
        let measured: CGRect
        if let cached = cachedMeasure, cached.color == style.color {
            attributed = cached.attributed
            measured = cached.size
        } else {
            attributed = attributedString(fontSize: reference, color: style.color)
            measured = attributed.boundingRect(with: CGSize(width: wrapWidth, height: CGFloat.greatestFiniteMagnitude),
                                               options: [.usesLineFragmentOrigin, .usesFontLeading])
            cachedMeasure = (style.color, attributed, measured)
        }
        // no paragraph: width from the longest line + a margin so nothing wraps
        let width = boxWidth != nil ? wrapWidth : ceil(measured.width) + reference * 0.25
        let x: CGFloat
        switch justify {
        case .left: x = 0
        case .center: x = -width / 2
        case .right: x = -width
        }
        let rect = CGRect(x: x, y: -ascent, width: width, height: ceil(measured.height) + reference)

        context.saveGState()
        context.translateBy(x: anchor.x, y: anchor.y)
        context.rotate(by: screenAngle)
        context.scaleBy(x: wf * s, y: -s)      // zoom and font condensing; AppKit text top to bottom (flipped context)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.current = previous
        context.restoreGState()
    }

    func boundingBox() -> CGRect {
        let c = corners
        let xs = c.map { $0.x }, ys = c.map { $0.y }
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
    }

    /// Inside the box = 0 (the text is selected by clicking anywhere inside it).
    func distance(to point: CGPoint) -> CGFloat {
        let local = point.applying(localToWorld.inverted())
        let b = layout.box
        if b.contains(local) { return 0 }
        let dx = max(b.minX - local.x, 0, local.x - b.maxX)
        let dy = max(b.minY - local.y, 0, local.y - b.maxY)
        return hypot(dx, dy)
    }

    func snapPoints() -> [SnapPoint] {
        return [SnapPoint(point: position, type: .insertion)]
    }

    /// Move, rotate, scale; mirroring does not flip the text (it stays readable).
    func applyTransform(_ transform: CGAffineTransform) {
        let scale = Geometry.uniformScale(of: transform)
        let dir = CGPoint(x: cos(rotation), y: sin(rotation))
        let moved = CGPoint(x: transform.a * dir.x + transform.c * dir.y, y: transform.b * dir.x + transform.d * dir.y)
        position = position.applying(transform)
        if scale.isFinite, scale > 0 {
            height *= scale
            if let width = boxWidth { boxWidth = width * scale }
        }
        var angle = atan2(moved.y, moved.x)
        if Geometry.isMirroring(transform) {
            // mirrored text is rotated by 180° if it would be upside down
            let normalized = Geometry.normalizeAngle(angle)
            if normalized > .pi / 2 + 1e-6 && normalized < 3 * .pi / 2 - 1e-6 { angle -= .pi }
        }
        rotation = Geometry.normalizeAngle(angle)
    }

    func clone() -> CADEntity {
        let copy = TextEntity(position: position, text: text, height: height, layer: layer, color: color)
        copy.copyFormat(from: self)
        copy.isRoomLabel = isRoomLabel
        copy.roomBounds = roomBounds
        return copyStyle(to: copy)
    }

    /// Takes over the format (everything except position and content).
    func copyFormat(from other: TextEntity) {
        widthFactor = other.widthFactor
        rotation = other.rotation
        fontFamily = other.fontFamily
        fontFace = other.fontFace
        justify = other.justify
        underline = other.underline
        boxWidth = other.boxWidth
        lineSpacing = other.lineSpacing
    }

    func primitives() -> [Primitive] { return [] }
}

// MARK: - Default text style (Text Style…)

/// Font, style, height on paper and alignment for new text.
final class TextStyleDialog: NSObject {
    private let familyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let facePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    private var selectedFamily: String {
        return familyPopup.indexOfSelectedItem <= 0 ? "" : (familyPopup.titleOfSelectedItem ?? "")
    }

    private func rebuildFaces(select face: String) {
        facePopup.removeAllItems()
        let faces = FontLibrary.faces(of: selectedFamily)
        facePopup.addItems(withTitles: faces)
        if faces.contains(face) {
            facePopup.selectItem(withTitle: face)
        } else if let regular = faces.first(where: { ["Regular", "Roman", "Book", "Medium"].contains($0) }) {
            facePopup.selectItem(withTitle: regular)
        }
    }

    @objc private func familyChanged() {
        rebuildFaces(select: facePopup.titleOfSelectedItem ?? "Regular")
    }

    /// nil = Cancel.
    func run(current: TextStyleDefaults, scaleNote: String) -> TextStyleDefaults? {
        familyPopup.addItem(withTitle: FontLibrary.systemFamilyTitle)
        familyPopup.menu?.addItem(.separator())
        familyPopup.addItems(withTitles: FontLibrary.families)
        if current.family.isEmpty { familyPopup.selectItem(at: 0) } else { familyPopup.selectItem(withTitle: current.family) }
        familyPopup.target = self
        familyPopup.action = #selector(familyChanged)
        rebuildFaces(select: current.face)

        let height = NSTextField(string: LineType.format(current.heightMM))
        height.widthAnchor.constraint(equalToConstant: 70).isActive = true
        height.toolTip = "Height of capital letters in mm on paper"
        let justify = NSSegmentedControl(labels: TextJustify.allCases.map { $0.title }, trackingMode: .selectOne, target: nil, action: nil)
        justify.selectedSegment = TextJustify.allCases.firstIndex(of: current.justify) ?? 0
        let underline = NSButton(checkboxWithTitle: "Underline", target: nil, action: nil)
        underline.state = current.underline ? .on : .off

        let heightRow = NSStackView(views: [height, NSTextField(labelWithString: "mm on paper")])
        heightRow.spacing = 6
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Font:"), familyPopup],
                                      [NSTextField(labelWithString: "Typeface:"), facePopup],
                                      [NSTextField(labelWithString: "Height:"), heightRow],
                                      [NSTextField(labelWithString: "Alignment:"), justify],
                                      [NSGridCell.emptyContentView, underline]])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.frame.size = grid.fittingSize

        let alert = NSAlert()
        alert.messageText = "Text Style"
        alert.informativeText = "Used for new text. \(scaleNote)"
        alert.accessoryView = grid
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        var style = current
        style.family = selectedFamily
        style.face = facePopup.titleOfSelectedItem ?? "Regular"
        if let value = ExpressionEvaluator.evaluate(height.stringValue), value > 0 { style.heightMM = CGFloat(value) }
        style.justify = TextJustify.allCases[max(0, justify.selectedSegment)]
        style.underline = underline.state == .on
        return style
    }
}

// MARK: - Text format (for editing directly on the canvas)

/// Everything except content and position – what is changed in the panel under the ☰ format button.
struct TextFormat: Equatable {
    var family = ""
    var face = "Regular"
    /// Font size in world units.
    var height: CGFloat = 2.5
    var rotationDegrees: CGFloat = 0
    var justify: TextJustify = .left
    var underline = false
    /// Paragraph width (nil = no wrapping).
    var boxWidth: CGFloat?
    var lineSpacing: CGFloat = 1

    /// Does it differ from plain text (default font, no rotation…)?
    func isFormatted(comparedTo style: TextStyleDefaults) -> Bool {
        return family != style.family || face != style.face || rotationDegrees != 0 || underline != style.underline
            || justify != style.justify || boxWidth != nil || lineSpacing != 1
    }
}

extension TextEntity {
    var format: TextFormat {
        return TextFormat(family: fontFamily, face: fontFace, height: height, rotationDegrees: rotation * 180 / .pi,
                          justify: justify, underline: underline, boxWidth: boxWidth, lineSpacing: lineSpacing)
    }

    func apply(_ format: TextFormat) {
        fontFamily = format.family
        fontFace = format.face
        height = max(format.height, 1e-6)
        rotation = Geometry.normalizeAngle(format.rotationDegrees * .pi / 180)
        justify = format.justify
        underline = format.underline
        boxWidth = format.boxWidth
        lineSpacing = format.lineSpacing
    }
}

/// Text editing panel (in the popover at the ☰ format button): every change takes effect immediately.
final class TextFormatPanel: NSViewController {
    var onChange: ((TextFormat) -> Void)?
    private(set) var format: TextFormat
    private let unitName: String

    private let familyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let facePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let heightField = NSTextField()
    private let rotationField = NSTextField()
    private let justifyControl = NSSegmentedControl(labels: TextJustify.allCases.map { $0.title },
                                                    trackingMode: .selectOne, target: nil, action: nil)
    private let underlineBox = NSButton(checkboxWithTitle: "Underline", target: nil, action: nil)
    private let widthField = NSTextField()
    private let spacingField = NSTextField()

    init(format: TextFormat, unitName: String) {
        self.format = format
        self.unitName = unitName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.alignment = .right
        return field
    }

    private func setupNumber(_ field: NSTextField, _ value: CGFloat?, width: CGFloat = 64) {
        field.stringValue = value.map { LineType.format($0) } ?? ""
        field.controlSize = .small
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        field.cell?.sendsActionOnEndEditing = true
        field.target = self
        field.action = #selector(changed)
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    override func loadView() {
        for popup in [familyPopup, facePopup] {
            popup.controlSize = .small
            popup.font = NSFont.systemFont(ofSize: 11)
            popup.target = self
        }
        familyPopup.addItem(withTitle: FontLibrary.systemFamilyTitle)
        familyPopup.menu?.addItem(.separator())
        familyPopup.addItems(withTitles: FontLibrary.families)
        if format.family.isEmpty { familyPopup.selectItem(at: 0) } else { familyPopup.selectItem(withTitle: format.family) }
        familyPopup.action = #selector(familyChanged)
        rebuildFaces(select: format.face)
        facePopup.action = #selector(changed)

        setupNumber(heightField, format.height)
        setupNumber(rotationField, AngleStyle.shown(format.rotationDegrees, .amount))
        setupNumber(widthField, format.boxWidth)
        setupNumber(spacingField, format.lineSpacing, width: 48)
        widthField.placeholderString = "no wrap"
        widthField.toolTip = "Paragraph width in drawing units – longer lines wrap. Empty = no wrapping"
        heightField.toolTip = "Height of capital letters in drawing units"
        rotationField.toolTip = "The preview at the cursor stays level; the placed text is rotated"

        justifyControl.controlSize = .small
        justifyControl.font = NSFont.systemFont(ofSize: 10)
        justifyControl.selectedSegment = TextJustify.allCases.firstIndex(of: format.justify) ?? 0
        justifyControl.target = self
        justifyControl.action = #selector(changed)
        underlineBox.controlSize = .small
        underlineBox.font = NSFont.systemFont(ofSize: 11)
        underlineBox.state = format.underline ? .on : .off
        underlineBox.target = self
        underlineBox.action = #selector(changed)

        let unit = { (text: String) -> NSTextField in
            let field = NSTextField(labelWithString: text)
            field.font = NSFont.systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            return field
        }
        let sizeRow = NSStackView(views: [heightField, unit(unitName), label(AngleStyle.caption("Rotation", .amount)), rotationField])
        sizeRow.spacing = 5
        let widthRow = NSStackView(views: [widthField, unit(unitName), label("Spacing"), spacingField])
        widthRow.spacing = 5

        let title = NSTextField(labelWithString: "Text Format")
        title.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let grid = NSGridView(views: [
            [label("Font"), familyPopup],
            [label("Typeface"), facePopup],
            [label("Height"), sizeRow],
            [label("Alignment"), justifyControl],
            [NSGridCell.emptyContentView, underlineBox],
            [label("Width"), widthRow]
        ])
        grid.rowSpacing = 6
        grid.columnSpacing = 6
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        let hint = NSTextField(wrappingLabelWithString: "Changes show right away · ⌥↩ in the text = new line · ↩ places the text")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, grid, hint])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        hint.widthAnchor.constraint(lessThanOrEqualToConstant: 300).isActive = true
        stack.frame.size = stack.fittingSize
        view = stack
    }

    private var selectedFamily: String {
        return familyPopup.indexOfSelectedItem <= 0 ? "" : (familyPopup.titleOfSelectedItem ?? "")
    }

    private func rebuildFaces(select face: String) {
        facePopup.removeAllItems()
        let faces = FontLibrary.faces(of: selectedFamily)
        facePopup.addItems(withTitles: faces)
        if faces.contains(face) {
            facePopup.selectItem(withTitle: face)
        } else if let regular = faces.first(where: { ["Regular", "Roman", "Book", "Medium"].contains($0) }) {
            facePopup.selectItem(withTitle: regular)
        }
    }

    @objc private func familyChanged() {
        rebuildFaces(select: facePopup.titleOfSelectedItem ?? "Regular")
        changed()
    }

    private func number(_ field: NSTextField) -> CGFloat? {
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return ExpressionEvaluator.evaluate(text).map { CGFloat($0) }
    }

    @objc private func changed() {
        var f = format
        f.family = selectedFamily
        f.face = facePopup.titleOfSelectedItem ?? f.face
        if let height = number(heightField), height > 0 { f.height = height } else { heightField.stringValue = LineType.format(f.height) }
        f.rotationDegrees = number(rotationField).map { AngleStyle.degrees($0, .amount) } ?? 0
        f.justify = TextJustify.allCases[max(0, justifyControl.selectedSegment)]
        f.underline = underlineBox.state == .on
        f.boxWidth = number(widthField).flatMap { $0 > 0 ? $0 : nil }
        f.lineSpacing = max(0.5, min(number(spacingField) ?? 1, 5))
        guard f != format else { return }
        format = f
        onChange?(f)
    }
}
