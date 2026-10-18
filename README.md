# OhMyCAD

A small 2D CAD editor for macOS – a fancy drawing board somewhere between a classic CAD program and SketchUp. Written in Swift on plain AppKit (no SwiftUI, no storyboards).

It is a personal project: built for one architect's everyday drawing, kept deliberately simple.

## Features

- Lines, polylines, arcs, circles, ellipses, polygons, splines, construction lines
- Trim, Extend, Break, Fillet, Chamfer, Offset, Mirror, Array, Join, Explode
- Dimensions (linear, aligned, chain, angular, radius, diameter), text, leaders
- Hatches with a pick-inside-area fill
- Layers, blocks with in-place editing, layouts with viewports, named views
- DXF import and export, native `.ohmycad` format
- Survey support: geodetic base point (S-JTSK), point list import, rotated view / UCS
- Snaps, ortho, dynamic input next to the cursor, Find and Replace
- Autosave, crash recovery and backups of previous versions
- Hover help for every tool: a short summary at once, usage instructions after a moment

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
