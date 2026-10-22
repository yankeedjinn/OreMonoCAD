//
//  Plot.swift
//  OhMyCAD
//
//  Plotting as in AutoCAD / DraftSight: one dialog for printers, PDF and images.
//
//  - Devices: macOS printers, PDF (vector), PNG / JPEG / TIFF.
//  - Paper and orientation, plot area (Extents / Display / Window / Layout), scale or
//    “Fit to paper”, offset (centered / X,Y), lineweights.
//  - Plot style: Color, Monochrome, Grayscale or an imported AutoCAD .ctb table (see PlotStyles.swift).
//  - Named settings (Page Setups) are stored in the drawing.
//  - A live page preview on the right.
//
//  Page drawing (PlotRenderer) is shared by the preview, PDF, images and the printer.
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - Plot settings

nonisolated struct PlotSettings: Codable, Equatable {
    /// Name of the named setting (Page Setup); nil = unsaved.
    var name: String?
    /// pdf | png | jpeg | tiff | printer
    var device: String = "pdf"
    var printerName: String?
    /// PaperSize.rawValue
    var paper: String = "a4"
    /// 0 = automatic, 1 = portrait, 2 = landscape
    var orientation: Int = 0
    /// extents | display | window | layout
    var area: String = "extents"
    var window: CGRect?
    var fitToPaper: Bool = false
    var scalePaper: CGFloat = 1
    var scaleModel: CGFloat = 1
    var centered: Bool = true
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    /// color | monochrome | grayscale | table (= styleTable)
    var style: String = "color"
    /// Imported plot style table (.ctb), used when style == "table".
    var styleTable: PlotStyleTable?
    var plotLineweights: Bool = true
    var marginMM: CGFloat = 10
    var dpi: CGFloat = 300
    var transparent: Bool = false
    var showSystemDialog: Bool = false

    init() {}

    // every field is optional → older and newer files can be read
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PlotSettings.defaults
        name = try c.decodeIfPresent(String.self, forKey: .name)
        device = try c.decodeIfPresent(String.self, forKey: .device) ?? d.device
        printerName = try c.decodeIfPresent(String.self, forKey: .printerName)
        paper = try c.decodeIfPresent(String.self, forKey: .paper) ?? d.paper
        orientation = try c.decodeIfPresent(Int.self, forKey: .orientation) ?? d.orientation
        area = try c.decodeIfPresent(String.self, forKey: .area) ?? d.area
        window = try c.decodeIfPresent(CGRect.self, forKey: .window)
        fitToPaper = try c.decodeIfPresent(Bool.self, forKey: .fitToPaper) ?? d.fitToPaper
        scalePaper = try c.decodeIfPresent(CGFloat.self, forKey: .scalePaper) ?? d.scalePaper
        scaleModel = try c.decodeIfPresent(CGFloat.self, forKey: .scaleModel) ?? d.scaleModel
        centered = try c.decodeIfPresent(Bool.self, forKey: .centered) ?? d.centered
        offsetX = try c.decodeIfPresent(CGFloat.self, forKey: .offsetX) ?? d.offsetX
        offsetY = try c.decodeIfPresent(CGFloat.self, forKey: .offsetY) ?? d.offsetY
        style = try c.decodeIfPresent(String.self, forKey: .style) ?? d.style
        styleTable = try c.decodeIfPresent(PlotStyleTable.self, forKey: .styleTable)
        plotLineweights = try c.decodeIfPresent(Bool.self, forKey: .plotLineweights) ?? d.plotLineweights
        marginMM = try c.decodeIfPresent(CGFloat.self, forKey: .marginMM) ?? d.marginMM
        dpi = try c.decodeIfPresent(CGFloat.self, forKey: .dpi) ?? d.dpi
        transparent = try c.decodeIfPresent(Bool.self, forKey: .transparent) ?? d.transparent
        showSystemDialog = try c.decodeIfPresent(Bool.self, forKey: .showSystemDialog) ?? d.showSystemDialog
    }

    static let defaults = PlotSettings()

    /// The plot style table in use (built-in or imported).
    var plotStyleTable: PlotStyleTable {
        switch style {
        case "monochrome": return .monochrome
        case "grayscale": return .grayscale
        case "table": return styleTable ?? .color
        default: return .color
        }
    }

    @MainActor var paperSize: PaperSize { return PaperSize(rawValue: paper) ?? .a4 }
    @MainActor var scale: DrawingScale { return DrawingScale(paper: max(scalePaper, 1e-9), model: max(scaleModel, 1e-9)) }

    @MainActor var rasterFormat: RasterFormat? {
        switch device {
        case "png": return .png
        case "jpeg": return .jpeg
        case "tiff": return .tiff
        default: return nil
        }
    }
}

// MARK: - What gets plotted

/// Plot source: the model, or a layout with viewports into the model.
struct PlotSource {
    let model: [CADEntity]
    let layerManager: LayerManager
    /// mm per drawing unit (model units)
    let modelMMPerUnit: CGFloat
    /// drawing scale (for line types in the model)
    let drawingScale: DrawingScale
    let layout: DrawingLayout?
    /// The current view (Display area) in space coordinates.
    let displayRect: CGRect?
    let title: String

    /// mm of paper per coordinate unit of the plotted space at scale 1:1.
    var mmPerUnit: CGFloat { return layout == nil ? modelMMPerUnit : 1 }

