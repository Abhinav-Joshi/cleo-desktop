// Register the generated head animation to Cleo's unchanged seated body.
import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else {
    fputs("Usage: swift prepare-bark.swift bark-sheet.png seated.png Resources\n", stderr)
    exit(2)
}
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let reference = URL(fileURLWithPath: CommandLine.arguments[2])
let output = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
func read(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read \(url.path)") }
    return image
}
func decode(_ image: CGImage) -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: 16384)
    pixels.withUnsafeMutableBytes { bytes in
        let context = CGContext(data: bytes.baseAddress, width: 64, height: 64,
            bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Int(pixels[i + 3])
        if alpha < 160 {
            for c in 0..<4 { pixels[i + c] = 0 }
        } else {
            for c in 0..<3 { pixels[i + c] = UInt8(min(255, Int(pixels[i + c]) * 255 / alpha)) }
            pixels[i + 3] = 255
        }
    }
    return pixels
}
func tagAnchor(_ pixels: [UInt8], fallback: CGPoint) -> CGPoint {
    var candidates = Set<Int>()
    for y in 34...49 { for x in 20...40 {
        let i = (y * 64 + x) * 4
        let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
        if pixels[i + 3] > 0 && r >= 160 && g >= 95 && b <= 110 && r > g * 1.1 && r < g * 1.7 && g > b * 1.8 {
            candidates.insert(y * 64 + x)
        }
    } }
    var best = fallback, bestScore = Double.infinity
    while let seed = candidates.first {
        candidates.remove(seed)
        var component = [seed], cursor = 0
        while cursor < component.count {
            let p = component[cursor]
            for n in [p - 64, p + 64, p - 1, p + 1] where candidates.remove(n) != nil { component.append(n) }
            cursor += 1
        }
        guard component.count >= 2 else { continue }
        let count = Double(component.count)
        let center = CGPoint(x: component.reduce(0.0) { $0 + Double($1 % 64) } / count,
                             y: component.reduce(0.0) { $0 + Double($1 / 64) } / count)
        let score = hypot(center.x - 30, center.y - 44) + Double(max(0, component.count - 12)) * 2
        if score < bestScore { best = center; bestScore = score }
    }
    return best
}
func image(_ pixels: [UInt8]) -> CGImage {
    CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
        shouldInterpolate: false, intent: .defaultIntent)!
}
func save(_ image: CGImage, _ url: URL) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot write \(url.path)") }
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sheet = read(input), seated = decode(read(reference))
let target = tagAnchor(seated, fallback: CGPoint(x: 31, y: 43))
print("Reference tag: \(target)")
var images: [CGImage] = []
// The generated final row changes scale. Reuse the matching relaxed head from
// the first row, and bookend the clip with the exact approved resting texture.
let sequence = [-1, 0, 2, 3, 4, 5, 6, 0, 8, 9, 10, 11, 6, 0, 0, -1]
for index in 0..<16 {
    let sourceIndex = sequence[index]
    if sourceIndex < 0 {
        let frame = image(seated)
        images.append(frame)
        save(frame, output.appendingPathComponent(String(format: "bark-%02d.png", index)))
        continue
    }
    let col = sourceIndex % 4, row = sourceIndex / 4
    let x0 = Int((Double(col) * Double(sheet.width) / 4).rounded())
    let x1 = Int((Double(col + 1) * Double(sheet.width) / 4).rounded())
    let y0 = Int((Double(row) * Double(sheet.height) / 4).rounded())
    let y1 = Int((Double(row + 1) * Double(sheet.height) / 4).rounded())
    let crop = sheet.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))!
    let head = decode(crop)
    let anchor = tagAnchor(head, fallback: CGPoint(x: 30, y: 44))
    let dx = Int((target.x - anchor.x).rounded()), dy = Int((target.y - anchor.y).rounded())
    var pixels = seated
    // Keep the approved paws, body, collar, and tail byte-for-byte. The entire
    // animated head and neck replace the old head, with a continuous fur join.
    for y in 0...40 { for x in 0...53 {
        let i = (y * 64 + x) * 4
        for c in 0..<4 { pixels[i + c] = 0 }
    } }
    var headRegion = Set<Int>()
    for y in 0..<64 { for x in 0..<64 {
        let tx = x + dx, ty = y + dy
        guard tx >= 0, tx <= 53, ty >= 0, ty <= 40 else { continue }
        if head[(y * 64 + x) * 4 + 3] > 0 { headRegion.insert(y * 64 + x) }
    } }
    // Discard disconnected tail-tip fragments from the generated cells.
    var largest: [Int] = []
    while let seed = headRegion.first {
        headRegion.remove(seed)
        var component = [seed], cursor = 0
        while cursor < component.count {
            let p = component[cursor]
            for n in [p - 64, p + 64, p - 1, p + 1] where headRegion.remove(n) != nil { component.append(n) }
            cursor += 1
        }
        if component.count > largest.count { largest = component }
    }
    for p in largest {
        let from = p * 4, to = ((p / 64 + dy) * 64 + p % 64 + dx) * 4
        for c in 0..<4 { pixels[to + c] = head[from + c] }
    }
    let frame = image(pixels)
    images.append(frame)
    save(frame, output.appendingPathComponent(String(format: "bark-%02d.png", index)))
    print("Frame \(index): tag \(anchor), registration \(dx),\(dy)")
}
let contact = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
    bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
contact.setFillColor(CGColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1))
contact.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
contact.interpolationQuality = .none
for (index, frame) in images.enumerated() {
    contact.draw(frame, in: CGRect(x: (index % 4) * 256, y: (3 - index / 4) * 256, width: 256, height: 256))
}
let artwork = output.deletingLastPathComponent().appendingPathComponent("Artwork", isDirectory: true)
save(contact.makeImage()!, artwork.appendingPathComponent("cleo-bark-frames.png"))
print("Prepared sixteen registered bark frames with Cleo's original body and tail.")
