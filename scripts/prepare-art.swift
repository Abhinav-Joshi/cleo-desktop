// Local sprite preparation only: slice generated artwork, reduce to 64 pixels,
// and preserve sharp alpha and nearest-neighbor pixels for the native renderer.
import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift prepare-art.swift source-sheet.png Resources\n", stderr)
    exit(2)
}
let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read sheet") }
var images: [CGImage] = []
for row in 0..<4 {
    for column in 0..<4 {
        let x0 = Int((Double(column) * Double(sheet.width) / 4).rounded())
        let x1 = Int((Double(column + 1) * Double(sheet.width) / 4).rounded())
        let y0 = Int((Double(row) * Double(sheet.height) / 4).rounded())
        let y1 = Int((Double(row + 1) * Double(sheet.height) / 4).rounded())
        let crop = sheet.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))!
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(data: bytes.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                                    bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 64, height: 64))
        }
        // Pixel sprites use binary alpha; discard faint generation halos and undo premultiplication.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Int(pixels[index + 3])
            if alpha < 160 { pixels[index] = 0; pixels[index + 1] = 0; pixels[index + 2] = 0; pixels[index + 3] = 0 }
            else {
                for channel in 0..<3 { pixels[index + channel] = UInt8(min(255, Int(pixels[index + channel]) * 255 / alpha)) }
                pixels[index + 3] = 255
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        images.append(image)
        let index = row * 4 + column
        let url = outputURL.appendingPathComponent(String(format: "cleo-%02d.png", index))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
    }
}

// A contact sheet and looping preview live outside the runtime's Resources.
let previewURL = outputURL.deletingLastPathComponent().appendingPathComponent("Artwork", isDirectory: true)
try FileManager.default.createDirectory(at: previewURL, withIntermediateDirectories: true)
let contact = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
contact.setFillColor(CGColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1))
contact.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
contact.interpolationQuality = .none
for (index, image) in images.enumerated() {
    contact.draw(image, in: CGRect(x: (index % 4) * 256, y: (3 - index / 4) * 256, width: 256, height: 256))
}
let preview = CGImageDestinationCreateWithURL(previewURL.appendingPathComponent("cleo-pixel-poses.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(preview, contact.makeImage()!, nil)
CGImageDestinationFinalize(preview)
let gif = CGImageDestinationCreateWithURL(previewURL.appendingPathComponent("cleo-preview.gif") as CFURL, UTType.gif.identifier as CFString, 16, nil)!
CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for image in images {
    let context = CGContext(data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 1024,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.94, green: 0.93, blue: 0.89, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: 256, height: 256))
    CGImageDestinationAddImage(gif, context.makeImage()!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.28]] as CFDictionary)
}
CGImageDestinationFinalize(gif)
let iconset = previewURL.appendingPathComponent("Cleo.iconset", isDirectory: true)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let side = points * scale
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(images[0], in: CGRect(x: 0, y: 0, width: side, height: side))
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        let destination = CGImageDestinationCreateWithURL(iconset.appendingPathComponent(name) as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
    }
}
print("Prepared sixteen 64×64 pixel sprites and local previews.")
