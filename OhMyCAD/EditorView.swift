//
//  EditorView.swift
//  OhMyCAD
//
//  The drawing area: rendering, mouse, keyboard and the logic of all tools.
//

import Cocoa

// MARK: - Drawing Tools

enum ToolGroup: Int, CaseIterable {
    case draw, architecture, modify, transform, dimension, insert, view

    var title: String {
        switch self {
        case .draw: return "Draw"
        case .architecture: return "Architecture"
        case .modify: return "Modify"
        case .transform: return "Transform"
        case .dimension: return "Annotate"
        case .insert: return "Insert"
        case .view: return "Zoom"
        }
    }
}

enum DrawingTool: Int, CaseIterable {
    case select, line, xline, circle, arc, ellipse, polygon, rectangle, polyline, spline, wall, wallFromCurve, hatch, hatchRebuild, hatchCut
    case trim, extend, fillet, chamfer, powerTrim, breakObject, breakAtPoint, offset, explode, join, editPoints, matchProperties, filter
    case move, copy, rotate, scale, mirror, stretch, array
    case dimLinear, dimAligned, dimContinue, dimAngular, dimRadius, dimDiameter, leader
    case text, roomLabel, measure, revisionCloud, wipeout, scaleBar, northArrow
    case blockCreate, blockInsert, xref, image
    case zoomIn, zoomOut, zoomExtents, zoomSelected, zoomWindow

    var title: String {
        switch self {
        case .select: return "Select"
        case .line: return "Line"
        case .xline: return "Construction Line"
        case .circle: return "Circle"
        case .arc: return "Arc"
        case .ellipse: return "Ellipse"
        case .polygon: return "Polygon"
        case .rectangle: return "Rectangle"
        case .polyline: return "Polyline"
        case .spline: return "Spline"
        case .wall: return "Wall"
        case .wallFromCurve: return "Wall from Curve"
        case .trim: return "Trim"
        case .extend: return "Extend"
        case .fillet: return "Fillet"
        case .chamfer: return "Chamfer"
        case .offset: return "Offset"
        case .explode: return "Explode"
        case .hatchRebuild: return "Rebuild Hatch"
        case .hatchCut: return "Cut Out of Hatch"
        case .editPoints: return "Edit Points"
        case .matchProperties: return "Match Properties"
        case .filter: return "Filter"
        case .join: return "Join"
        case .hatch: return "Hatch"
        case .powerTrim: return "PowerTrim"
        case .breakObject: return "Break"
        case .breakAtPoint: return "Break at Point"
        case .move: return "Move"
        case .copy: return "Copy"
        case .rotate: return "Rotate"
        case .scale: return "Scale"
        case .mirror: return "Mirror"
        case .stretch: return "Stretch"
        case .array: return "Array"
        case .dimLinear: return "Linear Dimension"
        case .dimAligned: return "Aligned Dimension"
        case .dimContinue: return "Continue Dimension"
        case .dimAngular: return "Angular Dimension"
        case .dimRadius: return "Radius Dimension"
        case .dimDiameter: return "Diameter Dimension"
        case .leader: return "Leader"
        case .text: return "Text"
        case .measure: return "Measure"
        case .revisionCloud: return "Revision Cloud"
        case .wipeout: return "Wipeout"
        case .roomLabel: return "Room Label"
        case .scaleBar: return "Scale Bar"
        case .northArrow: return "North Arrow"
        case .blockCreate: return "Create Block"
        case .blockInsert: return "Insert Block"
        case .xref: return "Attach External Reference"
        case .image: return "Attach Image or PDF"
        case .zoomIn: return "Zoom In"
        case .zoomOut: return "Zoom Out"
        case .zoomExtents: return "Zoom Extents"
        case .zoomSelected: return "Zoom Selected"
        case .zoomWindow: return "Zoom Window"
        }
    }

    // MARK: Tool help
    //
    // RULE: every tool MUST have both a summary and short usage instructions in `help`.
    // They are shown in a popup when hovering over the icon (usage after 3 s).
    // Missing help is reported by Xcode as a warning on every build
    // (the Scripts/check_tool_help.sh check in the “Check Tool Help” phase).

    static let help: [DrawingTool: (summary: String, usage: String)] = [
        .select: (
            summary: "Selects objects so you can edit, move or delete them.",
            usage: "Click an object · Shift-click adds or removes · drag left→right = objects fully inside, right→left = everything crossed (or click two corners instead of dragging) · drag a selected object to move it · the blue grips of selected objects edit their points (click or drag a grip, then click the new position)."),
        .line: (
            summary: "A straight line between two points.",
            usage: "Click the start and the end (or drag). Type length and angle in the box at the cursor. With LNC on (⌥7, or the Line key again while drawing), lines continue from the last end – ↩/Esc ends, C closes."),
        .xline: (
            summary: "An endless construction line for laying out the drawing – snaps, intersections and Trim work with it.",
            usage: "Click a point and then the direction (more lines through the same point follow until Esc). Hold the button (or right-click it) for Horizontal, Vertical or at an Angle – then every click places one line. While drawing press H, V, A or B (two points) to switch. Lines follow the rotated drawing coordinates. Trim or PowerTrim the ends away to turn a construction line into an ordinary line."),
        .circle: (
            summary: "A circle given by its center and radius.",
            usage: "Click the center, then a point on the circle – or type the radius."),
        .arc: (
            summary: "A circular arc – seven ways to construct it.",
            usage: "Hold the button (or right-click it) to choose the method. The ring in the icon marks the first point. Values can be typed at the cursor. When the center is known, hold Shift for the end in 15° steps."),
        .ellipse: (
            summary: "An ellipse given by its center and both half-axes – trim it to get an elliptical arc.",
            usage: "Click the center, then the end of the first axis (sets its direction and length), then the width of the other axis – or type the values at the cursor. Hold Shift (ortho) for a horizontal or vertical first axis. Grips change the axes; Trim makes an elliptical arc."),
        .polygon: (
            summary: "A regular polygon (equal sides and angles) – stored as a closed polyline.",
            usage: "Inscribed: click the center, then a corner. Circumscribed: the center, then the middle of a side. By one side: the two corners of one side (the polygon grows to the left). Press I, C or E while drawing to switch, S for the number of sides – or type radius, angle and sides at the cursor (Tab = next field)."),
        .rectangle: (
            summary: "A rectangle, stored as a closed polyline.",
            usage: "Click one corner, then the opposite one – or type width and height (Tab = next field). Hold Shift for a square while you hold it. C = from the center or from a corner, S = square on/off – both switch any time, also while drawing. From the center the typed width and height are the whole rectangle; for a square one side is enough."),
        .polyline: (
            summary: "Connected straight segments forming a single object.",
            usage: "Click the points · ↩, Esc, right-click or double-click finishes (with CLS on it asks whether to close) · C or clicking the first point closes · ⌫ removes the last point."),
        .spline: (
            summary: "A smooth curve passing through the points you click.",
            usage: "Click the points · ↩, Esc, right-click or double-click finishes (with CLS on it asks whether to close) · C or clicking the first point closes · ⌫ removes the last point."),
        .wall: (
            summary: "A wall drawn with a double line – click its line, and both faces appear at the wall thickness with mitered corners.",
            usage: "Click the points of the wall line · ↩, Esc, right-click or double-click finishes · C or a click on the first point closes it into a ring · ⌫ removes the last point · T = thickness in mm (remembered, 300 at first) · J = where the wall lies: centered on the line, to its left or to its right. The result is closed polylines (an open wall = one outline with its ends, a ring = the outer and the inner face), ready for a hatch. Walls are not joined automatically – clean up where they meet with Trim or PowerTrim."),
        .wallFromCurve: (
            summary: "Turns selected lines, arcs, polylines, splines, circles and ellipses into walls – both faces at the wall thickness along the curve.",
            usage: "Select the curves (before or after starting the tool) – the green preview shows the walls · T = thickness in mm (the same as for Wall) · J = where the wall lies: centered on the curve, outside or inside it (for an open curve, inside = the side it bends toward) · ↩ or right-click creates the walls, Esc cancels. Curves whose ends touch become one wall with mitered corners. The result is closed polylines, as with Wall; the curves themselves stay."),
        .hatch: (
            summary: "Fills or hatches a closed area – found automatically from whatever surrounds it.",
            usage: "Move over an area to see it highlighted, click to hatch it. Hold the button (or right-click it) for patterns, custom patterns, settings, Rebuild Hatch and Cut Out of Hatch; type angle and scale at the cursor. Gaps up to 3 px are bridged. Exactly the clicked area is filled: shapes inside it are left out as islands, and nothing inside those islands is filled."),
        .hatchRebuild: (
            summary: "Gives a hatch the shape of the closed area around it – e.g. after you draw the jambs of an opening.",
            usage: "Select the hatch (or several) and choose this tool (in the menu of the Hatch button) – or choose it first, select the hatch and press ↩. The pattern, angle and scale stay."),
        .hatchCut: (
            summary: "Cuts closed shapes (rectangle, circle, closed polyline) out of a hatch – an opening in a wall, a hole in a slab.",
            usage: "Select the hatch together with the closed shapes and choose this tool (in the menu of the Hatch button) – or choose it first, select them and press ↩. A shape across the edge trims or splits the hatch, a shape inside makes an island. The shapes stay in the drawing."),
        .trim: (
            summary: "Cuts away the part of an object between intersections.",
            usage: "Click the part to remove – every object cuts by default. Shift-click picks specific cutting edges. The red preview shows what will go. Construction lines can be trimmed too: cut on one side they become rays, on both sides ordinary lines."),
        .extend: (
            summary: "Lengthens a line, an arc or an open polyline up to the nearest object in its way.",
            usage: "Click near the end you want to extend. Shift-click picks specific boundaries. The green preview shows the result."),
        .offset: (
            summary: "Creates a parallel copy of a line, circle, arc, ellipse, polyline or spline at a given distance.",
            usage: "Type the distance (or 0 = through a point), click the object, then click the side. Repeats until Esc. Without a distance the copy goes through the clicked point. An ellipse or a spline gives a polyline that follows it closely."),
        .matchProperties: (
            summary: "Copies the look of one object – layer, color, lineweight, and for texts, dimensions and hatches their style – onto other objects.",
            usage: "Click the source object (or have one selected when you start), then click the objects to change, or drag a window over them (left→right = fully inside, right→left = crossed). Repeats until ↩, right-click or Esc. Hold the button (or right-click it) to choose which properties are copied."),
        .filter: (
            summary: "Selects the objects that match the properties you choose – object type, layer, color, linetype, lineweight, block name or a piece of text.",
            usage: "Click it (or Edit › Filter…), tick one or more properties and pick their values – an object must match all ticked ones. Search the whole drawing or only the current selection (so a second Filter narrows the first). Whole drawing = its visible objects on unlocked layers, Current selection = all selected objects; the linetype is that of the object's layer. The found objects become the selection and the Select tool is on – move, copy, delete or edit them as usual."),
        .fillet: (
            summary: "Rounds the corner between two lines or polyline segments with an arc.",
            usage: "Type the radius (0 = sharp corner), then click both lines on the sides you want to keep. Two neighboring segments of one polyline get an arc inside the polyline; a polyline end + a line are joined into one polyline."),
        .chamfer: (
            summary: "Cuts off (bevels) the corner between two lines or polyline segments with a straight line.",
            usage: "Type the two distances (Tab = next field; one value = both the same, 0 and 0 = sharp corner), then click both lines on the sides you want to keep – the first distance is measured on the first line from the corner. Two neighboring segments of one polyline are beveled inside the polyline; a polyline end + a line are joined into one polyline."),
        .explode: (
            summary: "Breaks polylines (and rectangles) into separate lines and arcs, and blocks into the objects they are made of.",
            usage: "Select the polylines or blocks and press ↩ – or select them first and then pick Explode."),
        .join: (
            summary: "Joins touching lines, arcs and polylines into one polyline; a single line becomes a polyline.",
            usage: "Select the objects and press ↩ – or select them first and then pick Join. Pieces whose ends meet are chained; a loop becomes a closed polyline."),
        .editPoints: (
            summary: "Selects single points (vertices, ends, centers) of any objects and moves them together.",
            usage: "Click a point or drag a box around points (or click its two corners) · Shift-click adds or removes · drag a selected point (or click it, then click the target) to move all selected points · snap, ortho and typed distance work."),
        .powerTrim: (
            summary: "Trims many parts with one stroke; a click extends an object like Extend.",
            usage: "Drag a freehand line across the parts to remove. A part ends at the nearest intersection or polyline corner, so one side of a polyline can be removed; an object that crosses nothing is removed whole. Construction lines work too – trimmed on both sides they become ordinary lines. Click near the end of a line, arc or open polyline to extend it to the nearest object."),
        .breakObject: (
            summary: "Removes the part of a line, arc, circle, ellipse, polyline or spline between two points – opens a gap.",
            usage: "Click the object at the first break point, then the second point (snaps work; the point is taken on the object). On a circle, an ellipse or a closed polyline the part counter-clockwise from the first to the second point is removed. Clicking the same point twice splits the object without a gap."),
        .breakAtPoint: (
            summary: "Splits a line, arc, polyline or spline into two objects at one point – without a gap.",
            usage: "Click the object where it should be split (snaps work, e.g. to an intersection or a midpoint). A closed polyline is opened at that point."),
        .move: (
            summary: "Moves the selected objects.",
            usage: "Select objects (↩), click a base point, then the target – or type distance and angle. With Select you can also simply drag a selected object."),
        .copy: (
            summary: "Copies the selected objects, as many times as you like.",
            usage: "Select objects (↩), click a base point, then click every place for a copy. Esc ends."),
        .rotate: (
            summary: "Rotates the selected objects around a point.",
            usage: "Select objects (↩), click the center of rotation, then click or type the angle (°). Hold Shift for 15° steps."),
        .scale: (
            summary: "Enlarges or shrinks the selected objects.",
            usage: "Select objects (↩), click the base point (it stays put), then click a grip point on the objects and pull it: at the dashed circle = 1×, closer = smaller (down to 0.01), farther = larger, past the base point = negative (turned 180°). Or type any factor – 0.01, 10, -1, 1/3 – and press ↩."),
        .mirror: (
            summary: "Creates a mirrored copy of the selected objects.",
            usage: "Select objects (↩), then click two points of the mirror line. At the end the bottom line asks whether to delete the originals: Y = yes, N / ↩ / click / right-click = keep them, Esc = cancel."),
        .stretch: (
            summary: "Stretches objects: points inside a window move, everything else stays – walls get longer, openings shift.",
            usage: "Drag a window (or click two corners) around the points to move – objects completely inside move as a whole, objects crossing the window are stretched. Then click the base point and the target, or type distance and angle. Circles, texts and blocks move only when their center / insertion point is inside."),
        .array: (
            summary: "Many copies at once – in rows and columns, or around a center point.",
            usage: "Hold the button (or right-click it) to choose Rectangular or Polar. Select objects (↩), for Polar click the center, then set the counts and spacing in the dialog – the preview updates as you type."),
        .dimLinear: (
            summary: "A horizontal or vertical dimension.",
            usage: "Click two points, then the position of the dimension line – move up/down for horizontal, left/right for vertical."),
        .dimContinue: (
            summary: "A chain of dimensions – each new one continues from the end of the previous one on the same line.",
            usage: "Right after a linear or aligned dimension, click the next points one by one (snap works). Otherwise click the dimension to continue from – near the end you want to go on from. ↩, right-click or Esc ends the chain."),
        .dimAligned: (
            summary: "A dimension parallel to the measured edge.",
            usage: "Click two points, then the distance of the dimension line."),
        .dimAngular: (
            summary: "Measures the angle between two legs.",
            usage: "Click the vertex, a point on each leg, then where the arc should go."),
        .dimRadius: (
            summary: "The radius of a circle or arc (R…).",
            usage: "Click the circle or arc, then where the text should go."),
        .dimDiameter: (
            summary: "The diameter of a circle or arc (Ø…).",
            usage: "Click the circle or arc, then where the text should go."),
        .text: (
            summary: "Writes text – a quick single line, a wrapping paragraph, or text with chosen font, typeface, height and rotation.",
            usage: "Click and type right on the drawing – ↩ places it, ⌥↩ = new line, Esc cancels. The ☰ menu next to the text opens font, typeface, height, rotation, alignment and width, which turns plain text into formatted text. Hold the button (or right-click it) for Paragraph (a box that wraps) or Formatted (panel opens at once). Double-click a text to edit it the same way."),
        .measure: (
            summary: "Measures without drawing anything – distance, angle, radius, area and perimeter, coordinates or length of objects.",
            usage: "Hold the button (or right-click it) to choose what to measure. Distance and Angle: click the points · Area: click the corners (↩ finishes, ⌫ removes the last one), click inside a closed area, or click a closed object · Length: click objects to add them up. The result shows on the drawing and in the bottom line; Esc clears it."),
        .blockCreate: (
            summary: "Turns the selected objects into a named block – a reusable symbol such as a door, a window, furniture or a title block.",
            usage: "Select the objects (↩), click the base point (you will insert the block by it) and type the name. The objects become one block. Using the same name again redefines the block – every copy in the drawing changes. Explode turns a block back into objects."),
        .blockInsert: (
            summary: "Places a block of this drawing – as many times as you like.",
            usage: "Hold the button (or right-click it) to choose the block, create one, open the Block Manager, attach an external reference or attach an image or PDF. Click the insertion point, again for more copies, Esc ends. Rotation, scale and mirroring are in Properties."),
        .xref: (
            summary: "Attaches another drawing (.ohmycad or .dxf) as an external reference – it updates by itself when that file is saved.",
            usage: "Choose the file, then click where its origin (0,0) should go. The reference cannot be edited here; Block Manager reloads it, finds a moved file or binds it into the drawing as an ordinary block."),
        .image: (
            summary: "Places a scan, photo, map or PDF page into the drawing to trace over – it is stored inside the drawing.",
            usage: "Choose the file and the scale it is drawn at (a 1:1000 map → 1:1000, a page of drawings → its scale), then click where its lower-left corner goes. Fit it onto the drawing with Move, Rotate and Scale (Scale: base point, a point of the picture, then where that point belongs) or by dragging a corner grip. Properties sets the opacity. It lies under the lines, its frame is not printed, and it is not exported to DXF."),
        .zoomIn: (
            summary: "Shows the drawing larger (closer).",
            usage: "Click it – the view zooms in around its center. Also ⌘= , the mouse wheel or pinching on the trackpad (zooms to the cursor). The current tool keeps working."),
        .zoomOut: (
            summary: "Shows the drawing smaller (farther).",
            usage: "Click it – the view zooms out around its center. Also ⌘- , the mouse wheel or pinching on the trackpad. The current tool keeps working."),
        .zoomExtents: (
            summary: "Fits the whole drawing into the window – every visible object, as large as possible. On a layout it shows the whole sheet.",
            usage: "Click it (or ⌘E, or double-click the middle mouse button). Handy when you get lost or after opening a file. The current tool keeps working."),
        .zoomSelected: (
            summary: "Fits only the selected objects into the window, as large as possible.",
            usage: "Select one or more objects, then click it (or ⌃⌘E). With nothing selected it does nothing and tells you so. Construction lines are ignored – they have no end. The current tool keeps working."),
        .zoomWindow: (
            summary: "Zooms to an area you choose with a rectangle.",
            usage: "Click it, then click two opposite corners of the area to show · Esc = cancel. Snap and grid work for the corners."),
        .roomLabel: (
            summary: "A room label – the room name and its floor area in m², which updates itself when the walls change.",
            usage: "Move over a room to see its outline, click inside it and type the name (it can stay empty). The outline must be closed – close door openings with a line or a door. Free-standing objects inside (furniture, columns) don't reduce the area; texts, dimensions, hatches and construction lines don't count. Edit the name like any text – the last line (m²) is kept up to date. Moved into another room, the label measures that one."),
        .scaleBar: (
            summary: "A graphic scale bar – from 0 to a round length, true to the drawing scale (on a layout, to the nearest viewport).",
            usage: "Click where its left end goes – it runs along the X axis of the drawing coordinates. It is about 5 cm long on paper, split into 4 or 5 parts. On a layout it takes the scale of the viewport nearest to the click. It is one block (“Scale Bar 1:100”); after changing the scale place a new one."),
        .northArrow: (
            summary: "A north arrow pointing north – up in the drawing, which is always drawn north-up.",
            usage: "Click where to place it. Its size is set on paper, so it suits any drawing scale, and it keeps pointing north when the view or the drawing coordinates are rotated. It is one block (“North Arrow”) – edit that block to change its look, e.g. the letter."),
        .revisionCloud: (
            summary: "A revision cloud – scalloped arcs around a changed part of the drawing (one closed polyline).",
            usage: "Click the corners of the outline · ↩, right-click, double-click, C or a click on the first corner closes it · ⌫ removes the last corner · R = rectangle from two corners (hold Shift for a square), P = back to corners · A = arc size in mm on paper (remembered). The arcs of a drawn cloud change in Properties › Scale (1 = 8 mm on paper)."),
        .wipeout: (
            summary: "A wipeout – an area that covers what lies below it with the background color, so a text or a dimension over a hatch or lines stays readable.",
            usage: "Click two opposite corners of a rectangle (or type width and height; hold Shift for a square) · P = outline by corners (↩, right-click, double-click, C or a click on the first corner closes it, ⌫ removes the last corner) · R = back to the rectangle. It covers lines and hatches but stays below texts and dimensions, so draw it around a text that is already there (Edit › Draw Order puts it above or below other objects). Its frame shows on screen only and is not printed; wipeouts are not exported to DXF."),
        .leader: (
            summary: "An arrow with a note.",
            usage: "Click the arrow point, then one or more bend points · ⌫ removes the last point · ↩, right-click or double-click asks for the text."),
    ]

    /// What the tool does (one sentence).
    var summary: String {
        return DrawingTool.help[self]?.summary ?? "(No description yet.)"
    }

    /// How the tool is used (very briefly).
    var usage: String {
        return DrawingTool.help[self]?.usage ?? "(No instructions yet.)"
    }

    /// Tool icon – drawn in code (ToolIcons.swift).
    func icon(pointSize: CGFloat = 15) -> NSImage? {
        return ToolIcons.image(for: self, size: pointSize + 4)
    }

    /// Keyboard shortcut (without modifiers) on the drawing area – custom from Settings, otherwise the default.
    var shortcut: String? {
        return Shortcuts.key(for: self)
    }

    /// The tool's default shortcut.
    var defaultShortcut: String? {
        switch self {
        case .select: return "S"
        case .line: return "L"
        case .circle: return "C"
        case .arc: return "A"
        case .rectangle: return "R"
        case .polyline: return "P"
        case .spline: return "N"
        case .hatch: return "H"
        case .trim: return "T"
        case .extend: return "E"
        case .fillet: return "F"
        case .offset: return "J"
        case .explode: return "X"
        case .editPoints: return "V"
        case .join: return "G"
        case .powerTrim: return "W"
        case .move: return "M"
        case .copy: return "K"
        case .rotate: return "O"
        case .scale: return "B"
        case .mirror: return "I"
        case .dimLinear: return "D"
        case .text: return "U"
        case .ellipse: return "Q"
        case .measure: return "Z"
        case .xline: return "Y"
        // second layer: Shift + the letter of a related tool
        case .chamfer: return "⇧F"
        case .polygon: return "⇧C"
        case .breakObject: return "⇧T"
        case .breakAtPoint: return "⇧E"
        case .revisionCloud: return "⇧R"
        case .wall: return "⇧L"
        case .wallFromCurve: return "⇧P"
        case .wipeout: return "⇧W"
        case .filter: return "⇧S"
        case .image: return "⇧I"
        case .roomLabel: return "⇧U"
        case .scaleBar: return "⇧B"
        case .northArrow: return "⇧N"
        default: return nil
        }
    }

    var group: ToolGroup {
        switch self {
        case .select, .line, .xline, .circle, .arc, .ellipse, .polygon, .rectangle, .polyline, .spline, .hatch, .hatchRebuild, .hatchCut: return .draw
        case .wall, .wallFromCurve: return .architecture
        case .trim, .extend, .fillet, .chamfer, .powerTrim, .breakObject, .breakAtPoint, .offset, .explode, .join, .editPoints, .matchProperties, .filter: return .modify
        case .move, .copy, .rotate, .scale, .mirror, .stretch, .array: return .transform
        case .dimLinear, .dimAligned, .dimContinue, .dimAngular, .dimRadius, .dimDiameter, .leader, .text, .roomLabel, .measure, .revisionCloud, .wipeout, .scaleBar, .northArrow: return .dimension
        case .blockCreate, .blockInsert, .xref, .image: return .insert
        case .zoomIn, .zoomOut, .zoomExtents, .zoomSelected, .zoomWindow: return .view
        }
    }

    /// Temporarily hidden tools – not in the panel, menus or shortcuts (the code stays, they are easy to bring back).
    static let hiddenTools: Set<DrawingTool> = [.stretch]

    /// Tools combined into one button on the panel – holding it (or right-clicking) picks the kind.
    /// The button shows the most recently used tool; shortcuts and the Tools menu work for each one separately.
    static let paletteFamilies: [[DrawingTool]] = [[.circle, .ellipse, .polygon], [.powerTrim, .trim, .extend, .breakObject, .breakAtPoint],
                                                    [.fillet, .chamfer], [.dimLinear, .dimAligned, .dimContinue, .dimAngular, .dimRadius, .dimDiameter],
                                                    [.revisionCloud, .wipeout], [.scaleBar, .northArrow]]

    var paletteFamily: [DrawingTool]? {
        return DrawingTool.paletteFamilies.first { $0.contains(self) }
    }

    /// The tool under whose button this one sits on the panel.
    var paletteLeader: DrawingTool {
        return paletteFamily?.first ?? self
    }

    /// Tools offered to the user.
    static var availableTools: [DrawingTool] {
        return allCases.filter { !hiddenTools.contains($0) }
    }

    static func tools(in group: ToolGroup) -> [DrawingTool] {
        return availableTools.filter { $0.group == group }
    }

    /// Title for menus: “…” for a tool that opens a dialog first, then the shortcut.
    var menuTitle: String {
        let name = [.filter, .xref, .image].contains(self) ? title + "…" : title
        if let shortcut = shortcut { return "\(name)  (\(shortcut))" }
        return name
    }

    /// How many points the tool needs (nil = any number, finished with Enter).
    var requiredPoints: Int? {
        switch self {
        case .line, .circle, .polygon, .rectangle: return 2
        case .arc, .ellipse, .dimLinear, .dimAligned: return 3
        case .dimAngular: return 4
        case .move, .copy, .rotate, .mirror, .stretch: return 2
        case .scale: return 3      // base point, grip, new grip position
        case .array: return 1      // center (for a polar array)
        case .blockCreate, .blockInsert, .xref, .scaleBar, .northArrow, .image: return 1      // base / insertion point
        case .polyline, .spline, .wall, .leader, .xline, .revisionCloud, .wipeout: return nil
        default: return 0
        }
    }

    var isTransform: Bool { return group == .transform }

    /// View commands – they don't switch the tool, only change the zoom (the running tool continues).
    static let viewCommands: [DrawingTool] = [.zoomIn, .zoomOut, .zoomExtents, .zoomSelected, .zoomWindow]

    /// Tools that work on the selected objects and finish immediately (Explode, Join, hatch edits).
    static let selectionCommands: [DrawingTool] = [.explode, .join, .hatchRebuild, .hatchCut]
}

// MARK: - Arc Methods

/// Arc construction methods (as in AutoCAD).
enum ArcMethod: Int, CaseIterable {
    case threePoint, startCenterEnd, startCenterAngle, centerStartEnd, centerStartAngle
    case startEndRadius, startEndAngle

    var title: String {
        switch self {
        case .threePoint: return "3 Points"
        case .startCenterEnd: return "Start, Center, End"
        case .startCenterAngle: return "Start, Center, Angle"
        case .centerStartEnd: return "Center, Start, End"
        case .centerStartAngle: return "Center, Start, Angle"
        case .startEndRadius: return "Start, End, Radius"
        case .startEndAngle: return "Start, End, Angle"
        }
    }

    /// Description for the menu.
    var detail: String {
        switch self {
        case .threePoint: return "Start point, any point on the arc, end point"
        case .startCenterEnd: return "Start point, center, end point (counter-clockwise)"
        case .startCenterAngle: return "Start point, center, included angle"
        case .centerStartEnd: return "Center, start point (sets the radius), end point"
        case .centerStartAngle: return "Center, start point (sets the radius), included angle"
        case .startEndRadius: return "Start and end point, then the radius"
        case .startEndAngle: return "Start and end point, then the included angle"
        }
    }

    /// Prompts for the individual steps.
    var prompts: [String] {
        switch self {
        case .threePoint:
            return ["start point", "second point on the arc", "end point"]
        case .startCenterEnd:
            return ["start point", "center", "end point (counter-clockwise)"]
        case .startCenterAngle:
            return ["start point", "center", "included angle (counter-clockwise, type ° or click)"]
        case .centerStartEnd:
            return ["center", "start point (sets the radius)", "end point (counter-clockwise)"]
        case .centerStartAngle:
            return ["center", "start point (sets the radius)", "included angle (counter-clockwise, type ° or click)"]
        case .startEndRadius:
            return ["start point", "end point", "radius (type it, or click – the arc bulges toward the cursor)"]
        case .startEndAngle:
            return ["start point", "end point", "included angle (type it, or click – the arc bulges toward the cursor)"]
        }
    }

    /// Is the second given point the center (and the first one the start)?
    var startFirst: Bool { return self == .startCenterEnd || self == .startCenterAngle }
    /// The center is clicked before the end (so Shift can step the end around it).
    var knowsCenter: Bool { return [.startCenterEnd, .startCenterAngle, .centerStartEnd, .centerStartAngle].contains(self) }
    /// Is the third point a point on the arc (three-point arc)?
    var usesThirdPointOnArc: Bool { return self == .threePoint || self == .startEndRadius || self == .startEndAngle }
}

// MARK: - CAD Editor View

final class CADEditorView: NSView, NSTextFieldDelegate {

    private enum Stage {
        case points          // entering points
        case selectObjects   // selecting objects for a transform
        case selectEdges     // selecting cutting edges / boundaries (Trim, Extend)
        case pickTargets     // clicking objects to edit
        case window          // Stretch: a window over the points that will move
    }

    var document: CADDocument?
    var layerManager: LayerManager?
    var selectionManager: SelectionManager?
    let viewport = Viewport()
    let gridRenderer = GridRenderer()
    let snapManager = SnapManager()
    /// SNAP TRACKING: snap points tracked by hovering – the cursor lines up with them.
    let snapTracker = SnapTracker()
    var snapTrackingEnabled: Bool {
        get { return snapTracker.enabled }
        set { snapTracker.enabled = newValue; needsDisplay = true; onModesChanged?() }
    }

    var currentTool: DrawingTool = .select {
        didSet {
            if oldValue != currentTool { selectedPoints.removeAll() }
            if currentTool != .select { lastTool = currentTool }
            resetToolState()
            // Explode / Join with already selected objects runs immediately – except when repeated with Enter / right click,
            // when it waits for confirmation (so the command doesn't accidentally run on the result of the previous step)
            if DrawingTool.selectionCommands.contains(currentTool), !(selectionManager?.isEmpty ?? true), !repeatingTool {
                DispatchQueue.main.async { [weak self] in self?.runSelectionCommand() }
            }
        }
    }

    var snapEnabled = true {
        didSet { activeSnap = nil; needsDisplay = true; onModesChanged?() }
    }

    /// GRID: points snap to the grid with step `gridSize`.
    var gridSnapEnabled = false {
        didSet { gridRenderer.snapActive = gridSnapEnabled; needsDisplay = true; onModesChanged?() }
    }
    /// Grid step (in drawing units) – both the drawn grid and snapping.
    var gridSize: CGFloat = 10 {
        didSet { gridRenderer.gridSpacing = gridSize; needsDisplay = true; onModesChanged?() }
    }
    /// The background grid is visible (saved in the drawing).
    var showGrid = true {
        didSet { gridRenderer.showGrid = showGrid; needsDisplay = true; onModesChanged?() }
    }
    /// The colored X/Y axes of the drawing coordinates are visible (saved in the drawing).
    var showAxes = true {
        didSet { gridRenderer.showAxes = showAxes; needsDisplay = true; onModesChanged?() }
    }
    /// POLAR: the direction from the previous point snaps in `polarIncrement` degree steps.
    var polarEnabled = false {
        didSet { needsDisplay = true; onModesChanged?() }
    }
    var polarIncrement: CGFloat = 15 {
        didSet { onModesChanged?() }
    }
    /// Drawing coordinate units (affect the line scale, lineweights and plotting).
    var drawingUnits: DrawingUnits = .mm {
        didSet { needsDisplay = true; onModesChanged?() }
    }

    /// How many drawing units correspond to 1 mm on paper (scale and units combined).
    var unitsPerPaperMM: CGFloat {
        return drawingScale.factor / drawingUnits.mmPerUnit
    }

    /// Scale converted to drawing units (for plotting).
    var effectiveDrawingScale: DrawingScale {
        return DrawingScale(paper: drawingScale.paper * drawingUnits.mmPerUnit, model: drawingScale.model)
    }

    var orthoEnabled = false {
        didSet { needsDisplay = true; onModesChanged?() }
    }

    // MARK: Drawing coordinates (rotated, UCS)
    //
    // Ortho, polar angles, the grid, entered coordinates and angles, rectangles, horizontal/vertical dimensions
    // and new text follow the rotated axes. Objects in the drawing stay in world coordinates.

    /// Rotation of the X/Y axes of the drawing coordinates (radians, counterclockwise).
    var ucsAngle: CGFloat = 0 {
        didSet { ucsChanged() }
    }
    /// Origin of the drawing coordinates in the drawing.
    var ucsOrigin: CGPoint = .zero {
        didSet { ucsChanged() }
    }
    var isUCSRotated: Bool { return abs(ucsAngle) > 1e-12 || ucsOrigin != .zero }

    /// From drawing coordinates to the drawing.
    var ucsToWorld: CGAffineTransform {
        return CGAffineTransform(rotationAngle: ucsAngle).concatenating(CGAffineTransform(translationX: ucsOrigin.x, y: ucsOrigin.y))
    }

    func toUCS(_ p: CGPoint) -> CGPoint { return p.applying(ucsToWorld.inverted()) }
    func fromUCS(_ p: CGPoint) -> CGPoint { return p.applying(ucsToWorld) }

    private func ucsChanged() {
        gridRenderer.ucsToWorld = ucsToWorld
        updateCrosshairAngle()
        needsDisplay = true
        onModesChanged?()
    }

    /// Direction of a vector in drawing coordinates.
    private func toUCSVector(_ d: CGPoint) -> CGPoint {
        return d.applying(CGAffineTransform(rotationAngle: -ucsAngle))
    }

    private func fromUCSVector(_ d: CGPoint) -> CGPoint {
        return d.applying(CGAffineTransform(rotationAngle: ucsAngle))
    }

    /// The point on the nearest grid node (the grid lies in drawing coordinates).
    private func snappedToGrid(_ p: CGPoint) -> CGPoint {
        let u = toUCS(p)
        return fromUCS(CGPoint(x: (u.x / gridSize).rounded() * gridSize, y: (u.y / gridSize).rounded() * gridSize))
    }

