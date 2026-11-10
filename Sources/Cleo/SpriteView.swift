import AppKit
import ImageIO

/// Each full transparent bitmap replaces the window buffer; tails cannot accumulate.
final class SpriteView: NSView {
    struct Frame { let image: CGImage; var width: Int { image.width }; var height: Int { image.height } }
    private(set) var frames: [Frame] = []
    private(set) var turnFrameCount = 0
    private(set) var barkFrameCount = 0
    private var rig: PixelRig!
    private var currentImage: CGImage?
    private var lastPixels: CFData?
    private var alpha = [UInt8](repeating: 0, count: 64 * 64)
    private var mirrored = false
    private var petting = false
    private var signature = ""
    private var lastStroke: TimeInterval = 0
    private var hoverTracking: NSTrackingArea?
    var onPet: (() -> Void)?
    var onHover: (() -> Void)?
    var companionMenu: NSMenu?

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override var needsPanelToBecomeKey: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for index in 0..<16 {
            let url = Bundle.main.resourceURL!.appendingPathComponent(String(format: "cleo-%02d.png", index))
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { frames.append(Frame(image: image)) }
        }
        var turnFrames: [CGImage] = []
        for index in 0..<16 {
            let url = Bundle.main.resourceURL!.appendingPathComponent(String(format: "turn-%02d.png", index))
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { turnFrames.append(image) }
        }
        turnFrameCount = turnFrames.count
        var barkFrames: [CGImage] = []
        for index in 0..<16 {
            let url = Bundle.main.resourceURL!.appendingPathComponent(String(format: "bark-%02d.png", index))
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) { barkFrames.append(image) }
        }
        barkFrameCount = barkFrames.count
        if frames.count == 16 {
            rig = PixelRig(frames: frames.map(\.image), turnFrames: turnFrames, barkFrames: barkFrames)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var spriteRect: NSRect {
        let available = min(bounds.width - 8, bounds.height - 8)
        let side = max(64, floor(available / 64) * 64)
        return NSRect(x: floor((bounds.width - side) / 2), y: 4, width: side, height: side)
    }
    var ballMouthPointOnScreen: NSPoint? {
        guard let point = rig?.ballMouthPoint, let window else { return nil }
        let rect = spriteRect
        let local = NSPoint(x: rect.minX + (mirrored ? 64 - point.x : point.x) * rect.width / 64,
                            y: rect.minY + (64 - point.y) * rect.height / 64)
        return window.convertPoint(toScreen: convert(local, to: nil))
    }
    var thrownBallDiameter: CGFloat { spriteRect.width / 64 * 7.04 }
    private func paint(in context: CGContext) {
        context.saveGState()
        // Copy, rather than blending over old pixels: transparent areas erase the previous tail.
        context.setBlendMode(.copy)
        context.setFillColor(NSColor.clear.cgColor)
        context.fill(bounds)
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        if mirrored { context.translateBy(x: bounds.width, y: 0); context.scaleBy(x: -1, y: 1) }
        if let image = currentImage { context.draw(image, in: spriteRect) }
        context.restoreGState()
    }
    override func draw(_ dirtyRect: NSRect) {
        if let context = NSGraphicsContext.current?.cgContext { paint(in: context) }
    }

    func render(mood: PetMood, time: Double, facingLeft: Bool, reducedMotion: Bool,
                gaze: CGPoint = .zero, carriedToy: CarriedToy = .none, ballProgress: Double = 0) {
        guard rig != nil else { return }
        let newPetting = mood == .pet
        let mirror = !facingLeft
        let key = "\(mood.rawValue):\(time.bitPattern):\(mirror):\(reducedMotion):\(Int(gaze.x * 10)):\(Int(gaze.y * 10)):\(carriedToy.rawValue):\(ballProgress.bitPattern)"
        guard key != signature else { return }
        signature = key
        rig.gaze = CGPoint(x: mirror ? -gaze.x : gaze.x, y: gaze.y)
        let image = rig.image(mood: mood, time: time, reducedMotion: reducedMotion,
                              carriedToy: carriedToy, ballProgress: ballProgress)
        if let data = image.dataProvider?.data,
           mirror != mirrored || lastPixels == nil || !CFEqual(data, lastPixels) {
            currentImage = image
            lastPixels = data
            if let pixels = CFDataGetBytePtr(data) {
                for y in 0..<64 { for x in 0..<64 { alpha[y * 64 + x] = pixels[y * image.bytesPerRow + x * 4 + 3] } }
            }
            needsDisplay = true
        }
        mirrored = mirror
        if petting != newPetting { petting = newPetting; window?.invalidateCursorRects(for: self) }
    }

    func containsDog(_ point: NSPoint) -> Bool {
        guard spriteRect.contains(point) else { return false }
        let rect = spriteRect
        let sourceX = min(63, max(0, Int((point.x - rect.minX) / rect.width * 64)))
        let x = mirrored ? 63 - sourceX : sourceX
        let y = 63 - min(63, max(0, Int((point.y - rect.minY) / rect.height * 64)))
        return alpha[y * 64 + x] > 32
    }
    func isNearDog(_ point: NSPoint) -> Bool {
        for dy in [-2.0, 0, 2] { for dx in [-2.0, 0, 2] {
            if containsDog(NSPoint(x: point.x + dx, y: point.y + dy)) { return true }
        } }
        return false
    }
    override func hitTest(_ point: NSPoint) -> NSView? { containsDog(convert(point, from: superview)) ? self : nil }
    override func resetCursorRects() { addCursorRect(spriteRect, cursor: petting ? .closedHand : .openHand) }
    override func updateTrackingAreas() {
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverTracking = area
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }
    override func mouseExited(with event: NSEvent) { onHover?() }
    override func mouseDown(with event: NSEvent) { onPet?() }
    override func mouseDragged(with event: NSEvent) {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStroke >= 0.1 && containsDog(convert(event.locationInWindow, from: nil)) { lastStroke = now; onPet?() }
    }
    override func menu(for event: NSEvent) -> NSMenu? { companionMenu }

    /// Captures only Cleo's current frame, never the screen or other windows.
    func snapshot() -> CGImage? {
        let width = Int(bounds.width * 2), height = Int(bounds.height * 2)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: 2, y: 2)
        paint(in: context)
        return context.makeImage()
    }
}
