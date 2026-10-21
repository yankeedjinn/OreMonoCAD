# OhMyCAD

A small 2D CAD editor for macOS – a fancy drawing board somewhere between a classic CAD program and SketchUp. Written in Swift on plain AppKit (no SwiftUI, no storyboards).

It is a personal project: built for one architect's everyday drawing, kept deliberately simple.

Current version: 1.11 (build 12).

## Features

- Lines, polylines, rectangles, arcs, circles, ellipses, polygons, splines, construction lines
- Move, Copy, Rotate, Scale, Mirror, Array, Edit Points, Match Properties
- Trim, PowerTrim, Extend, Break, Fillet, Chamfer, Offset, Join, Explode
- Dimensions (linear, aligned, continue, angular, radius, diameter), text, leaders
- Hatches with a pick-inside-area fill, Rebuild Hatch and Cut Out of Hatch
- Walls and Wall from Curve, room labels with floor area, revision clouds, wipeouts, scale bar and north arrow
- Image and PDF underlays, external references, groups, Filter, Select Similar
- Copy and paste between drawings, Draw Order
- Plot / print, PDF and image export, plot style tables (.ctb)
- Layers, blocks with in-place editing, layouts with viewports, named views
- DXF import and export, native `.ohmycad` format
- Survey support: geodetic base point (S-JTSK), point list import, rotated view / UCS
- Snaps, Snap Tracking, ortho, polar angles, grid, the value box next to the cursor, Find and Replace
- A customizable tool panel: Favorites, groups that can be moved or hidden, floating palettes
- Auto-save, crash recovery and backups of previous versions
- Help for every tool: a short summary at once on hover, usage instructions after a moment (tools inside a button's menu show their summary in the menu)

## Requirements

- macOS 26.1 or later
- Xcode 26 or later

## Building

1. Open `OhMyCAD.xcodeproj` in Xcode.
2. Under *Signing & Capabilities*, choose your own team (or *Sign to Run Locally*).
3. Press ⌘R.

Every build runs `Scripts/check_tool_help.sh`, which prints a warning for any tool that has no hover help.

## Fonts

OhMyCAD bundles [osifont](https://github.com/hikikomori82/osifont), an ISO 3098 technical lettering font, licensed under the GNU GPL v3 with the font exception. See `OhMyCAD/Fonts/osifont-LICENSE.md`.

## License

The source code is released under the MIT License – see [LICENSE](LICENSE). The bundled osifont keeps its own license.

© 2025–2026 Yankee Djinn
