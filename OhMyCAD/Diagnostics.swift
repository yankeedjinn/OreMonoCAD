//
//  Diagnostics.swift
//  OhMyCAD
//
//  App log, crash capture and problem reports (Help › Report a Problem…).
//
//  Everything stays on the computer, in the app's folder:
//  ~/Library/Containers/<app>/Data/Library/Application Support/OhMyCAD/Diagnostics
//  Nothing is sent automatically – the report is a ZIP the user saves and sends themselves.
//
//  Layers:
//  1. Log            – a log of what happened (open, save, tools, changes, messages, errors).
//  2. CrashGuard     – on a crash it writes the signal / exception and the call stack; on the next launch
//                      it detects it. Console output (e.g. “Fatal error: Index out of range”) is saved
//                      to a file outside Xcode, so the crash reason shows up in the report.
//     MetricKit      – macOS delivers its own crash or hang report (sometimes with a delay).
//  3. ProblemReporter – a dialog after a crash and the manual Help › Report a Problem… → a report ZIP.
//

import Cocoa
import MetricKit
import UniformTypeIdentifiers

// MARK: - Folders

nonisolated enum DiagnosticsPaths {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("OhMyCAD", isDirectory: true)
            .appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// The log (and its previous part once the size limit is exceeded).
    static var log: URL { return root.appendingPathComponent("ohmycad.log") }
    static var previousLog: URL { return root.appendingPathComponent("ohmycad.1.log") }
    /// Console output (stderr) of this and the previous launch – only outside Xcode.
    static var console: URL { return root.appendingPathComponent("console.log") }
    static var previousConsole: URL { return root.appendingPathComponent("console.previous.log") }
    /// Exists while the app is running – remains after a crash or a forced quit.
    static var sessionMarker: URL { return root.appendingPathComponent("session.running") }
    /// The crash handler writes here; after a clean quit it is empty and gets deleted.
    static var pendingCrash: URL { return root.appendingPathComponent("crash.pending") }
    /// Crash reports: new (not yet offered) and older.
    static var crashes: URL { return folder("Crashes") }
    static var newCrashes: URL { return folder("Crashes/New") }
    /// Reports from macOS (MetricKit).
    static var systemReports: URL { return folder("macOS Reports") }

    private static func folder(_ path: String) -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Files in a folder, newest first.
    static func files(in folder: URL, extensions: Set<String>) -> [URL] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                 options: [.skipsHiddenFiles])) ?? []
        func date(_ url: URL) -> Date {
            return (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        }
        return urls
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
            .sorted { date($0) > date($1) }
    }

    /// The end of a text file (the last `bytes` bytes), starting at a line start.
    static func tail(of url: URL, bytes: Int) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? handle.seek(toOffset: start)
        let data = (try? handle.readToEnd()) ?? Data()
        var text = String(decoding: data, as: UTF8.self)
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return text
    }
}

// MARK: - Log

