import AppKit
import ApplicationServices
import Foundation

enum GrokBotSend {
    static let optInKey = "sendIntoGrokBot"
    static let pauseKey = "pauseBeforeSend"
    static let pauseSeconds: TimeInterval = 2.5
    /// English accessibility label of Grok Bot 0.75.8's composer submit button.
    static let sendButtonLabel = "Send message"

    static var optedIn: Bool { UserDefaults.standard.bool(forKey: optInKey) }

    static var pauseBeforeSending: Bool {
        if UserDefaults.standard.object(forKey: pauseKey) == nil { return true }
        return UserDefaults.standard.bool(forKey: pauseKey)
    }

    /// Status only. Does not open Grok Bot, press Send, or read a transcript aloud.
    static func planLine() -> String {
        let snap = GrokBotDrafts.snapshot()
        let occupied = snap.records.filter(\.occupied).count
        var line = "optIn=\(optedIn) accessibility=\(GrokBotAccessibility.isTrusted) pauseBeforeSend=\(pauseBeforeSending) selectedDraftOccupied=\(snap.selectedDraftOccupied) composerDrafts=\(snap.records.count) occupiedDrafts=\(occupied)"
        if GrokBotAccessibility.isTrusted, let pid = NSRunningApplication.runningApplications(withBundleIdentifier: GrokBotLink.bundleIdentifier).first?.processIdentifier {
            line += " sendButtons=\(GrokBotAccessibility.sendButtonCount(pid: pid))"
        }
        return line
    }
}

enum GrokBotAccessibility {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt. Call this only after the menu opt-in.
    static func requestPrompt() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    enum Look {
        case waiting
        case mismatch
        case matched
        case unreadable
    }

    /// Reads Grok Bot's composer and Send button. Does not press anything.
    static func look(pid: pid_t, expected: String) -> Look {
        guard isTrusted else { return .unreadable }
        let found = Interface(pid: pid)
        if found.composerTexts.contains(expected) { return found.sendButtons == 1 ? .matched : .unreadable }
        if found.composerTexts.contains(where: { !$0.isEmpty && $0 != expected }) { return .mismatch }
        return found.composerTexts.isEmpty ? .unreadable : .waiting
    }

    static func pressSend(pid: pid_t) -> Bool {
        guard isTrusted else { return false }
        return Interface(pid: pid).pressSend()
    }

    static func sendButtonCount(pid: pid_t) -> Int {
        guard isTrusted else { return 0 }
        return Interface(pid: pid).sendButtons
    }

    private struct Interface {
        var composerTexts: [String] = []
        var sendButtons: Int = 0
        private var sendButton: AXUIElement?
        private var nodes = 0

        init(pid: pid_t) {
            let app = AXUIElementCreateApplication(pid)
            // Chromium builds its accessibility tree when a client asks for it.
            AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            var windows: CFTypeRef?
            AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
            var list = Self.elements(windows)
            if list.isEmpty {
                var children: CFTypeRef?
                AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children)
                list = Self.elements(children)
            }
            for window in list where string(window, kAXRoleAttribute) != (kAXMenuBarRole as String) {
                walk(window, depth: 0)
            }
        }

        private static func elements(_ value: CFTypeRef?) -> [AXUIElement] {
            value as? [AXUIElement] ?? []
        }

        private mutating func walk(_ element: AXUIElement, depth: Int) {
            guard depth < 14, nodes < 800 else { return }
            nodes += 1
            let role = string(element, kAXRoleAttribute) ?? ""
            if role == (kAXMenuBarRole as String) || role == "AXMenuBar" { return }
            if role == (kAXTextAreaRole as String) || role == (kAXTextFieldRole as String) {
                let value = (string(element, kAXValueAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { composerTexts.append(value) }
            }
            if role == (kAXButtonRole as String) {
                let label = string(element, kAXDescriptionAttribute) ?? string(element, kAXTitleAttribute) ?? ""
                if label == GrokBotSend.sendButtonLabel && enabled(element) {
                    sendButtons += 1
                    if sendButton == nil { sendButton = element }
                }
            }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success else { return }
            for child in Self.elements(children) { walk(child, depth: depth + 1) }
        }

        func pressSend() -> Bool {
            guard sendButtons == 1, let sendButton else { return false }
            return AXUIElementPerformAction(sendButton, kAXPressAction as CFString) == .success
        }

        private func string(_ element: AXUIElement, _ attribute: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
            return value as? String
        }

        private func enabled(_ element: AXUIElement) -> Bool {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &value) == .success else { return true }
            return (value as? Bool) ?? true
        }
    }
}