    /// Cursor (crosshair) rotated by the drawing coordinate axes on screen.
    private func updateCrosshairAngle() {
        let t = viewport.getTransform()
        let angle = atan2(t.b * cos(ucsAngle) + t.d * sin(ucsAngle), t.a * cos(ucsAngle) + t.c * sin(ucsAngle))
        if abs(crosshair.angle - angle) > 1e-9 { crosshair.angle = angle }
    }

    /// Value box at the cursor: true = always visible, false = appears once you start typing a number
    /// (F12, ⌥6, View › Drawing Aids › Value Box Always Visible, Settings). Typing values always works.
    var valueBoxAlways = AppSettings.valueBoxAlways {
        didSet {
            AppSettings.valueBoxAlways = valueBoxAlways
            updateDynamicInput()
            onPromptChanged?(prompt)
            onModesChanged?()
        }
    }

    /// The box is visible because it is being typed into right now (even if it is otherwise hidden).
    private var valueBoxRequested = false

    // MARK: Hatch – settings

    var hatchPattern: HatchPattern = .lines {
        didSet { onPromptChanged?(prompt) }
    }
    /// Pattern rotation in degrees (0 = as the pattern is defined).
    var hatchAngle: CGFloat = 0 {
        didSet { onPromptChanged?(prompt) }
    }
    /// Pattern scale (nil = from the drawing scale, e.g. 1:50 → 50).
    var hatchScale: CGFloat? {
        didSet { onPromptChanged?(prompt) }
    }

    var currentHatchAngle: CGFloat { return hatchAngle }

    var currentHatchScale: CGFloat { return hatchScale ?? unitsPerPaperMM }

    /// Rounding to a “nice” number of the 1–2–2.5–5–10 series.
    static func niceValue(_ raw: CGFloat) -> CGFloat {
        guard raw > 0, raw.isFinite else { return 1 }
        let magnitude = pow(10, floor(log10(raw)))
        for step in [1, 2, 2.5, 5, 10] as [CGFloat] where step * magnitude >= raw {
            return step * magnitude
        }
        return raw
    }

    private var hatchFinder: HatchRegionFinder?
    private var hatchFinderKey = ""
    /// Outline of the room under the cursor (Room Label) and the finder of room outlines (rebuilt when the drawing changes).
    private var roomHover: [CGPoint]?
    private var roomFinder: HatchRegionFinder?
    private var roomFinderKey = ""
    private var hatchHoverLoops: [[CGPoint]]?

    /// LWT: display lineweights.
    var showLineWeights = false {
        didSet { needsDisplay = true; onModesChanged?() }
    }

    /// true = fixed lineweight on screen, false = true to scale (changes with zoom).
    var lineWeightOnScreen = false {
        didSet { needsDisplay = true; onModesChanged?() }
    }

    /// Drawing scale (paper : model) – affects the displayed lineweights.
    var drawingScale = DrawingScale(paper: 1, model: 1) {
        didSet { needsDisplay = true; onModesChanged?() }
    }

    /// LINECONT: lines continue – each next one starts at the end of the previous one (separate lines are created).
    /// Can be toggled while drawing too: turning it on lets the line in progress continue, turning it off ends the chain
    /// after the line currently being drawn (the point in progress stays).
    var lineContinue = false {
        didSet {
            if !lineContinue {
                lineChainStart = nil
                lineChainCount = 0
            }
            if currentTool == .line { stateChanged() } else { onPromptChanged?(prompt) }
            onModesChanged?()
        }
    }

    /// Ask when finishing a polyline / spline whether to close it.
    var askToClose = true {
        didSet { onModesChanged?() }
    }

    var arcMethod: ArcMethod = .threePoint {
        didSet { if currentTool == .arc { resetToolState() } }
    }

    var filletRadius: CGFloat = 10
    /// Chamfer: distance from the corner on the first and the second object.
    var chamferFirst: CGFloat = 10
    var chamferSecond: CGFloat = 10

    // MARK: Blocks

    /// The drawing's blocks and external references (of the tab).
    var blockLibrary: BlockLibrary?
    /// The block inserted by the Insert Block tool (for External Reference the reference just attached).
    var insertDefinition: BlockDefinition? {
        didSet { if [.blockInsert, .xref].contains(currentTool) { onPromptChanged?(prompt); needsDisplay = true } }
    }
    /// After a block is created / changed (the block menu is refreshed).
    var onBlocksChanged: (() -> Void)?

    /// Array kind.
    var arrayKind: ArrayKind = .rectangular {
        didSet { if currentTool == .array { resetToolState() } }
    }
    private var arraySettings = ArraySettings()
    /// Preview of the array copies while the dialog is open.
    private var arrayPreview: [CADEntity] = [] {
        didSet { needsDisplay = true }
    }

    /// What the Measure tool measures.
    var measureKind: MeasureKind = .distance {
        didSet { if currentTool == .measure { resetToolState() } }
    }

    // MARK: Connection to the controller

    var onViewChanged: (() -> Void)?
    var onCursorMoved: ((CGPoint) -> Void)?
    /// Document change: removed and added entities + the action name for Undo.
    var onCommit: ((_ removed: [CADEntity], _ added: [CADEntity], _ actionName: String) -> Void)?
    var onDeleteRequested: (() -> Void)?
    /// Middle-button double-click – Zoom Extents (as in AutoCAD).
    var onZoomExtentsRequested: (() -> Void)?
    var onToolChangeRequested: ((DrawingTool) -> Void)?
    var onPromptChanged: ((String) -> Void)?
    var onMessage: ((String) -> Void)?
    /// The drawing's context menu (Cut, Copy, Paste, Draw Order…) – right button held, or Control-click.
    var onContextMenuRequested: (() -> NSMenu?)?
    /// Snap / Ortho / dynamic input change (for the status line).
    var onModesChanged: (() -> Void)?
    // MARK: Text

    /// The most recently used tool – Enter or right click while idle runs it again (as in AutoCAD).
    private(set) var lastTool: DrawingTool?

    /// Repeat the last tool? Only in the Select tool when nothing is running (otherwise Enter / right click confirm).
    private func repeatLastTool() -> Bool {
        guard AppSettings.repeatLastTool, currentTool == .select, !isBusy, pickRequest == nil, inlineText == nil, viewportPan == nil,
              let tool = lastTool, tool != .select else { return false }
        repeatingTool = true
        onToolChangeRequested?(tool)
        repeatingTool = false
        if DrawingTool.selectionCommands.contains(tool) {
            onMessage?("Repeat: \(tool.title) – select objects (or keep the selection) and press ↩ to run it")
        } else {
            onMessage?("Repeat: \(tool.title)")
        }
        return true
    }

    /// The tool is being started by a repeat right now (commands on the selection then don't run by themselves).
    private var repeatingTool = false

    /// Kind of text being inserted (menu of the Text tool).
    var textKind: TextKind = .simple {
        didSet { if currentTool == .text { resetToolState() } }
    }
    /// Default font, style and height of new text.
    var textStyle = TextStyleDefaults.load() {
        didSet { textStyle.save() }
    }
    /// Height of new text in world units (from the paper height and the scale).
    var newTextHeight: CGFloat {
        return max(textStyle.heightMM, 0.1) * unitsPerPaperMM
    }
    var onEditText: ((TextEntity) -> Void)?

    /// Text being typed directly on the canvas: field, gear, format and possibly the text being edited.
    private final class InlineTextSession {
        let field: NSTextField
        let gear: NSButton
        var anchor: CGPoint
        var format: TextFormat
        let editing: TextEntity?
        var popover: NSPopover?

        init(field: NSTextField, gear: NSButton, anchor: CGPoint, format: TextFormat, editing: TextEntity?) {
            self.field = field
            self.gear = gear
            self.anchor = anchor
            self.format = format
            self.editing = editing
        }
    }
    private var inlineText: InlineTextSession?
    /// First corner of the paragraph text frame.
    private var textBoxStart: CGPoint?

    /// Is text currently being typed on the canvas? (⌥+digit shortcuts are not used then.)
    var isEditingText: Bool { return inlineText != nil }

    /// Format of new text from the default style.
    private var defaultTextFormat: TextFormat {
        return TextFormat(family: textStyle.family, face: textStyle.face, height: newTextHeight,
                          rotationDegrees: Geometry.normalizeAngle(ucsAngle) * 180 / .pi,
                          justify: textStyle.justify, underline: textStyle.underline, boxWidth: nil, lineSpacing: 1)
    }

    /// New text from the default style.
    func makeText(_ value: String, at point: CGPoint, boxWidth: CGFloat? = nil) -> TextEntity {
        let entity = TextEntity(position: point, text: value, height: newTextHeight, layer: currentLayerName)
        var format = defaultTextFormat
        format.boxWidth = boxWidth
        entity.apply(format)
        return entity
    }

    /// Typing directly on the canvas. `editing` = editing an existing text, `showFormat` = open the edit panel right away.
    private func beginInlineText(at point: CGPoint, format: TextFormat, editing: TextEntity? = nil, showFormat: Bool = false) {
        commitInlineText()
        let field = NSTextField(frame: .zero)
        field.textColor = layerManager?.getLayer(editing?.layer ?? currentLayerName)?.color ?? .white
        if let color = editing?.color { field.textColor = color }
        field.backgroundColor = Theme.inlineTextBackground
        field.drawsBackground = true
        field.isBordered = true
        field.focusRingType = .none
        field.placeholderString = "Type the text · ↩ = place · ⌥↩ = new line · Esc = cancel"
        field.usesSingleLineMode = false
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.cell?.sendsActionOnEndEditing = false
        field.lineBreakMode = .byWordWrapping
        field.stringValue = editing?.text ?? ""
        field.delegate = self
        field.target = self
        field.action = #selector(inlineTextEntered(_:))

        // menu (☰): edit font, style, height, rotation… (turns plain text into formatted text)
        let gear = NSButton(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        gear.bezelStyle = .regularSquare
        gear.isBordered = false
        gear.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: "Text format")
        gear.contentTintColor = Theme.iconLight
        gear.wantsLayer = true
        gear.layer?.backgroundColor = Theme.inlineTextButton.cgColor
        gear.layer?.cornerRadius = 5
        gear.toolTip = "Text format – font, typeface, height, rotation, alignment, width"
        gear.target = self
        gear.action = #selector(inlineGearClicked(_:))

        addSubview(field)
        addSubview(gear)
        inlineText = InlineTextSession(field: field, gear: gear, anchor: point, format: format, editing: editing)
        applyInlineFormat()
        window?.makeFirstResponder(field)
        if let editor = field.currentEditor() { editor.selectedRange = NSRange(location: field.stringValue.count, length: 0) }
        stateChanged()
        if showFormat { DispatchQueue.main.async { [weak self] in self?.showInlineFormatPanel() } }
    }

    /// Font size in the field (points) and the field scale: points per drawing unit.
    /// The font in the field is always readable (12–28 points) and the paragraph width is converted by the same scale,
    /// so lines wrap the same way as in the finished text – regardless of zoom.
    private func inlineMetrics(_ format: TextFormat) -> (size: CGFloat, pointsPerUnit: CGFloat) {
        let em = max(format.height, 1e-9) / FontLibrary.capRatio(family: format.family, face: format.face)
        let onScreen = em * viewport.getCurrentZoom()
        let size = min(max(onScreen.isFinite ? onScreen : 13, 12), 28)
        return (size, size / em)
    }

    /// Field font and size from the format (a preview; rotation shows only after inserting).
    private func applyInlineFormat() {
        guard let session = inlineText else { return }
        let metrics = inlineMetrics(session.format)
        let font = FontLibrary.font(family: session.format.family, face: session.format.face, size: metrics.size)
        if session.field.font != font { session.field.font = font }
        session.field.alignment = session.format.justify.nsAlignment
        positionInlineText()
        needsDisplay = true
    }

    /// The text field stays at the insertion point even when panning and zooming; its height grows with the number of lines.
    private func positionInlineText() {
        guard let session = inlineText, let font = session.field.font else { return }
        let screen = viewport.worldToScreen(session.anchor)
        let k = inlineMetrics(session.format).pointsPerUnit
        // inner margins of the field (frame + text inset) – the text then wraps at the paragraph width
        let inset: CGFloat = 10
        let text = session.field.stringValue
        let longest = text.components(separatedBy: "\n")
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // the paragraph wraps in the field the same way as the finished text: at the paragraph width before the font is condensed
        // and the longest word stretches the paragraph (a word is never split)
        let widthFactor = max(session.editing?.widthFactor ?? 1, 0.05)
        var wrapWidth: CGFloat? = session.format.boxWidth.map { box in
            let longestWord = text.components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
            return max(box * k / widthFactor, ceil(longestWord * 1.03 + 2), 40)
        }
        // a paragraph wider than the area (from DXF it can be thousands of units): short text does not wrap in it anyway –
        // the field is only as wide as the text needs; long text wraps at the area width
        let available = max(240, bounds.width - 60)
        if let wrap = wrapWidth, wrap > available {
            wrapWidth = longest + font.pointSize * 2 <= available ? nil : available - inset
        }
        let width = wrapWidth.map { $0 + inset } ?? max(240, longest + font.pointSize * 2 + inset)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let lines = max(1, text.components(separatedBy: "\n").count)
        var textHeight = lineHeight * CGFloat(lines)
        if let wrap = wrapWidth {
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: wrap, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
            textHeight = max(textHeight, ceil(rect.height))
        }
        // a long paragraph doesn't fit – the field stops at the bottom edge of the area
        let height = min(textHeight + 6, max(bounds.height - 16, 40))
        var x = screen.x - 3
        switch session.format.justify {
        case .left: break
        case .center: x = screen.x - width / 2
        case .right: x = screen.x - width + 3
        }
        // baseline of the first line at the insertion point, further lines down
        let top = screen.y + font.ascender + 3
        session.field.frame = NSRect(x: x, y: top - height, width: width, height: height)
        session.gear.frame = NSRect(x: session.field.frame.maxX + 4, y: top - 22, width: 22, height: 22)
    }

    @objc private func inlineGearClicked(_ sender: NSButton) {
        if let popover = inlineText?.popover, popover.isShown {
            popover.performClose(nil)
        } else {
            showInlineFormatPanel()
        }
    }

    private func showInlineFormatPanel() {
        guard let session = inlineText else { return }
        let panel = TextFormatPanel(format: session.format, unitName: drawingUnits.suffix)
        panel.onChange = { [weak self] format in
            guard let self = self, let session = self.inlineText else { return }
            session.format = format
            self.applyInlineFormat()
        }
        let popover = NSPopover()
        popover.contentViewController = panel
        popover.behavior = .semitransient
        popover.appearance = NSAppearance(named: .darkAqua)
        session.popover = popover
        popover.show(relativeTo: session.gear.bounds, of: session.gear, preferredEdge: .maxX)
    }

    @objc private func inlineTextEntered(_ sender: NSTextField) {
        commitInlineText()
        window?.makeFirstResponder(self)
    }

    private func closeInlineSession(_ session: InlineTextSession) {
        session.popover?.close()
        session.field.removeFromSuperview()
        session.gear.removeFromSuperview()
    }

    private func commitInlineText() {
        guard let session = inlineText else { return }
        // finish a composing character (dead key – háček, acute accent…) and take exactly what is in the field
        var raw = session.field.stringValue
        if let editor = session.field.currentEditor() as? NSTextView {
            if editor.hasMarkedText() { editor.unmarkText() }
            raw = editor.string
        }
        inlineText = nil
        let value = raw.trimmingCharacters(in: .newlines)
        closeInlineSession(session)
        let empty = value.trimmingCharacters(in: .whitespaces).isEmpty
        if let original = session.editing {
            if empty {
                onCommit?([original], [], "Delete Text")
            } else if value != original.text || session.format != original.format,
                      let copy = original.clone() as? TextEntity {
                copy.text = value
                copy.apply(session.format)
                onCommit?([original], [copy], "Change Text")
                selectionManager?.select([copy])
            }
        } else if !empty {
            let entity = TextEntity(position: session.anchor, text: value, height: session.format.height, layer: currentLayerName)
            entity.apply(session.format)
            onCommit?([], [entity], "Add Text")
        }
        stateChanged()
    }

    private func cancelInlineText() {
        guard let session = inlineText else { return }
        inlineText = nil
        closeInlineSession(session)
        window?.makeFirstResponder(self)
        needsDisplay = true
        stateChanged()
    }

    /// Editing an existing text directly on the canvas (double-click, Properties).
    func beginEditing(_ text: TextEntity) {
        guard document?.contains(text) ?? false, !(layerManager?.isLayerLocked(text.layer) ?? false) else {
            NSSound.beep()
            return
        }
        cancelCurrentOperation()
        beginInlineText(at: text.position, format: text.format, editing: text)
    }

    /// Click with the Text tool.
    private func textClick(at point: CGPoint) {
        switch textKind {
        case .simple:
            beginInlineText(at: point, format: defaultTextFormat)
        case .formatted:
            beginInlineText(at: point, format: defaultTextFormat, showFormat: true)
        case .multiline:
            if let first = textBoxStart {
                finishTextBox(from: first, to: point)
            } else {
                textBoxStart = point
                currentWorldPoint = point
                stateChanged()
            }
        }
    }

    private func finishTextBox(from a: CGPoint, to b: CGPoint) {
        textBoxStart = nil
        let width = abs(b.x - a.x)
        guard width > newTextHeight else {
            onMessage?("The box is too narrow – drag it at least a few letters wide.")
            stateChanged()
            return
        }
        // insertion point = baseline of the first line below the top edge of the frame
        let top = max(a.y, b.y)
        let left = min(a.x, b.x)
        let x: CGFloat
        switch textStyle.justify {
        case .left: x = left
        case .center: x = left + width / 2
        case .right: x = left + width
        }
        var format = defaultTextFormat
        format.boxWidth = width
        beginInlineText(at: CGPoint(x: x, y: top - newTextHeight), format: format)
    }

    private func drawTextBoxPreview(in context: CGContext, transform: CGAffineTransform) {
        guard currentTool == .text, let first = textBoxStart, let current = currentWorldPoint else { return }
        let a = first.applying(transform), b = current.applying(transform)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        context.saveGState()
        context.setStrokeColor(NSColor.systemTeal.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [5, 3])
        context.stroke(rect)
        // placeholder lines
        let lineHeight = max(newTextHeight * viewport.getCurrentZoom() * 1.3, 4)
        var y = rect.maxY - lineHeight
        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(NSColor.systemTeal.withAlphaComponent(0.4).cgColor)
        var count = 0
        while y > rect.minY && count < 30 {
            context.move(to: CGPoint(x: rect.minX + 4, y: y))
            context.addLine(to: CGPoint(x: rect.maxX - 4, y: y))
            y -= lineHeight
            count += 1
        }
        context.strokePath()
        context.restoreGState()
    }

    /// Hatch pattern shortcut (Settings › Shortcuts): the Hatch tool with this pattern.
    var onHatchShortcut: ((String) -> Void)?

    // MARK: Cursor – CAD crosshair

    private let crosshair = CrosshairView(frame: .zero)
    /// Floating tool palettes lie on top of the drawing; over them the crosshair hides.
    let paletteLayer = FloatingPaletteLayer(frame: .zero)
    private static let invisibleCursor = NSCursor(image: NSImage(size: NSSize(width: 1, height: 1)), hotSpot: .zero)

    /// Cursor over the area (the system crosshair, or invisible – the crosshair is drawn by CrosshairView).
    private var drawingCursor: NSCursor {
        return AppSettings.cadCrosshair ? CADEditorView.invisibleCursor : .crosshair
    }

    /// After a change in Settings › Cursor.
    func applyCursorSettings() {
        crosshair.isHidden = !AppSettings.cadCrosshair
        crosshair.needsLayout = true
        crosshair.updateAppearance()
        window?.invalidateCursorRects(for: self)
        drawingCursor.set()
    }

    private func moveCrosshair(_ event: NSEvent?) {
        guard AppSettings.cadCrosshair else { return }
        crosshair.point = event.map { convert($0.locationInWindow, from: nil) }
    }

    /// Double-click on a layout viewport (Select) – opens the model in its area.
    var onViewportDoubleClick: ((ViewportEntity) -> Void)?

    // MARK: Layout sheet

    /// Drawing on a layout: paper in mm and viewports into the model. nil = model space.
    struct PaperSpace {
        let paperRect: CGRect
        let printableRect: CGRect
        /// Model entities (for the viewport content).
        let model: () -> [CADEntity]
        /// mm per model unit.
        let modelMMPerUnit: CGFloat
    }

    var paperSpace: PaperSpace? {
        didSet { viewportPan = nil; needsDisplay = true }
    }

    // MARK: In-place block editing

    /// A block is being edited: the surrounding drawing is dimmed in the background (can be snapped to, not selected),
    /// the block's base point is marked.
    struct BlockEditContext {
        let name: String
        /// Surrounding objects (in drawing coordinates) – only for display and snapping.
        let background: [CADEntity]
        /// The block's base point (in the drawing).
        let basePoint: CGPoint
    }

    var blockEditContext: BlockEditContext? {
        didSet {
            blockBackgroundBoxes = blockEditContext?.background.map { $0.boundingBox() } ?? []
            renderEpoch &+= 1
            needsDisplay = true
        }
    }

    private var blockBackgroundBoxes: [CGRect] = []

    /// Double-click on a block (Select tool) – start editing it.
    var onBlockEditRequested: ((BlockReference) -> Void)?

    /// Background objects near a point (for snapping).
    private func blockBackgroundNear(_ point: CGPoint, tolerance: CGFloat) -> [CADEntity] {
        guard let edit = blockEditContext, !edit.background.isEmpty else { return [] }
        let rect = CGRect(x: point.x - tolerance, y: point.y - tolerance, width: 2 * tolerance, height: 2 * tolerance)
        var result: [CADEntity] = []
        for (index, entity) in edit.background.enumerated()
        where index < blockBackgroundBoxes.count && CADEditorView.overlaps(blockBackgroundBoxes[index], rect) {
            if let layers = layerManager, !layers.isLayerVisible(entity.layer) { continue }
            result.append(entity)
        }
        return result
    }

    private func drawBlockEditBackground(in context: CGContext, transform: CGAffineTransform, visibleWorld: CGRect) {
        guard let edit = blockEditContext, !edit.background.isEmpty else { return }
        BlockReference.highlightDrawing = true
        defer { BlockReference.highlightDrawing = false }
        for (index, entity) in edit.background.enumerated() {
            guard index < blockBackgroundBoxes.count,
                  CADEditorView.overlaps(blockBackgroundBoxes[index], visibleWorld) else { continue }
            if let layers = layerManager, !layers.isLayerVisible(entity.layer) { continue }
            var s = style(for: entity)
            // dimmed – the block being edited is the only bright thing
            s.color = s.color.blended(withFraction: 0.72, of: backgroundColor) ?? s.color
            entity.draw(in: context, transform: transform, style: s)
        }
    }

