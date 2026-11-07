import Carbon.HIToolbox
import SwiftUI

/// A key and Carbon modifier flags. `key == -1` is a modifier-only combo for a row that covers several keys.
struct Combo: Codable, Equatable, Hashable {
    var key: Int
    var mods: Int
}

/// One row of Settings › Shortcuts (SetShortcuts.dc.html). Grouped rows ("Left / Right Half", "Switch to
/// layout ⌥1…9") keep their keys; rebinding them changes the modifiers they share.
enum ShortcutID: String, CaseIterable, Codable {
    case wheel, layoutsBar
    case switchLayout, sendLayout, saveWorkspace, cycleLayouts, emptyLayout
    case focus, moveWindow, wider, narrower, center, putBack, nextDisplay, nextTab
    case halvesLR, halvesTB, quarters, thirds, twoThirds, maximize, retile
    case everything, stepIn, stepOut, frame, back, forward, goView, saveView
    case desktop, arrange, split, float

    var title: String {
        switch self {
        case .wheel: String(localized: "Snap Wheel")
        case .layoutsBar: String(localized: "Layouts Bar")
        case .switchLayout: String(localized: "Switch to layout")
        case .sendLayout: String(localized: "Send window to layout")
        case .saveWorkspace: String(localized: "Save workspace")
        case .cycleLayouts: String(localized: "Next layout")
        case .emptyLayout: String(localized: "Next empty layout")
        case .focus: String(localized: "Focus window left / right / up / down")
        case .moveWindow: String(localized: "Move window left / right / up / down")
        case .wider: String(localized: "Make window wider")
        case .narrower: String(localized: "Make window narrower")
        case .center: String(localized: "Center window")
        case .putBack: String(localized: "Put windows back in place")
        case .nextDisplay: String(localized: "Send window to the next display")
        case .nextTab: String(localized: "Next tab in group")
        case .halvesLR: String(localized: "Left / Right Half")
        case .halvesTB: String(localized: "Top / Bottom Half")
        case .quarters: String(localized: "Quarters")
        case .thirds: String(localized: "Thirds")
        case .twoThirds: String(localized: "First / Last Two Thirds")
        case .maximize: String(localized: "Maximize")
        case .retile: String(localized: "Retile display")
        case .everything: String(localized: "Show the overview")
        case .stepIn: String(localized: "Expand a level")
        case .stepOut: String(localized: "Back a level")
        case .frame: String(localized: "Frame the focused window on its own")
        case .back: String(localized: "Go back")
        case .forward: String(localized: "Go forward")
        case .goView: String(localized: "Go to a saved view")
        case .saveView: String(localized: "Save this view")
        case .desktop: String(localized: "Show or hide the Desktop's tile")
        case .arrange: String(localized: "Arrange every window into tiles")
        case .split: String(localized: "Split with a new Finder window")
        case .float: String(localized: "Float or dock the focused window")
        }
    }

    var group: String {
        switch self {
        case .wheel, .layoutsBar: "Overlays"
        case .switchLayout, .sendLayout, .saveWorkspace, .cycleLayouts, .emptyLayout: "Layouts"
        case .focus, .moveWindow, .wider, .narrower, .center, .putBack, .nextDisplay, .nextTab: "Windows"
        case .everything, .stepIn, .stepOut, .frame, .back, .forward, .goView, .saveView: "Expand"
        case .desktop, .arrange, .split, .float: "Dock"
        default: "Snapping"
        }
    }

    /// The group's heading, translated; `group` stays the English key the Shortcuts tab sorts by.
    var groupTitle: String {
        switch group {
        case "Overlays": String(localized: "Snap Wheel and Layouts Bar")
        case "Layouts": String(localized: "Layouts")
        case "Windows": String(localized: "Windows")
        case "Expand": String(localized: "Views and expand")
        case "Dock": String(localized: "Dock mode")
        default: String(localized: "Snapping")
        }
    }

    var sub: String? {
        switch self {
        case .nextTab: String(localized: "Within the focused tab group")
        case .focus: String(localized: "H J K L work like the arrows. Past the last window, the display that way.")
        case .moveWindow: String(localized: "Trades places with the window that way. H J K L work like the arrows.")
        case .wider: String(localized: "Steps through half, two thirds, 90% and the full width.")
        case .narrower: String(localized: "Back down the same steps, to half the width.")
        case .putBack: String(localized: "For apps that move or resize their own windows.")
        case .goView: String(localized: "Hold the modifiers and press a number from 1 to 9.")
        case .saveView: String(localized: "Saves what you're looking at, to come back to with the number.")
        case .everything: String(localized: "Every window on every display, your layouts along the top.")
        default: nil
        }
    }

