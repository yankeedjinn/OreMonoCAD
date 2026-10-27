//
//  ToolOptionsBar.swift
//  OreMonoCAD
//
//  The purple bar above the drawing for tools whose options are ticked while they run (Select Similar,
//  Match Properties). It looks like the block edit bar and sits in the same strip above the drawing,
//  so it never covers the place you click.
//

import Cocoa

/// One tick box of the options bar.
struct ToolOption {
    let title: String
    /// Shown when hovering the box.
    let detail: String
    let isOn: Bool
}

final class ToolOptionsBar: NSView {
    /// A box was ticked or unticked (its index, its new state).
    var onToggle: ((Int, Bool) -> Void)?
    var onDone: (() -> Void)?

    static let height: CGFloat = 34

    private let label = NSTextField(labelWithString: "")
    private var boxes: [NSButton] = []
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.blockEditBar.cgColor
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = Theme.blockEditBarBorder.cgColor
        // light text and boxes on the dark purple, in both light and dark mode
        appearance = NSAppearance(named: .darkAqua)

        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)

        doneButton.bezelStyle = .rounded
        doneButton.controlSize = .small
        doneButton.font = NSFont.systemFont(ofSize: 11)
        doneButton.target = self
        doneButton.action = #selector(doneClicked(_:))
        doneButton.refusesFirstResponder = true
        addSubview(doneButton)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The text on the left, the boxes and the hover help of Done.
    func configure(text: String, options: [ToolOption], doneHelp: String) {
        label.stringValue = text
        doneButton.toolTip = doneHelp
        if boxes.map({ $0.title }) != options.map({ $0.title }) {
            boxes.forEach { $0.removeFromSuperview() }
            boxes = options.enumerated().map { index, option in
                let box = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(boxClicked(_:)))
                box.controlSize = .small
                box.font = NSFont.systemFont(ofSize: 11)
                box.tag = index
                // the keys (↩, Esc) stay with the drawing
                box.refusesFirstResponder = true
                addSubview(box)
                return box
            }
        }
        for (box, option) in zip(boxes, options) {
            box.state = option.isOn ? .on : .off
            box.toolTip = option.detail
        }
        needsLayout = true
    }

    /// Width based on the content (at most `maximum`).
    func preferredWidth(maximum: CGFloat) -> CGFloat {
        doneButton.sizeToFit()
        boxes.forEach { $0.sizeToFit() }
        let boxesWidth = boxes.reduce(0) { $0 + $1.frame.width + 10 }
        let text = label.intrinsicContentSize.width
        return min(maximum, max(360, 14 + text + 16 + boxesWidth + 4 + doneButton.frame.width + 10))
    }

    override func layout() {
        super.layout()
        doneButton.sizeToFit()
        let h = bounds.height
        doneButton.frame.origin = CGPoint(x: bounds.width - 10 - doneButton.frame.width, y: (h - doneButton.frame.height) / 2)
        // the boxes from the right, before Done; the text gets what is left
        var x = doneButton.frame.minX - 14
        for box in boxes.reversed() {
            box.sizeToFit()
            x -= box.frame.width
            box.frame.origin = CGPoint(x: x, y: (h - box.frame.height) / 2)
            x -= 10
        }
        let labelHeight = label.intrinsicContentSize.height
        label.frame = NSRect(x: 14, y: (h - labelHeight) / 2, width: max(0, x - 14 - 6), height: labelHeight)
    }

    @objc private func boxClicked(_ sender: NSButton) { onToggle?(sender.tag, sender.state == .on) }
    @objc private func doneClicked(_ sender: Any?) { onDone?() }
}
