//
//  Recovery.swift
//  OhMyCAD
//
//  Auto-saving of unsaved work, crash recovery and backups of previous versions.
//
//  • Auto-save: every few minutes (OhMyCAD › Settings › Drawing) changed drawings are
//    quietly saved to the app's folder (…/Application Support/OhMyCAD/AutoSave). The drawing's own
//    file is NOT changed by this. After the drawing is saved or closed, the auto-save is deleted.
//    It only remains after a crash (or Stop in Xcode, a force quit) – and restoring it is offered
//    on the next launch.
//  • Backups: when saving over an existing drawing, its previous version is copied to
//    …/Application Support/OhMyCAD/Backups (at most one per 10 minutes, the last N are kept).
//    File › Open Backup… opens a backup as a copy.
//

import Cocoa

// MARK: - Options

extension AppSettings {
    /// Auto-saving of unsaved work – after how many minutes (0 = off).
    static var autosaveMinutes: Int {
        get { return UserDefaults.standard.object(forKey: "OhMyCAD.autosaveMinutes") as? Int ?? 2 }
        set { UserDefaults.standard.set(max(0, newValue), forKey: "OhMyCAD.autosaveMinutes") }
    }

    /// How many backups of previous versions to keep per drawing (0 = none).
    static var backupCount: Int {
        get { return UserDefaults.standard.object(forKey: "OhMyCAD.backupCount") as? Int ?? 10 }
        set { UserDefaults.standard.set(max(0, newValue), forKey: "OhMyCAD.backupCount") }
    }

    static let autosaveChoices: [(minutes: Int, title: String)] = [
        (0, "Off"), (1, "Every minute"), (2, "Every 2 minutes"), (5, "Every 5 minutes"), (10, "Every 10 minutes"),
    ]

    static let backupChoices: [(count: Int, title: String)] = [
        (0, "Off"), (5, "Last 5 versions"), (10, "Last 10 versions"), (20, "Last 20 versions"),
    ]
}

// MARK: - Auto-save

/// Auto-save description (next to it a .ohmycad file with the same name).
nonisolated struct AutoSaveManifest: Codable {
    var id: String
    var title: String
    /// The original drawing file (nil = the drawing has never been saved).
    var originalPath: String?
    var savedAt: Date
    var objectCount: Int
    var appVersion: String?
}

/// An auto-save found at launch.
nonisolated struct AutoSaveEntry {
    let manifest: AutoSaveManifest
    let dataURL: URL
}

/// Writing and deleting auto-saves. Writing runs in the background on a queue – deleting uses the same
/// queue, so it never overtakes a write that is still running.
nonisolated enum AutoSaveStore {
    static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("OhMyCAD", isDirectory: true)
            .appendingPathComponent("AutoSave", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let queue = DispatchQueue(label: "OhMyCAD.autosave", qos: .utility)

    private static func dataURL(_ id: String) -> URL { return folder.appendingPathComponent(id + ".ohmycad") }
    private static func manifestURL(_ id: String) -> URL { return folder.appendingPathComponent(id + ".json") }

    /// Save in the background (the drawing record is ready – it is built on the main thread).
    static func write(_ file: OhMyCADFile, manifest: AutoSaveManifest) {
        queue.async {
            let started = Date()
            do {
                let data = try NativeFormat.encode(file, compact: true)
                try data.write(to: AutoSaveStore.dataURL(manifest.id), options: .atomic)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted]
                try encoder.encode(manifest).write(to: AutoSaveStore.manifestURL(manifest.id), options: .atomic)
                let seconds = Date().timeIntervalSince(started)
                Log.info("Auto-saved \u{201C}\(manifest.title)\u{201D}: \(manifest.objectCount) objects, "
                         + "\(data.count / 1024) KB, \(String(format: "%.2f", seconds)) s")
            } catch {
                Log.error("Auto-save of \u{201C}\(manifest.title)\u{201D} failed: \(error.localizedDescription)")
            }
        }
    }

    /// Delete the auto-save (after saving, closing the drawing, a clean quit or discarding).
    static func remove(_ id: String) {
        queue.async {
            try? FileManager.default.removeItem(at: AutoSaveStore.dataURL(id))
            try? FileManager.default.removeItem(at: AutoSaveStore.manifestURL(id))
        }
    }

    /// Wait until everything in the queue has been written (before the app quits).
    static func flush() {
        queue.sync {}
    }

    /// Auto-saves left over from last time (newest first).
    static func entries() -> [AutoSaveEntry] {
        return queue.sync {
            let fileManager = FileManager.default
            let urls = (try? fileManager.contentsOfDirectory(at: AutoSaveStore.folder, includingPropertiesForKeys: nil,
                                                             options: [.skipsHiddenFiles])) ?? []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            var result: [AutoSaveEntry] = []
            for url in urls where url.pathExtension.lowercased() == "json" {
                guard let data = try? Data(contentsOf: url),
                      let manifest = try? decoder.decode(AutoSaveManifest.self, from: data) else { continue }
                let drawing = AutoSaveStore.dataURL(manifest.id)
                guard fileManager.fileExists(atPath: drawing.path) else {
                    try? fileManager.removeItem(at: url)
                    continue
                }
                result.append(AutoSaveEntry(manifest: manifest, dataURL: drawing))
            }
            // orphaned drawings without a description (write interrupted between files) – cannot be offered, delete them
            let known = Set(result.map { $0.manifest.id })
            for url in urls where url.pathExtension.lowercased() == "ohmycad" {
                let id = url.deletingPathExtension().lastPathComponent
                if !known.contains(id) && !fileManager.fileExists(atPath: AutoSaveStore.manifestURL(id).path) {
                    try? fileManager.removeItem(at: url)
                }
            }
            return result.sorted { $0.manifest.savedAt > $1.manifest.savedAt }
        }
    }
}

