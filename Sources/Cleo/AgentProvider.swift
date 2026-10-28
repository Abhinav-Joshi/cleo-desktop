import AppKit
import Foundation

/// Outcome of handing text to one local agent app. Cleo never opens a network connection for this.
enum AgentHandoffResult {
    /// The provider's own app opened with the words waiting in its composer.
    case prefilled(note: String)
    /// The link could not be used. The words are on the clipboard instead.
    case clipboardFallback(note: String)
    case failed(note: String)

    var note: String {
        switch self {
        case .prefilled(let note), .clipboardFallback(let note), .failed(let note):
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

/// Hands text to the installed Grok Bot app through its local URL scheme.
final class GrokBotProvider: AgentProvider {
    let identifier = "grok-bot"
    let displayName = "Grok Bot"

    func deliver(text: String, completion: @escaping (AgentHandoffResult) -> Void) {
        let words = GrokBotLink.normalized(text)
        guard !words.isEmpty else {
            completion(.failed(note: "Cleo didn't catch any words."))
            return
        }
        guard let url = GrokBotLink.promptURL(for: words) else {
            completion(copyToClipboard(words, reason: "Those words could not fit in a Grok Bot link."))
            return
        }
        guard GrokBotLink.isInstalled else {
            completion(copyToClipboard(words, reason: "Grok Bot is not installed."))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Local URL only. Cleo does not open https://cursor.com or any other network request.
        NSWorkspace.shared.open(url, configuration: configuration) { application, error in
            DispatchQueue.main.async {
                if error != nil || application == nil {
                    completion(self.copyToClipboard(words, reason: "Grok Bot did not open the link."))
                } else {
                    completion(.prefilled(note: "In Grok Bot's composer, not sent. An existing draft is left as it is."))
                }
            }
        }
    }

    private func copyToClipboard(_ words: String, reason: String) -> AgentHandoffResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(words, forType: .string)
        if let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: GrokBotLink.bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: application, configuration: configuration) { _, _ in }
        }
        return .clipboardFallback(note: "\(reason) The words are on the clipboard.")
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
    return failed == 0
}