    /// Base point of the block being edited: a ring with a cross and a label.
    private func drawBlockBasePoint(in context: CGContext, transform: CGAffineTransform) {
        guard let edit = blockEditContext else { return }
        let p = edit.basePoint.applying(transform)
        guard p.x.isFinite, p.y.isFinite else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.systemPurple.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: CGRect(x: p.x - 6, y: p.y - 6, width: 12, height: 12))
        context.move(to: CGPoint(x: p.x - 10, y: p.y)); context.addLine(to: CGPoint(x: p.x + 10, y: p.y))
        context.move(to: CGPoint(x: p.x, y: p.y - 10)); context.addLine(to: CGPoint(x: p.x, y: p.y + 10))
        context.strokePath()
        context.restoreGState()
        ("base point" as NSString).draw(at: CGPoint(x: p.x + 9, y: p.y + 7),
                                        withAttributes: [.font: NSFont.systemFont(ofSize: 10),
                                                         .foregroundColor: NSColor.systemPurple])
    }

    /// Panning the viewport content with the mouse (⌥-drag): viewport, start point (screen) and temporary model center.
    private var viewportPan: (viewport: ViewportEntity, start: CGPoint, center: CGPoint)?

    /// Zooms to the whole paper of the layout.
    func zoomToPaper() {
        guard let paper = paperSpace else { return }
        let frame = Line(start: CGPoint(x: paper.paperRect.minX, y: paper.paperRect.minY),
                         end: CGPoint(x: paper.paperRect.maxX, y: paper.paperRect.maxY))
        viewport.zoomToFit(entities: [frame])
    }

    /// Selecting a rectangle with two clicks (plot area, new viewport). Esc = cancel (completion(nil)).
    private var pickRequest: (prompt: String, first: CGPoint?, completion: (CGRect?) -> Void)?

    func pickRectangle(prompt: String, completion: @escaping (CGRect?) -> Void) {
        cancelCurrentOperation()
        pickRequest = (prompt, nil, completion)
        window?.makeFirstResponder(self)
        stateChanged()
    }

    private func cancelPick() {
        guard let request = pickRequest else { return }
        pickRequest = nil
        request.completion(nil)
    }

    // MARK: Paste (Edit › Paste)

    /// Pasted objects hang on the cursor by their base point until a click places them (Clipboard.swift).
    private var pasteRequest: (entities: [CADEntity], base: CGPoint, completion: (_ offset: CGPoint) -> Void)?

    /// Starts placing pasted objects (an operation in progress is canceled, the current tool stays selected).
    /// `completion` gets the shift from their original position.
    func beginPaste(_ entities: [CADEntity], completion: @escaping (_ offset: CGPoint) -> Void) {
        cancelCurrentOperation()
        pasteRequest = (entities, DrawingClipboard.basePoint(of: entities), completion)
        window?.makeFirstResponder(self)
        stateChanged()
    }

    private func finishPaste(at point: CGPoint) {
        guard let paste = pasteRequest else { return }
        pasteRequest = nil
        activeSnap = nil
        stateChanged()
        paste.completion(point - paste.base)
    }

    /// Preview of the pasted objects at the cursor (a very large paste only partly, with its outline).
    private func drawPastePreview(_ paste: (entities: [CADEntity], base: CGPoint, completion: (_ offset: CGPoint) -> Void),
                                  cursor: CGPoint, in context: CGContext, transform: CGAffineTransform) {
        let shifted = CGAffineTransform(translationX: cursor.x - paste.base.x, y: cursor.y - paste.base.y).concatenating(transform)
        let style = StrokeStyle(color: .systemGreen, lineWidth: 1, dash: [6, 4])
        let limit = 3000
        for entity in paste.entities.prefix(limit) {
            entity.draw(in: context, transform: shifted, style: style)
        }
        guard paste.entities.count > limit else { return }
        var box = CGRect.null
        for entity in paste.entities where DrawingSafety.isDrawable(entity.boundingBox()) { box = box.union(entity.boundingBox()) }
        let outline = box.applying(shifted)
        guard DrawingSafety.isDrawable(outline) else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.systemGreen.cgColor)
        context.setLineWidth(1)
        context.stroke(outline)
        context.restoreGState()
    }

    /// Point for rectangle selection: snapping to objects and the grid.
    private func pickPoint(for event: NSEvent) -> CGPoint {
        let screenPoint = convert(event.locationInWindow, from: nil)
        var point = viewport.screenToWorld(screenPoint)
        activeSnap = nil
        if snapEnabled, let snap = snapManager.findSnapPoint(near: point,
                                                             in: entitiesNear(point, tolerance: snapTolerance / viewport.getCurrentZoom())
                                                                + blockBackgroundNear(point, tolerance: snapTolerance / viewport.getCurrentZoom()),
                                                             tolerance: snapTolerance / viewport.getCurrentZoom()) {
            activeSnap = snap
            point = snap.point
        } else if gridSnapEnabled, gridSize > 0 {
            point = snappedToGrid(point)
        }
        return point
    }

    private func drawPick(in context: CGContext, transform: CGAffineTransform) {
        guard let first = pickRequest?.first, let current = currentWorldPoint else { return }
        let a = first.applying(transform), b = current.applying(transform)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
        context.saveGState()
        context.setFillColor(NSColor.systemTeal.withAlphaComponent(0.1).cgColor)
        context.fill(rect)
        context.setStrokeColor(NSColor.systemTeal.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [6, 3])
        context.stroke(rect)
        context.restoreGState()
    }

    /// The viewport under a paper point (topmost), only on a visible and unlocked layer.
    private func viewportAt(_ point: CGPoint) -> ViewportEntity? {
        return editableEntities.reversed().compactMap { $0 as? ViewportEntity }.first { $0.rect.contains(point) }
    }

    /// The layout's paper and the viewport content (below the objects on paper).
    private func drawPaper(in context: CGContext, transform: CGAffineTransform) {
        guard let paper = paperSpace else { return }
        context.setFillColor(Theme.paperSurround.cgColor)
        context.fill(bounds)
        let sheet = paper.paperRect.applying(transform)
        guard DrawingSafety.isDrawable(sheet) else { return }
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 12, color: NSColor.black.cgColor)
        context.setFillColor(backgroundColor.cgColor)
        context.fill(sheet)
        context.restoreGState()
        context.saveGState()
        context.setStrokeColor(Theme.paperBorder.cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.stroke(paper.printableRect.applying(transform))
        context.restoreGState()
    }

    private func drawViewportContents(in context: CGContext, transform: CGAffineTransform) {
        guard let paper = paperSpace, let layerManager = layerManager else { return }
        let viewports = visibleEntities.compactMap { $0 as? ViewportEntity }
        guard !viewports.isEmpty else { return }
        let model = paper.model()
        for viewport in viewports {
            let center = viewportPan?.viewport === viewport ? viewportPan?.center : nil
            ViewportDrawing.drawContents(of: viewport, center: center, model: model, layerManager: layerManager,
                                         mmPerUnit: paper.modelMMPerUnit, paperTransform: transform,
                                         in: context, printing: false) { self.style(for: $0) }
        }
    }

    // MARK: State

    private let backgroundColor = Theme.canvasBackground
    /// Click selection tolerance (px) – half of the pick box from Settings › Cursor.
    private var pickTolerance: CGFloat { return max(3, AppSettings.pickboxSize / 2 + 1) }
    private let snapTolerance: CGFloat = 12     // px

    private var stage: Stage = .points
    private var points: [CGPoint] = []
    private var picked: [(entity: CADEntity, click: CGPoint)] = []
    private var edges: [CADEntity] = []
    /// Box for numeric entry at the cursor.
    private let dynamicInput = DynamicInputView(frame: .zero)
    /// The “Close?” question when finishing a polyline / spline.
    private let closePrompt = ClosePromptView(frame: .zero)
    private var awaitingCloseAnswer = false
    /// Continuous lines (LINECONT): first point of the chain and the number of lines drawn.
    private var lineChainStart: CGPoint?
    private var lineChainCount = 0
    /// The last point under the cursor after snap/ortho, but before entered values are applied.
    private var lastRawPoint: CGPoint?

    private var isPanning = false
    private var lastPanPoint: CGPoint = .zero
    private var mouseDownScreenPoint: CGPoint?
    private var ignoreNextMouseUp = false
    private var currentWorldPoint: CGPoint?
    private var activeSnap: SnapPoint?
    private var shiftHeld = false

    private var selectionBoxStart: CGPoint? {   // screen
        didSet { if selectionBoxStart == nil { selectionBoxAwaitsCorner = false } }
    }
    private var selectionBoxEnd: CGPoint?
    /// The window was started with a click (not a drag) – the next click sets the opposite corner.
    private var selectionBoxAwaitsCorner = false
    private var selectionBoxAdditive = false

    private var fence: [CGPoint] = []           // screen (PowerTrim)

    /// Dragging selected objects in selection mode (as in AutoCAD): the base point.
    private var dragMoveBase: CGPoint?

    // MARK: Grips

    /// Reference to a single grip (object + grip index).
    private struct PointRef: Equatable {
        let id: UUID
        let index: Int
    }
    /// Marked points: Shift-click on grips in Select, the selection in the Edit Points tool.
    private var selectedPoints: [PointRef] = [] {
        didSet { needsDisplay = true }
    }

    /// Grip editing in progress: the points being moved and the start point of the move.
    private struct GripEdit {
        let items: [(entity: CADEntity, index: Int, point: CGPoint)]
        let base: CGPoint
        /// The press only selected a point – without dragging it is just selected, the move does not start.
        let justSelected: Bool
    }
    private var activeGrip: GripEdit?
    private var gripDragged = false
    private var hoverGrip: (id: UUID, index: Int)?
    /// Grips are drawn only for a reasonable number of selected objects.
    private let maxGripEntities = 60
    private let gripHitRadius: CGFloat = 7

    /// Preview under the cursor for Trim/Extend/PowerTrim: what disappears (red) and what is created (green).
    private var hoverRemoved: CADEntity?
    private var hoverAdded: [CADEntity] = []

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        crosshair.frame = bounds
        crosshair.autoresizingMask = [.width, .height]
        crosshair.isHidden = !AppSettings.cadCrosshair
        addSubview(crosshair)
        paletteLayer.frame = bounds
        paletteLayer.autoresizingMask = [.width, .height]
        addSubview(paletteLayer)
        dynamicInput.isHidden = true
        addSubview(dynamicInput)
        dynamicInput.onChange = { [weak self] in self?.dynamicInputChanged() }
        snapTracker.onChange = { [weak self] in self?.overlayRedraw() }
        dynamicInput.onCommit = { [weak self] in self?.commitDynamicInput() }
        dynamicInput.onCancel = { [weak self] in self?.cancelDynamicInput() }
        dynamicInput.onLetterCommand = { [weak self] letter in self?.handleInputLetter(letter) ?? false }
        closePrompt.isHidden = true
        addSubview(closePrompt)
        closePrompt.onAnswer = { [weak self] close in self?.answerClosePrompt(close) }
        closePrompt.onAskChanged = { [weak self] ask in self?.askToClose = ask }
        viewport.setViewSize(bounds.size)
        viewport.onViewChanged = { [weak self] in
            self?.updateCrosshairAngle()
            self?.needsDisplay = true
            self?.applyInlineFormat()
            self?.onViewChanged?()
        }
    }

    override var acceptsFirstResponder: Bool { return true }
    override var isOpaque: Bool { return true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { return true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        viewport.setViewSize(newSize)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: drawingCursor)
    }

    // MARK: Helper properties

    private var allEntities: [CADEntity] {
        return document?.getAllEntities() ?? []
    }

    private var visibleEntities: [CADEntity] {
        let all = allEntities
        guard let layerManager = layerManager else { return all }
        return all.filter { layerManager.isLayerVisible($0.layer) }
    }

    /// Entities that are snapped to (visible).
    private var snapEntities: [CADEntity] {
        return visibleEntities
    }

    /// Entities that can be edited (visible and on an unlocked layer).
    private var editableEntities: [CADEntity] {
        guard let layerManager = layerManager else { return allEntities }
        return visibleEntities.filter { !layerManager.isLayerLocked($0.layer) }
    }

    private var selectedEntities: [CADEntity] {
        return selectionManager?.getSelectedEntities(from: allEntities) ?? []
    }

    private var isSelectingObjects: Bool {
        return currentTool == .select || stage == .selectObjects
    }

    /// Is the tool waiting for a point (that's when snap and ortho work)?
    private var expectsPoint: Bool {
        if dragMoveBase != nil || activeGrip != nil || pasteRequest != nil { return true }
        switch currentTool {
        case .select, .trim, .extend, .fillet, .chamfer, .powerTrim, .editPoints, .matchProperties, .roomLabel: return false
        case .dimRadius, .dimDiameter, .offset: return !picked.isEmpty
        case .measure: return measureKind.usesPoints
        case .dimContinue: return chainSource != nil
        default: return stage == .points
        }
    }

    /// Mirror is waiting for the answer to “Delete originals?” (the mirrored and the original objects).
    private var pendingMirror: (copies: [CADEntity], originals: [CADEntity])?

    var isBusy: Bool {
        return !points.isEmpty || !picked.isEmpty || selectionBoxStart != nil || !fence.isEmpty || dragMoveBase != nil
            || activeGrip != nil || pendingMirror != nil || axisPick != nil || pasteRequest != nil
            || dynamicInput.hasLockedValue || !edges.isEmpty
    }

    private var worldTolerance: CGFloat {
        return pickTolerance / viewport.getCurrentZoom()
    }

    // MARK: Tool state

    private func resetToolState() {
        valueBoxRequested = false
        pendingMirror = nil
        pasteRequest = nil
        snapManager.clearAcquired()
        snapTracker.clear()
        commitInlineText()
        textBoxStart = nil
        points.removeAll()
        picked.removeAll()
        edges.removeAll()
        fence.removeAll()
        selectionBoxStart = nil
        selectionBoxEnd = nil
        awaitingCloseAnswer = false
        closePrompt.isHidden = true
        lineChainStart = nil
        lineChainCount = 0
        hatchHoverLoops = nil
        roomHover = nil
        mouseDownScreenPoint = nil
        ignoreNextMouseUp = false
        activeSnap = nil
        dragMoveBase = nil
        activeGrip = nil
        gripDragged = false
        hoverRemoved = nil
        hoverAdded.removeAll()
        stretchItems.removeAll()
        chainSource = nil
        chainFrom = nil
        measureObjects.removeAll()
        measureTotal = 0
        matchSource = nil

        switch currentTool {
        case .trim, .extend, .powerTrim, .fillet, .chamfer, .offset:
            stage = .pickTargets
        case .breakObject, .breakAtPoint:
            stage = .points
        case .move, .copy, .rotate, .scale, .mirror:
            stage = (selectionManager?.isEmpty ?? true) ? .selectObjects : .points
        case .array:
            stage = (selectionManager?.isEmpty ?? true) ? .selectObjects : .points
            arrayPreview.removeAll()
            if stage == .points, arrayKind == .rectangular, !repeatingTool {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, self.currentTool == .array, self.stage == .points else { return }
                    self.openArrayDialog(center: nil)
                }
            }
        case .explode, .join, .hatchRebuild, .hatchCut, .wallFromCurve:
            stage = .selectObjects
        case .stretch:
            stage = .window
        case .matchProperties:
            stage = .points
            // a single preselected object = the source of properties
            if let selectionManager = selectionManager, selectedEntities.count == 1 {
                matchSource = selectedEntities.first
                selectionManager.clearSelection()
            }
        case .dimContinue:
            stage = .points
            // continue from the most recently created dimension, if it is still in the drawing
            if chainSource == nil, let last = lastChainableDimension, document?.contains(last) ?? false {
                chainSource = last
                chainFrom = last.points.count > 1 ? last.points[1] : nil
            }
            if chainFrom == nil { chainSource = nil }
        case .blockCreate:
            stage = (selectionManager?.isEmpty ?? true) ? .selectObjects : .points
        case .blockInsert:
            stage = .points
            if insertDefinition == nil || insertDefinition?.isExternal == true || blockLibrary?.named(insertDefinition?.name ?? "") !== insertDefinition {
                insertDefinition = blockLibrary?.blocks.first
            }
        default:
            stage = .points
        }
        if currentTool != .measure { measureResult = nil }
        stateChanged()
    }

    func cancelCurrentOperation() {
        cancelPick()
        if let request = axisPick {
            axisPick = nil
            request.completion(nil)
        }
        viewportPan = nil
        resetToolState()
    }

    private func stateChanged() {
        dynamicInput.reset()
        if let raw = lastRawPoint, expectsPoint { currentWorldPoint = raw }
        updateDynamicInput()
        onPromptChanged?(prompt)
        needsDisplay = true
    }

    var prompt: String {
        if let pick = pickRequest {
            return pick.first == nil ? pick.prompt + " · Esc = cancel" : "Click the opposite corner · Esc = cancel"
        }
        if let pick = axisPick {
            if pick.byObject { return pick.prompt + " · Esc = cancel" }
            return pick.first == nil ? pick.prompt + " · Esc = cancel"
                : "Drawing Coordinates: click a point on the new X axis (sets its direction) · Esc = cancel"
        }
        if let paste = pasteRequest {
            let count = paste.entities.count
            return "Paste \(count) object\(count == 1 ? "" : "s"): click where to place \(count == 1 ? "it" : "them") – the cursor holds the lower-left corner"
                + " (snaps work, or type X, Y + ↩) · Esc = cancel"
        }
        if pendingMirror != nil {
            return "Mirror: delete the original objects?  Y = yes · N, ↩, click or right-click = no (keep them) · Esc = cancel"
        }
        if selectionBoxAwaitsCorner {
            return "Click the opposite corner · Esc = cancel"
        }
        var text: String
        switch currentTool {
        case .select:
            text = (selectionManager?.isEmpty ?? true)
                ? "Click or drag a box to select · Shift adds · ⌘-drag or two fingers to pan"
                : "Drag a selected object to move it · click a blue grip to edit a point · Shift-click grips to move several points · Esc deselects"
            if let last = lastTool, last != .select { text += " · ↩ or right-click = repeat \(last.title)" }
            if let edit = blockEditContext {
                text = "Editing block \u{201C}\(edit.name)\u{201D} · " + text
            } else if selectionManager?.isEmpty ?? true, !(blockLibrary?.blocks.isEmpty ?? true) {
                text += " · double-click a block to edit it"
            }
        case .line:
            if points.isEmpty {
                text = lineContinue ? "Line (continuous): first point" : "Line: first point"
            } else if lineContinue {
                text = "Line (continuous): next point · ↩, right-click or Esc = end"
                    + (lineChainCount >= 2 ? " · C = close back to the start" : "")
            } else {
                text = "Line: second point"
            }
            if let key = DrawingTool.line.shortcut {
                text += " · \(key) = continuous \(lineContinue ? "off" : "on")"
            }
        case .circle:
            text = points.isEmpty ? "Circle: center point" : "Circle: point on circle (or type radius + ↩)"
        case .arc:
            text = "Arc (\(arcMethod.title)): " + arcMethod.prompts[min(points.count, 2)]
            if points.count == 2 && arcMethod.knowsCenter { text += " · hold Shift = 15° steps" }
        case .polygon:
            let what = "Polygon (\(polygonSides) sides, \(polygonMethod.shortTitle))"
            switch (polygonMethod, points.isEmpty) {
            case (.edge, true): text = what + ": first corner of a side · I / C / E = method · S = number of sides"
            case (.edge, false): text = what + ": second corner of the side (or type its length + ↩)"
            case (_, true): text = what + ": center · I / C / E = method · S = number of sides"
            case (.inscribed, false): text = what + ": a corner (or type the radius + ↩)"
            case (.circumscribed, false): text = what + ": the middle of a side (or type the inner radius + ↩)"
            }
        case .ellipse:
            switch points.count {
            case 0: text = "Ellipse: center"
            case 1: text = "Ellipse: end of the first axis (or length and angle + ↩) · hold Shift = ortho"
            default: text = "Ellipse: width of the other axis – click or type the half-axis + ↩"
            }
        case .stretch:
            if stage == .window {
                text = selectionBoxStart == nil
                    ? "Stretch: drag a window (or click two corners) across the points to move – objects fully inside move whole"
                    : "Stretch: opposite corner of the window"
            } else if points.isEmpty {
                text = "Stretch (\(stretchItems.count) object\(stretchItems.count == 1 ? "" : "s")): base point · Esc = new window"
            } else {
                text = "Stretch: second point (or distance and angle + ↩)"
            }
        case .zoomIn, .zoomOut, .zoomExtents, .zoomSelected, .zoomWindow, .filter:
            text = currentTool.title
        case .blockCreate:
            text = stage == .selectObjects
                ? "Create Block: select the objects, then ↩ or right-click"
                : "Create Block: base point – the block will be inserted by this point"
        case .blockInsert, .xref:
            if let definition = insertDefinition {
                text = "\(currentTool == .xref ? "External reference" : "Insert block") “\(definition.name)”: insertion point · Esc = done"
                    + (currentTool == .blockInsert ? " · hold the Insert Block button for other blocks" : "")
            } else {
                text = currentTool == .xref ? "Attach External Reference: choose the file to attach"
                    : "Insert Block: there are no blocks yet – select objects and use Create Block"
            }
        case .array:
            if stage == .selectObjects {
                text = "\(arrayKind.title): select objects, then ↩ or right-click"
            } else if arrayKind == .polar {
                text = "Polar Array: center point (the copies go around it)"
            } else {
                text = "Rectangular Array: set rows, columns and spacing in the dialog"
            }
        case .measure:
            switch measureKind {
            case .distance: text = points.isEmpty ? MeasureKind.distance.prompt : "Measure distance: second point"
            case .angle:
                text = points.isEmpty ? MeasureKind.angle.prompt
                    : points.count == 1 ? "Measure angle: point on the first leg" : "Measure angle: point on the second leg"
            case .areaPoints:
                text = points.isEmpty ? MeasureKind.areaPoints.prompt
                    : "Measure area: next corner · ↩, right-click or click the first corner = finish · ⌫ = undo corner"
            case .length:
                text = measureObjects.isEmpty ? MeasureKind.length.prompt
                    : "Measure length: \(measureObjects.count) object\(measureObjects.count == 1 ? "" : "s"), total \(Measure.format(measureTotal)) \(drawingUnits.suffix) · click more · Esc = start over"
            default: text = measureKind.prompt
            }
            text += " · hold the Measure button for other measurements"
        case .rectangle:
            let modes = [rectangleFromCenter ? "from center" : nil, rectangleIsSquare ? "square" : nil].compactMap { $0 }
            text = modes.isEmpty ? "Rectangle" : "Rectangle (" + modes.joined(separator: ", ") + ")"
            if points.isEmpty {
                text += rectangleFromCenter ? ": center" : ": first corner"
            } else {
                text += rectangleFromCenter ? ": corner" : ": opposite corner"
            }
            text += " · C = " + (rectangleFromCenter ? "from a corner" : "from the center") + " · S = square " + (rectangleSquare ? "off" : "on")
            if !rectangleSquare { text += " · hold Shift = square" }
        case .polyline:
            text = points.isEmpty ? "Polyline: first point"
                : "Polyline: next point (or length + ↩) · ↩ or right-click = finish · click the first point = close · ⌫ = undo point"
        case .spline:
            text = points.isEmpty ? "Spline: first point"
                : "Spline: next point · ↩ or right-click = finish · click the first point = close · ⌫ = undo point"
        case .wall:
            let what = "Wall \(DynamicInputView.format(wallThicknessMM)) mm, \(wallJustification.title)"
            text = points.isEmpty ? what + ": first point · T = thickness · J = side"
                : what + ": next point (or length + ↩) · ↩ or right-click = finish · click the first point = close · ⌫ = undo point"
        case .wallFromCurve:
            text = "Wall from Curve \(DynamicInputView.format(wallThicknessMM)) mm, \(wallCurveAlignment.title): "
                + "select lines, arcs, polylines, splines, circles or ellipses · T = thickness · J = side · ↩ or right-click = create"
        case .hatch:
            text = "Hatch (\(hatchPattern.title), \(LineType.formatAngle(currentHatchAngle))°, scale \(LineType.format(currentHatchScale))"
                + (hatchScale == nil ? " = drawing scale" : "") + "): click inside a closed area · hold the Hatch button for patterns"
        case .trim:
            text = edges.isEmpty
                ? "Trim: click the part to remove (all objects cut) · Shift-click = use only chosen cutting edges"
                : "Trim: click the part to remove · cutting edges: \(edges.count) (Shift-click to change, Esc to clear)"
        case .extend:
            text = edges.isEmpty
                ? "Extend: click near the end of a line, arc or open polyline (extends to the nearest object) · Shift-click = choose boundaries"
                : "Extend: click near the end of a line, arc or open polyline · boundaries: \(edges.count) (Shift-click to change, Esc to clear)"
        case .powerTrim:
            text = "PowerTrim: drag across the parts to remove · click near an end to extend it"
        case .breakObject:
            text = picked.isEmpty
                ? "Break: click the object at the first break point (snaps work)"
                : "Break: second break point – the part between is removed · the same point again = split without a gap · Esc = another object"
        case .breakAtPoint:
            text = "Break at Point: click the object where to split it (snaps work) – it becomes two objects"
        case .offset:
            let distanceText = offsetDistance.map { "distance " + LineType.format($0) } ?? "through point"
            text = picked.isEmpty
                ? "Offset (\(distanceText)): click the object to offset · type a distance (0 = through point)"
                : "Offset (\(distanceText)): click the side" + (offsetDistance == nil ? " – the copy passes through the clicked point" : "")
                    + " · Esc = choose another object"
        case .fillet:
            let radius = DynamicInputView.format(filletRadius)
            text = picked.isEmpty
                ? "Fillet (radius \(radius)): first line or polyline segment · type a radius + ↩ to change it"
                : "Fillet (radius \(radius)): second line or polyline segment"
        case .chamfer:
            let distances = "\(DynamicInputView.format(chamferFirst)) / \(DynamicInputView.format(chamferSecond))"
            text = picked.isEmpty
                ? "Chamfer (\(distances)): first line or polyline segment · type the distances + ↩ to change them"
                : "Chamfer (\(distances)): second line or polyline segment (the second distance is measured on it)"
        case .editPoints:
            text = selectedPoints.isEmpty
                ? "Edit Points: click a point or drag a box around points · Shift adds or removes"
                : "Edit Points: \(selectedPoints.count) point\(selectedPoints.count == 1 ? "" : "s") selected · drag one of them (or click it, then the target) to move them all · Shift adds · Esc clears"
        case .explode:
            text = "Explode: select polylines or blocks, then ↩ or right-click"
        case .hatchRebuild:
            text = "Rebuild Hatch: select the hatch, then ↩ or right-click"
        case .hatchCut:
            text = "Cut Out of Hatch: select the hatch and the closed shapes to cut out, then ↩ or right-click"
        case .join:
            text = "Join: select lines, arcs and polylines, then ↩ or right-click"
        case .move, .copy, .rotate, .scale, .mirror:
            if stage == .selectObjects {
                text = "\(currentTool.title): select objects, then ↩ or right-click"
            } else if points.isEmpty {
                text = currentTool == .mirror ? "Mirror: first point of the mirror line" : "\(currentTool.title): base point"
            } else {
                switch currentTool {
                case .move: text = "Move: second point (or distance + ↩)"
                case .copy: text = "Copy: second point (or distance + ↩) · Esc = done"
                case .rotate: text = "Rotate: angle point (or angle in ° + ↩) · hold Shift = 15° steps"
                case .scale:
                    text = points.count < 2
                        ? "Scale: click the grip point – a point of the objects you will pull (or type a factor + ↩)"
                        : "Scale: pull the grip – on the dashed circle = 1× · closer = smaller · farther = larger · past the base point = negative · or type a factor + ↩"
                default: text = "Mirror: second point of the mirror line"
                }
            }
        case .dimLinear, .dimAligned:
            switch points.count {
            case 0: text = "\(currentTool.title): first point"
            case 1: text = "\(currentTool.title): second point"
            default: text = "\(currentTool.title): position of the dimension line"
            }
        case .xline:
            switch xlineKind {
            case .twoPoints:
                text = points.isEmpty ? "Construction Line: point the line goes through"
                    : "Construction Line: direction (click or type an angle) · more lines through the same point · Esc = end"
            case .horizontal: text = "Horizontal Construction Line: click where it goes"
            case .vertical: text = "Vertical Construction Line: click where it goes"
            case .angle: text = "Construction Line at \(LineType.formatAngle(xlineAngle))°: click where it goes"
            }
            text += " · H = horizontal, V = vertical, A = angle, B = two points"
        case .matchProperties:
            if let source = matchSource {
                text = "Match Properties: click or window the objects to change (from \(source.typeName): \(matchSummary(of: source))) · ↩, right-click or Esc = end"
            } else {
                text = "Match Properties: click the source object · hold the button to choose what is copied"
            }
        case .dimContinue:
            text = chainSource == nil
                ? "Continue Dimension: click the dimension to continue from (near the end to go on from)"
                : "Continue Dimension: next point · ↩, right-click or Esc = end the chain"
        case .dimAngular:
            switch points.count {
            case 0: text = "Angular Dimension: vertex of the angle"
            case 1: text = "Angular Dimension: point on the first leg"
            case 2: text = "Angular Dimension: point on the second leg"
            default: text = "Angular Dimension: position of the arc"
            }
        case .dimRadius, .dimDiameter:
            text = picked.isEmpty ? "\(currentTool.title): click a circle or an arc" : "\(currentTool.title): text position"
        case .leader:
            text = points.isEmpty ? "Leader: arrow point" : "Leader: next point · ↩ or right-click = enter text · ⌫ = undo point"
        case .scaleBar:
            if let scale = scaleBarScale(near: currentWorldPoint ?? .zero) {
                text = "Scale Bar (\(scale.title)\(paperSpace != nil ? ", nearest viewport" : "")): click where its left end goes · hold the button for the North Arrow"
            } else {
                text = "Scale Bar: add a viewport to the layout first – the bar takes its scale"
            }
        case .northArrow:
            text = "North Arrow: click where to place it – it points north (up in the drawing)"
        case .image:
            if let source = pendingImage {
                text = "Attach \(source.isPDF ? "PDF" : "Image") “\(source.fileName)” (\(source.scale.title)): click where its lower-left corner goes"
                    + " · then fit it with Move, Rotate and Scale · Esc = cancel"
            } else {
                text = "Attach Image or PDF: choose the file first"
            }
        case .roomLabel:
            if let outline = roomHover {
                text = "Room Label: click to label this room – " + RoomLabels.areaLine(RoomLabels.squareMeters(of: outline, mmPerUnit: drawingUnits.mmPerUnit))
            } else {
                text = "Room Label: move over a closed room (its outline lights up) and click inside it"
            }
        case .revisionCloud:
            let what = "Revision Cloud (arcs \(DynamicInputView.format(revisionCloudArcMM)) mm on paper)"
            switch (revisionCloudShape, points.isEmpty) {
            case (.polygon, true): text = what + ": first corner of the outline · R = rectangle · A = arc size"
            case (.polygon, false):
                text = what + ": next corner · ↩, right-click, double-click, C or the first corner = close · ⌫ = undo corner"
            case (.rectangle, true): text = what + ": first corner of the rectangle · P = by corners · A = arc size"
            case (.rectangle, false): text = what + ": opposite corner (or type width and height + ↩) · hold Shift = square"
            }
        case .wipeout:
            switch (wipeoutShape, points.isEmpty) {
            case (.rectangle, true): text = "Wipeout: first corner of the rectangle · P = by corners"
            case (.rectangle, false): text = "Wipeout: opposite corner (or type width and height + ↩) · hold Shift = square"
            case (.polygon, true): text = "Wipeout: first corner of the outline · R = rectangle"
            case (.polygon, false):
                text = "Wipeout: next corner · ↩, right-click, double-click, C or the first corner = close · ⌫ = undo corner"
            }
        case .text:
            if inlineText != nil {
                text = "Text: type · ↩ = place · Esc = cancel · click elsewhere = place it and start another"
            } else if textKind == .multiline, textBoxStart != nil {
                text = "Paragraph text: click the opposite corner of the box (its width wraps the lines)"
            } else {
                text = textKind.prompt + " · hold the Text button for other kinds"
            }
        }
        if awaitingCloseAnswer {
            return "Close the \(currentTool.title.lowercased())?  Y = yes · N, ↩, click or right-click = no (keep it open) · Esc = keep drawing"
        }
        if [.polyline, .spline, .wall].contains(currentTool) && points.count >= 3 { text += " · C = close" }
        if inputMode != .none { text += "   · type a value (e.g. 15*7 or 15x7, 100/10), Tab = next field, ↩ = apply" }
        return text
    }

    // MARK: Drawing

    private func style(for entity: CADEntity) -> StrokeStyle {
        let color = layerManager?.resolvedColor(for: entity) ?? entity.color ?? .white
        var dash: [CGFloat] = []
        var marks: LineMarks?
        if let type = layerManager?.lineType(for: entity), !type.isContinuous {
            // line type by the drawing scale: a 3.5 mm dash on paper = 3.5 × scale units in the drawing,
            // times the object's linetype scale; a smaller pattern would just be a gray line → drawn solid (as in AutoCAD)
            let pointsPerMM = unitsPerPaperMM * viewport.getCurrentZoom() * (entity.lineTypeScale ?? 1)
            let parts = type.strokeParts(pointsPerMM: pointsPerMM, minimumPeriod: 3)
            dash = parts.dash
            marks = parts.marks
        }
        return StrokeStyle(color: color, lineWidth: displayedLineWidth(for: entity), dash: dash, marks: marks)
    }

    /// Line width on screen (points) according to LWT, the scale and the mode.
    ///
    /// - True to scale: weight on paper × drawing scale × zoom (changes with zoom like the drawing).
    /// - Fixed on screen: as in AutoCAD – up to 0.25 mm 1 point, thicker proportionally (0.5 mm = 2 points, 1 mm = 4 points),
    ///   regardless of zoom, so the differences in weight are always visible.
    func displayedLineWidth(for entity: CADEntity) -> CGFloat {
        guard showLineWeights else { return 1 }
        let mm = layerManager?.lineWeight(for: entity) ?? entity.lineWeight ?? LineWeights.defaultWeight
        guard mm > 0 else { return 1 }
        let width: CGFloat
        if lineWeightOnScreen {
            width = mm * 4
        } else {
            width = mm * unitsPerPaperMM * viewport.getCurrentZoom()
        }
        // thinner than 1 point: drawn as 1 point (with anti-aliasing the difference in brightness shows too), at most 200 points
        return min(max(1, width), 200)
    }

    /// Anti-aliasing of lines and text.
    var smoothLines = true {
        didSet { needsDisplay = true; onModesChanged?() }
    }

    /// Everything is first drawn into our own image (on the main thread) and only the finished image is
    /// handed to the window. The system's background drawing (CA::CG::Queue) thus never gets
    /// complex paths it could crash on, and any error shows up in our code.
    // MARK: Fast drawing
    //
    // The scene (background, grid, objects) is drawn into a bitmap that is kept. Mouse movement, snap,
    // previews and the selection window are drawn only on top of it. When zooming and panning (wheel, trackpad,
    // middle button) the bitmap is just shifted / scaled and the whole scene is redrawn once the view
    // stops for a moment. Off-screen objects are not drawn, tiny ones (under 1 px) only as a point.

    private var sceneImage: CGImage?
    private var sceneTransform = CGAffineTransform.identity
    private var sceneSize = CGSize.zero
    private var sceneScale: CGFloat = 0
    private var sceneDirty = true
    /// Only the overlay elements are redrawn (cursor, snap, preview, selection window) – the scene stays.
    private var overlayOnlyRedraw = false
    private var lastViewInteraction: TimeInterval = 0
    private var settleTimer: Timer?

    /// Every “redraw” outside mouse movement means the scene has changed too. The value being set decides –
    /// for layer-backed views the `needsDisplay` getter may not return true after it is set.
    override var needsDisplay: Bool {
        get { return super.needsDisplay }
        set {
            if newValue && !overlayOnlyRedraw { sceneDirty = true }
            super.needsDisplay = newValue
        }
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        if !overlayOnlyRedraw { sceneDirty = true }
        super.setNeedsDisplay(invalidRect)
    }

    /// Drawing reloads the objects (after a change of blocks, external references etc.).
    func invalidateRenderCache() {
        renderEpoch += 1
        needsDisplay = true
    }

    /// Zoom / pan from the wheel, trackpad or middle button: for now only the scene image is shifted.
    private func interactiveViewChange(_ change: () -> Void) {
        lastViewInteraction = Date.timeIntervalSinceReferenceDate
        overlayOnlyRedraw = true
        change()
        overlayOnlyRedraw = false
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.settleTimer = nil
                self.lastViewInteraction = 0
                self.needsDisplay = true
            }
        }
    }

    /// Only the overlay elements (mouse movement).
    private func overlayRedraw() {
        overlayOnlyRedraw = true
        needsDisplay = true
        overlayOnlyRedraw = false
    }

    /// The bitmap into which the whole frame is composed (scene + overlay elements); it is reused.
    private var frameContext: CGContext?

    private func makeBitmap(pixelWidth: Int, pixelHeight: Int) -> CGContext? {
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth < 20_000, pixelHeight < 20_000,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                         bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }

    /// The whole frame is composed in our bitmap and only the finished image at a fixed size goes to the view.
    /// (The system replays drawing directly into the view on its own thread – Core Animation – and there
    /// invalid or huge geometry crashes the app.)
    override func draw(_ dirtyRect: NSRect) {
        guard let target = NSGraphicsContext.current?.cgContext,
              bounds.width >= 1, bounds.height >= 1 else { return }

        let scale = max(window?.backingScaleFactor ?? 2, 1)
        let transform = viewport.getTransform()
        guard transform.a.isFinite, transform.b.isFinite, transform.c.isFinite, transform.d.isFinite,
              transform.tx.isFinite, transform.ty.isFinite else { return }
        let interactive = Date.timeIntervalSinceReferenceDate - lastViewInteraction < 0.5
        let sizeChanged = sceneSize != bounds.size || sceneScale != scale

        // the shifted / scaled old image only for a reasonable change – otherwise a new scene right away
        var shift = CGAffineTransform.identity
        var useShift = false
        if !sizeChanged, transform != sceneTransform, interactive {
            shift = sceneTransform.inverted().concatenating(transform)
            let factor = hypot(shift.a, shift.b)
            useShift = factor.isFinite && factor > 1.0 / 8 && factor < 8
                && shift.tx.isFinite && shift.ty.isFinite && abs(shift.tx) < 1e5 && abs(shift.ty) < 1e5
        }
        if sceneImage == nil || sceneDirty || sizeChanged || (transform != sceneTransform && !useShift) {
            renderSceneImage(scale: scale, transform: transform)
            useShift = false
        }

        let pixelWidth = Int((bounds.width * scale).rounded(.up))
        let pixelHeight = Int((bounds.height * scale).rounded(.up))
        if frameContext == nil || frameContext?.width != pixelWidth || frameContext?.height != pixelHeight {
            frameContext = makeBitmap(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        }
        guard let frame = frameContext else { return }

        frame.saveGState()
        frame.scaleBy(x: scale, y: scale)
        frame.setFillColor(backgroundColor.cgColor)
        frame.fill(bounds)
        if let image = sceneImage {
            frame.interpolationQuality = useShift ? .low : .none
            if useShift {
                frame.saveGState()
                frame.concatenate(shift)
                frame.draw(image, in: CGRect(origin: .zero, size: sceneSize))
                frame.restoreGState()
            } else {
                frame.draw(image, in: bounds)
            }
        }
        // overlay elements (preview, snap, selection window…) into the same bitmap
        frame.setAllowsAntialiasing(smoothLines)
        frame.setShouldAntialias(smoothLines)
        frame.setShouldSmoothFonts(smoothLines)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: frame, flipped: false)
        renderOverlays(in: frame, transform: transform)
        NSGraphicsContext.current = previous
        frame.restoreGState()

        if let image = frame.makeImage() {
            target.interpolationQuality = .none
            target.draw(image, in: bounds)
        }
    }

    private func renderSceneImage(scale: CGFloat, transform: CGAffineTransform) {
        let pixelWidth = Int((bounds.width * scale).rounded(.up))
        let pixelHeight = Int((bounds.height * scale).rounded(.up))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let bitmap = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                                     bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                        | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        bitmap.scaleBy(x: scale, y: scale)
        bitmap.setAllowsAntialiasing(smoothLines)
        bitmap.setShouldAntialias(smoothLines)
        bitmap.setShouldSmoothFonts(smoothLines)
        bitmap.interpolationQuality = smoothLines ? .high : .none

        // texts (NSString/NSAttributedString) draw into the current NSGraphicsContext
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: bitmap, flipped: false)
        renderScene(in: bitmap, transform: transform)
        NSGraphicsContext.current = previous

        sceneImage = bitmap.makeImage()
        sceneTransform = transform
        sceneSize = bounds.size
        sceneScale = scale
        sceneDirty = false
    }

    // MARK: List of drawn objects (cache)

    /// Visible objects in draw order and their bounds – recomputed only after the drawing, layers or blocks change.
    private var renderList: [CADEntity] = []
    private var renderBoxes: [CGRect] = []
    private var renderListKey = ""
    private var renderEpoch = 0

    private func refreshRenderList() {
        guard let document = document else {
            renderList = []
            renderBoxes = []
            renderListKey = ""
            return
        }
        let hidden = layerManager?.getAllLayers().filter { !$0.isVisible }.map { $0.name }.joined(separator: "\u{1}") ?? ""
        let blocks = blockSignature
        let key = "\(ObjectIdentifier(document).hashValue)|\(document.revision)|\(blocks)|\(renderEpoch)|\(hidden)"
        guard key != renderListKey else { return }
        renderListKey = key
        renderList = DrawOrder.sorted(visibleEntities)
        renderBoxes = renderList.map { $0.boundingBox() }
    }

    /// Do the bounds overlap the rectangle? (Zero width/height of a line counts; unknown bounds = always.)
    private static func overlaps(_ box: CGRect, _ rect: CGRect) -> Bool {
        if box.isNull || !box.minX.isFinite || !box.maxX.isFinite || !box.minY.isFinite || !box.maxY.isFinite { return true }
        return box.maxX >= rect.minX && box.minX <= rect.maxX && box.maxY >= rect.minY && box.minY <= rect.maxY
    }

    /// Visible objects whose bounds are near the point (snap, click) – in draw order.
    private func entitiesNear(_ point: CGPoint, tolerance: CGFloat) -> [CADEntity] {
        refreshRenderList()
        let rect = CGRect(x: point.x - tolerance, y: point.y - tolerance, width: 2 * tolerance, height: 2 * tolerance)
        var result: [CADEntity] = []
        for index in renderList.indices where CADEditorView.overlaps(renderBoxes[index], rect) {
            result.append(renderList[index])
        }
        return result
    }

    private func renderScene(in context: CGContext, transform: CGAffineTransform) {
        context.setFillColor(backgroundColor.cgColor)
        context.fill(bounds)
        ConstructionLine.drawingArea = bounds

        if let paper = paperSpace {
            drawPaper(in: context, transform: transform)
            context.saveGState()
            context.clip(to: paper.paperRect.applying(transform))
            gridRenderer.draw(in: context, viewport: viewport, viewSize: bounds.size)
            context.restoreGState()
            drawViewportContents(in: context, transform: transform)
        } else {
            gridRenderer.draw(in: context, viewport: viewport, viewSize: bounds.size)
        }
        let edgeIds = Set(edges.map { $0.id })
        let pickedIds = Set(picked.map { $0.entity.id })

        refreshRenderList()
        // only what is on screen (with a margin for lineweights and texts at the edge)
        let inverse = transform.inverted()
        let zoom = max(Geometry.uniformScale(of: transform), 1e-12)
        let margin = 48 / zoom
        let visibleWorld = bounds.applying(inverse).insetBy(dx: -margin, dy: -margin)
        drawBlockEditBackground(in: context, transform: transform, visibleWorld: visibleWorld)
        let editingText = inlineText?.editing
        let selection = selectionManager
        for index in renderList.indices {
            let box = renderBoxes[index]
            guard CADEditorView.overlaps(box, visibleWorld) else { continue }
            let entity = renderList[index]
            // the text being edited is drawn in the field on the canvas, not below it
            if let editing = editingText, editing === entity { continue }
            var s = style(for: entity)
            var highlighted = true
            if edgeIds.contains(entity.id) || pickedIds.contains(entity.id) {
                s.color = .systemOrange
                s.lineWidth = max(2.5, s.lineWidth + 1.5)
            } else if selection?.isSelected(entity) ?? false {
                s.color = .systemCyan
                s.lineWidth = max(2.5, s.lineWidth + 1.5)
            } else {
                highlighted = false
            }
            // a tiny object (smaller than a pixel) only as a point – drawing it whole would be needlessly slow
            if !box.isNull, max(box.width, box.height) * zoom < 1, box.minX.isFinite, box.minY.isFinite, !(entity is SurveyPoint) {
                let p = CGPoint(x: box.midX, y: box.midY).applying(transform)
                context.setFillColor(s.color.cgColor)
                context.fill(CGRect(x: p.x - 0.5, y: p.y - 0.5, width: 1, height: 1))
                continue
            }
            // a highlighted block is drawn entirely in the selection color
            BlockReference.highlightDrawing = highlighted
            entity.draw(in: context, transform: transform, style: s)
            BlockReference.highlightDrawing = false
        }
    }

    private func renderOverlays(in context: CGContext, transform: CGAffineTransform) {
        drawPreview(in: context, transform: transform)
        drawMeasure(in: context, transform: transform)
        drawHover(in: context, transform: transform)
        drawHatchHover(in: context, transform: transform)
        drawRoomHover(in: context, transform: transform)
        drawSelectionBox(in: context)
        drawFence(in: context)
        drawPick(in: context, transform: transform)
        drawScaleReference(in: context, transform: transform)
        drawTextBoxPreview(in: context, transform: transform)
        drawGrips(in: context, transform: transform)
        snapTracker.draw(in: context, bounds: bounds, ucsAngle: ucsAngle) { viewport.worldToScreen($0) }
        drawSnapMarker(in: context)
        drawAxisPick(in: context, transform: transform)
        drawUCSIcon(in: context, transform: transform)
        drawBlockBasePoint(in: context, transform: transform)
    }

    // MARK: Rotating the drawing coordinates – choosing the axes

    /// Picking just one point (geodetic base point) – no angle is returned.
    private var singlePointPick = false
    private var axisPick: (prompt: String, first: CGPoint?, byObject: Bool,
                           completion: ((origin: CGPoint, angle: CGFloat)?) -> Void)?

    /// Origin and direction of the X axis: by clicking an object, or by two points. Esc = completion(nil).
    func pickAxis(byObject: Bool, prompt: String, singlePoint: Bool = false,
                  completion: @escaping ((origin: CGPoint, angle: CGFloat)?) -> Void) {
        cancelCurrentOperation()
        singlePointPick = singlePoint
        axisPick = (prompt, nil, byObject, completion)
        window?.makeFirstResponder(self)
        stateChanged()
    }

    /// Axis from an object: a line / polyline segment (origin = the nearer end), text (insertion point and rotation).
    private func axisOfObject(near world: CGPoint) -> (origin: CGPoint, angle: CGFloat)? {
        let tolerance = worldTolerance
        var best: (origin: CGPoint, angle: CGFloat, distance: CGFloat)?
        for entity in entitiesNear(world, tolerance: tolerance) {
            if let text = entity as? TextEntity, text.distance(to: world) <= tolerance {
                return (text.position, text.rotation)
            }
            for primitive in entity.primitives() {
                guard case let .segment(a, b, _) = primitive, Geometry.distance(a, b) > 1e-9 else { continue }
                let d = Geometry.distance(from: world, toSegmentFrom: a, to: b)
                guard d <= tolerance, d < (best?.distance ?? .infinity) else { continue }
                let fromA = Geometry.distance(world, a) <= Geometry.distance(world, b)
                let origin = fromA ? a : b, other = fromA ? b : a
                best = (origin, Geometry.angle(from: origin, to: other), d)
            }
        }
        return best.map { ($0.origin, $0.angle) }
    }

    private func drawAxisPick(in context: CGContext, transform: CGAffineTransform) {
        guard let pick = axisPick, !pick.byObject, let first = pick.first, let current = currentWorldPoint else { return }
        let a = first.applying(transform), b = current.applying(transform)
        context.saveGState()
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [6, 3])
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()
        context.restoreGState()
    }

    /// Axis icon at the bottom left – only when the drawing coordinates or the view are rotated.
    private func drawUCSIcon(in context: CGContext, transform: CGAffineTransform) {
        guard isUCSRotated || abs(viewport.rotation) > 1e-12, paperSpace == nil else { return }
        let origin = CGPoint(x: 34, y: 34)
        let length: CGFloat = 26
        context.saveGState()
        context.setLineWidth(1.5)
        for (axisAngle, color, label) in [(ucsAngle, NSColor.systemRed, "X"), (ucsAngle + .pi / 2, NSColor.systemGreen, "Y")] {
            let d = CGPoint(x: cos(axisAngle), y: sin(axisAngle))
            let s = CGPoint(x: transform.a * d.x + transform.c * d.y, y: transform.b * d.x + transform.d * d.y).normalized
            let tip = origin + s * length
            context.setStrokeColor(color.cgColor)
            context.move(to: origin)
            context.addLine(to: tip)
            let side = s.perpendicular * 3.5
            context.move(to: tip - s * 6 + side)
            context.addLine(to: tip)
            context.addLine(to: tip - s * 6 - side)
            context.strokePath()
            let labelPoint = origin + s * (length + 9)
            (label as NSString).draw(at: CGPoint(x: labelPoint.x - 4, y: labelPoint.y - 7),
                                     withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: color])
        }
        context.setFillColor(Theme.ucsOrigin.cgColor)
        context.fill(CGRect(x: origin.x - 2, y: origin.y - 2, width: 4, height: 4))
        context.restoreGState()
    }

    /// Objects whose grips are shown: in Select the selected ones, in Edit Points all visible editable ones.
    private var gripEntities: [CADEntity] {
        guard dragMoveBase == nil else { return [] }
        switch currentTool {
        case .select:
            let selected = movableSelection
            return selected.count <= maxGripEntities ? selected : []
        case .editPoints:
            let a = viewport.screenToWorld(.zero)
            let b = viewport.screenToWorld(CGPoint(x: bounds.width, y: bounds.height))
            let visible = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            let pad = worldTolerance
            return Array(editableEntities.lazy
                .filter { visible.intersects($0.boundingBox().insetBy(dx: -pad, dy: -pad)) && !Grips.grips(of: $0).isEmpty }
                .prefix(800))
        default:
            return []
        }
    }

    /// Grips the tool works with (Edit Points: only vertices, ends and centers – not segment midpoints).
    private func activeGrips(of entity: CADEntity) -> [(index: Int, grip: Grips.Grip)] {
        let all = Grips.grips(of: entity).enumerated().map { (index: $0.offset, grip: $0.element) }
        return currentTool == .editPoints ? all.filter { $0.grip.kind != .midpoint } : all
    }

    private func drawGrips(in context: CGContext, transform: CGAffineTransform) {
        let entities = gripEntities
        guard !entities.isEmpty else { return }
        let half: CGFloat = 4
        let moving = Set((activeGrip?.items ?? []).map { "\($0.entity.id)#\($0.index)" })
        context.saveGState()
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [])
        for entity in entities {
            for item in activeGrips(of: entity) {
                let p = item.grip.point.applying(transform)
                guard DrawingSafety.isFinite(p) else { continue }
                let ref = PointRef(id: entity.id, index: item.index)
                let isActive = moving.contains("\(entity.id)#\(item.index)") || selectedPoints.contains(ref)
                let isHover = hoverGrip.map { $0.id == entity.id && $0.index == item.index } ?? false
                let fill: NSColor = isActive ? .systemRed : (isHover ? .systemOrange : Theme.grip)
                let rect = CGRect(x: p.x - half, y: p.y - half, width: 2 * half, height: 2 * half)
                let path = CGMutablePath()
                switch item.grip.kind {
                case .point:
                    path.addRect(rect)
                case .midpoint:
                    path.move(to: CGPoint(x: p.x, y: p.y - half - 1))
                    path.addLine(to: CGPoint(x: p.x + half + 1, y: p.y))
                    path.addLine(to: CGPoint(x: p.x, y: p.y + half + 1))
                    path.addLine(to: CGPoint(x: p.x - half - 1, y: p.y))
                    path.closeSubpath()
                case .center:
                    path.addEllipse(in: rect)
                }
                context.addPath(path)
                context.setFillColor(fill.cgColor)
                context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
                context.drawPath(using: .fillStroke)
            }
        }
        context.restoreGState()
    }

    /// The grip under the cursor (in screen points).
    private func grip(atScreen screenPoint: CGPoint) -> (entity: CADEntity, index: Int, point: CGPoint)? {
        let transform = viewport.getTransform()
        var best: (entity: CADEntity, index: Int, point: CGPoint)?
        var bestDistance = gripHitRadius
        for entity in gripEntities {
            for item in activeGrips(of: entity) {
                let d = Geometry.distance(item.grip.point.applying(transform), screenPoint)
                if d <= bestDistance {
                    bestDistance = d
                    best = (entity, item.index, item.grip.point)
                }
            }
        }
        return best
    }

    /// Points for the marked references (objects are looked up by id; vanished ones are skipped).
    private func gripItems(for refs: [PointRef]) -> [(entity: CADEntity, index: Int, point: CGPoint)] {
        var byID: [UUID: CADEntity] = [:]
        for entity in editableEntities { byID[entity.id] = entity }
        return refs.compactMap { ref -> (entity: CADEntity, index: Int, point: CGPoint)? in
            guard let entity = byID[ref.id] else { return nil }
            let grips = Grips.grips(of: entity)
            guard ref.index < grips.count else { return nil }
            return (entity, ref.index, grips[ref.index].point)
        }
    }

    private func beginGripEdit(base: CGPoint, items: [(entity: CADEntity, index: Int, point: CGPoint)], justSelected: Bool) {
        guard !items.isEmpty else { return }
        activeGrip = GripEdit(items: items, base: base, justSelected: justSelected)
        gripDragged = false
        hoverGrip = nil
        currentWorldPoint = base
        lastRawPoint = base
        onPromptChanged?(items.count > 1
            ? "Move \(items.count) points: click or drag to the new position · or type distance and angle + ↩ · Esc = cancel"
            : "Stretch: click or drag to the new position · or type distance and angle + ↩ · Esc = cancel")
        updateDynamicInput()
        needsDisplay = true
    }

    /// The edited objects when all edit points are moved by (target − base).
    private func gripResults(_ grip: GripEdit, target: CGPoint) -> [(original: CADEntity, edited: CADEntity)] {
        let delta = target - grip.base
        var order: [UUID] = []
        var groups: [UUID: (entity: CADEntity, moves: [(index: Int, point: CGPoint)])] = [:]
        for item in grip.items {
            if groups[item.entity.id] == nil {
                order.append(item.entity.id)
                groups[item.entity.id] = (item.entity, [])
            }
            groups[item.entity.id]?.moves.append((item.index, item.point + delta))
        }
        var result: [(original: CADEntity, edited: CADEntity)] = []
        for id in order {
            guard let group = groups[id] else { continue }
            var current: CADEntity = group.entity
            var valid = true
            // several points of the same object one after another (grip indices don't change by moving)
            for move in group.moves {
                guard let next = Grips.moved(current, grip: move.index, to: move.point) else {
                    valid = false
                    break
                }
                current = next
            }
            if valid && current !== group.entity { result.append((group.entity, current)) }
        }
        return result
    }

    /// Finishes grip editing at point `target`.
    private func finishGrip(at target: CGPoint) {
        guard let grip = activeGrip else { return }
        activeGrip = nil
        gripDragged = false
        activeSnap = nil
        if Geometry.distance(grip.base, target) > 1e-12 {
            let results = gripResults(grip, target: target)
            if !results.isEmpty {
                onCommit?(results.map { $0.original }, results.map { $0.edited }, grip.items.count > 1 ? "Move Points" : "Stretch")
                // carry the marking of points and objects over to the edited objects
                var newID: [UUID: UUID] = [:]
                for result in results { newID[result.original.id] = result.edited.id }
                selectedPoints = selectedPoints.map { PointRef(id: newID[$0.id] ?? $0.id, index: $0.index) }
                if currentTool == .select {
                    selectionManager?.select(results.map { $0.edited }, additive: true)
                }
            }
        }
        stateChanged()
    }

    /// Edit Points: points inside the dragged rectangle.
    private func finishPointBox(from start: CGPoint, to end: CGPoint) {
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        guard rect.width > 3 || rect.height > 3 else { return }
        let transform = viewport.getTransform()
        var refs = selectionBoxAdditive ? selectedPoints : []
        for entity in gripEntities {
            for item in activeGrips(of: entity) where rect.contains(item.grip.point.applying(transform)) {
                let ref = PointRef(id: entity.id, index: item.index)
                if !refs.contains(ref) { refs.append(ref) }
            }
        }
        selectedPoints = refs
        onPromptChanged?(prompt)
    }

    private func drawPreview(in context: CGContext, transform: CGAffineTransform) {
        if !arrayPreview.isEmpty {
            for copy in arrayPreview {
                copy.draw(in: context, transform: transform, style: StrokeStyle(color: .systemGreen, lineWidth: 1, dash: [6, 4]))
            }
            return
        }
        if awaitingCloseAnswer {
            // preview: the open shape solid, the closing part green and dashed
            let layer = currentLayerName
            let open: CADEntity = currentTool == .spline
                ? Spline(controlPoints: points, closed: false, layer: layer)
                : Polyline(vertices: points, closed: false, layer: layer)
            let closed: CADEntity = currentTool == .spline
                ? Spline(controlPoints: points, closed: true, layer: layer)
                : Polyline(vertices: points, closed: true, layer: layer)
            closed.draw(in: context, transform: transform,
                        style: StrokeStyle(color: .systemGreen, lineWidth: 1.5, dash: [6, 4]))
            open.draw(in: context, transform: transform, style: StrokeStyle(color: .lightGray, lineWidth: 1.5))
            return
        }
        if let pending = pendingMirror {
            // the mirrored result solid, the originals dashed (they may get deleted)
            for copy in pending.copies {
                copy.draw(in: context, transform: transform, style: StrokeStyle(color: .systemGreen, lineWidth: 1.5))
            }
            for original in pending.originals {
                original.draw(in: context, transform: transform, style: StrokeStyle(color: .systemRed, lineWidth: 1.5, dash: [5, 4]))
            }
            return
        }
        if currentTool == .wallFromCurve {
            // the walls of the selected curves – no cursor needed
            for outline in wallFromCurveOutlines() {
                outline.draw(in: context, transform: transform, style: StrokeStyle(color: .systemGreen, lineWidth: 1.5, dash: [6, 4]))
            }
            return
        }
        guard let cursor = currentWorldPoint else { return }
        let previewStyle = StrokeStyle(color: .lightGray, lineWidth: 1, dash: [6, 4])

        if let paste = pasteRequest {
            drawPastePreview(paste, cursor: cursor, in: context, transform: transform)
            return
        }

        if let grip = activeGrip {
            // grip editing preview + a rubber-band line from the original position
            for result in gripResults(grip, target: cursor) {
                result.edited.draw(in: context, transform: transform, style: StrokeStyle(color: .systemOrange, lineWidth: 1.5, dash: [6, 4]))
            }
            let a = grip.base.applying(transform), b = cursor.applying(transform)
            if DrawingSafety.isFinite(a), DrawingSafety.isFinite(b) {
                context.saveGState()
                context.setStrokeColor(NSColor.gray.cgColor)
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [3, 3])
                context.move(to: a)
                context.addLine(to: b)
                context.strokePath()
                context.restoreGState()
            }
            return
        }

        if let base = dragMoveBase {
            let t = CGAffineTransform(translationX: cursor.x - base.x, y: cursor.y - base.y)
            for entity in movableSelection {
                let copy = entity.clone()
                copy.applyTransform(t)
                copy.draw(in: context, transform: transform, style: previewStyle)
            }
            return
        }

        for entity in previewEntities(cursor: cursor) {
            entity.draw(in: context, transform: transform, style: previewStyle)
        }

        // rubber-band line from the last/base point
        if expectsPoint, let last = points.last, [.arc, .move, .copy, .rotate, .scale, .mirror, .stretch].contains(currentTool),
           DrawingSafety.isFinite(last.applying(transform)), DrawingSafety.isFinite(cursor.applying(transform)) {
            context.saveGState()
            context.setStrokeColor(NSColor.gray.cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.move(to: last.applying(transform))
            context.addLine(to: cursor.applying(transform))
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawHover(in context: CGContext, transform: CGAffineTransform) {
        if let removed = hoverRemoved {
            removed.draw(in: context, transform: transform,
                         style: StrokeStyle(color: .systemRed, lineWidth: 3, dash: [5, 3]))
        }
        for entity in hoverAdded {
            entity.draw(in: context, transform: transform,
                        style: StrokeStyle(color: .systemGreen, lineWidth: 1.5, dash: [6, 4]))
        }
    }

    /// Computes the Trim/Extend preview for the object under the cursor.
    private func updateHover(at worldPoint: CGPoint) {
        let previousRemoved = hoverRemoved?.id
        let previousCount = hoverAdded.count
        hoverRemoved = nil
        hoverAdded.removeAll()

        if fence.isEmpty, selectionBoxStart == nil {
            switch currentTool {
            case .trim:
                if let target = entity(at: worldPoint, where: { EditOperations.isTrimmable($0) }),
                   let detail = EditOperations.trimAny(target, at: worldPoint, edges: cuttingEdges) {
                    hoverRemoved = detail.removed
                }
            case .extend, .powerTrim:
                if let target = entity(at: worldPoint, where: { CADEditorView.isExtendable($0) }),
                   let extended = EditOperations.extend(target, near: worldPoint, boundaries: cuttingEdges) {
                    hoverAdded = [extended]
                }
            default:
                break
            }
        }
        if previousRemoved != nil || hoverRemoved != nil || previousCount > 0 || !hoverAdded.isEmpty {
            needsDisplay = true
        }
    }

    private static func isExtendable(_ entity: CADEntity) -> Bool {
        return entity is Line || entity is Arc || (entity as? Polyline)?.closed == false
    }

    private func drawSelectionBox(in context: CGContext) {
        guard let start = selectionBoxStart, let end = selectionBoxEnd else { return }
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        let crossing = end.x < start.x || currentTool == .stretch
        let color: NSColor = crossing ? .systemGreen : .systemBlue

        context.saveGState()
        context.setFillColor(color.withAlphaComponent(0.12).cgColor)
        context.fill(rect)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        if crossing { context.setLineDash(phase: 0, lengths: [5, 3]) }
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }

    private func drawFence(in context: CGContext) {
        guard fence.count >= 2, fence.allSatisfy({ DrawingSafety.isFinite($0) }) else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.systemRed.cgColor)
        context.setLineWidth(1.5)
        context.addLines(between: fence)
        context.strokePath()
        context.restoreGState()
    }

    private func drawSnapMarker(in context: CGContext) {
        guard let snap = activeSnap else { return }
        let p = viewport.worldToScreen(snap.point)
        guard DrawingSafety.isFinite(p) else { return }
        // construction line of the extension / perpendicular / tangent
        if let anchor = snap.anchor.map({ viewport.worldToScreen($0) }), DrawingSafety.isFinite(anchor) {
            context.saveGState()
            context.setStrokeColor(NSColor.systemGreen.withAlphaComponent(0.8).cgColor)
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [2, 3])
            context.move(to: anchor)
            context.addLine(to: p)
            context.strokePath()
            context.restoreGState()
        }
        SnapMarker.draw(snap.type, at: p, size: 6, color: .systemYellow, in: context)
        (snap.type.rawValue as NSString).draw(at: CGPoint(x: p.x + 10, y: p.y + 6),
                                              withAttributes: [.foregroundColor: NSColor.systemYellow,
                                                               .font: NSFont.systemFont(ofSize: 10)])
    }

    // MARK: Preview and entity creation

    private var currentLayerName: String {
        return layerManager?.currentLayerName ?? "0"
    }

    /// Dimension text height in the drawing: height on paper (Dimension Style) × drawing scale.
    private var dimensionTextHeight: CGFloat {
        return max(AppSettings.dimTextHeightMM, 0.1) * unitsPerPaperMM
    }

    /// A new dimension according to the dimension style (terminator, terminator size, decimal places).
    private func styled(_ dimension: DimensionEntity) -> DimensionEntity {
        // a “horizontal / vertical” linear dimension in rotated drawing coordinates
        if dimension.kind == .linear, dimension.fixedAngle == nil, abs(ucsAngle) > 1e-12, dimension.points.count >= 3 {
            let local = DimensionEntity(kind: .linear, points: dimension.points.map { toUCS($0) }, textHeight: dimension.textHeight)
            let d = fromUCSVector(local.measureDirection)
            dimension.fixedAngle = atan2(d.y, d.x)
        }
        dimension.arrowStyle = AppSettings.dimArrowStyle
        dimension.arrowSize = max(AppSettings.dimArrowSizeMM, 0.1) * unitsPerPaperMM
        dimension.precision = AppSettings.dimDecimals
        return dimension
    }

    /// Entities that would be created from the points so far + point `end`.
    private func makeEntities(with end: CGPoint, final: Bool) -> [CADEntity] {
        let layer = currentLayerName
        let all = points + [end]
        let tiny: CGFloat = 1e-9

        switch currentTool {
        case .line:
            guard all.count >= 2, Geometry.distance(all[0], all[1]) > tiny else { return [] }
            return [Line(start: all[0], end: all[1], layer: layer)]

        case .circle:
            guard all.count >= 2 else { return [] }
            let r = Geometry.distance(all[0], all[1])
            return r > tiny ? [Circle(center: all[0], radius: r, layer: layer)] : []

        case .arc:
            if all.count == 2 {
                guard !final else { return [] }
                if arcMethod.usesThirdPointOnArc {
                    return Geometry.distance(all[0], all[1]) > tiny ? [Line(start: all[0], end: all[1], layer: layer)] : []
                }
                // we know the center and the start – preview of the whole circle
                let center = arcMethod.startFirst ? all[1] : all[0]
                let r = Geometry.distance(all[0], all[1])
                return r > tiny ? [Circle(center: center, radius: r, layer: layer)] : []
            }
            guard all.count >= 3 else { return [] }
            let arc: Arc?
            switch arcMethod {
            case .threePoint:
                arc = CADEditorView.arcThrough(all[0], all[1], all[2], layer: layer)
            case .startEndRadius, .startEndAngle:
                arc = CADEditorView.arcThrough(all[0], all[2], all[1], layer: layer)
            default:
                let center = arcMethod.startFirst ? all[1] : all[0]
                let start = arcMethod.startFirst ? all[0] : all[1]
                let r = Geometry.distance(center, start)
                let a1 = Geometry.angle(from: center, to: start)
                let a2 = Geometry.angle(from: center, to: all[2])
                arc = (r > tiny && Geometry.ccwDelta(from: a1, to: a2) > 1e-9)
                    ? Arc(center: center, radius: r, startAngle: a1, endAngle: a2, layer: layer) : nil
            }
            return arc.map { [$0] } ?? []

        case .polygon:
            guard all.count >= 2,
                  let corners = RegularPolygon.vertices(sides: effectivePolygonSides, method: polygonMethod, all[0], all[1])
            else { return [] }
            return [Polyline(vertices: corners, closed: true, layer: layer)]

        case .ellipse:
            guard all.count >= 2 else { return [] }
            let axis = all[1] - all[0]
            guard axis.length > tiny else { return [] }
            let axisLine = Line(start: all[0] - axis, end: all[1], layer: layer)
            if all.count == 2 { return final ? [] : [axisLine] }
            let b = abs((all[2] - all[0]).dot(axis.normalized.perpendicular))
            guard b > tiny else { return final ? [] : [axisLine] }
            return [Ellipse(center: all[0], axisEnd: all[1], minorRadius: b, layer: layer)]

        case .stretch:
            guard let base = points.first else { return [] }
            return stretchResults(delta: end - base).map { $0.edited }

        case .dimContinue:
            return chainDimension(to: end).map { [$0] } ?? []

        case .blockInsert, .xref:
            guard let definition = insertDefinition else { return [] }
            return [BlockReference(definition: definition, position: end, layer: layer)]

        case .scaleBar, .northArrow:
            return symbolReference(at: end).map { [$0] } ?? []

        case .image:
            return pendingImage.map { [placedImage($0, at: end)] } ?? []

        case .xline:
            if xlineKind == .twoPoints {
                guard all.count >= 2, Geometry.distance(all[0], all[1]) > tiny else { return [] }
                return [ConstructionLine(point: all[0], angle: Geometry.angle(from: all[0], to: all[1]), layer: layer)]
            }
            return [ConstructionLine(point: end, angle: xlineFixedAngle, layer: layer)]

        case .rectangle:
            guard all.count >= 2 else { return [] }
            // sides parallel to the axes of the drawing coordinates
            let (a, d) = rectangleDiagonal(from: all[0], to: all[1])
            let b = a + fromUCSVector(d)
            guard abs(d.x) > tiny, abs(d.y) > tiny else {
                // zero width or height so far – at least a line in the preview
                return (!final && Geometry.distance(a, b) > tiny) ? [Line(start: a, end: b, layer: layer)] : []
            }
            return [Polyline(vertices: [a, a + fromUCSVector(CGPoint(x: d.x, y: 0)), b, a + fromUCSVector(CGPoint(x: 0, y: d.y))],
                             closed: true, layer: layer)]

        case .polyline:
            let vertices = final ? points : all
            guard vertices.count >= 2 else { return [] }
            return [Polyline(vertices: vertices, closed: false, layer: layer)]

        case .spline:
            let vertices = final ? points : all
            guard vertices.count >= 2 else { return [] }
            return [Spline(controlPoints: vertices, closed: false, layer: layer)]

        case .dimLinear, .dimAligned:
            if all.count == 2 && !final {
                return [Line(start: all[0], end: all[1], layer: layer)]
            }
            guard all.count >= 3, Geometry.distance(all[0], all[1]) > tiny else { return [] }
            return [styled(DimensionEntity(kind: currentTool == .dimLinear ? .linear : .aligned,
                              points: Array(all.prefix(3)), textHeight: dimensionTextHeight, layer: layer))]

        case .dimAngular:
            if all.count < 4 {
                guard !final, all.count >= 2 else { return [] }
                return (1..<all.count).map { Line(start: all[0], end: all[$0], layer: layer) }
            }
            return [styled(DimensionEntity(kind: .angular, points: Array(all.prefix(4)), textHeight: dimensionTextHeight, layer: layer))]

        case .dimRadius, .dimDiameter:
            guard let target = picked.first?.entity else { return [] }
            let center: CGPoint, radius: CGFloat
            if let circle = target as? Circle {
                center = circle.center
                radius = circle.radius
            } else if let arc = target as? Arc {
                center = arc.center
                radius = arc.radius
            } else {
                return []
            }
            return [styled(DimensionEntity(kind: currentTool == .dimRadius ? .radius : .diameter, points: [center, end],
                              radius: radius, textHeight: dimensionTextHeight, layer: layer))]

        case .leader:
            let vertices = final ? points : all
            guard vertices.count >= 2 else { return [] }
            return [DimensionEntity(kind: .leader, points: vertices, text: final ? "" : "…",
                              textHeight: dimensionTextHeight, layer: layer)]

        case .revisionCloud:
            let outline = outlineCorners(final ? points : all)
            if let cloud = RevisionCloud.polyline(around: outline, arcSize: revisionCloudArcSize, layer: layer) { return [cloud] }
            // not an area yet – at least the side drawn so far in the preview
            return (!final && all.count >= 2 && Geometry.distance(all[0], all[all.count - 1]) > tiny)
                ? [Polyline(vertices: all, layer: layer)] : []

        case .wall:
            return Walls.outlines(along: final ? points : all, closed: false, thickness: wallThickness,
                                  justification: wallJustification, layer: layer)

        case .wipeout:
            // the preview is only the outline – a filled one would hide the texts it is meant to keep visible
            let outline = outlineCorners(final ? points : all)
            let box = HatchEntity.box(of: outline)
            guard outline.count >= 2, max(box.width, box.height) > tiny else { return [] }
            return [Polyline(vertices: outline, closed: outline.count >= 3, layer: layer)]

        case .move, .copy, .rotate, .scale, .mirror:
            // Scale: preview only after the reference point is chosen
            if currentTool == .scale && points.count < 2 && !final { return [] }
            guard let base = points.first, let t = transformFor(base: base, target: end) else { return [] }
            return selectedEntities.map { entity -> CADEntity in
                let copy = entity.clone()
                copy.applyTransform(t)
                return copy
            }

        default:
            return []
        }
    }

    /// An arc from `start` through `through` to `end`.
    static func arcThrough(_ start: CGPoint, _ through: CGPoint, _ end: CGPoint, layer: String) -> Arc? {
        guard let circle = Geometry.circleThrough(start, through, end) else { return nil }
        let a1 = Geometry.angle(from: circle.center, to: start)
        let a2 = Geometry.angle(from: circle.center, to: through)
        let a3 = Geometry.angle(from: circle.center, to: end)
        // counterclockwise from start to end if the through point lies that way too; otherwise the other way
        if Geometry.ccwDelta(from: a1, to: a2) < Geometry.ccwDelta(from: a1, to: a3) {
            return Arc(center: circle.center, radius: circle.radius, startAngle: a1, endAngle: a3, layer: layer)
        }
        return Arc(center: circle.center, radius: circle.radius, startAngle: a3, endAngle: a1, layer: layer)
    }

    /// Center and start of the arc for the center-based methods.
    private var arcCenterAndStart: (center: CGPoint, start: CGPoint)? {
        guard currentTool == .arc, points.count >= 2, !arcMethod.usesThirdPointOnArc else { return nil }
        return arcMethod.startFirst ? (points[1], points[0]) : (points[0], points[1])
    }

    /// A point on the arc between points[0] and points[1] with the given height (rise) on the cursor's side.
    private func arcPointWithSagitta(_ sagitta: CGFloat, cursor: CGPoint) -> CGPoint? {
        guard points.count >= 2 else { return nil }
        let s = points[0], e = points[1]
        let n = (e - s).normalized.perpendicular
        guard n != .zero else { return nil }
        let mid = Geometry.midpoint(s, e)
        let side: CGFloat = (cursor - mid).dot(n) >= 0 ? 1 : -1
        return mid + n * (side * sagitta)
    }

    private func previewEntities(cursor: CGPoint) -> [CADEntity] {
        if awaitingCloseAnswer { return [] }
        guard expectsPoint, !points.isEmpty || [.dimRadius, .dimDiameter, .blockInsert, .xref, .dimContinue, .xline, .scaleBar, .northArrow, .image].contains(currentTool) else { return [] }
        return makeEntities(with: cursor, final: false)
    }

    // MARK: Scale with the mouse

    /// Reference length and direction for Scale: the cursor on the dashed circle = 1×.
    /// Length = distance of the base point from the farthest corner of the selection, direction = toward its center.
    private func scaleReference(base: CGPoint) -> (length: CGFloat, direction: CGPoint) {
        // a chosen reference point: its distance from the base point = 1×
        if currentTool == .scale, points.count >= 2 {
            let d = points[1] - base
            let length = hypot(d.x, d.y)
            if length > 1e-9 { return (length, CGPoint(x: d.x / length, y: d.y / length)) }
        }
        var box = CGRect.null
        for entity in selectedEntities { box = box.union(entity.boundingBox()) }
        guard !box.isNull, box.width.isFinite, box.height.isFinite else { return (1, CGPoint(x: 1, y: 0)) }
        let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                       CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
        var length = corners.map { Geometry.distance(base, $0) }.max() ?? 1
        if length < 1e-9 { length = max(box.width, box.height, 1) }
        var direction = (CGPoint(x: box.midX, y: box.midY) - base).normalized
        if direction == .zero { direction = CGPoint(x: 1, y: 0) }
        return (length, direction)
    }

    /// Nicer numbers when entering with the mouse: hundredths below 1, then 0.05 / 0.1 / 1.
    private static func roundedFactor(_ f: CGFloat) -> CGFloat {
        let a = abs(f)
        let step: CGFloat = a < 1 ? 0.01 : a < 3 ? 0.05 : a < 10 ? 0.1 : 1
        let rounded = (a / step).rounded() * step
        return (rounded == 0 ? step : rounded) * (f < 0 ? -1 : 1)
    }

    /// Scale from the cursor position: distance / reference length, negative on the opposite side of the base point.
    /// An exact value (entered as a number) is not rounded.
    private func scaleFactor(base: CGPoint, target: CGPoint) -> CGFloat {
        let reference = scaleReference(base: base)
        let d = target - base
        let along = d.dot(reference.direction)
        var factor = hypot(d.x, d.y) / reference.length
        if along < 0 { factor = -factor }
        // an entered number or a point snapped to an object (corner to corner) = an exact value without rounding
        if dynamicInput.lockedValue(0) != nil || activeSnap != nil { return factor }
        return CADEditorView.roundedFactor(factor)
    }

    /// The dashed “1×” circle around the base point.
    private func drawScaleReference(in context: CGContext, transform: CGAffineTransform) {
        guard currentTool == .scale, stage == .points, points.count >= 2, let base = points.first else { return }
        let reference = scaleReference(base: base)
        let center = base.applying(transform)
        let radius = reference.length * viewport.getCurrentZoom()
        guard DrawingSafety.isFinite(center), radius > 2, radius < 20_000 else { return }
        context.saveGState()
        context.setStrokeColor(NSColor.systemTeal.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        context.setLineDash(phase: 0, lengths: [4, 4])
        context.strokeEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        // the “+” direction mark and the 1× / −1× labels
        let tip = (base + reference.direction * reference.length).applying(transform)
        let back = (base - reference.direction * reference.length).applying(transform)
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium),
                                                         .foregroundColor: NSColor.systemTeal]
        ("1×" as NSString).draw(at: CGPoint(x: tip.x + 4, y: tip.y + 2), withAttributes: attributes)
        ("−1×" as NSString).draw(at: CGPoint(x: back.x + 4, y: back.y + 2), withAttributes: attributes)
        context.restoreGState()
    }

    private func transformFor(base: CGPoint, target: CGPoint) -> CGAffineTransform? {
        switch currentTool {
        case .move, .copy, .stretch:
            return CGAffineTransform(translationX: target.x - base.x, y: target.y - base.y)
        case .rotate:
            return Geometry.rotation(by: Geometry.angle(from: base, to: target), around: base)
        case .scale:
            let factor = scaleFactor(base: base, target: target)
            return abs(factor) > 1e-9 ? Geometry.scaling(by: factor, around: base) : nil
        case .mirror:
            return Geometry.mirror(acrossLineFrom: base, to: target)
        default:
            return nil
        }
    }

    // MARK: Points, snap and ortho

    /// Converts the mouse position to a world point (with snap and ortho if the tool is waiting for a point).
    private func resolvedWorldPoint(for event: NSEvent) -> CGPoint {
        let screenPoint = convert(event.locationInWindow, from: nil)
        var worldPoint = viewport.screenToWorld(screenPoint)
        activeSnap = nil
        shiftHeld = event.modifierFlags.contains(.shift)
        snapTracker.clearHit()
        guard expectsPoint else {
            snapTracker.hover(over: nil)
            return worldPoint
        }

        let tolerance = snapTolerance / viewport.getCurrentZoom()
        let reference = points.last ?? dragMoveBase ?? activeGrip?.base
        let cursorPoint = worldPoint
        if snapEnabled, let snap = snapManager.findSnapPoint(near: worldPoint,
                                                             in: entitiesNear(worldPoint, tolerance: tolerance)
                                                                + blockBackgroundNear(worldPoint, tolerance: tolerance),
                                                             tolerance: tolerance, from: reference) {
            activeSnap = snap
            worldPoint = snap.point
            snapTracker.hover(over: snap)
        } else {
            snapTracker.hover(over: nil)
            // the direction ortho / polar keeps from the previous point (snap tracking then stays on it).
            var constraint: CGPoint?
            // GRID: point on the nearest grid node
            if gridSnapEnabled, gridSize > 0 {
                worldPoint = snappedToGrid(worldPoint)
            }
            let drawsRectangle = currentTool == .rectangle || (drawsOutline && outlineShape == .rectangle)
            var angleStepped = false
            if shiftHeld, let pivot = shiftAngleStepPivot {
                // SHIFT in Rotate and at the end of an arc: the angle around the pivot in 15° steps (instead of ortho)
                let d = worldPoint - pivot.center
                let length = hypot(d.x, d.y)
                if length > 0 {
                    let step = 15 * CGFloat.pi / 180
                    let angle = ((atan2(d.y, d.x) - pivot.from) / step).rounded() * step + pivot.from
                    worldPoint = Geometry.pointOnCircle(pivot.center, length, angle)
                    angleStepped = true
                }
            } else if orthoEnabled != shiftHeld, !drawsRectangle, currentTool != .circle, let reference = reference {
                // ORTHO: along the axes of the drawing coordinates
                let d = toUCSVector(worldPoint - reference)
                worldPoint = reference + fromUCSVector(abs(d.x) >= abs(d.y) ? CGPoint(x: d.x, y: 0) : CGPoint(x: 0, y: d.y))
                constraint = worldPoint - reference
            } else if polarEnabled, polarIncrement > 0, !drawsRectangle, let reference = reference {
                // POLAR: angle in steps (from the X axis of the drawing coordinates), distance (with the grid) in grid steps
                let d = worldPoint - reference
                var length = hypot(d.x, d.y)
                if length > 0 {
                    let step = polarIncrement * .pi / 180
                    let angle = ((atan2(d.y, d.x) - ucsAngle) / step).rounded() * step + ucsAngle
                    if gridSnapEnabled, gridSize > 0 { length = max(gridSize, (length / gridSize).rounded() * gridSize) }
                    worldPoint = Geometry.pointOnCircle(reference, length, angle)
                    constraint = worldPoint - reference
                }
            }
            // SNAP TRACKING: line up with the tracked points (horizontally, vertically, at polar angles)
            let directions = SnapTracker.directions(ucsAngle: ucsAngle, polarIncrement: polarEnabled ? polarIncrement : nil)
            if !angleStepped, let aligned = snapTracker.align(cursor: cursorPoint, point: worldPoint, reference: reference,
                                               constraint: constraint, directions: directions, tolerance: tolerance) {
                worldPoint = aligned
            }
        }
        lastRawPoint = worldPoint
        return applyInputLocks(worldPoint)
    }

    /// Shift steps the angle by 15° around this point: the center of rotation in Rotate, the center of an arc
    /// whose end is being placed. `from` is the angle the steps count from (the X axis of the drawing
    /// coordinates, or the start of the arc).
    private var shiftAngleStepPivot: (center: CGPoint, from: CGFloat)? {
        switch currentTool {
        case .rotate:
            guard stage == .points, points.count == 1 else { return nil }
            return (points[0], ucsAngle)
        case .arc:
            guard points.count == 2, arcMethod.knowsCenter else { return nil }
            let center = arcMethod.startFirst ? points[1] : points[0]
            let start = arcMethod.startFirst ? points[0] : points[1]
            return (center, Geometry.angle(from: center, to: start))
        default:
            return nil
        }
    }

    /// The nearest editable entity within tolerance, optionally with a filter.
    private func entity(at worldPoint: CGPoint, where filter: (CADEntity) -> Bool = { _ in true }) -> CADEntity? {
        let tolerance = worldTolerance
        var best: CADEntity?
        var bestDistance = tolerance
        // in draw order: at equal distance the object on top wins
        let locked = layerManager
        for entity in entitiesNear(worldPoint, tolerance: tolerance) where filter(entity) {
            if locked?.isLayerLocked(entity.layer) ?? false { continue }
            var d = entity.distance(to: worldPoint)
            // a click inside a hatch (an image, a wipeout) selects it, but the lines inside it take priority
            if (entity is HatchEntity || entity is ImageEntity || entity is WipeoutEntity) && d == 0 { d = tolerance * 0.95 }
            if d <= bestDistance {
                bestDistance = d
                best = entity
            }
        }
        return best
    }

    // MARK: Point entry

    private func addPoint(_ point: CGPoint, clickCount: Int = 1) {
        if pasteRequest != nil {
            finishPaste(at: point)
            return
        }
        switch currentTool {
        case .xline:
            addConstructionLine(at: point)

        case .revisionCloud, .wipeout:
            addOutlinePoint(point, clickCount: clickCount)

        case .wall:
            addWallPoint(point, clickCount: clickCount)

        case .polyline, .spline, .leader:
            // a double-click finishes
            if clickCount >= 2 {
                requestFinishOpenEnded()
                return
            }
            // a click on the first point closes the polyline / spline
            if currentTool != .leader, points.count >= 3,
               Geometry.distance(viewport.worldToScreen(point), viewport.worldToScreen(points[0])) < 8 {
                finishOpenEnded(closed: true)
                return
            }
            if let last = points.last, Geometry.distance(last, point) < 1e-9 { return }
            points.append(point)
            stateChanged()

        default:
            guard let required = currentTool.requiredPoints, required > 0 else { return }
            // Scale: a scale entered as a number right after the base point – without a reference point
            if currentTool == .scale, points.count == 1, dynamicInput.lockedValue(0) != nil {
                finishTransform(target: point)
                return
            }
            if points.count + 1 >= required {
                finishPoints(with: point)
            } else {
                if let last = points.last, Geometry.distance(last, point) < 1e-9 { return }
                points.append(point)
                stateChanged()
            }
        }
    }

    /// Finishes a tool with a fixed number of points.
    private func finishPoints(with end: CGPoint) {
        if currentTool.isTransform {
            finishTransform(target: end)
            return
        }
        switch currentTool {
        case .blockCreate:
            finishBlockCreate(base: end)
            return
        case .blockInsert, .xref:
            finishBlockInsert(at: end)
            return
        case .scaleBar, .northArrow:
            finishSymbol(at: end)
            return
        case .image:
            finishImage(at: end)
            return
        default:
            break
        }
        let created = makeEntities(with: end, final: true)
        // dimensions snapped to objects are associative – they follow their changes
        for case let dimension as DimensionEntity in created {
            Associativity.attach(dimension, to: snapEntities, measured: picked.first?.entity)
        }
        if !created.isEmpty {
            onCommit?([], created, "Add \(currentTool.title)")
        }
        // the most recently created linear / aligned dimension – a chained dimension continues from it
        if let dimension = created.first as? DimensionEntity, dimension.kind == .linear || dimension.kind == .aligned {
            lastChainableDimension = dimension
        }
        // LINECONT: the next line starts at the end of the one just drawn
        if currentTool == .line && lineContinue && !created.isEmpty, let start = points.first {
            if lineChainStart == nil { lineChainStart = start }
            lineChainCount += 1
            points = [end]
            stateChanged()
            return
        }
        points.removeAll()
        picked.removeAll()
        stateChanged()
    }

    /// Ends the chain of continuous lines.
    private func endLineChain() {
        points.removeAll()
        lineChainStart = nil
        lineChainCount = 0
        stateChanged()
    }

    /// Finishing a polyline / spline: possibly asks first whether to close the shape.
    private func requestFinishOpenEnded() {
        guard [.polyline, .spline].contains(currentTool), points.count >= 3, askToClose else {
            finishOpenEnded(closed: false)
            return
        }
        awaitingCloseAnswer = true
        dynamicInput.reset()
        dynamicInput.isHidden = true
        closePrompt.configure(question: "Close the \(currentTool.title.lowercased())?", askEveryTime: askToClose)

        // the panel at the last point (or the cursor), so it doesn't cover the drawing more than necessary
        let anchor = viewport.worldToScreen(currentWorldPoint ?? points[points.count - 1])
        let size = closePrompt.frame.size
        var origin = CGPoint(x: anchor.x + 22, y: anchor.y - size.height - 22)
        if !origin.x.isFinite || !origin.y.isFinite { origin = CGPoint(x: 8, y: 8) }
        origin.x = min(max(4, origin.x), max(4, bounds.width - size.width - 4))
        origin.y = min(max(4, origin.y), max(4, bounds.height - size.height - 4))
        closePrompt.setFrameOrigin(origin)
        closePrompt.isHidden = false
        onPromptChanged?(prompt)
        needsDisplay = true
    }

    private func answerClosePrompt(_ close: Bool) {
        awaitingCloseAnswer = false
        closePrompt.isHidden = true
        window?.makeFirstResponder(self)
        finishOpenEnded(closed: close)
    }

    /// Esc in the question: back to drawing (the points stay).
    private func cancelClosePrompt() {
        awaitingCloseAnswer = false
        closePrompt.isHidden = true
        stateChanged()
    }

    /// Finishes a polyline, spline or leader.
    private func finishOpenEnded(closed: Bool) {
        let layer = currentLayerName
        defer {
            points.removeAll()
            stateChanged()
        }
        guard points.count >= 2 else { return }

        switch currentTool {
        case .polyline:
            onCommit?([], [Polyline(vertices: points, closed: closed && points.count >= 3, layer: layer)], "Add Polyline")
        case .spline:
            onCommit?([], [Spline(controlPoints: points, closed: closed && points.count >= 3, layer: layer)], "Add Spline")
        case .leader:
            guard let text = askForText(title: "Leader – Text", message: "Text of the leader:") else { return }
            let leader = styled(DimensionEntity(kind: .leader, points: points, text: text, textHeight: dimensionTextHeight, layer: layer))
            Associativity.attach(leader, to: snapEntities)
            onCommit?([], [leader], "Add Leader")
        default:
            break
        }
    }

    /// Selected objects that are not on a locked layer.
    private var movableSelection: [CADEntity] {
        return selectedEntities.filter { !(layerManager?.isLayerLocked($0.layer) ?? false) }
    }

    /// Finishes dragging the selected objects in selection mode.
    private func finishDragMove(from base: CGPoint, to target: CGPoint) {
        let originals = movableSelection
        guard !originals.isEmpty, Geometry.distance(base, target) > 1e-12 else { return }
        let t = CGAffineTransform(translationX: target.x - base.x, y: target.y - base.y)
        let moved = originals.map { entity -> CADEntity in
            let copy = entity.clone()
            copy.applyTransform(t)
            return copy
        }
        onCommit?(originals, moved, "Move")
        selectionManager?.select(moved)
    }

    /// The answer to “Delete originals?” for Mirror.
    private func answerMirror(deleteOriginals: Bool) {
        guard let pending = pendingMirror else { return }
        pendingMirror = nil
        if deleteOriginals {
            onCommit?(pending.originals, pending.copies, "Mirror")
            selectionManager?.select(pending.copies)
            onMessage?("Mirrored – originals deleted")
        } else {
            onCommit?([], pending.copies, "Mirror")
            onMessage?("Mirrored – originals kept")
        }
        stateChanged()
    }

    private func finishTransform(target: CGPoint) {
        if currentTool == .stretch {
            finishStretch(target: target)
            return
        }
        if currentTool == .array {
            points.removeAll()
            openArrayDialog(center: target)
            return
        }
        guard let base = points.first, let t = transformFor(base: base, target: target) else {
            onMessage?("Invalid point for \(currentTool.title.lowercased()).")
            return
        }
        let originals = selectedEntities.filter { !(layerManager?.isLayerLocked($0.layer) ?? false) }
        guard !originals.isEmpty else {
            onMessage?("Nothing selected (or all selected objects are on locked layers).")
            resetToolState()
            return
        }
        let transformed = originals.map { entity -> CADEntity in
            let copy = entity.clone()
            copy.applyTransform(t)
            return copy
        }

        switch currentTool {
        case .copy:
            onCommit?([], transformed, "Copy")
            points = [base]      // another copy from the same base point
            stateChanged()
            return
        case .mirror:
            // question in the bottom row: delete originals?
            pendingMirror = (transformed, originals)
            points.removeAll()
            stateChanged()
            return
        default:
            onCommit?(originals, transformed, currentTool.title)
            selectionManager?.select(transformed)
        }
        points.removeAll()
        stateChanged()
    }

    // MARK: Dynamic value entry

    /// Which fields are offered in the box at the cursor.
    private var inputMode: DynamicInputMode {
        guard !awaitingCloseAnswer else { return .none }
        if pasteRequest != nil { return .coordinates }
        if dragMoveBase != nil || activeGrip != nil { return .distanceAngle }
        switch currentTool {
        case .select, .trim, .extend, .powerTrim, .breakObject, .breakAtPoint, .dimRadius, .dimDiameter, .editPoints, .text, .measure, .roomLabel: return .none
        case .fillet: return .filletRadius
        case .chamfer: return .chamferDistances
        case .hatch: return .hatchSettings
        case .offset: return .offsetDistance
        default: break
        }
        guard expectsPoint else { return .none }
        if points.isEmpty { return .coordinates }
        switch currentTool {
        case .line, .polyline, .spline, .wall, .leader, .xline: return .lengthAngle
        case .circle: return .radius
        case .polygon: return .polygon(polygonMethod)
        case .ellipse: return points.count == 1 ? .lengthAngle : .radius
        case .stretch: return .distanceAngle
        case .arc:
            switch arcMethod {
            case .threePoint: return .coordinates
            case .startEndRadius: return points.count == 1 ? .lengthAngle : .radius
            case .startEndAngle: return points.count == 1 ? .lengthAngle : .includedAngle
            case .startCenterEnd, .startCenterAngle: return points.count == 1 ? .coordinates : .includedAngle
            case .centerStartEnd, .centerStartAngle: return points.count == 1 ? .radius : .includedAngle
            }
        case .rectangle: return .widthHeight
        case .revisionCloud, .wipeout: return outlineShape == .rectangle ? .widthHeight : .lengthAngle
        case .move, .copy: return .distanceAngle
        case .rotate, .mirror: return .angle
        case .scale: return .factor
        case .dimLinear, .dimAligned, .dimAngular: return .coordinates
        default: return .none
        }
    }

    private static func degrees(_ radians: CGFloat) -> CGFloat {
        return Geometry.normalizeAngle(radians) * 180 / .pi
    }

    /// Adjusts the point under the cursor according to the entered (locked) values.
    private func applyInputLocks(_ p: CGPoint) -> CGPoint {
        guard dynamicInput.hasLockedValue else { return p }
        let first = dynamicInput.lockedValue(0)
        let second = dynamicInput.lockedValue(1)
        let tiny: CGFloat = 1e-12

        switch inputMode {
        case .coordinates:
            // coordinates are entered in drawing coordinates
            let u = toUCS(p)
            return fromUCS(CGPoint(x: first ?? u.x, y: second ?? u.y))

        case .lengthAngle, .distanceAngle, .polygon:
            guard let reference = points.last ?? dragMoveBase ?? activeGrip?.base else { return p }
            let d = Geometry.distance(reference, p)
            let length = first ?? d
            let angle = second.map { $0 * .pi / 180 + ucsAngle } ?? (d > tiny ? Geometry.angle(from: reference, to: p) : 0)
            return Geometry.pointOnCircle(reference, length, angle)

        case .radius:
            if currentTool == .ellipse, points.count >= 2 {
                // minor semi-axis perpendicular to the major axis, on the cursor's side
                let u = (points[1] - points[0]).normalized.perpendicular
                guard u != .zero else { return p }
                let along = (p - points[0]).dot(u)
                let b = first.map { abs($0) } ?? abs(along)
                return points[0] + u * (along >= 0 ? b : -b)
            }
            if currentTool == .arc && arcMethod == .startEndRadius {
                // arc by start and end with the given radius (the smaller arc, bulging toward the cursor)
                guard points.count >= 2, var r = first else { return p }
                let halfChord = Geometry.distance(points[0], points[1]) / 2
                r = max(abs(r), halfChord)
                return arcPointWithSagitta(r - sqrt(max(0, r * r - halfChord * halfChord)), cursor: p) ?? p
            }
            guard let center = points.first else { return p }
            let d = Geometry.distance(center, p)
            let angle = d > tiny ? Geometry.angle(from: center, to: p) : 0
            return Geometry.pointOnCircle(center, first ?? d, angle)

        case .includedAngle:
            guard let sweepDegrees = first else { return p }
            if currentTool == .arc && arcMethod == .startEndAngle {
                guard points.count >= 2 else { return p }
                let halfChord = Geometry.distance(points[0], points[1]) / 2
                let theta = min(max(abs(sweepDegrees), 0.01), 359.99) * .pi / 180
                return arcPointWithSagitta(halfChord * tan(theta / 4), cursor: p) ?? p
            }
            guard let arc = arcCenterAndStart else { return p }
            let r = Geometry.distance(arc.center, arc.start)
            let start = Geometry.angle(from: arc.center, to: arc.start)
            return Geometry.pointOnCircle(arc.center, r, start + sweepDegrees * .pi / 180)

        case .widthHeight:
            guard let corner = points.first else { return p }
            let d = toUCSVector(p - corner)
            // from the center the cursor is at a corner – an entered width or height is the whole side, so half of it
            let part: CGFloat = currentTool == .rectangle && rectangleFromCenter ? 0.5 : 1
            var w = first.map { ($0 < 0 ? $0 : $0 * (d.x < 0 ? -1 : 1)) * part } ?? d.x
            var h = second.map { ($0 < 0 ? $0 : $0 * (d.y < 0 ? -1 : 1)) * part } ?? d.y
            // a square: one entered side gives the other
            if currentTool == .rectangle && rectangleIsSquare {
                if first != nil && second == nil { h = abs(w) * (d.y < 0 ? -1 : 1) }
                if second != nil && first == nil { w = abs(h) * (d.x < 0 ? -1 : 1) }
            }
            return corner + fromUCSVector(CGPoint(x: w, y: h))

        case .angle:
            guard let base = points.first, let angle = first else { return p }
            let r = max(Geometry.distance(base, p), 1)
            return Geometry.pointOnCircle(base, r, angle * .pi / 180 + ucsAngle)

        case .factor:
            guard let base = points.first, let factor = first, factor != 0 else { return p }
            let reference = scaleReference(base: base)
            return base + reference.direction * (factor * reference.length)

        case .filletRadius, .chamferDistances, .hatchSettings, .offsetDistance, .none:
            return p
        }
    }

    /// Values under the cursor that are shown in unlocked fields.
    private func liveInputValues(_ p: CGPoint, mode: DynamicInputMode) -> [CGFloat] {
        switch mode {
        case .coordinates:
            let u = toUCS(p)
            return [u.x, u.y]
        case .lengthAngle, .distanceAngle:
            guard let reference = points.last ?? dragMoveBase ?? activeGrip?.base else { return [] }
            return [Geometry.distance(reference, p), CADEditorView.degrees(Geometry.angle(from: reference, to: p) - ucsAngle)]
        case .polygon:
            guard let reference = points.last else { return [] }
            return [Geometry.distance(reference, p), CADEditorView.degrees(Geometry.angle(from: reference, to: p) - ucsAngle),
                    CGFloat(polygonSides)]
        case .radius:
            if currentTool == .ellipse, points.count >= 2 {
                let u = (points[1] - points[0]).normalized.perpendicular
                return [abs((p - points[0]).dot(u))]
            }
            if currentTool == .arc && arcMethod == .startEndRadius {
                guard points.count >= 2, let circle = Geometry.circleThrough(points[0], p, points[1]) else { return [] }
                return [circle.radius]
            }
            guard let center = points.first else { return [] }
            return [Geometry.distance(center, p)]
        case .includedAngle:
            if currentTool == .arc && arcMethod == .startEndAngle {
                guard points.count >= 2,
                      let arc = CADEditorView.arcThrough(points[0], p, points[1], layer: "0") else { return [] }
                return [arc.sweep * 180 / .pi]
            }
            guard let arc = arcCenterAndStart else { return [] }
            let start = Geometry.angle(from: arc.center, to: arc.start)
            return [Geometry.ccwDelta(from: start, to: Geometry.angle(from: arc.center, to: p)) * 180 / .pi]
        case .widthHeight:
            guard let corner = points.first else { return [] }
            var d = currentTool == .rectangle ? rectangleDiagonal(from: corner, to: p).diagonal : toUCSVector(p - corner)
            if drawsOutline && squareByShift { d = CADEditorView.squared(d) }
            return [abs(d.x), abs(d.y)]
        case .angle:
            guard let base = points.first else { return [] }
            return [CADEditorView.degrees(Geometry.angle(from: base, to: p) - ucsAngle)]
        case .factor:
            // before the reference point is chosen the scale is not derived from the cursor (only entered as a number)
            guard let base = points.first, points.count >= 2 else { return [] }
            return [scaleFactor(base: base, target: p)]
        case .filletRadius:
            return [filletRadius]
        case .chamferDistances:
            return [chamferFirst, chamferSecond]
        case .offsetDistance:
            if let distance = offsetDistance { return [distance] }
            guard let source = picked.first?.entity else { return [0] }
            return [EditOperations.offsetDistance(of: source, to: p)]
        case .hatchSettings:
            return [currentHatchAngle, currentHatchScale]
        case .none:
            return []
        }
    }

    /// Shows/hides the box at the cursor and updates the values in it.
    private func updateDynamicInput() {
        let mode = inputMode
        guard mode != .none, let cursor = currentWorldPoint ?? lastRawPoint else {
            dynamicInput.configure(labels: [])
            dynamicInput.isHidden = true
            return
        }
        dynamicInput.configure(labels: mode.labels, hint: dynamicInputHint)
        // only while typing: the box appears once you type into it (or an entered value remains in it)
        if !valueBoxAlways && !valueBoxRequested && !dynamicInput.hasLockedValue && !dynamicInput.isEditing {
            dynamicInput.isHidden = true
            return
        }
        dynamicInput.isHidden = false
        dynamicInput.setLiveValues(liveInputValues(cursor, mode: mode))

        let size = dynamicInput.frame.size
        let screen = viewport.worldToScreen(cursor)
        var origin = CGPoint(x: screen.x + 22, y: screen.y - size.height - 22)
        if !origin.x.isFinite || !origin.y.isFinite { origin = CGPoint(x: 8, y: 8) }
        origin.x = min(max(4, origin.x), max(4, bounds.width - size.width - 4))
        origin.y = min(max(4, origin.y), max(4, bounds.height - size.height - 4))
        dynamicInput.setFrameOrigin(origin)
    }

    /// Hint in the box at the cursor – which letter does something right now.
    private var dynamicInputHint: String? {
        if currentTool == .polygon {
            return "I / C / E = method · S = sides"
        }
        if currentTool == .rectangle {
            return "C = from center · S or Shift = square"
        }
        if [.polyline, .spline].contains(currentTool) && points.count >= 3 {
            return "C = close the \(currentTool == .spline ? "spline" : "polyline")"
        }
        if currentTool == .line && lineContinue && lineChainCount >= 2 {
            return "C = close back to the start"
        }
        if currentTool == .wall {
            return "T = thickness · J = side" + (points.count >= 3 ? " · C = close" : "")
        }
        if currentTool == .xline {
            return "H / V / A / B = direction"
        }
        if drawsOutline {
            let arcSize = currentTool == .revisionCloud ? " · A = arc size" : ""
            if outlineShape == .rectangle { return "P = by corners" + arcSize }
            return "R = rectangle" + arcSize + (points.count >= 3 ? " · C = close" : "")
        }
        return nil
    }

    /// A letter typed into the box: C closes the polyline / spline (or the continuous lines).
    private func handleInputLetter(_ letter: String) -> Bool {
        if currentTool == .xline { return switchXLineKind(letter: letter) }
        if currentTool == .polygon { return polygonLetter(letter) }
        if currentTool == .rectangle { return rectangleLetter(letter) }
        if drawsOutline { return outlineLetter(letter) }
        if currentTool == .wall { return wallLetter(letter) }
        guard letter == "c" else { return false }
        if [.polyline, .spline].contains(currentTool), points.count >= 3 {
            finishOpenEnded(closed: true)
            return true
        }
        if currentTool == .line, lineContinue, lineChainCount >= 2, let start = lineChainStart, let last = points.last {
            onCommit?([], [Line(start: last, end: start, layer: currentLayerName)], "Close Lines")
            endLineChain()
            return true
        }
        return false
    }

    /// The user changed a value in the box → recompute the preview.
    private func dynamicInputChanged() {
        if let raw = lastRawPoint, expectsPoint {
            currentWorldPoint = applyInputLocks(raw)
        }
        updateDynamicInput()
        needsDisplay = true
    }

    /// Enter in the box: uses the entered values as the next point (or the fillet radius).
    private func commitDynamicInput() {
        // after confirming, the box hides again in the “only while typing” mode
        defer {
            if !dynamicInput.hasInvalidField {
                valueBoxRequested = false
                updateDynamicInput()
            }
        }
        if dynamicInput.hasInvalidField {
            onMessage?("\u{201C}\(dynamicInput.invalidFieldText ?? "")\u{201D} is not a valid number or expression.")
            return
        }
        let mode = inputMode

        if mode == .hatchSettings {
            if let angle = dynamicInput.lockedValue(0) { hatchAngle = angle }
            if let scale = dynamicInput.lockedValue(1) {
                if scale > 0 { hatchScale = scale } else { onMessage?("The scale must be greater than 0.") }
            }
            onMessage?("Hatch: angle \(LineType.formatAngle(currentHatchAngle))°, scale \(DynamicInputView.format(currentHatchScale))")
            window?.makeFirstResponder(self)
            stateChanged()
            return
        }

        if mode == .offsetDistance {
            if let distance = dynamicInput.lockedValue(0) {
                if distance > 0 {
                    offsetDistance = distance
                    onMessage?("Offset distance \(DynamicInputView.format(distance))")
                } else if distance == 0 {
                    offsetDistance = nil
                    onMessage?("Offset through a point")
                } else {
                    onMessage?("The distance cannot be negative.")
                }
            }
            window?.makeFirstResponder(self)
            stateChanged()
            updateOffsetPreview()
            return
        }

        if case .polygon = mode, let typed = dynamicInput.lockedValue(2) {
            // an expression is allowed, but the result must be a whole number
            if let sides = Int(exactly: typed.rounded()), abs(typed - typed.rounded()) < 1e-9,
               sides >= RegularPolygon.minimumSides && sides <= RegularPolygon.maximumSides {
                polygonSides = sides
            } else {
                onMessage?(polygonSidesError(DynamicInputView.format(typed)))
            }
            // only the number of sides → no point is entered yet
            if dynamicInput.lockedValue(0) == nil && dynamicInput.lockedValue(1) == nil {
                dynamicInput.reset()
                window?.makeFirstResponder(self)
                onMessage?("Polygon: \(polygonSides) sides")
                stateChanged()
                return
            }
        }

        if mode == .chamferDistances {
            let first = dynamicInput.lockedValue(0)
            let second = dynamicInput.lockedValue(1)
            if first != nil || second != nil {
                // one entered value = both distances the same
                let a = first ?? second ?? 0
                let b = second ?? first ?? 0
                if a >= 0 && b >= 0 {
                    chamferFirst = a
                    chamferSecond = b
                    onMessage?("Chamfer distances set to \(DynamicInputView.format(a)) and \(DynamicInputView.format(b))")
                } else {
                    onMessage?("The distances cannot be negative.")
                }
            }
            window?.makeFirstResponder(self)
            stateChanged()
            return
        }

        if mode == .filletRadius {
            if let radius = dynamicInput.lockedValue(0) {
                if radius >= 0 {
                    filletRadius = radius
                    onMessage?("Fillet radius set to \(DynamicInputView.format(radius))")
                } else {
                    onMessage?("The radius cannot be negative.")
                }
            }
            window?.makeFirstResponder(self)
            stateChanged()
            return
        }

        // grip: entered distance / angle from the grip's original position
        if activeGrip != nil {
            if dynamicInput.hasLockedValue, let raw = lastRawPoint ?? currentWorldPoint {
                let point = applyInputLocks(raw)
                window?.makeFirstResponder(self)
                dynamicInput.reset()
                finishGrip(at: point)
            } else {
                window?.makeFirstResponder(self)
            }
            return
        }

        // pasted objects: ↩ without a typed value places them at the cursor
        if pasteRequest != nil && !dynamicInput.hasLockedValue {
            window?.makeFirstResponder(self)
            dynamicInput.reset()
            if let point = currentWorldPoint { finishPaste(at: point) }
            return
        }

        guard dynamicInput.hasLockedValue, mode != .none, dragMoveBase == nil else {
            window?.makeFirstResponder(self)
            dynamicInput.reset()
            confirm()
            return
        }

        let raw = lastRawPoint ?? currentWorldPoint ?? points.last ?? .zero
        let point = applyInputLocks(raw)
        window?.makeFirstResponder(self)
        addPoint(point)
        currentWorldPoint = raw
        stateChanged()
    }

    /// Esc in the box: discards the entered values and returns control to the drawing area.
    private func cancelDynamicInput() {
        valueBoxRequested = false
        dynamicInput.reset()
        window?.makeFirstResponder(self)
        if let raw = lastRawPoint { currentWorldPoint = raw }
        updateDynamicInput()
        needsDisplay = true
    }

    // MARK: Confirmation (Enter / right click)

    private func confirm() {
        switch currentTool {
        case .line:
            if !points.isEmpty { endLineChain() }
        case .polyline, .spline, .leader:
            requestFinishOpenEnded()
        case .wall:
            if points.count >= 2 {
                finishWall(closed: false)
            } else if !points.isEmpty {
                onMessage?("A wall needs at least two points.")
            }
        case .revisionCloud, .wipeout:
            if outlineShape == .polygon && points.count >= 3 {
                finishOutline(points)
            } else if !points.isEmpty {
                onMessage?(outlineShape == .polygon ? "The outline needs at least three corners." : "Click the opposite corner of the rectangle.")
            }
        case .trim, .extend:
            onToolChangeRequested?(.select)
        case .move, .copy, .rotate, .scale, .mirror:
            if stage == .selectObjects {
                if selectionManager?.isEmpty ?? true {
                    onMessage?("Select at least one object first.")
                } else {
                    stage = .points
                    stateChanged()
                }
            } else if currentTool == .copy {
                onToolChangeRequested?(.select)
            }
        case .explode, .join, .hatchRebuild, .hatchCut:
            if selectionManager?.isEmpty ?? true {
                onMessage?("Select at least one object first.")
            } else {
                runSelectionCommand()
            }
        case .wallFromCurve:
            finishWallFromCurve()
        case .measure:
            if measureKind == .areaPoints && points.count >= 3 { finishMeasuredArea() }
        case .dimContinue, .matchProperties, .xline:
            onToolChangeRequested?(.select)
        case .blockCreate:
            if stage == .selectObjects {
                if selectionManager?.isEmpty ?? true {
                    onMessage?("Select the objects for the block first.")
                } else {
                    stage = .points
                    stateChanged()
                }
            }
        case .array:
            if stage == .selectObjects {
                if selectionManager?.isEmpty ?? true {
                    onMessage?("Select at least one object first.")
                } else if arrayKind == .rectangular {
                    stage = .points
                    stateChanged()
                    openArrayDialog(center: nil)
                } else {
                    stage = .points
                    stateChanged()
                }
            } else if arrayKind == .rectangular {
                openArrayDialog(center: nil)
            }
        default:
            break
        }
    }

    /// Explode / Join on the selected objects; then back to Select with the result selected.
    private func runSelectionCommand() {
        guard DrawingTool.selectionCommands.contains(currentTool), let selectionManager = selectionManager else { return }
        let selected = selectedEntities.filter { !(layerManager?.isLayerLocked($0.layer) ?? false) }
        guard !selected.isEmpty else { return }
        if currentTool == .hatchRebuild || currentTool == .hatchCut {
            let rebuild = currentTool == .hatchRebuild
            onToolChangeRequested?(.select)     // first back to Select (the selection stays), then the result message
            if rebuild { rebuildSelectedHatches() } else { subtractFromSelectedHatches() }
            return
        }
        var removed: [CADEntity] = []
        var added: [CADEntity] = []
        let message: String
        if currentTool == .explode {
            for entity in selected {
                guard let parts = EditOperations.explode(entity) else { continue }
                removed.append(entity)
                added.append(contentsOf: parts)
            }
            message = removed.isEmpty
                ? "Nothing to explode – only polylines, rectangles and blocks can be exploded."
                : "Exploded \(removed.count) object\(removed.count == 1 ? "" : "s") into \(added.count) object\(added.count == 1 ? "" : "s")"
        } else {
            let result = EditOperations.join(selected)
            removed = result.removed
            added = result.added
            message = removed.isEmpty
                ? "Nothing to join – select lines, arcs or open polylines whose ends touch."
                : "Joined \(removed.count) object\(removed.count == 1 ? "" : "s") into \(added.count) polyline\(added.count == 1 ? "" : "s")"
        }
        let name = currentTool.title
        if !removed.isEmpty {
            onCommit?(removed, added, name)
            selectionManager.select(added)
        }
        onToolChangeRequested?(.select)
        onMessage?(message)
    }

    // MARK: Edits (Trim, Extend, PowerTrim, Fillet)

    private var cuttingEdges: [CADEntity] {
        // an edge that left the drawing (Undo, an edit) no longer cuts
        edges.removeAll { !(document?.contains($0) ?? false) }
        return edges.isEmpty ? visibleEntities : edges
    }

    /// A trimmed or extended cutting edge stays a cutting edge in its new form.
    private func replaceEdge(_ old: CADEntity, with new: [CADEntity]) {
        guard let index = edges.firstIndex(where: { $0 === old }) else { return }
        edges.replaceSubrange(index...index, with: new)
    }

    private func trimClick(at point: CGPoint) {
        guard let target = entity(at: point, where: { EditOperations.isTrimmable($0) }) else {
            onMessage?("No object here.")
            return
        }
        if let pieces = EditOperations.trimAny(target, at: point, edges: cuttingEdges)?.kept {
            onCommit?([target], pieces, "Trim")
            replaceEdge(target, with: pieces)
        } else {
            onMessage?("Nothing to trim – the object does not cross any cutting edge.")
        }
    }

    private func extendClick(at point: CGPoint) {
        guard let target = entity(at: point, where: { CADEditorView.isExtendable($0) }) else {
            onMessage?("Click a line, an arc or an open polyline.")
            return
        }
        if let extended = EditOperations.extend(target, near: point, boundaries: cuttingEdges) {
            onCommit?([target], [extended], "Extend")
            replaceEdge(target, with: [extended])
        } else {
            onMessage?("No boundary found in that direction.")
        }
    }

    private func powerTrimFence(_ screenPoints: [CGPoint]) {
        let world = screenPoints.map { viewport.screenToWorld($0) }
        guard world.count >= 2 else { return }
        var fencePrimitives: [Primitive] = []
        for i in 0..<(world.count - 1) {
            fencePrimitives.append(.segment(a: world[i], b: world[i + 1], param: 0))
        }

        let edgeList = visibleEntities
        var removed: [CADEntity] = []
        var added: [CADEntity] = []
        for curve in editableEntities where EditOperations.isTrimmable(curve) {
            var crossings: [CGPoint] = []
            for a in curve.primitives() {
                for f in fencePrimitives {
                    crossings.append(contentsOf: a.intersections(with: f).map { $0.point })
                }
            }
            guard !crossings.isEmpty,
                  let pieces = EditOperations.trim(curve, atPoints: crossings, edges: edgeList,
                                                   tolerance: worldTolerance) else { continue }
            removed.append(curve)
            added.append(contentsOf: pieces)
        }
        if removed.isEmpty {
            onMessage?("Nothing was trimmed.")
        } else {
            onCommit?(removed, added, "PowerTrim")
        }
    }

    // MARK: Hatch

    /// The region graph is built only when the drawing, the visible layers or the zoom change significantly.
    /// Changes when a block's content changes – inserted blocks then give the finders new edges.
    private var blockSignature: Int {
        return blockLibrary?.definitions.reduce(0) { $0 &+ $1.version &+ $1.entities.count } ?? 0
    }

    private func currentHatchFinder() -> HatchRegionFinder {
        let entities = visibleEntities.filter { !($0 is HatchEntity) && !($0 is DimensionEntity) }
        var signature = entities.count &+ blockSignature
        for entity in entities { signature = signature &* 31 &+ entity.id.hashValue }
        let zoomBucket = Int((log2(viewport.getCurrentZoom())).rounded())
        let key = "\(signature)|\(zoomBucket)"
        if let finder = hatchFinder, key == hatchFinderKey { return finder }
        let zoom = viewport.getCurrentZoom()
        let finder = HatchRegionFinder(entities: entities, gap: 3 / zoom, flatness: 0.25 / zoom)
        hatchFinder = finder
        hatchFinderKey = key
        return finder
    }

    // MARK: Hatch edits – new boundary and cut-out

    /// The selected hatches get the outline of the area they lie in (after jambs, openings… are drawn in).
    func rebuildSelectedHatches() {
        guard let layerManager = layerManager else { return }
        let hatches = selectedEntities.compactMap { $0 as? HatchEntity }.filter { !layerManager.isLayerLocked($0.layer) }
        guard !hatches.isEmpty else {
            onMessage?("Select the hatch first, then choose Rebuild Hatch.")
            NSSound.beep()
            return
        }
        hatchFinder = nil
        let finder = currentHatchFinder()
        var removed: [CADEntity] = []
        var added: [CADEntity] = []
        var failed = 0
        for hatch in hatches {
            guard let point = HatchEntity.interiorPoint(of: hatch.loops), let loops = finder.region(at: point) else {
                failed += 1
                continue
            }
            let copy = hatch.clone() as! HatchEntity
            copy.loops = loops
            removed.append(hatch)
            added.append(copy)
        }
        if !added.isEmpty {
            onCommit?(removed, added, "Rebuild Hatch")
            selectionManager?.select(added)
        }
        onMessage?(failed == 0
            ? "Hatch rebuilt from the boundaries around it"
            : failed == 1 ? "1 hatch not rebuilt – no closed boundary around it (a gap over 3 px?)"
            : "\(failed) hatches not rebuilt – no closed boundary around them (gaps over 3 px?)")
        if failed > 0 { NSSound.beep() }
    }

    /// The selected closed shapes (rectangle, polyline, circle…) are cut out of the selected hatches.
    /// A shape across the edge trims or splits the hatch, a shape inside makes an island.
    func subtractFromSelectedHatches() {
        guard let layerManager = layerManager else { return }
        let selected = selectedEntities
        let hatches = selected.compactMap { $0 as? HatchEntity }.filter { !layerManager.isLayerLocked($0.layer) }
        let cutters = selected.filter { ($0 as? CurveEntity)?.isClosedCurve ?? false }
        guard !hatches.isEmpty, !cutters.isEmpty else {
            onMessage?("Select the hatch and one or more closed shapes (rectangle, closed polyline, circle), then choose Cut Out of Hatch.")
            NSSound.beep()
            return
        }
        let zoom = viewport.getCurrentZoom()
        var removed: [CADEntity] = []
        var added: [CADEntity] = []
        for hatch in hatches {
            let box = hatch.boundingBox()
            let relevant = cutters.filter { $0.boundingBox().intersects(box) }
            guard !relevant.isEmpty else { continue }
            let outline: [CADEntity] = hatch.loops.map { Polyline(vertices: $0, closed: true, bulges: [], layer: hatch.layer) }
            let finder = HatchRegionFinder(entities: outline + relevant, gap: 0.5 / zoom, flatness: 0.25 / zoom)
            let cutterPaths = relevant.map { $0.makePath() }
            let faces = finder.boundedFaces
            var pieces: [[[CGPoint]]] = []
            var seen = Set<String>()
            for (index, face) in faces.enumerated() {
                // a point inside the area, but outside the areas nested in it
                let faceBox = HatchEntity.box(of: face)
                let nested = faces.enumerated().filter { other in
                    other.offset != index && faceBox.contains(HatchEntity.box(of: other.element))
                        && other.element.first.map { HatchEntity.pointInPolygon($0, face) } == true
                }.map { $0.element }
                guard let point = HatchEntity.interiorPoint(of: [face] + nested),
                      hatch.contains(point),
                      !cutterPaths.contains(where: { $0.contains(point, using: .evenOdd) }),
                      let loops = finder.region(at: point), let outer = loops.first, let first = outer.first else { continue }
                let key = "\(outer.count)|\(Int((first.x * 1000).rounded()))|\(Int((first.y * 1000).rounded()))"
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                pieces.append(loops)
            }
            removed.append(hatch)
            for loops in pieces {
                let copy = hatch.clone() as! HatchEntity
                copy.loops = loops
                added.append(copy)
            }
        }
        guard !removed.isEmpty else {
            onMessage?("The shapes don't touch the hatch.")
            NSSound.beep()
            return
        }
        onCommit?(removed, added, "Cut Out of Hatch")
        selectionManager?.select(added)
        onMessage?(added.isEmpty ? "The whole hatch was cut away"
            : "Cut out – \(added.count) hatch piece\(added.count == 1 ? "" : "s") (the shapes stay, delete them if not needed)")
    }

    private func updateHatchHover(at point: CGPoint) {
        let loops = currentHatchFinder().region(at: point)
        // a different area = a different number of loops, points or a different first point of some loop (offset shapes often have
        // the same number of points – comparing just the counts would leave the previous area's preview on screen)
        func signature(_ loops: [[CGPoint]]?) -> [CGFloat] {
            guard let loops = loops else { return [] }
            return loops.flatMap { loop -> [CGFloat] in [CGFloat(loop.count), loop.first?.x ?? 0, loop.first?.y ?? 0] }
        }
        let changed = (loops == nil) != (hatchHoverLoops == nil) || signature(loops) != signature(hatchHoverLoops)
        hatchHoverLoops = loops
        if changed { needsDisplay = true }
    }

    private func drawHatchHover(in context: CGContext, transform: CGAffineTransform) {
        guard currentTool == .hatch, let loops = hatchHoverLoops else { return }
        let path = CGMutablePath()
        for loop in loops where loop.count >= 3 {
            path.addLines(between: loop.map { $0.applying(transform) })
            path.closeSubpath()
        }
        guard DrawingSafety.isDrawable(path.boundingBoxOfPath) else { return }
        context.saveGState()
        context.addPath(path)
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        context.fillPath(using: .evenOdd)
        // preview of the actual pattern at the current angle and scale
        let preview = HatchEntity(loops: loops, pattern: hatchPattern, angle: currentHatchAngle * .pi / 180,
                                  scale: currentHatchScale, layer: currentLayerName)
        preview.draw(in: context, transform: transform,
                     style: StrokeStyle(color: NSColor.controlAccentColor.withAlphaComponent(0.8), lineWidth: 1))
        context.addPath(path)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 3])
        context.strokePath()
        context.restoreGState()
    }

    private func createHatch(at point: CGPoint) {
        guard let loops = currentHatchFinder().region(at: point) else {
            onMessage?("No closed area here – the boundary is open or has a gap larger than 3 px (zoom in to bridge smaller gaps).")
            NSSound.beep()
            return
        }
        let hatch = HatchEntity(loops: loops, pattern: hatchPattern,
                                angle: currentHatchAngle * .pi / 180, scale: currentHatchScale,
                                layer: currentLayerName)
        onCommit?([], [hatch], "Add Hatch")
        let islands = loops.count - 1
        onMessage?(islands > 0 ? "Hatched (\(islands) island\(islands == 1 ? "" : "s") left out)" : "Hatched")
        hatchHoverLoops = nil
        needsDisplay = true
    }

    // MARK: Offset

    /// Offset distance (nil = through the clicked point).
    var offsetDistance: CGFloat? {
        didSet { onPromptChanged?(prompt) }
    }

    /// Result of offsetting the selected object toward the point.
    private func offsetResult(toward point: CGPoint) -> CADEntity? {
        guard let source = picked.first?.entity else { return nil }
        let distance = offsetDistance ?? EditOperations.offsetDistance(of: source, to: point)
        return EditOperations.offset(source, distance: distance, toward: point)
    }

    private func offsetClick(at point: CGPoint) {
        if picked.isEmpty {
            guard let source = entity(at: point, where: { EditOperations.canOffset($0) }) else {
                onMessage?("Click a line, circle, arc, polyline or spline.")
                return
            }
            picked = [(source, point)]
            stateChanged()
            updateOffsetPreview()
            return
        }
        guard let result = offsetResult(toward: point) else {
            onMessage?("Offset not possible here (the distance is zero or larger than the radius).")
            NSSound.beep()
            return
        }
        onCommit?([], [result], "Offset")
        picked.removeAll()          // next object – the distance stays
        hoverAdded.removeAll()
        stateChanged()
    }

    /// Green offset preview according to the cursor position.
    private func updateOffsetPreview() {
        hoverAdded.removeAll()
        if currentTool == .offset, !picked.isEmpty, let cursor = currentWorldPoint,
           let result = offsetResult(toward: cursor) {
            hoverAdded = [result]
        }
        needsDisplay = true
    }

    private func filletClick(at point: CGPoint) {
        guard let target = entity(at: point, where: { EditOperations.canFillet($0) }) else {
            onMessage?("Fillet works with lines and polylines – click a line or a polyline segment.")
            return
        }
        if picked.isEmpty {
            picked = [(target, point)]
            stateChanged()
            return
        }
        guard let first = picked.first else { return }
        picked.removeAll()
        do {
            let result = try EditOperations.fillet(first.entity, click1: first.click, target, click2: point, radius: filletRadius)
            onCommit?(result.removed, result.added, "Fillet")
        } catch {
            onMessage?(error.localizedDescription)
        }
        stateChanged()
    }

    // MARK: Break

    /// A click with the Break / Break at Point tool. `raw` = the click location (finds the object), `snapped` = the snapped point.
    private func breakClick(at raw: CGPoint, snapped: CGPoint) {
        // second break point: anywhere, it is projected onto the selected object
        if currentTool == .breakObject, let first = picked.first, let curve = first.entity as? CurveEntity {
            picked.removeAll()
            hoverRemoved = nil
            commitBreak(curve, first: first.click, second: snapped)
            stateChanged()
            return
        }
        guard let target = (entity(at: raw, where: { $0 is CurveEntity }) ?? entity(at: snapped, where: { $0 is CurveEntity }))
                as? CurveEntity else {
            onMessage?("\(currentTool.title) works with lines, arcs, circles, ellipses, polylines and splines – click one of them.")
            return
        }
        // the snapped point only if it lies on the object (otherwise the click location)
        let tolerance = worldTolerance * 2
        let point = target.distance(to: snapped) <= tolerance ? snapped : raw
        if currentTool == .breakAtPoint {
            commitBreak(target, first: point, second: nil)
        } else {
            picked = [(target, point)]
        }
        stateChanged()
    }

    private func commitBreak(_ curve: CurveEntity, first: CGPoint, second: CGPoint?) {
        do {
            let result = try EditOperations.breakCurve(curve, first: first, second: second)
            onCommit?([curve], result.kept, currentTool.title)
            if result.removed == nil {
                onMessage?("Split into \(result.kept.count) object\(result.kept.count == 1 ? "" : "s")")
            }
        } catch {
            onMessage?(error.localizedDescription)
        }
    }

    /// Preview: the piece Break will remove in red (from the first point to the cursor).
    private func updateBreakPreview(at point: CGPoint) {
        let previous = hoverRemoved?.id
        hoverRemoved = nil
        if let first = picked.first, let curve = first.entity as? CurveEntity {
            hoverRemoved = (try? EditOperations.breakCurve(curve, first: first.click, second: point))?.removed
        }
        if previous != nil || hoverRemoved != nil { needsDisplay = true }
    }

    private func chamferClick(at point: CGPoint) {
        guard let target = entity(at: point, where: { EditOperations.canFillet($0) }) else {
            onMessage?("Chamfer works with lines and polylines – click a line or a polyline segment.")
            return
        }
        if picked.isEmpty {
            picked = [(target, point)]
            stateChanged()
            return
        }
        guard let first = picked.first else { return }
        picked.removeAll()
        do {
            let result = try EditOperations.chamfer(first.entity, click1: first.click, target, click2: point,
                                                    first: chamferFirst, second: chamferSecond)
            onCommit?(result.removed, result.added, "Chamfer")
        } catch {
            onMessage?(error.localizedDescription)
        }
        stateChanged()
    }

    // MARK: Rectangle

    /// C: the first click is the center of the rectangle (not its corner). Switches any time, also while drawing.
    var rectangleFromCenter = false {
        didSet { stateChanged() }
    }

    /// S: the rectangle is a square.
    var rectangleSquare = false {
        didSet { stateChanged() }
    }

    /// The rectangle is a square right now: S is on, or Shift is held (only while the mouse decides the size –
    /// typed values keep their own sides).
    private var rectangleIsSquare: Bool {
        rectangleSquare || squareByShift
    }

    /// Shift held while the mouse sizes a rectangle (Rectangle, the rectangle of Wipeout and Revision Cloud).
    private var squareByShift: Bool {
        shiftHeld && !dynamicInput.hasLockedValue
    }

    /// The diagonal `d` (in the drawing coordinates) made square: the longer side, toward the cursor.
    private static func squared(_ d: CGPoint) -> CGPoint {
        let side = max(abs(d.x), abs(d.y))
        return CGPoint(x: d.x < 0 ? -side : side, y: d.y < 0 ? -side : side)
    }

    /// The rectangle from the first click to `point`: its first corner and its diagonal along the axes
    /// of the drawing coordinates. Square = equal sides (the longer one, toward the cursor);
    /// from the center = the first click is the center and the cursor a corner.
    private func rectangleDiagonal(from first: CGPoint, to point: CGPoint) -> (corner: CGPoint, diagonal: CGPoint) {
        var d = toUCSVector(point - first)
        if rectangleIsSquare { d = CADEditorView.squared(d) }
        if rectangleFromCenter { return (first - fromUCSVector(d), d * 2) }
        return (first, d)
    }

    /// C = from the center / from a corner, S = square on/off.
    private func rectangleLetter(_ letter: String) -> Bool {
        switch letter {
        case "c":
            rectangleFromCenter.toggle()
            onMessage?("Rectangle from center " + (rectangleFromCenter ? "ON" : "OFF"))
            return true
        case "s":
            rectangleSquare.toggle()
            onMessage?("Square " + (rectangleSquare ? "ON" : "OFF"))
            return true
        default:
            return false
        }
    }

    // MARK: Polygon

    /// Number of sides and input method (remembered between launches).
    var polygonSides: Int = AppSettings.polygonSides {
        didSet {
            AppSettings.polygonSides = polygonSides
            if polygonSides != AppSettings.polygonSides { polygonSides = AppSettings.polygonSides }
            stateChanged()
        }
    }

    var polygonMethod: PolygonMethod = AppSettings.polygonMethod {
        didSet {
            AppSettings.polygonMethod = polygonMethod
            // a different meaning of the points → start over
            if currentTool == .polygon && oldValue != polygonMethod { points.removeAll() }
            dynamicInput.reset()
            stateChanged()
        }
    }

    /// Number of sides for the preview – even while being typed in the box at the cursor.
    private var effectivePolygonSides: Int {
        if case .polygon = inputMode, let typed = dynamicInput.lockedValue(2) {
            let sides = Int(typed.rounded())
            if sides >= RegularPolygon.minimumSides && sides <= RegularPolygon.maximumSides { return sides }
        }
        return polygonSides
    }

    /// I / C / E = method, S = number of sides. true = the letter was used.
    private func polygonLetter(_ letter: String) -> Bool {
        if letter == "s" {
            DispatchQueue.main.async { [weak self] in self?.askPolygonSides() }
            return true
        }
        guard let method = PolygonMethod.allCases.first(where: { $0.letter == letter }) else { return false }
        polygonMethod = method
        onMessage?("Polygon: \(method.title.lowercased())")
        return true
    }

    /// Window with the number of sides (S while drawing or from the button menu).
    func askPolygonSides() {
        let alert = NSAlert()
        alert.messageText = "Polygon – Number of Sides"
        alert.informativeText = "Number of sides (from \(RegularPolygon.minimumSides) to \(RegularPolygon.maximumSides)):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = "\(polygonSides)"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let sides = Int(text), sides >= RegularPolygon.minimumSides, sides <= RegularPolygon.maximumSides else {
            onMessage?(polygonSidesError(text))
            return
        }
        polygonSides = sides
        onMessage?("Polygon: \(sides) sides")
    }

    private func polygonSidesError(_ text: String) -> String {
        return "\u{201C}\(text)\u{201D} is not a valid number of sides – enter a whole number from "
            + "\(RegularPolygon.minimumSides) to \(RegularPolygon.maximumSides)."
    }

    // MARK: Image or PDF underlay (ImageUnderlay.swift)

    /// The chosen file waiting to be placed (set by the main window after the file dialog).
    var pendingImage: ImageSource? {
        didSet { if currentTool == .image { stateChanged() } }
    }

    /// The image at its size in the drawing: paper size × its scale, in drawing units.
    private func placedImage(_ source: ImageSource, at point: CGPoint) -> ImageEntity {
        let unitsPerPaperMM = source.scale.factor / max(drawingUnits.mmPerUnit, 1e-12)
        return ImageEntity(source: source, at: point, unitsPerPaperMM: unitsPerPaperMM, layer: currentLayerName)
    }

    private func finishImage(at point: CGPoint) {
        points.removeAll()
        guard let source = pendingImage else {
            onMessage?("Choose the image or PDF first (Insert › Attach Image or PDF…).")
            NSSound.beep()
            stateChanged()
            return
        }
        let image = placedImage(source, at: point)
        onCommit?([], [image], "Attach \(image.typeName)")
        pendingImage = nil
        onToolChangeRequested?(.select)
        selectionManager?.select([image])
        onMessage?("\(image.typeName) “\(source.fileName)” placed – fit it with Move, Rotate and Scale; Properties sets the opacity")
    }

    // MARK: Scale bar and north arrow (ScaleBar.swift)

    /// Blocks made for the preview – they join the drawing's blocks only when placed.
    private var symbolDrafts: [String: BlockDefinition] = [:]

    /// The scale a scale bar shows: on a layout that of the viewport nearest to the point, otherwise the drawing scale.
    private func scaleBarScale(near point: CGPoint) -> DrawingScale? {
        guard paperSpace != nil else { return drawingScale }
        func gap(_ rect: CGRect) -> CGFloat {
            return hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
        }
        return allEntities.compactMap { $0 as? ViewportEntity }.min { gap($0.rect) < gap($1.rect) }?.scale
    }

    /// The scale bar or north arrow at a point (nil = a scale bar on a layout without viewports).
    private func symbolReference(at point: CGPoint) -> BlockReference? {
        let definition: BlockDefinition
        var rotation: CGFloat = 0
        if currentTool == .northArrow {
            definition = symbolDefinition(named: AnnotationSymbols.northArrowName) { AnnotationSymbols.northArrow() }
        } else {
            guard let scale = scaleBarScale(near: point) else { return nil }
            definition = symbolDefinition(named: "Scale Bar \(scale.title)") {
                AnnotationSymbols.scaleBar(metersPerPaperMM: scale.factor / 1000, scaleTitle: scale.title)
            }
            // along the X axis of the drawing coordinates
            rotation = ucsAngle
        }
        let reference = BlockReference(definition: definition, position: point, layer: currentLayerName)
        reference.scale = unitsPerPaperMM
        reference.rotation = rotation
        return reference
    }

    /// The drawing's own block of that name (it may have been edited), otherwise a new one.
    private func symbolDefinition(named name: String, make: () -> BlockDefinition) -> BlockDefinition {
        if let existing = blockLibrary?.named(name), !existing.isExternal { return existing }
        if let draft = symbolDrafts[name] { return draft }
        let draft = make()
        symbolDrafts[name] = draft
        return draft
    }

    private func finishSymbol(at point: CGPoint) {
        points.removeAll()
        guard let reference = symbolReference(at: point) else {
            onMessage?("Add a viewport to the layout first – the scale bar takes its scale.")
            NSSound.beep()
            stateChanged()
            return
        }
        let definition = reference.definition
        if let library = blockLibrary, library.named(definition.name) !== definition {
            library.add(definition)
            symbolDrafts[definition.name] = nil
            onBlocksChanged?()
        }
        onCommit?([], [reference], "Add \(currentTool.title)")
        onMessage?("\(currentTool.title) placed – block “\(definition.name)”")
        onToolChangeRequested?(.select)
    }

    // MARK: Room label (RoomLabel.swift)

    /// Room outlines among the visible objects – the same ones the drawing uses to update the labels.
    private func currentRoomFinder() -> HatchRegionFinder {
        let entities = visibleEntities.filter { RoomLabels.isBoundary($0) }
        var signature = entities.count &+ blockSignature
        for entity in entities { signature = signature &* 31 &+ entity.id.hashValue }
        let key = "\(signature)|\(unitsPerPaperMM)"
        if let finder = roomFinder, key == roomFinderKey { return finder }
        let finder = RoomLabels.finder(for: entities, unitsPerPaperMM: unitsPerPaperMM)
        roomFinder = finder
        roomFinderKey = key
        return finder
    }

    private func updateRoomHover(at point: CGPoint) {
        let outline = RoomLabels.outline(at: point, finder: currentRoomFinder())
        let changed = outline?.count != roomHover?.count || outline?.first != roomHover?.first
        roomHover = outline
        if changed {
            onPromptChanged?(prompt)
            needsDisplay = true
        }
    }

    private func drawRoomHover(in context: CGContext, transform: CGAffineTransform) {
        guard currentTool == .roomLabel, let outline = roomHover else { return }
        let path = CGMutablePath()
        path.addLines(between: outline.map { $0.applying(transform) })
        path.closeSubpath()
        guard DrawingSafety.isDrawable(path.boundingBoxOfPath) else { return }
        context.saveGState()
        context.addPath(path)
        context.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
        context.fillPath()
        context.addPath(path)
        context.setStrokeColor(NSColor.controlAccentColor.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [5, 3])
        context.strokePath()
        context.restoreGState()
    }

    /// Click with Room Label: measures the room around the point, asks for the name and places the label there.
    private func placeRoomLabel(at point: CGPoint) {
        guard let outline = RoomLabels.outline(at: point, finder: currentRoomFinder()) else {
            onMessage?("No closed room here – close door openings with a line or a door (gaps up to \(DynamicInputView.format(RoomLabels.gapMM)) mm on paper are bridged).")
            NSSound.beep()
            return
        }
        let area = RoomLabels.squareMeters(of: outline, mmPerUnit: drawingUnits.mmPerUnit)
        guard let name = askForRoomName(area: area) else { return }
        let label = makeText(RoomLabels.newText(name: name, squareMeters: area), at: point)
        label.justify = .center
        label.isRoomLabel = true
        onCommit?([], [label], "Add Room Label")
        roomHover = nil
        onMessage?("Room label placed (\(RoomLabels.areaLine(area))) – the area follows the walls")
        stateChanged()
    }

    /// The name of a new room (nil = canceled; empty = only the area).
    private func askForRoomName(area: CGFloat) -> String? {
        let alert = NSAlert()
        alert.messageText = "Room Label – Name"
        alert.informativeText = "Floor area \(RoomLabels.areaLine(area)). Name of the room (it can stay empty):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "e.g. Living Room"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Revision cloud and wipeout (RevisionCloud.swift, Wipeout.swift)

    /// Outline by corners, or a rectangle from two corners.
    var revisionCloudShape: RevisionCloud.Shape = .polygon {
        didSet {
            if currentTool == .revisionCloud { points.removeAll() }
            stateChanged()
        }
    }

    /// The same two ways for a wipeout – a rectangle by default (the usual case: a clear area under a text).
    var wipeoutShape: RevisionCloud.Shape = .rectangle {
        didSet {
            if currentTool == .wipeout { points.removeAll() }
            stateChanged()
        }
    }

    /// Tools that draw a closed outline, by corners or as a rectangle.
    private var drawsOutline: Bool {
        return currentTool == .revisionCloud || currentTool == .wipeout
    }

    /// How the current tool draws its outline.
    private var outlineShape: RevisionCloud.Shape {
        get { return currentTool == .wipeout ? wipeoutShape : revisionCloudShape }
        set { if currentTool == .wipeout { wipeoutShape = newValue } else { revisionCloudShape = newValue } }
    }

    /// Arc size of new clouds in mm on paper (remembered between launches).
    var revisionCloudArcMM: CGFloat = AppSettings.revisionCloudArcMM {
        didSet { AppSettings.revisionCloudArcMM = revisionCloudArcMM }
    }

    /// Arc size in drawing units (by the drawing scale).
    private var revisionCloudArcSize: CGFloat {
        return revisionCloudArcMM * unitsPerPaperMM
    }

    /// Corners of the outline: the clicked ones, or a rectangle (by the drawing coordinates) from the first two.
    private func outlineCorners(_ corners: [CGPoint]) -> [CGPoint] {
        guard outlineShape == .rectangle else { return corners }
        guard corners.count >= 2 else { return [] }
        let a = corners[0]
        var d = toUCSVector(corners[1] - a)
        if squareByShift { d = CADEditorView.squared(d) }
        let b = a + fromUCSVector(d)
        return [a, a + fromUCSVector(CGPoint(x: d.x, y: 0)), b, a + fromUCSVector(CGPoint(x: 0, y: d.y))]
    }

    private func addOutlinePoint(_ point: CGPoint, clickCount: Int) {
        if outlineShape == .rectangle {
            if points.isEmpty {
                points.append(point)
                stateChanged()
            } else {
                finishOutline([points[0], point])
            }
            return
        }
        // a double-click or a click on the first corner closes the outline
        if points.count >= 3 && (clickCount >= 2
            || Geometry.distance(viewport.worldToScreen(point), viewport.worldToScreen(points[0])) < 8) {
            finishOutline(points)
            return
        }
        if let last = points.last, Geometry.distance(last, point) < 1e-9 { return }
        points.append(point)
        stateChanged()
    }

    /// Creates the cloud or the wipeout along the outline.
    private func finishOutline(_ corners: [CGPoint]) {
        defer {
            points.removeAll()
            stateChanged()
        }
        let outline = outlineCorners(corners)
        if currentTool == .wipeout {
            guard let wipeout = WipeoutEntity.make(outline: outline, layer: currentLayerName) else {
                onMessage?("The outline of the wipeout has no area.")
                return
            }
            onCommit?([], [wipeout], "Add Wipeout")
            return
        }
        guard let cloud = RevisionCloud.polyline(around: outline, arcSize: revisionCloudArcSize, layer: currentLayerName) else {
            onMessage?("The outline of the revision cloud has no area.")
            return
        }
        onCommit?([], [cloud], "Add Revision Cloud")
    }

    /// Letters while drawing a cloud or a wipeout; true = the letter was used.
    private func outlineLetter(_ letter: String) -> Bool {
        let name = currentTool == .wipeout ? "Wipeout" : "Revision Cloud"
        switch letter {
        case "r":
            outlineShape = .rectangle
            onMessage?(name + ": rectangle from two corners")
            return true
        case "p":
            outlineShape = .polygon
            onMessage?(name + ": outline by corners")
            return true
        case "a":
            guard currentTool == .revisionCloud else { return false }
            DispatchQueue.main.async { [weak self] in self?.askRevisionCloudArcSize() }
            return true
        case "c":
            // C closes the outline – and doesn't switch to Circle while an outline is being drawn
            guard !points.isEmpty, outlineShape == .polygon else { return false }
            if points.count >= 3 {
                finishOutline(points)
            } else {
                onMessage?("Closing (C) needs at least three corners.")
                NSSound.beep()
            }
            return true
        default:
            return false
        }
    }

    /// Window with the arc size (A while drawing a cloud).
    func askRevisionCloudArcSize() {
        let range = RevisionCloud.arcSizeRangeMM
        let alert = NSAlert()
        alert.messageText = "Revision Cloud – Arc Size"
        alert.informativeText = "Size of the arcs in mm on paper, measured between their ends (from \(DynamicInputView.format(range.lowerBound))"
            + " to \(DynamicInputView.format(range.upperBound)); in the drawing it follows the drawing scale):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = DynamicInputView.format(revisionCloudArcMM)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let value = ExpressionEvaluator.evaluate(text), range.contains(CGFloat(value)) else {
            onMessage?("\u{201C}\(text)\u{201D} is not a valid arc size – enter a number from \(DynamicInputView.format(range.lowerBound)) to \(DynamicInputView.format(range.upperBound)) mm.")
            return
        }
        revisionCloudArcMM = CGFloat(value)
        onMessage?("Revision Cloud: arcs \(DynamicInputView.format(revisionCloudArcMM)) mm on paper")
        stateChanged()
    }

    // MARK: Walls (Walls.swift)

    /// Thickness of new walls in mm (remembered between launches).
    var wallThicknessMM: CGFloat = AppSettings.wallThicknessMM {
        didSet {
            AppSettings.wallThicknessMM = wallThicknessMM
            onPromptChanged?(prompt)
            needsDisplay = true
        }
    }

    /// Where the wall lies relative to the clicked line.
    var wallJustification: Walls.Justification = .center {
        didSet { stateChanged() }
    }

    /// Thickness in drawing units (by the units of the drawing – mm, cm, m…).
    private var wallThickness: CGFloat {
        return wallThicknessMM / max(drawingUnits.mmPerUnit, 1e-12)
    }

    private func addWallPoint(_ point: CGPoint, clickCount: Int) {
        // a double-click finishes, a click on the first point closes the wall into a ring
        if clickCount >= 2 && points.count >= 2 {
            finishWall(closed: false)
            return
        }
        if points.count >= 3, Geometry.distance(viewport.worldToScreen(point), viewport.worldToScreen(points[0])) < 8 {
            finishWall(closed: true)
            return
        }
        if let last = points.last, Geometry.distance(last, point) < 1e-9 { return }
        points.append(point)
        stateChanged()
    }

    private func finishWall(closed: Bool) {
        defer {
            points.removeAll()
            stateChanged()
        }
        let outlines = Walls.outlines(along: points, closed: closed, thickness: wallThickness,
                                      justification: wallJustification, layer: currentLayerName)
        guard !outlines.isEmpty else {
            onMessage?("A wall needs at least two different points.")
            return
        }
        onCommit?([], outlines, "Add Wall")
    }

    /// Letters while drawing a wall; true = the letter was used.
    private func wallLetter(_ letter: String) -> Bool {
        switch letter {
        case "t":
            DispatchQueue.main.async { [weak self] in self?.askWallThickness() }
            return true
        case "j":
            wallJustification = wallJustification.next
            onMessage?("Wall: " + wallJustification.title)
            return true
        case "c":
            // C closes the wall – and doesn't switch to Circle while a wall is being drawn
            guard !points.isEmpty else { return false }
            if points.count >= 3 {
                finishWall(closed: true)
            } else {
                onMessage?("Closing (C) needs at least three points.")
                NSSound.beep()
            }
            return true
        default:
            return false
        }
    }

    /// Where a wall from a curve lies (Wall from Curve).
    var wallCurveAlignment: Walls.CurveAlignment = .center {
        didSet { stateChanged() }
    }

    /// The selected curves a wall can follow (not on locked layers).
    private var wallFromCurveSources: [CADEntity] {
        return selectedEntities.filter { Walls.canFollow($0) && !(layerManager?.isLayerLocked($0.layer) ?? false) }
    }

    /// The last preview – computed again only when the selection, thickness or side changes.
    private var wallFromCurveCache: (key: String, outlines: [Polyline])?

    private func wallFromCurveOutlines() -> [Polyline] {
        let sources = wallFromCurveSources
        let key = sources.map { $0.id.uuidString }.joined() + "|\(wallThickness)|\(wallCurveAlignment)"
        if let cache = wallFromCurveCache, cache.key == key { return cache.outlines }
        let outlines = Walls.outlines(alongCurves: sources, thickness: wallThickness, alignment: wallCurveAlignment,
                                      layer: currentLayerName)
        wallFromCurveCache = (key, outlines)
        return outlines
    }

    private func finishWallFromCurve() {
        guard !wallFromCurveSources.isEmpty else {
            onMessage?("Select lines, arcs, polylines, splines, circles or ellipses first.")
            return
        }
        wallFromCurveCache = nil      // the objects may have changed since the preview
        let outlines = wallFromCurveOutlines()
        guard !outlines.isEmpty else {
            onMessage?("No wall can be made from the selected objects.")
            return
        }
        onCommit?([], outlines, DrawingTool.wallFromCurve.title)
        selectionManager?.select(outlines)
        onToolChangeRequested?(.select)
        onMessage?("Wall from Curve: \(outlines.count) outline\(outlines.count == 1 ? "" : "s"), "
                   + "\(DynamicInputView.format(wallThicknessMM)) mm, \(wallCurveAlignment.title)")
    }

    /// Letters in Wall from Curve; true = the letter was used.
    private func wallFromCurveLetter(_ letter: String) -> Bool {
        switch letter {
        case "t":
            DispatchQueue.main.async { [weak self] in self?.askWallThickness() }
            return true
        case "j":
            wallCurveAlignment = wallCurveAlignment.next
            onMessage?("Wall from Curve: " + wallCurveAlignment.title)
            return true
        default:
            return false
        }
    }

    /// Window with the wall thickness (T while drawing a wall).
    func askWallThickness() {
        let range = Walls.thicknessRangeMM
        let alert = NSAlert()
        alert.messageText = "Wall – Thickness"
        alert.informativeText = "Thickness of new walls in mm (from \(DynamicInputView.format(range.lowerBound))"
            + " to \(DynamicInputView.format(range.upperBound))):"
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        field.stringValue = DynamicInputView.format(wallThicknessMM)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let value = ExpressionEvaluator.evaluate(text), range.contains(CGFloat(value)) else {
            onMessage?("\u{201C}\(text)\u{201D} is not a valid wall thickness – enter a number from \(DynamicInputView.format(range.lowerBound)) to \(DynamicInputView.format(range.upperBound)) mm.")
            return
        }
        wallThicknessMM = CGFloat(value)
        onMessage?("Wall: thickness \(DynamicInputView.format(wallThicknessMM)) mm")
        stateChanged()
    }

    // MARK: Construction lines

    /// Construction line input method (through two points, horizontal, vertical, at an angle).
    var xlineKind: XLineKind = .twoPoints {
        didSet {
            if currentTool == .xline { points.removeAll() }
            onXLineKindChanged?(xlineKind)
            stateChanged()
        }
    }
    /// Angle for the “at an angle” method (degrees, from the X axis of the drawing coordinates).
    var xlineAngle: CGFloat = 45 {
        didSet { onPromptChanged?(prompt) }
    }
    /// The method changed (by a key) – the tool panel switches the icon.
    var onXLineKindChanged: ((XLineKind) -> Void)?

    /// Fixed line direction in the drawing (horizontal / vertical / at an angle – in rotated drawing coordinates).
    private var xlineFixedAngle: CGFloat {
        switch xlineKind {
        case .horizontal, .twoPoints: return ucsAngle
        case .vertical: return ucsAngle + .pi / 2
        case .angle: return ucsAngle + xlineAngle * .pi / 180
        }
    }

    private func addConstructionLine(at point: CGPoint) {
        if xlineKind == .twoPoints {
            guard let first = points.first else {
                points = [point]
                stateChanged()
                return
            }
            guard Geometry.distance(first, point) > 1e-9 else { return }
            onCommit?([], [ConstructionLine(point: first, angle: Geometry.angle(from: first, to: point), layer: currentLayerName)],
                      "Add Construction Line")
            // further lines pass through the same point
            stateChanged()
            return
        }
        onCommit?([], [ConstructionLine(point: point, angle: xlineFixedAngle, layer: currentLayerName)], "Add Construction Line")
        stateChanged()
    }

    /// H / V / A / B while drawing a construction line. true = the letter was used.
    private func switchXLineKind(letter: String) -> Bool {
        let kind: XLineKind
        switch letter {
        case "h": kind = .horizontal
        case "v": kind = .vertical
        case "a": kind = .angle
        case "b": kind = .twoPoints
        default: return false
        }
        xlineKind = kind
        onMessage?(kind == .angle ? "Construction Line: at \(LineType.formatAngle(xlineAngle))° – hold the button to change the angle"
                   : "Construction Line: " + kind.title.lowercased())
        return true
    }

    // MARK: Match properties

    /// The object whose properties are transferred.
    private var matchSource: CADEntity?

    /// What is transferred from the source (for the prompt).
    private func matchSummary(of source: CADEntity) -> String {
        let chosen = AppSettings.matchProperties
        var parts: [String] = []
        if chosen.contains(.layer) { parts.append("layer \(source.layer)") }
        if chosen.contains(.color) { parts.append("color \(source.colorDescription)") }
        if chosen.contains(.lineWeight) {
            parts.append("lineweight " + (source.lineWeight.map { LineType.format($0) + " mm" } ?? "ByLayer"))
        }
        if chosen.contains(.style), MatchProperties.hasStyle(source) { parts.append("\(source.typeName.lowercased()) style") }
        return parts.isEmpty ? "nothing chosen" : parts.joined(separator: ", ")
    }

    private func applyMatch(to targets: [CADEntity]) {
        guard let source = matchSource else { return }
        let layerManager = self.layerManager
        var removed: [CADEntity] = []
        var added: [CADEntity] = []
        var locked = 0
        for target in targets where target !== source {
            if layerManager?.isLayerLocked(target.layer) ?? false { locked += 1; continue }
            guard let changed = MatchProperties.apply(from: source, to: target, properties: AppSettings.matchProperties) else { continue }
            removed.append(target)
            added.append(changed)
        }
        if added.isEmpty {
            onMessage?(locked > 0 ? "The object is on a locked layer." : "Nothing changed – the object already looks the same.")
        } else {
            selectionManager?.deselect(removed)
            onCommit?(removed, added, "Match Properties")
            onMessage?("Properties copied to \(added.count) object\(added.count == 1 ? "" : "s")" + (locked > 0 ? " · \(locked) on locked layers skipped" : ""))
        }
        stateChanged()
    }

    // MARK: Chained dimension

    /// The last dimension of the chain and the point the next one continues from.
    private var chainSource: DimensionEntity?
    private var chainFrom: CGPoint?
    /// The most recently drawn linear / aligned dimension (the default start of the chain).
    private var lastChainableDimension: DimensionEntity?

    private func pickChainSource(at point: CGPoint) {
        guard let dimension = entity(at: point, where: {
            guard let d = $0 as? DimensionEntity else { return false }
            return (d.kind == .linear || d.kind == .aligned) && d.points.count >= 3
        }) as? DimensionEntity else {
            onMessage?("Click a linear or aligned dimension.")
            NSSound.beep()
            return
        }
        chainSource = dimension
        // continue from the end nearer to the click
        chainFrom = Geometry.distance(point, dimension.points[0]) < Geometry.distance(point, dimension.points[1])
            ? dimension.points[0] : dimension.points[1]
        stateChanged()
    }

    /// The next dimension of the chain: from the last point to point `p`, on the same dimension line and in the same direction.
    private func chainDimension(to p: CGPoint) -> DimensionEntity? {
        guard let source = chainSource, let from = chainFrom, source.points.count >= 3 else { return nil }
        let d = source.measureDirection
        guard abs((p - from).dot(d)) > 1e-9 else { return nil }
        let dimension = DimensionEntity(kind: .linear, points: [from, p, source.points[2]], text: "",
                                        textHeight: source.textHeight, layer: source.layer, color: source.color)
        dimension.fixedAngle = atan2(d.y, d.x)
        dimension.arrowSize = source.arrowSize
        dimension.arrowStyle = source.arrowStyle
        dimension.precision = source.precision
        dimension.lineWeight = source.lineWeight
        return dimension
    }

    private func addChainDimension(to p: CGPoint) {
        guard let dimension = chainDimension(to: p) else {
            onMessage?("The point is level with the previous one – nothing to dimension.")
            NSSound.beep()
            return
        }
        Associativity.attach(dimension, to: snapEntities)
        onCommit?([], [dimension], "Continue Dimension")
        chainSource = dimension
        chainFrom = p
        lastChainableDimension = dimension
        stateChanged()
    }

    // MARK: Stretch

    /// What gets stretched: the object, the grip indices inside the window, or the whole object (move).
    private var stretchItems: [(entity: CADEntity, indices: [Int], whole: Bool)] = []

    /// The window (in screen points) is finished – find out which points will move.
    private func finishStretchWindow(from start: CGPoint, to end: CGPoint) {
        let w1 = viewport.screenToWorld(start), w2 = viewport.screenToWorld(end)
        let rect = CGRect(x: min(w1.x, w2.x), y: min(w1.y, w2.y), width: abs(w2.x - w1.x), height: abs(w2.y - w1.y))
        stretchItems = CADEditorView.stretchItems(in: rect, entities: editableEntities)
        guard !stretchItems.isEmpty else {
            onMessage?("Nothing in the window – drag it across the ends or corners you want to move.")
            NSSound.beep()
            stateChanged()
            return
        }
        picked = stretchItems.map { (entity: $0.entity, click: CGPoint.zero) }
        stage = .points
        let whole = stretchItems.filter { $0.whole }.count
        onMessage?("\(stretchItems.count - whole) object\(stretchItems.count - whole == 1 ? "" : "s") will stretch, \(whole) move whole")
        stateChanged()
    }

    static func stretchItems(in rect: CGRect, entities: [CADEntity]) -> [(entity: CADEntity, indices: [Int], whole: Bool)] {
        var result: [(entity: CADEntity, indices: [Int], whole: Bool)] = []
        for entity in entities {
            let box = entity.boundingBox()
            if rect.contains(box) {
                result.append((entity, [], true))
                continue
            }
            guard rect.intersects(box.insetBy(dx: -1e-9, dy: -1e-9)) else { continue }
            let grips = Grips.grips(of: entity)
            // circles, ellipses and texts are only moved when their center / insertion point is in the window
            if entity is Circle || entity is Ellipse || entity is TextEntity || CADEditorView.movesWhole(entity) {
                if let first = grips.first, rect.contains(first.point) { result.append((entity, [], true)) }
                continue
            }
            let pointIndices = grips.indices.filter { grips[$0].kind == .point }
            let inside = pointIndices.filter { rect.contains(grips[$0].point) }
            guard !inside.isEmpty else { continue }
            result.append((entity, inside, inside.count == pointIndices.count))
        }
        return result
    }

    /// Objects that never deform with Stretch (blocks, references).
    static func movesWhole(_ entity: CADEntity) -> Bool {
        return entity is BlockReference
    }

    private func stretchResults(delta: CGPoint) -> [(original: CADEntity, edited: CADEntity)] {
        guard delta.length > 1e-12 else { return [] }
        let move = CGAffineTransform(translationX: delta.x, y: delta.y)
        var result: [(original: CADEntity, edited: CADEntity)] = []
        for item in stretchItems {
            if item.whole {
                let copy = item.entity.clone()
                copy.applyTransform(move)
                result.append((item.entity, copy))
                continue
            }
            let base = Grips.grips(of: item.entity)
            var current: CADEntity = item.entity
            var valid = true
            for index in item.indices {
                guard index < base.count, let next = Grips.moved(current, grip: index, to: base[index].point + delta) else {
                    valid = false
                    break
                }
                current = next
            }
            if valid && current !== item.entity { result.append((item.entity, current)) }
        }
        return result
    }

    private func finishStretch(target: CGPoint) {
        guard let base = points.first else { return }
        let results = stretchResults(delta: target - base)
        if results.isEmpty {
            onMessage?("Nothing stretched (zero distance, or the shapes would collapse).")
        } else {
            onCommit?(results.map { $0.original }, results.map { $0.edited }, "Stretch")
            onMessage?("Stretched \(results.count) object\(results.count == 1 ? "" : "s") – drag a new window for the next stretch")
        }
        stretchItems.removeAll()
        picked.removeAll()
        points.removeAll()
        stage = .window
        stateChanged()
    }

    // MARK: Creating and inserting a block

    private func finishBlockCreate(base: CGPoint) {
        let originals = movableSelection
        points.removeAll()
        guard !originals.isEmpty, let library = blockLibrary else {
            onMessage?("Select the objects for the block first.")
            resetToolState()
            return
        }
        guard let answer = askForBlock(suggested: library.uniqueName()) else {
            stateChanged()
            return
        }
        let clones = originals.map { $0.clone() }
        let definition: BlockDefinition
        if let existing = library.named(answer.name) {
            guard !existing.isExternal else {
                onMessage?("“\(answer.name)” is an external reference – choose another name.")
                NSSound.beep()
                stateChanged()
                return
            }
            guard !originals.contains(where: { ($0 as? BlockReference)?.definition.contains(existing) ?? false }) else {
                onMessage?("A block cannot contain itself – the selection includes “\(existing.name)”.")
                NSSound.beep()
                stateChanged()
                return
            }
            let alert = NSAlert()
            alert.messageText = "Redefine the block “\(existing.name)”?"
            alert.informativeText = "Every reference to it in the drawing changes to the new objects. This cannot be undone."
            alert.addButton(withTitle: "Redefine")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else {
                stateChanged()
                return
            }
            existing.basePoint = base
            existing.entities = clones
            if !answer.note.isEmpty { existing.note = answer.note }
            definition = existing
        } else {
            definition = BlockDefinition(name: answer.name, basePoint: base, entities: clones, note: answer.note)
            library.add(definition)
        }
        insertDefinition = definition
        if answer.replace {
            let reference = BlockReference(definition: definition, position: base, layer: currentLayerName)
            onCommit?(originals, [reference], "Create Block")
            selectionManager?.select([reference])
        }
        onBlocksChanged?()
        onMessage?("Block “\(definition.name)” – \(clones.count) object\(clones.count == 1 ? "" : "s"). Insert Block places more copies.")
        needsDisplay = true
        onToolChangeRequested?(.select)
    }

    /// Name of the new block, a note and whether to replace the selected objects with the block. nil = Cancel.
    private func askForBlock(suggested: String) -> (name: String, note: String, replace: Bool)? {
        let alert = NSAlert()
        alert.messageText = "Create Block – Name"
        alert.informativeText = "The selected objects become a block. An existing name redefines that block."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let name = NSTextField(string: suggested)
        let note = NSTextField(string: "")
        note.placeholderString = "optional"
        for field in [name, note] { field.widthAnchor.constraint(equalToConstant: 220).isActive = true }
        let replace = NSButton(checkboxWithTitle: "Replace the selected objects with the block", target: nil, action: nil)
        replace.state = .on
        let grid = NSGridView(views: [[NSTextField(labelWithString: "Name:"), name],
                                      [NSTextField(labelWithString: "Description:"), note],
                                      [NSGridCell.emptyContentView, replace]])
        grid.rowSpacing = 8
        grid.column(at: 0).xPlacement = .trailing
        grid.frame.size = grid.fittingSize
        alert.accessoryView = grid
        alert.window.initialFirstResponder = name
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let trimmed = name.stringValue.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            NSSound.beep()
            return nil
        }
        return (trimmed, note.stringValue.trimmingCharacters(in: .whitespaces), replace.state == .on)
    }

    private func finishBlockInsert(at point: CGPoint) {
        points.removeAll()
        guard let definition = insertDefinition, blockLibrary?.named(definition.name) === definition else {
            onMessage?(currentTool == .xref ? "Choose the file of the external reference first."
                       : "No block chosen – hold the Insert Block button to choose one.")
            NSSound.beep()
            stateChanged()
            return
        }
        let reference = BlockReference(definition: definition, position: point, layer: currentLayerName)
        onCommit?([], [reference], currentTool == .xref ? "Attach External Reference" : "Insert Block")
        onMessage?("\(definition.isExternal ? "External reference" : "Block") “\(definition.name)” placed – click for another copy, Esc ends")
        stateChanged()
    }

    // MARK: Array

    /// Default array spacing: 1.5 × the selection size, rounded to a nice number.
    private func defaultArraySpacing(_ size: CGFloat, fallback: CGFloat) -> CGFloat {
        let raw = size > 1e-9 ? size * 1.5 : fallback
        return CADEditorView.niceValue(raw)
    }

    private func openArrayDialog(center: CGPoint?) {
        let originals = movableSelection
        guard !originals.isEmpty, let window = window else {
            onMessage?("Select the objects for the array first.")
            return
        }
        guard window.attachedSheet == nil else { return }
        var box = CGRect.null
        for entity in originals { box = box.union(entity.boundingBox()) }
        let fallback = max(box.width, box.height, 10)
        let dx = arraySettings.columnSpacing ?? defaultArraySpacing(box.width, fallback: fallback)
        let dy = arraySettings.rowSpacing ?? defaultArraySpacing(box.height, fallback: fallback)
        let kind = arrayKind
        let pivot = center ?? CGPoint(x: box.midX, y: box.midY)

        let form = ArrayForm(kind: kind, settings: arraySettings, columnSpacing: dx, rowSpacing: dy, unit: drawingUnits.suffix)
        let refresh = { [weak self, weak form] in
            guard let self = self, let form = form else { return }
            let s = form.settings
            self.arrayPreview = EditOperations.arrayCopies(of: originals, kind: kind, settings: s, center: pivot,
                                                           columnSpacing: s.columnSpacing ?? dx, rowSpacing: s.rowSpacing ?? dy)
        }
        form.onChange = refresh
        refresh()

        let alert = NSAlert()
        alert.messageText = kind.title
        alert.informativeText = kind == .rectangular
            ? "\(originals.count) object\(originals.count == 1 ? "" : "s") · the original stays in the lower-left cell. Negative spacing goes left / down."
            : "\(originals.count) object\(originals.count == 1 ? "" : "s") around the center · a positive angle goes counter-clockwise."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = form.view
        alert.window.initialFirstResponder = form.firstField
        onPromptChanged?("\(kind.title): set the values – the green preview shows the copies")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            let s = form.settings
            self.arrayPreview = []
            guard response == .alertFirstButtonReturn else {
                self.onMessage?("Array canceled")
                self.points.removeAll()
                self.stateChanged()
                return
            }
            // the spacing is remembered only when the user changed it
            self.arraySettings = s
            if s.columnSpacing == dx { self.arraySettings.columnSpacing = nil }
            if s.rowSpacing == dy { self.arraySettings.rowSpacing = nil }
            let copies = EditOperations.arrayCopies(of: originals, kind: kind, settings: s, center: pivot,
                                                    columnSpacing: s.columnSpacing ?? dx, rowSpacing: s.rowSpacing ?? dy)
            if copies.isEmpty {
                self.onMessage?("No copies – check the counts (at most \(ArraySettings.maxCopies) objects at once).")
                NSSound.beep()
            } else {
                self.onCommit?([], copies, kind.title)
                self.onMessage?("\(kind.title): \(copies.count) object\(copies.count == 1 ? "" : "s") added")
            }
            self.onToolChangeRequested?(.select)
            self.window?.makeFirstResponder(self)
        }
    }

    // MARK: Measure

    /// Measurement result shown on the canvas (stays until the next measurement or Esc).
    private struct MeasureResult {
        var path: [CGPoint] = []
        var closed = false
        var fill: [[CGPoint]] = []
        var lines: [String] = []
        var anchor: CGPoint = .zero
    }
    private var measureResult: MeasureResult?
    /// Measure › Length: the summed objects and their total length.
    private var measureObjects: [CADEntity] = []
    private var measureTotal: CGFloat = 0

    private func showMeasure(_ result: MeasureResult) {
        measureResult = result
        onMessage?(result.lines.joined(separator: " · "))
        stateChanged()
    }

    private func measureClick(_ event: NSEvent) {
        let unit = drawingUnits.suffix
        let raw = viewport.screenToWorld(convert(event.locationInWindow, from: nil))
        let f: (CGFloat) -> String = { Measure.format($0) }
        switch measureKind {
        case .distance:
            let p = resolvedWorldPoint(for: event)
            guard let a = points.first else {
                measureResult = nil
                points = [p]
                stateChanged()
                return
            }
            points.removeAll()
            // ΔX, ΔY and the angle in drawing coordinates (UCS), like the status bar
            let d = toUCSVector(p - a)
            let angle = Geometry.normalizeAngle(atan2(d.y, d.x)) * 180 / .pi
            showMeasure(MeasureResult(path: [a, p], lines: ["Distance \(f(Geometry.distance(a, p))) \(unit)",
                                                             "ΔX \(f(d.x)) · ΔY \(f(d.y))", "Angle \(f(angle))°"],
                                      anchor: Geometry.midpoint(a, p)))

        case .angle:
            let p = resolvedWorldPoint(for: event)
            if points.count < 2 {
                if points.isEmpty { measureResult = nil }
                if let last = points.last, Geometry.distance(last, p) < 1e-9 { return }
                points.append(p)
                stateChanged()
                return
            }
            let vertex = points[0], first = points[1]
            points.removeAll()
            let sweep = Geometry.ccwDelta(from: Geometry.angle(from: vertex, to: first),
                                          to: Geometry.angle(from: vertex, to: p)) * 180 / .pi
            let inner = min(sweep, 360 - sweep)
            showMeasure(MeasureResult(path: [first, vertex, p],
                                      lines: ["Angle \(f(inner))°", "Outer \(f(360 - inner))°"], anchor: vertex))

        case .point:
            let p = resolvedWorldPoint(for: event)
            let ucs = toUCS(p)
            showMeasure(MeasureResult(path: [p], lines: ["X \(f(ucs.x)) · Y \(f(ucs.y)) \(unit)"], anchor: p))

        case .areaPoints:
            let p = resolvedWorldPoint(for: event)
            if points.isEmpty { measureResult = nil }
            if points.count >= 3,
               Geometry.distance(viewport.worldToScreen(p), viewport.worldToScreen(points[0])) < 8 || event.clickCount >= 2 {
                finishMeasuredArea()
                return
            }
            if let last = points.last, Geometry.distance(last, p) < 1e-9 { return }
            points.append(p)
            stateChanged()

        case .radius:
            guard let target = entity(at: raw, where: { $0 is Circle || $0 is Arc || $0 is Ellipse || $0 is Polyline }),
                  let info = Measure.radiusText(of: target, near: raw, unit: unit) else {
                onMessage?("Click a circle, an arc, an ellipse or an arc segment of a polyline.")
                NSSound.beep()
                return
            }
            showMeasure(MeasureResult(path: [info.center, info.onCurve], lines: [info.text], anchor: info.onCurve))

        case .areaBoundary:
            guard let loops = currentHatchFinder().region(at: raw) else {
                onMessage?("No closed area here – the boundary is open or has a gap larger than 3 px.")
                NSSound.beep()
                return
            }
            let area = Measure.area(ofLoops: loops)
            let perimeter = loops.reduce(0) { $0 + Measure.perimeter($1, closed: true) }
            var lines = ["Area \(f(area)) \(unit)²", "Perimeter \(f(perimeter)) \(unit)"]
            if loops.count > 1 { lines.append("\(loops.count - 1) island\(loops.count - 1 == 1 ? "" : "s") left out") }
            showMeasure(MeasureResult(fill: loops, lines: lines, anchor: raw))

        case .areaObject:
            guard let target = entity(at: raw, where: { Measure.areaAndPerimeter(of: $0) != nil }),
                  let info = Measure.areaAndPerimeter(of: target) else {
                onMessage?("Click a closed object – circle, ellipse, rectangle, closed polyline or spline, hatch.")
                NSSound.beep()
                return
            }
            showMeasure(MeasureResult(fill: info.outline, lines: ["Area \(f(info.area)) \(unit)²",
                                                                   "Perimeter \(f(info.perimeter)) \(unit)",
                                                                   target.typeName], anchor: raw))

        case .length:
            guard let target = entity(at: raw, where: { $0 is CurveEntity }) as? CurveEntity else {
                onMessage?("Click a line, arc, circle, polyline, spline or ellipse.")
                return
            }
            if let index = measureObjects.firstIndex(where: { $0 === target }) {
                measureObjects.remove(at: index)
                measureTotal -= target.curveLength
            } else {
                measureObjects.append(target)
                measureTotal += target.curveLength
            }
            measureResult = nil
            onMessage?("Length \(f(measureTotal)) \(unit) (\(measureObjects.count) object\(measureObjects.count == 1 ? "" : "s"))")
            stateChanged()
        }
    }

    /// Measuring an area by points: done (↩, right click, click on the first point).
    private func finishMeasuredArea() {
        guard points.count >= 3 else { return }
        let polygon = points
        points.removeAll()
        let unit = drawingUnits.suffix
        let box = HatchEntity.box(of: polygon)
        showMeasure(MeasureResult(path: polygon, closed: true, fill: [polygon],
                                  lines: ["Area \(Measure.format(Measure.polygonArea(polygon))) \(unit)²",
                                          "Perimeter \(Measure.format(Measure.perimeter(polygon, closed: true))) \(unit)"],
                                  anchor: CGPoint(x: box.midX, y: box.midY)))
    }

    /// The in-progress (live) measurement under the cursor.
    private func liveMeasure(cursor: CGPoint) -> MeasureResult? {
        guard currentTool == .measure, !points.isEmpty else { return nil }
        let unit = drawingUnits.suffix
        let f: (CGFloat) -> String = { Measure.format($0) }
        switch measureKind {
        case .distance:
            let a = points[0]
            return MeasureResult(path: [a, cursor], lines: ["\(f(Geometry.distance(a, cursor))) \(unit)"],
                                 anchor: Geometry.midpoint(a, cursor))
        case .angle:
            guard points.count == 2 else { return MeasureResult(path: [points[0], cursor], anchor: cursor) }
            let sweep = Geometry.ccwDelta(from: Geometry.angle(from: points[0], to: points[1]),
                                          to: Geometry.angle(from: points[0], to: cursor)) * 180 / .pi
            return MeasureResult(path: [points[1], points[0], cursor], lines: ["\(f(min(sweep, 360 - sweep)))°"], anchor: points[0])
        case .areaPoints:
            let polygon = points + [cursor]
            return MeasureResult(path: polygon, closed: polygon.count >= 3, fill: polygon.count >= 3 ? [polygon] : [],
                                 lines: polygon.count >= 3 ? ["\(f(Measure.polygonArea(polygon))) \(unit)²"] : [], anchor: cursor)
        default:
            return nil
        }
    }

    private func drawMeasure(in context: CGContext, transform: CGAffineTransform) {
        guard currentTool == .measure else { return }
        let color = NSColor.systemTeal
        // summed objects (Length)
        for entity in measureObjects {
            entity.draw(in: context, transform: transform, style: StrokeStyle(color: color, lineWidth: 3))
        }
        var results: [MeasureResult] = []
        if let result = measureResult { results.append(result) }
        if let cursor = currentWorldPoint, let live = liveMeasure(cursor: cursor) { results.append(live) }
        for result in results {
            context.saveGState()
            for loop in result.fill where loop.count >= 3 {
                context.addLines(between: loop.map { $0.applying(transform) })
                context.closePath()
            }
            context.setFillColor(color.withAlphaComponent(0.16).cgColor)
            context.fillPath(using: .evenOdd)
            let screen = result.path.map { $0.applying(transform) }
            if screen.count >= 2, screen.allSatisfy({ DrawingSafety.isFinite($0) }) {
                context.setStrokeColor(color.cgColor)
                context.setLineWidth(1.5)
                context.addLines(between: screen)
                if result.closed { context.closePath() }
                context.strokePath()
            }
            context.setFillColor(color.cgColor)
            for p in screen where DrawingSafety.isFinite(p) {
                context.fillEllipse(in: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5))
            }
            context.restoreGState()
            drawLabel(result.lines, at: result.anchor.applying(transform), in: context)
        }
    }

    /// A framed label (measurement result).
    private func drawLabel(_ lines: [String], at point: CGPoint, in context: CGContext) {
        guard !lines.isEmpty, DrawingSafety.isFinite(point) else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                         .foregroundColor: NSColor.white]
        let text = lines.joined(separator: "\n") as NSString
        let size = text.boundingRect(with: CGSize(width: 600, height: 400), options: [.usesLineFragmentOrigin],
                                     attributes: attributes).size
        var rect = CGRect(x: point.x + 12, y: point.y + 10, width: ceil(size.width) + 12, height: ceil(size.height) + 8)
        rect.origin.x = min(rect.origin.x, bounds.width - rect.width - 4)
        rect.origin.y = min(rect.origin.y, bounds.height - rect.height - 4)
        context.saveGState()
        let background = CGPath(roundedRect: rect, cornerWidth: 5, cornerHeight: 5, transform: nil)
        context.addPath(background)
        context.setFillColor(Theme.canvasLabelBackground.cgColor)
        context.fillPath()
        context.addPath(background)
        context.setStrokeColor(NSColor.systemTeal.cgColor)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
        text.draw(with: rect.insetBy(dx: 6, dy: 4), options: [.usesLineFragmentOrigin], attributes: attributes)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // a click in the drawing ends typing – in the “only while typing” mode the box (without an entered value) hides
        valueBoxRequested = false
        let screenPoint = convert(event.locationInWindow, from: nil)
        mouseDownScreenPoint = screenPoint

        if pendingMirror != nil {
            answerMirror(deleteOriginals: false)
            ignoreNextMouseUp = true
            return
        }
        // a click in the drawing = No (same as right click and as for the Mirror question)
        if awaitingCloseAnswer {
            answerClosePrompt(false)
            ignoreNextMouseUp = true
            return
        }
        // Control-click = the context menu (like holding the right button – for a trackpad)
        if event.modifierFlags.contains(.control) && currentTool == .select && !isBusy {
            showContextMenu(for: event)
            return
        }

        if event.modifierFlags.contains(.command) {
            isPanning = true
            lastPanPoint = screenPoint
            NSCursor.closedHand.set()
            return
        }

        // a window started with a click: this click is its opposite corner
        if selectionBoxAwaitsCorner, let start = selectionBoxStart {
            finishBox(from: start, to: screenPoint)
            ignoreNextMouseUp = true
            return
        }

        // pasted objects: the click places them
        if pasteRequest != nil {
            finishPaste(at: resolvedWorldPoint(for: event))
            ignoreNextMouseUp = true
            return
        }

        // rotating the drawing coordinates: an object, or two points
        if let request = axisPick {
            if request.byObject {
                let world = viewport.screenToWorld(screenPoint)
                guard let axis = axisOfObject(near: world) else {
                    onMessage?("Click a line, a polyline segment or a text.")
                    NSSound.beep()
                    return
                }
                axisPick = nil
                stateChanged()
                request.completion(axis)
            } else {
                let point = pickPoint(for: event)
                if singlePointPick {
                    axisPick = nil
                    activeSnap = nil
                    stateChanged()
                    request.completion((point, 0))
                    return
                }
                if let first = request.first {
                    guard Geometry.distance(first, point) > 1e-9 else { NSSound.beep(); return }
                    axisPick = nil
                    activeSnap = nil
                    stateChanged()
                    request.completion((first, Geometry.angle(from: first, to: point)))
                } else {
                    axisPick = (request.prompt, point, false, request.completion)
                    currentWorldPoint = point
                    stateChanged()
                }
            }
            return
        }

        // rectangle selection (plot area, new viewport)
        if let request = pickRequest {
            let point = pickPoint(for: event)
            if let first = request.first {
                let rect = CGRect(x: min(first.x, point.x), y: min(first.y, point.y),
                                  width: abs(point.x - first.x), height: abs(point.y - first.y))
                guard rect.width > 0, rect.height > 0 else { NSSound.beep(); return }
                pickRequest = nil
                activeSnap = nil
                stateChanged()
                request.completion(rect)
            } else {
                pickRequest = (request.prompt, point, request.completion)
                currentWorldPoint = point
                stateChanged()
            }
            return
        }

        let worldPoint = viewport.screenToWorld(screenPoint)

        // layout: ⌥-drag inside a viewport pans the model, a double-click opens the model in the viewport's area
        if paperSpace != nil, currentTool == .select {
            if event.modifierFlags.contains(.option), let hit = viewportAt(worldPoint) {
                if hit.isLocked {
                    onMessage?("The viewport is locked – unlock it in Properties to pan its view.")
                    NSSound.beep()
                } else {
                    viewportPan = (hit, screenPoint, hit.modelCenter)
                    NSCursor.closedHand.set()
                }
                return
            }
            if event.clickCount == 2, let hit = viewportAt(worldPoint), entity(at: worldPoint) == nil || entity(at: worldPoint) === hit {
                onViewportDoubleClick?(hit)
                return
            }
        }

        // grips and points: a second click finishes the move, a click on a grip starts it, Shift-click marks a point
        if [.select, .editPoints].contains(currentTool) {
            if activeGrip != nil {
                finishGrip(at: resolvedWorldPoint(for: event))
                return
            }
            let shift = event.modifierFlags.contains(.shift)
            if let hit = grip(atScreen: screenPoint) {
                let ref = PointRef(id: hit.entity.id, index: hit.index)
                let kind = Grips.grips(of: hit.entity)[hit.index].kind
                if shift {
                    // segment midpoints move the whole segment – they are not added to a multiple selection
                    if let index = selectedPoints.firstIndex(of: ref) {
                        selectedPoints.remove(at: index)
                    } else if kind != .midpoint {
                        selectedPoints.append(ref)
                    } else {
                        NSSound.beep()
                    }
                    onPromptChanged?(prompt)
                    return
                }
                let wasSelected = selectedPoints.contains(ref)
                if !wasSelected {
                    selectedPoints = currentTool == .editPoints && kind != .midpoint ? [ref] : []
                }
                let refs = wasSelected ? selectedPoints : [ref]
                beginGripEdit(base: hit.point, items: gripItems(for: refs),
                              justSelected: currentTool == .editPoints && !wasSelected)
                return
            }
            if currentTool == .editPoints {
                // empty space: a rectangle around points (Shift adds)
                if !shift { selectedPoints.removeAll() }
                selectionBoxStart = screenPoint
                selectionBoxEnd = screenPoint
                selectionBoxAdditive = shift
                stateChanged()
                return
            }
            if !shift && !selectedPoints.isEmpty { selectedPoints.removeAll() }
        }

        if isSelectingObjects {
            // double-click on text = edit in a dialog
            if currentTool == .select, event.clickCount == 2, let text = entity(at: worldPoint) as? TextEntity {
                beginEditing(text)
                return
            }
            // double-click on a block = edit it in place
            if currentTool == .select, event.clickCount == 2, let reference = entity(at: worldPoint) as? BlockReference {
                onBlockEditRequested?(reference)
                return
            }
            // a click on an already selected object in selection mode = start of a drag (the point snaps)
            if currentTool == .select, !event.modifierFlags.contains(.shift),
               let hit = entity(at: worldPoint), selectionManager?.isSelected(hit) ?? false {
                dragMoveBase = worldPoint
                let base = resolvedWorldPoint(for: event)
                dragMoveBase = base
                currentWorldPoint = base
                onPromptChanged?("Move: drag to the new position and release (snap works) · Esc = cancel")
                needsDisplay = true
                return
            }
            handleSelectMouseDown(at: screenPoint, extend: event.modifierFlags.contains(.shift))
            return
        }

        // Stretch: a window over the points (drag, or two clicks)
        if currentTool == .stretch && stage == .window {
            if let start = selectionBoxStart {
                selectionBoxStart = nil
                selectionBoxEnd = nil
                finishStretchWindow(from: start, to: screenPoint)
            } else {
                selectionBoxStart = screenPoint
                selectionBoxEnd = screenPoint
                onPromptChanged?(prompt)
            }
            needsDisplay = true
            return
        }

        switch currentTool {
        case .measure:
            measureClick(event)

        case .trim, .extend:
            if event.modifierFlags.contains(.shift) {
                // Shift+click = select/deselect a cutting edge or boundary
                if let edge = entity(at: worldPoint) {
                    if let index = edges.firstIndex(where: { $0 === edge }) {
                        edges.remove(at: index)
                    } else {
                        edges.append(edge)
                    }
                    stateChanged()
                }
            } else if currentTool == .trim {
                trimClick(at: worldPoint)
            } else {
                extendClick(at: worldPoint)
            }
            updateHover(at: worldPoint)

        case .powerTrim:
            fence = [screenPoint]
            hoverRemoved = nil
            hoverAdded.removeAll()

        case .fillet:
            filletClick(at: worldPoint)

        case .chamfer:
            chamferClick(at: worldPoint)

        case .breakObject, .breakAtPoint:
            breakClick(at: worldPoint, snapped: resolvedWorldPoint(for: event))

        case .offset:
            offsetClick(at: picked.isEmpty ? worldPoint : resolvedWorldPoint(for: event))

        case .hatch:
            createHatch(at: worldPoint)

        case .roomLabel:
            placeRoomLabel(at: worldPoint)

        case .text:
            textClick(at: resolvedWorldPoint(for: event))

        case .matchProperties:
            if matchSource == nil {
                if let source = entity(at: worldPoint) {
                    matchSource = source
                    stateChanged()
                } else {
                    onMessage?("Click the object whose properties you want to copy.")
                    NSSound.beep()
                }
            } else if let target = entity(at: worldPoint) {
                applyMatch(to: [target])
            } else {
                // a click into empty space = start of a window
                selectionBoxStart = screenPoint
                selectionBoxEnd = screenPoint
            }

        case .dimContinue:
            if chainSource == nil {
                pickChainSource(at: worldPoint)
            } else {
                addChainDimension(to: resolvedWorldPoint(for: event))
            }

        case .dimRadius, .dimDiameter:
            if picked.isEmpty {
                if let target = entity(at: worldPoint, where: { $0 is Circle || $0 is Arc }) {
                    picked = [(target, worldPoint)]
                    currentWorldPoint = worldPoint
                    stateChanged()
                } else {
                    onMessage?("Click a circle or an arc.")
                }
            } else {
                finishPoints(with: resolvedWorldPoint(for: event))
            }

        default:
            let point = resolvedWorldPoint(for: event)
            let hadPoints = !points.isEmpty
            addPoint(point, clickCount: event.clickCount)
            // for a line/circle/rectangle the shape can also be “pulled out” with the mouse
            ignoreNextMouseUp = hadPoints || points.isEmpty
            currentWorldPoint = point
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let screenPoint = convert(event.locationInWindow, from: nil)
        moveCrosshair(event)

        if let pan = viewportPan {
            // screen offset → paper mm → model units (the content follows the mouse)
            let zoom = viewport.getCurrentZoom()
            let k = pan.viewport.paperMMPerUnit(mmPerUnit: paperSpace?.modelMMPerUnit ?? 1)
            let dx = (screenPoint.x - pan.start.x) / zoom / k
            let dy = (screenPoint.y - pan.start.y) / zoom / k
            viewportPan = (pan.viewport, pan.start, CGPoint(x: pan.viewport.modelCenter.x - dx, y: pan.viewport.modelCenter.y - dy))
            needsDisplay = true
            return
        }

        if isPanning {
            interactiveViewChange {
                viewport.pan(by: CGPoint(x: screenPoint.x - lastPanPoint.x, y: screenPoint.y - lastPanPoint.y))
            }
            lastPanPoint = screenPoint
            return
        }
        if selectionBoxStart != nil {
            selectionBoxEnd = screenPoint
            overlayRedraw()
            return
        }
        if activeGrip != nil, let down = mouseDownScreenPoint, Geometry.distance(down, screenPoint) > 4 {
            gripDragged = true
        }
        if currentTool == .powerTrim, !fence.isEmpty {
            if let last = fence.last, Geometry.distance(last, screenPoint) >= 2 { fence.append(screenPoint) }
            needsDisplay = true
            return
        }

        let worldPoint = resolvedWorldPoint(for: event)
        currentWorldPoint = worldPoint
        onCursorMoved?(worldPoint)
        updateDynamicInput()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let screenPoint = convert(event.locationInWindow, from: nil)

        if let pan = viewportPan {
            viewportPan = nil
            drawingCursor.set()
            if pan.center != pan.viewport.modelCenter, let copy = pan.viewport.clone() as? ViewportEntity {
                copy.modelCenter = pan.center
                selectionManager?.deselect([pan.viewport])
                onCommit?([pan.viewport], [copy], "Pan Viewport")
            }
            needsDisplay = true
            return
        }

        if isPanning {
            isPanning = false
            drawingCursor.set()
            return
        }

        // a grip dragged with the mouse is released = done; without dragging a second click is awaited
        if let grip = activeGrip {
            if gripDragged {
                finishGrip(at: resolvedWorldPoint(for: event))
            } else if grip.justSelected {
                // the press only selected a point – the move has not started
                activeGrip = nil
                stateChanged()
            }
            return
        }

        if let base = dragMoveBase {
            let target = resolvedWorldPoint(for: event)
            let dragged = mouseDownScreenPoint.map { Geometry.distance($0, screenPoint) > 4 } ?? false
            dragMoveBase = nil
            activeSnap = nil
            if dragged { finishDragMove(from: base, to: target) }
            stateChanged()
            return
        }

        if currentTool == .stretch && stage == .window, let start = selectionBoxStart {
            // drag = finished window; just a click = waiting for the second corner
            if Geometry.distance(start, screenPoint) > 4 {
                selectionBoxStart = nil
                selectionBoxEnd = nil
                finishStretchWindow(from: start, to: screenPoint)
            }
            needsDisplay = true
            return
        }

        if let start = selectionBoxStart, let end = selectionBoxEnd {
            // drag = finished window; just a click = waiting for the opposite corner
            if Geometry.distance(start, screenPoint) <= 4 {
                selectionBoxAwaitsCorner = true
                onPromptChanged?(prompt)
                needsDisplay = true
                return
            }
            finishBox(from: start, to: end)
            return
        }

        if currentTool == .powerTrim, !fence.isEmpty {
            let path = fence + [screenPoint]
            fence.removeAll()
            let dragged = path.count > 2 || Geometry.distance(path[0], screenPoint) > 4
            if dragged {
                powerTrimFence(path)
            } else {
                // a click (no stroke) extends, like Extend
                extendClick(at: viewport.screenToWorld(screenPoint))
            }
            updateHover(at: viewport.screenToWorld(screenPoint))
            needsDisplay = true
            return
        }

        if currentTool == .text, textKind == .multiline, let first = textBoxStart,
           let down = mouseDownScreenPoint, Geometry.distance(down, screenPoint) > 6 {
            finishTextBox(from: first, to: resolvedWorldPoint(for: event))
            return
        }

        if ignoreNextMouseUp {
            ignoreNextMouseUp = false
            return
        }

        // dragging with the mouse (instead of a second click) finishes a line, circle, rectangle and transforms
        if [.line, .circle, .polygon, .rectangle].contains(currentTool) || (currentTool.isTransform && stage == .points)
            || (drawsOutline && outlineShape == .rectangle),
           points.count == 1,
           let down = mouseDownScreenPoint, Geometry.distance(screenPoint, down) > 4 {
            addPoint(resolvedWorldPoint(for: event))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        // over a floating palette the drawing does not follow the mouse
        if paletteLayer.isOverPalette(event.locationInWindow) {
            if crosshair.point != nil { crosshair.point = nil }
            return
        }
        // mouse movement changes only the overlay elements (snap, preview, grips) – the scene is not redrawn
        overlayOnlyRedraw = true
        defer { overlayOnlyRedraw = false }
        moveCrosshair(event)
        if pickRequest != nil || (axisPick != nil && !(axisPick?.byObject ?? true)) {
            let point = pickPoint(for: event)
            currentWorldPoint = point
            onCursorMoved?(point)
            needsDisplay = true
            return
        }
        if selectionBoxStart != nil, selectionBoxAwaitsCorner || (currentTool == .stretch && stage == .window) {
            selectionBoxEnd = convert(event.locationInWindow, from: nil)
            needsDisplay = true
        }
        let hadSnap = activeSnap != nil
        let worldPoint = resolvedWorldPoint(for: event)
        currentWorldPoint = worldPoint
        onCursorMoved?(worldPoint)
        if expectsPoint || hadSnap || activeSnap != nil { needsDisplay = true }
        if [.trim, .extend, .powerTrim].contains(currentTool) { updateHover(at: worldPoint) }
        if currentTool == .breakObject { updateBreakPreview(at: worldPoint) }
        if currentTool == .hatch { updateHatchHover(at: worldPoint) }
        if currentTool == .roomLabel { updateRoomHover(at: worldPoint) }
        if currentTool == .offset { updateOffsetPreview() }
        if [.select, .editPoints].contains(currentTool), activeGrip == nil {
            let screenPoint = convert(event.locationInWindow, from: nil)
            let hit = grip(atScreen: screenPoint).map { (id: $0.entity.id, index: $0.index) }
            if hit?.id != hoverGrip?.id || hit?.index != hoverGrip?.index {
                hoverGrip = hit
                needsDisplay = true
            }
        }
        if activeGrip != nil { needsDisplay = true }
        updateDynamicInput()
    }

    /// Shift pressed or released: a rectangle preview switches between a square and a free rectangle
    /// right away, without waiting for the mouse to move.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        let shift = event.modifierFlags.contains(.shift)
        guard shift != shiftHeld else { return }
        shiftHeld = shift
        let sizesRectangle = (currentTool == .rectangle && !rectangleSquare) || (drawsOutline && outlineShape == .rectangle)
        guard sizesRectangle, !points.isEmpty else { return }
        updateDynamicInput()
        onPromptChanged?(prompt)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        crosshair.point = nil
        snapTracker.hover(over: nil)
        if activeSnap != nil {
            activeSnap = nil
            needsDisplay = true
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        if pasteRequest != nil {
            cancelCurrentOperation()
            onMessage?("Paste canceled")
            return
        }
        if pendingMirror != nil {
            answerMirror(deleteOriginals: false)
            return
        }
        if awaitingCloseAnswer {
            answerClosePrompt(false)
            return
        }
        // Select with nothing in progress: holding the button opens the context menu, a short click keeps its usual job
        if currentTool == .select && !isBusy && isRightButtonHeld() {
            showContextMenu(for: event)
            return
        }
        // right click: confirm / cancel the step in progress; when the tool isn't waiting for anything, it ends it
        // (another right click while idle then repeats the tool)
        let nothingSelected = selectionManager?.isEmpty ?? true
        switch currentTool {
        case .polyline, .spline, .leader:
            if points.isEmpty { endCurrentTool() } else { confirm() }
        case .wall:
            if points.isEmpty { endCurrentTool() } else if points.count >= 2 { confirm() } else { cancelCurrentOperation() }
        case .revisionCloud, .wipeout:
            if points.isEmpty {
                endCurrentTool()
            } else if outlineShape == .polygon && points.count >= 3 {
                confirm()
            } else {
                cancelCurrentOperation()
            }
        case .trim, .extend:
            confirm()
        case .move, .copy, .rotate, .scale, .mirror, .array, .blockCreate:
            if stage == .selectObjects {
                if nothingSelected { endCurrentTool() } else { confirm() }
            } else if currentTool == .copy && !points.isEmpty {
                confirm()
            } else if isBusy {
                cancelCurrentOperation()
            } else {
                endCurrentTool()
            }
        case .explode, .join, .hatchRebuild, .hatchCut, .wallFromCurve:
            if nothingSelected { endCurrentTool() } else { confirm() }
        case .measure where measureKind == .areaPoints && points.count >= 3:
            confirm()
        default:
            if isBusy {
                cancelCurrentOperation()
            } else if currentTool != .select {
                endCurrentTool()
            } else if !repeatLastTool() {
                super.rightMouseDown(with: event)
            }
        }
    }

    /// Waits until the right button is released or the hold time (Settings › Cursor & Mouse) has passed;
    /// true = it is still held. A shorter click finishes or repeats commands.
    private func isRightButtonHeld() -> Bool {
        let release = window?.nextEvent(matching: .rightMouseUp, until: Date(timeIntervalSinceNow: AppSettings.contextMenuHoldTime),
                                        inMode: .eventTracking, dequeue: false)
        return release == nil
    }

    private func showContextMenu(for event: NSEvent) {
        guard let menu = onContextMenuRequested?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    /// Ends the tool (back to Select); a right click or ↩ while idle then repeats it.
    private func endCurrentTool() {
        let tool = currentTool
        guard tool != .select else { return }
        onToolChangeRequested?(.select)
        if AppSettings.repeatLastTool {
            onMessage?("\(tool.title) ended · ↩ or right-click repeats it")
        } else {
            onMessage?("\(tool.title) ended")
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        // middle-button double-click = Zoom Extents (as in AutoCAD)
        if event.buttonNumber == 2 && event.clickCount == 2 {
            isPanning = false
            onZoomExtentsRequested?()
            return
        }
        isPanning = true
        lastPanPoint = convert(event.locationInWindow, from: nil)
    }

    override func otherMouseDragged(with event: NSEvent) {
        guard isPanning else { return }
        let screenPoint = convert(event.locationInWindow, from: nil)
        interactiveViewChange {
            viewport.pan(by: CGPoint(x: screenPoint.x - lastPanPoint.x, y: screenPoint.y - lastPanPoint.y))
        }
        lastPanPoint = screenPoint
    }

    override func otherMouseUp(with event: NSEvent) {
        isPanning = false
    }

    override func scrollWheel(with event: NSEvent) {
        let screenPoint = convert(event.locationInWindow, from: nil)
        let flags = event.modifierFlags
        let precise = event.hasPreciseScrollingDeltas
        if precise && !flags.contains(.command) && !AppSettings.trackpadScrollZooms {
            // trackpad / Magic Mouse: two-finger pan
            interactiveViewChange { viewport.pan(by: CGPoint(x: event.scrollingDeltaX, y: -event.scrollingDeltaY)) }
            return
        }
        // mouse wheel (or ⌘ + trackpad): zoom. macOS sends Shift + wheel as a horizontal scroll.
        var delta = event.scrollingDeltaY
        if delta == 0 { delta = event.scrollingDeltaX }
        guard delta != 0, delta.isFinite else { return }
        if AppSettings.zoomWheelReversed { delta = -delta }
        var step: CGFloat = (precise ? 0.01 : 0.1) * AppSettings.zoomSpeed
        if flags.contains(.shift) { step *= 0.25 }      // fine
        if flags.contains(.option) { step *= 3 }        // fast
        let factor = max(0.25, min(4.0, exp(delta * step)))
        let anchor = AppSettings.zoomToCursor ? screenPoint : CGPoint(x: bounds.midX, y: bounds.midY)
        interactiveViewChange { viewport.zoomAt(screenPoint: anchor, factor: factor) }
    }

    override func magnify(with event: NSEvent) {
        let screenPoint = convert(event.locationInWindow, from: nil)
        let anchor = AppSettings.zoomToCursor ? screenPoint : CGPoint(x: bounds.midX, y: bounds.midY)
        interactiveViewChange {
            viewport.zoomAt(screenPoint: anchor, factor: max(0.5, min(2.0, 1.0 + event.magnification * AppSettings.zoomSpeed)))
        }
    }

    // MARK: Selection

    private func handleSelectMouseDown(at screenPoint: CGPoint, extend: Bool) {
        guard let selectionManager = selectionManager else { return }
        let worldPoint = viewport.screenToWorld(screenPoint)

        if let hit = entity(at: worldPoint) {
            // a grouped object brings the rest of its group
            let picked = withGroups([hit])
            if extend || stage == .selectObjects {
                if selectionManager.isSelected(hit) {
                    selectionManager.deselect(picked)
                } else {
                    selectionManager.select(picked, additive: true)
                }
            } else {
                selectionManager.select(picked)
            }
            if picked.count > 1 {
                onMessage?("Group of \(picked.count) objects · Edit › Ungroup splits it")
            }
        } else {
            if !extend && stage != .selectObjects { selectionManager.clearSelection() }
            selectionBoxStart = screenPoint
            selectionBoxEnd = screenPoint
            selectionBoxAdditive = extend || stage == .selectObjects
        }
        stateChanged()
    }

    /// Lines used to tell whether a crossing selection really hit the object
    /// (not just its bounds – those are needlessly large for hatches, dimensions and leaders with text).
    private static func crossingPrimitives(of entity: CADEntity) -> [Primitive] {
        func polygon(_ points: [CGPoint]) -> [Primitive] {
            guard points.count >= 2 else { return [] }
            return points.indices.map { Primitive.segment(a: points[$0], b: points[($0 + 1) % points.count], param: 0) }
        }
        switch entity {
        case let hatch as HatchEntity:
            // hatch: only its outline (not when the selection is entirely inside the hatched area)
            return hatch.loops.flatMap { polygon($0) }
        case let wipeout as WipeoutEntity:
            return polygon(wipeout.vertices)
        case let text as TextEntity:
            return polygon(text.corners)
        case let dimension as DimensionEntity:
            // dimension / leader: lines, arcs, arrows and the text rectangle
            let parts = dimension.buildParts()
            var result: [Primitive] = parts.lines.map { Primitive.segment(a: $0.0, b: $0.1, param: 0) }
            result += parts.arcs.map { Primitive.arc(center: $0.center, radius: $0.radius, start: $0.start, sweep: $0.sweep, param: 0) }
            for arrow in parts.arrows { result += polygon(dimension.arrowPolygon(arrow.tip, arrow.direction)) }
            let lines = [dimension.displayText, dimension.belowText].filter { !$0.isEmpty }
            let height = dimension.textHeight
            for (index, line) in lines.enumerated() {
                let width = CGFloat(line.count) * height * 0.85
                let x0: CGFloat
                switch parts.textAlignment {
                case .left: x0 = 0
                case .center: x0 = -width / 2
                case .right: x0 = -width
                }
                let gap = height * 0.25
                let y0: CGFloat = index == 1 ? -gap - height : (parts.textAbove ? gap : -height / 2)
                let local = [CGPoint(x: x0, y: y0), CGPoint(x: x0 + width, y: y0),
                             CGPoint(x: x0 + width, y: y0 + height), CGPoint(x: x0, y: y0 + height)]
                let t = CGAffineTransform(translationX: parts.textAnchor.x, y: parts.textAnchor.y).rotated(by: parts.textAngle)
                result += polygon(local.map { $0.applying(t) })
            }
            return result
        default:
            return entity.primitives()
        }
    }

    /// Left to right = only whole objects inside (window), right to left = also crossed ones (crossing).
    /// Closes the window (dragged or clicked) and applies it according to the tool.
    private func finishBox(from start: CGPoint, to end: CGPoint) {
        selectionBoxStart = nil
        selectionBoxEnd = nil
        if currentTool == .editPoints {
            finishPointBox(from: start, to: end)
        } else if currentTool == .matchProperties {
            if abs(end.x - start.x) > 3 || abs(end.y - start.y) > 3 {
                applyMatch(to: entitiesInBox(from: start, to: end))
            }
        } else {
            finishSelectionBox(from: start, to: end)
        }
        onPromptChanged?(prompt)
        needsDisplay = true
    }

    private func finishSelectionBox(from start: CGPoint, to end: CGPoint) {
        guard let selectionManager = selectionManager,
              abs(end.x - start.x) > 3 || abs(end.y - start.y) > 3 else { return }
        selectionManager.select(withGroups(entitiesInBox(from: start, to: end)), additive: selectionBoxAdditive)
    }

    /// The objects and the other members of their groups (only editable ones) – unless
    /// Edit › Select Groups as a Whole is off.
    private func withGroups(_ entities: [CADEntity]) -> [CADEntity] {
        guard AppSettings.selectWholeGroups, entities.contains(where: { $0.groupID != nil }) else { return entities }
        return Groups.expanded(entities, from: editableEntities)
    }

    /// Objects in the window (screen points): left to right fully inside, right to left also crossed.
    private func entitiesInBox(from start: CGPoint, to end: CGPoint) -> [CADEntity] {
        let w1 = viewport.screenToWorld(start)
        let w2 = viewport.screenToWorld(end)
        let rect = CGRect(x: min(w1.x, w2.x), y: min(w1.y, w2.y),
                          width: abs(w2.x - w1.x), height: abs(w2.y - w1.y))
        let crossing = end.x < start.x

        return editableEntities.filter { entity in
            let box = entity.boundingBox()
            // infinite construction line: never fully inside, crossing only when the window really intersects it
            if box.isNull && !crossing { return false }
            if !crossing { return rect.contains(box) }
            guard box.isNull || rect.intersects(box.insetBy(dx: -1e-9, dy: -1e-9)) else { return false }
            // a more precise test: does any edge of the rectangle intersect the entity, or is it inside?
            if !box.isNull && rect.contains(box) { return true }
            let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                           CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.maxY)]
            let sides = (0..<4).map { Primitive.segment(a: corners[$0], b: corners[($0 + 1) % 4], param: 0) }
            let own = CADEditorView.crossingPrimitives(of: entity)
            if own.isEmpty { return true }
            for side in sides {
                for primitive in own where !side.intersections(with: primitive).isEmpty { return true }
            }
            return own.contains { primitive in
                if case let .segment(a, _, _) = primitive { return rect.contains(a) }
                if case let .arc(c, r, s, _, _) = primitive { return rect.contains(Geometry.pointOnCircle(c, r, s)) }
                return false
            }
        }
    }

    // MARK: Keyboard

    /// ↩, Enter on the numeric keypad or the space bar – confirmation (space bar as in AutoCAD).
    static func isConfirmKey(_ event: NSEvent) -> Bool {
        return [36, 76, 49].contains(event.keyCode)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])

        // Mirror: delete originals? (Y / A = yes, N / Enter = no, Esc = cancel)
        if pendingMirror != nil {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if event.keyCode == 53 {
                pendingMirror = nil
                onMessage?("Mirror canceled")
                stateChanged()
            } else if key == "y" || key == "a" {
                answerMirror(deleteOriginals: true)
            } else if key == "n" || CADEditorView.isConfirmKey(event) {
                answerMirror(deleteOriginals: false)
            } else {
                NSSound.beep()
            }
            return
        }

        if axisPick != nil {
            if event.keyCode == 53 {
                let request = axisPick
                axisPick = nil
                stateChanged()
                request?.completion(nil)
            } else {
                NSSound.beep()
            }
            return
        }

        // rectangle selection: Esc cancels, other keys are ignored
        if pickRequest != nil {
            if event.keyCode == 53 {
                cancelPick()
                stateChanged()
            } else {
                NSSound.beep()
            }
            return
        }

        // waiting for the answer to “Close?”
        if awaitingCloseAnswer {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if event.keyCode == 53 {                       // Esc = keep drawing
                cancelClosePrompt()
            } else if key == "y" || key == "a" {           // Y (yes) / A (ano, Czech for yes)
                answerClosePrompt(true)
            } else if key == "n" || CADEditorView.isConfirmKey(event) {
                answerClosePrompt(false)
            } else {
                NSSound.beep()
            }
            return
        }

        // the letters inside a tool work without Shift – Shift + a letter stays a tool shortcut (⇧T, ⇧C…)
        let shifted = event.modifierFlags.contains(.shift)

        // C with continuous lines = the last line back to the start of the chain
        if modifiers.isEmpty, !shifted, currentTool == .line, lineContinue, lineChainCount >= 2,
           let start = lineChainStart, let last = points.last,
           event.charactersIgnoringModifiers?.lowercased() == "c", !dynamicInput.hasLockedValue {
            onCommit?([], [Line(start: last, end: start, layer: currentLayerName)], "Close Lines")
            endLineChain()
            return
        }

        // C while drawing a polyline / spline = close right away
        if modifiers.isEmpty, !shifted, [.polyline, .spline].contains(currentTool), points.count >= 3,
           event.charactersIgnoringModifiers?.lowercased() == "c", !dynamicInput.hasLockedValue {
            finishOpenEnded(closed: true)
            return
        }

        // C on a line in progress that cannot be closed yet: don't switch to Circle (the drawing would be lost)
        if modifiers.isEmpty, !shifted, !points.isEmpty, !dynamicInput.hasLockedValue,
           [.polyline, .spline].contains(currentTool) || (currentTool == .line && lineContinue),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            onMessage?(currentTool == .line ? "Draw at least two lines before closing (C)." : "Closing (C) needs at least three points.")
            NSSound.beep()
            return
        }

        switch event.keyCode {
        case 53: // Escape
            if selectionBoxAwaitsCorner {
                // only the window started with a click is dropped, the tool goes on
                selectionBoxStart = nil
                selectionBoxEnd = nil
                onPromptChanged?(prompt)
                needsDisplay = true
            } else if dynamicInput.hasLockedValue {
                cancelDynamicInput()
            } else if [.polyline, .spline].contains(currentTool) && points.count >= 2 {
                requestFinishOpenEnded()
            } else if currentTool == .wall && points.count >= 2 {
                finishWall(closed: false)
            } else if isBusy {
                cancelCurrentOperation()
            } else if !selectedPoints.isEmpty {
                selectedPoints.removeAll()
                onPromptChanged?(prompt)
            } else if currentTool == .measure, measureResult != nil || !measureObjects.isEmpty {
                measureResult = nil
                measureObjects.removeAll()
                measureTotal = 0
                onMessage?("")
                stateChanged()
            } else if currentTool != .select {
                onToolChangeRequested?(.select)
            } else {
                selectionManager?.clearSelection()
            }
            return

        case 36, 76, 49: // Return, Enter, space bar (as in AutoCAD)
            if dynamicInput.hasLockedValue {
                commitDynamicInput()
            } else if pasteRequest != nil {
                if let point = currentWorldPoint { finishPaste(at: point) }
            } else if !repeatLastTool() {
                confirm()
            }
            return

        case 48: // Tab – jump into the value box
            if inputMode != .none {
                valueBoxRequested = true
                updateDynamicInput()
                dynamicInput.focusFirstField()
            }
            return

        case 51: // Backspace
            if ([.polyline, .spline, .wall, .leader, .revisionCloud, .wipeout].contains(currentTool) || (currentTool == .measure && measureKind == .areaPoints))
                && !points.isEmpty {
                points.removeLast()
                stateChanged()
            } else if currentTool == .select {
                onDeleteRequested?()
            }
            return

        case 117: // Forward Delete
            if currentTool == .select { onDeleteRequested?() }
            return

        // F3, F7–F10, F12 and ⌥ + digit never get here – the window toggles them already (MainViewController.handleModeKey)
        default:
            break
        }

        guard modifiers.isEmpty, let characters = event.charactersIgnoringModifiers, !characters.isEmpty else {
            super.keyDown(with: event)
            return
        }

        // numeric input → the box at the cursor (length, radius, angle, expression…)
        if characters.allSatisfy({ "0123456789.,-+(".contains($0) }) {
            if inputMode != .none {
                valueBoxRequested = true
                updateDynamicInput()
                dynamicInput.beginTyping(characters)
            } else {
                onMessage?("This tool does not take a typed value.")
            }
            return
        }

        // polygon: I / C / E switches the method, S = number of sides (like POLYGON in AutoCAD)
        if currentTool == .polygon, !shifted, characters.count == 1, polygonLetter(characters.lowercased()) {
            return
        }

        // rectangle: C = from the center / from a corner, S = square
        if currentTool == .rectangle, !shifted, characters.count == 1, rectangleLetter(characters.lowercased()) {
            return
        }

        // revision cloud and wipeout: R / P = rectangle or corners, A = arc size (cloud), C = close
        if drawsOutline, !shifted, characters.count == 1, outlineLetter(characters.lowercased()) {
            return
        }

        // wall: T = thickness, J = side, C = close
        if currentTool == .wall, !shifted, characters.count == 1, wallLetter(characters.lowercased()) {
            return
        }
        if currentTool == .wallFromCurve, !shifted, characters.count == 1, wallFromCurveLetter(characters.lowercased()) {
            return
        }

        // construction line: H / V / A / B switches the method (like XLINE in AutoCAD)
        if currentTool == .xline, !shifted, characters.count == 1, switchXLineKind(letter: characters.lowercased()) {
            return
        }

        let typedKey = (shifted ? "⇧" : "") + characters.uppercased()
        if characters.count == 1, let command = Shortcuts.command(forKey: typedKey) {
            // the Line key again while in the Line tool = continuous lines (LNC) on / off
            if command == .tool(.line), currentTool == .line, !dynamicInput.hasLockedValue {
                lineContinue.toggle()
                onMessage?(lineContinue ? "Continuous lines (LNC) ON" : "Continuous lines (LNC) OFF")
                return
            }
            switch command {
            case .tool(let tool): onToolChangeRequested?(tool)
            case .hatch(let name): onHatchShortcut?(name)
            }
            return
        }

        super.keyDown(with: event)
    }

    // MARK: Text dialog

    private func askForText(title: String, message: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}

