import AppKit
import ImageIO
import UniformTypeIdentifiers
import QuartzCore
import Darwin

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

enum Corner: Int, CaseIterable {
    case bottomRight, bottomLeft, topRight, topLeft
    var title: String { ["Bottom right", "Bottom left", "Top right", "Top left"][rawValue] }
}

@main
struct CleoMain {
    static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--command"), CommandLine.arguments.indices.contains(index + 1) {
            // A tiny local control channel drives the already-running app, with no UI takeover.
            DistributedNotificationCenter.default().postNotificationName(
                Notification.Name("local.cleo.companion.command"), object: CommandLine.arguments[index + 1],
                userInfo: nil, deliverImmediately: true)
            return
        }
        if CommandLine.arguments.contains("--self-check") {
            exit(cleoSelfCheck() ? 0 : 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--print-grok-url"), CommandLine.arguments.indices.contains(index + 1) {
            if let url = GrokBotLink.promptURL(for: CommandLine.arguments[index + 1]) {
                print(url.absoluteString)
                exit(0)
            }
            fputs("unusable\n", stderr)
            exit(1)
        }
        if CommandLine.arguments.contains("--speech-capability") {
            print(OnDeviceSpeechListener.capabilityLine())
            exit(OnDeviceSpeechListener.recognizerAvailable ? 0 : 1)
        }
        if CommandLine.arguments.contains("--send-plan") {
            print(GrokBotSend.planLine())
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = CleoApp()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class CleoApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: PetPanel!
    private var sprite: SpriteView!
    private var ballPanel: PetPanel!
    private var ballView: ThrownBallView!
    private var ballLaunch: NSPoint?
    private var ballControl: NSPoint?
    private var lastBallFlightProgress: Double = -1
    private var behavior: CleoBehavior!
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var snoozeTimer: Timer?
    private var visible = true
    private var paused = false
    private var suspended = Set<String>()
    private var selectedScreen: NSScreen?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var nextMoodBoundary: Date?
    private var commandObserver: NSObjectProtocol?
    private var recordingTimer: Timer?
    private let speech = OnDeviceSpeechListener()
    private let hotKey = TalkHotKey()
    private let providers: [AgentProvider] = [GrokBotProvider()]
    private var handoffNote: String?
    private var captureStarted = false
    private var permissionPromptOpen = false
    private var holdOwnsCapture = false
    private var pendingSend: DispatchWorkItem?
    private var pendingWords: String?
    private var activeProvider: AgentProvider {
        let saved = defaults.string(forKey: "agentProvider")
        return providers.first { $0.identifier == saved } ?? providers[0]
    }
    private var hoverEntryConsumed = false
    private var lastHoverMouseLocation: NSPoint?
    private var hoverBarkCount = 0
    private var hoverSleepGreetingCount = 0
    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var corner: Corner { Corner(rawValue: defaults.integer(forKey: "corner")) ?? .bottomRight }
    private var panelSide: CGFloat { CGFloat([136, 200, 264][max(0, min(2, defaults.integer(forKey: "size")))]) }
    private var reducedMotion: Bool { defaults.bool(forKey: "gentle") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    private var bedtime: Int {
        defaults.object(forKey: "bedtime") == nil ? 20 : defaults.integer(forKey: "bedtime")
    }
    private var isEvening: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= bedtime || hour < 7
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Never activate, become key, or send input to any app.
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: panelSide, height: panelSide),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Cleo"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        sprite = SpriteView(frame: NSRect(origin: .zero, size: panel.frame.size))
        guard sprite.frames.count == 16 && sprite.turnFrameCount == 16 && sprite.barkFrameCount == 16 else {
            fputs("Cleo needs her main, bedtime, and bark sprite resources. Rebuild with scripts/build.sh.\n", stderr)
            NSApp.terminate(nil)
            return
        }
        panel.contentView = sprite
        ballPanel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        ballPanel.title = "Cleo’s ball"
        ballPanel.isOpaque = false
        ballPanel.backgroundColor = .clear
        ballPanel.hasShadow = false
        ballPanel.level = panel.level
        ballPanel.hidesOnDeactivate = false
        ballPanel.isReleasedWhenClosed = false
        ballPanel.ignoresMouseEvents = true
        ballPanel.collectionBehavior = panel.collectionBehavior
        ballView = ThrownBallView(frame: NSRect(origin: .zero, size: ballPanel.frame.size))
        ballPanel.contentView = ballView
        sprite.autoresizingMask = [.width, .height]
        sprite.onPet = { [weak self] in self?.petCleo() }
        sprite.onHover = { [weak self] in self?.checkHover() }
        sprite.onHoldBegan = { [weak self] in self?.holdToTalkBegan() }
        sprite.onHoldEnded = { [weak self] in self?.holdToTalkEnded() }
        hotKey.onPressed = { [weak self] in self?.toggleTalking() }
        hotKey.install()
        sprite.companionMenu = menu
        let geometry = screenGeometry()
        behavior = CleoBehavior(bounds: geometry.0, home: geometry.1, now: now, evening: isEvening,
                                seed: UInt64.random(in: 1...UInt64.max))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Cleo companion")
        statusItem.button?.toolTip = "Cleo — your little desktop doodle"
        statusItem.menu = menu
        menu.delegate = self
        installObservers()
        updateFrame()
        panel.orderFrontRegardless()
        scheduleTimer()
        writeDiagnosticsIfRequested()
    }

    private func screenGeometry() -> (PetBounds, PetPoint) {
        let screens = NSScreen.screens
        let saved = defaults.object(forKey: "display") as? Int
        let screen = screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? Int) == saved }
            ?? selectedScreen.flatMap { candidate in screens.first { $0 == candidate } }
            ?? screens.first
        selectedScreen = screen
        let rect = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1024, height: 768)
        let minX = rect.minX + 12, minY = rect.minY + 10
        let maxX = max(minX, rect.maxX - panelSide - 12)
        let maxY = max(minY, rect.maxY - panelSide - 10)
        let x: CGFloat = [.bottomRight, .topRight].contains(corner) ? maxX : minX
        let y: CGFloat = [.topRight, .topLeft].contains(corner) ? maxY : minY
        return (PetBounds(minX: minX, minY: minY, maxX: maxX, maxY: maxY), PetPoint(x: x, y: y))
    }

    private func updateFrame() {
        let point = behavior.position
        let ballMotion = behavior.mood == .catchBall || (behavior.mood == .walk && behavior.carriedToy == .ball)
        let scale = ballMotion ? max(1, panel.screen?.backingScaleFactor ?? selectedScreen?.backingScaleFactor ?? 1) : 1
        let origin = NSPoint(x: (point.x * scale).rounded() / scale, y: (point.y * scale).rounded() / scale)
        if panel.frame.origin != origin {
            panel.setFrameOrigin(origin)
        }
        let resting = [.idle, .wag, .pet, .bark, .listen, .sleep, .sleepy, .sleepGreeting, .settleSleep, .circleSleep].contains(behavior.mood)
        let pointer = [.stick, .run].contains(behavior.mood) ? NSEvent.mouseLocation : NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let gaze = CGPoint(x: max(-1, min(1, (pointer.x - panel.frame.midX) / 160)),
                           y: max(-1, min(1, (pointer.y - panel.frame.midY) / 160)))
        sprite.render(mood: behavior.mood, time: behavior.animationTime,
                      facingLeft: resting ? true : behavior.facingLeft, reducedMotion: reducedMotion, gaze: gaze,
                      carriedToy: behavior.carriedToy, ballProgress: behavior.ballProgress)
        updateThrownBall()
    }

    private func hideThrownBall(reset: Bool = false) {
        if ballPanel?.isVisible == true { ballPanel.orderOut(nil) }
        if reset { ballLaunch = nil; ballControl = nil; lastBallFlightProgress = -1 }
    }

    private func updateThrownBall() {
        let time = behavior.ballProgress * BallTimeline.duration
        guard behavior.mood == .catchBall, behavior.carriedToy == .none,
              time < BallTimeline.catchTime else { hideThrownBall(reset: true); return }
        guard visible, !paused, suspended.isEmpty, panel.isVisible,
              let mouth = sprite.ballMouthPointOnScreen else { hideThrownBall(); return }
        let scale = max(1, panel.screen?.backingScaleFactor ?? selectedScreen?.backingScaleFactor ?? 1)
        let diameter = (sprite.thrownBallDiameter * scale).rounded() / scale
        let side = diameter + 4
        let display = selectedScreen?.visibleFrame ?? panel.screen?.visibleFrame ?? panel.frame.insetBy(dx: -300, dy: -200)
        let safe = display.insetBy(dx: diameter / 2 + 8, dy: diameter / 2 + 8)
        func clamp(_ point: NSPoint) -> NSPoint {
            NSPoint(x: min(safe.maxX, max(safe.minX, point.x)), y: min(safe.maxY, max(safe.minY, point.y)))
        }
        let progress = max(0, min(1, time / BallTimeline.catchTime))
        if ballLaunch == nil || progress < lastBallFlightProgress {
            let direction: CGFloat = behavior.facingLeft ? -1 : 1
            let room = direction < 0 ? mouth.x - safe.minX : safe.maxX - mouth.x
            let span = min(220, max(0, room))
            let headroom = max(0, safe.maxY - mouth.y)
            let start = clamp(NSPoint(x: mouth.x + direction * span, y: mouth.y + min(50, headroom * 0.25)))
            let target = clamp(NSPoint(x: mouth.x + behavior.ballDestination.x - behavior.position.x,
                                      y: mouth.y + behavior.ballDestination.y - behavior.position.y))
            ballLaunch = start
            ballControl = clamp(NSPoint(x: (start.x + target.x) / 2,
                                        y: max(start.y, target.y) + 150))
        }
        lastBallFlightProgress = progress
        guard let start = ballLaunch, let control = ballControl else { return }
        let remaining = 1 - progress
        let center = clamp(NSPoint(x: remaining * remaining * start.x + 2 * remaining * progress * control.x + progress * progress * mouth.x,
                                   y: remaining * remaining * start.y + 2 * remaining * progress * control.y + progress * progress * mouth.y))
        if ballPanel.frame.width != side { ballPanel.setContentSize(NSSize(width: side, height: side)) }
        let origin = NSPoint(x: ((center.x - side / 2) * scale).rounded() / scale,
                             y: ((center.y - side / 2) * scale).rounded() / scale)
        if ballPanel.frame.origin != origin { ballPanel.setFrameOrigin(origin) }
        if !ballPanel.isVisible { ballPanel.orderFrontRegardless() }
    }

    private func mousePoint() -> PetPoint {
        let mouse = NSEvent.mouseLocation
        return PetPoint(x: mouse.x - panel.frame.width / 2, y: mouse.y - panel.frame.height / 2)
    }

    private func tick() {
        guard visible, !paused, suspended.isEmpty else { return }
        checkHover()
        behavior.tick(now: now, mouse: [.stick, .run].contains(behavior.mood) ? mousePoint() : nil,
                      evening: isEvening, reducedMotion: reducedMotion)
        updateFrame()
        scheduleTimer()
    }

    private func checkHover() {
        guard behavior != nil, visible, !paused, suspended.isEmpty, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let local = sprite.convert(panel.convertPoint(fromScreen: mouse), from: nil)
        let pointerMoved = lastHoverMouseLocation.map { hypot(mouse.x - $0.x, mouse.y - $0.y) > 0.25 } ?? true
        lastHoverMouseLocation = mouse
        if hoverEntryConsumed {
            // Re-arm as soon as the person moves off her visible shape. A small
            // margin and actual pointer movement prevent animated fur from
            // turning a held hover into repeated barking.
            guard pointerMoved, !sprite.isNearDog(local) else { return }
            hoverEntryConsumed = false
        }
        guard !hoverEntryConsumed, sprite.containsDog(local),
              NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0) == panel.windowNumber else { return }
        hoverEntryConsumed = true
        guard NSEvent.pressedMouseButtons == 0 else { return }
        if greetCleo() {
            if behavior.mood == .sleepGreeting { hoverSleepGreetingCount += 1 }
            else { hoverBarkCount += 1 }
        }
    }

    @discardableResult
    private func greetCleo() -> Bool {
        if behavior.hovered(now: now) {
            updateFrame()
            scheduleTimer()
            return true
        }
        return false
    }

    private func secondsToMoodBoundary() -> TimeInterval {
        let date = Date()
        if let next = nextMoodBoundary, next > date { return next.timeIntervalSince(date) }
        let calendar = Calendar.current
        let next = [7, bedtime].compactMap { hour in
            calendar.nextDate(after: date, matching: DateComponents(hour: hour, minute: 0, second: 0), matchingPolicy: .nextTime)
        }.min() ?? date.addingTimeInterval(3600)
        nextMoodBoundary = next
        return max(0.1, next.timeIntervalSince(date))
    }

    private func scheduleTimer() {
        guard visible, !paused, suspended.isEmpty else { stopTimer(); return }
        let interval = min(behavior.suggestedTickInterval, secondsToMoodBoundary())
        if timer?.isValid == true && abs(timerInterval - interval) < 0.0001 { return }
        // Reuse the timer during each animation; change cadence only when the mood changes.
        timer?.invalidate()
        timerInterval = interval
        let next = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        next.tolerance = interval < 1 ? interval * (interval < 0.05 ? 0.05 : 0.12) : min(1, interval * 0.1)
        RunLoop.main.add(next, forMode: .common)
        timer = next
    }

    private func stopTimer() { timer?.invalidate(); timer = nil; timerInterval = 0; hideThrownBall() }

    private func petCleo() {
        if paused { return }
        hoverEntryConsumed = true
        // First sample applies Reduce Motion before an immediate user interaction.
        behavior.tick(now: now, mouse: nil, evening: isEvening, reducedMotion: reducedMotion)
        behavior.clicked(now: now, mouse: mousePoint())
        updateFrame()
        scheduleTimer()
    }

    private func request(_ mood: PetMood) {
        cancelOutgoingSend(note: "Didn't send.")
        abandonListening()
        visible = true
        paused = false
        snoozeTimer?.invalidate()
        if mood == .catchBall { hideThrownBall(reset: true) }
        behavior.tick(now: now, mouse: nil, evening: isEvening, reducedMotion: reducedMotion)
        behavior.request(mood, now: now)
        updateFrame()
        if suspended.isEmpty { panel.orderFrontRegardless(); updateThrownBall() }
        scheduleTimer()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func item(_ title: String, action: Selector? = nil, tag: Int = 0, checked: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = tag
        item.state = checked ? .on : .off
        return item
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let labels: [PetMood: String] = [.idle: "Keeping you company", .wag: "Happy to see you", .bark: "A little hello", .listen: "Listening", .walk: "On a tiny adventure", .stick: "Found a very good stick", .run: "You can’t catch me!", .catchBall: "Ball time", .sleep: "Dreaming of tennis balls", .pet: "That’s the spot", .sleepy: "Getting sleepy", .sleepGreeting: "A sleepy hello", .circleSleep: "Finding the perfect sleeping spot", .settleSleep: "Curling up"]
        let title = item("Cleo · \(labels[behavior.mood] ?? "Hanging out")")
        title.isEnabled = false
        menu.addItem(title)
        if pendingWords != nil {
            menu.addItem(item("Cancel send", action: #selector(cancelSend)))
        } else if captureStarted {
            menu.addItem(item("Stop and send to \(activeProvider.displayName)", action: #selector(stopTalking)))
        } else {
            menu.addItem(item("Talk to \(activeProvider.displayName) (⌃⌥Space)", action: #selector(startTalking)))
        }
        if let handoffNote {
            let note = item(handoffNote)
            note.isEnabled = false
            menu.addItem(note)
        }
        menu.addItem(.separator())
        menu.addItem(item(visible ? "Hide Cleo" : "Show Cleo", action: #selector(toggleVisible)))
        menu.addItem(item(paused ? "Resume" : "Pause", action: #selector(togglePause)))
        menu.addItem(item("Snooze for 30 minutes", action: #selector(snooze)))
        menu.addItem(.separator())
        menu.addItem(item("Give her a stick", action: #selector(giveStick)))
        menu.addItem(item("Catch a ball", action: #selector(catchBall)))
        menu.addItem(item("Wag hello", action: #selector(wag)))
        menu.addItem(item("Curl up and sleep", action: #selector(sleep)))
        menu.addItem(item("Back to your corner", action: #selector(goHome)))
        menu.addItem(.separator())
        let corners = NSMenu()
        for option in Corner.allCases { corners.addItem(item(option.title, action: #selector(changeCorner(_:)), tag: option.rawValue, checked: corner == option)) }
        let cornerItem = item("Screen corner"); cornerItem.submenu = corners; menu.addItem(cornerItem)
        let sizes = NSMenu()
        for (index, label) in ["Small · 128 pt", "Medium · 192 pt", "Large · 256 pt"].enumerated() {
            sizes.addItem(item(label, action: #selector(changeSize(_:)), tag: index, checked: defaults.integer(forKey: "size") == index))
        }
        let sizeItem = item("Size"); sizeItem.submenu = sizes; menu.addItem(sizeItem)
        let displays = NSMenu()
        for (index, screen) in NSScreen.screens.enumerated() {
            displays.addItem(item(screen.localizedName, action: #selector(changeDisplay(_:)), tag: index, checked: screen == selectedScreen))
        }
        let displayItem = item("Display"); displayItem.submenu = displays; menu.addItem(displayItem)
        let sleepTimes = NSMenu()
        for hour in 19...22 { sleepTimes.addItem(item("\(hour - 12) p.m. to 7 a.m.", action: #selector(changeBedtime(_:)), tag: hour, checked: hour == bedtime)) }
        let sleepItem = item("Sleepy hours"); sleepItem.submenu = sleepTimes; menu.addItem(sleepItem)
        menu.addItem(item("Gentle mode · stay put", action: #selector(toggleGentle), checked: defaults.bool(forKey: "gentle")))
        menu.addItem(.separator())
        menu.addItem(item("Send into Grok Bot", action: #selector(toggleSendOptIn), checked: GrokBotSend.optedIn))
        menu.addItem(item("Pause before sending", action: #selector(toggleSendPause), checked: GrokBotSend.pauseBeforeSending))
        let explanation = item("Sending presses Grok Bot's Send button. That needs Accessibility. A draft already in the composer is not sent or replaced.")
        explanation.isEnabled = false
        menu.addItem(explanation)
        menu.addItem(.separator())
        menu.addItem(item("Quit Cleo", action: #selector(quit)))
    }

    @objc private func startTalking() { toggleTalking() }
    @objc private func stopTalking() { finishCapture(deliver: true) }

    private func holdToTalkBegan() {
        guard visible, !paused, suspended.isEmpty else { return }
        holdOwnsCapture = true
        beginCapture()
    }

    private func holdToTalkEnded() {
        let owned = holdOwnsCapture
        holdOwnsCapture = false
        guard owned, captureStarted else { return }
        finishCapture(deliver: true)
    }

    private func toggleTalking() {
        if captureStarted { finishCapture(deliver: true) }
        else { beginCapture() }
    }

    @objc private func cancelSend() { cancelOutgoingSend(note: "Didn't send.") }
    @objc private func toggleSendOptIn() {
        let enabling = !GrokBotSend.optedIn
        defaults.set(enabling, forKey: GrokBotSend.optInKey)
        if enabling {
            if !GrokBotAccessibility.isTrusted { GrokBotAccessibility.requestPrompt() }
            handoffNote = GrokBotAccessibility.isTrusted
                ? "Cleo can press Send in Grok Bot."
                : "Allow Cleo in System Settings → Privacy & Security → Accessibility. That only lets her press Send."
        } else {
            cancelOutgoingSend(note: "Sending into Grok Bot is off.")
        }
    }
    @objc private func toggleSendPause() {
        defaults.set(!GrokBotSend.pauseBeforeSending, forKey: GrokBotSend.pauseKey)
    }

    private func beginCapture() {
        cancelOutgoingSend(note: nil)
        guard !captureStarted else { return }
        guard visible, !paused, suspended.isEmpty else { return }
        if !OnDeviceSpeechListener.permissionsGranted {
            guard !permissionPromptOpen else { return }
            permissionPromptOpen = true
            handoffNote = "Asking for the microphone and speech recognition."
            OnDeviceSpeechListener.requestAccess { [weak self] granted in
                guard let self else { return }
                self.permissionPromptOpen = false
                self.handoffNote = granted
                    ? "Permission is on. Hold Cleo or press ⌃⌥Space to talk."
                    : "Turn on the microphone and speech recognition for Cleo in System Settings."
                self.holdOwnsCapture = false
            }
            return
        }
        do {
            try speech.start()
        } catch let error as ListenError {
            handoffNote = error.note
            holdOwnsCapture = false
            return
        } catch {
            handoffNote = ListenError.unavailable.note
            holdOwnsCapture = false
            return
        }
        captureStarted = true
        handoffNote = nil
        behavior.beginDictation(now: now)
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Cleo is listening")
        statusItem.button?.toolTip = "Cleo is listening. Release her, or press Control-Option-Space, to hand the words to \(activeProvider.displayName)."
        updateFrame()
        scheduleTimer()
    }

    private func finishCapture(deliver: Bool) {
        guard captureStarted else { return }
        captureStarted = false
        holdOwnsCapture = false
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Cleo companion")
        statusItem.button?.toolTip = "Cleo — your little desktop doodle"
        speech.stop { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.behavior.endDictation(now: self.now, acknowledged: false)
                self.handoffNote = error.note
            case .success(let words) where deliver && !words.isEmpty:
                self.behavior.endDictation(now: self.now, acknowledged: true)
                self.scheduleSend(words)
            case .success:
                self.behavior.endDictation(now: self.now, acknowledged: false)
                if deliver { self.handoffNote = "Cleo didn't catch any words." }
            }
            self.updateFrame()
            self.scheduleTimer()
        }
    }

    private func scheduleSend(_ words: String) {
        let preview = words.count > 80 ? String(words.prefix(80)) + "…" : words
        let blocked = !GrokBotSend.optedIn || !GrokBotAccessibility.isTrusted || GrokBotDrafts.snapshot().selectedDraftOccupied
        guard GrokBotSend.pauseBeforeSending, !blocked else {
            handoffNote = blocked ? "Checking Grok Bot…" : "Sending to \(activeProvider.displayName)…"
            deliverWords(words)
            return
        }
        pendingWords = words
        handoffNote = "Will send in a moment: \(preview) Choose Cancel send to stop."
        statusItem.button?.toolTip = "Cleo will send: \(words). Open the paw menu and choose Cancel send to stop."
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingWords == words else { return }
            self.pendingWords = nil
            self.pendingSend = nil
            self.handoffNote = "Sending to \(self.activeProvider.displayName)…"
            self.deliverWords(words)
        }
        pendingSend = work
        DispatchQueue.main.asyncAfter(deadline: .now() + GrokBotSend.pauseSeconds, execute: work)
        updateFrame()
    }

    private func deliverWords(_ words: String) {
        activeProvider.deliver(text: words) { [weak self] outcome in
            self?.handoffNote = outcome.note
            self?.statusItem.button?.toolTip = "Cleo — your little desktop doodle"
        }
    }

    private func cancelOutgoingSend(note: String?) {
        pendingSend?.cancel()
        pendingSend = nil
        let hadWords = pendingWords != nil
        pendingWords = nil
        if hadWords { handoffNote = note }
        if hadWords { statusItem.button?.toolTip = "Cleo — your little desktop doodle" }
    }

    /// Stops the microphone without opening another app. Used when a different action takes over.
    private func abandonListening() {
        cancelOutgoingSend(note: "Didn't send.")
        guard captureStarted || permissionPromptOpen else { return }
        let wasCapturing = captureStarted
        captureStarted = false
        holdOwnsCapture = false
        permissionPromptOpen = false
        speech.cancel()
        if wasCapturing { behavior.cancelDictation() }
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Cleo companion")
        statusItem.button?.toolTip = "Cleo — your little desktop doodle"
    }

    @objc private func toggleVisible() {
        if visible { abandonListening() }
        visible.toggle()
        snoozeTimer?.invalidate()
        if visible && suspended.isEmpty { panel.orderFrontRegardless(); tick() }
        else { panel.orderOut(nil); stopTimer() }
    }
    @objc private func togglePause() {
        if !paused { abandonListening() }
        paused.toggle()
        if paused { stopTimer() } else { tick() }
    }
    @objc private func snooze() {
        abandonListening()
        visible = false
        panel.orderOut(nil)
        stopTimer()
        snoozeTimer?.invalidate()
        let timer = Timer(timeInterval: 30 * 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.visible = true
            if self.suspended.isEmpty { self.panel.orderFrontRegardless() }
            self.tick()
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimer = timer
    }
    @objc private func giveStick() { request(.stick) }
    @objc private func catchBall() { request(.catchBall) }
    @objc private func wag() { request(.wag) }
    @objc private func sleep() { request(.sleep) }
    @objc private func goHome() { request(.idle) }
    @objc private func quit() {
        cancelOutgoingSend(note: nil)
        NSApp.terminate(nil)
    }
    @objc private func changeCorner(_ sender: NSMenuItem) { defaults.set(sender.tag, forKey: "corner"); resetGeometry() }
    @objc private func changeSize(_ sender: NSMenuItem) { defaults.set(sender.tag, forKey: "size"); resetGeometry() }
    @objc private func changeDisplay(_ sender: NSMenuItem) {
        guard NSScreen.screens.indices.contains(sender.tag) else { return }
        defaults.set(NSScreen.screens[sender.tag].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")], forKey: "display")
        resetGeometry()
    }
    @objc private func changeBedtime(_ sender: NSMenuItem) { defaults.set(sender.tag, forKey: "bedtime"); nextMoodBoundary = nil; tick() }
    @objc private func toggleGentle() { defaults.set(!defaults.bool(forKey: "gentle"), forKey: "gentle"); tick() }

    private func resetGeometry() {
        panel.setContentSize(NSSize(width: panelSide, height: panelSide))
        let geometry = screenGeometry()
        behavior.updateBounds(geometry.0, home: geometry.1, now: now)
        updateFrame()
        scheduleTimer()
    }

    private func installObservers() {
        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("local.cleo.companion.command"), object: nil, queue: .main) { [weak self] message in
                guard let self, let command = message.object as? String else { return }
                switch command {
                case "stick": self.giveStick()
                case "ball": self.catchBall()
                case "wag": self.wag()
                case "pet": self.petCleo()
                case "bark": self.greetCleo()
                case "sleep": self.sleep()
                case "home": self.goHome()
                case "hide": if self.visible { self.toggleVisible() }
                case "show": if !self.visible { self.toggleVisible() }
                case "pause": if !self.paused { self.togglePause() }
                case "resume": if self.paused { self.togglePause() }
                case "snapshot": self.writeDiagnosticsIfRequested()
                case "record": self.recordLiveAnimation()
                case "record-bark": self.greetCleo(); self.recordLiveAnimation(frameCount: 12)
                case "record-hover": self.greetCleo(); self.recordLiveAnimation()
                case "record-sleep": self.recordLiveAnimation(frameCount: 72)
                case "record-ball": self.request(.catchBall); self.recordLiveAnimation(frameCount: 144, framesPerSecond: 24, contactFrames: [0, 20, 36, 40, 100, 142], captureScene: true)
                case "quit": self.quit()
                default: break
                }
            }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.resetGeometry() })
        observers.append(center.addObserver(forName: NSNotification.Name.NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in self?.nextMoodBoundary = nil; self?.tick() })
        let workspace = NSWorkspace.shared.notificationCenter
        let pairs: [(Notification.Name, Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification, "system"),
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, "screens"),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, "session")
        ]
        for (sleep, wake, reason) in pairs {
            workspaceObservers.append(workspace.addObserver(forName: sleep, object: nil, queue: .main) { [weak self] _ in
                self?.suspended.insert(reason); self?.stopTimer(); self?.panel.orderOut(nil)
            })
            workspaceObservers.append(workspace.addObserver(forName: wake, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.suspended.remove(reason)
                if self.suspended.isEmpty && self.visible { self.resetGeometry(); self.panel.orderFrontRegardless(); self.tick() }
            })
        }
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in self?.tick() })
    }

    /// Optional diagnostics inspect only Cleo's own window and render its own artwork.
    private func writeDiagnosticsIfRequested() {
        let args = CommandLine.arguments
        guard let argument = args.firstIndex(of: "--diagnostics"), args.indices.contains(argument + 1) else { return }
        let path = args[argument + 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.panel.displayIfNeeded()
            CATransaction.flush()
            var dogHits = 0, transparentHits = 0, transparentTests = 0
            // Ask WindowServer its normal mouse-down hit rules; never click or move the pointer.
            for y in stride(from: 2, to: Int(self.sprite.bounds.height), by: 5) {
                for x in stride(from: 2, to: Int(self.sprite.bounds.width), by: 5) {
                    let local = NSPoint(x: x, y: y)
                    let global = self.panel.convertPoint(toScreen: local)
                    let hit = NSWindow.windowNumber(at: global, belowWindowWithWindowNumber: 0) == self.panel.windowNumber
                    if self.sprite.containsDog(local) { if hit { dogHits += 1 } }
                    else { transparentTests += 1; if hit { transparentHits += 1 } }
                }
            }
            var report: [String: Any] = ["app": "Cleo", "frames": self.sprite.frames.count,
                "turnFrames": self.sprite.turnFrameCount,
                "barkFrames": self.sprite.barkFrameCount,
                "keyWindow": self.panel.isKeyWindow, "mainWindow": self.panel.isMainWindow, "appActive": NSApp.isActive,
                "windowVisible": self.panel.isVisible, "userVisible": self.visible, "paused": self.paused,
                "suspensionReasons": self.suspended.sorted(), "windowNumber": self.panel.windowNumber,
                "canBecomeKey": self.panel.canBecomeKey, "nonactivating": self.panel.styleMask.contains(.nonactivatingPanel),
                "transparentWindowHits": transparentHits, "transparentPointsTested": transparentTests, "dogWindowHits": dogHits,
                "panelPoints": Int(self.panel.frame.width), "spritePoints": Int(self.sprite.spriteRect.width),
                "mood": self.behavior.mood.rawValue, "timerIntervalSeconds": self.timerInterval,
                "carriedToy": self.behavior.carriedToy.rawValue, "ballProgress": self.behavior.ballProgress,
                "ballWindowVisible": self.ballPanel.isVisible, "ballIgnoresMouseEvents": self.ballPanel.ignoresMouseEvents,
                "ballCanBecomeKey": self.ballPanel.canBecomeKey, "ballKeyWindow": self.ballPanel.isKeyWindow,
                "ballWindowReceivesHit": self.ballPanel.isVisible && NSWindow.windowNumber(at: NSPoint(x: self.ballPanel.frame.midX, y: self.ballPanel.frame.midY), belowWindowWithWindowNumber: 0) == self.ballPanel.windowNumber,
                "dictating": self.behavior.isDictating, "captureStarted": self.captureStarted,
                "hotKeyRegistered": self.hotKey.isRegistered,
                "speechOnDeviceOnly": true, "grokBotInstalled": GrokBotLink.isInstalled,
                "sendOptIn": GrokBotSend.optedIn, "pauseBeforeSend": GrokBotSend.pauseBeforeSending,
                "accessibilityTrusted": GrokBotAccessibility.isTrusted,
                "agentProvider": self.activeProvider.identifier,
                "hoverEntryConsumed": self.hoverEntryConsumed, "hoverBarkCount": self.hoverBarkCount,
                "hoverSleepGreetingCount": self.hoverSleepGreetingCount,
                "pixelWidth": self.sprite.frames.first?.width ?? 0]
            var memory = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &memory) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS { report["physicalFootprintMiB"] = Double(memory.phys_footprint) / 1_048_576 }
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            if let image = self.sprite.snapshot(), let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path + ".png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                CGImageDestinationFinalize(destination)
            }
        }
    }

    private func recordingWorldRect() -> NSRect {
        let size = panel.frame.size
        var rect = panel.frame
            .union(NSRect(x: behavior.home.x, y: behavior.home.y, width: size.width, height: size.height))
            .union(NSRect(x: behavior.ballDestination.x, y: behavior.ballDestination.y, width: size.width, height: size.height))
        for point in [ballLaunch, ballControl].compactMap({ $0 }) {
            rect = rect.union(NSRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        }
        return rect.insetBy(dx: -12, dy: -12).integral
    }

    /// Composite only Cleo's own two views; never read the desktop or other windows.
    private func recordingImage(in worldRect: NSRect?) -> CGImage? {
        guard let worldRect else { return sprite.snapshot() }
        guard let dog = sprite.snapshot() else { return nil }
        let scale = min(1, 512 / worldRect.width, 320 / worldRect.height)
        let width = max(1, Int(ceil(worldRect.width * scale)))
        let height = max(1, Int(ceil(worldRect.height * scale)))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(dog, in: panel.frame.offsetBy(dx: -worldRect.minX, dy: -worldRect.minY))
        if ballPanel.isVisible {
            let rect = ballPanel.frame.insetBy(dx: 2, dy: 2).offsetBy(dx: -worldRect.minX, dy: -worldRect.minY)
            context.draw(ThrownBallView.artwork, in: rect)
        }
        return context.makeImage()
    }

    /// A short capture of the actual running artwork, for review without screen access.
    private func recordLiveAnimation(frameCount: Int = 36, framesPerSecond: Double = 12,
                                     contactFrames: [Int]? = nil, captureScene: Bool = false) {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--diagnostics"), args.indices.contains(index + 1), visible else { return }
        let prefix = args[index + 1]
        var frames: [CGImage] = []
        var positions: [[String: Any]] = []
        let frameDelay = 1.0 / framesPerSecond
        let worldRect = captureScene ? recordingWorldRect() : nil
        recordingTimer?.invalidate()
        let capture = Timer(timeInterval: frameDelay, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            if let frame = self.recordingImage(in: worldRect) {
                frames.append(frame)
                positions.append(["frame": frames.count - 1, "mood": self.behavior.mood.rawValue,
                    "x": self.panel.frame.minX, "y": self.panel.frame.minY,
                    "facingLeft": self.behavior.facingLeft, "animationTime": self.behavior.animationTime,
                    "carriedToy": self.behavior.carriedToy.rawValue, "ballProgress": self.behavior.ballProgress,
                    "timerIntervalSeconds": self.timerInterval,
                    "ballVisible": self.ballPanel.isVisible, "ballX": self.ballPanel.frame.midX,
                    "ballY": self.ballPanel.frame.midY,
                    "mouthX": self.sprite.ballMouthPointOnScreen?.x ?? 0,
                    "mouthY": self.sprite.ballMouthPointOnScreen?.y ?? 0,
                    "uptime": self.now])
            }
            guard frames.count >= frameCount else { return }
            timer.invalidate()
            self.recordingTimer = nil
            guard let first = frames.first else { return }
            let gif = CGImageDestinationCreateWithURL(URL(fileURLWithPath: prefix + ".gif") as CFURL,
                UTType.gif.identifier as CFString, frames.count, nil)!
            CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let sheet = CGContext(data: nil, width: first.width * 3, height: first.height * 2,
                bitsPerComponent: 8, bytesPerRow: first.width * 3 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            sheet.setFillColor(CGColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1))
            sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
            for (frameIndex, frame) in frames.enumerated() {
                CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary)
                let stride = max(1, frameCount / 6)
                let cell = contactFrames?.firstIndex(of: frameIndex) ?? (contactFrames == nil && frameIndex % stride == 0 ? frameIndex / stride : nil)
                if let cell, cell < 6 {
                    sheet.draw(frame, in: CGRect(x: (cell % 3) * first.width, y: (1 - cell / 3) * first.height,
                                               width: first.width, height: first.height))
                }
            }
            CGImageDestinationFinalize(gif)
            if let data = try? JSONSerialization.data(withJSONObject: positions, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: prefix + "-motion.json"))
            }
            if let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: prefix + "-motion.png") as CFURL, UTType.png.identifier as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, sheet.makeImage()!, nil)
                CGImageDestinationFinalize(destination)
            }
        }
        RunLoop.main.add(capture, forMode: .common)
        recordingTimer = capture
    }

    func applicationWillTerminate(_ notification: Notification) {
        abandonListening()
        hotKey.remove()
        stopTimer()
        snoozeTimer?.invalidate()
        recordingTimer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let commandObserver { DistributedNotificationCenter.default().removeObserver(commandObserver) }
    }
}