    /// Plottable objects of the space (the model, or objects on paper).
    var spaceEntities: [CADEntity] {
        let entities = layout?.document.getAllEntities() ?? model
        return entities.filter { layerManager.isLayerPrintable($0.layer) }
    }

    /// Bounds of everything that will be plotted (for a layout also the viewport content within their rectangles).
    var extents: CGRect? {
        var box = CGRect.null
        for entity in spaceEntities { box = box.union(entity.boundingBox()) }
        if let layout = layout {
            for viewport in layout.viewports { box = box.union(viewport.rect) }
        }
        guard !box.isNull, box.width.isFinite, box.height.isFinite else { return nil }
        return box
    }
}

/// The computed page layout.
struct PlotPlan {
    /// Page in points (1/72").
    var pageSize: CGSize
    /// The area that is drawn into (points, origin bottom left).
    var printable: CGRect
    /// World → page (points).
    var transform: CGAffineTransform
    /// Page points per world unit.
    var pointsPerUnit: CGFloat
    /// Resulting scale (paper : model) – for information.
    var effectiveScale: DrawingScale
    /// Plotted area in world coordinates.
    var area: CGRect
    var landscape: Bool
    /// The drawing exceeds the printable area.
    var overflows: Bool
}

enum PlotRenderer {
    static let pointsPerMM: CGFloat = 72 / 25.4

    enum PlotError: LocalizedError {
        case nothingToPlot, noWindow, renderingFailed, tooLarge

        var errorDescription: String? {
            switch self {
            case .nothingToPlot: return "Nothing to plot – the area is empty, or all layers are hidden or not printable."
            case .noWindow: return "Pick the plot window first (Plot area › Window › Pick)."
            case .renderingFailed: return "The page could not be created."
            case .tooLarge: return "The image would be too large – choose a lower resolution or smaller paper."
            }
        }
    }

    /// Plotted area in world coordinates.
    static func area(_ settings: PlotSettings, _ source: PlotSource) -> CGRect? {
        switch settings.area {
        case "layout":
            return source.layout?.paperRect ?? source.extents
        case "display":
            return source.displayRect ?? source.extents
        case "window":
            guard let window = settings.window?.standardized, window.width > 0, window.height > 0 else { return nil }
            return window
        default:
            return source.extents
        }
    }

    static func makePlan(_ settings: PlotSettings, _ source: PlotSource) throws -> PlotPlan {
        guard let box = area(settings, source) else {
            throw settings.area == "window" ? PlotError.noWindow : PlotError.nothingToPlot
        }
        let isSheet = settings.area == "layout" && source.layout != nil
        let w = max(box.width, 1e-6), h = max(box.height, 1e-6)
        // points per world unit according to the scale
        let atScale = isSheet ? pointsPerMM : pointsPerMM * settings.scale.paper / settings.scale.model * source.mmPerUnit
        let margin = isSheet && !settings.fitToPaper ? 0 : max(0, settings.marginMM) * pointsPerMM

        // page
        var landscape: Bool
        switch settings.orientation {
        case 1: landscape = false
        case 2: landscape = true
        default: landscape = isSheet ? (source.layout?.landscape ?? (w > h)) : w > h
        }
        var pageSize: CGSize
        if let portrait = settings.paperSize.portraitMM {
            pageSize = CGSize(width: portrait.width * pointsPerMM, height: portrait.height * pointsPerMM)
            if landscape { pageSize = CGSize(width: pageSize.height, height: pageSize.width) }
        } else {
            // paper from the drawing: the whole area at scale + margins
            pageSize = CGSize(width: w * atScale + 2 * margin, height: h * atScale + 2 * margin)
            landscape = pageSize.width > pageSize.height
            let over = max(pageSize.width, pageSize.height) / 14_400      // PDF limit (200")
            if over > 1 { pageSize = CGSize(width: pageSize.width / over, height: pageSize.height / over) }
        }
        let inset = min(margin, min(pageSize.width, pageSize.height) / 3)
        let printable = CGRect(origin: .zero, size: pageSize).insetBy(dx: inset, dy: inset)

        var k = atScale
        if settings.fitToPaper || settings.paperSize == .extents && pageSize.width < w * atScale {
            k = min(printable.width / w, printable.height / h)
        }
        let transform: CGAffineTransform
        if settings.centered {
            transform = CGAffineTransform(translationX: printable.midX, y: printable.midY)
                .scaledBy(x: k, y: k).translatedBy(x: -box.midX, y: -box.midY)
        } else {
            transform = CGAffineTransform(translationX: printable.minX + settings.offsetX * pointsPerMM,
                                          y: printable.minY + settings.offsetY * pointsPerMM)
                .scaledBy(x: k, y: k).translatedBy(x: -box.minX, y: -box.minY)
        }
        let placed = box.applying(transform)
        let overflows = !printable.insetBy(dx: -0.5, dy: -0.5).contains(placed)
        // scale as “1 : N” (paper mm : model units converted to mm)
        let paperMMPerUnit = k / pointsPerMM
        let ratio = source.mmPerUnit / max(paperMMPerUnit, 1e-12)
        let effective = ratio >= 1 ? DrawingScale(paper: 1, model: ratio) : DrawingScale(paper: 1 / ratio, model: 1)
        return PlotPlan(pageSize: pageSize, printable: printable, transform: transform, pointsPerUnit: k,
                        effectiveScale: effective, area: box, landscape: landscape, overflows: overflows)
    }

