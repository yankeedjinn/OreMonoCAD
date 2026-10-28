//
//  LayerColorSchemes.swift
//  OreMonoCAD
//
//  Color schemes for new layers: a new layer takes the next color of the drawing's scheme
//  that no layer has yet. The scheme is chosen with the palette button of the Layers panel
//  and saved in the drawing; Settings sets the scheme of a new drawing. Custom schemes take
//  the colors of the current layers and are kept in the app, so every drawing can use them.
//

import Cocoa

struct LayerColorScheme: Equatable {
    var name: String
    /// Colors as 0xRRGGBB, in the order new layers take them.
    var colors: [Int]
    var isCustom = false

    var nsColors: [NSColor] { return colors.map { Self.color($0) } }

    static let builtIn: [LayerColorScheme] = [
        // the colors of the logo (Splash.swift, LogoMark.faceColors) with a light gray and a teal
        LayerColorScheme(name: "OreMono", colors: [0x5FB4FF, 0xA98BFF, 0xFF7F9E, 0xFFD84D, 0xFFA95C, 0x63D995, 0xF2F2F2, 0x7FD8E0]),
        LayerColorScheme(name: "High Contrast", colors: [0xFF3B3B, 0xFFE600, 0x00E05A, 0x00D5FF, 0x2F6BFF, 0xFF3DF2, 0xFF8A00, 0xFFFFFF]),
        LayerColorScheme(name: "Grayscale", colors: [0xFFFFFF, 0xDCDCDC, 0xBDBDBD, 0xA0A0A0, 0x858585, 0x6E6E6E, 0xC8C8C8, 0x959595]),
        LayerColorScheme(name: "Earth", colors: [0xD98A64, 0xE3BE6E, 0xA3B87C, 0x6FAFA5, 0x8FA3C8, 0xBC93B4, 0xC9A88A, 0xE8DCC8]),
        // the colors new layers had before color schemes
        LayerColorScheme(name: "Classic", colors: [0xFF0000, 0xFFFF00, 0x00FF00, 0x00FFFF, 0x0000FF, 0xFF00FF])
    ]

    // MARK: Custom schemes and the default

    private static let customKey = "OreMonoCAD.customLayerColorSchemes"
    private static let defaultKey = "OreMonoCAD.defaultLayerColorScheme"

    static var custom: [LayerColorScheme] {
        get {
            let stored = UserDefaults.standard.array(forKey: customKey) as? [[String: Any]] ?? []
            return stored.compactMap { entry in
                guard let name = entry["name"] as? String, let colors = entry["colors"] as? [Int], !colors.isEmpty else { return nil }
                return LayerColorScheme(name: name, colors: colors, isCustom: true)
            }
        }
        set {
            UserDefaults.standard.set(newValue.map { ["name": $0.name, "colors": $0.colors] as [String: Any] }, forKey: customKey)
        }
    }

    static var all: [LayerColorScheme] { return builtIn + custom }

    static func named(_ name: String) -> LayerColorScheme? {
        return all.first { $0.name == name }
    }

    /// The scheme of a new drawing (Settings › Drawing).
    static var defaultScheme: LayerColorScheme {
        get { return UserDefaults.standard.string(forKey: defaultKey).flatMap { named($0) } ?? builtIn[0] }
        set { UserDefaults.standard.set(newValue.name, forKey: defaultKey) }
    }

    /// The scheme stored in a drawing. A custom scheme brings its colors along, so it works on another Mac too;
    /// a drawing without a scheme (older files, DXF) gets the default.
    static func stored(name: String?, colors: [NSColor]?) -> LayerColorScheme {
        guard let name = name else { return defaultScheme }
        if let scheme = builtIn.first(where: { $0.name == name }) { return scheme }
        if let colors = colors, !colors.isEmpty { return LayerColorScheme(name: name, colors: colors.map { hex($0) }, isCustom: true) }
        return named(name) ?? defaultScheme
    }

    // MARK: Colors

    /// The color for a new layer: the first color of the scheme no layer has yet; when all are used, they repeat.
    func nextColor(usedBy layers: [Layer]) -> NSColor {
        guard !colors.isEmpty else { return .white }
        let used = Set(layers.map { Self.hex($0.color) })
        if let free = colors.first(where: { !used.contains($0) }) { return Self.color(free) }
        return Self.color(colors[max(layers.count - 1, 0) % colors.count])
    }

    static func hex(_ color: NSColor) -> Int {
        let c = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? .white
        func byte(_ value: CGFloat) -> Int { return Int((min(max(value, 0), 1) * 255).rounded()) }
        return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
    }

    static func color(_ hex: Int) -> NSColor {
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                       blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }

    /// Most colors a custom scheme takes from the layers.
    static let maxCustomColors = 12

    /// A row of the scheme's colors for menus; `slots` keeps the rows of one menu equally wide, so the names line up.
    func strip(slots: Int) -> NSImage {
        let size: CGFloat = 12, gap: CGFloat = 2
        let width = CGFloat(max(slots, colors.count)) * (size + gap) - gap
        let colors = nsColors
        return NSImage(size: NSSize(width: max(width, size), height: size), flipped: false) { _ in
            for (i, color) in colors.enumerated() {
                let rect = NSRect(x: CGFloat(i) * (size + gap), y: 0, width: size, height: size).insetBy(dx: 0.5, dy: 0.5)
                let path = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
                color.setFill()
                path.fill()
                NSColor.black.withAlphaComponent(0.45).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            return true
        }
    }
}
