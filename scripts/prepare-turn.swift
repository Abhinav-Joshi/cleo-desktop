// Slice the dedicated sixteen-frame bedtime turn into small, sharp runtime images.
import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift prepare-turn.swift source.png Resources\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
      let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read turn sheet") }
var images: [CGImage] = []
for index in 0..<16 {
    let column = index % 4, row = index / 4
    let x0 = Int((Double(column) * Double(sheet.width) / 4).rounded())
    let x1 = Int((Double(column + 1) * Double(sheet.width) / 4).rounded())
    let y0 = Int((Double(row) * Double(sheet.height) / 4).rounded())
    let y1 = Int((Double(row + 1) * Double(sheet.height) / 4).rounded())
    let crop = sheet.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))!
    var pixels = [UInt8](repeating: 0, count: 16384)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: 64, height: 64,
            bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(crop, in: CGRect(x: 4, y: 4, width: 56, height: 56))
    }
    var minX = 64, maxX = 0, maxY = 0
    for y in 0..<64 { for x in 0..<64 {
        let offset = (y * 64 + x) * 4
        let alpha = Int(pixels[offset + 3])
        if alpha < 160 {
            for channel in 0..<4 { pixels[offset + channel] = 0 }
        } else {
            for channel in 0..<3 { pixels[offset + channel] = UInt8(min(255, Int(pixels[offset + channel]) * 255 / alpha)) }
            pixels[offset + 3] = 255
            minX = min(minX, x); maxX = max(maxX, x); maxY = max(maxY, y)
        }
    } }
    // Keep the paw plane and character center steady as the viewpoint turns.
    let dx = 32 - (minX + maxX) / 2, dy = 59 - maxY
    var aligned = [UInt8](repeating: 0, count: 16384)
    for y in 0..<64 { for x in 0..<64 {
        let toX = x + dx, toY = y + dy
        guard toX >= 0, toX < 64, toY >= 0, toY < 64 else { continue }
        let from = (y * 64 + x) * 4, to = (toY * 64 + toX) * 4
        for channel in 0..<4 { aligned[to + channel] = pixels[from + channel] }
    } }
    let image = CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(aligned) as CFData)!, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent)!
    images.append(image)
    let url = output.appendingPathComponent(String(format: "turn-%02d.png", index))
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Turn frame write failed") }
}
let contact = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
    bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
contact.setFillColor(CGColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1))
contact.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
contact.interpolationQuality = .none
for (index, image) in images.enumerated() {
    contact.draw(image, in: CGRect(x: (index % 4) * 256, y: (3 - index / 4) * 256, width: 256, height: 256))
}
let artwork = output.deletingLastPathComponent().appendingPathComponent("Artwork", isDirectory: true)
let destination = CGImageDestinationCreateWithURL(artwork.appendingPathComponent("cleo-bedtime-turn-frames.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, contact.makeImage()!, nil)
CGImageDestinationFinalize(destination)
print("Prepared sixteen turning frames with aligned feet and sharp transparency.")