    // MARK: Drawing

    /// Draws the page into a context whose coordinates are page points (origin bottom left).
    static func render(_ plan: PlotPlan, _ settings: PlotSettings, _ source: PlotSource,
                       in context: CGContext, background: Bool = true) {
        // screen-only helpers (frames of underlays) are left out
        RenderMode.plotting = true
        defer { RenderMode.plotting = false }
        let pageRect = CGRect(origin: .zero, size: plan.pageSize)
        if background && !(settings.transparent && (settings.rasterFormat?.supportsTransparency ?? false)) {
            context.setFillColor(NSColor.white.cgColor)
            context.fill(pageRect)
        }
        let layerManager = source.layerManager
        // line types: how many points make 1 mm of the pattern (in the model the pattern follows the drawing scale)
        let patternPointsPerMM = source.layout == nil
            ? plan.pointsPerUnit * source.drawingScale.factor / max(source.modelMMPerUnit, 1e-9)
            : plan.pointsPerUnit
        // plot style: output color and lineweight by the object's color
        let plotStyles = PlotStyleResolver(settings.plotStyleTable)
        func style(_ entity: CADEntity, patternPointsPerMM: CGFloat) -> StrokeStyle {
            let objectColor = layerManager.resolvedColor(for: entity)
            let plotStyle = plotStyles.style(for: objectColor)
            let color = PlotStyleResolver.plotColor(objectColor, style: plotStyle)
            let mm = plotStyle.lineweight ?? layerManager.lineWeight(for: entity)
            let width = settings.plotLineweights ? max(0.25, mm * pointsPerMM) : 0.3
            let type = layerManager.lineType(for: entity)
            let parts = type.strokeParts(pointsPerMM: patternPointsPerMM * (entity.lineTypeScale ?? 1), minimumPeriod: 1)
            return StrokeStyle(color: color, lineWidth: width, dash: parts.dash, marks: parts.marks)
        }

        context.saveGState()
        context.clip(to: plan.printable.insetBy(dx: -0.5, dy: -0.5))
        // objects inside blocks on their own layers: that layer's plot style; hidden or not plotted layers are left out
        BlockReference.innerStyle = { entity in
            guard layerManager.isLayerPrintable(entity.layer) else { return nil }
            return style(entity, patternPointsPerMM: patternPointsPerMM)
        }
        defer { BlockReference.innerStyle = nil }

        if let layout = source.layout {
            // viewports: the model scaled down into their rectangles (line types in paper mm)
            for viewport in layout.viewports where layerManager.isLayerVisible(viewport.layer) {
                ViewportDrawing.drawContents(of: viewport, model: source.model, layerManager: layerManager,
                                             mmPerUnit: source.modelMMPerUnit, paperTransform: plan.transform,
                                             in: context, printing: true) { style($0, patternPointsPerMM: plan.pointsPerUnit) }
            }
        }
        for entity in DrawOrder.sorted(source.spaceEntities) {
            entity.draw(in: context, transform: plan.transform, style: style(entity, patternPointsPerMM: patternPointsPerMM))
        }
        context.restoreGState()
    }

    // MARK: Outputs

    static func pdfData(_ settings: PlotSettings, _ source: PlotSource) throws -> Data {
        let plan = try makePlan(settings, source)
        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: plan.pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                      [kCGPDFContextTitle as String: source.title,
                                       kCGPDFContextCreator as String: "OhMyCAD"] as CFDictionary) else {
            throw PlotError.renderingFailed
        }
        context.beginPDFPage(nil)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        render(plan, settings, source, in: context)
        NSGraphicsContext.current = previous
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    /// Page image; resolution from `dpi` (a too large image is scaled down). Also returns the actual dpi.
    static func rasterData(_ settings: PlotSettings, _ source: PlotSource) throws -> (data: Data, size: CGSize, dpi: CGFloat) {
        guard let format = settings.rasterFormat else { throw PlotError.renderingFailed }
        let plan = try makePlan(settings, source)
        var dpi = max(30, min(settings.dpi, 1200))
        let maxPixels: CGFloat = 120_000_000
        var w = plan.pageSize.width / 72 * dpi, h = plan.pageSize.height / 72 * dpi
        if w * h > maxPixels {
            let shrink = sqrt(maxPixels / (w * h))
            dpi *= shrink
            w *= shrink
            h *= shrink
        }
        let pw = Int(w.rounded()), ph = Int(h.rounded())
        guard pw >= 1, ph >= 1, pw <= 40_000, ph <= 40_000 else { throw PlotError.tooLarge }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PlotError.tooLarge }
        context.setShouldAntialias(true)
        context.interpolationQuality = .high
        context.scaleBy(x: CGFloat(pw) / plan.pageSize.width, y: CGFloat(ph) / plan.pageSize.height)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        render(plan, settings, source, in: context)
        NSGraphicsContext.current = previous
        guard let image = context.makeImage() else { throw PlotError.renderingFailed }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: plan.pageSize.width, height: plan.pageSize.height)    // dpi into the metadata
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        let type: NSBitmapImageRep.FileType
        switch format {
        case .png: type = .png
        case .jpeg:
            type = .jpeg
            properties[.compressionFactor] = 0.92
        case .tiff:
            type = .tiff
            properties[.compressionMethod] = NSNumber(value: NSBitmapImageRep.TIFFCompression.lzw.rawValue)
        }
        guard let data = rep.representation(using: type, properties: properties) else { throw PlotError.renderingFailed }
        return (data, CGSize(width: pw, height: ph), dpi)
    }
}

