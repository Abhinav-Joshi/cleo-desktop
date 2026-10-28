import AppKit
import Foundation

/// Outcome of handing text to one local agent app. Cleo never opens a network connection for this.
enum AgentHandoffResult {
    /// Grok Bot's Send button was pressed. Grok Bot delivers the message on its own network.
    case sent(note: String)
    /// The composer has the words. Cleo did not press Send.
    case prefilled(note: String)
    /// A composer draft was already there, so nothing was replaced and nothing was sent.
    case keptDraft(note: String)
    case needsOptIn(note: String)
    case needsAccessibility(note: String)
    /// The link could not be used. The words are on the clipboard instead.
    case clipboardFallback(note: String)
    case failed(note: String)

    var note: String {
        switch self {
        case .sent(let note), .prefilled(let note), .keptDraft(let note), .needsOptIn(let note), .needsAccessibility(let note), .clipboardFallback(let note), .failed(let note):
            return note
        }
    }
}

/// One desktop agent Cleo can hand a transcript to. Later providers register beside Grok Bot.
protocol AgentProvider: AnyObject {
    var identifier: String { get }
    var displayName: String { get }
    func deliver(text: String, completion: @escaping (AgentHandoffResult) -> Void)
}

enum GrokBotLink {
    static let bundleIdentifier = "com.anysphere.sand"
    /// Grok Bot 0.75.8 rejects a decoded `text` longer than this.
    static let maxDecodedLength = 1000
    /// Grok Bot 0.75.8 rejects the whole URL longer than this.
    static let maxURLLength = 2048

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    /// Builds `grokbot://app/v1/prompt?text=…`, the route Grok Bot 0.75.8 parses.
    /// Returns nil when the text is empty after cleanup. Long text is shortened until the URL fits.
    static func promptURL(for raw: String) -> URL? {
        var text = normalized(raw)
        while !text.isEmpty {
            let urlString = "grokbot://app/v1/prompt?text=\(percentEncode(text))"
            if urlString.count <= maxURLLength, let url = URL(string: urlString) {
                return url
            }
            text.removeLast()
        }
        return nil
    }

    /// Collapses whitespace and drops control characters. Grok Bot rejects those in `text`.
    static func normalized(_ raw: String) -> String {
        var output = ""
        var lastWasSpace = false
        for character in raw {
            let scalars = character.unicodeScalars
            let isControl = scalars.contains { scalar in
                scalar.value < 32 || (scalar.value >= 127 && scalar.value <= 159)
            }
            if isControl || character == "\n" || character == "\r" || character == "\t" {
                if !output.isEmpty && !lastWasSpace {
                    output.append(" ")
                    lastWasSpace = true
                }
                continue
            }
            if character == " " {
                if output.isEmpty || lastWasSpace { continue }
                lastWasSpace = true
                output.append(" ")
            } else {
                lastWasSpace = false
                output.append(character)
            }
            if output.count >= maxDecodedLength { break }
        }
        while output.last == " " { output.removeLast() }
        if output.count > maxDecodedLength {
            output = String(output.prefix(maxDecodedLength))
            while output.last == " " { output.removeLast() }
        }
        return output
    }

    /// Same unreserved set as `encodeURIComponent`, with uppercase hex, so the URL stays printable ASCII.
    private static func percentEncode(_ text: String) -> String {
        var encoded = ""
        for scalar in text.unicodeScalars {
            let value = scalar.value
            let unreserved = (value >= 48 && value <= 57) || (value >= 65 && value <= 90)
                || (value >= 97 && value <= 122) || value == 45 || value == 95 || value == 46 || value == 126
            if unreserved {
                encoded.unicodeScalars.append(scalar)
            } else if let bytes = String(scalar).data(using: .utf8) {
                for byte in bytes {
                    encoded += String(format: "%%%02X", byte)
                }
            }
        }
        return encoded
    }
}

/// Fills Grok Bot's main-agent composer, then presses Send. Cleo opens no network connection.
final class GrokBotProvider: AgentProvider {
    let identifier = "grok-bot"
    let displayName = "Grok Bot"

