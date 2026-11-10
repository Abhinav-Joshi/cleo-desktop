import AppKit

/// The dog is one continuously deformed texture, with no detached cutout limbs.
final class PixelRig {
    var gaze: CGPoint = .zero
    /// Current mouth attachment in the rendered 64px image, measured from its top left.
    private(set) var ballMouthPoint: CGPoint?
    private struct Point { var x: Double; var y: Double }
    private struct Pose { let pixels: [UInt8]; let tail: Point; let head: Point; let kind: Int }
    private struct Bone { let kind: Int; let root: Point; let c: Double; let s: Double; let dx: Double; let dy: Double }
    private let seated: Pose, walking: Pose, playBow: Pose, catching: Pose, sleeping: Pose, bedtimeWalking: Pose
    private let turning: [Pose]
    private let turningFloors: [Double]
    private let barking: [Pose]
    private let ballWalking: [Pose]
    private let ballMouths: [Point]
    private let colorSpace = CGColorSpaceCreateDeviceRGB()
    private var idleFrames = [CGImage?](repeating: nil, count: 60)
    private let padding = 0.88

    init(frames: [CGImage], turnFrames: [CGImage] = [], barkFrames: [CGImage] = []) {
        precondition(!frames.isEmpty, "PixelRig needs Cleo's artwork")
        func pose(_ index: Int, _ kind: Int, _ tail: Point, _ head: Point) -> Pose {
            var pixels = [UInt8](repeating: 0, count: 16384)
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: 64, height: 64,
                    bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.interpolationQuality = .none
                context.draw(frames[min(index, frames.count - 1)], in: CGRect(x: 0, y: 0, width: 64, height: 64))
            }
            for y in 0..<64 { for x in 0..<64 {
                // Remove only the detached ball; neither the paw nor snout is cut.
                if (kind == 2 && x <= 13 && y > 44) || (kind == 3 && x <= 15 && y < 30) || (kind == 1 && y < 10) {
                    let i = (y * 64 + x) * 4
                    for channel in 0..<4 { pixels[i + channel] = 0 }
                }
            } }
            return Pose(pixels: pixels, tail: tail, head: head, kind: kind)
        }
        // Roots measured in the user's selected original art, with y measured from its top.
        seated = pose(0, 0, Point(x: 54, y: 52), Point(x: 34, y: 40))
        let walkingSource = pose(4, 1, Point(x: 55, y: 32), Point(x: 34, y: 40))
        walking = walkingSource
        playBow = pose(8, 2, Point(x: 56, y: 25), Point(x: 43, y: 44))
        let emptyMouthSource = pose(9, 3, Point(x: 56, y: 27), Point(x: 38, y: 33))
        catching = emptyMouthSource
        sleeping = pose(12, 4, Point(x: 54, y: 45), Point(x: 35, y: 46))
        // Flatten the neutral head into the actual walking stance once. The
        // resulting whole texture then uses exactly the same continuous skinning.
        // The neutral snout is two pixels left and eight pixels down in this pose.
        var bedtimePixels = walkingSource.pixels
        for y in 0..<42 { for x in 0..<40 {
            let i = (y * 64 + x) * 4
            for channel in 0..<4 { bedtimePixels[i + channel] = 0 }
        } }
        for sy in 9..<35 { for sx in 16..<46 {
            let from = (sy * 64 + sx) * 4
            guard emptyMouthSource.pixels[from + 3] != 0 else { continue }
            let to = ((sy + 8) * 64 + sx - 2) * 4
            for channel in 0..<4 { bedtimePixels[to + channel] = emptyMouthSource.pixels[from + channel] }
        } }
        bedtimeWalking = Pose(pixels: bedtimePixels, tail: walkingSource.tail, head: walkingSource.head, kind: 1)
        // The generator's row order contains heading reversals. Matched mirrors
        // give eight coherent headings, each with two walking steps, around 360°.
        let headings = [0, 1, 2, 3, 4, -5, -3, -4, -1, -2, 9, 12, 11, -12, -10, -13]
        var turnPoses: [Pose] = []
        var floors: [Double] = []
        if turnFrames.count >= 16 {
            var decoded: [[UInt8]] = []
            for image in turnFrames.prefix(16) {
                var pixels = [UInt8](repeating: 0, count: 16384)
                pixels.withUnsafeMutableBytes { bytes in
                    let context = CGContext(data: bytes.baseAddress, width: 64, height: 64,
                        bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.interpolationQuality = .none
                    context.setShouldAntialias(false)
                    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
                }
                decoded.append(pixels)
            }
            for heading in headings {
                let index = heading >= 0 ? heading : -heading - 1
                let original = decoded[index]
                var pixels = original
                if heading < 0 {
                    for y in 0..<64 { for x in 0..<64 { for channel in 0..<4 {
                        pixels[(y * 64 + x) * 4 + channel] = original[(y * 64 + 63 - x) * 4 + channel]
                    } } }
                }
                var floor = 59
                findFloor: for y in stride(from: 63, through: 0, by: -1) {
                    for x in 0..<64 where pixels[(y * 64 + x) * 4 + 3] != 0 {
                        floor = y
                        break findFloor
                    }
                }
                turnPoses.append(Pose(pixels: pixels, tail: Point(x: 45, y: 39),
                                      head: Point(x: 31, y: 34), kind: 5))
                floors.append(Double(floor + 1))
            }
        }
        turning = turnPoses
        turningFloors = floors
        var barkPoses: [Pose] = []
        if barkFrames.count >= 16 {
            for image in barkFrames.prefix(16) {
                var pixels = [UInt8](repeating: 0, count: 16384)
                pixels.withUnsafeMutableBytes { bytes in
                    let context = CGContext(data: bytes.baseAddress, width: 64, height: 64,
                        bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    context.interpolationQuality = .none
                    context.setShouldAntialias(false)
                    context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
                }
                barkPoses.append(Pose(pixels: pixels, tail: seated.tail, head: seated.head, kind: 6))
            }
        }
        barking = barkPoses
        var ballPoses: [Pose] = []
        var mouthPoints: [Point] = []
        if barkPoses.count == 16 {
            // Reuse the approved complete head lift: nose, upper jaw, eyes, and
            // ears travel together. Flatten each head onto the walking body once.
            let heads = [1, 2, 3, 4, 5, 6]
            let mouths = [Point(x: 27, y: 34), Point(x: 24.5, y: 31.5),
                          Point(x: 26, y: 29.5), Point(x: 25, y: 29.5),
                          Point(x: 26, y: 32), Point(x: 27, y: 34)]
            for (step, index) in heads.enumerated() {
                var pixels = walkingSource.pixels
                for y in 0..<42 { for x in 0..<40 {
                    for channel in 0..<4 { pixels[(y * 64 + x) * 4 + channel] = 0 }
                } }
                for y in 0...42 { for x in 0..<46 {
                    let sx = Int(floor((Double(x) + 0.5 - 22) / 0.85 + 30))
                    let sy = Int(floor((Double(y) + 0.5 - 45) / 0.85 + 44))
                    guard sx >= 0 && sx <= 53 && sy >= 0 && sy <= 40 else { continue }
                    let from = (sy * 64 + sx) * 4
                    guard barkPoses[index].pixels[from + 3] != 0 else { continue }
                    let to = (y * 64 + x) * 4
                    for channel in 0..<4 { pixels[to + channel] = barkPoses[index].pixels[from + channel] }
                } }
                ballPoses.append(Pose(pixels: pixels, tail: walkingSource.tail,
                    head: Point(x: 27, y: 41), kind: 1))
                mouthPoints.append(Point(x: 22 + (mouths[step].x - 30) * 0.85,
                                         y: 45 + (mouths[step].y - 44) * 0.85))
            }
        }
        ballWalking = ballPoses
        ballMouths = mouthPoints
    }

    func image(mood: PetMood, time: Double, reducedMotion: Bool,
               carriedToy: CarriedToy = .none, ballProgress: Double = 0) -> CGImage {
        ballMouthPoint = nil
        let t = time.isFinite ? max(0, time) : 0
        let idleIndex = Int(t * 12) % idleFrames.count
        if mood == .idle && !reducedMotion, let cached = idleFrames[idleIndex] { return cached }
        let clock = mood == .idle ? Double(idleIndex) / 12 : t
        let phase = clock * .pi * 2, motion = reducedMotion ? 0.0 : 1.0
        var bones: [Bone] = []
        var bob = 0.0, breath = 0.0
        var sleepyEyeOpening = 0.0
        var bodyWidth = 1.0, bodyHeight = 1.0
        var renderPadding = padding
        let catchTime = min(BallTimeline.duration, max(0,
            ballProgress.isFinite && ballProgress > 0 ? ballProgress * BallTimeline.duration : t))
        var mouth = Point(x: 15, y: 35)
        let pose: Pose
        func bone(_ kind: Int, _ root: Point, _ angle: Double, _ dx: Double = 0, _ dy: Double = 0) {
            bones.append(Bone(kind: kind, root: root, c: cos(angle), s: sin(angle), dx: dx, dy: dy))
        }
        switch mood {
        case .idle, .wag, .pet:
            pose = seated
            let happy = mood == .wag || mood == .pet
            bone(0, pose.tail, sin(phase * (happy ? 2.1 : 0.8)) * (happy ? 0.29 : 0.09) * motion)
            // Sitting and wagging keep her face and ears still. Nuzzling belongs
            // only to an actual petting interaction.
            if mood == .pet {
                bone(1, pose.head, (sin(phase * 0.2) * 0.035 + sin(phase * 0.6) * 0.02) * motion,
                     0, sin(phase * 0.6) * 0.65 * motion)
            }
        case .bark:
            if barking.count == 16 {
                // The dedicated chronological clip moves the upper jaw, nose,
                // eyes, and ears together. No synthetic lip warp is applied.
                // The requested greeting remains visible in Gentle mode;
                // the window and paws stay fixed throughout this short clip.
                let index = min(15, Int(t / 0.95 * 16))
                pose = barking[index]
                // A separate, strictly right-hand field keeps the animated
                // bark head and ears completely outside the tail's influence.
                bone(0, pose.tail, sin(phase * 2.1) * (reducedMotion ? 0.12 : 0.25))
            } else {
                // A coherent whole-head fallback if optional art is unavailable.
                // Preserve the original mouth texture instead of rebuilding it.
                pose = seated
                func woof(_ start: Double) -> Double {
                    smooth(start, start + 0.055, t) * (1 - smooth(start + 0.10, start + 0.205, t))
                }
                let lift = max(woof(0.055), woof(0.465)) * motion
                bone(1, pose.head, lift * 0.20, 0, -lift * 1.4)
            }
        case .stick, .run:
            pose = playBow
            let lookX = Double(max(-1, min(1, gaze.x.isFinite ? gaze.x : 0)))
            let lookY = Double(max(-1, min(1, gaze.y.isFinite ? gaze.y : 0)))
            bone(0, pose.tail, sin(phase * 2) * 0.35 * motion)
            bone(1, pose.head, (lookY * 0.09 + sin(phase * 0.5) * 0.018) * motion,
                 lookX * 0.65 * motion, sin(phase * 0.8) * 0.55 * motion)
            if mood == .run { bob = -abs(sin(phase * 2.2)) * 1.4 * motion }
        case .walk:
            // The walking source includes a stick. Use its neutral, coherently
            // flattened head whenever she is empty-mouthed or carrying her ball.
            if carriedToy == .ball, let closed = ballWalking.last, let anchor = ballMouths.last {
                pose = closed
                mouth = anchor
            } else { pose = carriedToy == .stick ? walking : bedtimeWalking }
            let gait = phase * 2.2
            bone(0, pose.tail, sin(gait * 0.65) * 0.18 * motion)
            bone(1, pose.head, sin(gait + 0.8) * 0.028 * motion)
            bone(2, Point(x: 27, y: 46), sin(gait) * 0.19 * motion)
            bone(3, Point(x: 49, y: 46), -sin(gait) * 0.19 * motion)
            bob = -abs(sin(gait)) * 0.65 * motion
        case .circleSleep:
            if turning.count == 16 {
                let index = reducedMotion ? 15 : min(15, Int(t * 5))
                pose = turning[index]
                renderPadding = 1
                // These frames change the body's actual heading, including its
                // rear view; the window's path and facing do not fake the turn.
                // Align planted feet across the two steps in each heading.
                bob = 49.6 - turningFloors[index] - abs(sin(phase * 2.5)) * 0.35 * motion
            } else {
            // Planted walking legs, with a neutral empty mouth instead of a
            // raised-paw catching silhouette, make this a quiet bedtime walk.
            pose = bedtimeWalking
            let gait = phase * 2.05
            bone(0, pose.tail, sin(gait * 0.45) * 0.07 * motion)
            bone(1, pose.head, sin(gait + 0.5) * 0.018 * motion,
                 0, sin(gait * 2) * 0.30 * motion)
            bone(4, Point(x: 24, y: 47), sin(gait) * 0.20 * motion)
            bone(5, Point(x: 33, y: 47), -sin(gait) * 0.20 * motion)
            bone(6, Point(x: 45, y: 46), -sin(gait) * 0.17 * motion)
            bone(7, Point(x: 56, y: 47), sin(gait) * 0.17 * motion)
            bob = -11 - abs(sin(gait)) * 0.45 * motion
            }
        case .settleSleep:
            let progress = reducedMotion ? 1 : min(1, t / 0.9)
            if progress < 0.55 {
                pose = turning.last ?? bedtimeWalking
                if !turning.isEmpty { renderPadding = 1 }
                let fold = smooth(0, 0.55, progress)
                // Bend at the knees, lower the chest, and bring the muzzle
                // toward the paws. The feet stay on the same floor throughout.
                bodyWidth = 1 + fold * 0.17
                bodyHeight = 1 - fold * 0.34
                // Walking source feet are at row63; keep them at the curled
                // pose's row52 floor while its knees and chest come down.
                bob = -3 - 8 * bodyHeight
                if let floor = turningFloors.last {
                    // Continue directly from the last curved turn texture. The
                    // same planted paw reaches the floor as she folds down.
                    bob = 49.6 - (55 + (floor - 55) * bodyHeight)
                }
                bone(1, pose.head, fold * -0.045, -fold * 3.5, fold * 5)
                if turning.isEmpty {
                    bone(4, Point(x: 24, y: 47), fold * -0.26)
                    bone(5, Point(x: 33, y: 47), fold * 0.24)
                    bone(6, Point(x: 45, y: 46), fold * 0.21)
                    bone(7, Point(x: 56, y: 47), fold * -0.20)
                }
            } else {
                // At ground contact the tucked pose takes over once; its head
                // and back then relax into the exact sleeping silhouette.
                // There is never a transparent double dog or a cycling pose card.
                pose = sleeping
                let release = 1 - smooth(0.55, 1, progress)
                bodyWidth = 1 + release * 0.025
                bodyHeight = 1 + release * 0.025
                bone(1, pose.head, release * -0.035, 0, -release * 0.7)
            }
        case .sleepGreeting:
            // Stay in the exact curled pose. Only her eyes and the lower curled
            // tail tip acknowledge the greeting; she never raises her head.
            pose = sleeping
            let greeting = smooth(0, 0.25, t) * (1 - smooth(2.15, 2.4, t))
            sleepyEyeOpening = greeting
            bone(10, Point(x: 57, y: 43),
                 sin(phase * 1.5) * greeting * (reducedMotion ? 0.05 : 0.10))
        case .sleep, .sleepy:
            pose = sleeping
            breath = (sin(t * .pi * 2 * 0.24) + 1) * 0.009 * motion
            bone(1, pose.head, sin(t * .pi * 2 * 0.24) * 0.009 * motion)
        case .catchBall:
            // One complete action uses the same neutral standing texture as the
            // walk home: watch, approach, crouch, pounce once, absorb, and hold.
            if ballWalking.count == 6 {
                let head: Int
                if catchTime < 1.1 { head = 0 }
                else if catchTime < 1.3 { head = 1 }
                else if catchTime < 1.5 { head = 2 }
                else if catchTime < 1.7 { head = 3 }
                else if catchTime < 1.85 { head = 4 }
                else { head = 5 }
                pose = ballWalking[head]
                mouth = ballMouths[head]
            } else { pose = bedtimeWalking }
            let approach = smooth(BallTimeline.approachStart, 0.5, catchTime)
                * (1 - smooth(1.05, BallTimeline.approachEnd, catchTime))
            let gait = max(0, catchTime - BallTimeline.approachStart) * .pi * 4.4
            let windUp = smooth(0.95, BallTimeline.approachEnd, catchTime)
                * (1 - smooth(BallTimeline.approachEnd, 1.3, catchTime))
            let flightProgress = smooth(BallTimeline.approachEnd, 1.9, catchTime)
            let flight = sin(flightProgress * .pi) * motion
            let absorption = smooth(1.82, 1.96, catchTime)
                * (1 - smooth(1.96, BallTimeline.landed, catchTime))
            let compression = (windUp + absorption) * motion
            bodyWidth = 1 + compression * 0.025
            bodyHeight = 1 - compression * 0.065
            // Compensate the anchored scale so paws meet the same floor.
            bob = 8 * (1 - bodyHeight) - flight * 5
            bone(2, Point(x: 27, y: 46),
                 (sin(gait) * 0.19 * approach + flight * 0.16) * motion)
            bone(3, Point(x: 49, y: 46),
                 (-sin(gait) * 0.19 * approach - flight * 0.12) * motion)
            bone(1, pose.head, (0.020 + flight * 0.045) * motion,
                 0, -flight * 0.35)
            bone(0, pose.tail, sin(catchTime * .pi * 3) * 0.13 * motion
                 * (1 - smooth(3.4, BallTimeline.duration, catchTime)))
        }
        var source = pose.pixels
        if mood == .stick || mood == .run { drawStick(into: &source) }
        if mood == .sleepGreeting { drawSleepyEyes(into: &source, openness: sleepyEyeOpening) }
        if (mood == .walk && carriedToy == .ball)
            || (mood == .catchBall && catchTime >= BallTimeline.catchTime) {
            // Held props are part of the source texture before skinning, so the
            // ball follows every head movement and cannot float beside her face.
            drawCarriedBall(into: &source, x: Int(mouth.x), y: Int(mouth.y))
        }
        if mood == .catchBall || (mood == .walk && carriedToy == .ball) {
            // Use the actual integer source-ball center for both the held prop
            // and the independent incoming ball's world-space endpoint.
            let anchor = Point(x: Double(Int(mouth.x)), y: Double(Int(mouth.y)))
            let delta = displacement(anchor, pose: pose, bones: bones)
            let skinned = Point(x: (anchor.x + delta.x - 48) * bodyWidth + 48,
                                y: (anchor.y + delta.y - 55) * bodyHeight + 55)
            ballMouthPoint = CGPoint(x: 32 + (skinned.x - 32) * renderPadding,
                y: 32 + ((skinned.y - 53) * (1 + breath) + 53 + bob - 32) * renderPadding)
        }
        var output = [UInt8](repeating: 0, count: 16384)
        for y in 0..<64 { for x in 0..<64 {
            var target = Point(x: (Double(x) + 0.5 - 32) / renderPadding + 32,
                y: ((Double(y) + 0.5 - 32) / renderPadding + 32 - bob - 53) / (1 + breath) + 53)
            if bodyWidth != 1 { target.x = (target.x - 48) / bodyWidth + 48 }
            if bodyHeight != 1 { target.y = (target.y - 55) / bodyHeight + 55 }
            var sample = target
            // Invert a continuous joint field, then sample the original texture once.
            // Every bone fades to zero at its attachment to the stationary torso.
            for _ in 0..<5 {
                let delta = displacement(sample, pose: pose, bones: bones)
                sample = Point(x: target.x - delta.x, y: target.y - delta.y)
            }
            let sx = Int(floor(sample.x)), sy = Int(floor(sample.y))
            if sx >= 0 && sx < 64 && sy >= 0 && sy < 64 {
                let from = (sy * 64 + sx) * 4, to = (y * 64 + x) * 4
                for channel in 0..<4 { output[to + channel] = source[from + channel] }
            }
        } }
        if mood == .bark {
            // A warped tail outline can leave a solitary pixel at its old edge.
            // Clear only isolated bark pixels; connected head, body, and fur stay intact.
            let occupied = output
            for y in 0..<64 { for x in 0..<64 {
                let i = (y * 64 + x) * 4
                guard occupied[i + 3] != 0 else { continue }
                var hasNeighbor = false
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0 && nx < 64 && ny >= 0 && ny < 64,
                       occupied[(ny * 64 + nx) * 4 + 3] != 0 { hasNeighbor = true }
                } }
                if !hasNeighbor { for channel in 0..<4 { output[i + channel] = 0 } }
            } }
        }
        let provider = CGDataProvider(data: Data(output) as CFData)!
        let base = CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 256, space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        var result = base
        if mood == .pet {
            let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
                bytesPerRow: 256, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.clear(CGRect(x: 0, y: 0, width: 64, height: 64))
            context.clip(to: CGRect(x: 0, y: 0, width: 64, height: 64))
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.draw(base, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            heart(on: context, time: t, reduced: reducedMotion)
            result = context.makeImage()!
        }
        if mood == .idle && !reducedMotion { idleFrames[idleIndex] = result }
        return result
    }