// MARK: - Printer page

/// A view the size of the printer's printable area; draws the page shifted by the printer margins.
final class PlotPageView: NSView {
    private let plan: PlotPlan
    private let settings: PlotSettings
    private let source: PlotSource
    private let pageOrigin: CGPoint

    init(plan: PlotPlan, settings: PlotSettings, source: PlotSource, imageable: CGRect) {
        self.plan = plan
        self.settings = settings
        self.source = source
        self.pageOrigin = imageable.origin
        super.init(frame: NSRect(origin: .zero, size: imageable.size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: -pageOrigin.x, y: -pageOrigin.y)
        PlotRenderer.render(plan, settings, source, in: context, background: false)
        context.restoreGState()
    }
}

// MARK: - Preview

final class PlotPreviewView: NSView {
    var plan: PlotPlan?
    var settings = PlotSettings()
    var source: PlotSource?
    var message: String?
    /// The printer's printable area (page points) – drawn dashed.
    var hardwareArea: CGRect?

    override func draw(_ dirtyRect: NSRect) {
        Theme.previewBackground.setFill()
        bounds.fill()
        guard let plan = plan, let source = source, let context = NSGraphicsContext.current?.cgContext else {
            drawMessage(message ?? "No preview")
            return
        }
        let inset: CGFloat = 18
        let s = min((bounds.width - 2 * inset) / plan.pageSize.width, (bounds.height - 2 * inset) / plan.pageSize.height)
        guard s.isFinite, s > 0 else { return }
        let page = CGRect(x: bounds.midX - plan.pageSize.width * s / 2, y: bounds.midY - plan.pageSize.height * s / 2,
                          width: plan.pageSize.width * s, height: plan.pageSize.height * s)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(page)
        context.restoreGState()

        if settings.transparent && (settings.rasterFormat?.supportsTransparency ?? false) {
            drawChecker(page, in: context)
        }

        context.saveGState()
        context.clip(to: page)
        context.translateBy(x: page.minX, y: page.minY)
        context.scaleBy(x: s, y: s)
        PlotRenderer.render(plan, settings, source, in: context, background: false)
        // margins: printable area and printer area
        context.setLineWidth(0.6 / s)
        context.setLineDash(phase: 0, lengths: [4 / s, 3 / s])
        context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.6).cgColor)
        if plan.printable != CGRect(origin: .zero, size: plan.pageSize) { context.stroke(plan.printable) }
        if let hardware = hardwareArea {
            context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.5).cgColor)
            context.stroke(hardware)
        }
        context.restoreGState()

        if plan.overflows {
            drawBadge("The drawing goes past the printable area", color: .systemOrange)
        }
    }

    private func drawChecker(_ rect: CGRect, in context: CGContext) {
        context.saveGState()
        context.clip(to: rect)
        let size: CGFloat = 8
        context.setFillColor(Theme.previewChecker.cgColor)
        var y = rect.minY
        var row = 0
        while y < rect.maxY {
            var x = rect.minX + (row % 2 == 0 ? 0 : size)
            while x < rect.maxX {
                context.fill(CGRect(x: x, y: y, width: size, height: size))
                x += 2 * size
            }
            y += size
            row += 1
        }
        context.restoreGState()
    }

    private func drawMessage(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12),
                                                         .foregroundColor: Theme.textHint]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
                                withAttributes: attributes)
    }

    private func drawBadge(_ text: String, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium),
                                                         .foregroundColor: NSColor.black]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: bounds.midX - size.width / 2 - 8, y: 4, width: size.width + 16, height: size.height + 6)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 8, y: rect.minY + 3), withAttributes: attributes)
    }
}

// MARK: - Plot dialog

final class PlotDialog: NSObject, NSWindowDelegate {
    enum Result {
        case plot(PlotSettings)
        case pickWindow(PlotSettings)
        case cancel(PlotSettings)
    }

    private(set) var settings: PlotSettings
    private let source: PlotSource
    private var pageSetups: [PlotSettings]
    private let onSetupsChanged: ([PlotSettings]) -> Void
    private var completion: ((Result) -> Void)?

    let window: NSWindow
    private let preview = PlotPreviewView()
    private let infoLabel = NSTextField(wrappingLabelWithString: "")

    private let devicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let systemDialogBox = NSButton(checkboxWithTitle: "Show the macOS print dialog (copies, tray…)", target: nil, action: nil)
    private let setupPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let paperPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let orientationControl = NSSegmentedControl(labels: ["Auto", "Portrait", "Landscape"], trackingMode: .selectOne, target: nil, action: nil)
    private let areaPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let pickButton = NSButton(title: "Pick <", target: nil, action: nil)
    private let fitBox = NSButton(checkboxWithTitle: "Fit to paper", target: nil, action: nil)
    private let scaleCombo = NSComboBox()
    private let centerBox = NSButton(checkboxWithTitle: "Center the plot", target: nil, action: nil)
    private let offsetXField = NSTextField()
    private let offsetYField = NSTextField()
    private let marginField = NSTextField()
    private let stylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let lineweightBox = NSButton(checkboxWithTitle: "Plot lineweights", target: nil, action: nil)
    private let dpiPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let transparentBox = NSButton(checkboxWithTitle: "Transparent background", target: nil, action: nil)

