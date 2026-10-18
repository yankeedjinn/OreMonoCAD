//
//  FindReplace.swift
//  OhMyCAD
//
//  Edit › Find and Replace… (⌘F): find and replace in texts, labels and dimension texts
//  in the open space (model or layout). Replacing goes through Undo like any other change.
//

import Cocoa

// MARK: - Search

/// A single match (the object and which of its fields).
struct TextMatch {
    enum Field {
        case text          // text, label
        case dimension     // dimension / leader text
        case belowText     // text below the dimension line
    }

    let entity: CADEntity
    let field: Field
    let value: String
    let count: Int

    var kind: String {
        switch field {
        case .text: return "Text"
        case .dimension:
            if let dimension = entity as? DimensionEntity, dimension.kind == .leader { return "Leader" }
            return "Dimension"
        case .belowText: return "Dimension (below)"
        }
    }
}

enum TextSearch {
    struct Options {
        var matchCase = false
        var wholeWords = false
    }

    /// Regular expression for the search text (entered as plain text, not as a regex).
    static func expression(for query: String, options: Options) -> NSRegularExpression? {
        guard !query.isEmpty else { return nil }
        var pattern = NSRegularExpression.escapedPattern(for: query)
        if options.wholeWords {
            // whole word: no letter or digit before or after it (works with accented letters too)
            pattern = "(?<![\\p{L}\\p{N}_])" + pattern + "(?![\\p{L}\\p{N}_])"
        }
        return try? NSRegularExpression(pattern: pattern, options: options.matchCase ? [] : [.caseInsensitive])
    }