    private func displacement(_ p: Point, pose: Pose, bones: [Bone]) -> Point {
        var result = Point(x: 0, y: 0)
        for bone in bones {
            let w = influence(p, kind: bone.kind, pose: pose)
            if w <= 0 { continue }
            let x = p.x - bone.root.x, y = p.y - bone.root.y
            result.x += (x * bone.c - y * bone.s - x + bone.dx) * w
            result.y += (x * bone.s + y * bone.c - y + bone.dy) * w
        }
        return result
    }
    private func influence(_ p: Point, kind: Int, pose: Pose) -> Double {
        switch kind {
        case 0:
            if pose.kind == 6 {
                // Bark artwork's ear can reach x53 through row40. Keep every
                // one of those pixels still while the original tail wags.
                let left = 54 - min(7, max(0, p.y - 41))
                return smooth(left, left + 3, p.x) * smooth(0, 13, pose.tail.y - p.y)
            }
            if pose.kind == 0 {
                // The seated ear reaches x52 around rows32...35. Trace the clear
                // space to its right, then widen below the ear toward the rump.
                // Tail influence is exactly zero over the entire head silhouette.
                let left = max(47, 53 - max(0, p.y - 35) * 1.5)
                return smooth(left, left + 3, p.x) * smooth(33, 34, p.y)
                    * smooth(0, 13, pose.tail.y - p.y)
            }
            return smooth(41, 48, p.x) * smooth(0, 13, pose.tail.y - p.y)
        case 1:
            switch pose.kind {
            case 0: return smooth(54, 48, p.x) * smooth(44, 36, p.y)
            case 1: return smooth(44, 35, p.x) * smooth(47, 39, p.y)
            case 2: return smooth(49, 36, p.x) * smooth(58, 51, p.y)
            case 3: return smooth(45, 34, p.x) * smooth(38, 30, p.y)
            default: return smooth(43, 32, p.x) * smooth(54, 47, p.y)
            }
        case 2: return smooth(44, 54, p.y) * smooth(40, 32, p.x)
        case 3: return smooth(44, 54, p.y) * smooth(35, 43, p.x)
        case 4: return smooth(36, 45, p.y) * smooth(30, 25, p.x)
        case 5: return smooth(38, 48, p.y) * smooth(24, 29, p.x) * smooth(40, 34, p.x)
        case 6: return smooth(42, 52, p.y) * smooth(43, 49, p.x) * smooth(60, 54, p.x)
        case 7: return smooth(42, 52, p.y) * smooth(55, 61, p.x)
        case 10:
            // The tail curls around the right-hand front of the sleeping dog.
            // The upper back, face, paws, and stationary tail root stay untouched.
            return smooth(42, 48, p.y) * smooth(38, 44, p.x) * smooth(64, 60, p.x)
        default: return 0
        }
    }
    private func smooth(_ start: Double, _ end: Double, _ value: Double) -> Double {
        let t = max(0, min(1, (value - start) / (end - start)))
        return t * t * (3 - 2 * t)
    }
    private func drawSleepyEyes(into pixels: inout [UInt8], openness: Double) {
        guard openness > 0.12 else { return }
        let original = pixels
        func pixel(_ x: Int, _ y: Int, _ color: (UInt8, UInt8, UInt8)) {
            let i = (y * 64 + x) * 4
            pixels[i] = color.0; pixels[i + 1] = color.1; pixels[i + 2] = color.2; pixels[i + 3] = 255
        }
        // Replace only the closed eyelid strokes with neighboring original fur.
        // The muzzle, sleeping head outline, ears, and body are unchanged.
        for (left, right, top, bottom) in [(14, 18, 38, 40), (23, 28, 38, 41)] {
            for y in top...bottom { for x in left...right {
                let sx = 19 + (x + y) % 2, sy = 35 + (y - top) % 2
                let i = (sy * 64 + sx) * 4
                pixel(x, y, (original[i], original[i + 1], original[i + 2]))
            } }
        }
        let dark: (UInt8, UInt8, UInt8) = (48, 22, 10)
        let warm: (UInt8, UInt8, UInt8) = (99, 53, 24)
        let height = openness < 0.55 ? 2 : 3
        for (x, y) in [(15, 38), (24, 39)] {
            if height == 2 {
                for column in 0..<3 { pixel(x + column, y, warm) }
                pixel(x + 1, y + 1, dark)
            } else {
                // Rounded three-pixel almonds, with warm corners rather than
                // tall rectangular pupils, keep the sleepy face soft.
                pixel(x + 1, y, dark)
                pixel(x + 2, y, warm)
                for column in 0..<3 { pixel(x + column, y + 1, dark) }
                pixel(x, y + 2, warm)
                pixel(x + 1, y + 2, dark)
                pixel(x + 1, y, (249, 225, 177))
            }
        }
    }

