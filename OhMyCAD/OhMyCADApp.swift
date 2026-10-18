//
//  OhMyCADApp.swift
//  OhMyCAD
//
//  Created by Yankee Djinn on 23.11.2025.
//
//  App entry point (pure AppKit, no SwiftUI and no storyboard).
//

import Cocoa

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private var window: NSWindow!
    private var mainViewController: MainViewController!

    /// Without MainMenu.xib the delegate would not be created on its own – hence a custom main().
    static func main() {
        // log and crash capture – as early as possible, so errors during startup are caught too
        CrashGuard.start()
        // custom NSApplication: logs exceptions that AppKit would otherwise silently swallow
        let app = OhMyCADApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        // Dock icon right from launch (even when debugging from Xcode)
        app.applicationIconImage = LogoMark.appIconImage()
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // fonts bundled with the app (osifont – a technical font per ISO 3098)
        FontLibrary.registerBundledFonts()

        mainViewController = MainViewController()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = mainViewController
        window.setContentSize(NSSize(width: 1400, height: 900))
        window.minSize = NSSize(width: 1100, height: 650)
        window.isRestorable = false
        // the window is held by AppDelegate – AppKit must not release it on close (otherwise a crash on quit)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        mainViewController.setupMenus()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // crashed last time → offer to save the report (only once per crash)
        ProblemReporter.offerReportAfterCrash { [weak self] in
            return self?.mainViewController.diagnosticSummary() ?? ""
        }
        // auto-saved unsaved work was left behind → offer to restore it
        let recovered = mainViewController.offerRecovery()

        // launched by double-clicking a drawing in Finder → open it directly, without the start screen
        if pendingURLs.isEmpty {
            if AppSettings.showWelcomeScreen && !recovered { showWelcomeDialog() }
        } else {
            for url in pendingURLs { mainViewController.openRecentFile(url) }
            pendingURLs.removeAll()
        }
    }

    // MARK: Opening from Finder / Dock

    /// Files that arrived before the window was created (cold start by double-click).
    private var pendingURLs: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        guard mainViewController != nil else {
            pendingURLs.append(contentsOf: urls)
            return
        }
        for url in urls { mainViewController.openRecentFile(url) }
    }

    private let splash = SplashController()

    /// Branded start screen – New Drawing (Enter / Esc) or Open File.
    private func showWelcomeDialog() {
        splash.onOpenFile = { [weak self] in self?.mainViewController.openDocument(nil) }
        splash.onOpenRecent = { [weak self] url in self?.mainViewController.openRecentFile(url) }
        splash.recentURLs = mainViewController.recentFileURLs
        splash.show(over: window)
    }

    // MARK: Unsaved changes

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        return mainViewController.confirmDiscardChanges()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Closing the window was already confirmed – the window is no longer visible then
        guard window.isVisible else { return .terminateNow }
        return mainViewController.confirmDiscardChanges() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        // every drawing has been decided (save / discard) → this session's auto-backups are removed
        mainViewController?.discardSessionAutosaves()
        CrashGuard.finish()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
