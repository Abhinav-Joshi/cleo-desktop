import AppKit

/// A cached pixel orb; its nonactivating window and motion are owned by the app.
final class ThrownBallView: NSView {
    static let artwork: CGImage = {
        var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
        func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int,
                  _ color: (UInt8, UInt8, UInt8)) {
            for row in y..<(y + height) { for column in x..<(x + width) {
                let i = (row * 8 + column) * 4
                pixels[i] = color.0; pixels[i + 1] = color.1
                pixels[i + 2] = color.2; pixels[i + 3] = 255
            } }
        }
        rect(1, 0, 6, 8, (77, 14, 6))
        rect(0, 1, 8, 6, (77, 14, 6))
        rect(2, 1, 4, 6, (240, 31, 14))
        rect(1, 2, 6, 4, (240, 31, 14))
        rect(2, 2, 2, 2, (255, 122, 64))
        return CGImage(width: 8, height: 8, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)!
    }()

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    var ballRect: NSRect { bounds.insetBy(dx: 2, dy: 2) }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        autoresizingMask = [.width, .height]
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setBlendMode(.copy)
        context.clear(bounds)
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(Self.artwork, in: ballRect)
        context.restoreGState()
    }
}