// MARK: - Text on the canvas (Esc = cancel)

extension CADEditorView {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard control === inlineText?.field else { return false }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelInlineText()
            return true
        }
        // ⌥↩ (and ⌃↩) = new line, ↩ = insert
        if commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) {
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        }
        return false
    }

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === inlineText?.field else { return }
        positionInlineText()
    }
}

// MARK: - CAD crosshair (cursor across the area)

/// Crosshair with a pick box – drawn in its own layer, so mouse movement doesn't redraw the drawing.
final class CrosshairView: NSView {
    private let lines = CAShapeLayer()
    private let box = CAShapeLayer()
    /// Rotation of the crosshair on screen (by the axes of the drawing coordinates).
    var angle: CGFloat = 0 {
        didSet { updatePaths() }
    }

    var point: CGPoint? {
        didSet { updatePaths() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(lines)
        layer?.addSublayer(box)
        for shape in [lines, box] {
            shape.fillColor = nil
            shape.actions = ["path": NSNull(), "strokeColor": NSNull(), "lineWidth": NSNull(), "position": NSNull(), "bounds": NSNull()]
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { return nil }

    func updateAppearance() {
        let color = AppSettings.crosshairColor.cgColor
        lines.strokeColor = color
        box.strokeColor = color
        lines.lineWidth = AppSettings.crosshairWidth
        box.lineWidth = AppSettings.crosshairWidth
        updatePaths()
    }

    override func layout() {
        super.layout()
        lines.frame = bounds
        box.frame = bounds
        updatePaths()
    }

    private func updatePaths() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard let p = point, p.x.isFinite, p.y.isFinite, bounds.contains(p) else {
            lines.path = nil
            box.path = nil
            return
        }
        // snapped to whole pixels so the lines are sharp
        let scale = window?.backingScaleFactor ?? 2
        let width = AppSettings.crosshairWidth
        let snap = { (v: CGFloat) -> CGFloat in
            let odd = Int((width * scale).rounded()) % 2 == 1
            return odd ? (floor(v * scale) + 0.5) / scale : (v * scale).rounded() / scale
        }
        let x = snap(p.x), y = snap(p.y)
        let size = AppSettings.crosshairSize
        let half = size >= 99.5 ? max(bounds.width, bounds.height) * 2 : max(bounds.width, bounds.height) * size / 200
        let pick = AppSettings.showPickbox ? AppSettings.pickboxSize : 0
        let gap = pick > 0 ? pick / 2 : 0
        let path = CGMutablePath()
        // rotated crosshair: arms along the axes of the drawing coordinates
        var turn = CGAffineTransform(translationX: x, y: y).rotated(by: angle.isFinite ? angle : 0).translatedBy(x: -x, y: -y)
        path.move(to: CGPoint(x: x - half, y: y), transform: turn); path.addLine(to: CGPoint(x: x - gap, y: y), transform: turn)
        path.move(to: CGPoint(x: x + gap, y: y), transform: turn); path.addLine(to: CGPoint(x: x + half, y: y), transform: turn)
        path.move(to: CGPoint(x: x, y: y - half), transform: turn); path.addLine(to: CGPoint(x: x, y: y - gap), transform: turn)
        path.move(to: CGPoint(x: x, y: y + gap), transform: turn); path.addLine(to: CGPoint(x: x, y: y + half), transform: turn)
        lines.path = path
        box.path = pick > 0 ? CGPath(rect: CGRect(x: x - pick / 2, y: y - pick / 2, width: pick, height: pick), transform: &turn) : nil
    }
}

// MARK: - Snap point markers

/// Marker for a snap point kind (on the canvas as well as in menus and settings).
enum SnapMarker {
    static func draw(_ type: SnapType, at p: CGPoint, size s: CGFloat, color: NSColor, in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [])
        func lines(_ points: [CGPoint]) {
            context.addLines(between: points)
            context.strokePath()
        }
        switch type {
        case .endpoint:
            context.stroke(CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
        case .midpoint:
            lines([CGPoint(x: p.x, y: p.y + s), CGPoint(x: p.x - s, y: p.y - s),
                   CGPoint(x: p.x + s, y: p.y - s), CGPoint(x: p.x, y: p.y + s)])
        case .center:
            context.strokeEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
        case .geometricCenter:
            context.strokeEllipse(in: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s))
            lines([CGPoint(x: p.x - s, y: p.y), CGPoint(x: p.x + s, y: p.y)])
            lines([CGPoint(x: p.x, y: p.y - s), CGPoint(x: p.x, y: p.y + s)])
        case .quadrant:
            lines([CGPoint(x: p.x, y: p.y + s), CGPoint(x: p.x + s, y: p.y), CGPoint(x: p.x, y: p.y - s),
                   CGPoint(x: p.x - s, y: p.y), CGPoint(x: p.x, y: p.y + s)])
        case .intersection:
            lines([CGPoint(x: p.x - s, y: p.y - s), CGPoint(x: p.x + s, y: p.y + s)])
            lines([CGPoint(x: p.x - s, y: p.y + s), CGPoint(x: p.x + s, y: p.y - s)])
        case .extensionLine:
            // dots and a cross: “continues further”
            lines([CGPoint(x: p.x - s * 0.7, y: p.y), CGPoint(x: p.x + s * 0.7, y: p.y)])
            lines([CGPoint(x: p.x, y: p.y - s * 0.7), CGPoint(x: p.x, y: p.y + s * 0.7)])
            for dx in [-s * 1.4, s * 1.4] {
                context.fillEllipse(in: CGRect(x: p.x + dx - 1.2, y: p.y - 1.2, width: 2.4, height: 2.4))
            }
        case .perpendicular:
            lines([CGPoint(x: p.x - s, y: p.y + s), CGPoint(x: p.x - s, y: p.y - s), CGPoint(x: p.x + s, y: p.y - s)])
            lines([CGPoint(x: p.x - s, y: p.y), CGPoint(x: p.x, y: p.y), CGPoint(x: p.x, y: p.y - s)])
        case .tangent:
            context.strokeEllipse(in: CGRect(x: p.x - s * 0.8, y: p.y - s * 0.8 - s * 0.2, width: 1.6 * s, height: 1.6 * s))
            lines([CGPoint(x: p.x - s, y: p.y + s * 0.6), CGPoint(x: p.x + s, y: p.y + s * 0.6)])
        case .nearest:
            lines([CGPoint(x: p.x - s, y: p.y + s), CGPoint(x: p.x + s, y: p.y + s), CGPoint(x: p.x - s, y: p.y - s),
                   CGPoint(x: p.x + s, y: p.y - s), CGPoint(x: p.x - s, y: p.y + s)])
        case .node:
            context.strokeEllipse(in: CGRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s))
            lines([CGPoint(x: p.x - s, y: p.y - s), CGPoint(x: p.x + s, y: p.y + s)])
            lines([CGPoint(x: p.x - s, y: p.y + s), CGPoint(x: p.x + s, y: p.y - s)])
        case .insertion:
            context.stroke(CGRect(x: p.x - s, y: p.y - s * 0.2, width: s * 1.2, height: s * 1.2))
            context.stroke(CGRect(x: p.x - s * 0.2, y: p.y - s, width: s * 1.2, height: s * 1.2))
        }
        context.restoreGState()
    }