    func deliver(text: String, completion: @escaping (AgentHandoffResult) -> Void) {
        let words = GrokBotLink.normalized(text)
        guard !words.isEmpty else {
            completion(.failed(note: "Cleo didn't catch any words."))
            return
        }
        guard GrokBotLink.isInstalled else {
            completion(copy(words, reason: "Grok Bot is not installed.", result: { .clipboardFallback(note: $0) }))
            return
        }
        let before = GrokBotDrafts.snapshot()
        if before.selectedDraftOccupied {
            completion(copy(words, reason: "Grok Bot already has a draft, so Cleo didn't send or replace it.", result: { .keptDraft(note: $0) }))
            return
        }
        guard let url = GrokBotLink.promptURL(for: words) else {
            completion(copy(words, reason: "Those words could not fit in a Grok Bot link.", result: { .clipboardFallback(note: $0) }))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Local URL only. Cleo does not open https://cursor.com.
        NSWorkspace.shared.open(url, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                if error != nil || application == nil {
                    completion(self.copy(words, reason: "Grok Bot did not open the link.", result: { .clipboardFallback(note: $0) }))
                    return
                }
                let pid = application?.processIdentifier
                    ?? NSRunningApplication.runningApplications(withBundleIdentifier: GrokBotLink.bundleIdentifier).first?.processIdentifier
                guard GrokBotSend.optedIn else {
                    completion(.needsOptIn(note: "Words are in Grok Bot's composer, not sent. Turn on Send into Grok Bot. That needs Accessibility."))
                    return
                }
                guard GrokBotAccessibility.isTrusted, let pid else {
                    completion(.needsAccessibility(note: "Words are in the composer, not sent. Allow Cleo in System Settings → Privacy & Security → Accessibility."))
                    return
                }
                self.confirmThenPress(words: words, before: before, pid: pid, attemptsLeft: 8, completion: completion)
            }
        }
    }

    private func confirmThenPress(words: String, before: GrokBotDraftSnapshot, pid: pid_t, attemptsLeft: Int, completion: @escaping (AgentHandoffResult) -> Void) {
        let landed = GrokBotDrafts.snapshot().landed(words, comparedWith: before)
        switch GrokBotAccessibility.look(pid: pid, expected: words) {
        case .mismatch:
            completion(copy(words, reason: "Grok Bot kept what was already in the composer, so Cleo didn't send.", result: { .keptDraft(note: $0) }))
        case .matched where landed || attemptsLeft == 0:
            completion(press(pid: pid, words: words))
        case .matched:
            // The composer shows the words. Give the draft file a moment, then press.
            retry(words: words, before: before, pid: pid, attemptsLeft: attemptsLeft, completion: completion)
        case .waiting, .unreadable:
            if attemptsLeft > 0 {
                retry(words: words, before: before, pid: pid, attemptsLeft: attemptsLeft, completion: completion)
            } else if landed {
                completion(.prefilled(note: "Words are in Grok Bot's composer. Send wasn't visible to Accessibility, so Cleo didn't press it."))
            } else {
                completion(copy(words, reason: "Cleo couldn't confirm an empty composer, so she didn't send.", result: { .keptDraft(note: $0) }))
            }
        }
    }

    private func retry(words: String, before: GrokBotDraftSnapshot, pid: pid_t, attemptsLeft: Int, completion: @escaping (AgentHandoffResult) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.confirmThenPress(words: words, before: before, pid: pid, attemptsLeft: attemptsLeft - 1, completion: completion)
        }
    }

    private func press(pid: pid_t, words: String) -> AgentHandoffResult {
        if GrokBotAccessibility.pressSend(pid: pid) {
            return .sent(note: "Sent to Grok Bot.")
        }
        return .prefilled(note: "Words are in Grok Bot's composer. Cleo couldn't press Send, so she didn't.")
    }

    private func copy(_ words: String, reason: String, result: (String) -> AgentHandoffResult) -> AgentHandoffResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(words, forType: .string)
        return result("\(reason) The words are on the clipboard.")
    }
}

