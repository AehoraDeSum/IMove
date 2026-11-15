import AppKit

let destination = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    NSColor(red: 0.035, green: 0.105, blue: 0.075, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 196, yRadius: 196).fill()
    let center = NSPoint(x: 512, y: 512)
    let sweep = NSBezierPath()
    sweep.move(to: center)
    sweep.appendArc(withCenter: center, radius: 338, startAngle: 26, endAngle: 79)
    sweep.close()
    NSColor(red: 0.29, green: 0.88, blue: 0.52, alpha: 0.45).setFill()
    sweep.fill()
    for (radius, alpha, width) in [(338.0, 0.86, 17.0), (225.0, 0.56, 13.0), (112.0, 0.52, 12.0)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: 512 - radius, y: 512 - radius,
                                                width: radius * 2, height: radius * 2))
        ring.lineWidth = width
        NSColor(white: 1, alpha: alpha).setStroke()
        ring.stroke()
    }
    let beam = NSBezierPath()
    beam.move(to: center)
    beam.line(to: NSPoint(x: 749, y: 749))
    beam.lineWidth = 15
    beam.lineCapStyle = .round
    NSColor.white.withAlphaComponent(0.9).setStroke()
    beam.stroke()
    NSColor(red: 0.29, green: 0.88, blue: 0.52, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 459, y: 459, width: 106, height: 106)).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: 480, y: 480, width: 64, height: 64)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
}

func bigEndian(_ value: Int) -> Data {
    var number = UInt32(value).bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var chunks = Data()
for (type, file) in [("icp4", "icon_16x16"), ("icp5", "icon_32x32"), ("icp6", "icon_32x32@2x"), ("ic07", "icon_128x128"), ("ic08", "icon_256x256"), ("ic09", "icon_512x512"), ("ic10", "icon_512x512@2x")] {
    let png = try Data(contentsOf: destination.appendingPathComponent(file + ".png"))
    chunks.append(Data(type.utf8))
    chunks.append(bigEndian(png.count + 8))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(chunks.count + 8))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