    /// A small image of the marker (template – the system gives the color).
    static func image(_ type: SnapType, size: CGFloat = 16) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(type, at: CGPoint(x: rect.midX, y: rect.midY), size: size * 0.32, color: .black, in: context)
            return true
        }
        image.isTemplate = true
        return image
    }
}

// MARK: - Array dialog

/// Fields with the array values: columns and rows with spacing, or count and angle for a polar array.
final class ArrayForm: NSObject, NSTextFieldDelegate {
    var onChange: (() -> Void)?
    private(set) var settings: ArraySettings
    let view: NSView
    private(set) var firstField: NSTextField?
    private var fields: [String: NSTextField] = [:]
    private let rotateBox = NSButton(checkboxWithTitle: "Rotate the copies", target: nil, action: nil)
    private let kind: ArrayKind

    init(kind: ArrayKind, settings: ArraySettings, columnSpacing: CGFloat, rowSpacing: CGFloat, unit: String) {
        self.kind = kind
        var initial = settings
        initial.columnSpacing = settings.columnSpacing ?? columnSpacing
        initial.rowSpacing = settings.rowSpacing ?? rowSpacing
        self.settings = initial
        let grid = NSGridView()
        grid.rowSpacing = 6
        grid.columnSpacing = 8
        view = grid
        super.init()

        func row(_ key: String, _ title: String, _ value: CGFloat, suffix: String = "") {
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            let field = NSTextField(string: LineType.format(value))
            field.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            field.widthAnchor.constraint(equalToConstant: 90).isActive = true
            field.delegate = self
            fields[key] = field
            if firstField == nil { firstField = field }
            grid.addRow(with: [label, field, NSTextField(labelWithString: suffix)])
        }
        switch kind {
        case .rectangular:
            row("columns", "Columns:", CGFloat(initial.columns))
            row("rows", "Rows:", CGFloat(initial.rows))
            row("dx", "Column spacing:", initial.columnSpacing ?? columnSpacing, suffix: unit)
            row("dy", "Row spacing:", initial.rowSpacing ?? rowSpacing, suffix: unit)
        case .polar:
            row("count", "Items (incl. original):", CGFloat(initial.count))
            row("fill", "Fill angle:", initial.fillAngle, suffix: "°")
            rotateBox.state = initial.rotateItems ? .on : .off
            rotateBox.target = self
            rotateBox.action = #selector(rotateToggled)
            grid.addRow(with: [NSGridCell.emptyContentView, rotateBox, NSGridCell.emptyContentView])
        }
        grid.column(at: 0).xPlacement = .trailing
        grid.frame.size = grid.fittingSize
    }

