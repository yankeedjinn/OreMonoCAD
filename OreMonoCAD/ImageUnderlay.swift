//
//  ImageUnderlay.swift
//  OreMonoCAD
//
//  Image or PDF underlay: a scan, photo, map or PDF page placed into the drawing to trace over
//  (attached to the drawing). The file is embedded in the drawing – it is saved inside
//  the drawing file, so the drawing stays complete when it is moved or sent. It is not exported to DXF.
//

import Cocoa
import ImageIO

/// What is being drawn: frames of underlays (and other screen-only helpers) are not plotted.
enum RenderMode {
    /// True while a page is plotted, printed or exported (Plot.swift).
    static var plotting = false
}

/// A file chosen for attaching, before it is placed.
struct ImageSource {
    let data: Data
    let isPDF: Bool
    /// PDF page (1 = the first).
    let page: Int
    let fileName: String
    /// Size on paper in mm (from the PDF page, or from the pixels and their dpi).
    let paperSize: CGSize
    /// The scale the picture is drawn at – its size in the drawing = paper size × this scale.
    var scale: DrawingScale
    /// Shared by the placed image and its copies (the decoded picture is kept once).
    let contentID = UUID()

    /// Largest file that can be attached (MB) – it is stored in the drawing.
    static let maximumFileMB = 50

    /// Reads the file: a raster image (PNG, JPEG, TIFF, HEIC…) or a page of a PDF. nil = not readable.
    static func load(data: Data, fileName: String, page: Int, scale: DrawingScale) -> ImageSource? {
        if let document = ImageEntity.pdfDocument(data) {
            let number = min(max(page, 1), document.numberOfPages)
            guard let pdfPage = document.page(at: number) else { return nil }
            var box = pdfPage.getBoxRect(.cropBox).size
            if pdfPage.rotationAngle % 180 != 0 { box = CGSize(width: box.height, height: box.width) }
            let size = CGSize(width: box.width / 72 * 25.4, height: box.height / 72 * 25.4)
            return ImageSource(data: data, isPDF: true, page: number, fileName: fileName, paperSize: size, scale: scale)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              var width = (properties[kCGImagePropertyPixelWidth] as? NSNumber).map({ CGFloat($0.doubleValue) }),
              var height = (properties[kCGImagePropertyPixelHeight] as? NSNumber).map({ CGFloat($0.doubleValue) }),
              width > 0, height > 0 else { return nil }
        // photos turned by the camera (EXIF orientation 5–8) have width and height swapped
        if let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, orientation >= 5 {
            swap(&width, &height)
        }
        var dpi = (properties[kCGImagePropertyDPIWidth] as? NSNumber).map { CGFloat($0.doubleValue) } ?? 72
        if !(dpi > 1) { dpi = 72 }
        let size = CGSize(width: width / dpi * 25.4, height: height / dpi * 25.4)
        return ImageSource(data: data, isPDF: false, page: 1, fileName: fileName, paperSize: size, scale: scale)
    }

    /// Number of pages of a PDF (0 = not a PDF).
    static func pageCount(of data: Data) -> Int {
        return ImageEntity.pdfDocument(data)?.numberOfPages ?? 0
    }
}

final class ImageEntity: CADEntity {
    let id = UUID()
    var layer: String
    var color: NSColor?
    var lineWeight: CGFloat?
    var lineTypeScale: CGFloat?
    var drawOrder = 0
    var groupID: UUID?

    /// The file as it was attached.
    let data: Data
    let isPDF: Bool
    /// PDF page (1 = the first).
    let page: Int
    /// The original file name (for information).
    let fileName: String
    /// Corners in the drawing: lower left, lower right and upper left of the picture
    /// (any parallelogram – the picture can be moved, rotated, scaled and mirrored).
    var origin: CGPoint
    var xCorner: CGPoint
    var yCorner: CGPoint
    /// 1 = opaque, less = faded (easier to draw over).
    var opacity: CGFloat = 1
    /// The same content shares the decoded picture (copies, Undo).
    let contentID: UUID

    init(data: Data, isPDF: Bool, page: Int, fileName: String, origin: CGPoint, xCorner: CGPoint, yCorner: CGPoint,
         contentID: UUID = UUID(), layer: String = "0", color: NSColor? = nil) {
        self.data = data
        self.isPDF = isPDF
        self.page = page
        self.fileName = fileName
        self.origin = origin
        self.xCorner = xCorner
        self.yCorner = yCorner
        self.contentID = contentID
        self.layer = layer
        self.color = color
    }

    /// A new image from a chosen file, its lower-left corner at a point (the picture upright – north stays up).
    convenience init(source: ImageSource, at point: CGPoint, unitsPerPaperMM: CGFloat, layer: String) {
        let width = source.paperSize.width * unitsPerPaperMM, height = source.paperSize.height * unitsPerPaperMM
        self.init(data: source.data, isPDF: source.isPDF, page: source.page, fileName: source.fileName,
                  origin: point, xCorner: point + CGPoint(x: width, y: 0), yCorner: point + CGPoint(x: 0, y: height),
                  contentID: source.contentID, layer: layer)
    }

    var typeName: String { return isPDF ? "PDF Underlay" : "Image" }

