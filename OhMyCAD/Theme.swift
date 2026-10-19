//
//  Theme.swift
//  OhMyCAD
//
//  One place for the interface colors (drawing area, tabs, panels, status line, popups, splash).
//  The values match the colors previously written directly in the code – the look has not changed.
//  Shades of gray are written as “white” (0 = black, 1 = white).
//

import Cocoa

enum Theme {
    private static func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(white: white, alpha: alpha)
    }

    // MARK: Accent

    /// Accent color from the macOS settings (selected tool, current layer, usage heading).
    static var accent: NSColor { .controlAccentColor }

    // MARK: Backgrounds

    static let windowBackground = NSColor.darkGray  // main window behind the panels
    static let listBackground = gray(0.12)          // layer list
    static let panelBackground = gray(0.15)         // layer, properties and Info panels, docked panel
    static let toolbarBackground = gray(0.17)       // tool panel
    static let stripBackground = gray(0.19)         // vertical strip of a collapsed panel
    static let statusBarBackground = gray(0.20)     // status line
    static let panelHeaderBackground = gray(0.22)   // panel header
    static let fieldBackground = gray(0.22)         // layer rename
    static let stripHoverBackground = gray(0.25)    // strip under the mouse
    static let toastBackground = gray(0.17, 0.94)
    static let tipBackground = gray(0.10, 0.97)     // tool hover help

    /// Tool button: pressed / under the mouse (white over a dark background).
    static let buttonPressed = gray(1, 0.22)
    static let buttonHover = gray(1, 0.10)

    // MARK: Lines and borders

    static let statusDivider = gray(0.30)           // separator of the prompt row in the status line
    static let panelBorder = gray(0.32)             // border of the docked panel and the strip
    static let dragHandle = gray(0.35)              // handle for dragging a panel
    static let statusSeparator = gray(0.38)         // vertical bars between status line items
    static let popupBorder = gray(0.40)             // border of toasts and help popups

    // MARK: Text and icons (lightest first)

    static let textValue = gray(0.92)               // values in the Info panel
    static let textToast = gray(0.90)
    static let textSoft = gray(0.88)                // tool icon, summary in the help popup
    static let iconLight = gray(0.85)               // line type preview, icons in the strip
    static let iconOn = gray(0.82)                  // layer icon when on, name in the strip
    static let textBright = gray(0.95)             // selected tab name, strip name under the mouse
    static let textSecondary = gray(0.80)           // panel icons, coordinates, info text
    static let textLabel = gray(0.75)               // property row labels, usage in the help popup
    static let menuTriangle = gray(0.70)            // triangle of a combined button
    static let textLayoutTab = gray(0.72)           // unselected layout tab name
    static let textHint = gray(0.70)                // message in the plot preview
    static let textMuted = gray(0.65)               // unselected tab name, dynamic input labels
    static let textNote = gray(0.60)
    static let textInfoCaption = gray(0.58)         // labels in the Info panel
    static let textHeading = gray(0.62)             // toolbar group and Properties section headings
    static let textCaption = gray(0.55)             // summaries
    static let textDimmed = gray(0.56)              // hidden layer, non-plotting layer
    static let stripSeparator = gray(0.45)
    static let iconOff = gray(0.48)                 // layer icon when off

    // MARK: Drawing area

    static let paperSurround = gray(0.045)          // around the paper in a layout
    static let canvasBackground = gray(0.10)        // drawing area; the selected tab blends with it
    static let paperBorder = gray(0.30)
    static let ucsOrigin = gray(0.70)               // small square at the UCS origin
    static let grip = NSColor(calibratedRed: 0.2, green: 0.45, blue: 1, alpha: 1)
    static let canvasLabelBackground = NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.3, alpha: 0.92)
    static let inlineTextBackground = gray(0.16, 0.95)  // text typed directly on the drawing
    static let inlineTextButton = gray(0.22, 0.95)      // format button next to it
    static let blockEditBar = NSColor(srgbRed: 0.24, green: 0.16, blue: 0.34, alpha: 0.96)

    // MARK: Tabs and layout bar

    static let tabBarBackground = gray(0.165)
    static let tabHover = gray(0.21)
    static let tabPlusHover = gray(0.22)
    static let tabSeparator = gray(0.28)
    static let tabCloseHover = gray(0.32)
    static let tabClosePressed = gray(0.40)
    static let layoutBarBackground = gray(0.14)
    static let layoutTab = gray(0.19)
    static let layoutBarBorder = gray(0.25)
    static let trayBackground = gray(0.13)          // right column behind Properties and Layers

    // MARK: Dynamic input

    static let inputBackground = gray(0.08, 0.92)
    static let confirmBackground = gray(0.08, 0.95)
    static let inputField = gray(0.18)
    static let inputFieldLocked = NSColor(calibratedRed: 0.35, green: 0.30, blue: 0.05, alpha: 1)
    static let inputHint = NSColor(calibratedRed: 0.95, green: 0.82, blue: 0.45, alpha: 1)

    // MARK: Previews

    static let swatchBackground = gray(0.12)        // hatch pattern and line type previews
    static let swatchStroke = gray(0.45)
    static let previewBackground = gray(0.17)       // plot preview
    static let previewChecker = gray(0.90)

    // MARK: Splash screen

    static let splashBackground = NSColor(srgbRed: 0.114, green: 0.114, blue: 0.137, alpha: 1)
    static let splashBorder = gray(1, 0.08)
    static let splashTitle = gray(1)                // app name
    static let splashVersion = gray(1, 0.5)
    static let splashText = gray(1, 0.68)
}
