#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-icon.swift output.iconset\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

let icons: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for icon in icons {
    let image = renderIcon(pixels: icon.pixels)
    let url = outputURL.appendingPathComponent(icon.name)
    try writePNG(image, to: url)
}

func renderIcon(pixels: Int) -> NSImage {
    let size = CGFloat(pixels)
    let scale = size / 1024.0
    let image = NSImage(size: NSSize(width: size, height: size))

    image.lockFocus()
    defer { image.unlockFocus() }

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: size, height: size).fill()

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
        NSRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }

    func path(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect(x, y, width, height), xRadius: radius * scale, yRadius: radius * scale)
    }

    let base = path(80, 80, 864, 864, radius: 190)
    NSGradient(
        starting: NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.12, alpha: 1),
        ending: NSColor(calibratedRed: 0.02, green: 0.32, blue: 0.30, alpha: 1)
    )?.draw(in: base, angle: -38)

    NSColor(calibratedWhite: 1, alpha: 0.12).setStroke()
    base.lineWidth = max(1, 18 * scale)
    base.stroke()

    let panel = path(196, 236, 632, 552, radius: 74)
    NSColor(calibratedWhite: 0.04, alpha: 0.74).setFill()
    panel.fill()
    NSColor(calibratedWhite: 1, alpha: 0.18).setStroke()
    panel.lineWidth = max(1, 8 * scale)
    panel.stroke()

    drawPrompt(scale: scale)
    drawRows(scale: scale)
    drawLens(scale: scale)

    return image
}

func drawPrompt(scale: CGFloat) {
    let chevron = NSBezierPath()
    chevron.move(to: NSPoint(x: 286 * scale, y: 612 * scale))
    chevron.line(to: NSPoint(x: 354 * scale, y: 544 * scale))
    chevron.line(to: NSPoint(x: 286 * scale, y: 476 * scale))
    NSColor(calibratedRed: 0.45, green: 0.96, blue: 0.83, alpha: 1).setStroke()
    chevron.lineWidth = max(2, 34 * scale)
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.stroke()

    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 396 * scale, y: 474 * scale))
    cursor.line(to: NSPoint(x: 522 * scale, y: 474 * scale))
    NSColor(calibratedWhite: 0.94, alpha: 0.95).setStroke()
    cursor.lineWidth = max(2, 28 * scale)
    cursor.lineCapStyle = .round
    cursor.stroke()
}

func drawRows(scale: CGFloat) {
    let rows: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (590, 218, 430, NSColor(calibratedRed: 0.29, green: 0.78, blue: 0.96, alpha: 1)),
        (510, 268, 330, NSColor(calibratedRed: 0.97, green: 0.80, blue: 0.33, alpha: 1)),
        (430, 218, 450, NSColor(calibratedRed: 0.83, green: 0.55, blue: 0.97, alpha: 1))
    ]

    for (y, x, width, color) in rows {
        let background = NSBezierPath(
            roundedRect: NSRect(x: x * scale, y: y * scale, width: width * scale, height: 42 * scale),
            xRadius: 21 * scale,
            yRadius: 21 * scale
        )
        NSColor(calibratedWhite: 1, alpha: 0.10).setFill()
        background.fill()

        let accent = NSBezierPath(
            roundedRect: NSRect(x: x * scale, y: y * scale, width: 82 * scale, height: 42 * scale),
            xRadius: 21 * scale,
            yRadius: 21 * scale
        )
        color.setFill()
        accent.fill()
    }
}

func drawLens(scale: CGFloat) {
    let circle = NSBezierPath(ovalIn: NSRect(x: 600 * scale, y: 584 * scale, width: 142 * scale, height: 142 * scale))
    NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
    circle.lineWidth = max(2, 28 * scale)
    circle.stroke()

    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 708 * scale, y: 600 * scale))
    handle.line(to: NSPoint(x: 798 * scale, y: 510 * scale))
    NSColor(calibratedWhite: 1, alpha: 0.92).setStroke()
    handle.lineWidth = max(2, 32 * scale)
    handle.lineCapStyle = .round
    handle.stroke()
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        throw IconError.pngEncodingFailed
    }
    try png.write(to: url)
}

enum IconError: Error {
    case pngEncodingFailed
}
