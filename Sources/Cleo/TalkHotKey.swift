import Carbon
import Foundation

/// A press-to-toggle hotkey registered with the system.
/// Hold-style global keys need Input Monitoring, which Cleo does not request.
final class TalkHotKey {
    var onPressed: (() -> Void)?
    private(set) var isRegistered = false
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var retainedSelf: Unmanaged<TalkHotKey>?

    func install() {
        guard hotKey == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        retainedSelf = Unmanaged.passUnretained(self)
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<TalkHotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { hotKey.onPressed?() }
            return noErr
        }, 1, &spec, retainedSelf?.toOpaque(), &handler)
        let identifier = EventHotKeyID(signature: OSType(0x434C454F), id: 1)
        // Control-Option-Space. It does not take Spotlight's Command-Space.
        let status = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), identifier,
                                         GetApplicationEventTarget(), 0, &hotKey)
        isRegistered = status == noErr && hotKey != nil
    }

    func remove() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
        retainedSelf = nil
        isRegistered = false
    }
}