    /// The keys a grouped row covers, in order; nil for a single-key row.
    func keys(iso: Bool) -> [Int]? {
        switch self {
        case .switchLayout, .sendLayout, .goView, .saveView: Hotkeys.digitKeys
        case .halvesLR: [kVK_LeftArrow, kVK_RightArrow]
        case .halvesTB: [kVK_UpArrow, kVK_DownArrow]
        case .quarters: [kVK_ANSI_U, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K]
        // ISO keyboards use the < key (left of Z) for Center Third.
        case .thirds: [kVK_ANSI_D, iso ? kVK_ANSI_Grave : kVK_ANSI_F, kVK_ANSI_G]
        case .twoThirds: [kVK_ANSI_E, kVK_ANSI_T]
        // Order: left, right, up, down, then H L K J for the same four (vi keys).
        case .focus, .moveWindow: Self.directionKeys
        default: nil
        }
    }

    var defaultCombo: Combo {
        let co = controlKey | optionKey
        switch self {
        case .wheel: return Combo(key: kVK_Space, mods: co)
        case .layoutsBar: return Combo(key: kVK_UpArrow, mods: optionKey)
        case .switchLayout: return Combo(key: -1, mods: optionKey)
        case .sendLayout: return Combo(key: -1, mods: optionKey | shiftKey)
        case .saveWorkspace: return Combo(key: kVK_ANSI_S, mods: co)
        case .cycleLayouts: return Combo(key: kVK_Tab, mods: optionKey)
        case .emptyLayout: return Combo(key: kVK_ANSI_N, mods: optionKey)
        // ⌃⌥⌘ + arrows: ⌘⌥I and ⌘⌥J would take over browsers' developer tools.
        case .focus: return Combo(key: -1, mods: controlKey | optionKey | cmdKey)
        case .moveWindow: return Combo(key: -1, mods: co | shiftKey)
        case .wider: return Combo(key: kVK_ANSI_W, mods: co)
        case .narrower: return Combo(key: kVK_ANSI_W, mods: co | shiftKey)
        case .center: return Combo(key: kVK_ANSI_C, mods: co)
        case .putBack: return Combo(key: kVK_ANSI_B, mods: co)
        case .nextDisplay: return Combo(key: kVK_ANSI_M, mods: co)
        case .nextTab: return Combo(key: kVK_Tab, mods: controlKey)
        case .maximize: return Combo(key: kVK_Return, mods: co)
        case .retile: return Combo(key: kVK_ANSI_R, mods: co)
        case .everything: return Combo(key: kVK_ANSI_O, mods: co)
        case .stepIn: return Combo(key: kVK_ANSI_Equal, mods: co)
        case .stepOut: return Combo(key: kVK_ANSI_Minus, mods: co)
        case .frame: return Combo(key: kVK_ANSI_Z, mods: co)
        case .back: return Combo(key: kVK_ANSI_LeftBracket, mods: co)
        case .forward: return Combo(key: kVK_ANSI_RightBracket, mods: co)
        case .goView: return Combo(key: -1, mods: co)
        case .saveView: return Combo(key: -1, mods: co | shiftKey)
        case .desktop: return Combo(key: kVK_ANSI_H, mods: co)
        case .arrange: return Combo(key: kVK_ANSI_A, mods: co)
        case .split: return Combo(key: kVK_ANSI_N, mods: co)
        case .float: return Combo(key: kVK_ANSI_L, mods: co)
        default: return Combo(key: -1, mods: co)
        }
    }

    var isGroup: Bool { defaultCombo.key == -1 }

    /// The arrows, then H L K J. Key i goes the way `Heading.allCases[i % 4]` says.
    static let directionKeys = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
                                kVK_ANSI_H, kVK_ANSI_L, kVK_ANSI_K, kVK_ANSI_J]
}

extension DeskState {
    /// The combo in effect for a row, or nil if it was cleared.
    func combo(_ id: ShortcutID) -> Combo? {
        clearedShortcuts.contains(id.rawValue) ? nil : shortcuts[id.rawValue] ?? id.defaultCombo
    }

    /// Every (key, modifiers) a row registers.
    func bindings(_ id: ShortcutID) -> [Combo] {
        guard let c = combo(id) else { return [] }
        return id.keys(iso: isoKeyboard).map { $0.map { Combo(key: $0, mods: c.mods) } } ?? [c]
    }
}

// MARK: - Names

enum KeyNames {
    static func modifiers(_ m: Int) -> [String] {
        var out: [String] = []
        if m & controlKey != 0 { out.append("⌃") }
        if m & optionKey != 0 { out.append("⌥") }
        if m & shiftKey != 0 { out.append("⇧") }
        if m & cmdKey != 0 { out.append("⌘") }
        return out
    }

