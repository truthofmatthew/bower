import Carbon.HIToolbox

/// Global shortcuts via Carbon's RegisterEventHotKey, which needs no Input Monitoring permission.
final class Hotkeys {
    static let shared = Hotkeys()

    private struct Binding {
        let down: () -> Void
        let up: (() -> Void)?
        var ref: EventHotKeyRef?
    }

    private var bindings: [UInt32: Binding] = [:]
    private var nextID: UInt32 = 1

    private init() {
        var specs = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard let b = Hotkeys.shared.bindings[hk.id] else { return noErr }
            if GetEventKind(event) == UInt32(kEventHotKeyPressed) { b.down() } else { b.up?() }
            return noErr
        }, 2, &specs, nil, nil)
    }

    /// `mods` uses Carbon flags: optionKey, controlKey, shiftKey, cmdKey.
    /// Returns eventHotKeyExistsErr when another app already owns the combination.
    @discardableResult
    func add(_ key: Int, _ mods: Int, down: @escaping () -> Void, up: (() -> Void)? = nil) -> OSStatus {
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hkid = EventHotKeyID(signature: OSType(0x424F_5752), id: id)  // "BOWR"
        let status = RegisterEventHotKey(UInt32(key), UInt32(mods), hkid, GetApplicationEventTarget(), 0, &ref)
        if status == noErr { bindings[id] = Binding(down: down, up: up, ref: ref) }
        return status
    }

    func removeAll() {
        for b in bindings.values { if let ref = b.ref { UnregisterEventHotKey(ref) } }
        bindings = [:]
    }

    static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
}
