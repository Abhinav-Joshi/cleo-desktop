import Foundation

struct PetPoint: Equatable {
    var x: Double
    var y: Double
}

/// The rectangle contains valid panel origins, rather than the panel's outer edges.
struct PetBounds: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double
}

enum PetMood: String, CaseIterable {
    case idle, wag, walk, stick, run, catchBall, sleep, pet, sleepy, circleSleep, settleSleep, bark, sleepGreeting, listen
}

enum CarriedToy: String {
    case none, stick, ball
}

enum BallTimeline {
    static let duration: TimeInterval = 3.8
    static let approachStart: TimeInterval = 0.35
    static let approachEnd: TimeInterval = 1.2
    static let catchTime: TimeInterval = 1.6
    static let landed: TimeInterval = 2.2
}

/// A small, clock-driven state machine. It owns no timers, windows, or input hooks.
final class CleoBehavior {
    private(set) var mood: PetMood
    private(set) var position: PetPoint
    private(set) var facingLeft = false
    private(set) var animationTime: Double = 0
    private(set) var sleepCircleProgress: Double = 0
    private(set) var carriedToy: CarriedToy = .none
    private(set) var ballProgress: Double = 0
    private(set) var isDictating = false
    var ballDestination: PetPoint { ballTarget }
    var home: PetPoint

    private var bounds: PetBounds
    private var lastTick: TimeInterval
    private var stateEnds: TimeInterval = .infinity
    private var nextActivity: TimeInterval = .infinity
    private var chaseBegan: TimeInterval = 0
    private var nextEscapeTarget: TimeInterval = 0
    private var greetingBegan: TimeInterval = 0
    private var interruptedActivity: InterruptedActivity?
    private struct InterruptedActivity {
        var mood: PetMood
        var facingLeft: Bool
        var animationTime: Double
        var stateEnds: TimeInterval
        var nextActivity: TimeInterval
        var chaseBegan: TimeInterval
        var nextEscapeTarget: TimeInterval
        var destination: PetPoint?
        var returningHome: Bool
        var restAfterReturn: PetMood?
        var manualSleep: Bool
        var sleepCircleProgress: Double
        var circleCenter: PetPoint
        var circleRadius: PetPoint
        var circleStartAngle: Double
        var carriedToy: CarriedToy
        var ballProgress: Double
        var ballStart: PetPoint
        var ballTarget: PetPoint
        var geometryChanged = false
    }
    private var destination: PetPoint?
    private var returningHome = false
    private var restAfterReturn: PetMood?
    private var isEvening: Bool
    private var isReducedMotion = false
    private var manualSleep = false
    private var randomState: UInt64
    private var sleepCircleCenter = PetPoint(x: 0, y: 0)
    private var sleepCircleRadius = PetPoint(x: 8, y: 5)
    private var sleepCircleStartAngle: Double = 0
    private var ballStart = PetPoint(x: 0, y: 0)
    private var ballTarget = PetPoint(x: 0, y: 0)

    init(bounds: PetBounds, home: PetPoint, now: TimeInterval, evening: Bool,
         seed: UInt64 = 0xC1E0_6D0D_1E) {
        let safeBounds = Self.normalized(bounds)
        self.bounds = safeBounds
        self.home = Self.clamped(home, to: safeBounds)
        self.position = self.home
        self.lastTick = now.isFinite ? now : 0
        self.isEvening = evening
        self.mood = evening ? .sleep : .idle
        self.randomState = seed == 0 ? 1 : seed
        enterRest(now: self.lastTick)
    }

    /// A small visible idle loop keeps Cleo expressive without a display-rate render loop.
    var suggestedTickInterval: TimeInterval {
        if returningHome { return carriedToy == .ball ? 1.0 / 24.0 : 1.0 / 18.0 }
        switch mood {
        case .idle: return isReducedMotion ? max(1, nextActivity - lastTick) : 1.0 / 12.0
        case .sleep: return 0.75
        case .sleepy: return 0.5
        case .bark, .sleepGreeting: return 1.0 / 18.0
        case .listen: return isReducedMotion ? 0.2 : 1.0 / 18.0
        case .catchBall: return isReducedMotion ? 0.25 : 1.0 / 24.0
        default: return isReducedMotion ? 0.25 : 1.0 / 18.0
        }
    }

