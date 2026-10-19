//
//  Export.swift
//  OhMyCAD
//
//  Paper and raster image formats for printing and export (the Plot dialog is in Plot.swift).
//

import Cocoa
import UniformTypeIdentifiers

// MARK: - Paper formats

enum PaperSize: String, CaseIterable {
    case extents, a4, a3, a2, a1, a0, letter, legal, tabloid

    var title: String {
        switch self {
        case .extents: return "Size of the plotted area (no paper format)"
        case .a4: return "A4  (210 × 297 mm)"
        case .a3: return "A3  (297 × 420 mm)"
        case .a2: return "A2  (420 × 594 mm)"
        case .a1: return "A1  (594 × 841 mm)"
        case .a0: return "A0  (841 × 1189 mm)"
        case .letter: return "Letter  (8.5 × 11 in)"
        case .legal: return "Legal  (8.5 × 14 in)"
        case .tabloid: return "Tabloid  (11 × 17 in)"
        }
    }

    /// Short name (A3, Letter…).
    var shortTitle: String {
        switch self {
        case .extents: return "Drawing size"
        case .a4: return "A4"
        case .a3: return "A3"
        case .a2: return "A2"
        case .a1: return "A1"
        case .a0: return "A0"
        case .letter: return "Letter"
        case .legal: return "Legal"
        case .tabloid: return "Tabloid"
        }
    }

    /// Portrait size in mm (nil = from the drawing).
    var portraitMM: CGSize? {
        switch self {
        case .extents: return nil
        case .a4: return CGSize(width: 210, height: 297)
        case .a3: return CGSize(width: 297, height: 420)
        case .a2: return CGSize(width: 420, height: 594)
        case .a1: return CGSize(width: 594, height: 841)
        case .a0: return CGSize(width: 841, height: 1189)
        case .letter: return CGSize(width: 215.9, height: 279.4)
        case .legal: return CGSize(width: 215.9, height: 355.6)
        case .tabloid: return CGSize(width: 279.4, height: 431.8)
        }
    }
}

enum RasterFormat: Int, CaseIterable {
    case png, jpeg, tiff

    var title: String {
        switch self {
        case .png: return "PNG"
        case .jpeg: return "JPEG"
        case .tiff: return "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        case .tiff: return "tif"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .tiff: return .tiff
        }
    }

    var supportsTransparency: Bool { return self != .jpeg }
}