// MARK: - Backups of previous versions

enum BackupStore {
    static let root: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = base.appendingPathComponent("OhMyCAD", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// A new backup no sooner than this many seconds after the previous one (so frequent ⌘S don't overwrite it within minutes).
    static let minimumInterval: TimeInterval = 10 * 60

    /// Backup folder of one drawing: name + short hash of the path (same names from different folders don't get mixed up).
    static func folder(for url: URL) -> URL {
        let name = url.deletingPathExtension().lastPathComponent
        let path = url.standardizedFileURL.path
        var hash: UInt32 = 2_166_136_261                 // FNV-1a – stable across launches
        for byte in path.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/:\\")).joined(separator: "-")
        return root.appendingPathComponent("\(safe) \(String(format: "%08x", hash))", isDirectory: true)
    }

    /// The drawing's backups, newest first.
    static func backups(for url: URL) -> [URL] {
        return DiagnosticsPaths.files(in: folder(for: url), extensions: ["ohmycad"])
    }

    /// Before saving over an existing file: copy its current content into the backups.
    static func backUpBeforeOverwriting(_ url: URL) {
        let keep = AppSettings.backupCount
        guard keep > 0 else { return }
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        let directory = folder(for: url)
        let existing = backups(for: url)
        if let newest = existing.first,
           let date = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) < minimumInterval {
            return
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd HHmmss"
            let name = url.deletingPathExtension().lastPathComponent
            let target = directory.appendingPathComponent("\(name) \(formatter.string(from: Date())).ohmycad")
            try fileManager.copyItem(at: url, to: target)
            // backup time = time the backup was created (a copy would otherwise carry the original file's time)
            try? fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: target.path)
            Log.info("Backup of the previous version: \(target.lastPathComponent)")
        } catch {
            Log.error("Backup of \(url.lastPathComponent) failed: \(error.localizedDescription)")
            return
        }
        for old in backups(for: url).dropFirst(keep) {
            try? fileManager.removeItem(at: old)
        }
    }

    /// At launch: remove backups older than 90 days, and empty folders too.
    static func cleanUp() {
        let fileManager = FileManager.default
        let limit = Date().addingTimeInterval(-90 * 24 * 3600)
        let folders = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil,
                                                            options: [.skipsHiddenFiles])) ?? []
        for directory in folders {
            let files = DiagnosticsPaths.files(in: directory, extensions: ["ohmycad"])
            for file in files {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let date = date, date < limit { try? fileManager.removeItem(at: file) }
            }
            let rest = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
            if rest.filter({ !$0.hasPrefix(".") }).isEmpty { try? fileManager.removeItem(at: directory) }
        }
    }

    static func showInFinder(for url: URL?) {
        if let url = url {
            let directory = folder(for: url)
            if FileManager.default.fileExists(atPath: directory.path) {
                NSWorkspace.shared.activateFileViewerSelecting([directory])
                return
            }
        }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }
}

// MARK: - Descriptions for dialogs

enum RecoveryText {
    static func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func line(for entry: AutoSaveEntry) -> String {
        let manifest = entry.manifest
        var text = "\u{2022} \(manifest.title) \u{2013} \(manifest.objectCount) object(s), saved \(describe(manifest.savedAt))"
        if let path = manifest.originalPath {
            text += "\n   from \(abbreviate(path))"
        } else {
            text += "\n   never saved to a file"
        }
        return text
    }

    /// /Users/name/… → ~/…
    static func abbreviate(_ path: String) -> String {
        return (path as NSString).abbreviatingWithTildeInPath
    }
}