    func tick(now: TimeInterval, mouse: PetPoint?, evening: Bool, reducedMotion: Bool) {
        guard now.isFinite else { return }
        let now = max(now, lastTick)
        // A suspended laptop must not cause a single enormous movement step on wake.
        let clockDelta = max(0, now - lastTick)
        var elapsed = min(clockDelta, 0.25)
        lastTick = now
        animationTime += min(clockDelta, 1)
        home = Self.clamped(home, to: bounds)
        position = Self.clamped(position, to: bounds)
        var resumedFromGreeting = false

        if mood == .bark || mood == .sleepGreeting {
            guard now >= stateEnds else { return }
            if resumeInterruptedActivity(now: now) {
                // The interrupted movement resumes on its next frame, from this exact spot.
                elapsed = 0
                resumedFromGreeting = true
            } else {
                finishActivity(now: now)
            }
        }

        let motionChanged = reducedMotion != isReducedMotion
        isReducedMotion = reducedMotion
        // Listening keeps the current pose. Evening and Reduce Motion apply once it ends.
        if !isDictating {
            if evening != isEvening {
                isEvening = evening
                manualSleep = false
                restAfterReturn = nil
                if reducedMotion || distance(position, home) < 1 {
                    enterRest(now: now)
                } else {
                    beginReturn(now: now)
                }
            }

            if reducedMotion {
                returningHome = false
                destination = nil
                restAfterReturn = nil
                if mood == .circleSleep || mood == .settleSleep {
                    position = home
                    enterRest(now: now, preferred: .sleep)
                }
                if mood == .walk || mood == .run || mood == .catchBall {
                    carriedToy = .none
                    setMood(isEvening ? .sleepy : .wag, now: now, duration: 4)
                }
            } else if motionChanged && distance(position, home) > 1 {
                beginReturn(now: now)
            }
        }

        if returningHome {
            move(toward: home, speed: 74, elapsed: elapsed)
            if distance(position, home) < 0.75 {
                position = home
                let requestedRest = restAfterReturn
                restAfterReturn = nil
                enterRest(now: now, preferred: requestedRest)
            }
            return
        }

        if now >= stateEnds {
            switch mood {
            case .walk, .stick, .run, .catchBall, .pet, .wag, .bark, .sleepGreeting:
                finishActivity(now: now)
            case .sleep:
                setMood(.sleepy, now: now, duration: random(7, 14))
            case .sleepy:
                enterRest(now: now)
            case .circleSleep:
                position = home
                sleepCircleProgress = 1
                setMood(.settleSleep, now: now, duration: 0.9)
            case .settleSleep:
                enterRest(now: now, preferred: .sleep)
            case .idle, .listen:
                break
            }
        }

        if returningHome {
            move(toward: home, speed: 74, elapsed: elapsed)
            return
        }

        if !reducedMotion && !resumedFromGreeting {
            switch mood {
            case .circleSleep:
                updateSleepCircle()
            case .run:
                playKeepAway(now: now, mouse: valid(mouse), elapsed: elapsed)
            case .stick:
                // Offer the stick in place, watching the person rather than strolling away.
                destination = nil
                if let mouse = valid(mouse) {
                    facingLeft = mouse.x < position.x
                    if distance(position, mouse) < 125 {
                        beginKeepAway(now: now, mouse: mouse)
                        playKeepAway(now: now, mouse: mouse, elapsed: elapsed)
                    }
                }
            case .catchBall:
                updateBallSequence()
            case .walk:
                if let target = destination {
                    move(toward: target, speed: 42, elapsed: elapsed)
                }
            default:
                break
            }
        }
        if (mood == .stick || mood == .run), let mouse = valid(mouse) {
            // Scooting backward must never make her turn her back on the game.
            facingLeft = mouse.x < position.x
        }

        if mood == .idle && now >= nextActivity {
            if reducedMotion {
                setMood(.wag, now: now, duration: 4)
            } else {
                let choice = random(0, 1)
                if choice < 0.55 { startActivity(.wag, now: now) }
                else if choice < 0.78 { startActivity(.walk, now: now) }
                else if choice < 0.95 { startActivity(.stick, now: now) }
                else { startActivity(.catchBall, now: now) }
            }
        }
    }

