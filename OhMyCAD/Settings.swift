//
//  Settings.swift
//  OhMyCAD
//
//  App settings (OhMyCAD › Settings…, ⌘,): global options that apply to all
//  drawings – unlike Format › Document Settings (units, grid of a specific drawing).
//

import Cocoa

// MARK: - Stored options

enum AppSettings {
    private static let defaults = UserDefaults.standard

    private static func bool(_ key: String, _ fallback: Bool) -> Bool {
        return defaults.object(forKey: key) as? Bool ?? fallback
    }

    /// Branded start screen at launch.
    static var showWelcomeScreen: Bool {
        get { return bool("OhMyCAD.showWelcome", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.showWelcome") }
    }

    /// Keep the value box at the cursor always visible (false = it appears once you start typing a number).
    static var valueBoxAlways: Bool {
        get { return bool("OhMyCAD.valueBoxAlways", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.valueBoxAlways") }
    }

    /// Enter / right click while idle repeats the last tool.
    static var repeatLastTool: Bool {
        get { return bool("OhMyCAD.repeatLastTool", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.repeatLastTool") }
    }

    /// Anti-aliasing of lines and text (default state after launch).
    static var smoothLines: Bool {
        get { return bool("OhMyCAD.smoothLines", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.smoothLines") }
    }

    /// Ask when finishing a polyline / spline whether to close it (default state).
    static var askToClose: Bool {
        get { return bool("OhMyCAD.askToClose", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.askToClose") }
    }

    /// Last Show Grid / Show Axes state – used by new drawings and by drawings that do not store it.
    static var showGrid: Bool {
        get { return bool("OhMyCAD.showGrid", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.showGrid") }
    }
    static var showAxes: Bool {
        get { return bool("OhMyCAD.showAxes", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.showAxes") }
    }

    /// Units of a new drawing.
    static var newDrawingUnits: DrawingUnits {
        get { return (defaults.string(forKey: "OhMyCAD.newUnits")).flatMap { DrawingUnits(rawValue: $0) } ?? .mm }
        set { defaults.set(newValue.rawValue, forKey: "OhMyCAD.newUnits") }
    }

    // MARK: Cursor (like CURSORSIZE / PICKBOX in AutoCAD)

    /// Cursor on the drawing area: false = system crosshair, true = CAD crosshair across the area.
    static var cadCrosshair: Bool {
        get { return bool("OhMyCAD.cadCrosshair", false) }
        set { defaults.set(newValue, forKey: "OhMyCAD.cadCrosshair") }
    }

    /// Length of the crosshair arms in % of the area size (1–100, 100 = across the whole area).
    static var crosshairSize: CGFloat {
        get { return CGFloat(defaults.object(forKey: "OhMyCAD.crosshairSize") as? Double ?? 5) }
        set { defaults.set(Double(max(1, min(newValue, 100))), forKey: "OhMyCAD.crosshairSize") }
    }

    /// Size of the pick box in the middle (px); also controls the click selection tolerance.
    static var pickboxSize: CGFloat {
        get { return CGFloat(defaults.object(forKey: "OhMyCAD.pickboxSize") as? Double ?? 10) }
        set { defaults.set(Double(max(0, min(newValue, 40))), forKey: "OhMyCAD.pickboxSize") }
    }

    static var showPickbox: Bool {
        get { return bool("OhMyCAD.showPickbox", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.showPickbox") }
    }

    /// Crosshair color.
    static var crosshairColor: NSColor {
        get {
            guard let c = defaults.array(forKey: "OhMyCAD.crosshairColor") as? [Double], c.count == 4 else {
                return NSColor(white: 0.92, alpha: 1)
            }
            return NSColor(srgbRed: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]), alpha: CGFloat(c[3]))
        }
        set {
            let c = newValue.usingColorSpace(.sRGB) ?? newValue
            defaults.set([Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)],
                         forKey: "OhMyCAD.crosshairColor")
        }
    }

    /// Crosshair line thickness (px).
    static var crosshairWidth: CGFloat {
        get { return CGFloat(defaults.object(forKey: "OhMyCAD.crosshairWidth") as? Double ?? 1) }
        set { defaults.set(Double(max(0.5, min(newValue, 4))), forKey: "OhMyCAD.crosshairWidth") }
    }

    // MARK: Dimension style

    /// Terminator of new dimensions.
    static var dimArrowStyle: DimArrowStyle {
        get { return defaults.string(forKey: "OhMyCAD.dimArrowStyle").flatMap { DimArrowStyle(rawValue: $0) } ?? .arrow }
        set { defaults.set(newValue.rawValue, forKey: "OhMyCAD.dimArrowStyle") }
    }

    /// Dimension text height on paper (mm).
    static var dimTextHeightMM: CGFloat {
        get { return CGFloat(defaults.object(forKey: "OhMyCAD.dimTextHeight") as? Double ?? 2.5) }
        set { defaults.set(Double(max(0.5, min(newValue, 20))), forKey: "OhMyCAD.dimTextHeight") }
    }

    /// Terminator size on paper (mm).
    static var dimArrowSizeMM: CGFloat {
        get { return CGFloat(defaults.object(forKey: "OhMyCAD.dimArrowSize") as? Double ?? 2.5) }
        set { defaults.set(Double(max(0.2, min(newValue, 20))), forKey: "OhMyCAD.dimArrowSize") }
    }

    /// Number of decimal places of new dimensions.
    static var dimDecimals: Int {
        get { return defaults.object(forKey: "OhMyCAD.dimDecimals") as? Int ?? 2 }
        set { defaults.set(max(0, min(newValue, 6)), forKey: "OhMyCAD.dimDecimals") }
    }

    // MARK: Mouse and zoom

    /// Reversed scroll-wheel zoom direction.
    static var zoomWheelReversed: Bool {
        get { return bool("OhMyCAD.zoomWheelReversed", false) }
        set { defaults.set(newValue, forKey: "OhMyCAD.zoomWheelReversed") }
    }

    /// Zoom speed (1 = default, 0.25–4).
    static var zoomSpeed: CGFloat {
        get { return CGFloat(defaults.object(forKey: "OhMyCAD.zoomSpeed") as? Double ?? 1) }
        set { defaults.set(Double(max(0.25, min(newValue, 4))), forKey: "OhMyCAD.zoomSpeed") }
    }

    /// Zoom toward the cursor (otherwise toward the center of the area).
    static var zoomToCursor: Bool {
        get { return bool("OhMyCAD.zoomToCursor", true) }
        set { defaults.set(newValue, forKey: "OhMyCAD.zoomToCursor") }
    }

    /// Trackpad / Magic Mouse: two-finger scrolling zooms (otherwise it pans the view).
    static var trackpadScrollZooms: Bool {
        get { return bool("OhMyCAD.trackpadScrollZooms", false) }
        set { defaults.set(newValue, forKey: "OhMyCAD.trackpadScrollZooms") }
    }

    /// How long the right button must be held in the drawing for the context menu, in seconds (0.25–1.5, default 0.4).
    /// The lower limit keeps an ordinary right click (finish / repeat a command) from opening the menu.
    static var contextMenuHoldTime: Double {
        get { return defaults.object(forKey: "OhMyCAD.contextMenuHoldTime") as? Double ?? 0.4 }
        set { defaults.set(max(0.25, min(newValue, 1.5)), forKey: "OhMyCAD.contextMenuHoldTime") }
    }

    // MARK: Object snap (SNAP)

    /// After the set of snap points changes (SNAP popup, Settings, menu View › Drawing Aids › Snap Points).
    static let snapsDidChange = Notification.Name("OhMyCADSnapsDidChange")

    /// Enabled kinds of snap points.
    /// What the Match Properties tool transfers (default = everything).
    static var matchProperties: Set<MatchProperty> {
        get {
            guard let names = defaults.stringArray(forKey: "OhMyCAD.matchProperties") else { return Set(MatchProperty.allCases) }
            return Set(names.compactMap { MatchProperty(rawValue: $0) })
        }
        set { defaults.set(MatchProperty.allCases.filter { newValue.contains($0) }.map { $0.rawValue }, forKey: "OhMyCAD.matchProperties") }
    }

    static var enabledSnaps: Set<SnapType> {
        get {
            guard let names = defaults.stringArray(forKey: "OhMyCAD.enabledSnaps") else { return SnapType.defaultSet }
            return Set(names.compactMap { SnapType(rawValue: $0) })
        }
        set {
            defaults.set(SnapType.allCases.filter { newValue.contains($0) }.map { $0.rawValue }, forKey: "OhMyCAD.enabledSnaps")
            NotificationCenter.default.post(name: snapsDidChange, object: nil)
        }
    }

    /// Delete custom values (grid, angles, scales) and the saved panel layout.
    static func resetRememberedValues() {
        for key in ["OhMyCAD.customGridSizes", "OhMyCAD.customPolarSteps", "OhMyCAD.trayWidth", "OhMyCAD.traySplit",
                    "OhMyCAD.pdfExport", "OhMyCAD.rasterExport"] {
            defaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Settings window

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// A change that should take effect immediately in the open window (anti-aliasing, text style…).
    var onChange: (() -> Void)?
    /// Editing the default text style (opens the Text Style dialog).
    var onEditTextStyle: (() -> Void)?
    /// Description of the current text style for the pane.
    var textStyleSummary: (() -> String)?
    /// Editing the default dimension style (opens the Dimension Style dialog).
    var onEditDimensionStyle: (() -> Void)?

    private let tabView = NSTabView()
    private var shortcutsPane: ShortcutsPane?
    private var snapPane: SnapSettingsPanel?
    private let textStyleLabel = NSTextField(labelWithString: "")
    private let dimStyleLabel = NSTextField(labelWithString: "")
    /// The value box option – also changed by a key (⌥6, F12), so it is refreshed when shown.
    private var valueBoxCheck: NSButton?
    private var actions: [MenuAction] = []

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        refresh()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        valueBoxCheck?.state = AppSettings.valueBoxAlways ? .on : .off
        textStyleLabel.stringValue = textStyleSummary?() ?? ""
        dimStyleLabel.stringValue = "\(AppSettings.dimArrowStyle.title) · text \(LineType.format(AppSettings.dimTextHeightMM)) mm"
            + " · ends \(LineType.format(AppSettings.dimArrowSizeMM)) mm on paper · \(AppSettings.dimDecimals) decimal\(AppSettings.dimDecimals == 1 ? "" : "s")"
        shortcutsPane?.reload()
        snapPane?.reload()
    }

    // MARK: Building

    private func check(_ title: String, _ value: Bool, tip: String, _ apply: @escaping (Bool) -> Void) -> NSButton {
        let box = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        box.state = value ? .on : .off
        box.toolTip = tip
        let action = MenuAction { [weak self, weak box] in
            apply(box?.state == .on)
            self?.onChange?()
        }
        actions.append(action)
        box.target = action
        box.action = #selector(MenuAction.run(_:))
        return box
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = NSFont.systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 520
        return field
    }

    /// A horizontal divider between two parts of one tab.
    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 520).isActive = true
        return box
    }

    private func pane(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        return stack
    }

    private func build() {
        guard let content = window?.contentView else { return }

        // General
        let valueBoxCheck = check("Value box always visible", AppSettings.valueBoxAlways,
                                  tip: "Off: the box with length, angle, radius… appears only when you start typing a number. Typing values always works. Also ⌥6 or F12") { AppSettings.valueBoxAlways = $0 }
        self.valueBoxCheck = valueBoxCheck
        let general = pane([
            check("Show the welcome screen at launch", AppSettings.showWelcomeScreen,
                  tip: "The window with New Drawing / Open File… / Open Recent when OhMyCAD starts") { AppSettings.showWelcomeScreen = $0 },
            check("Repeat the last tool with ↩, Space or right-click", AppSettings.repeatLastTool,
                  tip: "Only when the Select tool is active and nothing is in progress") { AppSettings.repeatLastTool = $0 },
            check("Smooth lines and text (antialiasing)", AppSettings.smoothLines,
                  tip: "Also in View › Smooth Lines (Antialiasing)") { AppSettings.smoothLines = $0 },
            check("Ask to close polylines and splines", AppSettings.askToClose,
                  tip: "Default for the CLS button (⌥4)") { AppSettings.askToClose = $0 },
            valueBoxCheck,
            note("These settings apply to the whole app and all drawings. Units, grid and polar angles of one drawing are in Format › Document Settings… (⌥⌘,).")
        ])

        // Drawing
        let unitsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        unitsPopup.addItems(withTitles: DrawingUnits.allCases.map { $0.title })
        unitsPopup.selectItem(at: DrawingUnits.allCases.firstIndex(of: AppSettings.newDrawingUnits) ?? 0)
        let unitsAction = MenuAction { [weak unitsPopup] in
            guard let popup = unitsPopup else { return }
            AppSettings.newDrawingUnits = DrawingUnits.allCases[max(0, popup.indexOfSelectedItem)]
        }
        actions.append(unitsAction)
        unitsPopup.target = unitsAction
        unitsPopup.action = #selector(MenuAction.run(_:))
        let unitsRow = NSStackView(views: [NSTextField(labelWithString: "Units of a new drawing:"), unitsPopup])
        unitsRow.spacing = 8

        let reset = NSButton(title: "Forget Remembered Values…", target: nil, action: nil)
        let resetAction = MenuAction { [weak self] in self?.confirmReset() }
        actions.append(resetAction)
        reset.target = resetAction
        reset.action = #selector(MenuAction.run(_:))
        // auto-save and backups (Recovery.swift)
        let autosavePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        autosavePopup.addItems(withTitles: AppSettings.autosaveChoices.map { $0.title })
        autosavePopup.selectItem(at: AppSettings.autosaveChoices.firstIndex { $0.minutes == AppSettings.autosaveMinutes }
                                 ?? AppSettings.autosaveChoices.firstIndex { $0.minutes == 2 } ?? 0)
        autosavePopup.toolTip = "Unsaved changes are saved in OhMyCAD's own folder – your drawing file is not changed"
        let autosaveAction = MenuAction { [weak autosavePopup] in
            guard let popup = autosavePopup else { return }
            let choices = AppSettings.autosaveChoices
            AppSettings.autosaveMinutes = choices[max(0, min(popup.indexOfSelectedItem, choices.count - 1))].minutes
        }
        actions.append(autosaveAction)
        autosavePopup.target = autosaveAction
        autosavePopup.action = #selector(MenuAction.run(_:))
        let autosaveRow = NSStackView(views: [NSTextField(labelWithString: "Auto-save unsaved work:"), autosavePopup])
        autosaveRow.spacing = 8

        let backupPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        backupPopup.addItems(withTitles: AppSettings.backupChoices.map { $0.title })
        backupPopup.selectItem(at: AppSettings.backupChoices.firstIndex { $0.count == AppSettings.backupCount }
                               ?? AppSettings.backupChoices.firstIndex { $0.count == 10 } ?? 0)
        backupPopup.toolTip = "When you save over a drawing, its previous version is kept as a backup"
        let backupAction = MenuAction { [weak backupPopup] in
            guard let popup = backupPopup else { return }
            let choices = AppSettings.backupChoices
            AppSettings.backupCount = choices[max(0, min(popup.indexOfSelectedItem, choices.count - 1))].count
        }
        actions.append(backupAction)
        backupPopup.target = backupAction
        backupPopup.action = #selector(MenuAction.run(_:))
        let showBackups = NSButton(title: "Show Backups in Finder", target: nil, action: nil)
        let showBackupsAction = MenuAction { BackupStore.showInFinder(for: nil) }
        actions.append(showBackupsAction)
        showBackups.target = showBackupsAction
        showBackups.action = #selector(MenuAction.run(_:))
        let backupRow = NSStackView(views: [NSTextField(labelWithString: "Backups of previous versions:"), backupPopup, showBackups])
        backupRow.spacing = 8

        let drawing = pane([
            unitsRow,
            note("A new tab takes the settings of the current drawing; an empty window after launch starts with these units."),
            autosaveRow,
            backupRow,
            note("Auto-save keeps your unsaved changes in OhMyCAD's own folder (your drawing file is not touched) and deletes them once you save or close the drawing. If OhMyCAD quits unexpectedly, it offers to recover them at the next launch. A backup of the previous version is made when you save over a drawing – at most one every 10 minutes; File › Open Backup… opens one as a copy."),
            reset,
            note("Removes your custom grid sizes and polar steps, the size of the right panel and the last export settings. Drawings are not affected.")
        ])

        // Styles (text and dimensions)
        let editStyle = NSButton(title: "Text Style…", target: nil, action: nil)
        let styleAction = MenuAction { [weak self] in
            self?.onEditTextStyle?()
            self?.refresh()
        }
        actions.append(styleAction)
        editStyle.target = styleAction
        editStyle.action = #selector(MenuAction.run(_:))
        textStyleLabel.font = NSFont.systemFont(ofSize: 12)
        let editDimStyle = NSButton(title: "Dimension Style…", target: nil, action: nil)
        let dimStyleAction = MenuAction { [weak self] in
            self?.onEditDimensionStyle?()
            self?.refresh()
        }
        actions.append(dimStyleAction)
        editDimStyle.target = dimStyleAction
        editDimStyle.action = #selector(MenuAction.run(_:))
        dimStyleLabel.font = NSFont.systemFont(ofSize: 12)
        let styles = pane([
            NSTextField(labelWithString: "Default style of new text:"),
            textStyleLabel,
            editStyle,
            note("Used by the Text tool. Every text can still get its own font, typeface and height with the ☰ menu next to it."),
            separator(),
            NSTextField(labelWithString: "Default style of new dimensions:"),
            dimStyleLabel,
            editDimStyle,
            note("Used by all dimension tools. Sizes are on paper and follow the drawing scale. Both styles are also in the Format menu.")
        ])

        // Cursor
        let cursorStyle = NSPopUpButton(frame: .zero, pullsDown: false)
        cursorStyle.addItems(withTitles: ["macOS crosshair (small)", "CAD-like crosshair"])
        cursorStyle.selectItem(at: AppSettings.cadCrosshair ? 1 : 0)
        let sizeSlider = NSSlider(value: Double(AppSettings.crosshairSize), minValue: 1, maxValue: 100, target: nil, action: nil)
        let sizeLabel = NSTextField(labelWithString: "")
        let pickSlider = NSSlider(value: Double(AppSettings.pickboxSize), minValue: 0, maxValue: 30, target: nil, action: nil)
        let pickLabel = NSTextField(labelWithString: "")
        let widthPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let widths: [CGFloat] = [0.5, 1, 1.5, 2, 3]
        widthPopup.addItems(withTitles: widths.map { "\(LineType.format($0)) px" })
        widthPopup.selectItem(at: widths.firstIndex(of: AppSettings.crosshairWidth) ?? 1)
        let colorWell = NSColorWell(style: .minimal)
        colorWell.color = AppSettings.crosshairColor
        let showBox = NSButton(checkboxWithTitle: "Show the pickbox in the middle", target: nil, action: nil)
        showBox.state = AppSettings.showPickbox ? .on : .off
        for slider in [sizeSlider, pickSlider] { slider.widthAnchor.constraint(equalToConstant: 260).isActive = true }
        colorWell.widthAnchor.constraint(equalToConstant: 44).isActive = true
        colorWell.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let updateLabels = {
            sizeLabel.stringValue = sizeSlider.doubleValue >= 99.5 ? "full screen" : "\(Int(sizeSlider.doubleValue.rounded())) %"
            pickLabel.stringValue = pickSlider.doubleValue < 0.5 ? "none" : "\(Int(pickSlider.doubleValue.rounded())) px"
            let cad = cursorStyle.indexOfSelectedItem == 1
            ([sizeSlider, widthPopup, colorWell, showBox] as [NSControl]).forEach { $0.isEnabled = cad }
        }
        updateLabels()
        let cursorAction = MenuAction { [weak self] in
            AppSettings.cadCrosshair = cursorStyle.indexOfSelectedItem == 1
            AppSettings.crosshairSize = CGFloat(sizeSlider.doubleValue.rounded())
            AppSettings.pickboxSize = CGFloat(pickSlider.doubleValue.rounded())
            AppSettings.crosshairWidth = widths[max(0, widthPopup.indexOfSelectedItem)]
            AppSettings.crosshairColor = colorWell.color
            AppSettings.showPickbox = showBox.state == .on
            updateLabels()
            self?.onChange?()
        }
        actions.append(cursorAction)
        for control in [cursorStyle, sizeSlider, pickSlider, widthPopup, colorWell, showBox] as [NSControl] {
            control.target = cursorAction
            control.action = #selector(MenuAction.run(_:))
        }
        sizeSlider.isContinuous = true
        pickSlider.isContinuous = true
        let row = { (caption: String, views: [NSView]) -> NSView in
            let label = NSTextField(labelWithString: caption)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let stack = NSStackView(views: [label] + views)
            stack.spacing = 8
            return stack
        }
        let cursorViews: [NSView] = [
            row("Cursor:", [cursorStyle]),
            row("Crosshair size:", [sizeSlider, sizeLabel]),
            row("Pickbox:", [pickSlider, pickLabel]),
            row("", [showBox]),
            row("Line width:", [widthPopup]),
            row("Color:", [colorWell]),
            note("The crosshair arms are a percentage of the drawing area; the pickbox is the square for picking objects – its size also sets how close a click must be to select something.")
        ]

        // Mouse and zoom
        let direction = NSPopUpButton(frame: .zero, pullsDown: false)
        direction.addItems(withTitles: ["Normal", "Reversed"])
        direction.selectItem(at: AppSettings.zoomWheelReversed ? 1 : 0)
        let speedSlider = NSSlider(value: log2(Double(AppSettings.zoomSpeed)), minValue: -2, maxValue: 2, target: nil, action: nil)
        speedSlider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        speedSlider.isContinuous = true
        speedSlider.numberOfTickMarks = 9
        let speedLabel = NSTextField(labelWithString: "")
        let toCursor = NSButton(checkboxWithTitle: "Zoom toward the cursor (otherwise toward the middle of the drawing area)", target: nil, action: nil)
        toCursor.state = AppSettings.zoomToCursor ? .on : .off
        let trackpad = NSButton(checkboxWithTitle: "Trackpad and Magic Mouse: two-finger scrolling zooms (otherwise it pans)", target: nil, action: nil)
        trackpad.state = AppSettings.trackpadScrollZooms ? .on : .off
        let holdSlider = NSSlider(value: AppSettings.contextMenuHoldTime, minValue: 0.25, maxValue: 1.5, target: nil, action: nil)
        holdSlider.widthAnchor.constraint(equalToConstant: 260).isActive = true
        holdSlider.isContinuous = true
        let holdLabel = NSTextField(labelWithString: "")
        let updateSpeed = {
            let value = pow(2, speedSlider.doubleValue)
            speedLabel.stringValue = String(format: "%.2g×", value) + (abs(value - 1) < 0.01 ? " (default)" : "")
            let hold = (holdSlider.doubleValue * 20).rounded() / 20
            holdLabel.stringValue = String(format: "%g s", hold) + (abs(hold - 0.4) < 0.01 ? " (default)" : "")
        }
        updateSpeed()
        let mouseAction = MenuAction { [weak self] in
            AppSettings.zoomWheelReversed = direction.indexOfSelectedItem == 1
            AppSettings.zoomSpeed = CGFloat(pow(2, speedSlider.doubleValue))
            AppSettings.zoomToCursor = toCursor.state == .on
            AppSettings.trackpadScrollZooms = trackpad.state == .on
            AppSettings.contextMenuHoldTime = (holdSlider.doubleValue * 20).rounded() / 20
            updateSpeed()
            self?.onChange?()
        }
        actions.append(mouseAction)
        for control in [direction, speedSlider, toCursor, trackpad, holdSlider] as [NSControl] {
            control.target = mouseAction
            control.action = #selector(MenuAction.run(_:))
        }
        let mouseRow = { (caption: String, views: [NSView]) -> NSView in
            let label = NSTextField(labelWithString: caption)
            label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let stack = NSStackView(views: [label] + views)
            stack.spacing = 8
            return stack
        }
        let cursorMouse = pane(cursorViews + [
            separator(),
            mouseRow("Wheel direction:", [direction]),
            mouseRow("Zoom speed:", [speedSlider, speedLabel]),
            mouseRow("", [toCursor]),
            mouseRow("", [trackpad]),
            mouseRow("Context menu hold time:", [holdSlider, holdLabel]),
            note("Hold the right button this long in the drawing (with the Select tool) for the context menu – Cut, Copy, Paste, Draw Order and more; Control-click opens it at once. A shorter right-click finishes or repeats commands as before."),
            note("While zooming with the wheel: hold Shift for fine steps (¼ speed), Option for fast zoom (3×). With a trackpad, ⌘ + two-finger scroll always zooms and pinching zooms too. If the wheel zooms the wrong way, choose Reversed. Double-click the middle button for Zoom Extents.")
        ])

        // Object snap
        let snapPanel = SnapSettingsPanel(compact: false)
        snapPanel.onChange = { [weak self] _ in self?.onChange?() }
        snapPane = snapPanel
        let snap = snapPanel.view

        // Shortcuts
        shortcutsPane = ShortcutsPane(window: window)
        let keys = shortcutsPane!.view

        for (title, view) in [("General", general), ("Drawing", drawing), ("Styles", styles),
                              ("Cursor & Mouse", cursorMouse), ("Snap", snap), ("Shortcuts", keys)] {
            let item = NSTabViewItem(identifier: title)
            item.label = title
            item.view = view
            tabView.addTabViewItem(item)
        }
        tabView.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            tabView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tabView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            tabView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    private func confirmReset() {
        guard let window = window else { return }
        let alert = NSAlert()
        alert.messageText = "Forget remembered values?"
        alert.informativeText = "Custom grid sizes, polar steps, panel sizes and the last export settings are removed. Drawings are not changed."
        alert.addButton(withTitle: "Forget")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            AppSettings.resetRememberedValues()
            self?.onChange?()
        }
    }
}

// MARK: - Snap point selection (SNAP popup and the Settings tab)

/// Checkboxes for snap point kinds. A change is saved immediately (AppSettings.enabledSnaps)
/// and takes effect everywhere – in the SNAP popup, in Settings and in the menu View › Drawing Aids › Snap Points.
final class SnapSettingsPanel: NSViewController {
    /// Called after a change; true = something was turned on (SNAP is then turned on if it is off).
    var onChange: ((Bool) -> Void)?
    private let compact: Bool
    private var boxes: [SnapType: NSButton] = [:]

    init(compact: Bool) {
        self.compact = compact
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let title = NSTextField(labelWithString: compact ? "Snap points" : "Object snap – which points Snap finds:")
        title.font = NSFont.systemFont(ofSize: compact ? 12 : 13, weight: .semibold)

        var cells: [[NSView]] = []
        var row: [NSView] = []
        for type in SnapType.allCases {
            let box = NSButton(checkboxWithTitle: type.rawValue, target: self, action: #selector(toggled(_:)))
            box.image = SnapMarker.image(type, size: compact ? 14 : 16)
            box.imagePosition = .imageLeading
            box.toolTip = type.detail
            box.identifier = NSUserInterfaceItemIdentifier(type.rawValue)
            if compact {
                box.controlSize = .small
                box.font = NSFont.systemFont(ofSize: 11)
            }
            boxes[type] = box
            row.append(box)
            if row.count == 2 {
                cells.append(row)
                row = []
            }
        }
        if !row.isEmpty { cells.append(row + [NSGridCell.emptyContentView]) }
        let grid = NSGridView(views: cells)
        grid.rowSpacing = compact ? 4 : 7
        grid.columnSpacing = compact ? 14 : 28

        func button(_ title: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .push
            if compact {
                b.controlSize = .small
                b.font = NSFont.systemFont(ofSize: 11)
            }
            return b
        }
        let buttonViews: [NSView] = [button("All", #selector(selectAllSnaps)), button("None", #selector(selectNoSnaps)),
                                     button("Default", #selector(selectDefaultSnaps))]
        let buttons = NSStackView(views: buttonViews)
        buttons.spacing = 6

        let hint = NSTextField(wrappingLabelWithString: compact
            ? "Snap (⌥3, F3) turns snapping on and off · hover for a description"
            : "Snap in the status bar (⌥3, F3) turns snapping on and off; right-click it (or click ▾ next to it) for this list. Extension: hover over the end of a line, then move along its direction. Perpendicular and Tangent work from the previous point.")
        hint.font = NSFont.systemFont(ofSize: compact ? 10 : 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = compact ? 300 : 520

        let views: [NSView] = [title, grid, buttons, hint]
        let stack = NSStackView(views: views)
        stack.orientation = NSUserInterfaceLayoutOrientation.vertical
        stack.alignment = NSLayoutConstraint.Attribute.leading
        stack.spacing = compact ? 8 : 12
        stack.edgeInsets = compact ? NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
                                   : NSEdgeInsets(top: 18, left: 22, bottom: 18, right: 22)
        if compact { stack.frame.size = stack.fittingSize }
        view = stack
        reload()
        NotificationCenter.default.addObserver(self, selector: #selector(snapsChanged(_:)),
                                               name: AppSettings.snapsDidChange, object: nil)
    }

    @objc private func snapsChanged(_ notification: Notification) {
        reload()
    }

    func reload() {
        let enabled = AppSettings.enabledSnaps
        for (type, box) in boxes { box.state = enabled.contains(type) ? .on : .off }
    }

    @objc private func toggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let type = SnapType(rawValue: raw) else { return }
        var set = AppSettings.enabledSnaps
        if sender.state == .on { set.insert(type) } else { set.remove(type) }
        AppSettings.enabledSnaps = set
        onChange?(sender.state == .on)
    }

    @objc private func selectAllSnaps() {
        AppSettings.enabledSnaps = Set(SnapType.allCases)
        onChange?(true)
    }

    @objc private func selectNoSnaps() {
        AppSettings.enabledSnaps = []
        onChange?(false)
    }

    @objc private func selectDefaultSnaps() {
        AppSettings.enabledSnaps = SnapType.defaultSet
        onChange?(true)
    }
}

// MARK: - Custom keyboard shortcuts
//
// One shared table for tools and hatch patterns (including custom ones). A shortcut = a single letter A–Z,
// alone (“F”) or with Shift (“⇧F”). Digits are for entering values, ⌥ + digit and F-keys for modes.

/// A command that can be assigned a shortcut.
enum ShortcutCommand: Hashable {
    case tool(DrawingTool)
    case hatch(String)

    var id: String {
        switch self {
        case .tool(let tool): return "tool.\(tool)"
        case .hatch(let name): return "hatch.\(name.lowercased())"
        }
    }

    var title: String {
        switch self {
        case .tool(let tool): return tool.title
        case .hatch(let name): return "Hatch: \(name)"
        }
    }

    var defaultKey: String? {
        switch self {
        case .tool(let tool): return tool.defaultShortcut
        case .hatch: return nil
        }
    }
}

enum Shortcuts {
    private static let storageKey = "OhMyCAD.shortcuts"
    /// After shortcuts change (menus and help are refreshed).
    static let didChange = Notification.Name("OhMyCADShortcutsDidChange")

    /// User changes: command id → letter ("" = no shortcut).
    private static var overrides: [String: String] = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]

    /// The effective shortcut of a command (custom, otherwise default).
    static func key(for command: ShortcutCommand) -> String? {
        if let custom = overrides[command.id] { return custom.isEmpty ? nil : custom }
        return command.defaultKey
    }

    static func key(for tool: DrawingTool) -> String? {
        return key(for: .tool(tool))
    }

    /// All commands that can have a shortcut (tools, then hatch patterns).
    static var commands: [ShortcutCommand] {
        return DrawingTool.availableTools.map { ShortcutCommand.tool($0) } + HatchPatternLibrary.all.map { .hatch($0.name) }
    }

    /// The command for a pressed key (“F” or “⇧F”).
    static func command(forKey key: String) -> ShortcutCommand? {
        let upper = key.uppercased()
        return commands.first { self.key(for: $0) == upper }
    }

    /// Converts the table notation to a shortcut: “f” → “F”; “⇧F”, “+F” or “Shift F” → “⇧F”. Otherwise nil.
    static func normalized(_ text: String) -> String? {
        var rest = text.trimmingCharacters(in: .whitespaces).uppercased()
        var shift = false
        for prefix in ["⇧", "SHIFT+", "SHIFT-", "SHIFT", "+"] where rest.hasPrefix(prefix) {
            shift = true
            rest = String(rest.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        guard rest.count == 1, let c = rest.unicodeScalars.first, c.value >= 65 && c.value <= 90 else { return nil }
        return (shift ? "⇧" : "") + rest
    }

    /// Sets a shortcut (nil = none). The same letter on another command is released.
    static func set(_ key: String?, for command: ShortcutCommand) {
        if let key = key, let other = self.command(forKey: key), other != command {
            store(nil, for: other)
        }
        store(key, for: command)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    private static func store(_ key: String?, for command: ShortcutCommand) {
        if key == command.defaultKey {
            overrides.removeValue(forKey: command.id)
        } else {
            overrides[command.id] = key ?? ""
        }
        UserDefaults.standard.set(overrides, forKey: storageKey)
    }

    static func resetAll() {
        overrides.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static var hasCustomizations: Bool { return !overrides.isEmpty }
}

// MARK: - Shortcut table in Settings

final class ShortcutsPane: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    let view: NSView
    private let tableView = NSTableView()
    private var commands: [ShortcutCommand] = []
    private weak var hostWindow: NSWindow?

    init(window: NSWindow?) {
        hostWindow = window
        let container = NSStackView()
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8
        container.edgeInsets = NSEdgeInsets(top: 14, left: 18, bottom: 14, right: 18)
        view = container
        super.init()

        let commandColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        commandColumn.title = "Command"
        commandColumn.width = 330
        let keyColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("key"))
        keyColumn.title = "Key"
        keyColumn.width = 70
        let defaultColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("default"))
        defaultColumn.title = "Default"
        defaultColumn.width = 70
        [commandColumn, keyColumn, defaultColumn].forEach { tableView.addTableColumn($0) }
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.dataSource = self
        tableView.delegate = self

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.widthAnchor.constraint(equalToConstant: 540).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 250).isActive = true

        let reset = NSButton(title: "Reset All to Defaults", target: self, action: #selector(resetAll))
        let hint = NSTextField(wrappingLabelWithString:
            "Click a key cell and type one letter (A–Z), or ⇧ and a letter for Shift (+F works too); empty = no shortcut. A key used elsewhere moves to the new command. Fixed keys: ⌥1, ⌥3–⌥0 and F3, F7–F12 switch modes, digits start typed values, ↩, Space or right-click repeats the last tool. Help › Keyboard Shortcuts… lists them all.")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.preferredMaxLayoutWidth = 540
        container.addArrangedSubview(scroll)
        container.addArrangedSubview(reset)
        container.addArrangedSubview(hint)
        reload()
    }

    func reload() {
        commands = Shortcuts.commands
        tableView.reloadData()
    }

    @objc private func resetAll() {
        Shortcuts.resetAll()
        reload()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return commands.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < commands.count, let id = tableColumn?.identifier.rawValue else { return nil }
        let command = commands[row]
        switch id {
        case "key":
            let field = NSTextField(string: Shortcuts.key(for: command) ?? "")
            field.isBordered = false
            field.drawsBackground = false
            field.isEditable = true
            field.alignment = .center
            field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            field.placeholderString = "–"
            field.tag = row
            field.delegate = self
            return field
        case "default":
            let label = NSTextField(labelWithString: command.defaultKey ?? "")
            label.alignment = .center
            label.textColor = .secondaryLabelColor
            return label
        default:
            let label = NSTextField(labelWithString: command.title)
            if case .hatch = command { label.textColor = .secondaryLabelColor }
            return label
        }
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, field.tag < commands.count else { return }
        let command = commands[field.tag]
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            Shortcuts.set(nil, for: command)
            reload()
            return
        }
        guard let key = Shortcuts.normalized(text) else {
            NSSound.beep()
            field.stringValue = Shortcuts.key(for: command) ?? ""
            return
        }
        if let other = Shortcuts.command(forKey: key), other != command, let window = hostWindow ?? field.window {
            let alert = NSAlert()
            alert.messageText = "“\(key)” is used by \(other.title)"
            alert.informativeText = "Move it to \(command.title)? \(other.title) will have no shortcut."
            alert.addButton(withTitle: "Move")
            alert.addButton(withTitle: "Cancel")
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn { Shortcuts.set(key, for: command) }
                self?.reload()
            }
            return
        }
        Shortcuts.set(key, for: command)
        reload()
    }
}