    private func drawCarriedBall(into pixels: inout [UInt8], x: Int, y: Int) {
        func rect(_ left: Int, _ top: Int, _ width: Int, _ height: Int,
                  _ color: (UInt8, UInt8, UInt8)) {
            for py in top..<(top + height) { for px in left..<(left + width) {
                guard px >= 0 && px < 64 && py >= 0 && py < 64 else { continue }
                let i = (py * 64 + px) * 4
                pixels[i] = color.0; pixels[i + 1] = color.1; pixels[i + 2] = color.2; pixels[i + 3] = 255
            } }
        }
        rect(x - 3, y - 4, 6, 8, (77, 14, 6))
        rect(x - 4, y - 3, 8, 6, (77, 14, 6))
        rect(x - 2, y - 3, 4, 6, (240, 31, 14))
        rect(x - 3, y - 2, 6, 4, (240, 31, 14))
        rect(x - 2, y - 2, 2, 2, (255, 122, 64))
    }

    private func drawStick(into pixels: inout [UInt8]) {
        func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            for py in y..<(y + height) { for px in x..<(x + width) {
                let i = (py * 64 + px) * 4
                pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = 255
            } }
        }
        // Her selected source art has its mouth around (25, 46).
        rect(12, 46, 25, 3, 72, 37, 15)
        rect(13, 46, 23, 1, 171, 108, 47)
        rect(13, 47, 23, 1, 132, 77, 30)
        rect(17, 43, 2, 4, 72, 37, 15)
        rect(18, 44, 1, 3, 171, 108, 47)
        rect(33, 48, 2, 3, 72, 37, 15)
    }
    private func pixelRect(_ c: CGContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double,
                           _ color: (CGFloat, CGFloat, CGFloat)) {
        c.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
        c.fill(CGRect(x: x, y: 64 - y - h, width: w, height: h))
    }
    private func ball(on c: CGContext, x: Double, y: Double) {
        pixelRect(c, x - 3, y - 4, 6, 8, (0.30, 0.055, 0.025))
        pixelRect(c, x - 4, y - 3, 8, 6, (0.30, 0.055, 0.025))
        pixelRect(c, x - 2, y - 3, 4, 6, (0.94, 0.12, 0.055))
        pixelRect(c, x - 3, y - 2, 6, 4, (0.94, 0.12, 0.055))
        pixelRect(c, x - 2, y - 2, 2, 2, (1, 0.48, 0.25))
    }
    private func heart(on c: CGContext, time: Double, reduced: Bool) {
        let lift = reduced ? 0 : Int(time * 5) % 9
        let shape = [(0, 0), (1, 0), (3, 0), (4, 0), (-1, 1), (0, 1), (1, 1), (2, 1),
            (3, 1), (4, 1), (5, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (1, 3), (2, 3), (3, 3), (2, 4)]
        for (x, y) in shape { pixelRect(c, Double(30 + x), Double(15 + y - lift), 1, 1, (0.94, 0.27, 0.36)) }
    }
}