/// The app log: one line per event, with a timestamp. Safe to call from any thread.
nonisolated enum Log {
    enum Level: String {
        case info = "I"
        case warning = "W"
        case error = "E"
    }

    /// Once exceeded, the log is moved to ohmycad.1.log and starts over (so at most 2 × this much is kept).
    private static let maxBytes: UInt64 = 2_000_000
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handle: FileHandle?
    nonisolated(unsafe) private static var bytesWritten: UInt64 = 0
    nonisolated(unsafe) private static var lastLine = ""
    nonisolated(unsafe) private static var repeatCount = 0
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func info(_ message: String) { write(.info, message) }
    static func warning(_ message: String) { write(.warning, message) }
    static func error(_ message: String) { write(.error, message) }

    static func write(_ level: Level, _ message: String) {
        // one line per entry – replace line breaks
        let text = message
            .replacingOccurrences(of: "\r\n", with: " | ")
            .replacingOccurrences(of: "\n", with: " | ")
            .replacingOccurrences(of: "\r", with: " | ")
        lock.lock()
        defer { lock.unlock() }
        // the same message over and over → only write the repeat count
        let key = level.rawValue + text
        if key == lastLine {
            repeatCount += 1
            return
        }
        var output = ""
        let stamp = formatter.string(from: Date())
        if repeatCount > 0 {
            output += "\(stamp) [I] (previous line repeated \(repeatCount)×)\n"
            repeatCount = 0
        }
        lastLine = key
        output += "\(stamp) [\(level.rawValue)] \(text)\n"
        append(output)
    }

    /// Flush the log to disk (before building a report).
    static func synchronize() {
        lock.lock()
        defer { lock.unlock() }
        if repeatCount > 0 {
            append("\(formatter.string(from: Date())) [I] (previous line repeated \(repeatCount)×)\n")
            repeatCount = 0
            lastLine = ""
        }
        try? handle?.synchronize()
    }

    // called only while holding the lock
    private static func append(_ text: String) {
        if handle == nil { openFile() }
        guard let file = handle else { return }
        let data = Data(text.utf8)
        do {
            try file.write(contentsOf: data)
        } catch {
            return
        }
        bytesWritten += UInt64(data.count)
        if bytesWritten > maxBytes { rotate() }
    }

    private static func openFile() {
        let url = DiagnosticsPaths.log
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let file = try? FileHandle(forWritingTo: url) else { return }
        handle = file
        bytesWritten = (try? file.seekToEnd()) ?? 0
        if bytesWritten > maxBytes { rotate() }
    }

    private static func rotate() {
        try? handle?.close()
        handle = nil
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: DiagnosticsPaths.previousLog)
        try? fileManager.moveItem(at: DiagnosticsPaths.log, to: DiagnosticsPaths.previousLog)
        fileManager.createFile(atPath: DiagnosticsPaths.log.path, contents: nil)
        handle = try? FileHandle(forWritingTo: DiagnosticsPaths.log)
        bytesWritten = 0
    }
}

// MARK: - Crash handler (runs inside the signal – only simple, pre-prepared things)

/// The file written to on a crash (opened in advance – nothing may be allocated in a signal handler).
nonisolated(unsafe) private var crashFileDescriptor: Int32 = -1
/// Pre-reserved space for the call stack addresses.
nonisolated(unsafe) private var crashFrames: UnsafeMutablePointer<UnsafeMutableRawPointer?>? = nil
private let crashFrameCapacity: Int32 = 128
/// Pre-built headers for the individual signals (index = signal number).
nonisolated(unsafe) private var crashSignalTexts: [[UInt8]] = []

nonisolated private func crashSignalHandler(_ sig: Int32) {
    let fd = crashFileDescriptor
    if fd >= 0 {
        let index = Int(sig)
        if index >= 0 && index < crashSignalTexts.count {
            crashSignalTexts[index].withUnsafeBufferPointer { buffer in
                _ = Darwin.write(fd, buffer.baseAddress, buffer.count)
            }
        }
        if let frames = crashFrames {
            let count = backtrace(frames, 128)
            backtrace_symbols_fd(frames, count, fd)
        }
    }
    // default behavior (macOS records the crash its own way) and exit
    Darwin.signal(sig, SIG_DFL)
    raise(sig)
}

nonisolated private func uncaughtExceptionHandler(_ exception: NSException) {
    let reason = exception.reason ?? "-"
    let text = "\n*** Uncaught exception: \(exception.name.rawValue) - \(reason)\nCall stack:\n"
        + exception.callStackSymbols.joined(separator: "\n") + "\n"
    let fd = crashFileDescriptor
    if fd >= 0 {
        let bytes = Array(text.utf8)
        bytes.withUnsafeBufferPointer { buffer in
            _ = Darwin.write(fd, buffer.baseAddress, buffer.count)
        }
    }
    Log.error("Uncaught exception: \(exception.name.rawValue) - \(reason)")
    Log.synchronize()
}

// MARK: - Crash watch

enum CrashGuard {
    /// How the previous launch ended.
    enum PreviousSession {
        case firstLaunch
        case clean
        /// It crashed – the crash report is in Crashes/New.
        case crashed
        /// It ended without a clean quit and without a report (force quit, Stop in Xcode, power outage…).
        case endedUnexpectedly
    }