    var infoText: String {
        let width = Geometry.distance(origin, xCorner), height = Geometry.distance(origin, yCorner)
        var text = String(format: "%@\n%@\n\nFile:     %@\nSize:     %.3f × %.3f\nOpacity:  %.0f %%",
                          typeName, commonInfo, fileName, width, height, opacity * 100)
        if isPDF { text += "\nPage:     \(page)" }
        if picture == nil { text += "\n⚠︎ The picture could not be read" }
        return text
    }

    /// The fourth corner (upper right).
    var oppositeCorner: CGPoint { return xCorner + yCorner - origin }
    var corners: [CGPoint] { return [origin, xCorner, oppositeCorner, yCorner] }

    // MARK: Picture

    /// Decoded pictures by content (dropped by the system when memory is short – then decoded again).
    private static let pictures = NSCache<NSUUID, CGImage>()
    /// Longest side of a decoded picture in pixels (a PDF page is rendered at this size).
    static let maximumPixels: CGFloat = 5000

    var picture: CGImage? {
        let key = contentID as NSUUID
        if let cached = ImageEntity.pictures.object(forKey: key) { return cached }
        guard let image = isPDF ? ImageEntity.renderPDF(data, page: page) : ImageEntity.decode(data) else { return nil }
        ImageEntity.pictures.setObject(image, forKey: key)
        return image
    }

    static func pdfDocument(_ data: Data) -> CGPDFDocument? {
        guard data.starts(with: Array("%PDF".utf8)) || data.prefix(1024).range(of: Data("%PDF".utf8)) != nil,
              let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider),
              document.numberOfPages > 0 else { return nil }
        return document
    }

    /// A raster file turned upright (EXIF orientation) and limited in size.
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: Int(maximumPixels)]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// A PDF page as a picture on white paper.
    private static func renderPDF(_ data: Data, page number: Int) -> CGImage? {
        guard let page = pdfDocument(data)?.page(at: number) else { return nil }
        var size = page.getBoxRect(.cropBox).size
        if page.rotationAngle % 180 != 0 { size = CGSize(width: size.height, height: size.width) }
        guard size.width > 0, size.height > 0 else { return nil }
        let k = maximumPixels / max(size.width, size.height)
        let width = max(1, Int((size.width * k).rounded())), height = max(1, Int((size.height * k).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let target = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(target)
        context.interpolationQuality = .high
        context.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return context.makeImage()
    }

    // MARK: CADEntity

    func makePath() -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: corners)
        path.closeSubpath()
        return path
    }

    func draw(in context: CGContext, transform: CGAffineTransform, style: StrokeStyle) {
        let o = origin.applying(transform), x = xCorner.applying(transform), y = yCorner.applying(transform)
        let screenBox = corners.reduce(CGRect.null) { $0.union(CGRect(origin: $1.applying(transform), size: .zero)) }
        guard DrawingSafety.isDrawable(screenBox) else { return }
        if let picture = picture {
            // the unit square of the picture → the parallelogram on screen / paper
            let frame = CGAffineTransform(a: x.x - o.x, b: x.y - o.y, c: y.x - o.x, d: y.y - o.y, tx: o.x, ty: o.y)
            context.saveGState()
            context.concatenate(frame)
            context.setAlpha(opacity)
            context.interpolationQuality = .high
            context.draw(picture, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            context.restoreGState()
        }
        // the frame only on screen (a picture that can't be read keeps its frame in print too)
        if !RenderMode.plotting || picture == nil {
            strokeWorldPath(makePath(), in: context, transform: transform, style: style)
        }
    }

    func boundingBox() -> CGRect {
        return corners.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// 0 inside the picture, otherwise the distance to its frame.
    func distance(to point: CGPoint) -> CGFloat {
        let u = xCorner - origin, v = yCorner - origin
        let det = u.x * v.y - u.y * v.x
        if abs(det) > 1e-12 {
            let d = point - origin
            let s = (d.x * v.y - d.y * v.x) / det
            let t = (u.x * d.y - u.y * d.x) / det
            if s >= 0 && s <= 1 && t >= 0 && t <= 1 { return 0 }
        }
        let c = corners
        return (0..<4).map { i -> CGFloat in
            let a = c[i], b = c[(i + 1) % 4]
            let t = max(0, min(1, Geometry.projectionParameter(of: point, ontoSegmentFrom: a, to: b)))
            return Geometry.distance(point, Geometry.lerp(a, b, t))
        }.min() ?? .infinity
    }

    func snapPoints() -> [SnapPoint] {
        var result = corners.map { SnapPoint(point: $0, type: .endpoint) }
        result.append(SnapPoint(point: Geometry.midpoint(origin, oppositeCorner), type: .center))
        return result
    }

    func applyTransform(_ transform: CGAffineTransform) {
        origin = origin.applying(transform)
        xCorner = xCorner.applying(transform)
        yCorner = yCorner.applying(transform)
    }

    func clone() -> CADEntity {
        let copy = ImageEntity(data: data, isPDF: isPDF, page: page, fileName: fileName, origin: origin,
                               xCorner: xCorner, yCorner: yCorner, contentID: contentID, layer: layer, color: color)
        copy.opacity = opacity
        return copyStyle(to: copy)
    }

    /// Not a cutting edge or a boundary – lines are drawn over it.
    func primitives() -> [Primitive] { return [] }
}
