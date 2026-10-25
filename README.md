# OreMonoCAD

A small 2D CAD editor for macOS – a fancy drawing board: more than a sketchpad, far less than a full CAD suite. Written in Swift on plain AppKit (no SwiftUI, no storyboards).

It is a personal project: built for one architect's everyday drawing, kept deliberately simple.

## Features

- Lines, polylines (with a constant width), rectangles, arcs, circles, ellipses, polygons, splines, construction lines
- Move, Copy, Rotate, Scale, Mirror, Align, Array, Edit Points, Match Properties
- Trim, MagicTrim (drag across parts to remove them, click to extend), Extend, Break, Fillet, Chamfer, Offset, Join, Explode
- Dimensions (linear, aligned, continue, angular, radius, diameter), text, leaders
- Hatches with a pick-inside-area fill, Rebuild Hatch and Cut Out of Hatch
- Walls and Wall from Curve (a new wall joins the walls it touches or crosses), room labels with floor area, revision clouds, wipeouts, scale bar and north arrow
- Image and PDF underlays, external references, groups, Filter, Select Similar
- Copy and paste between drawings, Draw Order (kept in DXF export)
- Plot / print, PDF and image export, plot style tables (.ctb)
- Layers, blocks with in-place editing, layouts with viewports, named views
- DXF import and export, native `.oremono` format (drawings saved by older versions as `.ohmycad` still open)
- Drawing units: mm, cm, m, inches and feet (lengths shown and typed as 12'-6 1/2"), with conversion of an existing drawing; text, dimension and lineweight sizes in paper millimeters
- Survey support: geodetic base point (S-JTSK), point list import, rotated view / UCS, angles in degrees or gons, directions as bearings
- Snaps, Snap Tracking, ortho, polar angles, grid, the value box next to the cursor, Find and Replace
- Shift modifiers (square rectangles, 15° steps for Rotate and Arc), a context menu on a held right mouse button, selection window by dragging or by two clicks
- A customizable tool panel: Favorites, groups that can be moved or hidden, floating palettes
- Auto-save, crash recovery and backups of previous versions
- Help for every tool: a short summary at once on hover, usage instructions after a moment (tools inside a button's menu show their summary in the menu and a HOW TO USE tip after a moment)

## DWG files

DWG is not supported. Convert DWG drawings to DXF first, for example with the free [ODA File Converter](https://www.opendesign.com/guestfiles/oda_file_converter).

## Requirements

- macOS 26.1 or later
- Xcode 26 or later

## Building

1. Open `OreMonoCAD.xcodeproj` in Xcode.
2. Under *Signing & Capabilities*, choose your own team (or *Sign to Run Locally*).
3. Press ⌘R.

Every build runs `Scripts/check_tool_help.sh`, which prints a warning for any tool that has no hover help.

## Fonts

OreMonoCAD bundles [osifont](https://github.com/hikikomori82/osifont), an ISO 3098 technical lettering font, licensed under the GNU GPL v3 with the font exception. See `OreMonoCAD/Fonts/osifont-LICENSE.md`.

## License

The source code is released under the MIT License – see [LICENSE](LICENSE). The bundled osifont keeps its own license.

Other product names mentioned in file formats or documentation belong to their respective owners; this project is not affiliated with any CAD vendor.

© 2025–2026 Yankee Djinn
