#!/usr/bin/env swift
// Generates the N1KO-STATE app icon as an .iconset → .icns
// Usage: swift scripts/gen_icon.swift

import AppKit

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16",       16),
    ("icon_16x16@2x",    32),
    ("icon_32x32",       32),
    ("icon_32x32@2x",    64),
    ("icon_128x128",    128),
    ("icon_128x128@2x", 256),
    ("icon_256x256",    256),
    ("icon_256x256@2x", 512),
    ("icon_512x512",    512),
    ("icon_512x512@2x",1024),
]

func drawIcon(size px: Int) -> NSImage {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let r = CGFloat(s * 0.22)

    // Background: dark gradient
    let bg = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: s, height: s), xRadius: r, yRadius: r)
    let dark1 = NSColor(srgbRed: 0.086, green: 0.086, blue: 0.102, alpha: 1)
    let dark2 = NSColor(srgbRed: 0.12, green: 0.12, blue: 0.16, alpha: 1)
    let gradient = NSGradient(starting: dark2, ending: dark1)!
    gradient.draw(in: bg, angle: -90)

    // Subtle border
    let borderColor = NSColor.white.withAlphaComponent(0.08)
    borderColor.setStroke()
    bg.lineWidth = s * 0.01
    bg.stroke()

    // Ring gauge (CPU-like)
    let center = CGPoint(x: s * 0.5, y: s * 0.52)
    let ringR = s * 0.28
    let lineW = s * 0.055

    // Track
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    ctx.setLineWidth(lineW)
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: ringR, startAngle: .pi * 0.8, endAngle: .pi * 0.2, clockwise: true)
    ctx.strokePath()

    // Filled arc (gradient-like: blue → purple)
    let arcStart = CGFloat.pi * 0.8
    let arcEnd = CGFloat.pi * 0.8 - CGFloat.pi * 1.2 // ~75% fill
    let blue = NSColor(srgbRed: 0.04, green: 0.52, blue: 1, alpha: 1)  // Theme.info
    ctx.setStrokeColor(blue.cgColor)
    ctx.setLineWidth(lineW)
    ctx.setLineCap(.round)
    ctx.addArc(center: center, radius: ringR, startAngle: arcStart, endAngle: arcEnd, clockwise: true)
    ctx.strokePath()

    // Purple accent dot at end of arc
    let purple = NSColor(srgbRed: 0.75, green: 0.35, blue: 0.95, alpha: 1) // Theme.memory
    let dotR = lineW * 0.5
    let dotX = center.x + ringR * cos(arcEnd)
    let dotY = center.y + ringR * sin(arcEnd)
    ctx.setFillColor(purple.cgColor)
    ctx.fillEllipse(in: CGRect(x: dotX - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))

    // Center text: "N1"
    let fontSize = s * 0.18
    let font = NSFont.systemFont(ofSize: fontSize, weight: .heavy)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white.withAlphaComponent(0.92),
    ]
    let text = "N1" as NSString
    let textSize = text.size(withAttributes: attrs)
    text.draw(at: NSPoint(x: center.x - textSize.width / 2,
                          y: center.y - textSize.height / 2 - s * 0.02),
              withAttributes: attrs)

    // Bottom mini bars (like a small chart)
    let barW = s * 0.035
    let barGap = s * 0.02
    let barCount = 5
    let totalBarW = CGFloat(barCount) * barW + CGFloat(barCount - 1) * barGap
    var bx = s * 0.5 - totalBarW / 2
    let barBase = s * 0.14
    let barHeights: [CGFloat] = [0.4, 0.7, 0.55, 0.85, 0.3]
    let barColors = [blue, blue, purple, blue, blue]

    for i in 0..<barCount {
        let h = s * 0.09 * barHeights[i]
        let barRect = CGRect(x: bx, y: barBase, width: barW, height: h)
        ctx.setFillColor(barColors[i].withAlphaComponent(0.8).cgColor)
        let path = CGPath(roundedRect: barRect, cornerWidth: barW * 0.35, cornerHeight: barW * 0.35, transform: nil)
        ctx.addPath(path)
        ctx.fillPath()
        bx += barW + barGap
    }

    img.unlockFocus()
    return img
}

// Create iconset directory
let fm = FileManager.default
let iconsetPath = "Resources/AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for entry in sizes {
    let img = drawIcon(size: entry.px)
    guard let tiff = img.tiffRepresentation,
          let bmp = NSBitmapImageRep(data: tiff),
          let png = bmp.representation(using: .png, properties: [:]) else {
        print("Failed to render \(entry.name)")
        continue
    }
    let path = "\(iconsetPath)/\(entry.name).png"
    try! png.write(to: URL(fileURLWithPath: path))
    print("  \(entry.name).png (\(entry.px)px)")
}

print("Converting to .icns...")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetPath, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()

if task.terminationStatus == 0 {
    try? fm.removeItem(atPath: iconsetPath)
    print("✅ Resources/AppIcon.icns created")
} else {
    print("❌ iconutil failed")
}
