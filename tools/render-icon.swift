#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("Usage: render-icon.swift OUTPUT.png\n".utf8)
    )
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let pixelSize = 1024

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    fatalError("Could not create icon bitmap")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.clear.setFill()
NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize).fill()

func sparklePath(center: NSPoint, outerRadius: CGFloat, innerRadius: CGFloat) -> NSBezierPath {
    let points = [
        NSPoint(x: center.x, y: center.y + outerRadius),
        NSPoint(x: center.x + innerRadius, y: center.y + innerRadius),
        NSPoint(x: center.x + outerRadius, y: center.y),
        NSPoint(x: center.x + innerRadius, y: center.y - innerRadius),
        NSPoint(x: center.x, y: center.y - outerRadius),
        NSPoint(x: center.x - innerRadius, y: center.y - innerRadius),
        NSPoint(x: center.x - outerRadius, y: center.y),
        NSPoint(x: center.x - innerRadius, y: center.y + innerRadius),
    ]

    let path = NSBezierPath()
    path.move(to: points[0])
    for point in points.dropFirst() {
        path.line(to: point)
    }
    path.close()
    return path
}

NSColor.white.setFill()
sparklePath(
    center: NSPoint(x: 480, y: 505),
    outerRadius: 270,
    innerRadius: 88
).fill()

NSColor.white.withAlphaComponent(0.92).setFill()
sparklePath(
    center: NSPoint(x: 735, y: 760),
    outerRadius: 115,
    innerRadius: 38
).fill()

NSColor.white.withAlphaComponent(0.78).setFill()
sparklePath(
    center: NSPoint(x: 735, y: 285),
    outerRadius: 80,
    innerRadius: 27
).fill()

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}

try png.write(to: outputURL, options: .atomic)
