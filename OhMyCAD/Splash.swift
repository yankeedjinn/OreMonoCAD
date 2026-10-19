//
//  Splash.swift
//  OhMyCAD
//
//  The OhMyCAD logo (variant 07d “Intersections – colors only”) drawn as vectors
//  and the start screen shown when the app launches.
//

import Cocoa

// MARK: - Logo

enum LogoMark {
    /// Colors of the six areas (palette B “Vivid” – more saturated and contrasting than the original sorbet), in order: left half of O, right part of O by the vertical,
    /// part of O inside V, wedge below V, part of the half-circle inside V, part of the half-circle by the vertical edge.
    static let faceColors: [NSColor] = [0x5FB4FF, 0xA98BFF, 0xFF7F9E, 0xFFD84D, 0xFFA95C, 0x63D995].map { LogoMark.color($0) }

    /// Icon background.
    static let ground = LogoMark.color(0x2A2A33)

    /// Logo bounds in design coordinates (y axis down, as in the SVG design).
    static let designBounds = CGRect(x: 82, y: 140, width: 348, height: 232)

    private static func color(_ hex: Int) -> NSColor {
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                       green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Logo areas in design coordinates. Construction: circle O (center 198,256), half-circle
    /// (center 430,256), both with radius 116; V from (198,140) via (314,372) to (430,140).
    static func facePaths() -> [CGPath] {
        let r: CGFloat = 116
        let o = CGPoint(x: 198, y: 256), h = CGPoint(x: 430, y: 256)
        let topO = CGPoint(x: 198, y: 140), bottomO = CGPoint(x: 198, y: 372)
        let topH = CGPoint(x: 430, y: 140), bottomH = CGPoint(x: 430, y: 372)
        let vBottom = CGPoint(x: 314, y: 372)
        // intersections of the V arms with the circles (t = 0.8 along the arm)
        let p1 = CGPoint(x: 290.8, y: 325.6), p2 = CGPoint(x: 337.2, y: 325.6)
        let a1: CGFloat = atan2(69.6, 92.8)          // angle of point p1 from the center of O
        let a2: CGFloat = atan2(69.6, -92.8)         // angle of point p2 from the center of the half-circle
        let up = -CGFloat.pi / 2, down = CGFloat.pi / 2

        func face(_ build: (CGMutablePath) -> Void) -> CGPath {
            let path = CGMutablePath()
            build(path)
            path.closeSubpath()
            return path
        }

        return [
            face { $0.move(to: topO); $0.addArc(center: o, radius: r, startAngle: up, endAngle: down, clockwise: true) },
            face { $0.move(to: topO); $0.addLine(to: bottomO)
                   $0.addArc(center: o, radius: r, startAngle: down, endAngle: a1, clockwise: true) },
            face { $0.move(to: topO); $0.addLine(to: p1)
                   $0.addArc(center: o, radius: r, startAngle: a1, endAngle: up, clockwise: true) },
            face { $0.move(to: p1); $0.addLine(to: vBottom); $0.addLine(to: p2)
                   $0.addArc(center: h, radius: r, startAngle: a2, endAngle: .pi, clockwise: false)
                   $0.addArc(center: o, radius: r, startAngle: 0, endAngle: a1, clockwise: false) },
            face { $0.move(to: topH); $0.addLine(to: p2)
                   $0.addArc(center: h, radius: r, startAngle: a2, endAngle: up, clockwise: false) },
            face { $0.move(to: topH); $0.addLine(to: bottomH)
                   $0.addArc(center: h, radius: r, startAngle: down, endAngle: a2, clockwise: false) }
        ]
    }

    /// Draws the logo into a rectangle (coordinates with y axis up), keeping the aspect ratio.
    static func draw(in context: CGContext, fitting rect: CGRect) {
        let b = designBounds
        let s = min(rect.width / b.width, rect.height / b.height)
        let w = b.width * s, h = b.height * s
        let ox = rect.midX - w / 2, oy = rect.midY - h / 2
        // design (y down) → drawing (y up)
        var transform = CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: ox - b.minX * s, ty: oy + h + b.minY * s)
        context.saveGState()
        context.setLineJoin(.round)
        context.setLineWidth(0.6)        // covers hairline gaps between adjacent areas
        for (path, color) in zip(facePaths(), faceColors) {
            guard let placed = path.copy(using: &transform) else { continue }
            context.addPath(placed)
            context.setFillColor(color.cgColor)
            context.setStrokeColor(color.cgColor)
            context.drawPath(using: .fillStroke)
        }
        context.restoreGState()
    }
}

extension LogoMark {
    /// App icon drawn as vectors (macOS icon grid: background 824/1024, corner 185, subtle shadow).
    /// Set as the Dock icon right at launch – even when debugging from Xcode, when macOS
    /// still remembers the old icon from its cache.
    static func appIconImage(pixels: Int = 1024) -> NSImage {
        let side = CGFloat(pixels)
        let image = NSImage(size: NSSize(width: side, height: side))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        let k = side / 1024

        // background with shadow
        let tile = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 20 * k,
                          color: NSColor(white: 0, alpha: 0.3).cgColor)
        ground.setFill()
        NSBezierPath(roundedRect: tile, xRadius: 185 * k, yRadius: 185 * k).fill()
        context.restoreGState()