    /// The view calls this once for each genuine pointer entry, including a fresh re-entry.
    @discardableResult
    func hovered(now: TimeInterval) -> Bool {
        guard now.isFinite, !isDictating else { return false }
        let underlyingMood = interruptedActivity?.mood ?? mood
        let restingAtHome = (underlyingMood == .idle || underlyingMood == .wag) && distance(position, home) <= 2
        let sleepyGreeting = underlyingMood == .sleep || underlyingMood == .sleepy
        // Play, petting, and the bedtime routine continue without a hover interruption.
        guard restingAtHome || sleepyGreeting else { return false }
        let now = max(now, lastTick)
        if mood != .bark && mood != .sleepGreeting {
            interruptedActivity = InterruptedActivity(
                mood: mood, facingLeft: facingLeft, animationTime: animationTime,
                stateEnds: stateEnds, nextActivity: nextActivity, chaseBegan: chaseBegan,
                nextEscapeTarget: nextEscapeTarget, destination: destination,
                returningHome: returningHome, restAfterReturn: restAfterReturn,
                manualSleep: manualSleep, sleepCircleProgress: sleepCircleProgress,
                circleCenter: sleepCircleCenter, circleRadius: sleepCircleRadius,
                circleStartAngle: sleepCircleStartAngle, carriedToy: carriedToy,
                ballProgress: ballProgress, ballStart: ballStart, ballTarget: ballTarget)
            greetingBegan = now
        }
        lastTick = now
        returningHome = false
        destination = nil
        setMood(sleepyGreeting ? .sleepGreeting : .bark, now: now, duration: sleepyGreeting ? 2.4 : 0.95)
        return true
    }

    /// Holds a listening pose without walking. The activity underneath resumes afterward.
    @discardableResult
    func beginDictation(now: TimeInterval) -> Bool {
        guard now.isFinite, !isDictating else { return false }
        let now = max(now, lastTick)
        lastTick = now
        if interruptedActivity == nil {
            interruptedActivity = InterruptedActivity(
                mood: mood, facingLeft: facingLeft, animationTime: animationTime,
                stateEnds: stateEnds, nextActivity: nextActivity, chaseBegan: chaseBegan,
                nextEscapeTarget: nextEscapeTarget, destination: destination,
                returningHome: returningHome, restAfterReturn: restAfterReturn,
                manualSleep: manualSleep, sleepCircleProgress: sleepCircleProgress,
                circleCenter: sleepCircleCenter, circleRadius: sleepCircleRadius,
                circleStartAngle: sleepCircleStartAngle, carriedToy: carriedToy,
                ballProgress: ballProgress, ballStart: ballStart, ballTarget: ballTarget)
            greetingBegan = now
        }
        isDictating = true
        returningHome = false
        destination = nil
        setMood(.listen, now: now, duration: .infinity)
        return true
    }

    /// A successful listen plays one existing bark, then the saved activity continues.
    func endDictation(now: TimeInterval, acknowledged: Bool) {
        guard now.isFinite, isDictating else { return }
        let now = max(now, lastTick)
        lastTick = now
        isDictating = false
        if acknowledged {
            setMood(.bark, now: now, duration: 0.95)
            return
        }
        if !resumeInterruptedActivity(now: now) { finishActivity(now: now) }
    }

    /// Drops the listening pose and the saved activity. The caller chooses the next mood.
    func cancelDictation() {
        guard isDictating else { return }
        isDictating = false
        interruptedActivity = nil
    }