    private(set) static var previousSession: PreviousSession = .firstLaunch
    static let launchDate = Date()
    private static var started = false
    private static let metricKitReceiver = MetricKitReceiver()

    /// Start as early as possible after app launch.
    static func start() {
        guard !started else { return }
        started = true
        let fileManager = FileManager.default
        let wasRunning = fileManager.fileExists(atPath: DiagnosticsPaths.sessionMarker.path)
        let crashed = collectPreviousCrash()
        if crashed {
            previousSession = .crashed
        } else if wasRunning {
            previousSession = .endedUnexpectedly
        } else {
            previousSession = fileManager.fileExists(atPath: DiagnosticsPaths.log.path) ? .clean : .firstLaunch
        }

        // console output: keep the previous launch's, write the new one to a file (only outside Xcode –
        // in Xcode it must stay in its console)
        try? fileManager.removeItem(at: DiagnosticsPaths.previousConsole)
        if fileManager.fileExists(atPath: DiagnosticsPaths.console.path) {
            try? fileManager.moveItem(at: DiagnosticsPaths.console, to: DiagnosticsPaths.previousConsole)
        }
        let debugger = isDebuggerAttached
        if !debugger {
            let fd = Darwin.open(DiagnosticsPaths.console.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            if fd >= 0 {
                dup2(fd, STDERR_FILENO)
                Darwin.close(fd)
            }
        }

        installCrashHandlers()
        fileManager.createFile(atPath: DiagnosticsPaths.sessionMarker.path,
                               contents: Data(ISO8601DateFormatter().string(from: launchDate).utf8))

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        Log.info("---- Launch OhMyCAD \(version) (\(build)) · \(ProcessInfo.processInfo.operatingSystemVersionString)"
                 + (debugger ? " · running under the debugger" : ""))
        switch previousSession {
        case .firstLaunch: break
        case .clean: break
        case .crashed:
            Log.warning("Previous session crashed: \(newCrashReports.first.map { crashSummary(of: $0) } ?? "?")")
        case .endedUnexpectedly:
            Log.warning("Previous session ended without quitting (force quit, Stop in Xcode or power loss) – no crash data")
        }

        // crash and hang reports from macOS
        MXMetricManager.shared.add(metricKitReceiver)
    }

    /// Clean quit (applicationWillTerminate).
    static func finish() {
        guard started else { return }
        Log.info("---- Quit")
        Log.synchronize()
        if crashFileDescriptor >= 0 {
            let fd = crashFileDescriptor
            crashFileDescriptor = -1
            Darwin.close(fd)
        }
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: DiagnosticsPaths.pendingCrash)
        try? fileManager.removeItem(at: DiagnosticsPaths.sessionMarker)
    }

    /// Crash reports the user has not seen yet (newest first).
    static var newCrashReports: [URL] {
        return DiagnosticsPaths.files(in: DiagnosticsPaths.newCrashes, extensions: ["log"])
    }