    static func count(in text: String, _ expression: NSRegularExpression) -> Int {
        return expression.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// All matches in the objects.
    static func find(_ query: String, options: Options, in entities: [CADEntity]) -> [TextMatch] {
        guard let expression = expression(for: query, options: options) else { return [] }
        var result: [TextMatch] = []
        for entity in entities {
            if let text = entity as? TextEntity {
                let n = count(in: text.text, expression)
                if n > 0 { result.append(TextMatch(entity: text, field: .text, value: text.text, count: n)) }
            } else if let dimension = entity as? DimensionEntity {
                let n = count(in: dimension.text, expression)
                if n > 0 { result.append(TextMatch(entity: dimension, field: .dimension, value: dimension.text, count: n)) }
                let below = count(in: dimension.belowText, expression)
                if below > 0 {
                    result.append(TextMatch(entity: dimension, field: .belowText, value: dimension.belowText, count: below))
                }
            }
        }
        return result
    }

    /// Replacement in a single text (the replacement is literal – $ and \ have no special meaning).
    static func replace(in text: String, _ expression: NSRegularExpression, with replacement: String) -> String {
        return expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                   withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    /// Replaces in the selected matches. Returns pairs (original object, edited copy) – each object at most once.
    static func replacements(for matches: [TextMatch], query: String, replacement: String,
                             options: Options) -> [(old: CADEntity, new: CADEntity)] {
        guard let expression = expression(for: query, options: options) else { return [] }
        var copies: [UUID: (old: CADEntity, new: CADEntity)] = [:]
        var order: [UUID] = []
        for match in matches {
            let id = match.entity.id
            if copies[id] == nil {
                copies[id] = (match.entity, match.entity.clone())
                order.append(id)
            }
            guard let copy = copies[id]?.new else { continue }
            switch match.field {
            case .text:
                if let text = copy as? TextEntity { text.text = replace(in: text.text, expression, with: replacement) }
            case .dimension:
                if let dimension = copy as? DimensionEntity {
                    dimension.text = replace(in: dimension.text, expression, with: replacement)
                }
            case .belowText:
                if let dimension = copy as? DimensionEntity {
                    dimension.belowText = replace(in: dimension.belowText, expression, with: replacement)
                }
            }
        }
        return order.compactMap { copies[$0] }
    }
}

// MARK: - Window

/// Floating Find and Replace window. Talks to the drawing via closures (MainViewController).
final class FindReplaceController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate,
                                   NSSearchFieldDelegate {
    /// Objects of the open space that are searched (visible layers).
    var entities: (() -> [CADEntity])?
    /// Can the object be changed? (locked layer = no)
    var isEditable: ((CADEntity) -> Bool)?
    /// Space name for the status line (“Model”, “Layout1”).
    var spaceName: (() -> String)?
    /// Show objects in the drawing (select and zoom).
    var onShow: (([CADEntity]) -> Void)?
    /// Select objects (without zooming).
    var onSelect: (([CADEntity]) -> Void)?
    /// Perform the replacement (as a single Undo change).
    var onReplace: (([(old: CADEntity, new: CADEntity)]) -> Void)?

    private let findField = NSSearchField()
    private let replaceField = NSTextField()
    private let matchCaseBox = NSButton(checkboxWithTitle: "Match case", target: nil, action: nil)
    private let wholeWordsBox = NSButton(checkboxWithTitle: "Whole words only", target: nil, action: nil)
    private let table = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "Replace All", target: nil, action: nil)
    private let selectButton = NSButton(title: "Select All Found", target: nil, action: nil)

    private var matches: [TextMatch] = []
    /// Row selection is being changed by code (after a search) – nothing is shown in the drawing then.
    private var updatingSelection = false

    init() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Find and Replace"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 460, height: 320)
        super.init(window: panel)
        panel.delegate = self
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Open the window; `initial` = text to search for (e.g. from the selected text).
    func show(searching initial: String?) {
        if let initial = initial, !initial.isEmpty { findField.stringValue = initial }
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(findField)
        search()
    }

    /// The drawing changed (another tab, Undo…) → search again.
    func refresh() {
        guard window?.isVisible == true else { return }
        search()
    }

    // MARK: Building

    private func build() {
        guard let content = window?.contentView else { return }
        let width = content.bounds.width
        let height = content.bounds.height
        let margin: CGFloat = 16
        let labelWidth: CGFloat = 96
        let fieldX = margin + labelWidth + 6

        func label(_ text: String, y: CGFloat) {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            field.frame = NSRect(x: margin, y: y + 3, width: labelWidth, height: 17)
            field.autoresizingMask = [.minYMargin]
            content.addSubview(field)
        }

        var y = height - margin - 24
        label("Find:", y: y)
        findField.frame = NSRect(x: fieldX, y: y, width: width - fieldX - margin, height: 24)
        findField.autoresizingMask = [.width, .minYMargin]
        findField.placeholderString = "Text to find in texts, labels and dimension texts"
        findField.sendsSearchStringImmediately = true
        findField.delegate = self
        findField.target = self
        findField.action = #selector(findChanged(_:))
        content.addSubview(findField)

        y -= 32
        label("Replace with:", y: y)
        replaceField.frame = NSRect(x: fieldX, y: y, width: width - fieldX - margin, height: 24)
        replaceField.autoresizingMask = [.width, .minYMargin]
        replaceField.placeholderString = "Empty = delete the found text"
        content.addSubview(replaceField)

        y -= 30
        matchCaseBox.frame = NSRect(x: fieldX, y: y, width: 120, height: 20)
        matchCaseBox.autoresizingMask = [.minYMargin]
        matchCaseBox.target = self
        matchCaseBox.action = #selector(optionsChanged(_:))
        content.addSubview(matchCaseBox)
        wholeWordsBox.frame = NSRect(x: fieldX + 130, y: y, width: 160, height: 20)
        wholeWordsBox.autoresizingMask = [.minYMargin]
        wholeWordsBox.target = self
        wholeWordsBox.action = #selector(optionsChanged(_:))
        content.addSubview(wholeWordsBox)

        // replace buttons on the right below the fields
        replaceAllButton.bezelStyle = .rounded
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll(_:))
        replaceAllButton.sizeToFit()
        replaceAllButton.frame.origin = CGPoint(x: width - margin - replaceAllButton.frame.width, y: y - 34)
        replaceAllButton.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(replaceAllButton)
        replaceButton.bezelStyle = .rounded
        replaceButton.target = self
        replaceButton.action = #selector(replaceSelected(_:))
        replaceButton.sizeToFit()
        replaceButton.frame.origin = CGPoint(x: replaceAllButton.frame.minX - 8 - replaceButton.frame.width, y: y - 34)
        replaceButton.autoresizingMask = [.minXMargin, .minYMargin]
        replaceButton.toolTip = "Replaces in the rows selected in the list"
        content.addSubview(replaceButton)

        let hint = NSTextField(labelWithString: "Click a row to show it in the drawing · ⌘-click or ⇧-click selects more rows")
        hint.font = NSFont.systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: margin, y: y - 30, width: replaceButton.frame.minX - margin - 8, height: 16)
        hint.autoresizingMask = [.width, .minYMargin]
        hint.lineBreakMode = .byTruncatingTail
        content.addSubview(hint)

        // list of matches
        let tableTop = y - 44
        let bottom: CGFloat = 50
        let scroll = NSScrollView(frame: NSRect(x: margin, y: bottom, width: width - 2 * margin, height: tableTop - bottom))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        for (identifier, title, columnWidth) in [("text", "Text", 330.0), ("kind", "Kind", 80.0), ("layer", "Layer", 100.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = CGFloat(columnWidth)
            column.resizingMask = identifier == "text" ? [.autoresizingMask, .userResizingMask] : [.userResizingMask]
            table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(showSelectedRows(_:))
        scroll.documentView = table
        content.addSubview(scroll)

        // status and selection at the bottom
        statusLabel.frame = NSRect(x: margin, y: 18, width: width - 2 * margin - 170, height: 17)
        statusLabel.autoresizingMask = [.width, .maxYMargin]
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)
        selectButton.bezelStyle = .rounded
        selectButton.target = self
        selectButton.action = #selector(selectAllFound(_:))
        selectButton.sizeToFit()
        selectButton.frame.origin = CGPoint(x: width - margin - selectButton.frame.width, y: 12)
        selectButton.autoresizingMask = [.minXMargin, .maxYMargin]
        selectButton.toolTip = "Selects all found objects in the drawing – e.g. to change their layer or style at once"
        content.addSubview(selectButton)

        updateButtons()
    }