    private func resumeInterruptedActivity(now: TimeInterval) -> Bool {
        guard let saved = interruptedActivity else { return false }
        interruptedActivity = nil
        let pausedFor = max(0, now - greetingBegan)
        mood = saved.mood
        facingLeft = saved.facingLeft
        animationTime = saved.animationTime
        stateEnds = saved.stateEnds + pausedFor
        nextActivity = saved.nextActivity + pausedFor
        chaseBegan = saved.chaseBegan + pausedFor
        nextEscapeTarget = saved.nextEscapeTarget + pausedFor
        destination = saved.destination.map { Self.clamped($0, to: bounds) }
        returningHome = saved.returningHome
        restAfterReturn = saved.restAfterReturn
        manualSleep = saved.manualSleep
        sleepCircleProgress = saved.sleepCircleProgress
        sleepCircleCenter = saved.circleCenter
        sleepCircleRadius = saved.circleRadius
        sleepCircleStartAngle = saved.circleStartAngle
        carriedToy = saved.carriedToy
        ballProgress = saved.ballProgress
        ballStart = Self.clamped(saved.ballStart, to: bounds)
        ballTarget = Self.clamped(saved.ballTarget, to: bounds)
        if mood == .settleSleep || (saved.geometryChanged && mood == .circleSleep) {
            position = home
            enterRest(now: now, preferred: .sleep)
        }
        return true
    }

    /// Mouse coordinates use the same origin coordinate space as `position`.
    func clicked(now: TimeInterval, mouse: PetPoint) {
        guard now.isFinite, !isDictating else { return }
        let now = max(now, lastTick)
        lastTick = now
        interruptedActivity = nil
        manualSleep = false
        restAfterReturn = nil
        if mood == .pet {
            // A continuous stroke extends affection without restarting the wag/heart frames.
            stateEnds = now + 3.2
            return
        }
        if !isReducedMotion && (mood == .stick || (mood == .walk && carriedToy == .stick)) {
            beginKeepAway(now: now, mouse: valid(mouse))
        } else if !isReducedMotion && mood == .run && now < stateEnds {
            // Repeated clicks can extend play briefly, but can never trap Cleo in a chase.
            stateEnds = min(chaseBegan + 12, max(stateEnds, now + 3))
            destination = escapeTarget(from: valid(mouse))
            if let mouse = valid(mouse) { facingLeft = mouse.x < position.x }
        } else {
            returningHome = false
            destination = nil
            carriedToy = .none
            setMood(.pet, now: now, duration: 3.2)
        }
    }

    func request(_ requestedMood: PetMood, now: TimeInterval) {
        guard now.isFinite else { return }
        let now = max(now, lastTick)
        lastTick = now
        if isDictating { cancelDictation() }
        interruptedActivity = nil
        manualSleep = requestedMood == .sleep || requestedMood == .circleSleep || requestedMood == .settleSleep
        if manualSleep && (mood == .circleSleep || mood == .settleSleep) { return }
        restAfterReturn = nil
        returningHome = false
        destination = nil
        switch requestedMood {
        case .idle, .sleep, .circleSleep, .settleSleep:
            // "Back to corner" follows the time of day, including after the walk home.
            let restingMood: PetMood = requestedMood == .idle && !isEvening ? .idle : .sleep
            if !isReducedMotion && distance(position, home) > 1 {
                restAfterReturn = restingMood
                beginReturn(now: now)
            } else {
                enterRest(now: now, preferred: restingMood)
            }
        case .run:
            if isReducedMotion { startActivity(.wag, now: now) }
            else { beginKeepAway(now: now, mouse: nil) }
        case .walk, .catchBall:
            startActivity(isReducedMotion ? .wag : requestedMood, now: now)
        case .wag, .stick, .pet, .sleepy, .bark, .sleepGreeting:
            startActivity(requestedMood, now: now)
        case .listen:
            beginDictation(now: now)
        }
    }