/// Local checks for the link builder and the listening pose. No microphone and no other app.
func cleoSelfCheck() -> Bool {
    var failed = 0
    func check(_ name: String, _ condition: Bool) {
        print(condition ? "ok \(name)" : "FAIL \(name)")
        if !condition { failed += 1 }
    }

    let spaced = GrokBotLink.promptURL(for: "hello world")?.absoluteString
    check("space encoding", spaced == "grokbot://app/v1/prompt?text=hello%20world")
    let broken = GrokBotLink.promptURL(for: "hello\nthere")?.absoluteString
    check("newline becomes space", broken == "grokbot://app/v1/prompt?text=hello%20there")
    check("blank rejected", GrokBotLink.promptURL(for: " \n\t") == nil)
    let plus = GrokBotLink.promptURL(for: "a+b")?.absoluteString ?? ""
    check("plus encoded", plus == "grokbot://app/v1/prompt?text=a%2Bb")
    let long = GrokBotLink.promptURL(for: String(repeating: "á", count: 5000))
    check("url fits", (long?.absoluteString.count ?? 9_999) <= GrokBotLink.maxURLLength)
    if let long, let items = URLComponents(url: long, resolvingAgainstBaseURL: false)?.queryItems,
       let text = items.first(where: { $0.name == "text" })?.value {
        check("decoded cap", text.count <= GrokBotLink.maxDecodedLength && items.count == 1)
        check("ascii url", long.absoluteString.unicodeScalars.allSatisfy { $0.value >= 33 && $0.value <= 126 })
    } else {
        check("decoded cap", false)
        check("ascii url", false)
    }

    let bounds = PetBounds(minX: 0, minY: 0, maxX: 500, maxY: 400)
    let home = PetPoint(x: 360, y: 24)
    let behavior = CleoBehavior(bounds: bounds, home: home, now: 0, evening: false, seed: 2)
    let start = behavior.position
    check("begin", behavior.beginDictation(now: 1))
    behavior.tick(now: 2, mouse: PetPoint(x: 0, y: 0), evening: false, reducedMotion: true)
    check("stays put", abs(behavior.position.x - start.x) < 0.01 && abs(behavior.position.y - start.y) < 0.01)
    check("listening", behavior.mood == .listen && behavior.isDictating)
    behavior.clicked(now: 2, mouse: start)
    check("click waits", behavior.mood == .listen)
    check("hover waits", behavior.hovered(now: 2) == false)
    behavior.endDictation(now: 2, acknowledged: true)
    check("ack bark", behavior.mood == .bark && !behavior.isDictating)
    behavior.tick(now: 3.2, mouse: nil, evening: false, reducedMotion: true)
    check("resumed", behavior.mood == .idle)
    check("still home", abs(behavior.position.x - start.x) < 0.01 && abs(behavior.position.y - start.y) < 0.01)

    let sleepy = CleoBehavior(bounds: bounds, home: home, now: 0, evening: true, seed: 3)
    let sleepSpot = sleepy.position
    check("asleep", sleepy.mood == .sleep)
    check("sleep listen", sleepy.beginDictation(now: 5))
    sleepy.tick(now: 6, mouse: PetPoint(x: 0, y: 0), evening: true, reducedMotion: false)
    check("sleep stays", sleepy.mood == .listen && abs(sleepy.position.x - sleepSpot.x) < 0.01 && abs(sleepy.position.y - sleepSpot.y) < 0.01)
    sleepy.endDictation(now: 6, acknowledged: true)
    sleepy.tick(now: 7.2, mouse: nil, evening: true, reducedMotion: true)
    check("back to sleep", sleepy.mood == .sleep && abs(sleepy.position.x - sleepSpot.x) < 0.01)

    let roundTrip = "sand.client.slice.ui-layout"
    let encoded = Base32.encode(Data(roundTrip.utf8))
    check("base32", String(data: Base32.decode(encoded) ?? Data(), encoding: .utf8) == roundTrip)
    let empty: [String: Any] = ["draft": ["prompt": "  ", "attachments": []], "recovery": NSNull()]
    check("blank draft", GrokBotDrafts.occupied(empty) == false)
    let typing: [String: Any] = ["draft": ["prompt": "hello", "attachments": []], "recovery": NSNull()]
    check("typing draft", GrokBotDrafts.occupied(typing) && GrokBotDrafts.prompt(of: typing) == "hello")
    let reply: [String: Any] = ["draft": ["prompt": "", "attachments": [], "replyToId": "abc"]]
    check("reply draft", GrokBotDrafts.occupied(reply))
    let previous = GrokBotDraftSnapshot(records: [.init(agentID: "a", prompt: "", occupied: false)], selectedAgentID: "a")
    let filled = GrokBotDraftSnapshot(records: [.init(agentID: "a", prompt: "hello", occupied: true)], selectedAgentID: "a")
    check("landed", filled.landed("hello", comparedWith: previous))
    let kept = GrokBotDraftSnapshot(records: [.init(agentID: "a", prompt: "mine", occupied: true)], selectedAgentID: "a")
    check("kept draft", filled.landed("hello", comparedWith: kept) == false && kept.selectedDraftOccupied)
    return failed == 0
}