    // MARK: Search

    private var options: TextSearch.Options {
        return TextSearch.Options(matchCase: matchCaseBox.state == .on, wholeWords: wholeWordsBox.state == .on)
    }

    @objc private func findChanged(_ sender: Any?) {
        search()
    }

    @objc private func optionsChanged(_ sender: Any?) {
        search()
    }

    private func search() {
        let query = findField.stringValue
        let found = TextSearch.find(query, options: options, in: entities?() ?? [])
        // matches that can stay selected remain selected
        let previouslySelected = Set(table.selectedRowIndexes.compactMap { index -> String? in
            index < matches.count ? key(matches[index]) : nil
        })
        matches = found
        updatingSelection = true
        table.reloadData()
        let keep = IndexSet(matches.indices.filter { previouslySelected.contains(key(matches[$0])) })
        table.selectRowIndexes(keep, byExtendingSelection: false)
        updatingSelection = false
        updateStatus()
        updateButtons()
    }

    private func key(_ match: TextMatch) -> String {
        return "\(match.entity.id.uuidString)-\(match.field)"
    }

    private func updateStatus() {
        let space = spaceName?() ?? "the drawing"
        if findField.stringValue.isEmpty {
            statusLabel.stringValue = "Type the text to find – it is searched in \(space)"
            return
        }
        let total = matches.reduce(0) { $0 + $1.count }
        let objects = Set(matches.map { $0.entity.id }).count
        if matches.isEmpty {
            statusLabel.stringValue = "Not found in \(space)"
        } else {
            statusLabel.stringValue = "\(total) occurrence\(total == 1 ? "" : "s") in \(objects) object\(objects == 1 ? "" : "s") · \(space)"
        }
    }

    private func updateButtons() {
        let any = !matches.isEmpty
        replaceAllButton.isEnabled = any
        replaceButton.isEnabled = any && !table.selectedRowIndexes.isEmpty
        selectButton.isEnabled = any
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int {
        return matches.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < matches.count, let column = tableColumn else { return nil }
        let match = matches[row]
        let identifier = column.identifier
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? {
            let view = NSTableCellView()
            view.identifier = identifier
            let field = NSTextField(labelWithString: "")
            field.lineBreakMode = .byTruncatingTail
            field.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(field)
            view.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
                field.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
                field.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
            return view
        }()
        let locked = !(isEditable?(match.entity) ?? true)
        switch identifier.rawValue {
        case "text":
            let single = match.value.replacingOccurrences(of: "\n", with: " / ")
            cell.textField?.stringValue = single.count > 300 ? String(single.prefix(300)) + "…" : single
        case "kind":
            cell.textField?.stringValue = match.kind + (match.count > 1 ? " (\(match.count)×)" : "")
        default:
            cell.textField?.stringValue = match.entity.layer + (locked ? " (locked)" : "")
        }
        cell.textField?.textColor = locked ? .tertiaryLabelColor : .labelColor
        cell.toolTip = locked ? "On a locked layer – it is not changed by Replace" : match.value
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateButtons()
        guard !updatingSelection else { return }
        showSelectedRows(nil)
    }

    private var selectedMatches: [TextMatch] {
        return table.selectedRowIndexes.compactMap { $0 < matches.count ? matches[$0] : nil }
    }

    @objc private func showSelectedRows(_ sender: Any?) {
        let chosen = selectedMatches
        guard !chosen.isEmpty else { return }
        onShow?(unique(chosen.map { $0.entity }))
    }

    private func unique(_ entities: [CADEntity]) -> [CADEntity] {
        var seen = Set<UUID>()
        return entities.filter { seen.insert($0.id).inserted }
    }

    // MARK: Actions

    @objc private func selectAllFound(_ sender: Any?) {
        guard !matches.isEmpty else { return }
        onSelect?(unique(matches.map { $0.entity }))
    }

    @objc private func replaceSelected(_ sender: Any?) {
        replace(selectedMatches)
    }

    @objc private func replaceAll(_ sender: Any?) {
        replace(matches)
    }

    private func replace(_ chosen: [TextMatch]) {
        let query = findField.stringValue
        guard !query.isEmpty, !chosen.isEmpty else { return }
        let editable = chosen.filter { isEditable?($0.entity) ?? true }
        let skipped = Set(chosen.map { $0.entity.id }).count - Set(editable.map { $0.entity.id }).count
        let pairs = TextSearch.replacements(for: editable, query: query, replacement: replaceField.stringValue,
                                            options: options)
        let occurrences = editable.reduce(0) { $0 + $1.count }
        if !pairs.isEmpty { onReplace?(pairs) }
        search()
        var message = pairs.isEmpty ? "Nothing replaced"
            : "Replaced \(occurrences) occurrence\(occurrences == 1 ? "" : "s") in \(pairs.count) object\(pairs.count == 1 ? "" : "s") (⌘Z undoes it)"
        if skipped > 0 { message += " · \(skipped) on locked layers skipped" }
        statusLabel.stringValue = message
    }

    // MARK: Window

    func windowDidBecomeKey(_ notification: Notification) {
        search()
    }
}