struct GrokBotDraftSnapshot {
    struct Record {
        var agentID: String
        var prompt: String
        var occupied: Bool
    }
    var records: [Record]
    var selectedAgentID: String?

    var selectedDraftOccupied: Bool {
        guard let selectedAgentID else { return false }
        return records.contains { $0.agentID == selectedAgentID && $0.occupied }
    }

    /// True when an empty composer slot now holds exactly `text`.
    func landed(_ text: String, comparedWith previous: GrokBotDraftSnapshot) -> Bool {
        for record in records where record.prompt == text {
            let before = previous.records.first { $0.agentID == record.agentID }
            if before == nil || before?.occupied == false { return true }
        }
        return false
    }
}

enum GrokBotDrafts {
    static func snapshot() -> GrokBotDraftSnapshot {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Grok Bot/sand-client-persistence")
        var records: [GrokBotDraftSnapshot.Record] = []
        var selected: String?
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasSuffix(".blob") {
            guard let key = Base32.decode(String(name.dropLast(5))),
                  let text = String(data: key, encoding: .utf8) else { continue }
            let url = directory.appendingPathComponent(name)
            guard let data = try? Data(contentsOf: url), data.count < 100_000,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let value = json["value"] else { continue }
            if text.hasSuffix(".selection.last-agent"), let body = value as? [String: Any] {
                selected = body["agentId"] as? String
            }
            if let agentID = agentID(in: text) {
                records.append(contentsOf: recordsFrom(value: value, agentID: agentID))
            }
        }
        return GrokBotDraftSnapshot(records: records, selectedAgentID: selected)
    }

    private static func agentID(in key: String) -> String? {
        let marker = ".composer-drafts."
        guard let range = key.range(of: marker) else { return nil }
        let raw = String(key[range.upperBound...])
        guard !raw.isEmpty, let decoded = raw.removingPercentEncoding, !decoded.isEmpty else { return nil }
        return decoded
    }

    private static func recordsFrom(value: Any, agentID: String) -> [GrokBotDraftSnapshot.Record] {
        guard let body = value as? [String: Any] else { return [] }
        if let agents = body["agents"] as? [String: Any] {
            return agents.map { id, entry in
                let record = entry as? [String: Any] ?? [:]
                return GrokBotDraftSnapshot.Record(agentID: id, prompt: prompt(of: record), occupied: occupied(record))
            }
        }
        return [GrokBotDraftSnapshot.Record(agentID: agentID, prompt: prompt(of: body), occupied: occupied(body))]
    }

    static func occupied(_ record: [String: Any]) -> Bool {
        if let draft = record["draft"] as? [String: Any], hasContent(draft) { return true }
        if let recovery = record["recovery"] as? [String: Any], hasContent(recovery) { return true }
        return false
    }

    static func prompt(of record: [String: Any]) -> String {
        (record["draft"] as? [String: Any])?["prompt"] as? String ?? ""
    }

    static func hasContent(_ draft: [String: Any]) -> Bool {
        let prompt = (draft["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !prompt.isEmpty { return true }
        if let attachments = draft["attachments"] as? [Any], !attachments.isEmpty { return true }
        if let reply = draft["replyToId"] as? String, !reply.isEmpty { return true }
        return false
    }
}

enum Base32 {
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    static func decode(_ input: String) -> Data? {
        var buffer = 0
        var bits = 0
        var output = Data()
        for character in input.uppercased() where character != "=" {
            guard let index = alphabet.firstIndex(of: character) else { return nil }
            buffer = (buffer << 5) | index
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((buffer >> bits) & 0xFF))
            }
        }
        return output
    }

    static func encode(_ data: Data) -> String {
        var buffer = 0
        var bits = 0
        var output = ""
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                output.append(alphabet[(buffer >> bits) & 31])
            }
        }
        if bits > 0 { output.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return output.lowercased()
    }
}
