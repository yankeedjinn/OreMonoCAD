//
//  BlockEdit.swift
//  OhMyCAD
//
//  Block editing (like BEDIT / REFEDIT in AutoCAD).
//
//  • Double-clicking a block (or Insert › Edit Block…) opens its content for editing in place, at the insertion –
//    the surrounding drawing stays dimmed but visible and can be snapped to.
//  • From the Block Manager (Edit…) the block is edited on its own, in its own coordinates.
//  • All tools work while editing; the edit has its own Undo/Redo.
//  • Save Block Changes overwrites the definition – all insertions of the block change at once. The whole edit then
//    appears in the main Undo as a single step (“Edit Block”). Discard Block Changes throws everything away.
//  • Set Base Point (in the bar) moves the block's base point. The copies in the drawing either stay where they are
//    (their insertion points move with the base point) or keep their insertion points (their drawing shifts).
//

import Cocoa

/// A block edit in progress in a drawing tab.
final class BlockEditSession {
    let definition: BlockDefinition
    /// The insertion being edited in place (nil = standalone, in the block's own coordinates).
    let reference: BlockReference?
    /// From block to drawing (identity for a standalone edit). Changes when Set Base Point moves the copies.
    private(set) var transform: CGAffineTransform
    /// The block's base point (in block coordinates) – written into the definition on save.
    private(set) var basePoint: CGPoint
    /// How far (in block coordinates) the insertion points of the copies move on save, so they stay in place.
    private(set) var copiesShift = CGPoint.zero
    /// The block's objects during editing (in drawing coordinates).
    let document = CADDocument()
    /// Undo for the block edit only.
    let undoer = UndoManager()
    /// Was the drawing unsaved before the edit? (Discard with no changes leaves it that way.)
    let wasEdited: Bool
    /// Has anything changed during the edit?
    var changed = false

    init(definition: BlockDefinition, reference: BlockReference?, wasEdited: Bool) {
        self.definition = definition
        self.reference = reference
        self.transform = reference?.blockTransform ?? .identity
        self.basePoint = definition.basePoint
        self.wasEdited = wasEdited
        for entity in definition.entities {
            let copy = entity.clone()
            copy.applyTransform(transform)
            document.addEntity(copy)
        }
    }

    /// The edited objects back in block coordinates.
    func editedEntities() -> [CADEntity] {
        let inverse = transform.inverted()
        return document.getAllEntities().map { entity -> CADEntity in
            let copy = entity.clone()
            copy.applyTransform(inverse)
            return copy
        }
    }

    // MARK: Base point

    /// The base point in drawing coordinates (where its mark is drawn).
    var basePointInDrawing: CGPoint { basePoint.applying(transform) }

    struct BasePointState {
        var basePoint: CGPoint
        var transform: CGAffineTransform
        var copiesShift: CGPoint
    }

    /// One Set Base Point step (and its reverse, for Undo).
    struct BasePointChange {
        let from: BasePointState
        let to: BasePointState
        /// How far the edited objects move (drawing coordinates).
        let objectShift: CGPoint

        var reversed: BasePointChange {
            BasePointChange(from: to, to: from, objectShift: CGPoint(x: -objectShift.x, y: -objectShift.y))
        }
    }

    private var basePointState: BasePointState {
        BasePointState(basePoint: basePoint, transform: transform, copiesShift: copiesShift)
    }

    /// The change that moves the base point to `point` (drawing coordinates).
    /// moveCopies = the copies keep their insertion points, so their drawing shifts; in place, the edited objects
    /// shift with them and the base point stays at the insertion. Otherwise the copies stay where they are.
    func basePointChange(to point: CGPoint, moveCopies: Bool) -> BasePointChange {
        let from = basePointState
        var to = from
        to.basePoint = point.applying(transform.inverted())
        var shift = CGPoint.zero
        if moveCopies {
            if reference != nil {
                let old = basePointInDrawing
                shift = CGPoint(x: old.x - point.x, y: old.y - point.y)
                to.transform = transform.concatenating(CGAffineTransform(translationX: shift.x, y: shift.y))
            }
        } else {
            to.copiesShift = CGPoint(x: copiesShift.x + to.basePoint.x - basePoint.x,
                                     y: copiesShift.y + to.basePoint.y - basePoint.y)
        }
        return BasePointChange(from: from, to: to, objectShift: shift)
    }

    func apply(_ change: BasePointChange) {
        basePoint = change.to.basePoint
        transform = change.to.transform
        copiesShift = change.to.copiesShift
        guard change.objectShift != .zero else { return }
        let shift = CGAffineTransform(translationX: change.objectShift.x, y: change.objectShift.y)
        for entity in document.getAllEntities() { entity.applyTransform(shift) }
    }

    /// The new insertion points of the copies on save, so they stay in place (empty when they don't move).
    /// `lists` = the drawing's spaces and the other blocks' contents, with the block that holds them (nil = a space).
    func copyPositions(in lists: [(entities: [CADEntity], owner: BlockDefinition?)]) -> [BlockContentChange.Placement] {
        guard copiesShift != .zero else { return [] }
        var result: [BlockContentChange.Placement] = []
        for list in lists {
            for case let copy as BlockReference in list.entities where copy.definition === definition {
                // the shift turned, mirrored and scaled like the copy
                let t = copy.blockTransform
                let offset = CGPoint(x: t.a * copiesShift.x + t.c * copiesShift.y, y: t.b * copiesShift.x + t.d * copiesShift.y)
                result.append(.init(reference: copy, position: CGPoint(x: copy.position.x + offset.x, y: copy.position.y + offset.y),
                                    owner: list.owner))
            }
        }
        return result
    }
}

