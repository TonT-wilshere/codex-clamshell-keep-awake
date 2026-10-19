import Cocoa

guard CommandLine.arguments.count == 2 else {
    fputs("usage: IconRenderer <output.png>\n", stderr)
    exit(2)
}

let canvas = NSSize(width: 1024, height: 1024)
let image = NSImage(size: canvas)
image.lockFocus()

guard let context = NSGraphicsContext.current else {
    fputs("unable to create graphics context\n", stderr)
    exit(1)
}

NSColor.clear.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: canvas)).fill()

let background = NSBezierPath(
    roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896),
    xRadius: 210,
    yRadius: 210
)

NSGraphicsContext.saveGraphicsState()
background.addClip()
NSGradient(
    colors: [
        NSColor(calibratedRed: 0.082, green: 0.129, blue: 0.290, alpha: 1),
        NSColor(calibratedRed: 0.086, green: 0.365, blue: 0.859, alpha: 1),
        NSColor(calibratedRed: 0.035, green: 0.208, blue: 0.525, alpha: 1)
    ],
    atLocations: [0, 0.55, 1],
    colorSpace: .deviceRGB
)?.draw(in: background, angle: -48)

NSColor(calibratedRed: 0.416, green: 0.659, blue: 1, alpha: 0.10).setFill()
NSBezierPath(ovalIn: NSRect(x: 510, y: 519, width: 500, height: 500)).fill()
NSColor(calibratedRed: 0, green: 0.122, blue: 0.380, alpha: 0.20).setFill()
NSBezierPath(ovalIn: NSRect(x: -50, y: -76, width: 540, height: 540)).fill()
NSGraphicsContext.restoreGraphicsState()

context.cgContext.saveGState()
context.cgContext.setShadow(
    offset: CGSize(width: 0, height: -22),
    blur: 28,
    color: NSColor(calibratedRed: 0, green: 0.078, blue: 0.247, alpha: 0.38).cgColor
)

let screen = NSBezierPath(
    roundedRect: NSRect(x: 228, y: 348, width: 568, height: 438),
    xRadius: 58,
    yRadius: 58
)
NSGradient(
    colors: [
        NSColor.white.withAlphaComponent(0.20),
        NSColor(calibratedRed: 0.376, green: 0.647, blue: 0.980, alpha: 0.06)
    ]
)?.draw(in: screen, angle: -45)
NSColor(calibratedRed: 0.969, green: 0.980, blue: 1, alpha: 1).setStroke()
screen.lineWidth = 34
screen.stroke()

let base = NSBezierPath()
base.move(to: NSPoint(x: 166, y: 316))
base.line(to: NSPoint(x: 858, y: 316))
base.line(to: NSPoint(x: 823, y: 258))
base.curve(
    to: NSPoint(x: 766, y: 226),
    controlPoint1: NSPoint(x: 811, y: 238),
    controlPoint2: NSPoint(x: 789, y: 226)
)
base.line(to: NSPoint(x: 258, y: 226))
base.curve(
    to: NSPoint(x: 201, y: 258),
    controlPoint1: NSPoint(x: 235, y: 226),
    controlPoint2: NSPoint(x: 213, y: 238)
)
base.close()
NSColor(calibratedRed: 0.969, green: 0.980, blue: 1, alpha: 1).setFill()
base.fill()
context.cgContext.restoreGState()

NSColor(calibratedRed: 0.086, green: 0.365, blue: 0.859, alpha: 0.45).setFill()
NSBezierPath(roundedRect: NSRect(x: 449, y: 282, width: 126, height: 18), xRadius: 9, yRadius: 9).fill()

let bolt = NSBezierPath()
bolt.move(to: NSPoint(x: 552, y: 701))
bolt.line(to: NSPoint(x: 408, y: 500))
bolt.line(to: NSPoint(x: 500, y: 500))
bolt.line(to: NSPoint(x: 469, y: 372))
bolt.line(to: NSPoint(x: 620, y: 584))
bolt.line(to: NSPoint(x: 524, y: 584))
bolt.close()
NSGradient(
    colors: [
        NSColor(calibratedRed: 0.780, green: 1, blue: 0.941, alpha: 1),
        NSColor(calibratedRed: 0.314, green: 0.890, blue: 0.698, alpha: 1)
    ]
)?.draw(in: bolt, angle: -70)

NSColor(calibratedRed: 0.051, green: 0.243, blue: 0.502, alpha: 0.52).setFill()
NSBezierPath(ovalIn: NSRect(x: 698, y: 702, width: 98, height: 98)).fill()
NSColor(calibratedRed: 0.333, green: 0.902, blue: 0.682, alpha: 1).setFill()
let status = NSBezierPath(ovalIn: NSRect(x: 715, y: 719, width: 64, height: 64))
status.fill()
NSColor(calibratedRed: 0.910, green: 1, blue: 0.969, alpha: 1).setStroke()
status.lineWidth = 12
status.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("unable to encode icon\n", stderr)
    exit(1)
}

do {
    try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
} catch {
    fputs("unable to write icon: \(error.localizedDescription)\n", stderr)
    exit(1)
}
