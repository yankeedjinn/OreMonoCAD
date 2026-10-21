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
//

import Cocoa

/// A block edit in progress in a drawing tab.
final class BlockEditSession {
    let definition: BlockDefinition
    /// The insertion being edited in place (nil = standalone, in the block's own coordinates).
    let reference: BlockReference?
    /// From block to drawing (identity for a standalone edit).
    let transform: CGAffineTransform
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
}

/// A change of a block definition's content (for the main Undo).
final class BlockContentChange: NSObject {
    let definition: BlockDefinition
    let entities: [CADEntity]

    init(definition: BlockDefinition, entities: [CADEntity]) {
        self.definition = definition
        self.entities = entities
    }
}

/// The bar above the drawing area during block editing.
final class BlockEditBar: NSView {
    var onSave: (() -> Void)?
    var onDiscard: (() -> Void)?

    private let label = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "Save Block Changes", target: nil, action: nil)
    private let discardButton = NSButton(title: "Discard Block Changes", target: nil, action: nil)

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
        let text = label.intrinsicContentSize.width
        return min(maximum, max(360, 14 + text + 16 + discardButton.frame.width + 6 + saveButton.frame.width + 10))
    }

    override func layout() {
        super.layout()
        saveButton.sizeToFit()
        discardButton.sizeToFit()
        let h = bounds.height
        saveButton.frame.origin = CGPoint(x: bounds.width - 10 - saveButton.frame.width, y: (h - saveButton.frame.height) / 2)
        discardButton.frame.origin = CGPoint(x: saveButton.frame.minX - 6 - discardButton.frame.width,
                                             y: (h - discardButton.frame.height) / 2)
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: 14, y: (h - labelHeight) / 2, width: max(0, discardButton.frame.minX - 14 - 12), height: labelHeight)
    }

    @objc private func saveClicked(_ sender: Any?) { onSave?() }
    @objc private func discardClicked(_ sender: Any?) { onDiscard?() }
}