/// A change of a block definition's content (for the main Undo).
final class BlockContentChange: NSObject {
    /// An insertion point of a copy of the block (`owner` = the block it lies in, nil = a space of the drawing).
    struct Placement {
        let reference: BlockReference
        let position: CGPoint
        let owner: BlockDefinition?
    }

    let definition: BlockDefinition
    let entities: [CADEntity]
    let basePoint: CGPoint
    let placements: [Placement]

    init(definition: BlockDefinition, entities: [CADEntity], basePoint: CGPoint, placements: [Placement] = []) {
        self.definition = definition
        self.entities = entities
        self.basePoint = basePoint
        self.placements = placements
    }
}

/// The bar above the drawing area during block editing.
final class BlockEditBar: NSView {
    var onSave: (() -> Void)?
    var onDiscard: (() -> Void)?
    var onSetBasePoint: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "Save Block Changes", target: nil, action: nil)
    private let discardButton = NSButton(title: "Discard Block Changes", target: nil, action: nil)
    private let basePointButton = HelpButton(title: "Set Base Point", target: nil, action: nil)

    static let height: CGFloat = 34

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.blockEditBar.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = Theme.blockEditBarBorder.cgColor

        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        saveButton.bezelStyle = .rounded
        saveButton.controlSize = .small
        saveButton.font = NSFont.systemFont(ofSize: 11)
        saveButton.keyEquivalent = ""
        saveButton.target = self
        saveButton.action = #selector(saveClicked(_:))
        saveButton.toolTip = "Write the changes into the block – every copy of it changes (⌥⌘S)"
        addSubview(saveButton)

        discardButton.bezelStyle = .rounded
        discardButton.controlSize = .small
        discardButton.font = NSFont.systemFont(ofSize: 11)
        discardButton.target = self
        discardButton.action = #selector(discardClicked(_:))
        discardButton.toolTip = "Leave the block as it was"
        addSubview(discardButton)

        basePointButton.bezelStyle = .rounded
        basePointButton.controlSize = .small
        basePointButton.font = NSFont.systemFont(ofSize: 11)
        basePointButton.target = self
        basePointButton.action = #selector(basePointClicked(_:))
        basePointButton.summary = "Move the point the block is held and inserted by"
        basePointButton.usage = "Click the new base point (snaps work). If the block has copies in the drawing, choose whether "
            + "they stay where they are or keep their insertion points and shift. Save Block Changes writes it into the block; "
            + "Undo takes it back."
        addSubview(basePointButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(blockName: String, copies: Int, inPlace: Bool) {
        let place = inPlace ? "in place" : "on its own"
        let copiesText = copies == 1 ? "1 copy in the drawing changes" : "\(copies) copies in the drawing change"
        label.stringValue = "Editing block \u{201C}\(blockName)\u{201D} \(place) \u{00B7} \(copiesText) when you save"
        layout()
    }

    /// Width based on the text (at most `maximum`).
    func preferredWidth(maximum: CGFloat) -> CGFloat {
        saveButton.sizeToFit()
        discardButton.sizeToFit()
        basePointButton.sizeToFit()
        let text = label.intrinsicContentSize.width
        return min(maximum, max(360, 14 + text + 16 + basePointButton.frame.width + 14 + discardButton.frame.width + 6
                                + saveButton.frame.width + 10))
    }

    override func layout() {
        super.layout()
        saveButton.sizeToFit()
        discardButton.sizeToFit()
        basePointButton.sizeToFit()
        let h = bounds.height
        saveButton.frame.origin = CGPoint(x: bounds.width - 10 - saveButton.frame.width, y: (h - saveButton.frame.height) / 2)
        discardButton.frame.origin = CGPoint(x: saveButton.frame.minX - 6 - discardButton.frame.width,
                                             y: (h - discardButton.frame.height) / 2)
        basePointButton.frame.origin = CGPoint(x: discardButton.frame.minX - 14 - basePointButton.frame.width,
                                               y: (h - basePointButton.frame.height) / 2)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: 14, y: (h - labelHeight) / 2, width: max(0, basePointButton.frame.minX - 14 - 12), height: labelHeight)
    }

    @objc private func saveClicked(_ sender: Any?) { onSave?() }
    @objc private func discardClicked(_ sender: Any?) { onDiscard?() }
    @objc private func basePointClicked(_ sender: Any?) {
        basePointButton.hideHelp()
        onSetBasePoint?()
    }
}

/// A button with the tool hover help: the summary at once, HOW TO USE after about 3 s (like the tool panel).
final class HelpButton: NSButton {
    var summary = ""
    var usage = ""

    private let tipView = HoverTipView(frame: .zero)
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area = trackingArea { removeTrackingArea(area) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        perform(#selector(showHelp), with: nil, afterDelay: 0.5)
        perform(#selector(expandHelp), with: nil, afterDelay: 3.0)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hideHelp()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { hideHelp() }
        super.viewWillMove(toWindow: newWindow)
    }

    func hideHelp() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        tipView.isHidden = true
    }

    @objc private func showHelp() { presentHelp(expanded: false) }
    @objc private func expandHelp() { presentHelp(expanded: true) }

    private func presentHelp(expanded: Bool) {
        guard !isHidden, let content = window?.contentView else { return }
        if tipView.superview !== content {
            tipView.removeFromSuperview()
            content.addSubview(tipView, positioned: .above, relativeTo: nil)
        }
        tipView.configure(title: title, summary: summary, usage: usage, expanded: expanded)
        // below the button, always fully inside the window
        let frame = convert(bounds, to: content)
        let size = tipView.frame.size
        var origin = CGPoint(x: frame.minX, y: frame.minY - 6 - size.height)
        origin.x = min(max(origin.x, 4), content.bounds.width - size.width - 4)
        origin.y = max(origin.y, 4)
        tipView.setFrameOrigin(origin)
        tipView.isHidden = false
    }
}
