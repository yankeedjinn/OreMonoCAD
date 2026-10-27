//
//  ContentView.swift
//  OreMonoCAD
//
//  Created by Yankee Djinn on 23.11.2025.
//
//  The editor's main window (MainViewController) and menus.
//  The other parts are in the files Geometry, Entities, Operations, Managers,
//  EditorView, Panels and DXF. The app entry point is in OreMonoCADApp.swift.
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - Undo helper

/// A single document change for NSUndoManager (the selector API needs an NSObject).
final class ReplaceBatch: NSObject {
    let removed: [CADEntity]
    let added: [CADEntity]
    /// The document the change concerns (model or layout) – Undo then works even after switching spaces.
    let document: CADDocument?
    /// Where the added objects lay in the drawing order before they were removed (Undo / Redo); nil = a new change.
    let addedAnchors: [CADDocument.OrderAnchor]?

    init(removed: [CADEntity], added: [CADEntity], document: CADDocument? = nil, addedAnchors: [CADDocument.OrderAnchor]? = nil) {
        self.removed = removed
        self.added = added
        self.document = document
        self.addedAnchors = addedAnchors
    }
}

// MARK: - Main View Controller

final class MainViewController: NSViewController, ToolbarViewDelegate, NSMenuItemValidation, NSWindowDelegate, NSMenuDelegate {

    // MARK: Tabs – every open drawing has its own tab (Tabs.swift)

    private var tabs: [DrawingTab] = [DrawingTab(untitledNumber: 1)]
    private var activeIndex = 0
    private var activeTab: DrawingTab { return tabs[activeIndex] }
    private var tabBar: DrawingTabBarView!

    /// Drawing, layers, selection and Undo of the active tab.
    /// Document of the space currently being edited – the model, or the open layout.
    var document: CADDocument { return activeTab.activeDocument }
    var layerManager: LayerManager { return activeTab.layerManager }
    var selectionManager: SelectionManager { return activeTab.selectionManager }
    private var undoer: UndoManager { return activeTab.activeUndoer }

    private(set) var editorView: CADEditorView!
    private var toolbarView: ToolbarView!
    private var layerPanel: LayerPanelView!
    /// Where layer management is: in the side panel, in its own window, or hidden.
    private enum LayersMode { case tray, window, hidden }
    private var layersMode: LayersMode = .tray
    private var layersContainer: DockablePanelView!
    private var layerHolder: NSView!
    private var trayBackground: NSView!
    private var trayResizeHandle: DragHandleView!
    /// Dividers between expanded panels (at most three panels stacked → two dividers).
    private var traySplitHandles: [DragHandleView] = []
    /// Panels of the side panel and their order from top to bottom (the user changes it by dragging the header).
    private enum TrayPanel: String, CaseIterable { case info, properties, layers }
    private var trayOrder: [TrayPanel] = TrayPanel.allCases
    /// Height shares of the expanded panels.
    private var trayWeights: [TrayPanel: CGFloat] = [.info: 0.25, .properties: 0.4, .layers: 0.35]
    private var trayHeights: [TrayPanel: CGFloat] = [:]
    private var infoPanel: InfoPanelView!
    private var infoContainer: DockablePanelView!
    private var infoShown = true
    private var infoFolded = false
    /// The whole side panel collapsed into a narrow strip.
    private var trayCollapsed = false
    /// The side panel moved to the left edge, next to the tool panel (kept in the app's settings).
    private var trayOnLeft = UserDefaults.standard.bool(forKey: "OreMonoCAD.trayOnLeft")
    private var propertiesFolded = false
    private var layersFolded = false
    private var trayWidth: CGFloat = 300
    /// Layer management in its own window (after detaching).
    private var layerWindow: NSPanel?
    private var layerWindowRestoreFrame: NSRect?
    private var propertiesPanel: PropertiesPanelView!

    /// Mode of the Properties panel.
    private enum PanelMode { case docked, collapsed, floating, detached, closed }
    private var propertiesMode: PanelMode = .docked
    private var propertiesContainer: DockablePanelView!
    private var collapsedStrip: CollapsedStripView!
    private var detachedPanel: NSPanel?
    private var floatingOrigin: CGPoint?
    private var dragStartFrame: NSRect?
    private let collapsedWidth: CGFloat = 22
    private let floatingHeight: CGFloat = 420
    private var statusBar: StatusBarView!
    /// Messages in the bottom left corner of the drawing area.
    private var toast: ToastView!

    private(set) var currentTool: DrawingTool = .select
    /// The Edit › Find and Replace window (created on first opening).
    private var findController: FindReplaceController?
    /// The “Editing block…” bar above the drawing area (only during block editing).
    private var blockEditBar: BlockEditBar?
    /// The options bar of Select Similar and Match Properties (ToolOptionsBar.swift).
    private var toolOptionsBar: ToolOptionsBar?

    private var currentFileURL: URL? {
        get { return activeTab.fileURL }
        set { activeTab.fileURL = newValue }
    }

    /// Height of the palette bar at the top of the window (0 when no palette is held to the top).
    private var toolbarHeight: CGFloat = 0
    /// The bar above the drawing tabs for the palettes held to the top.
    private var paletteDockBar: PaletteDockBar!
    /// Width of the palette bar at the right edge of the window (0 when no palette is held to the right).
    private var sideDockWidth: CGFloat = 0
    /// The bar at the right edge of the window, beyond the side panel, for the palettes held to the right.
    private var paletteSideBar: PaletteDockBar!
    /// Height of the palette bar under the drawing (0 when no palette is held to the bottom).
    private var bottomDockHeight: CGFloat = 0
    /// The bar under the drawing, above the layout tabs, for the palettes held to the bottom.
    private var paletteBottomBar: PaletteDockBar!
    /// Width of the palette bar at the left edge of the window (0 when no palette is held to the left).
    private var leftDockWidth: CGFloat = 0
    /// The bar at the left edge of the window, beyond the tool panel, for the palettes held to the left.
    private var paletteLeftBar: PaletteDockBar!
    /// Where the parts right of the tool panel start: the left palette bar and the tool panel.
    private var leftInset: CGFloat {
        return leftDockWidth + paletteWidth
    }

    /// Width of the tool panel on the left – none when all its groups are hidden or moved to palettes.
    private var paletteWidth: CGFloat {
        guard let toolbarView = toolbarView else { return ToolbarView.preferredWidth }
        return toolbarView.isEmpty ? 0 : toolbarView.panelWidth
    }
    /// Status line – a free margin at the bottom so the Dock doesn't open when clicking the toggles.
    private let statusBarHeight: CGFloat = 70
    private let layerPanelWidth: CGFloat = 290
    private let propertiesPanelWidth: CGFloat = 230

    var hasUnsavedChanges: Bool {
        get { return activeTab.isEdited }
        set {
            let changed = activeTab.isEdited != newValue
            if newValue {
                // auto-save notices that a change was added since the last backup
                activeTab.changeCount &+= 1
                activeTab.blockEdit?.changed = true
                findController?.refresh()
            } else {
                // saved (or freshly loaded) → the auto-save is no longer needed
                forgetAutosave(of: activeTab)
            }
            activeTab.isEdited = newValue
            view.window?.isDocumentEdited = newValue
            if changed { refreshTabBar() }
        }
    }