    func updateBounds(_ bounds: PetBounds, home: PetPoint, now: TimeInterval) {
        let wasHome = distance(position, self.home) < 2
        let wasSettling = mood == .circleSleep || mood == .settleSleep
        let wasCatching = mood == .catchBall
        self.bounds = Self.normalized(bounds)
        self.home = Self.clamped(home, to: self.bounds)
        position = Self.clamped(position, to: self.bounds)
        destination = nil
        nextEscapeTarget = 0
        if mood == .bark || mood == .sleepGreeting || mood == .listen {
            if wasHome || isReducedMotion { position = self.home }
            interruptedActivity?.geometryChanged = true
            return
        }
        if wasCatching {
            let safeNow = now.isFinite ? max(now, lastTick) : lastTick
            if wasHome || distance(position, self.home) < 1 {
                position = self.home
                enterRest(now: safeNow)
            } else {
                // A changed display cancels the trajectory, retaining a ball only if caught.
                beginReturn(now: safeNow)
            }
        } else if wasSettling {
            position = self.home
            enterRest(now: now.isFinite ? max(now, lastTick) : lastTick, preferred: .sleep)
        } else if wasHome || isReducedMotion {
            position = self.home
        } else if now.isFinite {
            beginReturn(now: max(now, lastTick))
        }
    }

    private func startActivity(_ activity: PetMood, now: TimeInterval) {
        returningHome = false
        destination = nil
        carriedToy = activity == .stick ? .stick : .none
        ballProgress = 0
        let duration: Double
        switch activity {
        case .wag: duration = 4.5
        case .walk: duration = 5.5
        case .stick: duration = 10
        case .catchBall: duration = BallTimeline.duration
        case .pet: duration = 3.2
        case .sleepy: duration = 12
        case .bark: duration = 0.95
        case .sleepGreeting: duration = 2.4
        default: duration = 5
        }
        setMood(activity, now: now, duration: duration)
        if activity == .catchBall {
            ballStart = position
            ballTarget = nearbyTarget(radius: 80, from: position)
            if abs(ballTarget.x - position.x) > 0.1 { facingLeft = ballTarget.x < position.x }
        } else if !isReducedMotion && activity == .walk {
            destination = nearbyTarget(radius: 150)
        }
    }

    private func updateBallSequence() {
        let time = min(BallTimeline.duration, animationTime)
        ballProgress = min(1, time / BallTimeline.duration)
        if time >= BallTimeline.approachStart {
            let progress = smooth((time - BallTimeline.approachStart) /
                                  (BallTimeline.approachEnd - BallTimeline.approachStart))
            position = Self.clamped(interpolate(ballStart, ballTarget, progress), to: bounds)
        }
        if time >= BallTimeline.catchTime { carriedToy = .ball }
    }

    private func finishActivity(now: TimeInterval) {
        if !isReducedMotion && distance(position, home) > 1 { beginReturn(now: now) }
        else { enterRest(now: now) }
    }

    private func beginReturn(now: TimeInterval) {
        returningHome = true
        destination = nil
        setMood(.walk, now: now, duration: .infinity)
    }

    private func enterRest(now: TimeInterval, preferred: PetMood? = nil) {
        returningHome = false
        destination = nil
        carriedToy = .none
        ballProgress = 0
        let restingMood = preferred ?? ((isEvening || manualSleep) ? .sleep : .idle)
        let wasAlreadySleepy = mood == .sleep || mood == .sleepy || mood == .circleSleep || mood == .settleSleep || mood == .sleepGreeting
        if restingMood == .sleep && !wasAlreadySleepy && !isReducedMotion && beginSleepCircle(now: now) {
            nextActivity = .infinity
            return
        }
        setMood(restingMood, now: now, duration: restingMood == .sleep && !manualSleep ? random(110, 240) : .infinity)
        nextActivity = restingMood == .idle && !isEvening ? now + random(65, 145) : .infinity
    }

    private func setMood(_ mood: PetMood, now: TimeInterval, duration: TimeInterval) {
        self.mood = mood
        animationTime = 0
        if mood != .catchBall { ballProgress = mood == .walk && carriedToy == .ball ? 1 : 0 }
        if mood != .circleSleep && mood != .settleSleep { sleepCircleProgress = 0 }
        stateEnds = duration.isFinite ? now + duration : .infinity
    }