    /// Move new reports to the older ones – the post-crash dialog won't appear again.
    static func markCrashReportsSeen() {
        let fileManager = FileManager.default
        for url in newCrashReports {
            let target = DiagnosticsPaths.crashes.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: target)
            try? fileManager.moveItem(at: url, to: target)
        }
        // older reports – keep only the last 20
        for url in DiagnosticsPaths.files(in: DiagnosticsPaths.crashes, extensions: ["log"]).dropFirst(20) {
            try? fileManager.removeItem(at: url)
        }
        for url in DiagnosticsPaths.files(in: DiagnosticsPaths.systemReports, extensions: ["json"]).dropFirst(20) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// In one sentence what happened (“signal 11 (SIGSEGV …)”, “Fatal error: Index out of range”…).
    static func crashSummary(of url: URL) -> String {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        var parts: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("*** ") {
                parts.append(String(trimmed.dropFirst(4)))
            } else if trimmed.contains("Fatal error:") {
                // Swift: “…/EditorView.swift:1234: Fatal error: Index out of range”
                if let range = trimmed.range(of: "Fatal error:") {
                    let file = trimmed[..<range.lowerBound].components(separatedBy: "/").last ?? ""
                    let where_ = file.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
                    parts.append(String(trimmed[range.lowerBound...]) + (where_.isEmpty ? "" : " (\(where_))"))
                } else {
                    parts.append(trimmed)
                }
            }
        }
        var unique: [String] = []
        for part in parts where !unique.contains(part) { unique.append(part) }
        return unique.isEmpty ? "unknown cause" : unique.prefix(3).joined(separator: " · ")
    }

    // MARK: Internals

    /// The previous launch crashed → report into Crashes/New (with the tail of the console output). Returns whether it crashed.
    private static func collectPreviousCrash() -> Bool {
        let fileManager = FileManager.default
        let pending = DiagnosticsPaths.pendingCrash
        guard let attributes = try? fileManager.attributesOfItem(atPath: pending.path) else { return false }
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else {
            try? fileManager.removeItem(at: pending)
            return false
        }
        let date = attributes[.modificationDate] as? Date ?? Date()
        let crashText = (try? String(contentsOf: pending, encoding: .utf8))
            ?? String(decoding: (try? Data(contentsOf: pending)) ?? Data(), as: UTF8.self)
        let console = DiagnosticsPaths.tail(of: DiagnosticsPaths.console, bytes: 16_000)
        let logTail = DiagnosticsPaths.tail(of: DiagnosticsPaths.log, bytes: 8_000)

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let fileStamp = DateFormatter()
        fileStamp.locale = Locale(identifier: "en_US_POSIX")
        fileStamp.dateFormat = "yyyyMMdd-HHmmss"

        var report = "OhMyCAD crash report\nTime of crash: \(stamp.string(from: date))\n"
        report += crashText
        report += "\n\n--- Console output of that session (end) ---\n"
        report += console.isEmpty ? "(none – the app ran under Xcode, see its console)\n" : console
        report += "\n\n--- Log before the crash (end) ---\n" + logTail
        let target = DiagnosticsPaths.newCrashes.appendingPathComponent("crash-\(fileStamp.string(from: date)).log")
        try? report.write(to: target, atomically: true, encoding: .utf8)
        try? fileManager.removeItem(at: pending)
        return true
    }

    private static func installCrashHandlers() {
        // file for writing on a crash – opened in advance
        let fd = Darwin.open(DiagnosticsPaths.pendingCrash.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        guard fd >= 0 else {
            Log.error("Crash reporting is off: cannot create \(DiagnosticsPaths.pendingCrash.lastPathComponent)")
            return
        }
        crashFileDescriptor = fd
        crashFrames = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: Int(crashFrameCapacity))

        let names: [Int32: String] = [
            SIGABRT: "SIGABRT - the app stopped itself (a failed check or an exception)",
            SIGSEGV: "SIGSEGV - invalid memory access",
            SIGBUS: "SIGBUS - invalid memory access",
            SIGILL: "SIGILL - illegal instruction",
            SIGTRAP: "SIGTRAP - a Swift runtime check failed (e.g. index out of range or an unexpected nil)",
            SIGFPE: "SIGFPE - arithmetic error",
        ]
        crashSignalTexts = (0..<32).map { number in
            let name = names[Int32(number)] ?? "unknown signal"
            return Array("\n*** OhMyCAD crashed: signal \(number) (\(name))\nBacktrace:\n".utf8)
        }

        // a dedicated stack for the handler – works even on stack overflow (infinite recursion)
        let stackSize = 128 * 1024
        var alternate = stack_t()
        alternate.ss_sp = UnsafeMutableRawPointer.allocate(byteCount: stackSize, alignment: 16)
        alternate.ss_size = stackSize
        alternate.ss_flags = 0
        sigaltstack(&alternate, nil)

        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = crashSignalHandler
            action.sa_flags = SA_ONSTACK
            sigaction(sig, &action, nil)
        }
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }

    /// Is the app running under Xcode (a debugger)?
    static var isDebuggerAttached: Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        return result == 0 && (info.kp_proc.p_flag & P_TRACED) != 0
    }
}