        // logo – same ratio to the background as in the design (background 464, logo 348 × 232)
        let scale = 824 * k / 464
        let markSize = CGSize(width: designBounds.width * scale, height: designBounds.height * scale)
        let markRect = CGRect(x: tile.midX - markSize.width / 2, y: tile.midY - markSize.height / 2,
                              width: markSize.width, height: markSize.height)
        draw(in: context, fitting: markRect)

        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        image.addRepresentation(rep)
        return image
    }
}

/// The logo as a view – optionally on a background shaped like the app icon.
final class LogoMarkView: NSView {
    var showsTile = true { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        var markRect = bounds
        if showsTile {
            let side = min(bounds.width, bounds.height)
            let tile = CGRect(x: bounds.midX - side / 2, y: bounds.midY - side / 2, width: side, height: side)
            let shape = NSBezierPath(roundedRect: tile, xRadius: side * 0.225, yRadius: side * 0.225)
            LogoMark.ground.setFill()
            shape.fill()
            // logo-to-background ratio as in the app icon (logo width ≈ 75 % of the background)
            markRect = tile.insetBy(dx: side * 0.125, dy: side * 0.125)
        }
        LogoMark.draw(in: context, fitting: markRect)
    }
}

// MARK: - Start screen

private final class SplashPanel: NSPanel {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    override var canBecomeKey: Bool { return true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Start screen at launch: logo, name, version, quick start and a New / Open choice.
final class SplashController: NSObject {
    var onNewDrawing: (() -> Void)?
    var onOpenFile: (() -> Void)?
    var onOpenRecent: ((URL) -> Void)?
    /// Recent files for the Open Recent button.
    var recentURLs: [URL] = []

    private var panel: SplashPanel?
    private weak var parentWindow: NSWindow?

    func show(over window: NSWindow?) {
        let size = NSSize(width: 760, height: 420)
        let panel = SplashPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                                backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.onCancel = { [weak self] in self?.dismiss(then: self?.onNewDrawing) }

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = Theme.splashBackground.cgColor
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = Theme.splashBorder.cgColor
        panel.contentView = content

        // app icon
        let logo = LogoMarkView(frame: NSRect(x: 48, y: 90, width: 240, height: 240))
        logo.setAccessibilityLabel("OhMyCAD")
        content.addSubview(logo)

        // name: “OhMy” light, “CAD” bold
        let name = NSMutableAttributedString(string: "OhMy", attributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .light), .foregroundColor: Theme.splashTitle])
        name.append(NSAttributedString(string: "CAD", attributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .bold), .foregroundColor: Theme.splashTitle]))
        let title = NSTextField(labelWithAttributedString: name)
        title.frame = NSRect(x: 330, y: 300, width: 350, height: 58)
        content.addSubview(title)

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 12)
        versionLabel.textColor = Theme.splashVersion
        versionLabel.frame = NSRect(x: 333, y: 278, width: 300, height: 18)
        content.addSubview(versionLabel)

        let tips = NSTextField(wrappingLabelWithString: """
        A drawing board for 2D plans and details.
        Opens and saves DXF and native files.
        Hover over any tool to reveal its secrets.

        Vibecoded by Yankee Djinn.

        Use at your own risk.
        """)
        tips.font = NSFont.systemFont(ofSize: 12)
        tips.textColor = Theme.splashText
        tips.frame = NSRect(x: 333, y: 104, width: 360, height: 150)
        content.addSubview(tips)

        let open = NSButton(title: "Open File…", target: self, action: #selector(openClicked))
        open.bezelStyle = .push
        open.controlSize = .large
        open.sizeToFit()
        open.frame.origin = CGPoint(x: 330, y: 36)
        content.addSubview(open)

        // Open Recent – a drop-down list of recently opened drawings
        let recent = NSPopUpButton(frame: .zero, pullsDown: true)
        recent.controlSize = .large
        recent.addItem(withTitle: "Open Recent")
        if recentURLs.isEmpty {
            recent.addItem(withTitle: "No Recent Files")
            recent.lastItem?.isEnabled = false
            recent.autoenablesItems = false
        }
        for url in recentURLs.prefix(12) {
            recent.addItem(withTitle: url.lastPathComponent)
            guard let item = recent.lastItem else { continue }
            item.representedObject = url
            item.toolTip = url.path
            item.target = self
            item.action = #selector(recentChosen(_:))
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        recent.sizeToFit()
        recent.frame.size.width = max(recent.frame.width, 140)
        recent.frame.origin = CGPoint(x: open.frame.maxX + 10, y: 36 + (open.frame.height - recent.frame.height) / 2)
        recent.toolTip = recentURLs.isEmpty ? "No drawings opened yet" : "Open one of the recently used drawings"
        content.addSubview(recent)

        let new = NSButton(title: "New Drawing", target: self, action: #selector(newClicked))
        new.bezelStyle = .push
        new.controlSize = .large
        new.keyEquivalent = "\r"
        new.sizeToFit()
        new.frame.origin = CGPoint(x: size.width - 40 - new.frame.width, y: 36)
        content.addSubview(new)

        // centered over the main window
        if let window = window {
            let frame = window.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
            window.addChildWindow(panel, ordered: .above)
            parentWindow = window
        } else {
            panel.center()
        }

        self.panel = panel
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 1
        }
    }

    @objc private func newClicked() { dismiss(then: onNewDrawing) }
    @objc private func openClicked() { dismiss(then: onOpenFile) }

    @objc private func recentChosen(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let open = onOpenRecent
        dismiss(then: { open?(url) })
    }

    private func dismiss(then action: (() -> Void)?) {
        guard let panel = panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
            self?.parentWindow?.makeKeyAndOrderFront(nil)
            action?()
        })
    }
}
