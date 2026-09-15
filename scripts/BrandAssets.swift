import AppKit
import ImageIO

guard CommandLine.arguments.count == 7 else {
    fputs("Usage: BrandAssets dog.gif app-icon.png menu-mark.png dmg-source.png dmg-background.png iconset\n", stderr)
    exit(2)
}

let dogGIFURL = URL(fileURLWithPath: CommandLine.arguments[1])
let appIconURL = URL(fileURLWithPath: CommandLine.arguments[2])
let menuMarkURL = URL(fileURLWithPath: CommandLine.arguments[3])
let dmgSourceURL = URL(fileURLWithPath: CommandLine.arguments[4])
let dmgBackgroundURL = URL(fileURLWithPath: CommandLine.arguments[5])
let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[6], isDirectory: true)

guard
    let gifSource = CGImageSourceCreateWithURL(dogGIFURL as CFURL, nil),
    let dogFrame = CGImageSourceCreateImageAtIndex(gifSource, 0, nil)
else {
    fputs("Could not read the first companion frame.\n", stderr)
    exit(1)
}

func steppedTilePath(size: CGFloat, inset: CGFloat) -> NSBezierPath {
    let step = max(1, (size * 0.055).rounded())
    let minimum = inset
    let maximum = size - inset
    let path = NSBezierPath()
    path.move(to: NSPoint(x: minimum + step, y: minimum))
    path.line(to: NSPoint(x: maximum - step, y: minimum))
    path.line(to: NSPoint(x: maximum, y: minimum + step))
    path.line(to: NSPoint(x: maximum, y: maximum - step))
    path.line(to: NSPoint(x: maximum - step, y: maximum))
    path.line(to: NSPoint(x: minimum + step, y: maximum))
    path.line(to: NSPoint(x: minimum, y: maximum - step))
    path.line(to: NSPoint(x: minimum, y: minimum + step))
    path.close()
    return path
}

func renderAppIcon(size: Int) -> NSImage {
    let dimension = CGFloat(size)
    let image = NSImage(size: NSSize(width: dimension, height: dimension))
    image.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    NSColor(calibratedRed: 0.57, green: 0.31, blue: 0.14, alpha: 1).setFill()
    steppedTilePath(size: dimension, inset: 0).fill()
    NSColor(calibratedRed: 0.105, green: 0.055, blue: 0.038, alpha: 1).setFill()
    steppedTilePath(size: dimension, inset: max(1, (dimension * 0.045).rounded())).fill()

    let dogImage = NSImage(cgImage: dogFrame, size: NSSize(width: 64, height: 64))
    let dogCanvas = dimension * (size <= 32 ? 1.02 : 0.86)
    let dogOrigin = (dimension - dogCanvas) / 2
    dogImage.draw(
        in: NSRect(x: dogOrigin, y: dogOrigin, width: dogCanvas, height: dogCanvas),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "MacomonBrandAssets", code: 1)
    }
    try data.write(to: url, options: .atomic)
}

let menuMark = NSBitmapImageRep(cgImage: dogFrame)
guard let menuMarkData = menuMark.representation(using: .png, properties: [:]) else {
    fputs("Could not encode the companion menu mark.\n", stderr)
    exit(1)
}

do {
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
    try menuMarkData.write(to: menuMarkURL, options: .atomic)
    try writePNG(renderAppIcon(size: 1024), to: appIconURL)

    let iconFiles: [(String, Int)] = [
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
    for (filename, size) in iconFiles {
        try writePNG(renderAppIcon(size: size), to: iconsetURL.appendingPathComponent(filename))
    }

    guard let backgroundSource = NSImage(contentsOf: dmgSourceURL) else {
        fputs("Could not read the installer background source.\n", stderr)
        exit(1)
    }
    let background = NSImage(size: NSSize(width: 720, height: 440))
    background.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    NSColor(calibratedRed: 0.07, green: 0.035, blue: 0.025, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 720, height: 440).fill()
    backgroundSource.draw(
        in: NSRect(x: 0, y: 0, width: 720, height: 440),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
    background.unlockFocus()
    try writePNG(background, to: dmgBackgroundURL)
} catch {
    fputs("Brand asset generation failed: \(error)\n", stderr)
    exit(1)
}