    // Without a storyboard/xib the controller must create its view itself
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        installModeKeys()
        // default options from Settings
        editorView.smoothLines = AppSettings.smoothLines
        editorView.askToClose = AppSettings.askToClose
        activeTab.units = AppSettings.newDrawingUnits
        editorView.drawingUnits = AppSettings.newDrawingUnits
        // custom shortcuts: menus using them are rebuilt
        NotificationCenter.default.addObserver(forName: Shortcuts.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setupMenus() }
        }
        // snap points: the SNAP popup, Settings and the menu share one set
        NotificationCenter.default.addObserver(forName: AppSettings.snapsDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.editorView.snapManager.enabledSnaps = AppSettings.enabledSnaps
                self.editorView.needsDisplay = true
            }
        }
        // angles in degrees or gons, bearings, feet and inches (Settings › Drawing)
        NotificationCenter.default.addObserver(forName: AngleStyle.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.editorView.unitStyleChanged()
                self.updateModes()
                self.refreshPanels()
            }
        }
        startXrefWatcher()
        setupTabBar()
        setupLayoutBar()
        connectManagers()
        setupCallbacks()
        refreshTabBar()
        refreshPanels()
        updateStatusBar()
        updateModes()
        toolbarView.setArcMethod(editorView.arcMethod)
        toolbarView.setTextKind(editorView.textKind)
        toolbarView.setMeasureKind(editorView.measureKind)
        toolbarView.setArrayKind(editorView.arrayKind)
        statusBar.setPrompt(editorView.prompt)

        // auto-saving of unsaved work (Recovery.swift)
        Timer.scheduledTimer(timeInterval: 15, target: self, selector: #selector(autosaveTimerFired(_:)),
                             userInfo: nil, repeats: true)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillResignActive(_:)),
                                               name: NSApplication.willResignActiveNotification, object: nil)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(editorView)
        updateWindowTitle()
    }

    private func setupUI() {
        view.wantsLayer = true
        view.layer?.backgroundColor = Theme.windowBackground.cgColor
        let b = view.bounds
        let middleHeight = b.height - toolbarHeight - statusBarHeight

        editorView = CADEditorView(frame: b)
        editorView.autoresizingMask = [.width, .height]
        view.addSubview(editorView)

        // the Model | Layout1 | … bar below the drawing area
        layoutBar = LayoutBarView(frame: .zero)
        view.addSubview(layoutBar)

        // tabs of open drawings – at the top of the drawing area
        tabBar = DrawingTabBarView(frame: NSRect(x: 0, y: b.height - toolbarHeight - DrawingTabBarView.height,
                                                 width: b.width, height: DrawingTabBarView.height))
        tabBar.autoresizingMask = [.width, .minYMargin]
        view.addSubview(tabBar)

        // vertical tool panel on the left
        toolbarView = ToolbarView(frame: NSRect(x: 0, y: statusBarHeight, width: paletteWidth, height: middleHeight))
        toolbarView.autoresizingMask = [.height, .maxXMargin]
        toolbarView.delegate = self
        view.addSubview(toolbarView)
        toolbarView.onShapeChanged = { [weak self] in self?.toolPanelShapeChanged() }
        toolbarView.isHidden = toolbarView.isEmpty
        toolbarView.frame.size.width = paletteWidth

        // floating tool palettes on top of the drawing: their buttons come from the tool panel
        editorView.paletteLayer.makeButton = { [weak self] tool, combined in
            self?.toolbarView.makePaletteButton(tool, combined: combined)
        }
        toolbarView.onToolsDroppedOutside = { [weak self] tools, windowPoint in
            self?.editorView.paletteLayer.dropTools(tools, atWindowPoint: windowPoint)
        }
        // a whole group moves to a palette (it leaves the panel) and comes back when the palette closes
        toolbarView.onSectionDroppedOutside = { [weak self] section, tools, windowPoint in
            self?.editorView.paletteLayer.dropTools(tools, atWindowPoint: windowPoint, section: section.title)
        }
        editorView.paletteLayer.onPanelLayoutChanged = { [weak self] in self?.toolbarView.reloadLayout() }
        // one reset for the tool panel and the palettes, from the menus of both
        toolbarView.onLayoutReset = { [weak self] in self?.resetToolLayout() }
        editorView.paletteLayer.onResetAll = { [weak self] in self?.resetToolLayout() }
        toolbarView.onSectionShown = { [weak self] section in self?.editorView.paletteLayer.takeBackSection(section) }
        paletteDockBar = PaletteDockBar(edge: .top, frame: NSRect(x: 0, y: b.height, width: b.width, height: 0))
        paletteDockBar.autoresizingMask = [.width, .minYMargin]
        paletteDockBar.onThicknessChanged = { [weak self] height in self?.paletteDockBarChanged(height) }
        view.addSubview(paletteDockBar)
        editorView.paletteLayer.dockBar = paletteDockBar
        paletteSideBar = PaletteDockBar(edge: .right, frame: NSRect(x: b.width, y: statusBarHeight, width: 0, height: middleHeight))
        paletteSideBar.autoresizingMask = [.height, .minXMargin]
        paletteSideBar.onThicknessChanged = { [weak self] width in self?.paletteSideBarChanged(width) }
        view.addSubview(paletteSideBar)
        editorView.paletteLayer.sideBar = paletteSideBar
        paletteBottomBar = PaletteDockBar(edge: .bottom, frame: NSRect(x: paletteWidth, y: statusBarHeight + LayoutBarView.height,
                                                                       width: b.width - paletteWidth, height: 0))
        paletteBottomBar.onThicknessChanged = { [weak self] height in self?.paletteBottomBarChanged(height) }
        view.addSubview(paletteBottomBar)
        editorView.paletteLayer.bottomBar = paletteBottomBar
        editorView.paletteLayer.toolPanel = toolbarView
        paletteLeftBar = PaletteDockBar(edge: .left, frame: NSRect(x: 0, y: statusBarHeight, width: 0, height: middleHeight))
        paletteLeftBar.autoresizingMask = [.height, .maxXMargin]
        paletteLeftBar.onThicknessChanged = { [weak self] width in self?.paletteLeftBarChanged(width) }
        view.addSubview(paletteLeftBar)
        editorView.paletteLayer.leftBar = paletteLeftBar
        editorView.paletteLayer.reload()

        // side panel: Properties and Layers stacked, both collapsible
        trayBackground = NSView(frame: .zero)
        trayBackground.wantsLayer = true
        trayBackground.layer?.backgroundColor = Theme.trayBackground.cgColor
        view.addSubview(trayBackground)

        layerPanel = LayerPanelView(frame: NSRect(x: 0, y: 0, width: 410, height: 360))
        layerPanel.onDetach = { [weak self] in self?.detachLayers() }
        layerPanel.onAttach = { [weak self] in self?.attachLayers() }
        layerPanel.onToggleMaximize = { [weak self] in self?.toggleMaximizeLayers() }
        layerHolder = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 360))
        layersContainer = DockablePanelView(title: "Layers", content: layerHolder)
        layersContainer.onButton = { [weak self] button in self?.layersButton(button) }

        // Properties in a movable wrapper with a header
        propertiesPanel = PropertiesPanelView(frame: NSRect(x: 0, y: 0, width: propertiesPanelWidth,
                                                            height: middleHeight - DockablePanelView.headerHeight))
        propertiesContainer = DockablePanelView(title: "Properties", content: propertiesPanel)
        propertiesContainer.onButton = { [weak self] button in self?.propertiesButton(button) }
        propertiesContainer.onDrag = { [weak self] offset, finished in self?.dragTrayPanel(.properties, offset, finished: finished) }

        // Info: information about the selected objects (formerly at the bottom of Properties)
        infoPanel = InfoPanelView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        infoContainer = DockablePanelView(title: "Info", content: infoPanel)
        infoContainer.setButtons([.fold, .collapse, .close])
        infoContainer.onButton = { [weak self] button in self?.infoButton(button) }
        infoContainer.onDrag = { [weak self] offset, finished in self?.dragTrayPanel(.info, offset, finished: finished) }
        layersContainer.onDrag = { [weak self] offset, finished in self?.dragTrayPanel(.layers, offset, finished: finished) }

        collapsedStrip = CollapsedStripView(frame: NSRect(x: b.width - collapsedWidth, y: statusBarHeight,
                                                          width: collapsedWidth, height: middleHeight))
        collapsedStrip.onExpand = { [weak self] in
            self?.trayCollapsed = false
            self?.layoutTray()
        }
        collapsedStrip.isHidden = true
        view.addSubview(collapsedStrip)

        statusBar = StatusBarView(frame: NSRect(x: 0, y: 0, width: b.width, height: statusBarHeight))
        statusBar.autoresizingMask = [.width, .maxYMargin]
        view.addSubview(statusBar)
        // the inner edges of the side columns: dragging them sets 1 to 4 icons in a row
        for part in ColumnPart.allCases {
            let handle = DragHandleView(frame: .zero)
            handle.cursor = .resizeLeftRight
            handle.toolTip = "Drag to show 1 to 4 icons in a row"
            handle.isHidden = true
            handle.onDrag = { [weak self] offset, finished in self?.dragColumnWidth(part, offset, finished: finished) }
            view.addSubview(handle)
            columnHandles[part] = handle
        }
        toast = ToastView(frame: .zero)
        view.addSubview(toast, positioned: .above, relativeTo: nil)
        statusBar.onMessage = { [weak self] message in self?.showToast(message) }

        // handles: the side panel width and the divider between Properties and Layers
        if let saved = UserDefaults.standard.object(forKey: "OreMonoCAD.trayWidth") as? Double { trayWidth = CGFloat(saved) }
        if let saved = UserDefaults.standard.stringArray(forKey: "OreMonoCAD.trayOrder") {
            let order = saved.compactMap { TrayPanel(rawValue: $0) }
            if Set(order) == Set(TrayPanel.allCases) && order.count == TrayPanel.allCases.count { trayOrder = order }
        }
        if let saved = UserDefaults.standard.dictionary(forKey: "OreMonoCAD.trayWeights") as? [String: Double] {
            for (key, value) in saved { if let kind = TrayPanel(rawValue: key), value > 0 { trayWeights[kind] = CGFloat(value) } }
        }
        infoShown = UserDefaults.standard.object(forKey: "OreMonoCAD.infoShown") as? Bool ?? true
        trayResizeHandle = DragHandleView(frame: .zero)
        trayResizeHandle.cursor = .resizeLeftRight
        trayResizeHandle.toolTip = "Drag to resize the panel"
        trayResizeHandle.onDrag = { [weak self] offset, finished in self?.resizeTray(offset, finished: finished) }
        for index in 0..<(TrayPanel.allCases.count - 1) {
            let handle = DragHandleView(frame: .zero)
            handle.cursor = .resizeUpDown
            handle.drawsLine = true
            handle.onDrag = { [weak self] offset, finished in self?.dragTraySplit(index, offset, finished: finished) }
            traySplitHandles.append(handle)
        }

        setLayersMode(.tray)
        setPropertiesMode(.docked)
        view.addSubview(trayResizeHandle)
        traySplitHandles.forEach { view.addSubview($0) }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        guard propertiesContainer != nil else { return }
        layoutTray()
    }

    // MARK: Side panel (tray)

    private func container(for kind: TrayPanel) -> DockablePanelView {
        switch kind {
        case .info: return infoContainer
        case .properties: return propertiesContainer
        case .layers: return layersContainer
        }
    }

    /// Panels currently in the side panel (top to bottom) and whether they are folded to the header.
    private var traySections: [(kind: TrayPanel, panel: DockablePanelView, folded: Bool)] {
        var sections: [(kind: TrayPanel, panel: DockablePanelView, folded: Bool)] = []
        for kind in trayOrder {
            switch kind {
            case .info:
                if infoShown { sections.append((kind, infoContainer, infoFolded)) }
            case .properties:
                if propertiesMode == .docked { sections.append((kind, propertiesContainer, propertiesFolded)) }
            case .layers:
                if layersMode == .tray { sections.append((kind, layersContainer, layersFolded)) }
            }
        }
        return sections
    }

    /// The width the side panel takes next to the drawing area.
    private var trayOccupiedWidth: CGFloat {
        if traySections.isEmpty { return 0 }
        return trayCollapsed ? collapsedWidth : trayWidth
    }

    /// Lays out the panels in the side panel, the handles and the drawing area.
    private func layoutTray() {
        let b = view.bounds
        let top = b.height - toolbarHeight, bottom = statusBarHeight
        let sections = traySections
        let visible = !sections.isEmpty && !trayCollapsed

        collapsedStrip.isHidden = !(trayCollapsed && !sections.isEmpty)
        collapsedStrip.frame = NSRect(x: trayOnLeft ? leftInset : b.width - sideDockWidth - collapsedWidth, y: bottom,
                                      width: collapsedWidth, height: top - bottom)
        collapsedStrip.titles = sections.map { $0.kind.rawValue.capitalized }

        // remove panels that should not be in the side panel (or when it is collapsed)
        // (Properties outside the side panel are floating / in a window – they stay where they are)
        for kind in TrayPanel.allCases {
            let panel = container(for: kind)
            let inTray = sections.contains { $0.kind == kind }
            if inTray && !visible { panel.removeFromSuperview() }
            if !inTray && kind != .properties { panel.removeFromSuperview() }
        }
        trayBackground.isHidden = !visible
        trayResizeHandle.isHidden = !visible
        traySplitHandles.forEach { $0.isHidden = true }

        if visible {
            trayWidth = min(max(trayWidth, 240), max(240, b.width - sideDockWidth - leftInset - 320))
            let x = trayOnLeft ? leftInset : b.width - sideDockWidth - trayWidth
            let header = DockablePanelView.headerHeight
            let total = top - bottom
            let expanded = sections.indices.filter { !sections[$0].folded }
            let free = total - CGFloat(sections.count - expanded.count) * header
            var heights = sections.map { $0.folded ? header : CGFloat(0) }
            if !expanded.isEmpty {
                // height by shares, each expanded panel at least three rows
                let minimum = min(header * 3, free / CGFloat(expanded.count))
                let sum = expanded.reduce(CGFloat(0)) { $0 + (trayWeights[sections[$1].kind] ?? 0.33) }
                for index in expanded {
                    heights[index] = max(free * (trayWeights[sections[index].kind] ?? 0.33) / max(sum, 0.001), minimum)
                }
                let excess = expanded.reduce(CGFloat(0)) { $0 + heights[$1] } - free
                let flexible = expanded.filter { heights[$0] > minimum }
                let room = flexible.reduce(CGFloat(0)) { $0 + heights[$1] - minimum }
                if excess != 0 && room > 0 {
                    for index in flexible { heights[index] -= excess * (heights[index] - minimum) / room }
                }
                // rounding: the last expanded panel absorbs the remainder
                let used = heights.reduce(0, +)
                if let last = expanded.last { heights[last] += total - used }
            }

            trayBackground.frame = NSRect(x: x, y: bottom, width: trayWidth, height: total)
            var y = top
            trayHeights = [:]
            for (index, section) in sections.enumerated() {
                let panel = section.panel
                y -= heights[index]
                if panel.superview !== view {
                    panel.removeFromSuperview()
                    view.addSubview(panel, positioned: .above, relativeTo: trayBackground)
                }
                panel.autoresizingMask = []
                panel.isFolded = section.folded
                panel.content.isHidden = section.folded
                panel.frame = NSRect(x: x, y: y, width: trayWidth, height: heights[index])
                trayHeights[section.kind] = heights[index]
            }
            // the handle lies on the side facing the drawing
            trayResizeHandle.frame = NSRect(x: (trayOnLeft ? x + trayWidth : x) - 3, y: bottom, width: 6, height: total)
            // a divider below every expanded panel that is followed by another expanded one
            splitPairs = []
            for (pair, handle) in zip(zip(expanded, expanded.dropFirst()), traySplitHandles) {
                let upper = sections[pair.0].panel
                handle.isHidden = false
                handle.frame = NSRect(x: x, y: upper.frame.minY - 3, width: trayWidth, height: 6)
                splitPairs.append((sections[pair.0].kind, sections[pair.1].kind))
            }
        }
        updateEditorViewFrame()
    }

    /// Which panels the divider separates (upper, lower).
    private var splitPairs: [(TrayPanel, TrayPanel)] = []
    private var trayDragStartWidth: CGFloat?
    private var splitDragStart: (upper: CGFloat, lower: CGFloat, weight: CGFloat)?

    private func resizeTray(_ offset: CGPoint, finished: Bool) {
        if trayDragStartWidth == nil { trayDragStartWidth = trayWidth }
        trayWidth = (trayDragStartWidth ?? trayWidth) + (trayOnLeft ? offset.x : -offset.x)
        layoutTray()
        if finished {
            trayDragStartWidth = nil
            UserDefaults.standard.set(Double(trayWidth), forKey: "OreMonoCAD.trayWidth")
        }
    }

    /// Dragging the divider between two panels: height flows from one to the other.
    private func dragTraySplit(_ index: Int, _ offset: CGPoint, finished: Bool) {
        guard index < splitPairs.count else { return }
        let (upper, lower) = splitPairs[index]
        if splitDragStart == nil {
            splitDragStart = (trayHeights[upper] ?? 100, trayHeights[lower] ?? 100,
                              (trayWeights[upper] ?? 0.33) + (trayWeights[lower] ?? 0.33))
        }
        guard let start = splitDragStart else { return }
        let both = start.upper + start.lower
        let minimum = DockablePanelView.headerHeight * 3
        guard both > 2 * minimum else { return }
        let newUpper = min(max(start.upper - offset.y, minimum), both - minimum)
        trayWeights[upper] = start.weight * newUpper / both
        trayWeights[lower] = start.weight * (both - newUpper) / both
        layoutTray()
        if finished {
            splitDragStart = nil
            saveTrayLayout()
        }
    }

    private func saveTrayLayout() {
        UserDefaults.standard.set(trayOrder.map { $0.rawValue }, forKey: "OreMonoCAD.trayOrder")
        var weights: [String: Double] = [:]
        for (kind, weight) in trayWeights { weights[kind.rawValue] = Double(weight) }
        UserDefaults.standard.set(weights, forKey: "OreMonoCAD.trayWeights")
        UserDefaults.standard.set(infoShown, forKey: "OreMonoCAD.infoShown")
    }

    // MARK: Reordering panels by dragging the header

    /// The dragged panel and the top edge the drag started from.
    private var trayDrag: (kind: TrayPanel, startTop: CGFloat)?

    /// The panel whose header is dragged sideways to move the whole side panel to the other side.
    private var traySideDrag: TrayPanel?

    /// How far (points) a header must be dragged toward the other side to move the side panel there.
    private let traySideDistance: CGFloat = 150

    /// Where the side panel will lie when the dragged header is released now: an accent area on the other side.
    private lazy var traySidePreview: NSView = {
        let preview = NSView()
        preview.wantsLayer = true
        preview.layer?.backgroundColor = Theme.accent.withAlphaComponent(0.15).cgColor
        preview.layer?.borderColor = Theme.accent.cgColor
        preview.layer?.borderWidth = 2
        preview.layer?.cornerRadius = 6
        let label = NSTextField(labelWithString: "Release to move the panels here")
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Theme.accent
        label.alignment = .center
        label.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        preview.addSubview(label)
        return preview
    }()

    /// Shows (or hides) the place on the other side where the side panel will move.
    private func showTraySidePreview(_ shown: Bool) {
        guard shown else {
            traySidePreview.removeFromSuperview()
            return
        }
        let b = view.bounds
        // the panel keeps its width; on the left it starts after the tool panel, on the right it ends at the right bar
        let x = trayOnLeft ? b.width - sideDockWidth - trayWidth : leftInset
        traySidePreview.frame = NSRect(x: x, y: statusBarHeight, width: trayWidth, height: b.height - toolbarHeight - statusBarHeight)
        if let label = traySidePreview.subviews.first as? NSTextField {
            label.frame = NSRect(x: 8, y: (traySidePreview.bounds.height - 20) / 2, width: trayWidth - 16, height: 20)
        }
        if traySidePreview.superview !== view { view.addSubview(traySidePreview, positioned: .above, relativeTo: nil) }
    }

    /// Panel header in the side panel: dragging up / down changes the order,
    /// any panel (Info, Properties, Layers) dragged far toward the other side of the window moves the whole panel there.
    private func dragTrayPanel(_ kind: TrayPanel, _ offset: CGPoint, finished: Bool) {
        if kind == .properties && propertiesMode != .docked {
            dragProperties(offset, finished: finished)
            return
        }
        let towardDrawing = trayOnLeft ? offset.x > 40 : offset.x < -40
        let sideways = abs(offset.x) > abs(offset.y) * 1.5
        let sections = traySections
        guard !trayCollapsed, sections.contains(where: { $0.kind == kind }) else { return }
        let panel = container(for: kind)
        if trayDrag == nil && (traySideDrag == kind || (traySideDrag == nil && towardDrawing && sideways)) {
            traySideDrag = kind
            // the panel follows the mouse sideways; released far enough, the side panel changes sides
            let x = trayOnLeft ? leftInset : view.bounds.width - sideDockWidth - trayWidth
            panel.frame.origin.x = x + offset.x
            panel.layer?.zPosition = 10
            // far enough: the place on the other side lights up
            showTraySidePreview(!finished && abs(offset.x) >= traySideDistance)
            if finished {
                traySideDrag = nil
                panel.layer?.zPosition = 0
                if abs(offset.x) >= traySideDistance { setTrayOnLeft(!trayOnLeft) } else { layoutTray() }
            }
            return
        }
        if trayDrag == nil {
            guard abs(offset.y) > 6, !finished else { return }
            trayDrag = (kind, panel.frame.maxY)
            panel.layer?.zPosition = 10
            NSCursor.closedHand.set()
        }
        guard let drag = trayDrag else { return }

        let top = view.bounds.height - toolbarHeight, bottom = statusBarHeight
        let height = panel.frame.height
        let desiredTop = min(max(drag.startTop + offset.y, bottom + height), top)
        let center = desiredTop - height / 2

        // new position: how many other panels (excluding the dragged one, from the top) have their center above the dragged one's center
        let others = sections.filter { $0.kind != kind }
        var y = top
        var index = 0
        for other in others {
            let h = other.panel.frame.height
            if y - h / 2 > center { index += 1 }
            y -= h
        }
        var visibleOrder = others.map { $0.kind }
        visibleOrder.insert(kind, at: min(index, visibleOrder.count))
        let hidden = trayOrder.filter { !visibleOrder.contains($0) }
        let newOrder = visibleOrder + hidden
        if newOrder != trayOrder {
            trayOrder = newOrder
            layoutTray()
        }

        if finished {
            trayDrag = nil
            panel.layer?.zPosition = 0
            layoutTray()
            saveTrayLayout()
        } else {
            panel.frame.origin.y = desiredTop - height
        }
    }

    /// Moves the side panel to the left edge (next to the tool panel) or back to the right.
    private func setTrayOnLeft(_ left: Bool) {
        trayOnLeft = left
        UserDefaults.standard.set(left, forKey: "OreMonoCAD.trayOnLeft")
        // a floating Properties panel stays where it is, a docked one moves with the panel
        layoutTray()
    }

    /// View › Side Panel on the Left.
    @objc func toggleTraySide(_ sender: Any?) {
        setTrayOnLeft(!trayOnLeft)
    }

    /// View › Reset Side Panel Layout: Info, Properties, Layers stacked, default heights.
    @objc func resetTrayLayout(_ sender: Any?) {
        trayOrder = TrayPanel.allCases
        trayWeights = [.info: 0.25, .properties: 0.4, .layers: 0.35]
        infoShown = true
        infoFolded = false
        propertiesFolded = false
        layersFolded = false
        trayCollapsed = false
        if propertiesMode != .docked { setPropertiesMode(.docked) }
        if layersMode != .tray { setLayersMode(.tray) }
        layoutTray()
        refreshProperties()
        saveTrayLayout()
    }

    // MARK: Rotating the drawing coordinates and the view

    /// Suffix after the coordinates in the status line (units, rotation).
    private var coordinateSuffix: String {
        var text = editorView.drawingUnits.suffix
        if editorView.isUCSRotated { text += String(format: " · UCS %@", AngleStyle.text(Geometry.normalizeAngle(editorView.ucsAngle) * 180 / .pi)) }
        return text
    }

    private func setUCS(origin: CGPoint, angle: CGFloat, message: String) {
        editorView.ucsOrigin = origin
        editorView.ucsAngle = Geometry.normalizeAngle(angle) < 1e-12 ? 0 : Geometry.normalizeAngle(angle)
        if activeTab.activeLayout == nil {
            activeTab.ucsOrigin = editorView.ucsOrigin
            activeTab.ucsAngle = editorView.ucsAngle
        }
        markSettingsChanged()
        statusBar.showMessage(message)
        updateStatusBar()
        refreshProperties()     // Properties show drawing coordinates
    }

    private var ucsAvailable: Bool {
        guard activeTab.activeLayout == nil else {
            statusBar.showMessage("Drawing coordinates and view rotation are for the model – switch to Model first.")
            NSSound.beep()
            return false
        }
        return true
    }

    @objc func ucsFromObject(_ sender: Any?) {
        guard ucsAvailable else { return }
        if currentTool != .select { selectTool(.select) }
        editorView.pickAxis(byObject: true, prompt: "Drawing Coordinates: click a line or a text – its direction becomes the X axis") { [weak self] axis in
            guard let self = self, let axis = axis else { return }
            self.setUCS(origin: axis.origin, angle: axis.angle,
                        message: String(format: "Drawing coordinates rotated %@ – ortho, grid and new rectangles follow the object · View › Rotate View to Drawing Coordinates turns the screen",
                                        AngleStyle.text(Geometry.normalizeAngle(axis.angle) * 180 / .pi)))
        }
    }

    @objc func ucsFromTwoPoints(_ sender: Any?) {
        guard ucsAvailable else { return }
        if currentTool != .select { selectTool(.select) }
        editorView.pickAxis(byObject: false, prompt: "Drawing Coordinates: click the new origin (0,0)") { [weak self] axis in
            guard let self = self, let axis = axis else { return }
            self.setUCS(origin: axis.origin, angle: axis.angle,
                        message: String(format: "Drawing coordinates: new origin, X axis at %@",
                                        AngleStyle.text(Geometry.normalizeAngle(axis.angle) * 180 / .pi)))
        }
    }

    @objc func ucsByAngle(_ sender: Any?) {
        guard ucsAvailable,
              let degrees = askAngle(title: "Rotate Drawing Coordinates",
                                     message: AngleStyle.bearings
                                        ? "Bearing of the X axis in \(angleUnitWord) (clockwise from north, \(AngleStyle.text(0, .direction)) = world). The origin stays."
                                        : "Angle of the X axis in \(angleUnitWord) (counter-clockwise, 0 = world). The origin stays.",
                                     initial: Geometry.normalizeAngle(editorView.ucsAngle) * 180 / .pi, kind: .direction) else { return }
        setUCS(origin: editorView.ucsOrigin, angle: degrees * .pi / 180,
               message: "Drawing coordinates rotated \(AngleStyle.text(degrees))")
    }

    @objc func ucsWorld(_ sender: Any?) {
        guard ucsAvailable else { return }
        setUCS(origin: .zero, angle: 0, message: "Drawing coordinates = world (no rotation, origin 0,0)")
    }

    @objc func rotateViewByAngle(_ sender: Any?) {
        guard ucsAvailable,
              let degrees = askAngle(title: "Rotate View",
                                     message: "Turn the drawing on screen by this angle in \(angleUnitWord) (counter-clockwise). The objects don't move.",
                                     initial: Geometry.normalizeAngle(editorView.viewport.rotation) * 180 / .pi, kind: .amount) else { return }
        setViewRotation(degrees * .pi / 180)
    }

    /// Plan: the X axis of the drawing coordinates horizontal on screen.
    @objc func rotateViewToUCS(_ sender: Any?) {
        guard ucsAvailable else { return }
        setViewRotation(-editorView.ucsAngle)
    }

    @objc func resetViewRotation(_ sender: Any?) {
        guard ucsAvailable else { return }
        setViewRotation(0)
    }

    private func setViewRotation(_ angle: CGFloat) {
        editorView.viewport.setRotation(angle)
        activeTab.viewRotation = editorView.viewport.rotation
        markSettingsChanged()
        let degrees = editorView.viewport.rotation * 180 / .pi
        statusBar.showMessage(abs(degrees) < 1e-9 ? "View not rotated" : "View rotated \(AngleStyle.text(degrees)) – the objects keep their coordinates")
    }

    /// “degrees” or “gons” – the unit angles are typed in (Settings › Drawing), for the angle dialogs.
    private var angleUnitWord: String { return AngleStyle.unit == .gons ? "gons" : "degrees" }

    /// Asks for an angle in the unit (and for a direction, the bearings) of Settings › Drawing; `initial` and the result are degrees.
    private func askAngle(title: String, message: String, initial: CGFloat, kind: AngleKind) -> CGFloat? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 160, height: 24))
        field.stringValue = LineType.format(AngleStyle.shown(initial, kind))
        field.placeholderString = "e.g. 30 or -12.5"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "gons", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "gon", with: "", options: .caseInsensitive)
        guard let value = ExpressionEvaluator.evaluate(text.trimmingCharacters(in: .whitespaces)), value.isFinite else {
            statusBar.showMessage("\u{201C}\(field.stringValue)\u{201D} is not a valid angle.")
            NSSound.beep()
            return nil
        }
        return AngleStyle.degrees(CGFloat(value), kind)
    }

    // MARK: Info panel

    private func infoButton(_ button: DockablePanelView.HeaderButton) {
        switch button {
        case .collapse:
            trayCollapsed = true
            layoutTray()
        case .close:
            infoShown = false
            layoutTray()
            saveTrayLayout()
        case .fold:
            infoFolded.toggle()
            layoutTray()
        case .detach, .dock:
            break
        }
    }

    /// View › Info Panel (⌘3, F2).
    @objc func toggleInfoPanel(_ sender: Any?) {
        if !infoShown || trayCollapsed || infoFolded {
            infoShown = true
            infoFolded = false
            trayCollapsed = false
            refreshProperties()
        } else {
            infoShown = false
        }
        layoutTray()
        saveTrayLayout()
    }

    // MARK: Properties panel – in the side panel, floating, detached, closed

    private func setPropertiesMode(_ mode: PanelMode) {
        let previous = propertiesMode
        if previous == .detached && mode != .detached { detachedPanel?.orderOut(nil) }
        // “collapse” = collapse the whole side panel into a strip
        if mode == .collapsed {
            propertiesMode = .docked
            trayCollapsed = true
            propertiesContainer.removeFromSuperview()
            layoutTray()
            refreshProperties()
            return
        }
        propertiesMode = mode
        propertiesContainer.removeFromSuperview()
        propertiesContainer.layer?.shadowOpacity = 0
        propertiesContainer.isFolded = false
        propertiesContainer.content.isHidden = false

        let b = view.bounds
        let middleHeight = b.height - toolbarHeight - statusBarHeight

        switch mode {
        case .docked:
            trayCollapsed = false
            propertiesFolded = false
            propertiesContainer.setButtons([.fold, .detach, .collapse, .close])

        case .floating:
            let height = min(floatingHeight, middleHeight - 20)
            let origin = floatingOrigin ?? CGPoint(x: b.width - propertiesPanelWidth - 30,
                                                   y: b.height - toolbarHeight - height - 20)
            propertiesContainer.frame = NSRect(origin: origin, size: NSSize(width: propertiesPanelWidth, height: height))
            propertiesContainer.autoresizingMask = [.minXMargin, .minYMargin]
            view.addSubview(propertiesContainer, positioned: .above, relativeTo: nil)
            clampFloatingProperties()
            propertiesContainer.setButtons([.dock, .detach, .close])
            propertiesContainer.layer?.shadowColor = NSColor.black.cgColor
            propertiesContainer.layer?.shadowOpacity = 0.5
            propertiesContainer.layer?.shadowRadius = 10
            propertiesContainer.layer?.shadowOffset = CGSize(width: 0, height: -3)

        case .detached:
            let panel = detachedPanel ?? makeDetachedPanel()
            if let content = panel.contentView {
                propertiesContainer.frame = content.bounds
                propertiesContainer.autoresizingMask = [.width, .height]
                content.addSubview(propertiesContainer)
            }
            propertiesContainer.setButtons([.dock, .close])
            if previous != .detached, let window = view.window {
                panel.setFrameTopLeftPoint(NSPoint(x: window.frame.maxX - propertiesPanelWidth - 40,
                                                   y: window.frame.maxY - 80))
            }
            panel.orderFront(nil)

        case .collapsed, .closed:
            break
        }
        layoutTray()
        refreshProperties()
    }

    private func makeDetachedPanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: propertiesPanelWidth, height: floatingHeight),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Properties"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 200, height: 220)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        detachedPanel = panel
        return panel
    }

    /// The close button of the detached window = close the panel (⌘2 again), for layers = return to the side panel.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === detachedPanel {
            setPropertiesMode(.closed)
            return false
        }
        if sender === layerWindow {
            attachLayers()
            return false
        }
        return true
    }

    // MARK: Layer management – in the side panel, in its own window, maximized

    private var isLayerWindowMaximized: Bool {
        return layerWindowRestoreFrame != nil
    }

    private func makeLayerWindow() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Layers"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 410, height: 260)
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.delegate = self
        if let main = view.window {
            panel.setFrameTopLeftPoint(NSPoint(x: main.frame.minX + leftInset + 20, y: main.frame.maxY - 70))
        }
        layerWindow = panel
        return panel
    }

    private func setLayersMode(_ mode: LayersMode) {
        layersMode = mode
        switch mode {
        case .tray:
            if let window = layerWindow {
                if let restore = layerWindowRestoreFrame { window.setFrame(restore, display: false) }
                layerWindowRestoreFrame = nil
                window.orderOut(nil)
            }
            layerPanel.removeFromSuperview()
            layerPanel.frame = layerHolder.bounds
            layerPanel.autoresizingMask = [.width, .height]
            layerHolder.addSubview(layerPanel)
            layerPanel.setMode(.tray)
            layersContainer.setButtons([.fold, .detach, .collapse, .close])
            layersFolded = false
            trayCollapsed = false

        case .window:
            let panel = layerWindow ?? makeLayerWindow()
            layerPanel.removeFromSuperview()
            if let content = panel.contentView {
                layerPanel.frame = content.bounds
                layerPanel.autoresizingMask = [.width, .height]
                content.addSubview(layerPanel)
            }
            layerPanel.setMode(isLayerWindowMaximized ? .maximized : .window)
            panel.makeKeyAndOrderFront(nil)

        case .hidden:
            layerWindow?.orderOut(nil)
        }
        layerPanel.reloadData()
        if propertiesContainer != nil { layoutTray() }
    }

    private func detachLayers() {
        setLayersMode(.window)
    }

    private func attachLayers() {
        setLayersMode(.tray)
    }

    /// Maximize: the window across the whole screen (without covering the Dock and menu), again = original size.
    private func toggleMaximizeLayers() {
        if layersMode != .window || !(layerWindow?.isVisible ?? false) { detachLayers() }
        guard let window = layerWindow else { return }
        if let restore = layerWindowRestoreFrame {
            window.setFrame(restore, display: true, animate: true)
            layerWindowRestoreFrame = nil
            layerPanel.setMode(.window)
        } else {
            layerWindowRestoreFrame = window.frame
            let screen = window.screen ?? view.window?.screen ?? NSScreen.main
            if let visible = screen?.visibleFrame {
                window.setFrame(visible.insetBy(dx: 8, dy: 8), display: true, animate: true)
            }
            layerPanel.setMode(.maximized)
        }
    }

    private func propertiesButton(_ button: DockablePanelView.HeaderButton) {
        switch button {
        case .collapse:
            trayCollapsed = true
            layoutTray()
        case .detach: setPropertiesMode(.detached)
        case .dock: setPropertiesMode(.docked)
        case .close: setPropertiesMode(.closed)
        case .fold:
            propertiesFolded.toggle()
            layoutTray()
        }
    }

    private func layersButton(_ button: DockablePanelView.HeaderButton) {
        switch button {
        case .collapse:
            trayCollapsed = true
            layoutTray()
        case .detach: detachLayers()
        case .dock: attachLayers()
        case .close: setLayersMode(.hidden)
        case .fold:
            layersFolded.toggle()
            layoutTray()
        }
    }

    /// Dragging the header: a docked panel becomes floating, near the right edge it docks again.
    private func dragProperties(_ offset: CGPoint, finished: Bool) {
        switch propertiesMode {
        case .docked:
            guard hypot(offset.x, offset.y) > 12 else { return }
            let start = propertiesContainer.frame
            let height = min(floatingHeight, max(start.height, 260))
            dragStartFrame = NSRect(x: start.minX, y: start.maxY - height, width: propertiesPanelWidth, height: height)
            floatingOrigin = CGPoint(x: start.minX + offset.x, y: start.maxY - height + offset.y)
            setPropertiesMode(.floating)
            if finished { finishPropertiesDrag() }

        case .floating:
            if dragStartFrame == nil { dragStartFrame = propertiesContainer.frame }
            guard var frame = dragStartFrame else { return }
            frame.origin.x += offset.x
            frame.origin.y += offset.y
            propertiesContainer.frame = frame
            clampFloatingProperties()
            floatingOrigin = propertiesContainer.frame.origin
            if finished { finishPropertiesDrag() }

        default:
            break
        }
    }

    private func finishPropertiesDrag() {
        dragStartFrame = nil
        // pulled to the edge where the side panel lies = return to it
        let atPanel = trayOnLeft ? propertiesContainer.frame.minX <= leftInset + 24
                                 : propertiesContainer.frame.maxX >= view.bounds.width - sideDockWidth - 24
        if propertiesMode == .floating && atPanel {
            floatingOrigin = nil
            setPropertiesMode(.docked)
        }
    }

    /// A floating panel must not escape the window.
    private func clampFloatingProperties() {
        var frame = propertiesContainer.frame
        let b = view.bounds
        frame.origin.x = min(max(frame.origin.x, leftInset), b.width - sideDockWidth - frame.width)
        frame.origin.y = min(max(frame.origin.y, statusBarHeight), b.height - toolbarHeight - frame.height)
        propertiesContainer.frame = frame
    }

    private func showToast(_ message: String) {
        if !message.isEmpty { Log.info("Message: " + message) }
        guard let editor = editorView, toast != nil else { return }
        let frame = editor.frame
        toast.show(message, at: CGPoint(x: frame.minX + 12, y: frame.minY + 10), availableWidth: frame.width)
        // the popup must be above the panels and the drawing area
        if toast.superview?.subviews.last !== toast {
            toast.removeFromSuperview()
            view.addSubview(toast, positioned: .above, relativeTo: nil)
        }
    }

    /// Reset Tool Panel and Palettes: all palettes close and lose their options, the tool panel
    /// shows all its groups in the default order again.
    private func resetToolLayout() {
        editorView.paletteLayer.resetPalettes()
        toolbarView.resetToDefaults()
    }

    /// The tool panel lost its last group or got one back, or got wider or narrower: it disappears, comes back
    /// or changes its width, the drawing moves. (The groups come back from View › Tool Panel or when their
    /// palettes close.)
    private func toolPanelShapeChanged() {
        // the last group just left the panel: say where the groups come back from, so the panel doesn't vanish silently
        if toolbarView.isEmpty && !toolbarView.isHidden && infoContainer != nil {
            statusBar.showMessage("Tool panel hidden – View › Tool Panel shows its groups again")
        }
        toolbarView.isHidden = toolbarView.isEmpty
        toolbarView.frame.size.width = paletteWidth
        // while the window is still being built the side panel is not there yet – it is laid out later
        if infoContainer != nil { layoutTray() }
    }

    /// The palette bar at the top got taller or lower: the tool panel, the tabs and the drawing move below it.
    private func paletteDockBarChanged(_ height: CGFloat) {
        toolbarHeight = height
        let b = view.bounds
        paletteDockBar.frame = NSRect(x: 0, y: b.height - height, width: b.width, height: height)
        toolbarView.frame = NSRect(x: leftDockWidth, y: statusBarHeight, width: paletteWidth, height: b.height - height - statusBarHeight)
        paletteLeftBar?.frame = NSRect(x: 0, y: statusBarHeight, width: leftDockWidth, height: b.height - height - statusBarHeight)
        paletteSideBar?.frame = NSRect(x: b.width - sideDockWidth, y: statusBarHeight, width: sideDockWidth,
                                       height: b.height - height - statusBarHeight)
        if propertiesContainer != nil { layoutTray() }
    }

    /// The palette bar at the left edge got wider or narrower: the tool panel and everything right of it move.
    private func paletteLeftBarChanged(_ width: CGFloat) {
        leftDockWidth = width
        let b = view.bounds
        paletteLeftBar.frame = NSRect(x: 0, y: statusBarHeight, width: width, height: b.height - toolbarHeight - statusBarHeight)
        toolbarView.frame.origin.x = width
        // while the window is still being built the side panel is not there yet – it is laid out later
        if infoContainer != nil { layoutTray() }
    }

    /// The palette bar at the right edge got wider or narrower: the side panel and the drawing move aside.
    private func paletteSideBarChanged(_ width: CGFloat) {
        sideDockWidth = width
        let b = view.bounds
        paletteSideBar.frame = NSRect(x: b.width - width, y: statusBarHeight, width: width,
                                      height: b.height - toolbarHeight - statusBarHeight)
        // while the window is still being built the side panel is not there yet – it is laid out later
        if infoContainer != nil { layoutTray() }
    }

    /// The palette bar under the drawing got taller or lower: the drawing gets lower or taller.
    private func paletteBottomBarChanged(_ height: CGFloat) {
        bottomDockHeight = height
        // while the window is still being built the side panel is not there yet – it is laid out later
        if infoContainer != nil { updateEditorViewFrame() }
    }

    private func updateEditorViewFrame() {
        var frame = view.bounds
        frame.origin.y = statusBarHeight
        frame.size.height -= toolbarHeight + statusBarHeight
        frame.origin.x = leftInset + (trayOnLeft ? trayOccupiedWidth : 0)
        frame.size.width -= leftInset + trayOccupiedWidth + sideDockWidth
        // the tab bar at the top, the drawing area below it
        frame.size.height -= DrawingTabBarView.height
        // the Model | layouts bar at the bottom
        frame.origin.y += LayoutBarView.height
        frame.size.height -= LayoutBarView.height
        // the bottom palette bar between the layout tabs and the drawing
        let bottomDock = bottomDockHeight
        frame.origin.y += bottomDock
        frame.size.height -= bottomDock
        // block editing and the tool options: the bars get their own strip above the drawing, so they never cover
        // the place you click
        let barStrip = blockEditStripHeight + toolOptionsStripHeight
        frame.size.height -= barStrip
        // a small window with wide side columns: the drawing shrinks to nothing, never to a negative size
        frame.size.width = max(frame.size.width, 0)
        frame.size.height = max(frame.size.height, 0)
        editorView.frame = frame
        tabBar?.frame = NSRect(x: frame.minX, y: frame.maxY + barStrip, width: frame.width, height: DrawingTabBarView.height)
        layoutBar?.frame = NSRect(x: frame.minX, y: frame.minY - bottomDock - LayoutBarView.height, width: frame.width,
                                  height: LayoutBarView.height)
        paletteBottomBar?.frame = NSRect(x: frame.minX, y: frame.minY - bottomDock, width: frame.width, height: bottomDock)
        positionBlockEditBar()
        positionToolOptionsBar()
        layoutColumnHandles()
    }

    // MARK: Width of the side columns (icons in a row)

    /// The side columns whose inner edge can be dragged: the left palette bar, the tool panel, the right palette bar.
    private enum ColumnPart: CaseIterable {
        case leftBar, toolPanel, rightBar
    }

    private var columnHandles: [ColumnPart: DragHandleView] = [:]
    /// Icons in a row when the drag of a column edge started.
    private var columnDragStart: Int?

    /// Puts the handles on the inner edges of the side columns (hidden when the column is not shown).
    private func layoutColumnHandles() {
        let b = view.bounds
        let y = statusBarHeight, height = b.height - toolbarHeight - statusBarHeight, width: CGFloat = 5
        let places: [ColumnPart: (x: CGFloat, shown: Bool)] = [
            .leftBar: (leftDockWidth - width, leftDockWidth > 0),
            .toolPanel: (leftInset - width, paletteWidth > 0),
            .rightBar: (b.width - sideDockWidth, sideDockWidth > 0),
        ]
        for (part, handle) in columnHandles {
            guard let place = places[part] else { continue }
            handle.isHidden = !place.shown
            handle.frame = NSRect(x: place.x, y: y, width: width, height: height)
        }
    }

    private func iconsPerRow(_ part: ColumnPart) -> Int {
        switch part {
        case .toolPanel: return ToolbarView.iconsPerRow
        case .leftBar: return PaletteDockBar.iconsPerRow(for: .left)
        case .rightBar: return PaletteDockBar.iconsPerRow(for: .right)
        }
    }

    /// Dragging the inner edge of a side column: every icon's width further (toward the drawing) adds an icon
    /// to a row, back takes one away, 1 to 4.
    private func dragColumnWidth(_ part: ColumnPart, _ offset: CGPoint, finished: Bool) {
        let current = iconsPerRow(part)
        if columnDragStart == nil { columnDragStart = current }
        let inward = part == .rightBar ? -offset.x : offset.x
        let wanted = min(4, max(1, (columnDragStart ?? current) + Int((inward / 38).rounded())))
        if wanted != current {
            switch part {
            case .toolPanel:
                ToolbarView.iconsPerRow = wanted
                toolbarView.reloadLayout()
            case .leftBar:
                PaletteDockBar.setIconsPerRow(wanted, for: .left)
                editorView.paletteLayer.reload()
            case .rightBar:
                PaletteDockBar.setIconsPerRow(wanted, for: .right)
                editorView.paletteLayer.reload()
            }
        }
        if finished { columnDragStart = nil }
    }

    private func connectManagers() {
        editorView.document = document
        editorView.layerManager = layerManager
        editorView.selectionManager = selectionManager
        editorView.blockLibrary = activeTab.blocks
        if let current = editorView.insertDefinition, activeTab.blocks.named(current.name) !== current {
            editorView.insertDefinition = nil
        }
        layerPanel.layerManager = layerManager
    }

    private func setupCallbacks() {
        document.onEntitiesChanged = { [weak self] in
            self?.editorView.needsDisplay = true
            self?.refreshProperties()
        }

        // layers and the current layer are saved in the drawing, so any change of them is a change of the drawing
        layerManager.onLayersChanged = { [weak self] in
            // objects on a hidden layer don't stay selected – they would be moved or deleted unseen
            if let self = self {
                let hidden = self.selectionManager.getSelectedEntities(from: self.document.getAllEntities())
                    .filter { !self.layerManager.isLayerVisible($0.layer) }
                if !hidden.isEmpty { self.selectionManager.deselect(hidden) }
            }
            self?.layerPanel.reloadData()
            self?.refreshProperties()
            self?.editorView.needsDisplay = true
            self?.hasUnsavedChanges = true
        }

        layerManager.onCurrentLayerChanged = { [weak self] in
            self?.layerPanel.reloadData()
            self?.updateStatusBar()
            self?.hasUnsavedChanges = true
        }

        selectionManager.onSelectionChanged = { [weak self] in
            guard let self = self else { return }
            self.editorView.needsDisplay = true
            self.refreshProperties()
            self.statusBar.setPrompt(self.editorView.prompt)
            if self.layersMode == .tray { self.layerPanel.reloadData() }     // marker for layers of the selected objects
        }

        editorView.onViewChanged = { [weak self] in self?.updateStatusBar() }
        editorView.onCursorMoved = { [weak self] point in
            guard let self = self else { return }
            self.showCursorCoordinates(point)
        }
        statusBar.onToggleGridSnap = { [weak self] in self?.toggleGridSnap() }
        statusBar.onToggleShowGrid = { [weak self] in self?.toggleGrid() }
        statusBar.onToggleShowAxes = { [weak self] in self?.toggleAxes() }
        statusBar.onCoordinatesClicked = { [weak self] in self?.toggleCoordinateDisplay() }
        statusBar.onFunctionKeysInfo = { [weak self] in self?.showFunctionKeysInfo() }
        refreshFunctionKeysState()
        statusBar.onTogglePolar = { [weak self] in self?.togglePolar() }
        statusBar.onSetGridSize = { [weak self] size in
            self?.editorView.gridSize = size
            self?.markSettingsChanged()
        }
        statusBar.onSetPolarIncrement = { [weak self] degrees in
            self?.editorView.polarIncrement = degrees
            self?.editorView.polarEnabled = true
            self?.markSettingsChanged()
        }
        editorView.onPromptChanged = { [weak self] prompt in
            self?.statusBar.setPrompt(prompt)
            self?.updateToolOptionsBar()
        }
        editorView.onXLineKindChanged = { [weak self] kind in self?.toolbarView.setXLineKind(kind) }
        editorView.onMessage = { [weak self] message in self?.statusBar.showMessage(message) }
        editorView.onBlockEditRequested = { [weak self] reference in
            self?.beginBlockEdit(definition: reference.definition, reference: reference)
        }
        editorView.onModesChanged = { [weak self] in self?.updateModes() }
        statusBar.onToggleSnap = { [weak self] in self?.toggleSnap() }
        statusBar.onShowSnapSettings = { [weak self] anchor in self?.showSnapSettings(relativeTo: anchor) }
        statusBar.onToggleOrtho = { [weak self] in self?.toggleOrtho() }
        statusBar.onToggleSnapTracking = { [weak self] in self?.toggleSnapTracking() }
        statusBar.onToggleAskToClose = { [weak self] in self?.toggleAskToClose() }
        statusBar.onToggleLineContinue = { [weak self] in self?.toggleLineContinue() }
        statusBar.onToggleLineWeights = { [weak self] in self?.toggleLineWeights() }
        statusBar.onToggleScreenWeights = { [weak self] in self?.toggleScreenWeights() }
        statusBar.onSelectScale = { [weak self] scale in self?.selectScale(scale) }
        statusBar.onAddCustomScale = { [weak self] in self?.addCustomScale() }
        statusBar.onClearCustomScales = { [weak self] in self?.clearCustomScales() }
        editorView.onDeleteRequested = { [weak self] in self?.deleteSelection() }
        editorView.onZoomExtentsRequested = { [weak self] in self?.zoomExtents() }
        editorView.onToolChangeRequested = { [weak self] tool in self?.selectTool(tool) }
        editorView.onContextMenuRequested = { [weak self] in self?.drawingContextMenu() }
        editorView.onCommit = { [weak self] removed, added, name in
            self?.applyChange(removed: removed, added: added, actionName: name)
            self?.warnAboutCurrentLayer(added: added)
        }

        layerPanel.onRenameLayer = { [weak self] oldName, newName in self?.renameLayer(oldName, to: newName) }
        layerPanel.onDeleteLayer = { [weak self] name in self?.deleteLayer(name) }
        layerPanel.selectedObjectLayers = { [weak self] in
            guard let self = self else { return [] }
            return Set(self.selectionManager.getSelectedEntities(from: self.document.getAllEntities()).map { $0.layer })
        }
        layerPanel.onSelectLayerObjects = { [weak self] name in self?.selectObjects(onLayer: name) }

        propertiesPanel.onChangeLayer = { [weak self] name in self?.changeSelection(actionName: "Change Layer") { $0.layer = name } }
        propertiesPanel.onChangeColor = { [weak self] color in self?.changeSelection(actionName: "Change Color") { $0.color = color } }
        propertiesPanel.onChangeLineWeight = { [weak self] weight in
            self?.changeSelection(actionName: "Change Lineweight") { $0.lineWeight = weight }
        }
        propertiesPanel.onChangeHatchPattern = { [weak self] pattern in
            self?.changeSelection(actionName: "Change Hatch Pattern") { entity in if let hatch = entity as? HatchEntity { hatch.pattern = pattern } }
        }
        propertiesPanel.onChangeHatchAngle = { [weak self] degrees in
            self?.changeSelection(actionName: "Change Hatch Angle") { entity in if let hatch = entity as? HatchEntity { hatch.angle = degrees * .pi / 180 } }
        }
        propertiesPanel.onChangeHatchScale = { [weak self] scale in
            self?.changeSelection(actionName: "Change Hatch Scale") { entity in if let hatch = entity as? HatchEntity { hatch.scale = scale } }
        }
        propertiesPanel.onEdit = { [weak self] name, edit in self?.editSelection(actionName: name, edit) }
        propertiesPanel.modelExtents = { [weak self] in self?.modelExtents() }
        propertiesPanel.modelLayerNames = { [weak self] in self?.layerManager.getAllLayers().map { $0.name } ?? [] }
        propertiesPanel.unitsPerPaperMM = { [weak self] in self?.editorView.unitsPerPaperMM ?? 1 }
        propertiesPanel.lineTypeOf = { [weak self] entity in self?.layerManager.lineType(for: entity) ?? .continuous }
        editorView.onViewportDoubleClick = { [weak self] viewport in self?.openModel(at: viewport) }
        editorView.onHatchShortcut = { [weak self] name in
            guard let pattern = HatchPatternLibrary.named(name) else { return }
            self?.toolbarDidSelectHatchPattern(pattern)
        }
        editorView.onEditText = { [weak self] text in self?.editText(text) }
        editorView.onBlocksChanged = { [weak self] in
            self?.hasUnsavedChanges = true
            self?.editorView.needsDisplay = true
        }
        propertiesPanel.onReloadXref = { [weak self] definition in self?.reloadXref(definition) }
        propertiesPanel.blockDefinitions = { [weak self] in self?.activeTab.blocks.blocks ?? [] }
        propertiesPanel.onEditText = { [weak self] text in self?.editText(text) }
        propertiesPanel.onRebuildHatch = { [weak self] in self?.rebuildHatch(nil) }
        propertiesPanel.onSubtractFromHatch = { [weak self] in self?.subtractFromHatch(nil) }
        propertiesPanel.needsVertexRefresh = { [weak self] in self?.refreshProperties() }
        propertiesPanel.onRequestCustomHatchPattern = { [weak self] in
            guard let self = self else { return }
            guard let pattern = HatchPatternEditor().run(basedOn: self.editorView.hatchPattern) else {
                self.refreshProperties()
                return
            }
            HatchPatternLibrary.addCustom(pattern)
            self.changeSelection(actionName: "Change Hatch Pattern") { entity in if let hatch = entity as? HatchEntity { hatch.pattern = pattern } }
        }
    }

    /// View › Layers Panel (⌘1): shows the layers in the side panel (or their window); a second press collapses them.
    private func showLayerManager() {
        switch layersMode {
        case .window:
            if layerWindow?.isVisible ?? false {
                layerWindow?.makeKeyAndOrderFront(nil)
            } else {
                attachLayers()
            }
        case .hidden:
            attachLayers()
        case .tray:
            if trayCollapsed {
                trayCollapsed = false
                layersFolded = false
            } else {
                layersFolded.toggle()
            }
            layerPanel.reloadData()
            layoutTray()
        }
    }

    /// Are the layers visible right now?
    private var layersVisible: Bool {
        switch layersMode {
        case .tray: return !trayCollapsed && !layersFolded
        case .window: return layerWindow?.isVisible ?? false
        case .hidden: return false
        }
    }

    private func refreshPanels() {
        layerPanel.reloadData()
        refreshProperties()
    }

    private func refreshProperties() {
        let all = document.getAllEntities()
        let selection = selectionManager.getSelectedEntities(from: all)
        propertiesPanel.ucsToWorld = editorView.ucsToWorld
        propertiesPanel.update(selection: selection, layerNames: layerManager.getAllLayers().map { $0.name })
        infoPanel.update(selection: selection, objectCount: all.count, layerCount: layerManager.getAllLayers().count)
    }

    private func updateStatusBar() {
        GeoReference.active = activeTab.geoReference ?? .identity
        GeoReference.activeMetersPerUnit = modelMetersPerUnit
        statusBar.setZoom(editorView.viewport.getCurrentZoom())
        statusBar.setCurrentLayer(layerManager.currentLayerName)
    }

    private func updateWindowTitle() {
        view.window?.title = currentFileURL?.lastPathComponent ?? activeTab.title
        view.window?.representedURL = currentFileURL
        view.window?.isDocumentEdited = activeTab.isEdited
        refreshTabBar()
    }

    // MARK: Tabs

    private func setupTabBar() {
        tabBar.onSelect = { [weak self] index in self?.activateTab(index) }
        tabBar.onClose = { [weak self] index in self?.closeTab(at: index) }
        tabBar.onNewTab = { [weak self] in self?.newTab(nil) }
        tabBar.onMove = { [weak self] from, to in self?.moveTab(from: from, to: to) }
        tabBar.onCloseOthers = { [weak self] index in self?.closeOtherTabs(keeping: index) }
        tabBar.onRevealInFinder = { [weak self] index in
            guard let self = self, self.tabs.indices.contains(index), let url = self.tabs[index].fileURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    private func refreshTabBar() {
        tabBar?.update(titles: tabs.map { (title: $0.title, toolTip: $0.fileURL?.path ?? "Not saved yet", edited: $0.isEdited) },
                       selected: activeIndex)
    }

    /// The lowest free number for “Untitled N”.
    private func freeUntitledNumber() -> Int {
        let used = Set(tabs.filter { $0.fileURL == nil }.map { $0.untitledNumber })
        var number = 1
        while used.contains(number) { number += 1 }
        return number
    }

    /// Saves the drawing area state (view and drawing settings) into the active tab.
    private func storeActiveTabState() {
        let tab = activeTab
        // during block editing the tab keeps the view from before the edit (it returns to it)
        if tab.blockEdit != nil { return }
        if let layout = tab.activeLayout {
            // on a layout drawing is in mm 1:1 – the model settings stay in the tab
            layout.viewState = editorView.viewport.viewState
            layout.gridSize = editorView.gridSize
        } else {
            tab.viewState = editorView.viewport.viewState
            tab.drawingScale = editorView.drawingScale
            tab.units = editorView.drawingUnits
            tab.gridSize = editorView.gridSize
            tab.viewRotation = editorView.viewport.rotation
            tab.ucsAngle = editorView.ucsAngle
            tab.ucsOrigin = editorView.ucsOrigin
        }
        tab.showLineWeights = editorView.showLineWeights
        tab.showGrid = editorView.showGrid
        tab.showAxes = editorView.showAxes
        tab.lineWeightOnScreen = editorView.lineWeightOnScreen
        tab.hatchPattern = editorView.hatchPattern
        tab.hatchAngle = editorView.hatchAngle
        tab.hatchScale = editorView.hatchScale
        tab.polarIncrement = editorView.polarIncrement
    }

    /// Connects the drawing area and the panels to the active tab.
    private func restoreActiveTabState() {
        defer { findController?.refresh() }
        let tab = activeTab
        editorView.cancelCurrentOperation()
        connectManagers()
        setupCallbacks()
        editorView.drawingScale = tab.drawingScale
        editorView.showLineWeights = tab.showLineWeights
        editorView.showGrid = tab.showGrid
        editorView.showAxes = tab.showAxes
        editorView.lineWeightOnScreen = tab.lineWeightOnScreen
        editorView.hatchPattern = tab.hatchPattern
        editorView.hatchAngle = tab.hatchAngle
        editorView.hatchScale = tab.hatchScale
        editorView.drawingUnits = tab.units
        editorView.gridSize = tab.gridSize
        editorView.polarIncrement = tab.polarIncrement
        toolbarView.setHatchPattern(tab.hatchPattern)
        editorView.viewport.viewState = tab.viewState ?? (zoom: 1, pan: CGPoint.zero)
        applySpace()
        updateWindowTitle()
        refreshPanels()
        updateStatusBar()
        updateModes()
        statusBar.setPrompt(editorView.prompt)
        editorView.needsDisplay = true
        view.window?.makeFirstResponder(editorView)
    }

    private func activateTab(_ index: Int) {
        guard tabs.indices.contains(index), index != activeIndex else { return }
        guard ensureNoBlockEdit() else { return }
        editorView.cancelCurrentOperation()
        storeActiveTabState()
        activeIndex = index
        restoreActiveTabState()
    }

    /// A new empty drawing in a new tab (drawing settings are taken from the current tab).
    @objc func newTab(_ sender: Any?) {
        guard ensureNoBlockEdit() else { return }
        editorView.cancelCurrentOperation()
        storeActiveTabState()
        let current = activeTab
        let tab = DrawingTab(untitledNumber: freeUntitledNumber())
        tab.drawingScale = current.drawingScale
        tab.showLineWeights = current.showLineWeights
        tab.lineWeightOnScreen = current.lineWeightOnScreen
        tab.hatchPattern = current.hatchPattern
        tab.hatchAngle = current.hatchAngle
        tab.hatchScale = current.hatchScale
        tab.units = current.units
        tab.gridSize = current.gridSize
        tab.polarIncrement = current.polarIncrement
        tabs.insert(tab, at: activeIndex + 1)
        activeIndex += 1
        restoreActiveTabState()
        statusBar.showMessage("New drawing")
    }

    private func moveTab(from: Int, to: Int) {
        guard tabs.indices.contains(from), tabs.indices.contains(to), from != to else { return }
        let active = activeTab
        let tab = tabs.remove(at: from)
        tabs.insert(tab, at: to)
        activeIndex = tabs.firstIndex { $0 === active } ?? 0
        refreshTabBar()
    }

    @objc func selectNextTab(_ sender: Any?) {
        guard tabs.count > 1 else { return }
        activateTab((activeIndex + 1) % tabs.count)
    }

    @objc func selectPreviousTab(_ sender: Any?) {
        guard tabs.count > 1 else { return }
        activateTab((activeIndex - 1 + tabs.count) % tabs.count)
    }

    /// ⌘W – closes the tab; the last empty tab closes the window.
    @objc func closeCurrentTab(_ sender: Any?) {
        if tabs.count == 1 && activeTab.isPristine {
            view.window?.performClose(sender)
        } else {
            closeTab(at: activeIndex)
        }
    }

    private func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let tab = tabs[index]
        if tab.blockEdit != nil, tab === activeTab { guard ensureNoBlockEdit() else { return } }
        if tab.isEdited {
            activateTab(index)          // show the drawing we are asking about
            // the switch was refused (Cancel in the block edit question) – the question would be about another drawing
            guard activeTab === tab, confirmCloseActiveTab() else { return }
        }
        guard let position = tabs.firstIndex(where: { $0 === tab }) else { return }
        // closed (saved or discarded) → the auto-save is removed
        AutoSaveStore.remove(tab.autosaveID)
        if tabs.count == 1 {
            // last tab → a clean drawing in its place
            editorView.cancelCurrentOperation()
            tabs = [DrawingTab(untitledNumber: 1)]
            activeIndex = 0
            restoreActiveTabState()
            return
        }
        if position == activeIndex {
            editorView.cancelCurrentOperation()
            tabs.remove(at: position)
            activeIndex = min(position, tabs.count - 1)
            restoreActiveTabState()
        } else {
            tabs.remove(at: position)
            if position < activeIndex { activeIndex -= 1 }
            refreshTabBar()
        }
    }

    private func closeOtherTabs(keeping index: Int) {
        guard tabs.indices.contains(index) else { return }
        let keep = tabs[index]
        for tab in tabs where tab !== keep {
            guard let position = tabs.firstIndex(where: { $0 === tab }) else { continue }
            closeTab(at: position)
            if tabs.contains(where: { $0 === tab }) { break }     // the user pressed Cancel
        }
        if let position = tabs.firstIndex(where: { $0 === keep }) { activateTab(position) }
    }

    /// Asks whether to save the active tab. true = it can be closed.
    private func confirmCloseActiveTab() -> Bool {
        guard activeTab.isEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(activeTab.title)”?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        switch alert.runModal() {
        case .alertFirstButtonReturn: return saveActiveTabNow()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    /// Saves the active tab immediately (without a sheet) – for closing. true = saved.
    private func saveActiveTabNow() -> Bool {
        guard ensureNoBlockEdit() else { return false }
        if let url = currentFileURL, NativeFormat.isNative(url) {
            return save(to: url)
        }
        let panel = makeSavePanel()
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        return save(to: url)
    }

    /// Opens a file in a new tab (or switches to the tab where it is already open).
    // MARK: Recent files

    /// Recently opened / saved drawings (managed by the system – work in the sandbox and across launches).
    /// Files that were deleted or moved to the Trash are left out; the system list itself stays untouched,
    /// so a drawing on a disconnected drive comes back once the drive is mounted again.
    var recentFileURLs: [URL] {
        return NSDocumentController.shared.recentDocumentURLs.filter { url in
            guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else { return false }
            let components = url.standardizedFileURL.pathComponents
            return !components.contains(".Trash") && !components.contains(".Trashes")
        }
    }

    private func noteRecent(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }

    /// Opens a recent file (from the menu or from the start screen).
    func openRecentFile(_ url: URL) {
        openFile(url)
    }

    @objc func openRecentItem(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { openRecentFile(url) }
    }

    @objc func clearRecentFiles(_ sender: Any?) {
        NSDocumentController.shared.clearRecentDocuments(sender)
    }

    private func populateRecentMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = recentFileURLs
        if urls.isEmpty {
            let empty = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentItem(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = url
            item.toolTip = url.path
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear Menu", action: urls.isEmpty ? nil : #selector(clearRecentFiles(_:)), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
    }

    private func openFile(_ url: URL) {
        guard ensureNoBlockEdit() else { return }
        Log.info("Open: \(url.lastPathComponent)")
        let path = url.standardizedFileURL.path
        if let index = tabs.firstIndex(where: { $0.fileURL?.standardizedFileURL.path == path }) {
            activateTab(index)
            statusBar.showMessage("\(url.lastPathComponent) is already open")
            return
        }
        let reuse = activeTab.isPristine
        if !reuse {
            editorView.cancelCurrentOperation()
            storeActiveTabState()
            tabs.insert(DrawingTab(untitledNumber: 0), at: activeIndex + 1)
            activeIndex += 1
            restoreActiveTabState()
        }
        let tab = activeTab
        if !loadDocument(from: url) && !reuse {
            // the file could not be opened → close the empty tab again
            if let position = tabs.firstIndex(where: { $0 === tab }), tabs.count > 1 {
                tabs.remove(at: position)
                activeIndex = max(0, min(position - 1, tabs.count - 1))
                restoreActiveTabState()
            }
        }
    }

    func selectTool(_ tool: DrawingTool) {
        // zoom only changes the view – the tool in progress continues
        switch tool {
        case .zoomIn: zoomIn(); return
        case .zoomOut: zoomOut(); return
        case .zoomExtents: zoomExtents(); return
        case .zoomSelected: zoomSelected(nil); return
        case .zoomWindow: zoomWindow(nil); return
        // Filter is a dialog – it ends in the Select tool with the found objects selected
        case .filter: filterObjects(nil); return
        // Block Manager is a window of its own – the tool does not change
        case .blockManager: showBlockManager(nil); return
        default: break
        }
        // External Reference: first the file, then the insertion point
        if tool == .xref && !xrefReady {
            attachXref(nil)
            return
        }
        xrefReady = false
        // Image or PDF Reference: first the file, then the corner
        if tool.placesUnderlay && editorView.pendingImage?.isPDF != (tool == .pdfReference) {
            if tool == .pdfReference { attachPDF(nil) } else { attachImage(nil) }
            return
        }
        if !tool.placesUnderlay { editorView.pendingImage = nil }
        if tool != currentTool { Log.info("Tool: \(tool.title)") }
        currentTool = tool
        editorView.currentTool = tool
        toolbarView.setSelectedTool(tool)
        statusBar.showMessage("")
        updateStatusBar()
        updateToolOptionsBar()
    }

    // MARK: Toolbar delegate

    func toolbarDidSelectTool(_ tool: DrawingTool) {
        selectTool(tool)
        view.window?.makeFirstResponder(editorView)
    }

    func toolbarDidSelectHatchPattern(_ pattern: HatchPattern) {
        editorView.hatchPattern = pattern
        toolbarView.setHatchPattern(pattern)
        if currentTool != .hatch { selectTool(.hatch) }
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    @objc func selectHatchPattern(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String, let pattern = HatchPatternLibrary.named(name) {
            toolbarDidSelectHatchPattern(pattern)
        }
    }

    // MARK: Hatch – custom patterns and settings

    func toolbarHatchSettingsSummary() -> (angle: CGFloat, scaleText: String) {
        let scale = LineType.format(editorView.currentHatchScale)
        return (editorView.currentHatchAngle, editorView.hatchScale == nil ? "\(scale) (drawing scale)" : scale)
    }

    func toolbarDidRequestCustomHatchPattern() {
        newCustomHatchPattern(nil)
    }

    func toolbarDidRequestHatchSettings() {
        hatchSettings(nil)
    }

    func toolbarDidRemoveCustomHatchPattern(_ name: String) {
        let alert = NSAlert()
        alert.messageText = "Remove the custom pattern “\(name)”?"
        alert.informativeText = "Hatches already drawn with it keep their look."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        HatchPatternLibrary.removeCustom(named: name)
        if editorView.hatchPattern.name == name { toolbarDidSelectHatchPattern(.lines) }
        refreshProperties()
        statusBar.showMessage("Pattern “\(name)” removed")
    }

    /// A new custom pattern (from the menu) – it becomes the current pattern of the Hatch tool.
    @objc func newCustomHatchPattern(_ sender: Any?) {
        guard let pattern = HatchPatternEditor().run(basedOn: editorView.hatchPattern) else { return }
        HatchPatternLibrary.addCustom(pattern)
        toolbarDidSelectHatchPattern(pattern)
        refreshProperties()
        statusBar.showMessage("Pattern “\(pattern.name)” added")
    }

    @objc func hatchSettings(_ sender: Any?) {
        guard let result = HatchSettingsDialog.run(angle: editorView.hatchAngle, scale: editorView.hatchScale,
                                                   drawingScale: editorView.drawingScale) else { return }
        editorView.hatchAngle = result.angle
        editorView.hatchScale = result.scale
        statusBar.setPrompt(editorView.prompt)
    }

    @objc func removeCustomHatchPatternFromMenu(_ sender: NSMenuItem) {
        if let name = sender.representedObject as? String { toolbarDidRemoveCustomHatchPattern(name) }
    }

    /// The Format › Hatch Pattern menu is rebuilt every time it opens (so it contains new custom patterns too).
    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu.title == "Open Recent" {
            populateRecentMenu(menu)
            return
        }
        if menu.title == "Layouts" {
            menu.removeAllItems()
            let tab = activeTab
            if tab.layouts.isEmpty {
                let empty = NSMenuItem(title: "No Layouts Yet", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for (index, layout) in tab.layouts.enumerated() {
                let item = NSMenuItem(title: layout.name, action: #selector(showLayoutFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
                item.state = tab.activeLayoutIndex == index ? .on : .off
                item.toolTip = layout.paperDescription
                menu.addItem(item)
            }
            return
        }
        if menu.title == "Named Views" {
            populateNamedViewsMenu(menu)
            return
        }
        if menu.title == "Insert Block" {
            menu.removeAllItems()
            let definitions = toolbarBlockDefinitions()
            if definitions.isEmpty {
                let empty = NSMenuItem(title: "No blocks in this drawing yet", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            }
            for definition in definitions {
                let item = NSMenuItem(title: definition.name, action: #selector(insertBlockFromMenu(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = definition.name
                item.image = BlockPreview.image(of: definition, size: 18)
                item.subtitle = definition.menuSubtitle
                menu.addItem(item)
            }
            return
        }
        guard menu.title == "Hatch Pattern" else { return }
        let summary = toolbarHatchSettingsSummary()
        HatchMenuBuilder.populate(menu, current: editorView.hatchPattern, angle: summary.angle, scaleText: summary.scaleText,
                                  actions: .init(target: self,
                                                 choose: #selector(selectHatchPattern(_:)),
                                                 newCustom: #selector(newCustomHatchPattern(_:)),
                                                 settings: #selector(hatchSettings(_:)),
                                                 removeCustom: #selector(removeCustomHatchPatternFromMenu(_:))),
                                  imageSize: 18)
    }

    // MARK: Text

    func toolbarDidSelectTextKind(_ kind: TextKind) {
        editorView.textKind = kind
        toolbarView.setTextKind(kind)
        if currentTool != .text { selectTool(.text) }
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    func toolbarDidRequestTextStyle() {
        textStyle(nil)
    }

    @objc func rebuildHatch(_ sender: Any?) {
        editorView.cancelCurrentOperation()
        editorView.rebuildSelectedHatches()
        view.window?.makeFirstResponder(editorView)
    }

    @objc func subtractFromHatch(_ sender: Any?) {
        editorView.cancelCurrentOperation()
        editorView.subtractFromSelectedHatches()
        view.window?.makeFirstResponder(editorView)
    }

    @objc func textStyle(_ sender: Any?) {
        let height = LineType.format(editorView.newTextHeight)
        let note = activeTab.activeLayout != nil
            ? "On a layout 1 mm on paper = 1 unit."
            : "At the drawing scale \(editorView.drawingScale.title) that is \(height) \(editorView.drawingUnits.suffix) in the drawing."
        guard let style = TextStyleDialog().run(current: editorView.textStyle, scaleNote: note) else { return }
        editorView.textStyle = style
        statusBar.showMessage("Text style: \(style.family.isEmpty ? FontLibrary.systemFamilyTitle : style.family) \(style.face), \(LineType.format(style.heightMM)) mm")
    }

    /// Editing text directly on the canvas (Properties › Edit) – the ☰ button next to the text opens the format.
    private func editText(_ text: TextEntity) {
        view.window?.makeFirstResponder(editorView)
        editorView.beginEditing(text)
    }

    func toolbarDidSelectMeasureKind(_ kind: MeasureKind) {
        editorView.measureKind = kind
        toolbarView.setMeasureKind(kind)
        if currentTool != .measure { selectTool(.measure) }
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    // MARK: Construction lines

    func toolbarPolygonSettings() -> (method: PolygonMethod, sides: Int) {
        return (editorView.polygonMethod, editorView.polygonSides)
    }

    func toolbarDidSelectPolygonMethod(_ method: PolygonMethod) {
        if currentTool != .polygon { selectTool(.polygon) }
        editorView.polygonMethod = method
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    func toolbarDidRequestPolygonSides() {
        if currentTool != .polygon { selectTool(.polygon) }
        editorView.askPolygonSides()
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    func toolbarDidSelectXLineKind(_ kind: XLineKind) {
        if kind == .angle {
            guard let degrees = askAngle(title: "Construction Line – Angle",
                                         message: AngleStyle.bearings
                                            ? "Bearing in \(angleUnitWord), clockwise from the Y axis (north) of the drawing coordinates."
                                            : "Angle in \(angleUnitWord) from the X axis of the drawing coordinates (counter-clockwise).",
                                         initial: editorView.xlineAngle, kind: .direction) else { return }
            editorView.xlineAngle = degrees
        }
        if currentTool != .xline { selectTool(.xline) }
        editorView.xlineKind = kind
        toolbarView.setXLineKind(kind)
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    // MARK: Match properties

    func toolbarDidChangeMatchProperties() {
        if currentTool != .matchProperties { selectTool(.matchProperties) }
        statusBar.setPrompt(editorView.prompt)
        updateToolOptionsBar()
        view.window?.makeFirstResponder(editorView)
    }

    // MARK: Dimension style

    func toolbarDidSelectDimArrowStyle(_ style: DimArrowStyle) {
        AppSettings.dimArrowStyle = style
        statusBar.showMessage("New dimensions: \(style.title.lowercased()) · existing ones: select them and change Ends in Properties")
        if ![.dimLinear, .dimAligned, .dimContinue, .dimAngular, .dimRadius, .dimDiameter].contains(currentTool) {
            selectTool(.dimLinear)
        }
        view.window?.makeFirstResponder(editorView)
    }

    func toolbarDidRequestDimensionStyle() {
        dimensionStyle(nil)
    }

    /// Style of new dimensions: terminator, text height and terminator size on paper, decimal places.
    @objc func dimensionStyle(_ sender: Any?) {
        let ends = NSPopUpButton(frame: .zero, pullsDown: false)
        for style in DimArrowStyle.allCases {
            ends.addItem(withTitle: style.title)
            ends.lastItem?.image = ToolIcons.image(for: style, size: 18)
        }
        ends.selectItem(at: DimArrowStyle.allCases.firstIndex(of: AppSettings.dimArrowStyle) ?? 0)
        let height = NSTextField(string: LineType.format(AppSettings.dimTextHeightMM))
        height.toolTip = "Height of capital letters in mm on paper"
        let size = NSTextField(string: LineType.format(AppSettings.dimArrowSizeMM))
        let decimals = NSTextField(string: "\(AppSettings.dimDecimals)")
        for field in [height, size, decimals] { field.widthAnchor.constraint(equalToConstant: 70).isActive = true }
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities()).compactMap { $0 as? DimensionEntity }
        let applyToSelection = NSButton(checkboxWithTitle: "Change also the \(selected.count) selected dimension\(selected.count == 1 ? "" : "s")", target: nil, action: nil)
        applyToSelection.state = selected.isEmpty ? .off : .on
        applyToSelection.isEnabled = !selected.isEmpty
        func unit(_ text: String) -> NSTextField {
            let label = NSTextField(labelWithString: text)
            label.textColor = .secondaryLabelColor
            return label
        }
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Ends:"), ends, NSGridCell.emptyContentView],
            [NSTextField(labelWithString: "Text height:"), height, unit("mm on paper")],
            [NSTextField(labelWithString: "Size of the ends:"), size, unit("mm on paper")],
            [NSTextField(labelWithString: "Decimals:"), decimals, unit("0 = whole numbers")],
            [NSGridCell.emptyContentView, applyToSelection, NSGridCell.emptyContentView]
        ])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame.size = grid.fittingSize

        let alert = NSAlert()
        alert.messageText = "Dimension Style"
        alert.informativeText = "Sizes are on paper – in the drawing they follow the drawing scale (\(editorView.drawingScale.title)), like text."
        alert.accessoryView = grid
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let style = DimArrowStyle.allCases[max(0, ends.indexOfSelectedItem)]
        AppSettings.dimArrowStyle = style
        if let v = ExpressionEvaluator.evaluate(height.stringValue), v > 0 { AppSettings.dimTextHeightMM = CGFloat(v) }
        if let v = ExpressionEvaluator.evaluate(size.stringValue), v > 0 { AppSettings.dimArrowSizeMM = CGFloat(v) }
        if let v = Int(decimals.stringValue.trimmingCharacters(in: .whitespaces)), v >= 0 { AppSettings.dimDecimals = v }
        if applyToSelection.state == .on, !selected.isEmpty {
            let k = editorView.unitsPerPaperMM
            editSelection(actionName: "Change Dimension Style") { entity in
                guard let d = entity as? DimensionEntity, let c = d.clone() as? DimensionEntity else { return nil }
                c.arrowStyle = style
                c.textHeight = AppSettings.dimTextHeightMM * k
                c.arrowSize = AppSettings.dimArrowSizeMM * k
                c.precision = AppSettings.dimDecimals
                return c
            }
        }
        statusBar.showMessage("Dimension style: \(style.title.lowercased()), text \(LineType.format(AppSettings.dimTextHeightMM)) mm on paper")
    }

    func toolbarDidSelectArrayKind(_ kind: ArrayKind) {
        editorView.arrayKind = kind
        toolbarView.setArrayKind(kind)
        if currentTool != .array { selectTool(.array) }
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    @objc func selectArrayKind(_ sender: NSMenuItem) {
        if let kind = ArrayKind(rawValue: sender.tag) { toolbarDidSelectArrayKind(kind) }
    }

    @objc func selectMeasureKind(_ sender: NSMenuItem) {
        if let kind = MeasureKind(rawValue: sender.tag) { toolbarDidSelectMeasureKind(kind) }
    }

    // MARK: Blocks and external references

    /// The next selection of the External Reference tool already has a file (it doesn't ask again).
    private var xrefReady = false
    private var blockManager: BlockManagerController?
    private var xrefTimer: Timer?

    func toolbarBlockDefinitions() -> [BlockDefinition] {
        return activeTab.blocks.blocks + activeTab.blocks.xrefs
    }

    func toolbarCurrentBlock() -> BlockDefinition? {
        return editorView.insertDefinition
    }

    func toolbarDidChooseBlock(_ definition: BlockDefinition) {
        insertBlock(definition)
    }

    /// Inserting a block (or reference) by clicking.
    private func insertBlock(_ definition: BlockDefinition) {
        editorView.insertDefinition = definition
        if definition.isExternal {
            xrefReady = true
            selectTool(.xref)
        } else {
            selectTool(.blockInsert)
        }
        editorView.insertDefinition = definition
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    @objc func insertBlockFromMenu(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let definition = activeTab.blocks.named(name) else { return }
        insertBlock(definition)
    }

    /// How many times the block is used (model, layouts and nested in other blocks).
    private func blockUseCount(_ definition: BlockDefinition) -> Int {
        return activeTab.blocks.useCount(of: definition, in: activeTab.allDocuments.map { $0.getAllEntities() })
    }

    @objc func showBlockManager(_ sender: Any?) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        if let session = activeTab.blockEdit {
            statusBar.showMessage("Finish editing the block \u{201C}\(session.definition.name)\u{201D} first (Save Block Changes or Discard Block Changes)")
            NSSound.beep()
            return
        }
        editorView.cancelCurrentOperation()
        let manager = BlockManagerController(library: activeTab.blocks) { [weak self] definition in
            self?.blockUseCount(definition) ?? 0
        }
        manager.onInsert = { [weak self] definition in self?.insertBlock(definition) }
        manager.onEdit = { [weak self] definition in
            // once the Block Manager sheet closes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.beginBlockEdit(definition: definition, reference: nil)
            }
        }
        manager.onAttach = { [weak self] in
            // once the Block Manager sheet closes
            self?.perform(#selector(MainViewController.attachXref(_:)), with: nil, afterDelay: 0.35)
        }
        manager.onChanged = { [weak self] in
            guard let self = self else { return }
            self.hasUnsavedChanges = true
            self.editorView.needsDisplay = true
            self.refreshProperties()
        }
        blockManager = manager
        manager.show(in: window)
    }

    /// Attaches another drawing as an external reference and lets it be placed by clicking.
    @objc func attachXref(_ sender: Any?) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        editorView.cancelCurrentOperation()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = NativeDrawingFile.openableContentTypes + [UTType(filenameExtension: "dxf") ?? .data]
        panel.message = "Choose the drawing to attach as an external reference – it updates when that file changes"
        panel.prompt = "Attach"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else {
                if self.currentTool == .xref { self.selectTool(.select) }
                return
            }
            if let current = self.currentFileURL, current.standardizedFileURL.path == url.standardizedFileURL.path {
                self.statusBar.showMessage("A drawing cannot be attached to itself.")
                NSSound.beep()
                return
            }
            let library = self.activeTab.blocks
            // the same file a second time = the same reference
            if let existing = library.xrefs.first(where: { $0.source?.path == url.path }) {
                library.reload(existing)
                self.insertBlock(existing)
                return
            }
            let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let source = XrefSource(path: url.path, bookmark: bookmark)
            source.accessedURL = url
            let definition = BlockDefinition(name: library.uniqueName(url.deletingPathExtension().lastPathComponent),
                                             basePoint: .zero, entities: [], source: source)
            definition.entities = XrefLoader.load(source)
            if let error = source.error {
                Log.error("Error Attaching External Reference: \(error)")
                let alert = NSAlert()
                alert.messageText = "Error Attaching External Reference"
                alert.informativeText = error
                alert.alertStyle = .warning
                alert.beginSheetModal(for: window, completionHandler: nil)
                return
            }
            library.add(definition)
            self.hasUnsavedChanges = true
            self.insertBlock(definition)
            self.statusBar.showMessage("External reference “\(definition.name)” – \(definition.entities.count) object\(definition.entities.count == 1 ? "" : "s"). Click where its origin (0,0) goes.")
        }
    }

    // MARK: Image or PDF underlay (ImageUnderlay.swift)

    /// Insert › Attach Image Reference…: a scan, photo or map to trace over (stored inside the drawing).
    @objc func attachImage(_ sender: Any?) {
        chooseUnderlay(for: .image)
    }

    /// Insert › Attach PDF Reference…: a PDF page to trace over (stored inside the drawing).
    @objc func attachPDF(_ sender: Any?) {
        chooseUnderlay(for: .pdfReference)
    }

    /// The file dialog of Image Reference or PDF Reference.
    private func chooseUnderlay(for tool: DrawingTool) {
        guard let window = view.window, window.attachedSheet == nil else { return }
        editorView.cancelCurrentOperation()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = tool == .pdfReference ? [.pdf] : [.image]
        panel.message = tool == .pdfReference ? "Choose a PDF to trace over – it is stored inside the drawing"
                                              : "Choose a scan, photo or map to trace over – it is stored inside the drawing"
        panel.prompt = "Attach"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else {
                if self.currentTool.placesUnderlay { self.selectTool(.select) }
                return
            }
            self.prepareImage(from: url, tool: tool)
        }
    }

    /// Reads the chosen file, asks for its scale (and the page of a PDF) and lets the user click where it goes.
    private func prepareImage(from url: URL, tool: DrawingTool) {
        let name = url.lastPathComponent
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            showImageProblem("“\(name)” could not be read.")
            return
        }
        guard data.count <= ImageSource.maximumFileMB * 1_000_000 else {
            showImageProblem("“\(name)” is larger than \(ImageSource.maximumFileMB) MB. The file is stored inside the drawing – "
                             + "make it smaller first (e.g. a lower resolution or only the page you need).")
            return
        }
        let pages = ImageSource.pageCount(of: data)
        guard let options = askImageOptions(fileName: name, pages: pages) else {
            if currentTool.placesUnderlay { selectTool(.select) }
            return
        }
        guard let source = ImageSource.load(data: data, fileName: name, page: options.page, scale: options.scale) else {
            showImageProblem("“\(name)” is not an image or a PDF that can be read.")
            return
        }
        editorView.pendingImage = source
        selectTool(tool)
        view.window?.makeFirstResponder(editorView)
        statusBar.setPrompt(editorView.prompt)
    }

    /// The scale the picture is drawn at and, for a PDF with more pages, which page. nil = Cancel.
    private func askImageOptions(fileName: String, pages: Int) -> (scale: DrawingScale, page: Int)? {
        let alert = NSAlert()
        alert.messageText = "Attach “\(fileName)”"
        alert.informativeText = "The scale it is drawn at – its size in the drawing is the paper size × this scale"
            + " (a scan of a 1:1000 map → 1:1000; a photo or a picture without a scale – leave it and fit it with Scale)."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        let scaleField = NSTextField(string: editorView.drawingScale.title)
        scaleField.placeholderString = "1:100"
        let pageField = NSTextField(string: "1")
        var rows: [[NSView]] = [[NSTextField(labelWithString: "Scale:"), scaleField]]
        if pages > 1 { rows.append([NSTextField(labelWithString: "Page (1–\(pages)):"), pageField]) }
        for field in [scaleField, pageField] { field.widthAnchor.constraint(equalToConstant: 120).isActive = true }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 6
        grid.frame.size = grid.fittingSize
        alert.accessoryView = grid
        alert.window.initialFirstResponder = scaleField
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let page = Int(pageField.stringValue.trimmingCharacters(in: .whitespaces)) ?? 0
        guard let scale = PlotDialog.parseScale(scaleField.stringValue), pages <= 1 || (1...pages).contains(page) else {
            NSSound.beep()
            statusBar.showMessage("Not attached – type the scale as 1:100 (or just 100)" + (pages > 1 ? " and a page from 1 to \(pages)" : ""))
            return nil
        }
        return (scale, pages > 1 ? page : 1)
    }

    private func showImageProblem(_ text: String) {
        if currentTool.placesUnderlay { selectTool(.select) }
        Log.error("Error Attaching Image or PDF: \(text)")
        let alert = NSAlert()
        alert.messageText = "Error Attaching Image or PDF"
        alert.informativeText = text
        alert.alertStyle = .warning
        if let window = view.window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }

    /// Reloads external references from their files (menu, Properties).
    @objc func reloadXrefs(_ sender: Any?) {
        let xrefs = activeTab.blocks.xrefs
        guard !xrefs.isEmpty else {
            statusBar.showMessage("This drawing has no external references.")
            return
        }
        let failed = xrefs.filter { !activeTab.blocks.reload($0) }
        editorView.needsDisplay = true
        refreshProperties()
        statusBar.showMessage(failed.isEmpty ? "External references reloaded"
                              : "Not loaded: " + failed.map { $0.name }.joined(separator: ", "))
    }

    private func reloadXref(_ definition: BlockDefinition) {
        let ok = activeTab.blocks.reload(definition)
        editorView.needsDisplay = true
        refreshProperties()
        statusBar.showMessage(ok ? "“\(definition.name)” reloaded" : (definition.source?.error ?? "Not loaded"))
    }

    /// External references reload by themselves when their file is saved (checked every 2 s).
    private func startXrefWatcher() {
        xrefTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                for tab in self.tabs where !tab.blocks.xrefs.isEmpty {
                    let changed = tab.blocks.reloadChangedXrefs()
                    guard !changed.isEmpty, tab === self.activeTab else { continue }
                    self.editorView.needsDisplay = true
                    self.refreshProperties()
                    self.statusBar.showMessage("External reference updated: " + changed.map { $0.name }.joined(separator: ", "))
                }
            }
        }
    }

    // MARK: Draw order (pseudo Z)

    /// New order of the selected objects: the function gets (current order, lowest, highest in the drawing).
    private func changeDrawOrder(_ name: String, _ order: (Int, Int, Int) -> Int) {
        let all = document.getAllEntities()
        let lowest = all.map { $0.drawOrder }.min() ?? 0
        let highest = all.map { $0.drawOrder }.max() ?? 0
        let selected = selectionManager.getSelectedEntities(from: all).filter { !layerManager.isLayerLocked($0.layer) }
        guard !selected.isEmpty else {
            statusBar.showMessage("Select at least one object first.")
            NSSound.beep()
            return
        }
        editSelection(actionName: name) { entity in
            let value = order(entity.drawOrder, lowest, highest)
            guard value != entity.drawOrder else { return nil }
            let copy = entity.clone()
            copy.drawOrder = value
            return copy
        }
        let orders = Set(selectionManager.getSelectedEntities(from: document.getAllEntities()).map { $0.drawOrder })
        statusBar.showMessage(orders.count == 1 ? "Draw order \(orders.first!) (higher = on top)" : "Draw order changed")
    }

    @objc func bringToFront(_ sender: Any?) { changeDrawOrder("Bring to Front") { _, _, high in high + 1 } }
    @objc func sendToBack(_ sender: Any?) { changeDrawOrder("Send to Back") { _, low, _ in low - 1 } }
    @objc func bringForward(_ sender: Any?) { changeDrawOrder("Bring Forward") { order, _, _ in order + 1 } }
    @objc func sendBackward(_ sender: Any?) { changeDrawOrder("Send Backward") { order, _, _ in order - 1 } }
    @objc func bringAboveObject(_ sender: Any?) { changeDrawOrder(relativeTo: true) }
    @objc func sendUnderObject(_ sender: Any?) { changeDrawOrder(relativeTo: false) }

    /// Bring Above / Send Under Object: the selection gets the draw order of a clicked object + 1 (above) or − 1 (under).
    private func changeDrawOrder(relativeTo above: Bool) {
        let name = above ? "Bring Above Object" : "Send Under Object"
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
        guard !selected.isEmpty else {
            statusBar.showMessage("Select at least one object first.")
            NSSound.beep()
            return
        }
        let prompt = above ? "Bring Above Object: click the object the selection goes above"
                           : "Send Under Object: click the object the selection goes under"
        editorView.pickObject(prompt: prompt, excluding: Set(selected.map { $0.id })) { [weak self] target in
            guard let target = target else { return }
            let value = target.drawOrder + (above ? 1 : -1)
            self?.changeDrawOrder(name) { _, _, _ in value }
        }
    }

    /// The drawing's context menu (right button held, or Control-click): clipboard, Draw Order and selection
    /// commands of the Edit menu – the same actions, enabled the same way (validateMenuItem).
    private func drawingContextMenu() -> NSMenu {
        let menu = NSMenu()
        @discardableResult
        func add(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                 in parent: NSMenu? = nil) -> NSMenuItem {
            let menuItem = (parent ?? menu).addItem(withTitle: title, action: action, keyEquivalent: key)
            menuItem.keyEquivalentModifierMask = modifiers
            menuItem.target = self
            return menuItem
        }
        add("Cut", #selector(cut(_:)), "x")
        add("Copy", #selector(copy(_:)), "c")
        add("Paste", #selector(paste(_:)), "v")
        add("Paste at Original Coordinates", #selector(pasteAtOriginalCoordinates(_:)), "v", [.command, .shift])
        menu.addItem(.separator())
        add("Delete", #selector(deleteSelection), "\u{8}")
        menu.addItem(.separator())
        let orderMenu = NSMenu()
        menu.addItem(withTitle: "Draw Order", action: nil, keyEquivalent: "").submenu = orderMenu
        add("Bring to Front", #selector(bringToFront(_:)), "f", [.command, .shift], in: orderMenu)
        add("Bring Forward", #selector(bringForward(_:)), "f", [.command, .shift, .option], in: orderMenu)
        add("Send Backward", #selector(sendBackward(_:)), "b", [.command, .shift, .option], in: orderMenu)
        add("Send to Back", #selector(sendToBack(_:)), "b", [.command, .shift], in: orderMenu)
        orderMenu.addItem(.separator())
        add("Bring Above Object", #selector(bringAboveObject(_:)), in: orderMenu)
            .toolTip = "Puts the selection just above an object you click"
        add("Send Under Object", #selector(sendUnderObject(_:)), in: orderMenu)
            .toolTip = "Puts the selection just under an object you click"
        menu.addItem(.separator())
        add("Select All", #selector(selectAllEntities(_:)), "a")
        add("Select Similar", #selector(selectSimilar(_:)), "a", [.command, .shift])
        menu.addItem(.separator())
        // the same descriptions as in the Edit menu
        add("Group", #selector(groupSelection(_:)), "g", [.command, .option])
            .toolTip = "The selected objects become one group – a click on one of them selects them all"
        add("Ungroup", #selector(ungroupSelection(_:)), "g", [.command, .option, .shift])
            .toolTip = "The selected groups fall apart into separate objects"
        return menu
    }

    // MARK: Groups (Groups.swift)

    /// Edit › Group: the selected objects become one group (objects already in a group move to the new one).
    @objc func groupSelection(_ sender: Any?) {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
            .filter { !layerManager.isLayerLocked($0.layer) }
        guard selected.count >= 2 else {
            statusBar.showMessage("Select at least two objects to group them.")
            NSSound.beep()
            return
        }
        let group = UUID()
        editSelection(actionName: "Group") { entity in
            let copy = entity.clone()
            copy.groupID = group
            return copy
        }
        statusBar.showMessage("Group of \(selected.count) objects – a click on one of them selects them all")
    }

    /// Edit › Ungroup: the selected objects leave their groups.
    @objc func ungroupSelection(_ sender: Any?) {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
        let grouped = selected.filter { $0.groupID != nil && !layerManager.isLayerLocked($0.layer) }
        guard !grouped.isEmpty else {
            statusBar.showMessage("The selected objects are not in a group.")
            NSSound.beep()
            return
        }
        let groupCount = Set(grouped.compactMap { $0.groupID }).count
        let others = selected.filter { entity in !grouped.contains { $0 === entity } }
        let freed = grouped.map { entity -> CADEntity in
            let copy = entity.clone()
            copy.groupID = nil
            return copy
        }
        applyChange(removed: grouped, added: freed, actionName: "Ungroup", inheritsGroup: false)
        selectionManager.select(others + freed)
        statusBar.showMessage(groupCount == 1 ? "Group split into \(freed.count) objects" : "\(groupCount) groups split")
        view.window?.makeFirstResponder(editorView)
    }

    /// Edit › Select Groups as a Whole – off, a click selects a single object of a group (to edit it alone).
    @objc func toggleWholeGroups(_ sender: Any?) {
        AppSettings.selectWholeGroups.toggle()
        statusBar.showMessage(AppSettings.selectWholeGroups ? "A click on a grouped object selects the whole group"
                                                            : "A click selects single objects, groups stay")
    }

    func toolbarDidSelectArcMethod(_ method: ArcMethod) {
        editorView.arcMethod = method
        toolbarView.setArcMethod(method)
        if currentTool != .arc { selectTool(.arc) }
        statusBar.setPrompt(editorView.prompt)
        view.window?.makeFirstResponder(editorView)
    }

    // MARK: Document changes with Undo

    /// - Parameter inheritsGroup: false = new objects don't take over the group of the removed ones (Ungroup).
    /// - Parameter inheritsDrawOrder: false = new objects keep their own draw order (edited copies, e.g. Draw Order set to 0).
    func applyChange(removed: [CADEntity], added: [CADEntity], actionName: String, inheritsGroup: Bool = true,
                     inheritsDrawOrder: Bool = true) {
        guard !removed.isEmpty || !added.isEmpty else { return }
        // groups: new pieces stay in the group of their original, copies get a group of their own
        Groups.adjust(added: added, removed: removed, documentEntities: document.getAllEntities(), inheritsGroup: inheritsGroup)
        // new pieces (Trim, Join…) inherit the draw order if all the original objects have the same one
        if inheritsDrawOrder, let order = removed.first?.drawOrder, order != 0, removed.allSatisfy({ $0.drawOrder == order }) {
            for entity in added where entity.drawOrder == 0 { entity.drawOrder = order }
        }
        // associative dimensions move with the objects they are attached to
        let change = Associativity.update(documentEntities: document.getAllEntities(), removed: removed, added: added)
        // room labels measure their room again when the walls around them change (in the same undo step)
        let layers = layerManager
        let rooms = RoomLabels.updates(documentEntities: document.getAllEntities(), removed: change.removed, added: change.added,
                                       isVisible: { layers.isLayerVisible($0.layer) },
                                       unitsPerPaperMM: editorView.unitsPerPaperMM, mmPerUnit: editorView.drawingUnits.mmPerUnit)
        applyBatch(ReplaceBatch(removed: change.removed + rooms.removed, added: change.added + rooms.added, document: document))
        undoer.setActionName(actionName)
        Log.info("Change: \(actionName) (−\(change.removed.count) +\(change.added.count))")
    }

    /// New objects on a hidden or locked current layer: say why they can't be seen or edited.
    private func warnAboutCurrentLayer(added: [CADEntity]) {
        let name = layerManager.currentLayerName
        guard added.contains(where: { $0.layer == name }) else { return }
        if !layerManager.isLayerVisible(name) {
            statusBar.showMessage("Layer \u{201C}\(name)\u{201D} is hidden – the new object is not visible (turn the layer on in the Layers panel)")
        } else if layerManager.isLayerLocked(name) {
            statusBar.showMessage("Layer \u{201C}\(name)\u{201D} is locked – the new object cannot be edited until you unlock the layer")
        }
    }

    @objc private func applyBatch(_ batch: ReplaceBatch) {
        let target = batch.document ?? document
        // Undo/Redo of a change in another space (model ↔ layout) first shows that space
        if target !== document {
            if target === activeTab.document {
                activateSpace(nil)
            } else if let index = activeTab.layouts.firstIndex(where: { $0.document === target }) {
                activateSpace(index)
            }
        }
        perform(batch, on: target)
    }

    /// Applies the change to the document (without switching to its space) and registers its Undo.
    private func perform(_ batch: ReplaceBatch, on target: CADDocument) {
        selectionManager.deselect(batch.removed)
        // the places of the removed objects, so that Undo puts them back where they were
        let anchors = target.orderAnchors(of: batch.removed)
        target.replace(batch.removed, with: batch.added, anchors: batch.addedAnchors)
        let inverse = ReplaceBatch(removed: batch.added, added: batch.removed, document: target, addedAnchors: anchors)
        undoer.registerUndo(withTarget: self, selector: #selector(applyBatch(_:)), object: inverse)
        hasUnsavedChanges = true
    }

    /// Edits the selected objects from the Properties panel: the function returns an edited copy (nil = no change).
    private func editSelection(actionName: String, _ edit: (CADEntity) -> CADEntity?) {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
            .filter { !layerManager.isLayerLocked($0.layer) }
        var removed: [CADEntity] = []
        var added: [CADEntity] = []
        for entity in selected {
            guard let changed = edit(entity) else { continue }
            removed.append(entity)
            added.append(changed)
        }
        guard !removed.isEmpty else {
            refreshProperties()
            return
        }
        let unchanged = selected.filter { entity in !removed.contains { $0 === entity } }
        // the edited copies already carry their draw order – it must not be reset to the original one
        applyChange(removed: removed, added: added, actionName: actionName, inheritsDrawOrder: false)
        selectionManager.select(unchanged + added)
        view.window?.makeFirstResponder(editorView)
    }

    /// Changes a property of the selected objects (via copies, so it can be undone).
    private func changeSelection(actionName: String, _ change: (CADEntity) -> Void) {
        let all = selectionManager.getSelectedEntities(from: document.getAllEntities())
        // objects on locked layers stay as they are (like in editSelection)
        let selected = all.filter { !layerManager.isLayerLocked($0.layer) }
        guard !selected.isEmpty else {
            if !all.isEmpty { statusBar.showMessage("The selected objects are on locked layers – nothing changed.") }
            refreshProperties()
            return
        }
        let changed = selected.map { entity -> CADEntity in
            let copy = entity.clone()
            change(copy)
            return copy
        }
        applyChange(removed: selected, added: changed, actionName: actionName)
        let unchanged = all.filter { entity in !selected.contains { $0 === entity } }
        selectionManager.select(unchanged + changed)
    }

    // MARK: Layers

    /// Selects all objects of a layer (right click in the layer panel).
    private func selectObjects(onLayer name: String) {
        guard let layer = layerManager.getAllLayers().first(where: { $0.name == name }) else { return }
        guard layer.isVisible, !layer.isLocked else {
            statusBar.showMessage("Layer “\(name)” is \(layer.isVisible ? "locked" : "hidden") – its objects cannot be selected.")
            return
        }
        if currentTool != .select { selectTool(.select) }
        let objects = document.getAllEntities().filter { $0.layer == name }
        selectionManager.select(objects)
        statusBar.showMessage("Selected \(objects.count) object\(objects.count == 1 ? "" : "s") on layer “\(name)”")
        view.window?.makeFirstResponder(editorView)
    }

    private func renameLayer(_ oldName: String, to newName: String) {
        guard applyLayerRename(from: oldName, to: newName.trimmingCharacters(in: .whitespaces)) else {
            let alert = NSAlert()
            alert.messageText = "The layer cannot be renamed"
            alert.informativeText = layerManager.getLayer(newName.trimmingCharacters(in: .whitespaces)) != nil
                ? "A layer named “\(newName)” already exists."
                : "The name is empty, or it is layer 0 (which always keeps its name)."
            alert.alertStyle = .warning
            alert.runModal()
            layerPanel.reloadData()
            return
        }
        hasUnsavedChanges = true
        refreshPanels()
        editorView.needsDisplay = true
    }

    /// Renames the layer with its objects. Undoable, so that objects brought back by an older Undo step
    /// find their layer under the name they have.
    @discardableResult
    private func applyLayerRename(from oldName: String, to newName: String) -> Bool {
        guard layerManager.renameLayer(oldName, to: newName) else { return false }
        moveObjects(fromLayer: oldName, toLayer: newName)
        registerLayerUndo(actionName: "Rename Layer") { $0.applyLayerRename(from: newName, to: oldName) }
        return true
    }

    /// Objects in the model, on layouts and inside blocks change their layer name (Rename Layer).
    private func moveObjects(fromLayer oldName: String, toLayer newName: String) {
        // the objects of a block being edited too – they are written back into the block on Save Block Changes
        let contents = activeTab.allDocuments.map { $0.getAllEntities() } + activeTab.blocks.definitions.map { $0.entities }
            + (activeTab.blockEdit.map { [$0.document.getAllEntities()] } ?? [])
        for entities in contents {
            for entity in entities {
                if entity.layer == oldName { entity.layer = newName }
                if let viewport = entity as? ViewportEntity, viewport.frozenLayers.remove(oldName) != nil {
                    viewport.frozenLayers.insert(newName)
                }
            }
        }
        for definition in activeTab.blocks.definitions { definition.contentDidChange() }
    }

    /// A layer change goes into the undo history with the objects, so the steps undo in the right order.
    private func registerLayerUndo(actionName: String, _ undo: @escaping (MainViewController) -> Void) {
        let undoer = activeTab.undoer
        undoer.registerUndo(withTarget: self) { target in
            undo(target)
            target.refreshPanels()
            target.editorView.needsDisplay = true
        }
        undoer.setActionName(actionName)
        hasUnsavedChanges = true
    }

    private func deleteLayer(_ name: String) {
        if name == "0" {
            statusBar.showMessage("Layer 0 cannot be deleted.")
            return
        }
        let count = objects(onLayer: name).count
        if count > 0 {
            let alert = NSAlert()
            alert.messageText = "Do you really want to delete the layer \u{201C}\(name)\u{201D}?"
            alert.informativeText = "It contains \(count) object\(count == 1 ? "" : "s"). \(count == 1 ? "It" : "They") will be moved to the default layer 0."
            alert.addButton(withTitle: "Delete Layer")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        removeLayerUndoably(name)
        if count > 0 {
            refreshPanels()
            editorView.needsDisplay = true
            statusBar.showMessage("Layer \u{201C}\(name)\u{201D} deleted – \(count) object\(count == 1 ? "" : "s") moved to layer 0")
        }
    }

    /// Objects on a layer in the model, on layouts, inside blocks and in a block being edited.
    private func objects(onLayer name: String) -> [CADEntity] {
        let contents = activeTab.allDocuments.map { $0.getAllEntities() } + activeTab.blocks.definitions.map { $0.entities }
            + (activeTab.blockEdit.map { [$0.document.getAllEntities()] } ?? [])
        return contents.flatMap { $0.filter { $0.layer == name } }
    }

    /// Viewports on layouts that hide the layer.
    private func viewports(hidingLayer name: String) -> [ViewportEntity] {
        return activeTab.allDocuments.flatMap { $0.getAllEntities().compactMap { $0 as? ViewportEntity } }
            .filter { $0.frozenLayers.contains(name) }
    }

    /// Deletes the layer; its objects go to layer 0. Undo brings back the layer and its objects in one step.
    private func removeLayerUndoably(_ name: String) {
        let moved = objects(onLayer: name)
        let hiding = viewports(hidingLayer: name)
        guard let layer = layerManager.getLayer(name), layerManager.removeLayer(name) else { return }
        for entity in moved { entity.layer = "0" }
        for viewport in hiding { viewport.frozenLayers.remove(name) }
        if !moved.isEmpty {
            for definition in activeTab.blocks.definitions { definition.contentDidChange() }
        }
        registerLayerUndo(actionName: "Delete Layer") { $0.restoreLayer(layer, objects: moved, hiddenIn: hiding) }
    }

    private func restoreLayer(_ layer: Layer, objects: [CADEntity], hiddenIn viewports: [ViewportEntity]) {
        layerManager.addLayer(layer)
        for entity in objects { entity.layer = layer.name }
        for viewport in viewports { viewport.frozenLayers.insert(layer.name) }
        if !objects.isEmpty {
            for definition in activeTab.blocks.definitions { definition.contentDidChange() }
        }
        registerLayerUndo(actionName: "Delete Layer") { $0.removeLayerUndoably(layer.name) }
    }

    // MARK: Menu – file

    @objc func undoAction(_ sender: Any?) {
        // while drawing ⌘Z takes back only the last point (or the step in progress), not the previous object
        if editorView.undoStepInProgress() { return }
        editorView.cancelCurrentOperation()
        if undoer.canUndo {
            Log.info("Undo: \(undoer.undoActionName)")
            undoer.undo()
        }
    }

    @objc func redoAction(_ sender: Any?) {
        editorView.cancelCurrentOperation()
        if undoer.canRedo {
            Log.info("Redo: \(undoer.redoActionName)")
            undoer.redo()
        }
    }

    /// New drawing – in a new tab.
    @objc func newDocument(_ sender: Any?) {
        newTab(sender)
    }

    /// Open – each file into its own tab (several files can be selected at once).
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = NativeDrawingFile.openableContentTypes + [UTType(filenameExtension: "dxf") ?? .data]
        panel.allowsMultipleSelection = true
        panel.message = "Choose one or more drawings – OreMonoCAD or DXF, each opens in its own tab"
        panel.prompt = "Open"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { self?.openFile(url) }
        }
    }

    /// File › Import…: objects from DXF / .oremono are added to the open drawing (at their coordinates).
    @objc func importDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .data] + NativeDrawingFile.openableContentTypes + [.plainText,
                                     UTType(filenameExtension: "csv") ?? .commaSeparatedText]
        panel.allowsMultipleSelection = true
        panel.message = "Import adds the objects to the open drawing – DXF, OreMonoCAD, or a surveyor's point list (TXT: number Y X Z code)"
        panel.prompt = "Import"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { self?.importFile(url) }
        }
    }

    private func importFile(_ url: URL) {
        Log.info("Import: \(url.lastPathComponent)")
        do {
            let entities: [CADEntity]
            let layers: [Layer]
            let blocks: BlockLibrary
            let units: DrawingUnits?
            let skipped: [String: Int]
            var isSurvey = false
            var unitsMissing = false
            let ext = url.pathExtension.lowercased()
            if ext == "txt" || ext == "csv" {
                // a coordinate list from a surveyor: points in S-JTSK (DXF coordinates = −Y, −X, meters)
                let list = try SurveyPointList.read(from: url)
                let layerName = "Survey points"
                entities = list.map { SurveyPoint(position: CGPoint(x: -$0.y, y: -$0.x), z: $0.z, number: $0.number,
                                                  code: $0.code, layer: layerName) }
                layers = [Layer(name: layerName, color: .systemOrange)]
                blocks = BlockLibrary()
                units = .m
                skipped = [:]
                isSurvey = true
            } else if NativeFormat.isNative(url) {
                let result = try NativeFormat.read(from: url)
                entities = result.entities
                layers = result.layers
                blocks = result.blocks
                units = result.settings?.units.flatMap { DrawingUnits(rawValue: $0) }
                skipped = result.skippedEntityTypes
            } else {
                let result = try DXFReader().read(from: url)
                entities = result.entities
                layers = result.layers
                blocks = result.blocks
                units = result.units
                skipped = result.skippedEntityTypes
                unitsMissing = result.units == nil
            }
            guard !entities.isEmpty else {
                statusBar.showMessage("\(url.lastPathComponent) has no objects to import.")
                return
            }
            // a geodetic survey (S-JTSK in meters)?
            if !isSurvey, units == nil || units == .m { isSurvey = Self.looksLikeSurvey(entities) }
            var surveyTransform: CGAffineTransform?
            if isSurvey {
                guard let placement = askSurveyPlacement(fileName: url.lastPathComponent) else { return }
                if placement {
                    let reference = ensureGeoReference(for: entities)
                    surveyTransform = reference.fromSurveyDXF(metersPerUnit: modelMetersPerUnit)
                } else {
                    // keep the S-JTSK numbers, just meters → drawing units
                    let k = CGFloat(1 / modelMetersPerUnit)
                    surveyTransform = CGAffineTransform(scaleX: k, y: k)
                }
            }

            // layers the drawing doesn't have yet (same-named ones stay as in the drawing)
            let existing = Set(layerManager.getAllLayers().map { $0.name.lowercased() })
            var newLayers = 0
            for layer in layers where !existing.contains(layer.name.lowercased()) {
                layerManager.addLayer(layer)
                newLayers += 1
            }
            // blocks: the same name is already in the drawing → the imported block is renamed
            for definition in blocks.definitions where !activeTab.blocks.definitions.contains(where: { $0 === definition }) {
                if activeTab.blocks.named(definition.name) != nil {
                    definition.name = activeTab.blocks.uniqueName(definition.name)
                }
                activeTab.blocks.add(definition)
            }
            editorView.blockLibrary = activeTab.blocks

            // different units → size conversion
            var note = ""
            if let transform = surveyTransform {
                for entity in entities { entity.applyTransform(transform) }
                note = " · survey in S-JTSK placed by the base point (Format › Geodetic Base Point…)"
            } else if let units = units, units != editorView.drawingUnits {
                let factor = units.mmPerUnit / editorView.drawingUnits.mmPerUnit
                let transform = CGAffineTransform(scaleX: factor, y: factor)
                for entity in entities { entity.applyTransform(transform) }
                note = " · scaled from \(units.suffix) to \(editorView.drawingUnits.suffix)"
            } else if unitsMissing {
                note = " · no known units in the file – read as \(editorView.drawingUnits.suffix)"
            }

            if currentTool != .select { selectTool(.select) }
            applyChange(removed: [], added: entities, actionName: "Import")
            // nothing stays selected after an import (a large DXF would otherwise show all highlighted)
            selectionManager.clearSelection()
            // show the drawing including the import
            editorView.viewport.zoomToFit(entities: document.getAllEntities())
            editorView.needsDisplay = true
            refreshPanels()

            var message = "Imported \(entities.count) object\(entities.count == 1 ? "" : "s") from \(url.lastPathComponent)\(note)"
            if newLayers > 0 { message += " · \(newLayers) new layer\(newLayers == 1 ? "" : "s")" }
            if !skipped.isEmpty {
                message += " · not supported yet: " + skipped.keys.sorted().map { "\($0) ×\(skipped[$0]!)" }.joined(separator: ", ")
            }
            statusBar.showMessage(message)
        } catch {
            showError(title: "Error Importing File", error: error)
        }
    }

    // MARK: Geodetic survey (S-JTSK)

    /// Meters per model unit.
    private var modelMetersPerUnit: Double {
        return Double(activeTab.units.mmPerUnit) / 1000
    }

    /// Do most objects lie within the S-JTSK extent (DXF coordinates in meters, negative numbers)?
    static func looksLikeSurvey(_ entities: [CADEntity]) -> Bool {
        let sample = entities.prefix(400)
        var inside = 0, counted = 0
        for entity in sample {
            let box = entity.boundingBox()
            guard !box.isNull, box.midX.isFinite, box.midY.isFinite else { continue }
            counted += 1
            if GeoReference.looksLikeSurveyDXF(CGPoint(x: box.midX, y: box.midY)) { inside += 1 }
        }
        return counted > 0 && Double(inside) / Double(counted) > 0.8
    }

    /// true = place by the base point, false = keep S-JTSK, nil = cancel.
    private func askSurveyPlacement(fileName: String) -> Bool? {
        let alert = NSAlert()
        alert.messageText = "Geodetic Survey in S-JTSK"
        let hasReference = activeTab.geoReference != nil
        alert.informativeText = "\(fileName) uses S-JTSK coordinates in meters.\n\n"
            + (hasReference
               ? "Place at Base Point puts it into your drawing by the geodetic base point already set."
               : "Place at Base Point puts it around 0,0 of your drawing and sets the geodetic base point from it (Format › Geodetic Base Point… shows or changes it).")
            + "\n\nKeep S-JTSK Coordinates leaves the large numbers as they are."
        alert.addButton(withTitle: "Place at Base Point")
        alert.addButton(withTitle: "Keep S-JTSK Coordinates")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    /// The drawing's base point; when there is none yet, it is created from the survey center (whole meters → 0,0 of the drawing).
    private func ensureGeoReference(for surveyEntities: [CADEntity]) -> GeoReference {
        if let existing = activeTab.geoReference { return existing }
        var box = CGRect.null
        for entity in surveyEntities { box = box.union(entity.boundingBox()) }
        var reference = GeoReference()
        if !box.isNull {
            reference.y = (-Double(box.midX)).rounded()
            reference.x = (-Double(box.midY)).rounded()
        }
        activeTab.geoReference = reference
        markSettingsChanged()
        updateStatusBar()
        return reference
    }

    /// Format › Geodetic Base Point…: drawing point ↔ Y, X in S-JTSK and the ±0.000 elevation.
    @objc func editGeoReference(_ sender: Any?) {
        showGeoReferenceDialog(local: nil)
    }

    private func showGeoReferenceDialog(local picked: CGPoint?) {
        let reference = activeTab.geoReference ?? GeoReference()
        let mpu = modelMetersPerUnit
        let local = picked ?? reference.local
        // for a selected point pre-fill S-JTSK from the current tie (the coordinates keep matching)
        let geo: (y: Double, x: Double) = picked.map { reference.jtsk(of: $0, metersPerUnit: mpu) } ?? (y: reference.y, x: reference.x)

        let alert = NSAlert()
        alert.messageText = "Geodetic Base Point"
        alert.informativeText = "Which point of your drawing lies where in S-JTSK (meters, as the surveyor writes Y and X). "
            + "The drawing stays north-up – rotate only the view or the drawing coordinates."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Pick in Drawing…")
        if activeTab.geoReference != nil { alert.addButton(withTitle: "Remove") }

        let unit = activeTab.units.suffix
        func field(_ value: String) -> NSTextField {
            let f = NSTextField(string: value)
            f.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            f.widthAnchor.constraint(equalToConstant: 150).isActive = true
            return f
        }
        let localX = field(LineType.format(local.x)), localY = field(LineType.format(local.y))
        let jtskY = field(GeoReference.format(geo.y)), jtskX = field(GeoReference.format(geo.x))
        let zero = field(reference.heightZero.map { GeoReference.format($0) } ?? "")
        zero.placeholderString = "optional, e.g. 605.100"
        let rows: [(String, NSView)] = [("Drawing X (\(unit))", localX), ("Drawing Y (\(unit))", localY),
                                         ("S-JTSK Y (m)", jtskY), ("S-JTSK X (m)", jtskX), ("±0.000 = (m Bpv)", zero)]
        let grid = NSGridView(views: rows.map { [NSTextField(labelWithString: $0.0), $0.1] })
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 150)
        alert.accessoryView = grid
        alert.window.initialFirstResponder = jtskY

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            func value(_ f: NSTextField) -> Double? {
                let text = f.stringValue.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")
                return text.isEmpty ? nil : ExpressionEvaluator.evaluate(text)
            }
            guard let lx = value(localX), let ly = value(localY), let y = value(jtskY), let x = value(jtskX) else {
                NSSound.beep()
                statusBar.showMessage("Base point not changed – fill in the drawing point and S-JTSK Y and X.")
                return
            }
            activeTab.geoReference = GeoReference(local: CGPoint(x: lx, y: ly), y: y, x: x, heightZero: value(zero))
            markSettingsChanged()
            updateStatusBar()
            refreshProperties()
            statusBar.showMessage("Geodetic base point set: drawing \(LineType.format(lx)), \(LineType.format(ly)) = S-JTSK Y \(GeoReference.format(y)), X \(GeoReference.format(x))"
                                  + " · click the coordinates in the status bar to show S-JTSK")
        case .alertThirdButtonReturn:
            if activeTab.activeLayout != nil { activateSpace(nil) }
            if currentTool != .select { selectTool(.select) }
            editorView.pickAxis(byObject: false, prompt: "Geodetic Base Point: click the point in the drawing", singlePoint: true) { [weak self] result in
                guard let self = self else { return }
                DispatchQueue.main.async { self.showGeoReferenceDialog(local: result?.origin) }
            }
        case NSApplication.ModalResponse(rawValue: NSApplication.ModalResponse.alertThirdButtonReturn.rawValue + 1):
            activeTab.geoReference = nil
            markSettingsChanged()
            updateStatusBar()
            statusBar.showMessage("Geodetic base point removed – drawing coordinates in meters are read as −Y, −X")
        default:
            break
        }
    }

    /// Coordinates in the status line: project, or S-JTSK (clicking them toggles).
    private var showsJTSK = false

    private func toggleCoordinateDisplay() {
        showsJTSK.toggle()
        statusBar.showMessage(showsJTSK ? "Coordinates in S-JTSK (Y, X in meters) – click them again for drawing coordinates"
                                        : "Drawing coordinates")
    }

    private func showCursorCoordinates(_ point: CGPoint) {
        if showsJTSK && activeTab.activeLayout == nil {
            let reference = activeTab.geoReference ?? GeoReference.identity
            let geo = reference.jtsk(of: point, metersPerUnit: modelMetersPerUnit)
            statusBar.setCoordinateText(String(format: "Y: %.3f  X: %.3f  m S-JTSK", geo.y, geo.x))
        } else {
            statusBar.setCoordinates(editorView.toUCS(point), unit: coordinateSuffix)
        }
    }

    /// File › Export DXF in S-JTSK…: the model in meters and surveyor coordinates (−Y, −X).
    @objc func exportSurveyDXF(_ sender: Any?) {
        guard ensureNoBlockEdit() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .data]
        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? activeTab.title
        panel.nameFieldStringValue = baseName + " S-JTSK.dxf"
        panel.message = activeTab.geoReference == nil
            ? "No geodetic base point is set – the drawing is exported as if its coordinates were already S-JTSK"
            : "The model in S-JTSK, meters – for the surveyor or the cadastral map"
        panel.prompt = "Export"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            let reference = self.activeTab.geoReference ?? GeoReference.identity
            let transform = reference.toSurveyDXF(metersPerUnit: self.modelMetersPerUnit)
            let copy = CADDocument()
            for entity in self.activeTab.document.getAllEntities() {
                let moved = entity.clone()
                moved.applyTransform(transform)
                copy.addEntity(moved)
            }
            do {
                try DXFWriter().write(document: copy, layerManager: self.layerManager, units: .m, to: url)
                self.statusBar.showMessage("Exported \(url.lastPathComponent) in S-JTSK (meters)")
            } catch {
                self.showError(title: "Error Exporting DXF", error: error)
            }
        }
    }

    /// Loads a file into the active tab. true = it succeeded.
    @discardableResult
    private func loadDocument(from url: URL) -> Bool {
        if NativeFormat.isNative(url) {
            return loadNativeDocument(from: url)
        }
        do {
            let result = try DXFReader().read(from: url)
            replaceDocument(with: result.entities, layers: result.layers, url: url)
            activeTab.blocks = result.blocks
            connectManagers()
            var unitsNote = ""
            if let units = result.units {
                editorView.drawingUnits = units
                activeTab.units = units
                updateModes()
            } else if Self.looksLikeSurvey(result.entities) {
                // geodetic survey: drawing in meters, S-JTSK coordinates (−Y, −X)
                editorView.drawingUnits = .m
                activeTab.units = .m
                updateModes()
                showsJTSK = true
            } else {
                unitsNote = " · no known units in the file – read as \(editorView.drawingUnits.suffix)"
            }
            editorView.viewport.zoomToFit(entities: document.getAllEntities())

            var message = "Opened \(url.lastPathComponent): \(result.entities.count) object\(result.entities.count == 1 ? "" : "s")" + unitsNote
            if !result.skippedEntityTypes.isEmpty {
                let skipped = result.skippedEntityTypes.keys.sorted()
                    .map { "\($0) ×\(result.skippedEntityTypes[$0]!)" }
                    .joined(separator: ", ")
                message += " · not supported yet: \(skipped)"
            }
            statusBar.showMessage(message)
            noteRecent(url)
            return true
        } catch {
            showError(title: "Error Opening File", error: error)
            return false
        }
    }

    /// quietly = recovery / backup: no “Opened…” message and no entry in Open Recent.
    private func loadNativeDocument(from url: URL, quietly: Bool = false) -> Bool {
        do {
            let result = try NativeFormat.read(from: url)
            replaceDocument(with: result.entities, layers: result.layers, url: url)
            activeTab.blocks = result.blocks
            connectManagers()
            // external references: objects from their files
            let missing = result.blocks.xrefs.filter { !result.blocks.reload($0) }
            if !missing.isEmpty {
                statusBar.showMessage("External reference\(missing.count == 1 ? "" : "s") not loaded: " + missing.map { $0.name }.joined(separator: ", ")
                                      + " – Block Manager › Browse… finds them")
            }
            applySettings(result.settings)
            if let current = result.currentLayer { _ = layerManager.setCurrentLayer(current) }
            hasUnsavedChanges = false      // restoring the saved current layer is not a change
            if let zoom = result.settings?.viewZoom, let pan = result.settings?.viewPan {
                editorView.viewport.viewState = (zoom, pan)
            } else {
                editorView.viewport.zoomToFit(entities: document.getAllEntities())
            }
            activeTab.layouts = result.layouts
            activeTab.namedViews = result.namedViews
            activeTab.pageSetups = result.pageSetups
            activeTab.modelPlotSettings = result.modelPlot
            syncViewportUnits(activeTab)
            refreshLayoutBar()
            refreshPanels()
            updateModes()
            editorView.needsDisplay = true
            if let active = result.activeLayout { activateSpace(active) }

            var message = "Opened \(url.lastPathComponent): \(result.entities.count) object\(result.entities.count == 1 ? "" : "s")"
            if !result.skippedEntityTypes.isEmpty {
                let skipped = result.skippedEntityTypes.keys.sorted()
                    .map { "\($0) ×\(result.skippedEntityTypes[$0]!)" }
                    .joined(separator: ", ")
                message += " · skipped (unknown or damaged): \(skipped)"
            }
            if quietly {
                if !result.skippedEntityTypes.isEmpty { Log.warning(message) }
            } else {
                statusBar.showMessage(message)
                noteRecent(url)
            }
            return true
        } catch {
            showError(title: "Error Opening File", error: error)
            return false
        }
    }

    /// Drawing settings for the drawing file.
    private func currentSettings() -> DrawingSettingsRecord {
        return settings(for: activeTab)
    }

    /// Drawing settings of any tab (an inactive tab keeps its state inside itself).
    private func settings(for tab: DrawingTab) -> DrawingSettingsRecord {
        let isActive = tab === activeTab
        if isActive { storeActiveTabState() }
        let view = tab.viewState ?? (isActive ? editorView.viewport.viewState : (zoom: CGFloat(1), pan: CGPoint.zero))
        return DrawingSettingsRecord(scalePaper: tab.drawingScale.paper,
                                     scaleModel: tab.drawingScale.model,
                                     showLineWeights: tab.showLineWeights,
                                     lineWeightOnScreen: tab.lineWeightOnScreen,
                                     smoothLines: nil,
                                     hatchPattern: HatchPatternRecord(tab.hatchPattern),
                                     hatchAngle: tab.hatchAngle,
                                     hatchScale: tab.hatchScale,
                                     viewZoom: view.zoom,
                                     viewPan: view.pan,
                                     units: tab.units.rawValue,
                                     gridSize: tab.gridSize,
                                     polarIncrement: tab.polarIncrement,
                                     viewRotation: tab.viewRotation == 0 ? nil : tab.viewRotation,
                                     ucsAngle: tab.ucsAngle == 0 ? nil : tab.ucsAngle,
                                     ucsOrigin: tab.ucsOrigin == .zero ? nil : tab.ucsOrigin,
                                     geoLocal: tab.geoReference?.local,
                                     geoY: tab.geoReference?.y,
                                     geoX: tab.geoReference?.x,
                                     geoHeightZero: tab.geoReference?.heightZero,
                                     showGrid: tab.showGrid,
                                     showAxes: tab.showAxes)
    }

    private func applySettings(_ settings: DrawingSettingsRecord?) {
        // older drawings and drawings without settings follow the app setting
        editorView.showGrid = settings?.showGrid ?? AppSettings.showGrid
        editorView.showAxes = settings?.showAxes ?? AppSettings.showAxes
        guard let settings = settings else { return }
        if let paper = settings.scalePaper, let model = settings.scaleModel, paper > 0, model > 0 {
            editorView.drawingScale = DrawingScale(paper: paper, model: model)
        }
        if let value = settings.showLineWeights { editorView.showLineWeights = value }
        if let value = settings.lineWeightOnScreen { editorView.lineWeightOnScreen = value }
        if let pattern = settings.hatchPattern {
            editorView.hatchPattern = pattern.pattern
            toolbarView.setHatchPattern(editorView.hatchPattern)
        }
        if let angle = settings.hatchAngle { editorView.hatchAngle = angle }
        editorView.hatchScale = settings.hatchScale
        if let raw = settings.units, let units = DrawingUnits(rawValue: raw) {
            editorView.drawingUnits = units
            activeTab.units = units
        }
        if let size = settings.gridSize, size > 0 { editorView.gridSize = size }
        if let step = settings.polarIncrement, step > 0 { editorView.polarIncrement = step }
        if let y = settings.geoY, let x = settings.geoX {
            activeTab.geoReference = GeoReference(local: settings.geoLocal ?? .zero, y: y, x: x, heightZero: settings.geoHeightZero)
        } else {
            activeTab.geoReference = nil
        }
        activeTab.viewRotation = settings.viewRotation ?? 0
        activeTab.ucsAngle = settings.ucsAngle ?? 0
        activeTab.ucsOrigin = settings.ucsOrigin ?? .zero
        if activeTab.activeLayout == nil {
            editorView.viewport.restoreRotation(activeTab.viewRotation)
            editorView.ucsAngle = activeTab.ucsAngle
            editorView.ucsOrigin = activeTab.ucsOrigin
        }
    }

    private func replaceDocument(with entities: [CADEntity], layers: [Layer]?, url: URL?) {
        editorView.cancelCurrentOperation()
        selectionManager.clearSelection()
        activeTab.layouts = []
        activeTab.activeLayoutIndex = nil
        activeTab.pageSetups = []
        activeTab.modelPlotSettings = nil
        editorView.paperSpace = nil
        activeTab.document = CADDocument()
        activeTab.blocks = BlockLibrary()
        activeTab.namedViews = []
        // new drawing: view and drawing coordinates unrotated, no geodetic point
        activeTab.geoReference = nil
        activeTab.viewRotation = 0
        activeTab.ucsAngle = 0
        activeTab.ucsOrigin = .zero
        editorView.viewport.restoreRotation(0)
        editorView.ucsAngle = 0
        editorView.ucsOrigin = .zero
        for entity in entities { document.addEntity(entity) }
        layerManager.reset(with: layers ?? [])

        connectManagers()
        setupCallbacks()
        undoer.removeAllActions()
        selectTool(.select)

        currentFileURL = url
        hasUnsavedChanges = false
        updateWindowTitle()
        refreshPanels()
        updateStatusBar()
        refreshLayoutBar()
        editorView.needsDisplay = true
    }

    @objc func saveDocument(_ sender: Any?) {
        guard ensureNoBlockEdit() else { return }
        // Saving goes only to the native format – an opened DXF is not overwritten (DXF can't hold everything), Save As is offered.
        if let url = currentFileURL, NativeFormat.isNative(url) {
            save(to: url)
        } else {
            saveDocumentAs(sender)
        }
    }

    @objc func saveDocumentAs(_ sender: Any?) {
        guard ensureNoBlockEdit() else { return }
        let panel = makeSavePanel()
        guard let window = view.window else { return }
        let tab = activeTab
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            // the tab Save As was invoked from is saved
            if let index = self.tabs.firstIndex(where: { $0 === tab }) { self.activateTab(index) }
            self.save(to: url)
        }
    }

    private func makeSavePanel() -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [NativeDrawingFile.contentType]
        let tab = activeTab
        // recovered drawing / opened backup: offer the original location and name (the system confirms overwriting)
        let baseName = tab.suggestedSaveURL?.deletingPathExtension().lastPathComponent
            ?? currentFileURL?.deletingPathExtension().lastPathComponent
            ?? tab.suggestedName ?? tab.title
        if let suggested = tab.suggestedSaveURL {
            panel.directoryURL = suggested.deletingLastPathComponent()
        }
        panel.nameFieldStringValue = baseName + "." + NativeDrawingFile.fileExtension
        panel.message = "OreMonoCAD drawing – keeps everything (to share with other CAD apps use File › Export DXF…)"
        panel.prompt = "Save"
        return panel
    }

    @discardableResult
    private func save(to url: URL) -> Bool {
        Log.info("Save: \(url.lastPathComponent) (\(activeTab.document.getAllEntities().count) objects)")
        // stash the previous version of the file among the backups (at most once per 10 minutes)
        BackupStore.backUpBeforeOverwriting(url)
        do {
            let settings = currentSettings()
            let tab = activeTab
            tab.restoreReferencedBlocks()
            try NativeFormat.write(entities: tab.document.getAllEntities(),
                                   layers: layerManager.getAllLayers(),
                                   currentLayer: layerManager.currentLayerName,
                                   settings: settings,
                                   layouts: tab.layouts,
                                   activeLayout: tab.activeLayoutIndex,
                                   pageSetups: tab.pageSetups,
                                   modelPlot: tab.modelPlotSettings,
                                   blocks: tab.blocks,
                                   namedViews: tab.namedViews,
                                   to: url)
            currentFileURL = url
            tab.customTitle = nil
            tab.suggestedSaveURL = nil
            tab.suggestedName = nil
            hasUnsavedChanges = false
            refreshTabBar()
            updateWindowTitle()
            statusBar.showMessage("Saved \(url.lastPathComponent)")
            noteRecent(url)
            return true
        } catch {
            showError(title: "Error Saving File", error: error)
            return false
        }
    }

    /// Export to DXF (for exchange with other CAD programs). The drawing stays saved in its own file.
    @objc func exportDXF(_ sender: Any?) {
        guard ensureNoBlockEdit() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "dxf") ?? .data]
        let baseName = currentFileURL?.deletingPathExtension().lastPathComponent ?? activeTab.title
        panel.nameFieldStringValue = baseName + ".dxf"
        panel.message = "DXF does not keep everything (exact colors, hatch patterns, printable layers, layouts…)"
        panel.prompt = "Export"
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            do {
                try DXFWriter().write(document: self.activeTab.document, layerManager: self.layerManager,
                                      units: self.modelUnits, to: url)
                self.statusBar.showMessage("Exported \(url.lastPathComponent)")
            } catch {
                self.showError(title: "Error Exporting DXF", error: error)
            }
        }
    }

    // MARK: Plot, PDF and images

    private var plotDialog: PlotDialog?

    /// Units and scale of the model (on a layout the editor draws in mm 1:1, the tab keeps the model's).
    private var modelUnits: DrawingUnits {
        return activeTab.activeLayout == nil ? editorView.drawingUnits : activeTab.units
    }

    private var modelScale: DrawingScale {
        return activeTab.activeLayout == nil ? editorView.drawingScale : activeTab.drawingScale
    }

    /// Bounds of the visible model.
    private func modelExtents() -> CGRect? {
        let box = activeTab.document.getAllEntities()
            .filter { layerManager.isLayerVisible($0.layer) }
            .reduce(CGRect.null) { $0.union($1.boundingBox()) }
        return box.isNull || !box.width.isFinite || !box.height.isFinite ? nil : box
    }

    private func makePlotSource() -> PlotSource {
        let tab = activeTab
        let a = editorView.viewport.screenToWorld(.zero)
        let b = editorView.viewport.screenToWorld(CGPoint(x: editorView.bounds.width, y: editorView.bounds.height))
        let display = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        syncViewportUnits(tab, mmPerUnit: modelUnits.mmPerUnit)
        return PlotSource(model: tab.document.getAllEntities(), layerManager: layerManager,
                          modelMMPerUnit: modelUnits.mmPerUnit, drawingScale: modelScale,
                          layout: tab.activeLayout, displayRect: display, title: plotTitle)
    }

    private var plotTitle: String {
        if let layout = activeTab.activeLayout { return "\(activeTab.title) – \(layout.name)" }
        return activeTab.title
    }

    private func defaultPlotSettings() -> PlotSettings {
        var s = PlotSettings()
        if let layout = activeTab.activeLayout {
            s.area = "layout"
            s.paper = layout.paper.rawValue
            s.orientation = layout.landscape ? 2 : 1
            s.marginMM = layout.marginMM
        } else {
            s.area = "extents"
            s.paper = PaperSize.a4.rawValue
            s.fitToPaper = true
            s.scalePaper = modelScale.paper
            s.scaleModel = modelScale.model
        }
        return s
    }

    private func rememberPlotSettings(_ settings: PlotSettings, for tab: DrawingTab, layout: DrawingLayout?) {
        if let layout = layout { layout.plotSettings = settings } else { tab.modelPlotSettings = settings }
    }

    /// File › Plot / Print… / Export PDF… / Export Image… – all through the Plot dialog.
    @objc func printDrawing(_ sender: Any?) {
        showPlotDialog(device: nil)
    }

    @objc func exportPDF(_ sender: Any?) {
        showPlotDialog(device: "pdf")
    }

    @objc func exportImage(_ sender: Any?) {
        let current = activeTab.activeLayout?.plotSettings ?? (activeTab.activeLayout == nil ? activeTab.modelPlotSettings : nil)
        showPlotDialog(device: current?.rasterFormat != nil ? current?.device : "png")
    }

    func showPlotDialog(device: String?, initial: PlotSettings? = nil) {
        guard let window = view.window, plotDialog == nil else { return }
        guard ensureNoBlockEdit() else { return }
        editorView.cancelCurrentOperation()
        let tab = activeTab
        let layout = tab.activeLayout
        var settings = initial ?? layout?.plotSettings ?? (layout == nil ? tab.modelPlotSettings : nil) ?? defaultPlotSettings()
        if let device = device {
            settings.device = device
            if device != "printer" { settings.printerName = nil }
        }
        if settings.area == "layout" && layout == nil { settings.area = "extents" }
        let source = makePlotSource()
        let dialog = PlotDialog(settings: settings, source: source, pageSetups: tab.pageSetups) { [weak self, weak tab] setups in
            tab?.pageSetups = setups
            if tab === self?.activeTab { self?.hasUnsavedChanges = true }
        }
        plotDialog = dialog
        dialog.begin(for: window) { [weak self, weak tab] result in
            guard let self = self, let tab = tab else { return }
            self.plotDialog = nil
            switch result {
            case .cancel(let s):
                self.rememberPlotSettings(s, for: tab, layout: layout)
            case .plot(let s):
                self.rememberPlotSettings(s, for: tab, layout: layout)
                DispatchQueue.main.async { self.performPlot(s, source: source) }
            case .pickWindow(let s):
                self.rememberPlotSettings(s, for: tab, layout: layout)
                DispatchQueue.main.async {
                    self.statusBar.showMessage("Plot window: click two corners · Esc returns to the Plot dialog")
                    self.editorView.pickRectangle(prompt: "Plot window: click the first corner") { [weak controller = self] rect in
                        var picked = s
                        if let rect = rect {
                            picked.window = rect
                            picked.area = "window"
                        }
                        // back to the dialog – only when the same drawing and space are still open
                        DispatchQueue.main.async {
                            guard let controller = controller, tab === controller.activeTab, layout === tab.activeLayout else { return }
                            controller.showPlotDialog(device: nil, initial: picked)
                        }
                    }
                }
            }
        }
    }

    private func plotFileName(for settings: PlotSettings) -> String {
        var base = currentFileURL?.deletingPathExtension().lastPathComponent ?? activeTab.title
        if let layout = activeTab.activeLayout { base += " - " + layout.name }
        return base + "." + (settings.rasterFormat?.fileExtension ?? "pdf")
    }

    private func performPlot(_ settings: PlotSettings, source: PlotSource) {
        guard let window = view.window else { return }
        if settings.device == "printer" {
            do {
                let plan = try PlotRenderer.makePlan(settings, source)
                let info = PlotDialog.makePrintInfo(settings, plan: plan)
                var imageable = info.imageablePageBounds
                if imageable.width < 1 || imageable.height < 1 { imageable = CGRect(origin: .zero, size: plan.pageSize) }
                info.leftMargin = imageable.minX
                info.bottomMargin = imageable.minY
                info.rightMargin = max(0, plan.pageSize.width - imageable.maxX)
                info.topMargin = max(0, plan.pageSize.height - imageable.maxY)
                let page = PlotPageView(plan: plan, settings: settings, source: source, imageable: imageable)
                let operation = NSPrintOperation(view: page, printInfo: info)
                operation.showsPrintPanel = settings.showSystemDialog
                operation.showsProgressPanel = true
                operation.jobTitle = source.title
                operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                statusBar.showMessage("Sent to \(settings.printerName ?? "the printer")")
            } catch {
                showError(title: "Error Plotting", error: error)
            }
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [settings.rasterFormat?.contentType ?? .pdf]
        panel.nameFieldStringValue = plotFileName(for: settings)
        panel.message = settings.rasterFormat == nil ? "Vector PDF" : "\(settings.rasterFormat!.title) image at \(Int(settings.dpi)) dpi"
        panel.prompt = "Export"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            do {
                if settings.rasterFormat != nil {
                    let result = try PlotRenderer.rasterData(settings, source)
                    try result.data.write(to: url, options: .atomic)
                    let reduced = result.dpi < settings.dpi - 0.5 ? " – reduced to \(Int(result.dpi)) dpi (very large image)" : ""
                    self.statusBar.showMessage("Saved \(url.lastPathComponent) (\(Int(result.size.width)) × \(Int(result.size.height)) px)\(reduced)")
                } else {
                    try PlotRenderer.pdfData(settings, source).write(to: url, options: .atomic)
                    self.statusBar.showMessage("Saved \(url.lastPathComponent)")
                }
            } catch {
                self.showError(title: settings.rasterFormat == nil ? "Error Exporting PDF" : "Error Exporting Image", error: error)
            }
        }
    }

    // MARK: Layouts

    private var layoutBar: LayoutBarView!

    private func setupLayoutBar() {
        layoutBar.onSelect = { [weak self] index in self?.activateSpace(index) }
        layoutBar.onAdd = { [weak self] in self?.newLayout(nil) }
        layoutBar.onRename = { [weak self] index in self?.renameLayout(at: index) }
        layoutBar.onDuplicate = { [weak self] index in self?.duplicateLayout(at: index) }
        layoutBar.onDelete = { [weak self] index in self?.deleteLayout(at: index) }
        layoutBar.onPageSetup = { [weak self] index in self?.layoutPageSetup(at: index) }
        layoutBar.onAddViewport = { [weak self] index in
            self?.activateSpace(index)
            self?.addViewport(nil)
        }
        layoutBar.onMove = { [weak self] from, to in self?.moveLayout(from: from, to: to) }
        layoutBar.onPlot = { [weak self] index in
            self?.activateSpace(index)
            self?.printDrawing(nil)
        }
        refreshLayoutBar()
    }

    private func refreshLayoutBar() {
        let tab = activeTab
        layoutBar?.update(layoutNames: tab.layouts.map { $0.name }, selected: tab.activeLayoutIndex,
                          toolTips: tab.layouts.map { "\($0.name) – \($0.paperDescription)\nDouble-click to rename · right-click for page setup, viewports, plot" })
    }

    /// Viewports need to know how many mm a model unit is.
    private func syncViewportUnits(_ tab: DrawingTab, mmPerUnit: CGFloat? = nil) {
        let mm = mmPerUnit ?? (tab === activeTab ? modelUnits.mmPerUnit : tab.units.mmPerUnit)
        for layout in tab.layouts {
            for viewport in layout.viewports { viewport.mmPerUnit = mm }
        }
    }

    /// Sets up the drawing area according to the active tab's space (model / layout).
    private func applySpace() {
        let tab = activeTab
        syncViewportUnits(tab, mmPerUnit: tab.units.mmPerUnit)
        if let layout = tab.activeLayout {
            // a layout is not rotated
            editorView.viewport.restoreRotation(0)
            editorView.ucsAngle = 0
            editorView.ucsOrigin = .zero
            editorView.drawingUnits = .mm
            editorView.drawingScale = DrawingScale(paper: 1, model: 1)
            editorView.gridSize = layout.gridSize
            refreshPaperSpace()
            if let state = layout.viewState {
                editorView.viewport.viewState = state
            } else {
                editorView.zoomToPaper()
            }
        } else {
            editorView.paperSpace = nil
            editorView.viewport.restoreRotation(tab.viewRotation)
            editorView.ucsAngle = tab.ucsAngle
            editorView.ucsOrigin = tab.ucsOrigin
        }
        refreshLayoutBar()
        updateStatusBar()
    }

    private func refreshPaperSpace() {
        let tab = activeTab
        guard let layout = tab.activeLayout else { editorView.paperSpace = nil; return }
        editorView.paperSpace = CADEditorView.PaperSpace(paperRect: layout.paperRect, printableRect: layout.printableRect,
                                                         model: { [weak tab] in tab?.document.getAllEntities() ?? [] },
                                                         modelMMPerUnit: tab.units.mmPerUnit)
    }

    /// Switches to the model (nil) or to a layout.
    func activateSpace(_ index: Int?) {
        let tab = activeTab
        guard index != tab.activeLayoutIndex else { return }
        guard ensureNoBlockEdit() else { return }
        if let index = index, !tab.layouts.indices.contains(index) { return }
        editorView.cancelCurrentOperation()
        storeActiveTabState()
        selectionManager.clearSelection()
        tab.activeLayoutIndex = index
        restoreActiveTabState()
        statusBar.showMessage(tab.activeLayout.map { "\($0.name) – \($0.paperDescription) · draw on the sheet in mm" } ?? "Model")
    }

    @objc func showModelSpace(_ sender: Any?) {
        activateSpace(nil)
    }

    @objc func showLayoutFromMenu(_ sender: NSMenuItem) {
        activateSpace(sender.tag)
    }

    /// New viewport: a rectangle on paper, the whole model at the largest standard scale that fits.
    private func makeViewport(rect: CGRect) -> ViewportEntity {
        let tab = activeTab
        let mm = tab.units.mmPerUnit
        let box = modelExtents()
        let scale = box.map { ViewportEntity.fittingScale(for: $0, in: rect, mmPerUnit: mm) } ?? tab.drawingScale
        if layerManager.getLayer("Viewports") == nil {
            // viewports on their own non-plotting layer (“Defpoints”, as DXF files expect) – the frames are not plotted
            let current = layerManager.currentLayerName
            layerManager.addLayer(Layer(name: "Viewports", color: NSColor(white: 0.55, alpha: 1), isPrintable: false))
            layerManager.setCurrentLayer(current)
        }
        let viewport = ViewportEntity(rect: rect, modelCenter: box.map { CGPoint(x: $0.midX, y: $0.midY) } ?? .zero,
                                      scale: scale, layer: "Viewports")
        viewport.mmPerUnit = mm
        return viewport
    }

    @objc func newLayout(_ sender: Any?) {
        editorView.cancelCurrentOperation()
        storeActiveTabState()
        let tab = activeTab
        let layout = DrawingLayout(name: tab.uniqueLayoutName(), paper: .a3, landscape: true)
        tab.layouts.append(layout)
        hasUnsavedChanges = true
        activateSpace(tab.layouts.count - 1)
        // default viewport across the whole printable area
        let viewport = makeViewport(rect: layout.printableRect)
        layout.document.addEntity(viewport)
        editorView.needsDisplay = true
        statusBar.showMessage("\(layout.name) created – \(layout.paperDescription), viewport \(viewport.scale.title). Right-click the tab for page setup.")
    }

    @objc func addViewport(_ sender: Any?) {
        guard let layout = activeTab.activeLayout else {
            statusBar.showMessage("Viewports go on a layout – click a layout tab below the drawing first.")
            NSSound.beep()
            return
        }
        let tab = activeTab
        editorView.pickRectangle(prompt: "New viewport: click the first corner") { [weak self] rect in
            guard let self = self, let rect = rect, tab === self.activeTab, layout === tab.activeLayout else { return }
            let viewport = self.makeViewport(rect: rect)
            self.applyChange(removed: [], added: [viewport], actionName: "Add Viewport")
            self.selectionManager.select([viewport])
            self.statusBar.showMessage("Viewport \(viewport.scale.title) – change the scale in Properties, ⌥-drag inside to pan")
        }
    }

    private func layoutIndex(_ index: Int?) -> Int? {
        let i = index ?? activeTab.activeLayoutIndex
        guard let value = i, activeTab.layouts.indices.contains(value) else { return nil }
        return value
    }

    @objc func renameLayoutFromMenu(_ sender: Any?) { if let i = layoutIndex(nil) { renameLayout(at: i) } }
    @objc func deleteLayoutFromMenu(_ sender: Any?) { if let i = layoutIndex(nil) { deleteLayout(at: i) } }
    @objc func duplicateLayoutFromMenu(_ sender: Any?) { if let i = layoutIndex(nil) { duplicateLayout(at: i) } }
    @objc func pageSetupFromMenu(_ sender: Any?) { if let i = layoutIndex(nil) { layoutPageSetup(at: i) } }

    private func renameLayout(at index: Int) {
        let tab = activeTab
        guard tab.layouts.indices.contains(index) else { return }
        let layout = tab.layouts[index]
        let alert = NSAlert()
        alert.messageText = "Rename Layout"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = layout.name
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.lowercased() != "model" else { NSSound.beep(); return }
        guard !tab.layouts.contains(where: { $0 !== layout && $0.name == name }) else {
            statusBar.showMessage("A layout named “\(name)” already exists.")
            NSSound.beep()
            return
        }
        // saved views of the layout go with it
        let oldName = layout.name
        for index in tab.namedViews.indices where tab.namedViews[index].layout == oldName {
            tab.namedViews[index].layout = name
        }
        layout.name = name
        hasUnsavedChanges = true
        refreshLayoutBar()
    }

    private func duplicateLayout(at index: Int) {
        let tab = activeTab
        guard tab.layouts.indices.contains(index) else { return }
        let source = tab.layouts[index]
        let copy = source.duplicate(named: tab.uniqueLayoutName(source.name + " copy "))
        tab.layouts.insert(copy, at: index + 1)
        syncViewportUnits(tab)
        hasUnsavedChanges = true
        activateSpace(index + 1)
    }

    private func deleteLayout(at index: Int) {
        let tab = activeTab
        guard tab.layouts.indices.contains(index) else { return }
        let layout = tab.layouts[index]
        let alert = NSAlert()
        alert.messageText = "Delete the layout “\(layout.name)”?"
        alert.informativeText = "Everything drawn on this sheet is deleted. The model stays as it is. This cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if tab.activeLayoutIndex == index {
            activateSpace(nil)
            // the switch to the model was refused (Cancel in the block edit question) – the sheet stays
            guard tab.activeLayoutIndex == nil else { return }
        }
        tab.layouts.remove(at: index)
        if let active = tab.activeLayoutIndex, active > index { tab.activeLayoutIndex = active - 1 }
        hasUnsavedChanges = true
        refreshLayoutBar()
    }

    private func moveLayout(from: Int, to: Int) {
        let tab = activeTab
        guard tab.layouts.indices.contains(from), tab.layouts.indices.contains(to), from != to else { return }
        let active = tab.activeLayout
        let layout = tab.layouts.remove(at: from)
        tab.layouts.insert(layout, at: to)
        if let active = active { tab.activeLayoutIndex = tab.layouts.firstIndex { $0 === active } }
        hasUnsavedChanges = true
        refreshLayoutBar()
    }

    private func layoutPageSetup(at index: Int) {
        let tab = activeTab
        guard tab.layouts.indices.contains(index) else { return }
        let layout = tab.layouts[index]
        guard let result = LayoutPageSetupDialog.run(name: layout.name, paper: layout.paper,
                                                     landscape: layout.landscape, marginMM: layout.marginMM) else { return }
        layout.paper = result.paper
        layout.landscape = result.landscape
        layout.marginMM = result.marginMM
        // plotting a layout follows its paper
        if var plot = layout.plotSettings, plot.area == "layout" {
            plot.paper = layout.paper.rawValue
            plot.orientation = layout.landscape ? 2 : 1
            layout.plotSettings = plot
        }
        hasUnsavedChanges = true
        if layout === tab.activeLayout {
            refreshPaperSpace()
            editorView.zoomToPaper()
        }
        refreshLayoutBar()
        statusBar.showMessage("\(layout.name): \(layout.paperDescription)")
    }

    /// Double-click on a viewport: the model zoomed to the area the viewport shows.
    private func openModel(at viewport: ViewportEntity) {
        let area = viewport.modelRect()
        activateSpace(nil)
        let diagonal = Line(start: CGPoint(x: area.minX, y: area.minY), end: CGPoint(x: area.maxX, y: area.maxY))
        editorView.viewport.zoomToFit(entities: [diagonal])
        statusBar.showMessage("Model – the area of the viewport \(viewport.scale.title)")
    }

    // MARK: Menu – edit and view

    @objc func deleteSelection() {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
            .filter { !layerManager.isLayerLocked($0.layer) }
        guard !selected.isEmpty else { return }
        applyChange(removed: selected, added: [], actionName: "Delete")
        statusBar.showMessage("\(selected.count) object\(selected.count == 1 ? "" : "s") deleted")
    }

    // MARK: Menu – clipboard (Cut / Copy / Paste between drawings, Clipboard.swift)

    /// Edit › Copy (⌘C): remembers the selected objects – they can be pasted into this or another open drawing.
    @objc func copy(_ sender: Any?) {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
        guard !selected.isEmpty else {
            NSSound.beep()
            return
        }
        DrawingClipboard.shared.store(selected, layerManager: layerManager)
        statusBar.showMessage("Copied \(selected.count) object\(selected.count == 1 ? "" : "s") · ⌘V = paste (also into another drawing), ⇧⌘V = at the same coordinates")
    }

    /// Edit › Cut (⌘X): copies the selected objects and deletes them (objects on locked layers stay).
    @objc func cut(_ sender: Any?) {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
            .filter { !layerManager.isLayerLocked($0.layer) }
        guard !selected.isEmpty else {
            NSSound.beep()
            return
        }
        DrawingClipboard.shared.store(selected, layerManager: layerManager)
        applyChange(removed: selected, added: [], actionName: "Cut")
        statusBar.showMessage("Cut \(selected.count) object\(selected.count == 1 ? "" : "s") · ⌘V = paste")
    }

    /// Edit › Paste (⌘V): the copied objects hang on the cursor, a click places them.
    @objc func paste(_ sender: Any?) {
        guard let content = preparePaste() else { return }
        let tab = activeTab
        let target = document
        editorView.beginPaste(content.entities) { [weak self] offset in
            guard let self = self else { return }
            // the drawing or the space changed while placing → nothing is pasted
            guard tab === self.activeTab, target === self.document else { return }
            self.commitPaste(content, offset: offset)
        }
    }

    /// Edit › Paste at Original Coordinates (⇧⌘V): the copied objects at the same coordinates as in their drawing.
    @objc func pasteAtOriginalCoordinates(_ sender: Any?) {
        guard let content = preparePaste() else { return }
        editorView.cancelCurrentOperation()
        commitPaste(content, offset: .zero)
    }

    /// Fresh copies of the clipboard for the open drawing (nil = nothing to paste).
    private func preparePaste() -> DrawingClipboard.PasteContent? {
        guard !DrawingClipboard.shared.isEmpty else {
            statusBar.showMessage("Nothing to paste – select objects and copy them (⌘C) first")
            NSSound.beep()
            return nil
        }
        let content = DrawingClipboard.shared.prepare(for: layerManager, blocks: activeTab.blocks,
                                                      editedBlock: activeTab.blockEdit?.definition,
                                                      onLayout: activeTab.activeLayout != nil && activeTab.blockEdit == nil)
        guard !content.entities.isEmpty else {
            statusBar.showMessage("Nothing to paste here – viewports go only onto a layout, and a block cannot contain itself")
            NSSound.beep()
            return nil
        }
        return content
    }

    /// Puts the pasted objects into the drawing (one undo step) with the layers and blocks they need.
    private func commitPaste(_ content: DrawingClipboard.PasteContent, offset: CGPoint) {
        for layer in content.newLayers where layerManager.getLayer(layer.name) == nil {
            layerManager.addLayer(layer)
        }
        for definition in content.newBlocks where !activeTab.blocks.definitions.contains(where: { $0 === definition }) {
            activeTab.blocks.add(definition)
        }
        if !content.newBlocks.isEmpty { editorView.blockLibrary = activeTab.blocks }
        if offset != .zero {
            let shift = CGAffineTransform(translationX: offset.x, y: offset.y)
            for entity in content.entities { entity.applyTransform(shift) }
        }
        applyChange(removed: [], added: content.entities, actionName: "Paste")
        selectionManager.select(content.entities)
        editorView.needsDisplay = true
        refreshPanels()

        let count = content.entities.count
        var message = "Pasted \(count) object\(count == 1 ? "" : "s")"
        if !content.newLayers.isEmpty { message += " · \(content.newLayers.count) new layer\(content.newLayers.count == 1 ? "" : "s")" }
        if !content.newBlocks.isEmpty { message += " · \(content.newBlocks.count) new block\(content.newBlocks.count == 1 ? "" : "s")" }
        if content.skipped > 0 { message += " · \(content.skipped) skipped (viewports only on a layout, no block inside itself)" }
        statusBar.showMessage(message)
    }

    @objc func selectAllEntities(_ sender: Any?) {
        // ⌘A while typing (text on the canvas, a value, a dialog field) selects that text, not the drawing
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView, textView.isSelectable {
            textView.selectAll(sender)
            return
        }
        let selectable = document.getAllEntities().filter {
            layerManager.isLayerVisible($0.layer) && !layerManager.isLayerLocked($0.layer)
        }
        selectionManager.select(selectable)
    }

    /// Edit › Select Similar (⇧⌘A): starts the Select Similar tool – the selected objects are the samples,
    /// what must match is ticked in the options bar above the drawing.
    @objc func selectSimilar(_ sender: Any?) {
        selectTool(.selectSimilar)
        view.window?.makeFirstResponder(editorView)
    }

    /// Edit › Filter… (⌥S on the drawing area): selects the objects that match the ticked properties (Filter.swift) –
    /// in the open space on visible and unlocked layers, or within the current selection.
    @objc func filterObjects(_ sender: Any?) {
        let all = document.getAllEntities()
        let candidates = all.filter { layerManager.isLayerVisible($0.layer) && !layerManager.isLayerLocked($0.layer) }
        let selected = selectionManager.getSelectedEntities(from: all)
        guard !candidates.isEmpty || !selected.isEmpty else {
            statusBar.showMessage("Filter: nothing to search – the drawing is empty or its layers are hidden or locked")
            NSSound.beep()
            return
        }
        guard let criteria = FilterDialog.run(candidates: candidates, selected: selected, layers: layerManager) else { return }
        let searched = criteria.scope == .selection ? selected : candidates
        let found = searched.filter { criteria.matches($0, layers: layerManager) }
        guard !found.isEmpty else {
            statusBar.showMessage("Filter: no object with " + criteria.summary + " – the selection stays as it was")
            NSSound.beep()
            return
        }
        editorView.cancelCurrentOperation()
        if currentTool != .select { selectTool(.select) }
        selectionManager.select(found)
        editorView.needsDisplay = true
        view.window?.makeFirstResponder(editorView)
        statusBar.showMessage("Filter: selected \(found.count) object\(found.count == 1 ? "" : "s") with " + criteria.summary)
    }

    /// Edit › Find and Replace… (⌘F) – texts, labels and dimension texts in the model, on layouts and in blocks.
    @objc func findAndReplace(_ sender: Any?) {
        if findController == nil {
            let controller = FindReplaceController()
            controller.sources = { [weak self] in
                guard let self = self else { return [] }
                return self.findSources()
            }
            controller.isEditable = { [weak self] entity in
                return !(self?.layerManager.isLayerLocked(entity.layer) ?? false)
            }
            controller.spaceName = { [weak self] in
                guard let self = self else { return "the drawing" }
                let title = "\u{201C}\(self.activeTab.title)\u{201D}"
                if let session = self.activeTab.blockEdit {
                    return title + " \u{2013} block \u{201C}\(session.definition.name)\u{201D}"
                }
                return title + " \u{2013} model, layouts and blocks"
            }
            controller.onShow = { [weak self] matches in
                self?.showFound(matches)
            }
            controller.onSelect = { [weak self] matches in
                guard let self = self else { return }
                let here = self.uniqueEntities(matches.filter { self.isOpenSpace($0.place) }.map { $0.entity })
                let elsewhere = matches.count - matches.filter { self.isOpenSpace($0.place) }.count
                self.selectionManager.select(here)
                self.editorView.needsDisplay = true
                var message = "Selected \(here.count) object\(here.count == 1 ? "" : "s") with the found text"
                if elsewhere > 0 { message += " \u{2013} texts on other layouts or in blocks are not selected" }
                self.statusBar.showMessage(message)
            }
            controller.onReplace = { [weak self] replacements in
                self?.replaceFoundTexts(replacements)
            }
            findController = controller
        }
        // a single selected text → search for its first line
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
        var initial: String?
        if selected.count == 1, let text = selected.first as? TextEntity {
            initial = text.text.components(separatedBy: "\n").first.map { String($0.prefix(80)) }
        }
        findController?.show(searching: initial)
    }

    /// Find and Replace searches the open space first, then the other spaces and the blocks.
    /// During a block edit only the edited block is searched (its objects are the open space).
    private func findSources() -> [TextSource] {
        let tab = activeTab
        let layers = layerManager
        let visible: (CADEntity) -> Bool = { entity in layers.isLayerVisible(entity.layer) }
        if let session = tab.blockEdit {
            return [TextSource(place: .model, name: "Block \u{201C}\(session.definition.name)\u{201D}",
                               entities: document.getAllEntities().filter(visible))]
        }
        var spaces = [TextSource(place: .model, name: "Model", entities: tab.document.getAllEntities().filter(visible))]
        for (index, layout) in tab.layouts.enumerated() {
            spaces.append(TextSource(place: .layout(index), name: layout.name,
                                     entities: layout.document.getAllEntities().filter(visible)))
        }
        let open = spaces.firstIndex { isOpenSpace($0.place) } ?? 0
        spaces.insert(spaces.remove(at: open), at: 0)
        let blocks = tab.blocks.blocks.map { definition in
            TextSource(place: .block(definition), name: "Block \u{201C}\(definition.name)\u{201D}",
                       entities: definition.entities.filter(visible))
        }
        return spaces + blocks
    }

    /// Is the place the space being edited now? (During a block edit the found objects are all in it.)
    private func isOpenSpace(_ place: TextPlace) -> Bool {
        if activeTab.blockEdit != nil { return true }
        switch place {
        case .model: return activeTab.activeLayoutIndex == nil
        case let .layout(index): return activeTab.activeLayoutIndex == index
        case .block: return false
        }
    }

    private func uniqueEntities(_ entities: [CADEntity]) -> [CADEntity] {
        var seen = Set<UUID>()
        return entities.filter { seen.insert($0.id).inserted }
    }

    /// Shows found objects: in their space (switching to it), a text in a block through the copies of the block.
    private func showFound(_ matches: [TextMatch]) {
        guard let first = matches.first else { return }
        let tab = activeTab
        if tab.blockEdit != nil || !isBlock(first.place) {
            if tab.blockEdit == nil {
                switch first.place {
                case .model: activateSpace(nil)
                case let .layout(index): activateSpace(index)
                case .block: break
                }
                guard isOpenSpace(first.place) else { return }      // the switch was canceled
            }
            let entities = uniqueEntities(matches.filter { $0.place.isSame(as: first.place) }.map { $0.entity })
            selectionManager.select(entities)
            zoom(toShow: entities)
            return
        }
        guard case let .block(definition) = first.place else { return }
        // the copies of the block: in the open space, otherwise in the first space that has some
        func copies(in document: CADDocument) -> [CADEntity] {
            return document.getAllEntities().filter { ($0 as? BlockReference)?.definition === definition }
        }
        var found = copies(in: document)
        if found.isEmpty {
            let spaces: [(index: Int?, document: CADDocument)] = [(nil, tab.document)]
                + tab.layouts.enumerated().map { (index: Optional($0.offset), document: $0.element.document) }
            if let other = spaces.first(where: { !copies(in: $0.document).isEmpty }) {
                activateSpace(other.index)
                found = copies(in: document)
            }
        }
        guard !found.isEmpty else {
            statusBar.showMessage("The block \u{201C}\(definition.name)\u{201D} is not inserted in any space \u{2013} Block Manager shows it")
            NSSound.beep()
            return
        }
        selectionManager.select(found)
        zoom(toShow: found)
        statusBar.showMessage("The text is in the block \u{201C}\(definition.name)\u{201D} \u{2013} its copies are selected")
    }

    private func isBlock(_ place: TextPlace) -> Bool {
        if case .block = place { return true }
        return false
    }

    /// Replace in Find and Replace: the open space, the other spaces and the blocks change in one Undo step.
    private func replaceFoundTexts(_ replacements: [TextReplacement]) {
        guard !replacements.isEmpty else { return }
        editorView.cancelCurrentOperation()
        // a text left empty is deleted in the same step (an empty text is invisible and is not saved)
        func kept(_ entity: CADEntity) -> Bool {
            guard let text = entity as? TextEntity else { return true }
            return !text.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let tab = activeTab
        let undo = undoer
        undo.beginUndoGrouping()
        // the open space as any other change (associative dimensions, room labels)
        let here = replacements.filter { isOpenSpace($0.place) }
        if !here.isEmpty {
            applyChange(removed: here.map { $0.old }, added: here.map { $0.new }.filter(kept), actionName: "Replace Text")
        }
        if tab.blockEdit == nil {
            // other spaces: changed without switching to them (Undo shows them)
            let spaces: [(place: TextPlace, document: CADDocument)] = [(.model, tab.document)]
                + tab.layouts.enumerated().map { (place: TextPlace.layout($0.offset), document: $0.element.document) }
            for space in spaces where !isOpenSpace(space.place) {
                let changes = replacements.filter { $0.place.isSame(as: space.place) }
                guard !changes.isEmpty else { continue }
                let batch = ReplaceBatch(removed: changes.map { $0.old }, added: changes.map { $0.new }.filter(kept),
                                         document: space.document)
                perform(batch, on: space.document)
            }
            // blocks: the new content of each definition (every copy of the block changes)
            for definition in tab.blocks.blocks {
                let changes = replacements.filter { $0.place.isSame(as: .block(definition)) }
                guard !changes.isEmpty else { continue }
                var edited: [UUID: CADEntity] = [:]
                for change in changes { edited[change.old.id] = change.new }
                let entities = definition.entities.compactMap { entity -> CADEntity? in
                    guard let copy = edited[entity.id] else { return entity }
                    return kept(copy) ? copy : nil
                }
                applyBlockChange(BlockContentChange(definition: definition, entities: entities, basePoint: definition.basePoint))
            }
        }
        undo.setActionName("Replace Text")
        undo.endUndoGrouping()
        editorView.invalidateRenderCache()
        editorView.needsDisplay = true
        refreshPanels()
    }

    /// Shows objects in the drawing together with their surroundings (Find and Replace).
    private func zoom(toShow entities: [CADEntity]) {
        var box = CGRect.null
        for entity in entities {
            let bounds = entity.boundingBox()
            guard !bounds.isNull, bounds.minX.isFinite, bounds.minY.isFinite, bounds.maxX.isFinite, bounds.maxY.isFinite else { continue }
            box = box.union(bounds)
        }
        guard !box.isNull else { return }
        let pad = max(max(box.width, box.height) * 0.6, 1)
        let area = box.insetBy(dx: -pad, dy: -pad)
        editorView.viewport.zoomToFit(entities: [Line(start: CGPoint(x: area.minX, y: area.minY),
                                                      end: CGPoint(x: area.maxX, y: area.maxY))])
        editorView.needsDisplay = true
    }

    @objc func toggleSimilarProperty(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let property = SimilarProperty(rawValue: raw) else { return }
        var properties = AppSettings.similarProperties
        if properties.contains(property) { properties.remove(property) } else { properties.insert(property) }
        if properties.isEmpty {
            statusBar.showMessage("At least one property has to match – Object Type stays on")
            properties = [.type]
        }
        AppSettings.similarProperties = properties
        if currentTool == .selectSimilar { editorView.applySelectSimilar() }
        updateToolOptionsBar()
    }

    @objc func selectToolFromMenu(_ sender: NSMenuItem) {
        if let tool = DrawingTool(rawValue: sender.tag) { selectTool(tool) }
    }

    @objc func setFilletRadius(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Fillet – Radius"
        alert.informativeText = "Radius of the fillet (0 = sharp corner):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.stringValue = String(format: "%g", Double(editorView.filletRadius))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if let value = ExpressionEvaluator.evaluate(field.stringValue), value >= 0 {
            editorView.filletRadius = CGFloat(value)
            statusBar.setPrompt(editorView.prompt)
        } else {
            statusBar.showMessage("“\(field.stringValue)” is not a valid radius.")
        }
    }

    /// Format › Chamfer Distances… – chamfer distances from the corner on the first and the second object.
    @objc func setChamferDistances(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Chamfer – Distances"
        alert.informativeText = "Distances from the corner used by the Chamfer tool – the first on the first line you click, "
            + "the second on the second line (both 0 = sharp corner):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let first = NSTextField(frame: NSRect(x: 0, y: 0, width: 90, height: 24))
        let second = NSTextField(frame: NSRect(x: 0, y: 0, width: 90, height: 24))
        first.stringValue = String(format: "%g", Double(editorView.chamferFirst))
        second.stringValue = String(format: "%g", Double(editorView.chamferSecond))
        let firstLabel = NSTextField(labelWithString: "First:")
        let secondLabel = NSTextField(labelWithString: "Second:")
        let row = NSStackView(views: [firstLabel, first, secondLabel, second])
        row.spacing = 6
        row.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        first.widthAnchor.constraint(equalToConstant: 90).isActive = true
        second.widthAnchor.constraint(equalToConstant: 90).isActive = true
        first.nextKeyView = second
        second.nextKeyView = first
        alert.accessoryView = row
        alert.window.initialFirstResponder = first
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        func number(_ field: NSTextField) -> Double? {
            let text = field.stringValue.trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : ExpressionEvaluator.evaluate(text)
        }
        let a = number(first), b = number(second)
        // one field empty = the same distance as in the other
        guard let d1 = a ?? b, let d2 = b ?? a, d1 >= 0, d2 >= 0 else {
            // the field that holds the wrong value
            let firstOK = first.stringValue.trimmingCharacters(in: .whitespaces).isEmpty || (a ?? -1) >= 0
            let wrong = firstOK ? second : first
            statusBar.showMessage("\u{201C}\(wrong.stringValue)\u{201D} is not a valid distance.")
            return
        }
        editorView.chamferFirst = CGFloat(d1)
        editorView.chamferSecond = CGFloat(d2)
        statusBar.setPrompt(editorView.prompt)
    }

    @objc func zoomIn() { editorView.viewport.zoomIn() }
    @objc func zoomOut() { editorView.viewport.zoomOut() }

    /// Zoom Window: the area chosen by two corners is enlarged to fill the window.
    @objc func zoomWindow(_ sender: Any?) {
        view.window?.makeFirstResponder(editorView)
        editorView.pickRectangle(prompt: "Zoom Window: click the first corner of the area to show") { [weak self] rect in
            guard let self = self else { return }
            if let rect = rect {
                let diagonal = Line(start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.maxX, y: rect.maxY))
                self.editorView.viewport.zoomToFit(entities: [diagonal])
            }
            self.statusBar.setPrompt(self.editorView.prompt)
        }
    }

    @objc func zoomExtents() {
        if activeTab.activeLayout != nil {
            editorView.zoomToPaper()
            return
        }
        editorView.viewport.zoomToFit(entities: document.getAllEntities())
    }

    /// Zoom Extents for the selected objects only.
    @objc func zoomSelected(_ sender: Any?) {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
        // infinite construction lines have no bounds – you can't zoom to them
        let finite = selected.filter { entity in
            let box = entity.boundingBox()
            return !box.isNull && box.minX.isFinite && box.minY.isFinite && box.maxX.isFinite && box.maxY.isFinite
        }
        guard !finite.isEmpty else {
            showToast(selected.isEmpty ? "Zoom Selected: nothing is selected"
                                       : "Zoom Selected: construction lines have no extents")
            return
        }
        editorView.viewport.zoomToFit(entities: finite)
    }

    @objc func toggleLayerPanel() {
        showLayerManager()
    }

    @objc func togglePropertiesPanel() {
        switch propertiesMode {
        case .closed, .collapsed:
            setPropertiesMode(.docked)
        case .docked where trayCollapsed || propertiesFolded:
            trayCollapsed = false
            propertiesFolded = false
            layoutTray()
        default:
            setPropertiesMode(.closed)
        }
    }

    /// Collapses / expands the whole side panel into a narrow strip.
    @objc func collapseProperties() {
        trayCollapsed.toggle()
        layoutTray()
    }

    @objc func detachProperties() {
        setPropertiesMode(propertiesMode == .detached ? .docked : .detached)
    }

    // MARK: Mode keys (⌥ + digit always, F-keys when macOS sends them)

    private var modeKeyMonitor: Any?

    private enum ModeKey { case snap, snapTracking, askToClose, lineWeights, dynamicInput, lineContinue, ortho, grid, polar, showGrid, help, infoPanel }

    /// ⌥ + digit by the physical key (works on every layout, including Czech).
    private static let optionKeys: [UInt16: ModeKey] = [
        18: .snapTracking, 19: .showGrid, 20: .snap, 21: .askToClose, 23: .lineWeights, 22: .dynamicInput,
        26: .lineContinue, 28: .ortho, 25: .grid, 29: .polar
    ]
    /// F1–F12 (F11 reaches the app only when macOS does not use it for Show Desktop).
    private static let functionKeys: [UInt16: ModeKey] = [
        122: .help, 120: .infoPanel, 99: .snap, 118: .askToClose, 96: .lineWeights, 97: .lineContinue,
        98: .showGrid, 100: .ortho, 101: .grid, 109: .polar, 103: .snapTracking, 111: .dynamicInput
    ]

    private func installModeKeys() {
        modeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleModeKey(event) ? nil : event
        }
        // FKEYS state according to the macOS setting (refreshed when returning to the app)
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshFunctionKeysState() }
        }
    }

    private func handleModeKey(_ event: NSEvent) -> Bool {
        guard event.window === view.window else { return false }
        // leave typing in text fields alone (except the box at the cursor)
        if let text = view.window?.firstResponder as? NSTextView, !text.isDescendant(of: editorView) { return false }
        // text typed directly on the canvas: ⌥+digit types characters (@, #, …), doesn't toggle modes
        if editorView.isEditingText { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // ⇧⌘] / ⇧⌘[ = next / previous tab (by the physical key, as ⌥ + digit)
        if modifiers == [.command, .shift], event.keyCode == 30 || event.keyCode == 33 {
            if event.keyCode == 30 { selectNextTab(nil) } else { selectPreviousTab(nil) }
            return true
        }
        let mode: ModeKey?
        if modifiers == [.option] {
            mode = MainViewController.optionKeys[event.keyCode]
        } else if modifiers.isEmpty {
            mode = MainViewController.functionKeys[event.keyCode]
        } else {
            mode = nil
        }
        guard let key = mode else { return false }
        // the key is swallowed here, so the drawing area would not learn that ⌥ was used with it
        editorView.cancelOptionTap()
        toggleMode(key)
        return true
    }

    /// Every toggle shows its ON / OFF message itself – the same from a key, the menu or the status line.
    private func toggleMode(_ key: ModeKey) {
        switch key {
        case .snap: toggleSnap()
        case .snapTracking: toggleSnapTracking()
        case .askToClose: toggleAskToClose()
        case .lineWeights: toggleLineWeights()
        case .dynamicInput: toggleDynamicInput()
        case .lineContinue: toggleLineContinue()
        case .ortho: toggleOrtho()
        case .grid: toggleGridSnap()
        case .showGrid: toggleGrid()
        case .polar: togglePolar()
        case .help: showKeyboardShortcuts(nil)
        case .infoPanel: toggleInfoPanel(nil)
        }
    }

    /// Does the top row send F1–F12? (a global macOS setting; nil = cannot be determined)
    private func refreshFunctionKeysState() {
        let value = UserDefaults.standard.object(forKey: "com.apple.keyboard.fnState")
        statusBar.setFunctionKeysState((value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false)
    }

    /// FKEYS: explanation and opening the keyboard settings in macOS.
    private func showFunctionKeysInfo() {
        refreshFunctionKeysState()
        let alert = NSAlert()
        alert.messageText = "Function Keys F1–F12"
        alert.informativeText = """
        Whether the top row sends F1, F2… or controls brightness and volume is a macOS setting for the whole Mac – an app cannot switch it.

        • Hold fn (Globe) and press the F-key, or
        • turn on “Use F1, F2, etc. keys as standard function keys” in System Settings › Keyboard › Keyboard Shortcuts… › Function Keys, or
        • use the shortcuts that always work in OreMonoCAD: ⌥1 Snap tracking · ⌥2 Show grid · ⌥3 Snap · ⌥4 CLS · ⌥5 LWT · ⌥6 value box · ⌥7 LNC · ⌥8 Ortho · ⌥9 Grid snap · ⌥0 Polar.

        Keyboards that are not made by Apple usually send F1–F12 directly.
        """
        alert.addButton(withTitle: "Open Keyboard Settings")
        alert.addButton(withTitle: "Close")
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    @objc func toggleGridSnap() {
        editorView.gridSnapEnabled.toggle()
        statusBar.showMessage(editorView.gridSnapEnabled
            ? "Snap to grid ON – step \(LineType.format(editorView.gridSize)) \(editorView.drawingUnits.suffix)" : "Snap to grid OFF")
    }

    @objc func togglePolar() {
        editorView.polarEnabled.toggle()
        statusBar.showMessage(editorView.polarEnabled
            ? "Polar angles ON – every \(AngleStyle.text(editorView.polarIncrement))" : "Polar angles OFF")
    }

    /// A change of the drawing settings is saved with the drawing.
    private func markSettingsChanged() {
        hasUnsavedChanges = true
        updateModes()
    }

    /// Converts everything besides the objects that is stored in model coordinates (Convert Units),
    /// and registers the opposite conversion for Undo.
    private func convertUnitSettings(from oldUnits: DrawingUnits, to newUnits: DrawingUnits, factor: CGFloat) {
        let tab = activeTab
        func scaled(_ p: CGPoint) -> CGPoint { return CGPoint(x: p.x * factor, y: p.y * factor) }
        // viewports on layouts keep showing the same place in the model
        for layout in tab.layouts {
            for viewport in layout.viewports { viewport.modelCenter = scaled(viewport.modelCenter) }
        }
        tab.ucsOrigin = scaled(tab.ucsOrigin)
        if tab.activeLayout == nil { editorView.ucsOrigin = tab.ucsOrigin }
        if var reference = tab.geoReference {
            reference.local = scaled(reference.local)
            tab.geoReference = reference
            GeoReference.active = reference
        }
        for index in tab.namedViews.indices where tab.namedViews[index].layout == nil {
            tab.namedViews[index].zoom /= factor
            tab.namedViews[index].pan = scaled(tab.namedViews[index].pan)
        }
        if tab.activeLayout == nil {
            editorView.viewport.viewState = (zoom: editorView.viewport.getCurrentZoom() / factor,
                                             pan: scaled(editorView.viewport.viewState.pan))
            editorView.drawingUnits = newUnits
            // a fixed hatch scale is a length in model units too (the grid size has its own undo step)
            if let scale = editorView.hatchScale { editorView.hatchScale = scale * factor }
        } else {
            if let view = tab.viewState { tab.viewState = (zoom: view.zoom / factor, pan: scaled(view.pan)) }
            if let scale = tab.hatchScale { tab.hatchScale = scale * factor }
        }
        tab.units = newUnits
        syncViewportUnits(tab, mmPerUnit: newUnits.mmPerUnit)
        tab.activeUndoer.registerUndo(withTarget: self) { target in
            target.convertUnitSettings(from: newUnits, to: oldUnits, factor: 1 / factor)
            target.markSettingsChanged()
            target.editorView.needsDisplay = true
        }
    }

    /// The model's grid size, undoable (Undo puts back exactly the previous size).
    private func setModelGridSize(_ size: CGFloat, undoTo previous: CGFloat) {
        if activeTab.activeLayout == nil { editorView.gridSize = size } else { activeTab.gridSize = size }
        activeTab.activeUndoer.registerUndo(withTarget: self) { target in
            target.setModelGridSize(previous, undoTo: size)
            target.markSettingsChanged()
            target.editorView.needsDisplay = true
        }
    }

    /// Block definitions converted with the model's units: the ones used only in the model.
    /// Blocks placed on a layout (a title block in paper mm) and external references keep their size.
    private func convertedBlocks(factor: CGFloat) -> [BlockDefinition] {
        var onLayouts: [BlockDefinition] = []
        func collect(_ entities: [CADEntity]) {
            for case let reference as BlockReference in entities
                where !onLayouts.contains(where: { $0 === reference.definition }) {
                onLayouts.append(reference.definition)
                collect(reference.definition.entities)
            }
        }
        for layout in activeTab.layouts { collect(layout.document.getAllEntities()) }
        return activeTab.blocks.definitions.filter { definition in
            !definition.isExternal && !onLayouts.contains { $0 === definition }
        }
    }

    /// Replaces the base point and the objects of block definitions, undoable (Convert Units).
    private func setBlockContents(_ contents: [(BlockDefinition, CGPoint, [CADEntity])]) {
        guard !contents.isEmpty else { return }
        let previous = contents.map { ($0.0, $0.0.basePoint, $0.0.entities) }
        for (definition, base, entities) in contents {
            definition.basePoint = base
            definition.entities = entities
        }
        activeTab.activeUndoer.registerUndo(withTarget: self) { target in
            target.setBlockContents(previous)
            target.editorView.needsDisplay = true
        }
    }

    /// Document settings: units, grid and angle snapping.
    @objc func documentSettings(_ sender: Any?) {
        // Convert Units changes the model and the blocks – not while a block is being edited
        // (only the edited block would be converted, and its own Undo ends with the edit)
        guard ensureNoBlockEdit(reason: "Document settings change the whole drawing.") else { return }
        // units and grid belong to the model – from a layout it first switches to the model
        if activeTab.activeLayout != nil {
            activateSpace(nil)
            statusBar.showMessage("Document settings belong to the model – switched to Model")
        }
        guard let result = DocumentSettingsDialog.run(units: editorView.drawingUnits, gridSize: editorView.gridSize,
                                                      gridSnap: editorView.gridSnapEnabled, showGrid: editorView.showGrid,
                                                      polar: editorView.polarEnabled, polarIncrement: editorView.polarIncrement) else { return }
        let oldUnits = editorView.drawingUnits
        let oldGridSize = editorView.gridSize
        var gridSize = result.gridSize
        if result.units != oldUnits && result.convertDrawing {
            // convert the coordinates so the drawing stays the same real size
            let factor = oldUnits.mmPerUnit / result.units.mmPerUnit
            let t = CGAffineTransform(scaleX: factor, y: factor)
            let originals = document.getAllEntities()
            // block definitions are converted too, so their references keep their scale and new insertions fit
            let converted = convertedBlocks(factor: factor)
            let scaled = originals.map { entity -> CADEntity in
                return EditorUnitConversion.converted(entity, transform: t, factor: factor, convertedBlocks: converted)
            }
            // an untouched grid size keeps its real size
            if gridSize == oldGridSize { gridSize = oldGridSize * factor }
            setBlockContents(converted.map { definition in
                (definition, definition.basePoint.applying(t), definition.entities.map {
                    EditorUnitConversion.converted($0, transform: t, factor: factor, convertedBlocks: converted)
                })
            })
            applyChange(removed: originals, added: scaled, actionName: "Convert Units")
            // the settings tied to model coordinates are converted in the same undo step
            convertUnitSettings(from: oldUnits, to: result.units, factor: factor)
        }
        if result.units != oldUnits && result.convertDrawing {
            // in the conversion's undo step the grid size is set (and undone) on its own –
            // the user may have changed it in the same dialog
            if gridSize != oldGridSize { setModelGridSize(gridSize, undoTo: oldGridSize) }
        } else {
            editorView.gridSize = gridSize
        }
        editorView.drawingUnits = result.units
        activeTab.units = result.units
        syncViewportUnits(activeTab, mmPerUnit: result.units.mmPerUnit)
        editorView.gridSnapEnabled = result.gridSnap
        editorView.showGrid = result.showGrid
        AppSettings.showGrid = result.showGrid
        editorView.polarIncrement = result.polarIncrement
        editorView.polarEnabled = result.polar
        markSettingsChanged()
        editorView.needsDisplay = true
        statusBar.showMessage("Units: \(result.units.title) · grid \(LineType.format(gridSize)) · polar \(AngleStyle.text(result.polarIncrement))")
    }

    /// Show Grid and Show Axes are saved in the drawing, so switching them is a change of the drawing.
    /// The app remembers the last state too, for new drawings.
    @objc func toggleGrid() {
        editorView.showGrid.toggle()
        AppSettings.showGrid = editorView.showGrid
        hasUnsavedChanges = true
        statusBar.showMessage(editorView.showGrid ? "Show grid ON" : "Show grid OFF")
    }

    @objc func toggleAxes() {
        editorView.showAxes.toggle()
        AppSettings.showAxes = editorView.showAxes
        hasUnsavedChanges = true
        statusBar.showMessage(editorView.showAxes ? "Show axes ON" : "Show axes OFF")
    }

    @objc func toggleSnap() {
        editorView.snapEnabled.toggle()
        statusBar.showMessage(editorView.snapEnabled ? "Object snap ON" : "Object snap OFF")
    }

    @objc func toggleSnapTracking() {
        editorView.snapTrackingEnabled.toggle()
        statusBar.showMessage(editorView.snapTrackingEnabled ? "Snap tracking ON" : "Snap tracking OFF")
    }

    @objc func toggleOrtho() {
        editorView.orthoEnabled.toggle()
        statusBar.showMessage(editorView.orthoEnabled ? "Ortho ON" : "Ortho OFF")
    }

    /// The value box at the cursor: always / only while typing (⌥6, F12, View menu, Settings).
    @objc func toggleDynamicInput() {
        editorView.valueBoxAlways.toggle()
        statusBar.showMessage(editorView.valueBoxAlways ? "Value box always visible ON" : "Value box always visible OFF")
    }

    @objc func toggleAskToClose() {
        editorView.askToClose.toggle()
        statusBar.showMessage(editorView.askToClose ? "Ask to close ON" : "Ask to close OFF")
    }

    @objc func toggleLineWeights() {
        editorView.showLineWeights.toggle()
        // saved in the drawing, like Show Grid
        markSettingsChanged()
        statusBar.showMessage(editorView.showLineWeights ? "Lineweights ON" : "Lineweights OFF")
    }

    // MARK: App settings

    private var settingsController: SettingsWindowController?
    private var keyboardShortcutsController: KeyboardShortcutsWindowController?

    /// Help › Keyboard Shortcuts… – an overview of all keys (rebuilt every time it opens).
    @objc func showKeyboardShortcuts(_ sender: Any?) {
        if keyboardShortcutsController == nil { keyboardShortcutsController = KeyboardShortcutsWindowController() }
        keyboardShortcutsController?.show()
    }

    @objc func showSettings(_ sender: Any?) {
        if settingsController == nil {
            let controller = SettingsWindowController()
            controller.onChange = { [weak self] in self?.applyAppSettings() }
            controller.onEditTextStyle = { [weak self] in self?.textStyle(nil) }
            controller.onEditDimensionStyle = { [weak self] in self?.dimensionStyle(nil) }
            controller.textStyleSummary = { [weak self] in
                guard let style = self?.editorView.textStyle else { return "" }
                return "\(style.family.isEmpty ? FontLibrary.systemFamilyTitle : style.family) \(style.face) · \(LineType.format(style.heightMM)) mm on paper · \(style.justify.title)\(style.underline ? " · underlined" : "")"
            }
            settingsController = controller
        }
        settingsController?.show()
    }

    /// Applies changes from Settings to the open window.
    private func applyAppSettings() {
        editorView.smoothLines = AppSettings.smoothLines
        if editorView.valueBoxAlways != AppSettings.valueBoxAlways { editorView.valueBoxAlways = AppSettings.valueBoxAlways }
        editorView.askToClose = AppSettings.askToClose
        editorView.applyCursorSettings()
        statusBar.setPrompt(editorView.prompt)
        updateModes()
    }

    @objc func toggleSmoothLines() {
        editorView.smoothLines.toggle()
        AppSettings.smoothLines = editorView.smoothLines
        statusBar.showMessage(editorView.smoothLines ? "Smooth lines ON" : "Smooth lines OFF")
    }

    @objc func toggleScreenWeights() {
        editorView.lineWeightOnScreen.toggle()
        if !editorView.showLineWeights { editorView.showLineWeights = true }
        markSettingsChanged()
        statusBar.showMessage(editorView.lineWeightOnScreen ? "Lineweights fixed on screen ON" : "Lineweights fixed on screen OFF")
    }

    private func selectScale(_ scale: DrawingScale) {
        if activeTab.activeLayout != nil {
            // on a layout the paper is 1:1 – each viewport has its own scale (Properties)
            statusBar.showMessage("On a layout the sheet is 1:1 – select a viewport and set its scale in Properties")
            updateModes()
            return
        }
        // the scale (and the offer to rescale hatches) belongs to the drawing, not to a block being edited
        guard ensureNoBlockEdit(reason: "The scale \(scale.title) belongs to the whole drawing.") else {
            updateModes()
            return
        }
        let previous = editorView.drawingScale
        editorView.drawingScale = scale
        markSettingsChanged()
        statusBar.showMessage("Scale \(scale.title)")
        offerHatchRescale(from: previous, to: scale)
    }

    /// After a change of the drawing scale: offers to resize the patterns of the existing hatches too, so they keep
    /// their size on paper (line types follow the drawing scale by themselves, a hatch keeps its own scale).
    private func offerHatchRescale(from old: DrawingScale, to new: DrawingScale) {
        let ratio = new.factor / old.factor
        guard ratio.isFinite, ratio > 0, abs(ratio - 1) > 1e-9 else { return }
        // objects on locked layers stay as they are (like in changeSelection)
        let hatches = document.getAllEntities().compactMap { $0 as? HatchEntity }.filter { !layerManager.isLayerLocked($0.layer) }
        guard !hatches.isEmpty else { return }
        switch AppSettings.hatchRescale {
        case .never:
            return
        case .always:
            break
        case .ask:
            let noun = hatches.count == 1 ? "hatch" : "\(hatches.count) hatches"
            let alert = NSAlert()
            alert.messageText = "Rescale the existing hatches too?"
            alert.informativeText = "The scale changed from \(old.title) to \(new.title). The patterns of the \(noun) can follow it "
                + "so they keep their size on paper (pattern scale × \(LineType.format(ratio))). Line types follow the scale by themselves."
            alert.addButton(withTitle: "Rescale Hatches")
            alert.addButton(withTitle: "Keep As They Are")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again (change it in Settings › Styles)"
            let rescale = alert.runModal() == .alertFirstButtonReturn
            if alert.suppressionButton?.state == .on {
                AppSettings.hatchRescale = rescale ? .always : .never
                settingsController?.refresh()
            }
            guard rescale else { return }
        }
        let rescaled = hatches.map { hatch -> CADEntity in
            let copy = hatch.clone()
            if let copy = copy as? HatchEntity { copy.scale = hatch.scale * ratio }
            return copy
        }
        applyChange(removed: hatches, added: rescaled, actionName: "Rescale Hatches")
        editorView.needsDisplay = true
        refreshPanels()
        statusBar.showMessage("Scale \(new.title) · \(hatches.count == 1 ? "1 hatch" : "\(hatches.count) hatches") rescaled")
    }

    /// A new custom scale (remembered for the next launch too).
    @objc func addCustomScale() {
        let alert = NSAlert()
        alert.messageText = "Custom Scale"
        alert.informativeText = "Scale of the drawing as paper:model (e.g. 1:75, 3:1 or just 75 = 1:75):"
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        field.placeholderString = "1:75"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        defer { updateModes() }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard let scale = DrawingScale.parse(field.stringValue) else {
            statusBar.showMessage("“\(field.stringValue)” is not a valid scale.")
            return
        }
        var custom = DrawingScale.custom
        if !custom.contains(scale) && !DrawingScale.presets.contains(scale) {
            custom.append(scale)
            DrawingScale.custom = custom
        }
        selectScale(scale)
    }

    @objc func clearCustomScales() {
        DrawingScale.custom = []
        updateModes()
        statusBar.showMessage("Custom scales removed")
    }

    @objc func toggleLineContinue() {
        editorView.lineContinue.toggle()
        statusBar.setPrompt(editorView.prompt)
        statusBar.showMessage(editorView.lineContinue ? "Continuous lines (LNC) ON" : "Continuous lines (LNC) OFF")
    }

    private func updateModes() {
        statusBar.setModes(snap: editorView.snapEnabled, ortho: editorView.orthoEnabled,
                           askToClose: editorView.askToClose,
                           lineContinue: editorView.lineContinue, lineWeights: editorView.showLineWeights,
                           scale: editorView.drawingScale, screenWeights: editorView.lineWeightOnScreen,
                           gridSnap: editorView.gridSnapEnabled, gridSize: editorView.gridSize,
                           showGrid: editorView.showGrid, showAxes: editorView.showAxes,
                           polar: editorView.polarEnabled, polarIncrement: editorView.polarIncrement,
                           unit: editorView.drawingUnits.suffix)
        statusBar.setSnapTracking(editorView.snapTrackingEnabled)
    }

    @objc func selectArcMethod(_ sender: NSMenuItem) {
        if let method = ArcMethod(rawValue: sender.tag) { toolbarDidSelectArcMethod(method) }
    }

    @objc func toggleSnapType(_ sender: NSMenuItem) {
        guard let type = SnapType.allCases.first(where: { $0.rawValue == sender.representedObject as? String }) else { return }
        var set = AppSettings.enabledSnaps
        if set.contains(type) {
            set.remove(type)
        } else {
            set.insert(type)
            if !editorView.snapEnabled { editorView.snapEnabled = true }
        }
        AppSettings.enabledSnaps = set
    }

    // MARK: Snap point popup (right click on SNAP / ▾)

    private var snapPopover: NSPopover?

    private func showSnapSettings(relativeTo anchor: NSView) {
        if let popover = snapPopover, popover.isShown {
            popover.performClose(nil)
            return
        }
        let panel = SnapSettingsPanel(compact: true)
        panel.onChange = { [weak self] turnedOn in
            guard let self = self else { return }
            if turnedOn && !self.editorView.snapEnabled { self.editorView.snapEnabled = true }
        }
        let popover = NSPopover()
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        snapPopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    @objc func showSnapSettingsFromMenu(_ sender: Any?) {
        showSnapSettings(relativeTo: statusBar.snapAnchor)
    }

    // MARK: Helpers

    /// Before closing the window / quitting: asks about each tab with unsaved changes in turn
    /// (no summary dialog first). Returns true if it is OK to continue.
    func confirmDiscardChanges() -> Bool {
        guard ensureNoBlockEdit() else { return false }
        let edited = tabs.filter { $0.isEdited }
        guard !edited.isEmpty else { return true }
        for tab in edited {
            guard let index = tabs.firstIndex(where: { $0 === tab }) else { continue }
            activateTab(index)
            guard confirmCloseActiveTab() else { return false }
        }
        return true
    }

    private func showError(title: String, error: Error) {
        Log.error("\(title): \(error.localizedDescription) [\(String(describing: error))]")
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .critical
        alert.runModal()
    }

    // MARK: Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        switch action {
        case #selector(selectNextTab(_:)), #selector(selectPreviousTab(_:)):
            return tabs.count > 1
        case #selector(saveBlockEdit(_:)), #selector(discardBlockEdit(_:)):
            return activeTab.blockEdit != nil
        case #selector(editBlockFromMenu(_:)):
            return activeTab.blockEdit == nil
        case #selector(toggleSimilarProperty(_:)):
            if let raw = menuItem.representedObject as? String, let property = SimilarProperty(rawValue: raw) {
                menuItem.state = AppSettings.similarProperties.contains(property) ? .on : .off
            }
            return true
        case #selector(undoAction(_:)):
            menuItem.title = undoer.undoMenuItemTitle
            return undoer.canUndo || editorView.isBusy
        case #selector(redoAction(_:)):
            menuItem.title = undoer.redoMenuItemTitle
            return undoer.canRedo
        case #selector(deleteSelection), #selector(copy(_:)), #selector(cut(_:)):
            return !selectionManager.isEmpty
        case #selector(paste(_:)), #selector(pasteAtOriginalCoordinates(_:)):
            return !DrawingClipboard.shared.isEmpty
        case #selector(selectToolFromMenu(_:)):
            menuItem.state = menuItem.tag == currentTool.rawValue ? .on : .off
            return true
        case #selector(toggleGrid):
            menuItem.state = editorView.showGrid ? .on : .off
            return true
        case #selector(toggleAxes):
            menuItem.state = editorView.showAxes ? .on : .off
            return true
        case #selector(toggleSnap):
            menuItem.state = editorView.snapEnabled ? .on : .off
            return true
        case #selector(toggleOrtho):
            menuItem.state = editorView.orthoEnabled ? .on : .off
            return true
        case #selector(toggleSnapTracking):
            menuItem.state = editorView.snapTrackingEnabled ? .on : .off
            return true
        case #selector(toggleGridSnap):
            menuItem.state = editorView.gridSnapEnabled ? .on : .off
            return true
        case #selector(togglePolar):
            menuItem.state = editorView.polarEnabled ? .on : .off
            return true
        case #selector(toggleDynamicInput):
            menuItem.state = editorView.valueBoxAlways ? .on : .off
            return true
        case #selector(toggleAskToClose):
            menuItem.state = editorView.askToClose ? .on : .off
            return true
        case #selector(toggleLineWeights):
            menuItem.state = editorView.showLineWeights ? .on : .off
            return true
        case #selector(toggleScreenWeights):
            menuItem.state = editorView.lineWeightOnScreen ? .on : .off
            return true
        case #selector(toggleSmoothLines):
            menuItem.state = editorView.smoothLines ? .on : .off
            return true
        case #selector(toggleLineContinue):
            menuItem.state = editorView.lineContinue ? .on : .off
            return true
        case #selector(selectHatchPattern(_:)):
            menuItem.state = (menuItem.representedObject as? String) == editorView.hatchPattern.name ? .on : .off
            return true
        case #selector(selectArcMethod(_:)):
            menuItem.state = menuItem.tag == editorView.arcMethod.rawValue ? .on : .off
            return true
        case #selector(selectArrayKind(_:)):
            menuItem.state = currentTool == .array && menuItem.tag == editorView.arrayKind.rawValue ? .on : .off
            return true
        case #selector(selectMeasureKind(_:)):
            menuItem.state = currentTool == .measure && menuItem.tag == editorView.measureKind.rawValue ? .on : .off
            return true
        case #selector(bringToFront(_:)), #selector(sendToBack(_:)), #selector(bringForward(_:)), #selector(sendBackward(_:)),
             #selector(bringAboveObject(_:)), #selector(sendUnderObject(_:)):
            return !selectionManager.isEmpty
        case #selector(groupSelection(_:)):
            return selectionManager.count >= 2
        case #selector(selectSimilar(_:)):
            return true
        case #selector(ungroupSelection(_:)):
            return !selectionManager.isEmpty
                && selectionManager.getSelectedEntities(from: document.getAllEntities()).contains { $0.groupID != nil }
        case #selector(toggleWholeGroups(_:)):
            menuItem.state = AppSettings.selectWholeGroups ? .on : .off
            return true
        case #selector(toggleSnapType(_:)):
            let enabled = SnapType.allCases.contains {
                $0.rawValue == menuItem.representedObject as? String && editorView.snapManager.enabledSnaps.contains($0)
            }
            menuItem.state = enabled ? .on : .off
            return true
        case #selector(toggleLayerPanel):
            menuItem.state = layersVisible ? .on : .off
            return true
        case #selector(showModelSpace(_:)):
            menuItem.state = activeTab.activeLayout == nil ? .on : .off
            return true
        case #selector(addViewport(_:)), #selector(duplicateLayoutFromMenu(_:)), #selector(renameLayoutFromMenu(_:)),
             #selector(pageSetupFromMenu(_:)), #selector(deleteLayoutFromMenu(_:)):
            return activeTab.activeLayout != nil
        case #selector(printDrawing(_:)), #selector(exportPDF(_:)), #selector(exportImage(_:)):
            return plotDialog == nil
        case #selector(togglePropertiesPanel):
            let hidden = propertiesMode == .closed || (propertiesMode == .docked && (trayCollapsed || propertiesFolded))
            menuItem.state = hidden ? .off : .on
            return true
        case #selector(collapseProperties):
            menuItem.state = trayCollapsed ? .on : .off
            return true
        case #selector(toggleTraySide(_:)):
            menuItem.state = trayOnLeft ? .on : .off
            return true
        case #selector(toggleInfoPanel(_:)):
            menuItem.state = infoShown && !trayCollapsed && !infoFolded ? .on : .off
            return true
        case #selector(detachProperties):
            menuItem.state = propertiesMode == .detached ? .on : .off
            return true
        default:
            return true
        }
    }
}

// MARK: - Menu Setup

extension MainViewController {

    func setupMenus() {
        let mainMenu = NSMenu()

        @discardableResult
        func item(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                  modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
            menuItem.keyEquivalentModifierMask = modifiers
            menuItem.target = target
            menu.addItem(menuItem)
            return menuItem
        }

        func submenu(_ title: String, in parent: NSMenu? = nil, image: NSImage? = nil) -> NSMenu {
            let menu = NSMenu(title: title)
            let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            menuItem.submenu = menu
            menuItem.image = image
            (parent ?? mainMenu).addItem(menuItem)
            return menu
        }

        // Menu icons: drawing functions show the icons of the tool panel, common commands
        // Apple's symbols (as the system's own menus do); toggles and lists have none.
        func symbol(_ name: String) -> NSImage? {
            return NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        func icon(_ menuIcon: MenuIcon) -> NSImage {
            return ToolIcons.image(for: menuIcon, size: 17)
        }
        let settingsIcon = ToolIcons.settingsImage(size: 17)

        // App
        let appMenu = submenu("OreMonoCAD")
        item(appMenu, "About OreMonoCAD", #selector(NSApplication.orderFrontStandardAboutPanel(_:))).image = symbol("info.circle")
        appMenu.addItem(.separator())
        item(appMenu, "Settings…", #selector(showSettings(_:)), ",", target: self).image = symbol("gearshape")
        // also here, next to Settings (where shortcuts are changed) – the same window as Help › Keyboard Shortcuts… and F1
        item(appMenu, "Keyboard Shortcuts…  (F1)", #selector(showKeyboardShortcuts(_:)), modifiers: [], target: self).image = symbol("keyboard")
        appMenu.addItem(.separator())
        item(appMenu, "Hide OreMonoCAD", #selector(NSApplication.hide(_:)), "h").image = symbol("eye.slash")
        item(appMenu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", modifiers: [.command, .option]).image = symbol("eye.slash.circle")
        item(appMenu, "Show All", #selector(NSApplication.unhideAllApplications(_:)), modifiers: []).image = symbol("eye")
        appMenu.addItem(.separator())
        item(appMenu, "Quit OreMonoCAD", #selector(NSApplication.terminate(_:)), "q").image = symbol("power")

        // File
        let fileMenu = submenu("File")
        item(fileMenu, "New", #selector(newDocument(_:)), "n", target: self).image = symbol("doc.badge.plus")
        item(fileMenu, "New Tab", #selector(newTab(_:)), "t", target: self).image = symbol("plus.square.on.square")
        item(fileMenu, "Open…", #selector(openDocument(_:)), "o", target: self).image = symbol("folder")
        let recentMenu = submenu("Open Recent", in: fileMenu, image: symbol("clock"))
        recentMenu.delegate = self      // items are filled in in menuNeedsUpdate
        item(fileMenu, "Open Backup…", #selector(openBackup(_:)), modifiers: [], target: self).image = symbol("clock.arrow.circlepath")
        item(fileMenu, "Import…", #selector(importDocument(_:)), "i", modifiers: [.command, .shift], target: self).image = symbol("tray.and.arrow.down")
        fileMenu.addItem(.separator())
        item(fileMenu, "Save", #selector(saveDocument(_:)), "s", target: self).image = symbol("square.and.arrow.down")
        item(fileMenu, "Save As…", #selector(saveDocumentAs(_:)), "s", modifiers: [.command, .shift], target: self).image = symbol("square.and.arrow.down.on.square")
        item(fileMenu, "Export DXF…", #selector(exportDXF(_:)), "e", modifiers: [.command, .shift], target: self).image = symbol("square.and.arrow.up")
        item(fileMenu, "Export DXF in S-JTSK…", #selector(exportSurveyDXF(_:)), modifiers: [], target: self).image = symbol("globe")
        item(fileMenu, "Export PDF…", #selector(exportPDF(_:)), "p", modifiers: [.command, .option], target: self).image = symbol("doc.richtext")
        item(fileMenu, "Export Image (PNG, JPEG, TIFF)…", #selector(exportImage(_:)), "e", modifiers: [.command, .option], target: self).image = symbol("photo")
        fileMenu.addItem(.separator())
        item(fileMenu, "Plot / Print…", #selector(printDrawing(_:)), "p", target: self).image = symbol("printer")
        fileMenu.addItem(.separator())
        item(fileMenu, "Close Tab", #selector(closeCurrentTab(_:)), "w", target: self).image = symbol("xmark")
        item(fileMenu, "Close Window", #selector(NSWindow.performClose(_:)), "w", modifiers: [.command, .shift]).image = symbol("xmark.square")

        // Edit
        let editMenu = submenu("Edit")
        item(editMenu, "Undo", #selector(undoAction(_:)), "z", target: self).image = symbol("arrow.uturn.backward")
        item(editMenu, "Redo", #selector(redoAction(_:)), "z", modifiers: [.command, .shift], target: self).image = symbol("arrow.uturn.forward")
        editMenu.addItem(.separator())
        // without a target: a text field being edited (layer renaming…) gets them first, otherwise the drawing objects
        item(editMenu, "Cut", #selector(NSText.cut(_:)), "x").image = symbol("scissors")
        item(editMenu, "Copy", #selector(NSText.copy(_:)), "c").image = symbol("doc.on.doc")
        item(editMenu, "Paste", #selector(NSText.paste(_:)), "v").image = symbol("doc.on.clipboard")
        item(editMenu, "Paste at Original Coordinates", #selector(pasteAtOriginalCoordinates(_:)), "v",
             modifiers: [.command, .shift], target: self).image = icon(.pasteAtOrigin)
        editMenu.addItem(.separator())
        item(editMenu, "Delete", #selector(deleteSelection), "\u{8}", target: self).image = symbol("trash")
        item(editMenu, "Select All", #selector(selectAllEntities(_:)), "a", target: self).image = DrawingTool.select.icon(pointSize: 13)
        item(editMenu, "Select Similar", #selector(selectSimilar(_:)), "a", modifiers: [.command, .shift], target: self).image = DrawingTool.selectSimilar.icon(pointSize: 13)
        item(editMenu, "Find and Replace…", #selector(findAndReplace(_:)), "f", target: self).image = symbol("magnifyingglass")
        let similarMenu = submenu("Select Similar Matches", in: editMenu, image: settingsIcon)
        for property in SimilarProperty.allCases {
            let menuItem = item(similarMenu, property.title, #selector(toggleSimilarProperty(_:)), modifiers: [], target: self)
            menuItem.representedObject = property.rawValue
            menuItem.toolTip = property.detail
        }
        let filter = item(editMenu, "Filter…", #selector(filterObjects(_:)), modifiers: [], target: self)
        filter.toolTip = "Selects the objects that match chosen properties – type, layer, color, linetype, lineweight, block, hatch pattern, text, text height, length, area"
        filter.image = DrawingTool.filter.icon(pointSize: 13)
        editMenu.addItem(.separator())
        let orderMenu = submenu("Draw Order", in: editMenu, image: symbol("square.3.layers.3d"))
        item(orderMenu, "Bring to Front", #selector(bringToFront(_:)), "f", modifiers: [.command, .shift], target: self).image = symbol("square.3.layers.3d.top.filled")
        item(orderMenu, "Bring Forward", #selector(bringForward(_:)), "f", modifiers: [.command, .shift, .option], target: self).image = symbol("square.2.layers.3d.top.filled")
        item(orderMenu, "Send Backward", #selector(sendBackward(_:)), "b", modifiers: [.command, .shift, .option], target: self).image = symbol("square.2.layers.3d.bottom.filled")
        item(orderMenu, "Send to Back", #selector(sendToBack(_:)), "b", modifiers: [.command, .shift], target: self).image = symbol("square.3.layers.3d.bottom.filled")
        orderMenu.addItem(.separator())
        let aboveObject = item(orderMenu, "Bring Above Object", #selector(bringAboveObject(_:)), "", target: self)
        aboveObject.toolTip = "Puts the selection just above an object you click"
        aboveObject.image = symbol("arrow.up.square")
        let underObject = item(orderMenu, "Send Under Object", #selector(sendUnderObject(_:)), "", target: self)
        underObject.toolTip = "Puts the selection just under an object you click"
        underObject.image = symbol("arrow.down.square")
        editMenu.addItem(.separator())
        let group = item(editMenu, "Group", #selector(groupSelection(_:)), "g", modifiers: [.command, .option], target: self)
        group.toolTip = "The selected objects become one group – a click on one of them selects them all"
        group.image = icon(.group)
        let ungroup = item(editMenu, "Ungroup", #selector(ungroupSelection(_:)), "g", modifiers: [.command, .option, .shift], target: self)
        ungroup.toolTip = "The selected groups fall apart into separate objects"
        ungroup.image = icon(.ungroup)
        item(editMenu, "Select Groups as a Whole", #selector(toggleWholeGroups(_:)), modifiers: [], target: self)
            .toolTip = "Off = a click selects a single object of a group, e.g. to edit it alone"

        // Tools – by group, the shortcuts work on the drawing area
        let toolsMenu = submenu("Tools")
        for group in ToolGroup.allCases {
            if group != .draw { toolsMenu.addItem(.separator()) }
            let header = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            header.isEnabled = false
            toolsMenu.addItem(header)
            var tools = DrawingTool.tools(in: group)
            // MagicTrim before Trim, as on their combined button
            if let magic = tools.firstIndex(of: .magicTrim), let trim = tools.firstIndex(of: .trim), magic > trim {
                tools.insert(tools.remove(at: magic), at: trim)
            }
            for tool in tools {
                let menuItem = item(toolsMenu, tool.menuTitle, #selector(selectToolFromMenu(_:)),
                                    modifiers: [], target: self)
                menuItem.tag = tool.rawValue
                menuItem.image = tool.icon(pointSize: 13)
            }
        }

        // Rebuild Hatch and Cut Out of Hatch are in the menu above as tools (Draw group).
        // Tool and style settings are in the Format menu, here only the tools and their kinds.
        toolsMenu.addItem(.separator())
        let arrayMenu = submenu("Array", in: toolsMenu, image: DrawingTool.array.icon(pointSize: 13))
        for kind in ArrayKind.allCases {
            let menuItem = item(arrayMenu, kind.title, #selector(selectArrayKind(_:)), modifiers: [], target: self)
            menuItem.tag = kind.rawValue
            menuItem.image = ToolIcons.image(for: kind, size: 18)
            menuItem.subtitle = kind.detail
        }

        let measureMenu = submenu("Measure", in: toolsMenu, image: DrawingTool.measure.icon(pointSize: 13))
        for kind in MeasureKind.allCases {
            let menuItem = item(measureMenu, kind.title, #selector(selectMeasureKind(_:)), modifiers: [], target: self)
            menuItem.tag = kind.rawValue
            menuItem.image = ToolIcons.image(for: kind, size: 18)
            menuItem.subtitle = kind.detail
        }

        // Insert – blocks and external references
        let insertMenu = submenu("Insert")
        let blockCreate = item(insertMenu, "Create Block", #selector(selectToolFromMenu(_:)), modifiers: [], target: self)
        blockCreate.tag = DrawingTool.blockCreate.rawValue
        blockCreate.image = DrawingTool.blockCreate.icon(pointSize: 13)
        let blockList = submenu("Insert Block", in: insertMenu, image: DrawingTool.blockInsert.icon(pointSize: 13))
        blockList.delegate = self      // the block list is filled in in menuNeedsUpdate
        item(insertMenu, "Block Manager…", #selector(showBlockManager(_:)), "b", modifiers: [.command, .option], target: self).image = settingsIcon
        item(insertMenu, "Edit Block…", #selector(editBlockFromMenu(_:)), modifiers: [], target: self).image = icon(.editBlock)
        item(insertMenu, "Save Block Changes", #selector(saveBlockEdit(_:)), "s", modifiers: [.command, .option], target: self).image = symbol("checkmark")
        item(insertMenu, "Discard Block Changes", #selector(discardBlockEdit(_:)), modifiers: [], target: self).image = symbol("xmark.circle")
        insertMenu.addItem(.separator())
        let attach = item(insertMenu, "Attach External Reference…", #selector(attachXref(_:)), modifiers: [], target: self)
        attach.image = DrawingTool.xref.icon(pointSize: 13)
        item(insertMenu, "Reload External References", #selector(reloadXrefs(_:)), modifiers: [], target: self).image = symbol("arrow.clockwise")
        insertMenu.addItem(.separator())
        let attachPicture = item(insertMenu, "Attach Image Reference…", #selector(attachImage(_:)), modifiers: [], target: self)
        attachPicture.image = DrawingTool.image.icon(pointSize: 13)
        let attachPDFPage = item(insertMenu, "Attach PDF Reference…", #selector(attachPDF(_:)), modifiers: [], target: self)
        attachPDFPage.image = DrawingTool.pdfReference.icon(pointSize: 13)

        // Format – drawing, style and tool settings
        let formatMenu = submenu("Format")
        item(formatMenu, "Document Settings…", #selector(documentSettings(_:)), ",", modifiers: [.command, .option], target: self).image = settingsIcon
        let ucsMenu = submenu("Drawing Coordinates", in: formatMenu, image: icon(.drawingCoordinates))
        item(ucsMenu, "Align to Object", #selector(ucsFromObject(_:)), modifiers: [], target: self)
        item(ucsMenu, "By Two Points", #selector(ucsFromTwoPoints(_:)), modifiers: [], target: self)
        item(ucsMenu, "By Angle…", #selector(ucsByAngle(_:)), modifiers: [], target: self)
        ucsMenu.addItem(.separator())
        item(ucsMenu, "World (No Rotation)", #selector(ucsWorld(_:)), modifiers: [], target: self)
        item(formatMenu, "Geodetic Base Point…", #selector(editGeoReference(_:)), modifiers: [], target: self).image = icon(.geodeticBasePoint)
        formatMenu.addItem(.separator())
        item(formatMenu, "Text Style…", #selector(textStyle(_:)), modifiers: [], target: self).image = DrawingTool.text.icon(pointSize: 13)
        item(formatMenu, "Dimension Style…", #selector(dimensionStyle(_:)), modifiers: [], target: self).image = DrawingTool.dimLinear.icon(pointSize: 13)
        let hatchMenu = submenu("Hatch Pattern", in: formatMenu, image: DrawingTool.hatch.icon(pointSize: 13))
        hatchMenu.delegate = self      // items are filled in in menuNeedsUpdate
        formatMenu.addItem(.separator())
        let arcMenu = submenu("Arc Method", in: formatMenu, image: DrawingTool.arc.icon(pointSize: 13))
        for method in ArcMethod.allCases {
            let menuItem = item(arcMenu, method.title, #selector(selectArcMethod(_:)), modifiers: [], target: self)
            menuItem.tag = method.rawValue
            menuItem.image = ToolIcons.image(for: method, size: 18)
            menuItem.subtitle = method.detail
        }
        item(formatMenu, "Fillet Radius…", #selector(setFilletRadius(_:)), modifiers: [], target: self).image = DrawingTool.fillet.icon(pointSize: 13)
        item(formatMenu, "Chamfer Distances…", #selector(setChamferDistances(_:)), modifiers: [], target: self).image = DrawingTool.chamfer.icon(pointSize: 13)

        // View
        let viewMenu = submenu("View")
        item(viewMenu, "Zoom In", #selector(zoomIn), "=", target: self).image = DrawingTool.zoomIn.icon(pointSize: 13)
        item(viewMenu, "Zoom Out", #selector(zoomOut), "-", target: self).image = DrawingTool.zoomOut.icon(pointSize: 13)
        item(viewMenu, "Zoom Extents", #selector(zoomExtents), "e", target: self).image = DrawingTool.zoomExtents.icon(pointSize: 13)
        item(viewMenu, "Zoom Selected", #selector(zoomSelected(_:)), "e", modifiers: [.command, .control], target: self).image = DrawingTool.zoomSelected.icon(pointSize: 13)
        item(viewMenu, "Zoom Window", #selector(zoomWindow(_:)), modifiers: [], target: self).image = DrawingTool.zoomWindow.icon(pointSize: 13)
        viewMenu.addItem(.separator())
        item(viewMenu, "Save View…", #selector(saveNamedView(_:)), "v", modifiers: [.command, .option], target: self).image = symbol("bookmark")
        let namedViewsMenu = submenu("Named Views", in: viewMenu, image: symbol("rectangle.stack"))
        namedViewsMenu.delegate = self      // items are filled in in menuNeedsUpdate
        viewMenu.addItem(.separator())
        item(viewMenu, "Rotate View…", #selector(rotateViewByAngle(_:)), modifiers: [], target: self).image = symbol("rotate.right")
        item(viewMenu, "Rotate View to Drawing Coordinates", #selector(rotateViewToUCS(_:)), modifiers: [], target: self).image = icon(.rotateToCoordinates)
        item(viewMenu, "Reset View Rotation", #selector(resetViewRotation(_:)), modifiers: [], target: self).image = DrawingTool.northArrow.icon(pointSize: 13)
        viewMenu.addItem(.separator())
        item(viewMenu, "Layers Panel", #selector(toggleLayerPanel), "1", target: self).image = ToolIcons.image(for: MatchProperty.layer, size: 17)
        item(viewMenu, "Properties Panel", #selector(togglePropertiesPanel), "2", target: self).image = symbol("list.bullet.rectangle")
        item(viewMenu, "Info Panel  (F2)", #selector(toggleInfoPanel(_:)), "3", target: self).image = symbol("info.square")
        // which tool panel sections to show (the panel fills the submenu each time it opens)
        if let toolbarView = toolbarView {
            let toolPanelItem = NSMenuItem(title: "Tool Panel", action: nil, keyEquivalent: "")
            toolPanelItem.submenu = toolbarView.makeToolPanelMenu()
            toolPanelItem.image = icon(.toolPanel)
            viewMenu.addItem(toolPanelItem)
        }
        item(viewMenu, "Reset Side Panel Layout", #selector(resetTrayLayout(_:)), modifiers: [], target: self).image = symbol("rectangle.split.3x1")
        item(viewMenu, "Collapse Side Panel", #selector(collapseProperties), "0", target: self).image = symbol("sidebar.right")
        item(viewMenu, "Side Panel on the Left", #selector(toggleTraySide(_:)), target: self).image = symbol("sidebar.left")
        item(viewMenu, "Properties in a Separate Window", #selector(detachProperties), target: self).image = symbol("macwindow.on.rectangle")
        // Enter Full Screen (⌃⌘F) is added to the View menu by macOS itself
        viewMenu.addItem(.separator())
        item(viewMenu, "Show Grid  (⌥2, F7)", #selector(toggleGrid), modifiers: [], target: self)
        item(viewMenu, "Show Axes", #selector(toggleAxes), modifiers: [], target: self)
        // drawing modes (status line); ⌥ + digit and F-keys are caught by the window (handleModeKey)
        let aidsMenu = submenu("Drawing Aids", in: viewMenu, image: icon(.drawingAids))
        item(aidsMenu, "Snap  (⌥3, F3)", #selector(toggleSnap), modifiers: [], target: self)
        item(aidsMenu, "Snap Tracking  (⌥1, F11)", #selector(toggleSnapTracking), modifiers: [], target: self)
        item(aidsMenu, "Ortho  (⌥8, F8, or hold Shift)", #selector(toggleOrtho), modifiers: [], target: self)
        item(aidsMenu, "Snap to Grid  (⌥9, F9)", #selector(toggleGridSnap), modifiers: [], target: self)
        item(aidsMenu, "Polar Angles  (⌥0, F10)", #selector(togglePolar), modifiers: [], target: self)
        item(aidsMenu, "Value Box Always Visible  (⌥6, F12)", #selector(toggleDynamicInput), modifiers: [], target: self)
        item(aidsMenu, "Ask to Close Polylines & Splines  (⌥4, F4)", #selector(toggleAskToClose), modifiers: [], target: self)
        item(aidsMenu, "Continuous Lines – LNC  (⌥7, F6)", #selector(toggleLineContinue), modifiers: [], target: self)
        aidsMenu.addItem(.separator())
        let snapMenu = submenu("Snap Points", in: aidsMenu)
        for type in SnapType.allCases {
            let menuItem = item(snapMenu, type.rawValue, #selector(toggleSnapType(_:)), modifiers: [], target: self)
            menuItem.representedObject = type.rawValue
            menuItem.image = SnapMarker.image(type, size: 14)
            menuItem.toolTip = type.detail
        }
        snapMenu.addItem(.separator())
        item(snapMenu, "Snap Points Panel…", #selector(showSnapSettingsFromMenu(_:)), modifiers: [], target: self)
        viewMenu.addItem(.separator())
        item(viewMenu, "Show Lineweights – LWT  (⌥5, F5)", #selector(toggleLineWeights), "l", modifiers: [.command, .shift], target: self)
        item(viewMenu, "Lineweights Fixed on Screen", #selector(toggleScreenWeights), target: self)
        item(viewMenu, "Smooth Lines (Antialiasing)", #selector(toggleSmoothLines), target: self)
        item(viewMenu, "Custom Scale…", #selector(addCustomScale), target: self).image = DrawingTool.scaleBar.icon(pointSize: 13)

        // Layout
        let layoutMenu = submenu("Layout")
        item(layoutMenu, "Model", #selector(showModelSpace(_:)), "0", modifiers: [.command, .control], target: self).image = icon(.model)
        let layoutsItem = NSMenuItem(title: "Layouts", action: nil, keyEquivalent: "")
        let layoutsList = NSMenu(title: "Layouts")
        layoutsList.delegate = self
        layoutsItem.submenu = layoutsList
        layoutsItem.image = icon(.layouts)
        layoutMenu.addItem(layoutsItem)
        layoutMenu.addItem(.separator())
        item(layoutMenu, "New Layout", #selector(newLayout(_:)), "l", modifiers: [.command, .control], target: self).image = icon(.newLayout)
        item(layoutMenu, "Duplicate Layout", #selector(duplicateLayoutFromMenu(_:)), modifiers: [], target: self).image = icon(.duplicateLayout)
        item(layoutMenu, "Rename Layout…", #selector(renameLayoutFromMenu(_:)), modifiers: [], target: self).image = symbol("pencil")
        item(layoutMenu, "Page Setup…", #selector(pageSetupFromMenu(_:)), "p", modifiers: [.command, .shift], target: self).image = settingsIcon
        item(layoutMenu, "Delete Layout…", #selector(deleteLayoutFromMenu(_:)), modifiers: [], target: self).image = symbol("trash")
        layoutMenu.addItem(.separator())
        item(layoutMenu, "Add Viewport", #selector(addViewport(_:)), "v", modifiers: [.command, .control], target: self).image = icon(.viewport)
        layoutMenu.addItem(.separator())
        item(layoutMenu, "Plot / Print…", #selector(printDrawing(_:)), modifiers: [], target: self).image = symbol("printer")

        // Window
        let windowMenu = submenu("Window")
        item(windowMenu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m").image = symbol("minus.square")
        item(windowMenu, "Zoom", #selector(NSWindow.performZoom(_:)), modifiers: []).image = symbol("arrow.up.left.and.arrow.down.right")
        windowMenu.addItem(.separator())
        item(windowMenu, "Show Next Tab  (⇧⌘])", #selector(selectNextTab(_:)), "\t", modifiers: [.control], target: self).image = symbol("chevron.right")
        item(windowMenu, "Show Previous Tab  (⇧⌘[)", #selector(selectPreviousTab(_:)), "\t", modifiers: [.control, .shift], target: self).image = symbol("chevron.left")
        NSApp.windowsMenu = windowMenu

        // Help (macOS adds menu search to it by itself)
        let helpMenu = submenu("Help")
        item(helpMenu, "Keyboard Shortcuts…  (F1)", #selector(showKeyboardShortcuts(_:)), modifiers: [], target: self).image = symbol("keyboard")
        helpMenu.addItem(.separator())
        item(helpMenu, "Report a Problem…", #selector(reportProblem(_:)), modifiers: [], target: self).image = symbol("exclamationmark.bubble")
        item(helpMenu, "Show Log in Finder", #selector(showLogInFinder(_:)), modifiers: [], target: self).image = symbol("doc.text")
        #if DEBUG
        // development build only: test the crash report (run outside Xcode – there Xcode catches the crash)
        helpMenu.addItem(.separator())
        item(helpMenu, "Simulate Crash (Debug Build Only)", #selector(simulateCrash(_:)), modifiers: [], target: self)
        #endif
        NSApp.helpMenu = helpMenu

        NSApp.mainMenu = mainMenu
    }
}

// MARK: - Problem report (Help)

extension MainViewController {
    @objc func reportProblem(_ sender: Any?) {
        editorView.cancelCurrentOperation()
        let tab = activeTab
        let hasDrawing = !tab.document.isEmpty || !tab.layouts.isEmpty
        Log.info("Report a Problem…")
        ProblemReporter.reportProblem(summary: diagnosticSummary(), drawingName: hasDrawing ? tab.title : nil,
                                      writeDrawing: { [weak self] url in try self?.writeDrawingCopy(to: url) })
    }

    @objc func showLogInFinder(_ sender: Any?) {
        ProblemReporter.showLogInFinder()
    }

    #if DEBUG
    @objc func simulateCrash(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Simulate a crash?"
        alert.informativeText = "OreMonoCAD will stop immediately, unsaved changes are lost. "
            + "Start it again afterwards – it should offer to save a problem report and to recover "
            + "drawings changed more than about 15 seconds ago. "
            + "Run the app outside Xcode for this test; under Xcode the debugger catches the crash first."
        alert.addButton(withTitle: "Crash Now")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Log.warning("Simulated crash (Help › Simulate Crash)")
        fatalError("Simulated crash (Help › Simulate Crash)")
    }
    #endif

    /// App state for the report: open drawings and the tool.
    func diagnosticSummary() -> String {
        var lines = ["Open drawings (* = active):"]
        for (index, tab) in tabs.enumerated() {
            let marker = index == activeIndex ? "*" : " "
            let objects = tab.document.getAllEntities().count
            var line = "  \(marker) \(tab.title)"
            if tab.isEdited { line += " (unsaved changes)" }
            line += " - \(objects) object(s), units \(tab.units.suffix), \(tab.layouts.count) layout(s), "
            line += "\(tab.blocks.definitions.count) block(s)"
            if tab.fileURL?.pathExtension.lowercased() == "dxf" { line += ", opened from DXF" }
            lines.append(line)
        }
        lines.append("Current tool: \(currentTool.title)" + (activeTab.activeLayout != nil ? " · on a layout sheet" : " · in the model"))
        return lines.joined(separator: "\n")
    }

    /// A copy of the open drawing for the report – without changing its file, name or saved state.
    func writeDrawingCopy(to url: URL) throws {
        let settings = currentSettings()
        let tab = activeTab
        tab.restoreReferencedBlocks()
        try NativeFormat.write(entities: tab.document.getAllEntities(),
                               layers: layerManager.getAllLayers(),
                               currentLayer: layerManager.currentLayerName,
                               settings: settings,
                               layouts: tab.layouts,
                               activeLayout: tab.activeLayoutIndex,
                               pageSetups: tab.pageSetups,
                               modelPlot: tab.modelPlotSettings,
                               blocks: tab.blocks,
                               namedViews: tab.namedViews,
                               to: url)
    }
}

// MARK: - Auto-save, crash recovery, backups (Recovery.swift)

extension MainViewController {
    /// Every 15 s: changed drawings waiting longer than the set interval are quietly saved.
    @objc func autosaveTimerFired(_ timer: Timer) {
        autosaveChangedTabs(ignoringInterval: false)
    }

    /// Switching to another app (or sleep) → save right away, don't wait for the interval.
    @objc func applicationWillResignActive(_ notification: Notification) {
        autosaveChangedTabs(ignoringInterval: true)
    }

    private func autosaveChangedTabs(ignoringInterval: Bool) {
        let minutes = AppSettings.autosaveMinutes
        guard minutes > 0 else { return }
        // not in the middle of a drag, an operation in progress, text typing or an open dialog – it tries next time
        guard NSEvent.pressedMouseButtons == 0, NSApp.modalWindow == nil,
              !editorView.isBusy, !editorView.isEditingText else { return }
        let interval = TimeInterval(minutes * 60)
        let now = Date()
        for tab in tabs where tab.isEdited && tab.changeCount != tab.autosavedChangeCount {
            // the first change after opening or saving is auto-saved at the next tick, so a crash
            // shortly after starting to draw does not lose everything; then the set interval applies
            if ignoringInterval || !tab.hasAutosave || now.timeIntervalSince(tab.lastAutosave) >= interval {
                autosave(tab)
            }
        }
    }

    /// The drawing record is assembled here (main thread) and written in the background.
    private func autosave(_ tab: DrawingTab) {
        let started = Date()
        tab.restoreReferencedBlocks()
        let entities = tab.document.getAllEntities()
        let file = NativeFormat.makeFile(entities: entities,
                                         layers: tab.layerManager.getAllLayers(),
                                         currentLayer: tab.layerManager.currentLayerName,
                                         settings: settings(for: tab),
                                         layouts: tab.layouts,
                                         activeLayout: tab.activeLayoutIndex,
                                         pageSetups: tab.pageSetups,
                                         modelPlot: tab.modelPlotSettings,
                                         blocks: tab.blocks,
                                         namedViews: tab.namedViews)
        let original = tab.fileURL ?? tab.suggestedSaveURL
        let manifest = AutoSaveManifest(id: tab.autosaveID,
                                        title: tab.fileURL == nil ? (tab.suggestedName ?? tab.title) : tab.title,
                                        originalPath: original?.path,
                                        savedAt: Date(),
                                        objectCount: entities.count,
                                        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        tab.autosavedChangeCount = tab.changeCount
        tab.lastAutosave = Date()
        tab.hasAutosave = true
        AutoSaveStore.write(file, manifest: manifest)
        let milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        if milliseconds > 250 { Log.warning("Auto-save of \u{201C}\(manifest.title)\u{201D} held the app for \(milliseconds) ms") }
    }

    /// The drawing is saved / freshly loaded / closed → its auto-save is no longer needed.
    private func forgetAutosave(of tab: DrawingTab) {
        AutoSaveStore.remove(tab.autosaveID)
        tab.autosavedChangeCount = tab.changeCount
        tab.lastAutosave = Date()
        tab.hasAutosave = false
    }

    /// Clean quit: the user decided on every drawing (save / discard) → this session's auto-saves are removed.
    /// Auto-saves from last time for which “Decide Later” was chosen stay.
    func discardSessionAutosaves() {
        for tab in tabs { AutoSaveStore.remove(tab.autosaveID) }
        AutoSaveStore.flush()
    }

    // MARK: Recovery after launch

    /// Auto-saves from last time were left → offer to recover them. true = something was recovered.
    @discardableResult
    func offerRecovery() -> Bool {
        BackupStore.cleanUp()
        let entries = AutoSaveStore.entries()
        guard !entries.isEmpty else { return false }
        Log.info("Found \(entries.count) auto-saved drawing(s) from an earlier session")

        while true {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = entries.count == 1
                ? "Recover unsaved work?"
                : "Recover unsaved work in \(entries.count) drawings?"
            var list = entries.prefix(8).map { RecoveryText.line(for: $0) }.joined(separator: "\n")
            if entries.count > 8 { list += "\n\u{2026} and \(entries.count - 8) more" }
            alert.informativeText = "OreMonoCAD did not quit properly, so these changes were never saved to their files. "
                + "They were saved automatically:\n\n" + list
                + "\n\nRecovered drawings open in new tabs. The original files stay as they were until you save."
            alert.addButton(withTitle: "Recover")
            alert.addButton(withTitle: "Decide Later")
            alert.addButton(withTitle: "Discard\u{2026}")
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                var recovered = 0
                for entry in entries.reversed() where restoreAutosave(entry) { recovered += 1 }
                if recovered > 0 {
                    statusBar.showMessage(recovered == 1
                        ? "Recovered \u{201C}\(entries[0].manifest.title)\u{201D} \u{2013} save it with \u{2318}S"
                        : "Recovered \(recovered) drawings \u{2013} save them with \u{2318}S")
                }
                return recovered > 0
            case .alertThirdButtonReturn:
                let confirm = NSAlert()
                confirm.alertStyle = .critical
                confirm.messageText = "Discard the auto-saved work?"
                confirm.informativeText = "The unsaved changes in "
                    + entries.map { "\u{201C}\($0.manifest.title)\u{201D}" }.joined(separator: ", ")
                    + " will be lost. This cannot be undone."
                confirm.addButton(withTitle: "Discard")
                confirm.addButton(withTitle: "Cancel")
                if confirm.runModal() == .alertFirstButtonReturn {
                    for entry in entries { AutoSaveStore.remove(entry.manifest.id) }
                    Log.info("Auto-saved work discarded")
                    return false
                }
                // Cancel → back to the first question
            default:
                Log.info("Recovery postponed (Decide Later)")
                return false
            }
        }
    }

    /// A single auto-save → a new tab (the auto-save stays until the drawing is saved or closed).
    private func restoreAutosave(_ entry: AutoSaveEntry) -> Bool {
        let manifest = entry.manifest
        guard let tab = openCopyInTab(from: entry.dataURL) else {
            Log.error("Recovery of \u{201C}\(manifest.title)\u{201D} failed")
            return false
        }
        // the tab takes over the auto-save – further auto-saving overwrites it
        tab.autosaveID = manifest.id
        tab.hasAutosave = true
        if let path = manifest.originalPath {
            let original = URL(fileURLWithPath: path)
            tab.suggestedSaveURL = NativeFormat.isNative(original)
                ? original
                : original.deletingPathExtension().appendingPathExtension(NativeDrawingFile.fileExtension)
        }
        tab.suggestedName = manifest.title
        tab.customTitle = manifest.title + " (recovered)"
        hasUnsavedChanges = true
        refreshTabBar()
        updateWindowTitle()
        Log.info("Recovered \u{201C}\(manifest.title)\u{201D} (auto-saved \(RecoveryText.describe(manifest.savedAt)))")
        return true
    }

    /// Opens a file as a copy in a new tab (not tied to the file). nil = it failed.
    private func openCopyInTab(from url: URL) -> DrawingTab? {
        guard ensureNoBlockEdit() else { return nil }
        let reuse = activeTab.isPristine
        if !reuse {
            editorView.cancelCurrentOperation()
            storeActiveTabState()
            tabs.insert(DrawingTab(untitledNumber: 0), at: activeIndex + 1)
            activeIndex += 1
            restoreActiveTabState()
        }
        let tab = activeTab
        guard loadNativeDocument(from: url, quietly: true) else {
            if !reuse, let position = tabs.firstIndex(where: { $0 === tab }), tabs.count > 1 {
                tabs.remove(at: position)
                activeIndex = max(0, min(position - 1, tabs.count - 1))
                restoreActiveTabState()
            }
            return nil
        }
        // copy: ⌘S asks where to save – the backup file is never overwritten
        currentFileURL = nil
        return tab
    }

    // MARK: Backups of previous versions

    /// File › Open Backup… – the backup opens as a copy.
    @objc func openBackup(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [NativeDrawingFile.contentType]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var directory = BackupStore.root
        if let url = currentFileURL {
            let own = BackupStore.folder(for: url)
            if FileManager.default.fileExists(atPath: own.path) { directory = own }
        }
        panel.directoryURL = directory
        panel.message = "Backups of earlier versions (one folder per drawing) – the backup opens as a copy and stays unchanged"
        panel.prompt = "Open Copy"
        guard let window = view.window else { return }
        let sourceURL = currentFileURL
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let url = panel.url else { return }
            self.openBackupCopy(url, currentDrawing: sourceURL)
        }
    }

    private func openBackupCopy(_ url: URL, currentDrawing: URL?) {
        Log.info("Open backup: \(url.lastPathComponent)")
        guard let tab = openCopyInTab(from: url) else { return }
        // backup name = “<drawing> 2026-10-18 182011”
        let base = url.deletingPathExtension().lastPathComponent
        var parts = base.components(separatedBy: " ")
        var stamp = ""
        if parts.count >= 3, parts[parts.count - 2].count == 10, parts[parts.count - 1].count == 6 {
            let time = parts[parts.count - 1]
            stamp = "\(parts[parts.count - 2]) \(time.prefix(2)):\(time.dropFirst(2).prefix(2))"
            parts.removeLast(2)
        }
        let name = parts.joined(separator: " ")
        tab.customTitle = name + (stamp.isEmpty ? " (backup)" : " (backup \(stamp))")
        tab.suggestedName = name
        // a backup of an open drawing → Save offers its location
        if let drawing = currentDrawing,
           BackupStore.folder(for: drawing).standardizedFileURL.path == url.deletingLastPathComponent().standardizedFileURL.path {
            tab.suggestedSaveURL = drawing
        }
        refreshTabBar()
        updateWindowTitle()
        statusBar.showMessage("Opened a copy of the backup \u{2013} the backup itself stays unchanged; \u{2318}S saves it as a drawing")
    }
}

// MARK: - Saved views (View › Save View…, View › Named Views)

extension MainViewController {
    /// Description of the view's space for the menu.
    private func spaceTitle(of view: NamedViewRecord) -> String {
        return view.layout.map { "Layout \u{201C}\($0)\u{201D}" } ?? "Model"
    }

    private func populateNamedViewsMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let views = activeTab.namedViews
        if views.isEmpty {
            let empty = NSMenuItem(title: "No Saved Views", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            empty.toolTip = "View › Save View… (⌥⌘V) remembers the current view under a name"
            menu.addItem(empty)
            return
        }
        for (index, view) in views.enumerated() {
            let item = NSMenuItem(title: view.name, action: #selector(restoreNamedViewFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.subtitle = spaceTitle(of: view)
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (title, action) in [("Rename View", #selector(renameNamedViewFromMenu(_:))),
                                ("Delete View", #selector(deleteNamedViewFromMenu(_:)))] {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let sub = NSMenu(title: title)
            for (index, view) in views.enumerated() {
                let item = NSMenuItem(title: view.name + (title == "Delete View" ? "" : "…"), action: action, keyEquivalent: "")
                item.target = self
                item.tag = index
                sub.addItem(item)
            }
            parent.submenu = sub
            menu.addItem(parent)
        }
    }

    /// Window with the view name. nil = Cancel or an empty name.
    private func askViewName(title: String, message: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// View › Save View… (⌥⌘V): remembers the center, zoom and rotation of the open space.
    @objc func saveNamedView(_ sender: Any?) {
        let tab = activeTab
        var number = tab.namedViews.count + 1
        while tab.namedViews.contains(where: { $0.name.lowercased() == "view \(number)" }) { number += 1 }
        guard let name = askViewName(title: "Save View",
                                     message: "Name of the view – it remembers what is on the screen now (position, zoom"
                                        + (tab.activeLayout == nil ? ", rotation" : "") + ") in " + (tab.activeLayout.map { "the layout \u{201C}\($0.name)\u{201D}" } ?? "the model") + ".",
                                     initial: "View \(number)") else { return }
        let state = editorView.viewport.viewState
        let view = NamedViewRecord(name: name,
                                   layout: tab.activeLayout?.name,
                                   zoom: state.zoom,
                                   pan: state.pan,
                                   rotation: tab.activeLayout == nil && editorView.viewport.rotation != 0 ? editorView.viewport.rotation : nil)
        if let index = tab.namedViews.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            tab.namedViews[index] = view
            statusBar.showMessage("View \u{201C}\(name)\u{201D} updated")
        } else {
            tab.namedViews.append(view)
            statusBar.showMessage("View \u{201C}\(name)\u{201D} saved \u{2013} View \u{203A} Named Views brings it back")
        }
        hasUnsavedChanges = true
        Log.info("Named view saved: \(name)")
    }

    @objc func restoreNamedViewFromMenu(_ sender: NSMenuItem) {
        let views = activeTab.namedViews
        guard views.indices.contains(sender.tag) else { return }
        restoreNamedView(views[sender.tag])
    }

    private func restoreNamedView(_ view: NamedViewRecord) {
        let tab = activeTab
        var target: Int?
        if let layoutName = view.layout {
            guard let index = tab.layouts.firstIndex(where: { $0.name == layoutName }) else {
                statusBar.showMessage("The layout \u{201C}\(layoutName)\u{201D} of the view \u{201C}\(view.name)\u{201D} no longer exists")
                NSSound.beep()
                return
            }
            target = index
        }
        if target != tab.activeLayoutIndex { activateSpace(target) }
        // switching may be refused (e.g. during a block edit) – the view would then land in the wrong space
        guard tab.activeLayoutIndex == target else { return }
        guard view.zoom.isFinite, view.zoom > 0, view.pan.x.isFinite, view.pan.y.isFinite else { return }
        editorView.viewport.viewState = (zoom: view.zoom, pan: view.pan)
        if target == nil {
            editorView.viewport.restoreRotation(view.rotation ?? 0)
            tab.viewRotation = editorView.viewport.rotation
        }
        editorView.needsDisplay = true
        updateStatusBar()
        statusBar.showMessage("View \u{201C}\(view.name)\u{201D} \u{2013} " + spaceTitle(of: view))
    }

    @objc func renameNamedViewFromMenu(_ sender: NSMenuItem) {
        let tab = activeTab
        guard tab.namedViews.indices.contains(sender.tag) else { return }
        let old = tab.namedViews[sender.tag].name
        guard let name = askViewName(title: "Rename View", message: "New name of the view \u{201C}\(old)\u{201D}:", initial: old),
              name != old else { return }
        if tab.namedViews.enumerated().contains(where: { $0.offset != sender.tag && $0.element.name.lowercased() == name.lowercased() }) {
            statusBar.showMessage("A view named \u{201C}\(name)\u{201D} already exists")
            NSSound.beep()
            return
        }
        tab.namedViews[sender.tag].name = name
        hasUnsavedChanges = true
    }

    @objc func deleteNamedViewFromMenu(_ sender: NSMenuItem) {
        let tab = activeTab
        guard tab.namedViews.indices.contains(sender.tag) else { return }
        let name = tab.namedViews[sender.tag].name
        tab.namedViews.remove(at: sender.tag)
        hasUnsavedChanges = true
        statusBar.showMessage("View \u{201C}\(name)\u{201D} deleted")
    }
}

// MARK: - Block editing (BlockEdit.swift)

extension MainViewController {
    /// Insert › Edit Block…: edits the selected block in place.
    @objc func editBlockFromMenu(_ sender: Any?) {
        let selected = selectionManager.getSelectedEntities(from: document.getAllEntities())
        let references = selected.compactMap { $0 as? BlockReference }
        guard references.count == 1, let reference = references.first else {
            statusBar.showMessage("Select one block (or double-click it) to edit it in place \u{2013} Block Manager \u{203A} Edit\u{2026} edits any block on its own")
            NSSound.beep()
            return
        }
        beginBlockEdit(definition: reference.definition, reference: reference)
    }

    @objc func saveBlockEdit(_ sender: Any?) {
        finishBlockEdit(save: true)
    }

    @objc func discardBlockEdit(_ sender: Any?) {
        guard let session = activeTab.blockEdit else { return }
        if session.changed {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Discard the changes to the block \u{201C}\(session.definition.name)\u{201D}?"
            alert.informativeText = "The block stays as it was before you started editing it."
            alert.addButton(withTitle: "Discard Block Changes")
            alert.addButton(withTitle: "Keep Editing")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        finishBlockEdit(save: false)
    }

    /// Start editing a block. `reference` = in place of this insertion (nil = standalone).
    func beginBlockEdit(definition: BlockDefinition, reference requested: BlockReference?) {
        let tab = activeTab
        // a copy stretched differently in X and Y (from DXF) cannot be edited in place: circles, arcs and texts
        // would not stay what they are – the block is edited on its own then, in its own coordinates
        let stretched = requested?.isStretched ?? false
        let reference = stretched ? nil : requested
        if let session = tab.blockEdit {
            statusBar.showMessage("The block \u{201C}\(session.definition.name)\u{201D} is being edited \u{2013} save or discard it first "
                                  + "(blocks inside it can be edited afterwards)")
            NSSound.beep()
            return
        }
        if let source = definition.source {
            statusBar.showMessage("\u{201C}\(definition.name)\u{201D} is an external reference \u{2013} open its own file (\(source.fileName)) to change it")
            NSSound.beep()
            return
        }
        guard tab.blocks.definitions.contains(where: { $0 === definition }) else {
            statusBar.showMessage("This block is not in the drawing's block list any more")
            return
        }
        // a standalone edit is done in the model (not through the layout paper)
        if reference == nil, tab.activeLayoutIndex != nil { activateSpace(nil) }
        editorView.cancelCurrentOperation()
        storeActiveTabState()
        selectionManager.clearSelection()
        if currentTool != .select { selectTool(.select) }

        // surroundings: the other objects of the open space (only for display and snapping)
        let background = reference.map { picked in
            DrawOrder.sorted(document.getAllEntities().filter { $0 !== picked })
        } ?? []
        let session = BlockEditSession(definition: definition, reference: reference, wasEdited: tab.isEdited)
        tab.blockEdit = session
        connectManagers()
        setupCallbacks()
        editorView.blockEditContext = CADEditorView.BlockEditContext(name: definition.name, background: background,
                                                                     basePoint: session.basePointInDrawing)
        if reference == nil {
            // standalone: the whole block including its base point on screen
            var items = session.document.getAllEntities()
            items.append(Line(start: definition.basePoint, end: definition.basePoint))
            editorView.viewport.zoomToFit(entities: items)
        }
        showBlockEditBar(for: session)
        refreshPanels()
        updateStatusBar()
        updateModes()
        statusBar.setPrompt(editorView.prompt)
        editorView.needsDisplay = true
        view.window?.makeFirstResponder(editorView)
        let copies = blockUseCount(definition)
        statusBar.showMessage((stretched ? "This copy is stretched, so the block is edited on its own \u{00B7} " : "")
                              + "Editing the block \u{201C}\(definition.name)\u{201D} \u{2013} all tools work \u{00B7} Save Block Changes "
                              + "updates \(copies == 1 ? "its copy" : "all \(copies) copies") \u{00B7} Discard Block Changes leaves it as it was")
        Log.info("Edit block: \(definition.name) (\(reference == nil ? "on its own" : "in place"), \(definition.entities.count) objects)")
    }

    /// End the block edit. save = write into the definition. Returns false if the edit could not be ended.
    @discardableResult
    func finishBlockEdit(save: Bool) -> Bool {
        let tab = activeTab
        guard let session = tab.blockEdit else { return true }
        editorView.cancelCurrentOperation()
        let name = session.definition.name
        var store = save && session.changed
        var entities: [CADEntity] = []
        if store {
            entities = session.editedEntities()
            if entities.isEmpty {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "The block \u{201C}\(name)\u{201D} would be empty"
                alert.informativeText = "A block needs at least one object. To remove the block, discard the changes, "
                    + "delete its copies and use Block Manager \u{203A} Purge Unused."
                alert.addButton(withTitle: "Keep Editing")
                alert.addButton(withTitle: "Discard Block Changes")
                guard alert.runModal() == .alertSecondButtonReturn else { return false }
                store = false
            } else if entities.contains(where: { ($0 as? BlockReference)?.definition.contains(session.definition) ?? false }) {
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "A block cannot contain itself"
                alert.informativeText = "The block \u{201C}\(name)\u{201D} now contains a copy of itself (perhaps inside another block). "
                    + "Delete that copy, then save the block."
                alert.addButton(withTitle: "Keep Editing")
                alert.runModal()
                return false
            }
        }

        tab.blockEdit = nil
        editorView.blockEditContext = nil
        selectionManager.clearSelection()
        hideBlockEditBar()
        restoreActiveTabState()

        if store {
            // Set Base Point with “Keep Copies in Place”: the insertion points of all copies move along
            let lists = activeTab.allDocuments.map { (entities: $0.getAllEntities(), owner: BlockDefinition?.none) }
                + activeTab.blocks.definitions.filter { $0 !== session.definition }.map { (entities: $0.entities, owner: Optional($0)) }
            applyBlockChange(BlockContentChange(definition: session.definition, entities: entities, basePoint: session.basePoint,
                                                placements: session.copyPositions(in: lists)))
            undoer.setActionName("Edit Block \u{201C}\(name)\u{201D}")
            let copies = blockUseCount(session.definition)
            statusBar.showMessage("Block \u{201C}\(name)\u{201D} saved \u{2013} \(copies == 1 ? "1 copy" : "\(copies) copies") updated (\u{2318}Z undoes it)")
            Log.info("Block saved: \(name) (\(entities.count) objects)")
        } else if save {
            statusBar.showMessage("Block \u{201C}\(name)\u{201D} unchanged")
        } else {
            // nothing was written into the drawing – the “unsaved” state as before the edit
            if session.changed && !session.wasEdited { hasUnsavedChanges = false }
            statusBar.showMessage("Changes to the block \u{201C}\(name)\u{201D} discarded")
            Log.info("Block edit discarded: \(name)")
        }
        refreshPanels()
        editorView.needsDisplay = true
        return true
    }

    /// Before an action that doesn't go together with a block edit (another tab, save, plot…): ask.
    /// true = no edit is running (or it has just ended).
    /// `reason` (a change of the whole drawing, e.g. its scale or units): asks even when the block has no changes,
    /// so the edit does not end without a word; without it an unchanged block edit ends quietly.
    private func ensureNoBlockEdit(reason: String? = nil) -> Bool {
        guard let session = activeTab.blockEdit else { return true }
        guard session.changed else {
            guard let reason = reason else { return finishBlockEdit(save: false) }
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Close the block \u{201C}\(session.definition.name)\u{201D}?"
            alert.informativeText = reason + " The block is still being edited (without changes) – it closes first."
            alert.addButton(withTitle: "Close Block")
            alert.addButton(withTitle: "Cancel")
            return alert.runModal() == .alertFirstButtonReturn ? finishBlockEdit(save: false) : false
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Save the changes to the block \u{201C}\(session.definition.name)\u{201D}?"
        alert.informativeText = "The block is still being edited. Save Block Changes writes them to every copy of it."
        alert.addButton(withTitle: "Save Block Changes")
        alert.addButton(withTitle: "Discard Block Changes")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return finishBlockEdit(save: true)
        case .alertSecondButtonReturn: return finishBlockEdit(save: false)
        default: return false
        }
    }

    /// New content of a block definition – as a step of the main Undo (Undo restores the previous content).
    @objc private func applyBlockChange(_ change: BlockContentChange) {
        let previous = BlockContentChange(definition: change.definition, entities: change.definition.entities,
                                          basePoint: change.definition.basePoint,
                                          placements: change.placements.map { .init(reference: $0.reference, position: $0.reference.position,
                                                                                    owner: $0.owner) })
        change.definition.entities = change.entities
        if change.definition.basePoint != change.basePoint { change.definition.basePoint = change.basePoint }
        for placement in change.placements {
            placement.reference.position = placement.position
            // copies inside another block: its copies recompute their content
            placement.owner?.contentDidChange()
        }
        undoer.registerUndo(withTarget: self, selector: #selector(applyBlockChange(_:)), object: previous)
        hasUnsavedChanges = true
        if change.placements.isEmpty {
            editorView.needsDisplay = true
        } else {
            editorView.invalidateRenderCache()
        }
        refreshProperties()
    }

    // MARK: Block base point

    /// Set Base Point (block edit bar): click the new base point, then (when the block has copies) choose
    /// whether the copies stay where they are or keep their insertion points.
    private func setBlockBasePoint() {
        guard let session = activeTab.blockEdit else { return }
        if currentTool != .select { selectTool(.select) }
        editorView.pickAxis(byObject: false, prompt: "Set Base Point: click the new base point of the block",
                            singlePoint: true) { [weak self] result in
            guard let self = self, let point = result?.origin else { return }
            DispatchQueue.main.async { self.finishBlockBasePoint(session: session, at: point) }
        }
        statusBar.setPrompt(editorView.prompt)
    }

    private func finishBlockBasePoint(session: BlockEditSession, at point: CGPoint) {
        guard activeTab.blockEdit === session else { return }
        guard Geometry.distance(point, session.basePointInDrawing) > 1e-9 else {
            statusBar.showMessage("That is the base point already")
            return
        }
        var moveCopies = false
        let copies = blockUseCount(session.definition)
        if copies > 0 {
            let alert = NSAlert()
            alert.messageText = "Set Base Point \u{2013} Copies in the Drawing"
            alert.informativeText = "Keep Copies in Place: the drawing does not move, only the point the block is held and "
                + "inserted by changes.\n\nMove Copies: \(copies == 1 ? "the copy keeps its" : "all \(copies) copies keep their") "
                + "insertion point, so the drawing of the block shifts by the distance between the old and the new base point."
                + "\n\nEither way it is written into the block with Save Block Changes."
            alert.addButton(withTitle: "Keep Copies in Place")
            alert.addButton(withTitle: "Move Copies")
            alert.addButton(withTitle: "Cancel")
            switch alert.runModal() {
            case .alertFirstButtonReturn: moveCopies = false
            case .alertSecondButtonReturn: moveCopies = true
            default: return
            }
        }
        applyBlockBasePoint(session.basePointChange(to: point, moveCopies: moveCopies))
        statusBar.showMessage(moveCopies
            ? "Base point moved \u{2013} the copies will shift when you save the block (\u{2318}Z undoes it)"
            : "Base point moved \u{2013} the copies stay where they are (\u{2318}Z undoes it)")
        Log.info("Block base point: \(session.definition.name) (\(moveCopies ? "copies move" : "copies stay"))")
    }

    /// One Set Base Point step of the block edit – undoable within the edit.
    private func applyBlockBasePoint(_ change: BlockEditSession.BasePointChange) {
        guard let session = activeTab.blockEdit else { return }
        session.apply(change)
        undoer.registerUndo(withTarget: self) { target in target.applyBlockBasePoint(change.reversed) }
        undoer.setActionName("Set Base Point")
        editorView.blockEditContext?.basePoint = session.basePointInDrawing
        editorView.invalidateRenderCache()
        hasUnsavedChanges = true
        refreshProperties()
    }

    // MARK: Block edit bar

    private func showBlockEditBar(for session: BlockEditSession) {
        let bar = blockEditBar ?? BlockEditBar(frame: NSRect(x: 0, y: 0, width: 480, height: BlockEditBar.height))
        if blockEditBar == nil {
            bar.onSave = { [weak self] in self?.finishBlockEdit(save: true) }
            bar.onDiscard = { [weak self] in self?.discardBlockEdit(nil) }
            bar.onSetBasePoint = { [weak self] in self?.setBlockBasePoint() }
            blockEditBar = bar
        }
        bar.configure(blockName: session.definition.name, copies: blockUseCount(session.definition),
                      inPlace: session.reference != nil)
        if bar.superview == nil { view.addSubview(bar, positioned: .above, relativeTo: editorView) }
        bar.isHidden = false
        updateEditorViewFrame()
    }

    private func hideBlockEditBar() {
        blockEditBar?.isHidden = true
        updateEditorViewFrame()
    }

    /// The strip above the drawing area that holds the block edit bar (0 when no block is being edited).
    private var blockEditStripHeight: CGFloat {
        guard let bar = blockEditBar, !bar.isHidden else { return 0 }
        return BlockEditBar.height + 8
    }

    private func positionBlockEditBar() {
        guard let bar = blockEditBar, !bar.isHidden, let editor = editorView else { return }
        let frame = editor.frame
        let width = bar.preferredWidth(maximum: max(200, frame.width - 24))
        // above the tool options bar, if that one is shown
        bar.frame = NSRect(x: frame.midX - width / 2, y: frame.maxY + toolOptionsStripHeight + (blockEditStripHeight - BlockEditBar.height) / 2,
                           width: width, height: BlockEditBar.height)
        bar.needsLayout = true
    }

    // MARK: Tool options bar

    /// Shows the options bar while Select Similar or Match Properties runs (with the current ticks and state),
    /// hides it for other tools.
    private func updateToolOptionsBar() {
        guard currentTool == .selectSimilar || currentTool == .matchProperties else {
            if let bar = toolOptionsBar, !bar.isHidden {
                bar.isHidden = true
                updateEditorViewFrame()
            }
            return
        }
        let bar = toolOptionsBar ?? ToolOptionsBar(frame: NSRect(x: 0, y: 0, width: 480, height: ToolOptionsBar.height))
        if toolOptionsBar == nil {
            bar.onToggle = { [weak self] index, isOn in self?.toolOptionToggled(index, isOn: isOn) }
            bar.onDone = { [weak self] in
                guard let self = self else { return }
                self.selectTool(.select)
                self.view.window?.makeFirstResponder(self.editorView)
            }
            toolOptionsBar = bar
        }
        if currentTool == .selectSimilar {
            let chosen = AppSettings.similarProperties
            let text: String
            if let count = editorView.similarSelectedCount {
                text = "Select Similar \u{00B7} \(count) object\(count == 1 ? "" : "s") selected \u{00B7} must match:"
            } else {
                text = "Select Similar \u{00B7} click a sample object \u{00B7} must match:"
            }
            bar.configure(text: text,
                          options: SimilarProperty.allCases.map { ToolOption(title: $0.title, detail: $0.detail, isOn: chosen.contains($0)) },
                          doneHelp: "End Select Similar – the selection stays (↩, right-click or Esc does the same)")
        } else {
            let chosen = AppSettings.matchProperties
            let text = editorView.matchSource == nil
                ? "Match Properties \u{00B7} click the source object \u{00B7} copy:"
                : "Match Properties \u{00B7} click or window the objects to change \u{00B7} copy:"
            bar.configure(text: text,
                          options: MatchProperty.allCases.map { ToolOption(title: $0.title, detail: $0.detail, isOn: chosen.contains($0)) },
                          doneHelp: "End Match Properties (↩, right-click or Esc does the same)")
        }
        if bar.superview == nil { view.addSubview(bar, positioned: .above, relativeTo: editorView) }
        if bar.isHidden {
            bar.isHidden = false
            updateEditorViewFrame()
        } else {
            positionToolOptionsBar()
        }
    }

    /// A box in the options bar was ticked or unticked – the same settings as Edit › Select Similar Matches
    /// and the menu of the Match Properties button.
    private func toolOptionToggled(_ index: Int, isOn: Bool) {
        if currentTool == .selectSimilar {
            let all = SimilarProperty.allCases
            guard all.indices.contains(index) else { return }
            var properties = AppSettings.similarProperties
            if isOn { properties.insert(all[index]) } else { properties.remove(all[index]) }
            if properties.isEmpty {
                statusBar.showMessage("At least one property has to match – Object Type stays on")
                properties = [.type]
            }
            AppSettings.similarProperties = properties
            editorView.applySelectSimilar()
        } else if currentTool == .matchProperties {
            let all = MatchProperty.allCases
            guard all.indices.contains(index) else { return }
            var properties = AppSettings.matchProperties
            if isOn { properties.insert(all[index]) } else { properties.remove(all[index]) }
            AppSettings.matchProperties = properties
            statusBar.setPrompt(editorView.prompt)
        }
        updateToolOptionsBar()
        view.window?.makeFirstResponder(editorView)
    }

    /// The strip above the drawing area that holds the tool options bar (0 when it is hidden).
    private var toolOptionsStripHeight: CGFloat {
        guard let bar = toolOptionsBar, !bar.isHidden else { return 0 }
        return ToolOptionsBar.height + 8
    }

    private func positionToolOptionsBar() {
        guard let bar = toolOptionsBar, !bar.isHidden, let editor = editorView else { return }
        let frame = editor.frame
        let width = bar.preferredWidth(maximum: max(200, frame.width - 24))
        bar.frame = NSRect(x: frame.midX - width / 2, y: frame.maxY + (toolOptionsStripHeight - ToolOptionsBar.height) / 2,
                           width: width, height: ToolOptionsBar.height)
        bar.needsLayout = true
    }
}

/// One object converted to other drawing units (Document Settings › Units with “convert the drawing”).
enum EditorUnitConversion {
    static func converted(_ entity: CADEntity, transform: CGAffineTransform, factor: CGFloat,
                          convertedBlocks: [BlockDefinition]) -> CADEntity {
        let copy = entity.clone()
        // applyTransform already scales dimension text and arrows
        copy.applyTransform(transform)
        if let dimension = copy as? DimensionEntity {
            // dimensions keep their real precision (mm with 0 decimals → m with 3)
            let extraDecimals = Int((-log10(factor)).rounded())
            dimension.precision = max(0, min(dimension.precision + extraDecimals, 6))
        }
        // a converted block already has the new size – its reference keeps its scale
        if let reference = copy as? BlockReference, let original = entity as? BlockReference,
           convertedBlocks.contains(where: { $0 === reference.definition }) {
            reference.scale = original.scale
        }
        return copy
    }
}