/// Crash and hang reports from macOS (MetricKit) – saved and bundled with the report.
nonisolated final class MetricKitReceiver: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        for (index, payload) in payloads.enumerated() {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let name = "macos-\(formatter.string(from: payload.timeStampEnd))-\(index).json"
            let url = DiagnosticsPaths.systemReports.appendingPathComponent(name)
            try? payload.jsonRepresentation().write(to: url, options: .atomic)
            Log.warning("macOS diagnostic report received: \(crashes) crash(es), \(hangs) hang(s) – saved as \(name)")
        }
    }
}

// MARK: - Exceptions AppKit catches by itself

/// AppKit catches exceptions on the main thread and only prints them – the app keeps running but may be
/// in an inconsistent state. Here they are written to the log along with the call stack.
final class OhMyCADApplication: NSApplication {
    override func reportException(_ exception: NSException) {
        let stack = exception.callStackSymbols.prefix(25).joined(separator: " / ")
        Log.error("AppKit exception: \(exception.name.rawValue) - \(exception.reason ?? "-") · stack: \(stack)")
        super.reportException(exception)
    }
}

// MARK: - Problem report

enum ProblemReporter {
    /// Where the app keeps its log – Help › Show Log in Finder.
    static func showLogInFinder() {
        Log.synchronize()
        let url = DiagnosticsPaths.log
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([DiagnosticsPaths.root])
        }
    }

    /// After launch: crashed last time → offer a report (only once per crash).
    static func offerReportAfterCrash(summary: @escaping () -> String) {
        let reports = CrashGuard.newCrashReports
        guard let newest = reports.first else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "OhMyCAD quit unexpectedly last time"
        var cause = CrashGuard.crashSummary(of: newest)
        if reports.count > 1 { cause += "\n(and \(reports.count - 1) earlier crash\(reports.count == 2 ? "" : "es"))" }
        alert.informativeText = "What happened: \(cause)\n\n"
            + "A problem report helps to find and fix the cause. It contains the crash details and the app's log."
        alert.addButton(withTitle: "Save Report…")
        alert.addButton(withTitle: "Not Now")
        let form = ReportForm(drawingName: nil)
        alert.accessoryView = form.view
        alert.layout()
        alert.window.initialFirstResponder = form.textView
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            saveReport(description: form.description, summary: summary(), drawing: nil, afterCrash: true)
        } else {
            Log.info("Crash report not saved (Not Now)")
        }
        CrashGuard.markCrashReportsSeen()
    }

    /// Help › Report a Problem…
    static func reportProblem(summary: String, drawingName: String?, writeDrawing: @escaping (URL) throws -> Void) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Report a Problem"
        alert.informativeText = "Describe what went wrong and how to make it happen again. "
            + "The report is a ZIP file with this description, the app's log, recent crash details and basic "
            + "information about your Mac. Nothing is sent anywhere – you attach the file to a message yourself."
        alert.addButton(withTitle: "Save Report…")
        alert.addButton(withTitle: "Cancel")
        let form = ReportForm(drawingName: drawingName)
        alert.accessoryView = form.view
        alert.layout()
        alert.window.initialFirstResponder = form.textView
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let drawing: (name: String, write: (URL) throws -> Void)?
        if let name = drawingName, form.includeDrawing { drawing = (name, writeDrawing) } else { drawing = nil }
        saveReport(description: form.description, summary: summary, drawing: drawing, afterCrash: false)
        // crashes offered in the meantime are already in the report
        CrashGuard.markCrashReportsSeen()
    }

    // MARK: Form in the dialog

    /// Problem description + optionally “include the drawing”.
    private final class ReportForm {
        let view: NSView
        let textView: NSTextView
        private let drawingCheckbox: NSButton?

        init(drawingName: String?) {
            let width: CGFloat = 420
            let textHeight: CGFloat = 110
            let label = NSTextField(labelWithString: "What were you doing? (optional – a few words help a lot)")
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor

            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: textHeight))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            scroll.autohidesScrollers = true
            let text = NSTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
            text.isRichText = false
            text.importsGraphics = false
            text.allowsUndo = true
            text.font = .systemFont(ofSize: 13)
            text.isAutomaticQuoteSubstitutionEnabled = false
            text.isAutomaticDashSubstitutionEnabled = false
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            text.textContainerInset = NSSize(width: 3, height: 4)
            scroll.documentView = text
            textView = text

            var checkbox: NSButton?
            if let name = drawingName {
                let box = NSButton(checkboxWithTitle: "Attach the open drawing \u{201C}\(name)\u{201D} (helps to reproduce the problem)",
                                   target: nil, action: nil)
                box.state = .on
                box.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                checkbox = box
            }
            drawingCheckbox = checkbox

            // layout from top to bottom
            let gap: CGFloat = 6
            let labelHeight = label.intrinsicContentSize.height
            let checkboxHeight = checkbox.map { $0.intrinsicContentSize.height + gap + 2 } ?? 0
            let height = labelHeight + gap + textHeight + checkboxHeight
            view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
            var y = height - labelHeight
            label.frame = NSRect(x: 0, y: y, width: width, height: labelHeight)
            view.addSubview(label)
            y -= gap + textHeight
            scroll.frame = NSRect(x: 0, y: y, width: width, height: textHeight)
            view.addSubview(scroll)
            if let box = checkbox {
                y -= gap + 2 + box.intrinsicContentSize.height
                box.frame = NSRect(x: 0, y: y, width: width, height: box.intrinsicContentSize.height)
                view.addSubview(box)
            }
        }

        var description: String {
            return textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var includeDrawing: Bool {
            return drawingCheckbox?.state == .on
        }
    }

    // MARK: Building the ZIP

    private static func saveReport(description: String, summary: String,
                                   drawing: (name: String, write: (URL) throws -> Void)?, afterCrash: Bool) {
        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd HHmm"

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "OhMyCAD Problem Report \(stamp.string(from: Date())).zip"
        panel.message = "Save the problem report, then attach the file to a message"
        panel.prompt = "Save Report"
        guard panel.runModal() == .OK, let destination = panel.url else { return }

        do {
            let notes = try buildReport(description: description, summary: summary, drawing: drawing,
                                        afterCrash: afterCrash, to: destination)
            Log.info("Problem report saved: \(destination.lastPathComponent)")
            NSWorkspace.shared.activateFileViewerSelecting([destination])
            if !notes.isEmpty {
                let alert = NSAlert()
                alert.alertStyle = .informational
                alert.messageText = "The report was saved, with a note"
                alert.informativeText = notes.joined(separator: "\n")
                alert.runModal()
            }
        } catch {
            Log.error("Error Saving Report: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Error Saving Report"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Report folder → ZIP at `destination`. Returns notes (what could not be included).
    private static func buildReport(description: String, summary: String,
                                    drawing: (name: String, write: (URL) throws -> Void)?,
                                    afterCrash: Bool, to destination: URL) throws -> [String] {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("OhMyCAD-Report-\(UUID().uuidString)", isDirectory: true)
        let folder = staging.appendingPathComponent("OhMyCAD Problem Report", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        Log.synchronize()
        var notes: [String] = []
        var included: [String] = []

        func copy(_ source: URL, into subfolder: String, as name: String? = nil) {
            guard fileManager.fileExists(atPath: source.path) else { return }
            let directory = folder.appendingPathComponent(subfolder, isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent(name ?? source.lastPathComponent)
            if (try? fileManager.copyItem(at: source, to: target)) != nil {
                included.append("\(subfolder)/\(target.lastPathComponent)")
            }
        }

        // log and console output
        copy(DiagnosticsPaths.log, into: "Log")
        copy(DiagnosticsPaths.previousLog, into: "Log")
        copy(DiagnosticsPaths.console, into: "Log")
        copy(DiagnosticsPaths.previousConsole, into: "Log")
        // crashes: all new ones, the last five older ones
        let newCrashes = CrashGuard.newCrashReports
        for url in newCrashes { copy(url, into: "Crashes") }
        for url in DiagnosticsPaths.files(in: DiagnosticsPaths.crashes, extensions: ["log"]).prefix(5) {
            copy(url, into: "Crashes")
        }
        for url in DiagnosticsPaths.files(in: DiagnosticsPaths.systemReports, extensions: ["json"]).prefix(5) {
            copy(url, into: "macOS Reports")
        }
        // drawing
        if let drawing = drawing {
            let directory = folder.appendingPathComponent("Drawing", isDirectory: true)
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeName = drawing.name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
            let target = directory.appendingPathComponent(safeName.isEmpty ? "Drawing" : safeName)
                .appendingPathExtension("ohmycad")
            do {
                try drawing.write(target)
                included.append("Drawing/\(target.lastPathComponent)")
            } catch {
                notes.append("The drawing could not be attached: \(error.localizedDescription)")
            }
        }

        // report.txt – an overview at the beginning
        var text = "OhMyCAD Problem Report\n"
        text += "======================\n\n"
        text += systemInfo()
        text += "\nReason for the report: " + (afterCrash ? "the app crashed (offered at the next launch)" : "reported by the user") + "\n"
        if !newCrashes.isEmpty {
            text += "\nCrash\(newCrashes.count == 1 ? "" : "es") not reported yet:\n"
            for url in newCrashes { text += "  \(url.lastPathComponent): \(CrashGuard.crashSummary(of: url))\n" }
        }
        text += "\nDescription:\n"
        text += description.isEmpty ? "(none)\n" : description + "\n"
        text += "\n" + summary + "\n"
        text += "\nFiles in this report:\n"
        text += included.isEmpty ? "  (none)\n" : included.map { "  \($0)\n" }.joined()
        if !notes.isEmpty { text += "\nNotes:\n" + notes.map { "  \($0)\n" }.joined() }
        try text.write(to: folder.appendingPathComponent("Report.txt"), atomically: true, encoding: .utf8)

        // ZIP
        let zipURL = staging.appendingPathComponent("report.zip")
        try zip(folder, to: zipURL)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: zipURL, to: destination)
        return notes
    }

    /// Pack a folder into a ZIP (via the system NSFileCoordinator, otherwise with the ditto tool).
    private static func zip(_ folder: URL, to zipURL: URL) throws {
        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: [.forUploading], error: &coordinatorError) { temporary in
            do {
                try FileManager.default.copyItem(at: temporary, to: zipURL)
            } catch {
                copyError = error
            }
        }
        if coordinatorError == nil, copyError == nil, FileManager.default.fileExists(atPath: zipURL.path) { return }

        try? FileManager.default.removeItem(at: zipURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, zipURL.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: zipURL.path) else {
            throw EditError(message: "The ZIP file could not be created ("
                            + (coordinatorError?.localizedDescription ?? copyError?.localizedDescription
                               ?? "ditto exited with \(process.terminationStatus)") + ").")
        }
    }

    // MARK: Computer info

    private static func systemInfo() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        #if DEBUG
        let configuration = "Debug"
        #else
        let configuration = "Release"
        #endif
        let process = ProcessInfo.processInfo
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        let uptime = Int(Date().timeIntervalSince(CrashGuard.launchDate))
        let memory = Double(process.physicalMemory) / 1_073_741_824

        var lines: [String] = []
        lines.append("Created: \(formatter.string(from: Date()))")
        lines.append("App: OhMyCAD \(version) (\(build)), \(configuration) build")
        lines.append("macOS: \(process.operatingSystemVersionString)")
        lines.append("Mac: \(hardwareModel()), \(process.processorCount) cores, \(String(format: "%.0f", memory)) GB memory")
        let screens = NSScreen.screens.map { screen -> String in
            let size = screen.frame.size
            return "\(Int(size.width))×\(Int(size.height)) @\(String(format: "%.0f", screen.backingScaleFactor))x"
        }
        lines.append("Screens: " + (screens.isEmpty ? "-" : screens.joined(separator: ", ")))
        lines.append("Language: \(Locale.preferredLanguages.prefix(3).joined(separator: ", ")) · region \(Locale.current.identifier)")
        lines.append("Running for: \(uptime / 3600) h \(uptime / 60 % 60) min")
        lines.append("Under the debugger (Xcode): \(CrashGuard.isDebuggerAttached ? "yes" : "no")")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func hardwareModel() -> String {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "unknown model" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "unknown model" }
        #if arch(arm64)
        let architecture = "Apple silicon"
        #else
        let architecture = "Intel"
        #endif
        let model = String(cString: buffer)
        return "\(model) (\(architecture))"
    }
}