    @objc private func rotateToggled() {
        settings.rotateItems = rotateBox.state == .on
        onChange?()
    }

    func controlTextDidChange(_ notification: Notification) {
        read()
        onChange?()
    }

    private func value(_ key: String) -> CGFloat? {
        guard let text = fields[key]?.stringValue, let number = ExpressionEvaluator.evaluate(text) else { return nil }
        return CGFloat(number)
    }

    /// A count: an expression is allowed, but the result must be a whole number (otherwise it is ignored like an invalid value).
    private func integer(_ key: String) -> Int? {
        guard let v = value(key), abs(v - v.rounded()) < 1e-9 else { return nil }
        return Int(exactly: v.rounded())
    }

    /// Reads the valid values (invalid ones are ignored, the last valid one stays).
    private func read() {
        switch kind {
        case .rectangular:
            if let v = integer("columns"), v >= 1, v <= 10_000 { settings.columns = v }
            if let v = integer("rows"), v >= 1, v <= 10_000 { settings.rows = v }
            if let v = value("dx") { settings.columnSpacing = v }
            if let v = value("dy") { settings.rowSpacing = v }
        case .polar:
            if let v = integer("count"), v >= 2, v <= 10_000 { settings.count = v }
            if let v = value("fill"), v != 0, abs(v) <= 360 { settings.fillAngle = v }
        }
    }
}