    private static let special: [Int: String] = [
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Return: "↩", kVK_Space: String(localized: "Space"),
        kVK_Tab: "Tab", kVK_Escape: "esc", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]", kVK_ANSI_Equal: "=", kVK_ANSI_Minus: "-", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_Grave: "`", kVK_ISO_Section: "§",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]

    /// The character the current keyboard layout puts on a key (so an AZERTY A shows as A), else a symbol.
    static func key(_ code: Int, iso: Bool = false) -> String {
        if code == kVK_ANSI_Grave, iso { return "<" }
        if let s = special[code] { return s }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var dead: UInt32 = 0, length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                           UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    /// Keycaps for a row, the way the design draws them: one per modifier, then the key or keys.
    static func caps(_ id: ShortcutID, _ c: Combo, iso: Bool) -> [String] {
        let keys: String
        if let ks = id.keys(iso: iso) {
            if [.switchLayout, .sendLayout, .goView, .saveView].contains(id) {
                keys = "1…9"
            } else if ks == ShortcutID.directionKeys {
                keys = "← → ↑ ↓  " + [kVK_ANSI_H, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L].map { key($0, iso: iso) }.joined(separator: " ")
            } else {
                keys = ks.map { key($0, iso: iso) }.joined(separator: " ")
            }
        } else {
            keys = key(c.key, iso: iso)
        }
        // U+2066…U+2069 isolate each cap left to right, so "1…9" and "← →" don't flip in right-to-left languages.
        return (modifiers(c.mods) + [keys]).map { "\u{2066}\($0)\u{2069}" }
    }

    static func carbon(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        return m
    }
}

// MARK: - Recording and conflicts

/// Shared by Settings and AppDelegate: which row is recording, and which rows clash.
final class ShortcutCenter: ObservableObject {
    @Published var recording: ShortcutID?
    /// Row → "Also used by Quarters" or "Already used by another app".
    @Published var conflicts: [ShortcutID: String] = [:]
    /// A message from the last recording, such as "Quarters was ⌃⌥U; that has no shortcut now."
    @Published var notice: String?
    var suspend: () -> Void = {}
    var resume: () -> Void = {}
    private var monitor: Any?

    func record(_ id: ShortcutID, store: Store, engine: Engine) {
        stop()
        recording = id
        suspend()  // Bower's own hotkeys would swallow the keys being recorded
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let id = self.recording else { return e }
            let mods = KeyNames.carbon(e.modifierFlags)
            switch Int(e.keyCode) {
            case kVK_Escape: self.stop()
            case kVK_Delete: engine.setShortcut(id, nil); self.stop()
            case kVK_Function, kVK_CapsLock, kVK_Help:
                self.notice = String(localized: "That key isn't for Bower.")
                NSSound.beep()
            default:
                // A combo needs ⌃, ⌥ or ⌘, so plain typing (and ⇧ with a letter) is never taken over.
                guard mods & (controlKey | optionKey | cmdKey) != 0 else {
                    self.notice = String(localized: "Shortcuts need ⌃, ⌥ or ⌘.")
                    NSSound.beep()
                    return nil
                }
                let combo = Combo(key: id.isGroup ? -1 : Int(e.keyCode), mods: mods)
                let st = store.state
                if id.isGroup, let other = ShortcutID.allCases.first(where: { $0 != id && $0.isGroup && st.combo($0)?.mods == mods
                                                                       && $0.keys(iso: st.isoKeyboard) == id.keys(iso: st.isoKeyboard) }) {
                    // Two rows with the same keys (numbers, or arrows) can't share modifiers.
                    self.notice = id.keys(iso: st.isoKeyboard) == Hotkeys.digitKeys
                        ? String(localized: "\(KeyNames.modifiers(mods).joined()) with a number is \(other.title). Change that first.")
                        : String(localized: "\(KeyNames.modifiers(mods).joined()) with the arrows is \(other.title). Change that first.")
                    NSSound.beep()
                    return nil
                }
                self.notice = nil
                // Taking a key moves it here: the row that had it is left without one, and says so.
                let mine = id.keys(iso: st.isoKeyboard).map { $0.map { Combo(key: $0, mods: mods) } } ?? [combo]
                for other in ShortcutID.allCases where other != id && !st.bindings(other).filter(mine.contains).isEmpty {
                    let had = st.combo(other).map { KeyNames.caps(other, $0, iso: st.isoKeyboard).joined() } ?? ""
                    engine.setShortcut(other, nil)
                    self.notice = String(localized: "\(other.title) was \(had); that has no shortcut now.")
                }
                engine.setShortcut(id, combo)
                self.stop()
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil { recording = nil; resume() }
    }
}

extension Engine {
    /// nil clears the row.
    func setShortcut(_ id: ShortcutID, _ c: Combo?) {
        store.update { st in
            if let c {
                st.clearedShortcuts.remove(id.rawValue)
                st.shortcuts[id.rawValue] = c == id.defaultCombo ? nil : c
            } else {
                st.clearedShortcuts.insert(id.rawValue)
            }
        }
        onShortcutsChanged()
    }

    func resetShortcuts() {
        store.update { $0.shortcuts = [:]; $0.clearedShortcuts = [] }
        onShortcutsChanged()
    }

    func setISO(_ iso: Bool) {
        store.update { $0.isoKeyboard = iso }
        onShortcutsChanged()
    }
}