    private func beginSleepCircle(now: TimeInterval) -> Bool {
        let radiusX = min(8, (bounds.maxX - bounds.minX) * 0.5)
        let radiusY = min(5, (bounds.maxY - bounds.minY) * 0.5)
        guard radiusX >= 3, radiusY >= 2 else { return false }
        sleepCircleRadius = PetPoint(x: radiusX, y: radiusY)
        // The whole ellipse fits inside the origin bounds, even at a screen corner.
        sleepCircleCenter = PetPoint(x: min(bounds.maxX - radiusX, max(bounds.minX + radiusX, home.x)),
                                     y: min(bounds.maxY - radiusY, max(bounds.minY + radiusY, home.y)))
        sleepCircleStartAngle = atan2((home.y - sleepCircleCenter.y) / radiusY,
                                      (home.x - sleepCircleCenter.x) / radiusX)
        sleepCircleProgress = 0
        setMood(.circleSleep, now: now, duration: 3.2)
        return true
    }

    private func updateSleepCircle() {
        let time = min(3.2, animationTime)
        sleepCircleProgress = min(1, time / 3.2)
        let start = PetPoint(x: sleepCircleCenter.x + cos(sleepCircleStartAngle) * sleepCircleRadius.x,
                             y: sleepCircleCenter.y + sin(sleepCircleStartAngle) * sleepCircleRadius.y)
        let next: PetPoint
        if time < 0.2 {
            next = interpolate(home, start, smooth(time / 0.2))
        } else if time < 3 {
            let angle = sleepCircleStartAngle + Double.pi * 2 * smooth((time - 0.2) / 2.8)
            next = PetPoint(x: sleepCircleCenter.x + cos(angle) * sleepCircleRadius.x,
                            y: sleepCircleCenter.y + sin(angle) * sleepCircleRadius.y)
        } else {
            next = interpolate(start, home, smooth((time - 3) / 0.2))
        }
        let tangentX = next.x - position.x
        if abs(tangentX) > 0.001 { facingLeft = tangentX < 0 }
        position = Self.clamped(next, to: bounds)
    }

    private func smooth(_ fraction: Double) -> Double {
        let value = min(1, max(0, fraction))
        return value * value * (3 - 2 * value)
    }

    private func interpolate(_ from: PetPoint, _ to: PetPoint, _ fraction: Double) -> PetPoint {
        PetPoint(x: from.x + (to.x - from.x) * fraction, y: from.y + (to.y - from.y) * fraction)
    }

    private func nearbyTarget(radius: Double, from origin: PetPoint? = nil) -> PetPoint {
        let anchor = origin ?? home
        // Reflect choices at the corner, so a corner home still produces a visible stroll.
        let leftRoom = anchor.x - bounds.minX
        let rightRoom = bounds.maxX - anchor.x
        let downRoom = anchor.y - bounds.minY
        let upRoom = bounds.maxY - anchor.y
        let xDirection = rightRoom >= leftRoom ? 1.0 : -1.0
        let yDirection = upRoom >= downRoom ? 1.0 : -1.0
        return Self.clamped(PetPoint(x: anchor.x + xDirection * random(radius * 0.45, radius),
                                    y: anchor.y + yDirection * random(0, radius * 0.24)), to: bounds)
    }

    private func beginKeepAway(now: TimeInterval, mouse: PetPoint?) {
        returningHome = false
        carriedToy = .stick
        chaseBegan = now
        setMood(.run, now: now, duration: 8)
        destination = mouse.map { escapeTarget(from: $0) }
        nextEscapeTarget = now + 0.18
        if let mouse { facingLeft = mouse.x < position.x }
    }