    private static let dpiValues: [CGFloat] = [96, 150, 200, 300, 600]

    /// Entries of the style popup.
    private enum StyleItem {
        case builtIn(String)
        case table(Int)
        case separator
        case importFile
    }
    private static let builtInStyles: [(key: String, title: String)] = [
        ("color", "Color"), ("monochrome", "Monochrome (all black)"), ("grayscale", "Grayscale")
    ]
    private var styleItems: [StyleItem] = []
    /// Imported plot style tables known to this dialog (current settings, page setups, imported now).
    private var styleTables: [PlotStyleTable] = []
    private let printers = NSPrinter.printerNames
    private let papers = PaperSize.allCases

    init(settings: PlotSettings, source: PlotSource, pageSetups: [PlotSettings],
         onSetupsChanged: @escaping ([PlotSettings]) -> Void) {
        self.settings = settings
        self.source = source
        self.pageSetups = pageSetups
        self.onSetupsChanged = onSetupsChanged
        var tables: [PlotStyleTable] = []
        for table in ([settings.styleTable] + pageSetups.map { $0.styleTable }).compactMap({ $0 })
        where !tables.contains(where: { $0.name == table.name }) {
            tables.append(table)
        }
        styleTables = tables
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = source.layout.map { "Plot – \($0.name)" } ?? "Plot – Model"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 820, height: 560)
        window.delegate = self
        buildUI()
        load(settings)
    }

    func begin(for parent: NSWindow, completion: @escaping (Result) -> Void) {
        self.completion = completion
        parent.beginSheet(window) { _ in }
    }

    private func finish(_ result: Result) {
        guard let completion = completion else { return }
        self.completion = nil
        window.sheetParent?.endSheet(window)
        completion(result)
    }

    // MARK: Building

    private func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = NSFont.systemFont(ofSize: 12)
        field.alignment = .right
        return field
    }

    private func section(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text.uppercased())
        field.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func numberField(_ field: NSTextField, width: CGFloat = 64) {
        field.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        field.target = self
        field.action = #selector(controlChanged)
        field.cell?.sendsActionOnEndEditing = true
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
    }

    private func buildUI() {
        guard let content = window.contentView else { return }

        // device
        devicePopup.target = self
        devicePopup.action = #selector(controlChanged)
        systemDialogBox.target = self
        systemDialogBox.action = #selector(controlChanged)
        systemDialogBox.font = NSFont.systemFont(ofSize: 11)

        // named settings
        setupPopup.target = self
        setupPopup.action = #selector(setupChosen)
        let saveSetup = NSButton(title: "Save As…", target: self, action: #selector(saveSetup))
        let deleteSetup = NSButton(title: "Delete", target: self, action: #selector(deleteSetup))
        [saveSetup, deleteSetup].forEach { $0.controlSize = .small; $0.bezelStyle = .push }
        saveSetup.toolTip = "Save the current settings under a name (stored in the drawing)"
        let setupRow = NSStackView(views: [setupPopup, saveSetup, deleteSetup])
        setupRow.spacing = 6

        paperPopup.addItems(withTitles: papers.map { $0.title })
        paperPopup.target = self
        paperPopup.action = #selector(controlChanged)
        orientationControl.target = self
        orientationControl.action = #selector(controlChanged)
        orientationControl.controlSize = .small

        let areas = source.layout == nil
            ? ["Extents – the whole drawing", "Display – what you see now", "Window – a picked rectangle"]
            : ["Layout – the whole sheet", "Extents – everything on the sheet", "Display – what you see now", "Window – a picked rectangle"]
        areaPopup.addItems(withTitles: areas)
        areaPopup.target = self
        areaPopup.action = #selector(controlChanged)
        pickButton.target = self
        pickButton.action = #selector(pickWindow)
        pickButton.controlSize = .small
        pickButton.bezelStyle = .push
        pickButton.toolTip = "Close the dialog for a moment and click two corners in the drawing"
        let areaRow = NSStackView(views: [areaPopup, pickButton])
        areaRow.spacing = 6

        fitBox.target = self
        fitBox.action = #selector(controlChanged)
        scaleCombo.addItems(withObjectValues: DrawingScale.presets.map { $0.title })
        scaleCombo.target = self
        scaleCombo.action = #selector(controlChanged)
        scaleCombo.completes = false
        scaleCombo.widthAnchor.constraint(equalToConstant: 110).isActive = true
        scaleCombo.toolTip = "Paper : model, e.g. 1:50 (1 mm on paper = 50 mm in reality)"
        let scaleRow = NSStackView(views: [scaleCombo, fitBox])
        scaleRow.spacing = 10

        centerBox.target = self
        centerBox.action = #selector(controlChanged)
        numberField(offsetXField)
        numberField(offsetYField)
        let offsetRow = NSStackView(views: [centerBox, NSTextField(labelWithString: "X"), offsetXField,
                                            NSTextField(labelWithString: "Y"), offsetYField, NSTextField(labelWithString: "mm")])
        offsetRow.spacing = 5
        numberField(marginField)
        marginField.toolTip = "Distance of the plot from the paper edge"

        stylePopup.target = self
        stylePopup.action = #selector(styleChosen)
        stylePopup.toolTip = "How colors are printed: as they are, all black, in gray, or by an AutoCAD plot style table (.ctb). "
            + "Choose “Import .ctb…” to load a table; it is saved in the drawing"
        lineweightBox.target = self
        lineweightBox.action = #selector(controlChanged)
        lineweightBox.toolTip = "Off = all lines thin (0.1 mm)"

        dpiPopup.addItems(withTitles: PlotDialog.dpiValues.map { "\(Int($0)) dpi" })
        dpiPopup.target = self
        dpiPopup.action = #selector(controlChanged)
        transparentBox.target = self
        transparentBox.action = #selector(controlChanged)
        let rasterRow = NSStackView(views: [dpiPopup, transparentBox])
        rasterRow.spacing = 10

        let grid = NSGridView(views: [
            [section("Printer / Plotter"), NSGridCell.emptyContentView],
            [label("Device:"), devicePopup],
            [NSGridCell.emptyContentView, systemDialogBox],
            [label("Page setup:"), setupRow],
            [section("Paper"), NSGridCell.emptyContentView],
            [label("Paper:"), paperPopup],
            [label("Orientation:"), orientationControl],
            [label("Margin (mm):"), marginField],
            [section("What and How"), NSGridCell.emptyContentView],
            [label("Plot area:"), areaRow],
            [label("Scale:"), scaleRow],
            [label("Offset:"), offsetRow],
            [section("Look"), NSGridCell.emptyContentView],
            [label("Style:"), stylePopup],
            [NSGridCell.emptyContentView, lineweightBox],
            [label("Image:"), rasterRow]
        ])
        grid.rowSpacing = 7
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for index in [0, 4, 8, 12] {
            grid.row(at: index).topPadding = index == 0 ? 0 : 8
            grid.cell(atColumnIndex: 0, rowIndex: index).xPlacement = .leading
            grid.mergeCells(inHorizontalRange: NSRange(location: 0, length: 2), verticalRange: NSRange(location: index, length: 1))
        }

        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = .secondaryLabelColor

        let plotButton = NSButton(title: "Plot", target: self, action: #selector(plotClicked))
        plotButton.keyEquivalent = "\r"
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelButton.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [cancelButton, plotButton])
        buttons.spacing = 8

        [grid, preview, infoLabel, buttons].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            grid.widthAnchor.constraint(equalToConstant: 440),

            preview.leadingAnchor.constraint(equalTo: grid.trailingAnchor, constant: 16),
            preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            preview.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            preview.bottomAnchor.constraint(equalTo: infoLabel.topAnchor, constant: -8),

            infoLabel.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            infoLabel.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            infoLabel.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -10),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        ])
        preview.wantsLayer = true
        preview.layer?.cornerRadius = 6
    }

    // MARK: Settings ↔ controls

    private var deviceItems: [(device: String, printer: String?)] = []

    private func rebuildDevices() {
        devicePopup.removeAllItems()
        deviceItems = [("pdf", nil), ("png", nil), ("jpeg", nil), ("tiff", nil)]
        devicePopup.addItems(withTitles: ["PDF (vector)", "PNG image", "JPEG image", "TIFF image"])
        if !printers.isEmpty {
            devicePopup.menu?.addItem(.separator())
            deviceItems.append(("-", nil))
            for name in printers {
                devicePopup.addItem(withTitle: name)
                devicePopup.lastItem?.image = NSImage(systemSymbolName: "printer", accessibilityDescription: nil)
                deviceItems.append(("printer", name))
            }
        }
    }

    private func rebuildSetups() {
        setupPopup.removeAllItems()
        setupPopup.addItem(withTitle: "<None>")
        for setup in pageSetups { setupPopup.addItem(withTitle: setup.name ?? "?") }
        if let name = settings.name, let index = pageSetups.firstIndex(where: { $0.name == name }) {
            setupPopup.selectItem(at: index + 1)
        } else {
            setupPopup.selectItem(at: 0)
        }
    }

    private func rebuildStyles() {
        stylePopup.removeAllItems()
        styleItems = []
        for style in PlotDialog.builtInStyles {
            stylePopup.addItem(withTitle: style.title)
            styleItems.append(.builtIn(style.key))
        }
        if !styleTables.isEmpty {
            stylePopup.menu?.addItem(.separator())
            styleItems.append(.separator)
            for (index, table) in styleTables.enumerated() {
                stylePopup.addItem(withTitle: "\(table.name).ctb")
                styleItems.append(.table(index))
            }
        }
        stylePopup.menu?.addItem(.separator())
        styleItems.append(.separator)
        stylePopup.addItem(withTitle: "Import .ctb…")
        styleItems.append(.importFile)

        var selected = 0
        for (i, item) in styleItems.enumerated() {
            switch item {
            case .builtIn(let key) where key == settings.style:
                selected = i
            case .table(let index) where settings.style == "table" && styleTables[index].name == settings.styleTable?.name:
                selected = i
            default:
                break
            }
        }
        stylePopup.selectItem(at: selected)
    }

    private var areaKeys: [String] {
        return source.layout == nil ? ["extents", "display", "window"] : ["layout", "extents", "display", "window"]
    }

    private func load(_ s: PlotSettings) {
        settings = s
        rebuildDevices()
        if s.device == "printer", let name = s.printerName, let index = deviceItems.firstIndex(where: { $0.printer == name }) {
            devicePopup.selectItem(at: index)
        } else if s.device == "printer", let index = deviceItems.firstIndex(where: { $0.device == "printer" }) {
            devicePopup.selectItem(at: index)
        } else {
            devicePopup.selectItem(at: deviceItems.firstIndex { $0.device == s.device } ?? 0)
        }
        systemDialogBox.state = s.showSystemDialog ? .on : .off
        rebuildSetups()
        paperPopup.selectItem(at: papers.firstIndex(of: s.paperSize) ?? 1)
        orientationControl.selectedSegment = max(0, min(s.orientation, 2))
        marginField.stringValue = LineType.format(s.marginMM)
        areaPopup.selectItem(at: areaKeys.firstIndex(of: s.area) ?? 0)
        fitBox.state = s.fitToPaper ? .on : .off
        scaleCombo.stringValue = s.scale.title
        centerBox.state = s.centered ? .on : .off
        offsetXField.stringValue = LineType.format(s.offsetX)
        offsetYField.stringValue = LineType.format(s.offsetY)
        rebuildStyles()
        lineweightBox.state = s.plotLineweights ? .on : .off
        dpiPopup.selectItem(at: PlotDialog.dpiValues.firstIndex(of: s.dpi) ?? 3)
        transparentBox.state = s.transparent ? .on : .off
        refresh()
    }

    /// Reads the values from the controls.
    private func read() {
        var s = settings
        let fallback: (device: String, printer: String?) = ("pdf", nil)
        let device = deviceItems.indices.contains(devicePopup.indexOfSelectedItem) ? deviceItems[devicePopup.indexOfSelectedItem] : fallback
        s.device = device.device == "-" ? "pdf" : device.device
        s.printerName = device.printer
        s.showSystemDialog = systemDialogBox.state == .on
        s.paper = papers[max(0, paperPopup.indexOfSelectedItem)].rawValue
        s.orientation = orientationControl.selectedSegment
        s.marginMM = number(marginField) ?? s.marginMM
        s.area = areaKeys[max(0, min(areaPopup.indexOfSelectedItem, areaKeys.count - 1))]
        s.fitToPaper = fitBox.state == .on
        if let scale = PlotDialog.parseScale(scaleCombo.stringValue) {
            s.scalePaper = scale.paper
            s.scaleModel = scale.model
        }
        s.centered = centerBox.state == .on
        s.offsetX = number(offsetXField) ?? s.offsetX
        s.offsetY = number(offsetYField) ?? s.offsetY
        let styleIndex = stylePopup.indexOfSelectedItem
        switch styleItems.indices.contains(styleIndex) ? styleItems[styleIndex] : .builtIn("color") {
        case .builtIn(let key):
            s.style = key
            s.styleTable = nil
        case .table(let index):
            s.style = "table"
            s.styleTable = styleTables[index]
        case .separator, .importFile:
            break
        }
        s.plotLineweights = lineweightBox.state == .on
        s.dpi = PlotDialog.dpiValues[max(0, dpiPopup.indexOfSelectedItem)]
        s.transparent = transparentBox.state == .on
        if s != settings { s.name = nil }      // a change = it is no longer a saved setting
        settings = s
    }

    private func number(_ field: NSTextField) -> CGFloat? {
        return ExpressionEvaluator.evaluate(field.stringValue).map { CGFloat($0) }
    }

    /// „1:50“, „2:1“, „50“ (= 1:50).
    static func parseScale(_ text: String) -> DrawingScale? {
        let parts = text.replacingOccurrences(of: " ", with: "").split(separator: ":").map(String.init)
        if parts.count == 2, let a = ExpressionEvaluator.evaluate(parts[0]), let b = ExpressionEvaluator.evaluate(parts[1]), a > 0, b > 0 {
            return DrawingScale(paper: CGFloat(a), model: CGFloat(b))
        }
        if parts.count == 1, let b = ExpressionEvaluator.evaluate(parts[0]), b > 0 {
            return DrawingScale(paper: 1, model: CGFloat(b))
        }
        return nil
    }

    private func refresh() {
        let s = settings
        let isPrinter = s.device == "printer"
        let isRaster = s.rasterFormat != nil
        let isSheet = s.area == "layout"
        systemDialogBox.isEnabled = isPrinter
        pickButton.isEnabled = true
        scaleCombo.isEnabled = !s.fitToPaper && !isSheet
        offsetXField.isEnabled = !s.centered
        offsetYField.isEnabled = !s.centered
        dpiPopup.isEnabled = isRaster
        transparentBox.isEnabled = s.rasterFormat?.supportsTransparency ?? false
        marginField.isEnabled = !(isSheet && !s.fitToPaper)

        preview.settings = s
        preview.source = source
        preview.hardwareArea = nil
        do {
            let plan = try PlotRenderer.makePlan(s, source)
            preview.plan = plan
            preview.message = nil
            if isPrinter, let info = printInfo(for: s, plan: plan) {
                let imageable = info.imageablePageBounds
                if imageable.width > 0, imageable.width < plan.pageSize.width - 1 || imageable.height < plan.pageSize.height - 1 {
                    preview.hardwareArea = imageable
                }
            }
            infoLabel.stringValue = describe(plan, s)
        } catch {
            preview.plan = nil
            preview.message = error.localizedDescription
            infoLabel.stringValue = error.localizedDescription
        }
        preview.needsDisplay = true
    }

    private func describe(_ plan: PlotPlan, _ s: PlotSettings) -> String {
        let mm = { (points: CGFloat) in LineType.format((points / PlotRenderer.pointsPerMM * 10).rounded() / 10) }
        var parts: [String] = []
        parts.append("Paper \(mm(plan.pageSize.width)) × \(mm(plan.pageSize.height)) mm")
        let placed = plan.area.applying(plan.transform)
        parts.append("plot \(mm(placed.width)) × \(mm(placed.height)) mm")
        if s.area == "layout" && !s.fitToPaper {
            parts.append("sheet 1:1 (viewports keep their own scales)")
        } else {
            parts.append("scale \(plan.effectiveScale.title)\(s.fitToPaper ? " (fitted)" : "")")
        }
        if let format = s.rasterFormat {
            let w = Int((plan.pageSize.width / 72 * s.dpi).rounded()), h = Int((plan.pageSize.height / 72 * s.dpi).rounded())
            parts.append("\(format.title) \(w) × \(h) px")
        }
        if s.device == "printer" { parts.append("red dashes = what the printer can reach") }
        return parts.joined(separator: " · ")
    }

    /// Plot settings for the printer (paper, orientation, margins 0).
    func printInfo(for s: PlotSettings, plan: PlotPlan) -> NSPrintInfo? {
        guard s.device == "printer" else { return nil }
        return PlotDialog.makePrintInfo(s, plan: plan)
    }

    static func makePrintInfo(_ s: PlotSettings, plan: PlotPlan) -> NSPrintInfo {
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        if let name = s.printerName, let printer = NSPrinter(name: name) { info.printer = printer }
        info.orientation = plan.landscape ? .landscape : .portrait
        info.paperSize = plan.pageSize
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        info.horizontalPagination = .clip
        info.verticalPagination = .clip
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        return info
    }

    // MARK: Actions

    @objc private func controlChanged() {
        read()
        rebuildSetups()
        refresh()
    }

    @objc private func styleChosen() {
        let index = stylePopup.indexOfSelectedItem
        guard styleItems.indices.contains(index), case .importFile = styleItems[index] else {
            controlChanged()
            return
        }
        rebuildStyles()      // back to the current style until a file is read
        let panel = NSOpenPanel()
        panel.message = "Choose an AutoCAD color-dependent plot style table (.ctb) – it is saved in the drawing"
        panel.prompt = "Import"
        panel.allowedContentTypes = [UTType(filenameExtension: "ctb") ?? .data, UTType(filenameExtension: "stb") ?? .data]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let table = try PlotStyleTable.readCTB(data, name: url.deletingPathExtension().lastPathComponent)
                self.styleTables.removeAll { $0.name == table.name }
                self.styleTables.append(table)
                var s = self.settings
                s.style = "table"
                s.styleTable = table
                s.name = nil
                self.settings = s
                self.rebuildStyles()
                self.rebuildSetups()
                self.refresh()
            } catch {
                Log.error("Error Importing Plot Style Table: \(error.localizedDescription) [\(String(describing: error))]")
                let alert = NSAlert()
                alert.messageText = "Error Importing Plot Style Table"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .critical
                alert.beginSheetModal(for: self.window) { _ in }
            }
        }
    }

    @objc private func setupChosen() {
        let index = setupPopup.indexOfSelectedItem - 1
        guard pageSetups.indices.contains(index) else {
            settings.name = nil
            return
        }
        load(pageSetups[index])
    }

    @objc private func saveSetup() {
        read()
        let alert = NSAlert()
        alert.messageText = "Save Page Setup"
        alert.informativeText = "Name of the page setup (saved in the drawing):"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = settings.name ?? "\(settings.paperSize.shortTitle) \(settings.device == "printer" ? "print" : settings.device.uppercased())\(settings.fitToPaper ? "" : " \(settings.scale.title)")"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            var setup = self.settings
            setup.name = name
            setup.window = setup.area == "window" ? setup.window : nil
            self.pageSetups.removeAll { $0.name == name }
            self.pageSetups.append(setup)
            self.pageSetups.sort { ($0.name ?? "") < ($1.name ?? "") }
            self.settings.name = name
            self.onSetupsChanged(self.pageSetups)
            self.rebuildSetups()
        }
    }

    @objc private func deleteSetup() {
        let index = setupPopup.indexOfSelectedItem - 1
        guard pageSetups.indices.contains(index) else { NSSound.beep(); return }
        pageSetups.remove(at: index)
        settings.name = nil
        onSetupsChanged(pageSetups)
        rebuildSetups()
    }

    @objc private func pickWindow() {
        read()
        finish(.pickWindow(settings))
    }

    @objc private func plotClicked() {
        window.makeFirstResponder(nil)      // commit the field being edited
        read()
        do {
            _ = try PlotRenderer.makePlan(settings, source)
        } catch {
            NSSound.beep()
            refresh()
            return
        }
        finish(.plot(settings))
    }

    @objc private func cancelClicked() {
        read()
        finish(.cancel(settings))
    }
}
