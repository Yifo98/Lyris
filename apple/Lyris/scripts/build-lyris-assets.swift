import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("usage: swift build-lyris-assets.swift <source.png> <output-directory>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

guard let source = NSImage(contentsOf: sourceURL) else {
    throw NSError(domain: "LyrisAssets", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not read source image"])
}
var sourceRect = NSRect(origin: .zero, size: source.size)
guard let sourceCGImage = source.cgImage(
    forProposedRect: &sourceRect,
    context: nil,
    hints: [.interpolation: NSImageInterpolation.high]
) else {
    throw NSError(domain: "LyrisAssets", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not decode source pixels"])
}

func pngData(size: Int, roundedMask: Bool) throws -> Data {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw NSError(domain: "LyrisAssets", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
    }
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    let artworkInset = CGFloat(size) * 0.055
    let artworkRect = CGRect(
        x: artworkInset,
        y: artworkInset,
        width: CGFloat(size) - artworkInset * 2,
        height: CGFloat(size) - artworkInset * 2
    )
    if roundedMask {
        let radius = artworkRect.width * 0.185
        context.addPath(
            CGPath(
                roundedRect: artworkRect,
                cornerWidth: radius,
                cornerHeight: radius,
                transform: nil
            )
        )
        context.clip()
    }
    context.interpolationQuality = .high
    context.draw(sourceCGImage, in: artworkRect)

    guard let image = context.makeImage() else {
        throw NSError(domain: "LyrisAssets", code: 4, userInfo: [NSLocalizedDescriptionKey: "Could not render icon"])
    }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "LyrisAssets", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    return data
}

let appIconURL = outputDirectory.appendingPathComponent("LyrisAppIcon.png")
try pngData(size: 1024, roundedMask: true).write(to: appIconURL, options: .atomic)

let iconsetURL = outputDirectory.appendingPathComponent("Lyris.iconset", isDirectory: true)
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
for pointSize in [16, 32, 128, 256, 512] {
    try pngData(size: pointSize, roundedMask: true).write(
        to: iconsetURL.appendingPathComponent("icon_\(pointSize)x\(pointSize).png"),
        options: .atomic
    )
    try pngData(size: pointSize * 2, roundedMask: true).write(
        to: iconsetURL.appendingPathComponent("icon_\(pointSize)x\(pointSize)@2x.png"),
        options: .atomic
    )
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = [
    "-c", "icns",
    iconsetURL.path,
    "-o", outputDirectory.appendingPathComponent("Lyris.icns").path,
]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw NSError(domain: "LyrisAssets", code: 6, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}
try fileManager.removeItem(at: iconsetURL)