    private func playKeepAway(now: TimeInterval, mouse: PetPoint?, elapsed: Double) {
        guard let mouse else { destination = nil; return }
        let gap = distance(position, mouse)
        // Once safely out of reach she stays in her bow; a distant cursor never lures her away.
        if gap > 165 {
            destination = nil
            return
        }
        if gap < 123 || (destination != nil && now >= nextEscapeTarget) {
            destination = escapeTarget(from: mouse)
            nextEscapeTarget = now + 0.18
        }
        guard let target = destination else { return }
        let remaining = distance(position, target)
        if remaining < 5 {
            destination = nil
            return
        }
        // A spring softens each short scoot; the dead zone prevents constant chasing/jitter.
        move(toward: target, speed: min(190, max(28, remaining * 6)), elapsed: elapsed)
        facingLeft = mouse.x < position.x
    }

    private func escapeTarget(from mouse: PetPoint?) -> PetPoint {
        guard let mouse, distance(position, mouse) < 180 else { return position }
        let radius = 148 + sin(animationTime * 2.4) * 6
        let dx = position.x - mouse.x
        let dy = position.y - mouse.y
        let baseAngle: Double
        if hypot(dx, dy) > 1 {
            baseAngle = atan2(dy, dx)
        } else {
            // If the cursor is directly over her, hop toward available space nearby.
            baseAngle = atan2((bounds.minY + bounds.maxY) * 0.5 - position.y,
                              (bounds.minX + bounds.maxX) * 0.5 - position.x)
        }
        let playfulAngle = baseAngle + sin(animationTime * 3.1) * 0.2
        var best = position
        var bestScore = -Double.infinity
        // Short ring candidates let her sidestep along an edge without dashing to a corner.
        for index in 0..<16 {
            let offset = Double(index) * Double.pi / 8
            let angle = playfulAngle + offset
            let candidate = Self.clamped(PetPoint(x: mouse.x + cos(angle) * radius,
                                                  y: mouse.y + sin(angle) * radius), to: bounds)
            let score = -abs(distance(candidate, mouse) - radius) * 3
                + cos(offset) * 35 - distance(candidate, position) * 0.1
            if score > bestScore { bestScore = score; best = candidate }
        }
        return best
    }

    private func move(toward target: PetPoint, speed: Double, elapsed: Double) {
        let dx = target.x - position.x
        let dy = target.y - position.y
        let length = hypot(dx, dy)
        guard length > 0.001, elapsed > 0 else { return }
        let fraction = min(1, speed * elapsed / length)
        if abs(dx) > 0.1 { facingLeft = dx < 0 }
        position = Self.clamped(PetPoint(x: position.x + dx * fraction,
                                        y: position.y + dy * fraction), to: bounds)
    }

    private func distance(_ a: PetPoint, _ b: PetPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func valid(_ point: PetPoint?) -> PetPoint? {
        guard let point, point.x.isFinite, point.y.isFinite else { return nil }
        return point
    }

    private static func clamped(_ point: PetPoint, to bounds: PetBounds) -> PetPoint {
        PetPoint(x: min(bounds.maxX, max(bounds.minX, point.x.isFinite ? point.x : bounds.minX)),
                 y: min(bounds.maxY, max(bounds.minY, point.y.isFinite ? point.y : bounds.minY)))
    }

    private static func normalized(_ bounds: PetBounds) -> PetBounds {
        let x1 = bounds.minX.isFinite ? bounds.minX : 0
        let x2 = bounds.maxX.isFinite ? bounds.maxX : x1
        let y1 = bounds.minY.isFinite ? bounds.minY : 0
        let y2 = bounds.maxY.isFinite ? bounds.maxY : y1
        return PetBounds(minX: min(x1, x2), minY: min(y1, y2),
                         maxX: max(x1, x2), maxY: max(y1, y2))
    }

    private func random(_ lower: Double, _ upper: Double) -> Double {
        // xorshift64*: deterministic, allocation-free, and independent of global RNG state.
        randomState ^= randomState >> 12
        randomState ^= randomState << 25
        randomState ^= randomState >> 27
        let bits = (randomState &* 2_685_821_657_736_338_717) >> 11
        return lower + (upper - lower) * (Double(bits) / 9_007_199_254_740_992)
    }
}
