import AppKit

/// What the newer appearance and screen settings change outside the Settings window, applied as they change.
private enum Applied {
    static var appearance: BowerAppearance?
    static var reserved: ReservedEdges?
    static var rearrange: DispatchWorkItem?
}

extension AppDelegate {
    func applyExtras() {
        let p = store.state.prefs
        if p.appearance != Applied.appearance {
            Applied.appearance = p.appearance
            switch p.appearance {
            case .automatic: NSApp.appearance = nil
            case .light: NSApp.appearance = NSAppearance(named: .aqua)
            case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
        guard AX.trusted else { return }
        FocusRing.shared.refresh()
        let r = p.reserved
        guard r != Applied.reserved else { return }
        let first = Applied.reserved == nil
        Applied.reserved = r
        guard !first else { return }
        // A slider sends many changes; arrange once it rests.
        Applied.rearrange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            for s in NSScreen.screens { self.engine.arrange(s) }
            self.tabs.applyAll()
        }
        Applied.rearrange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }
}

/// A light tap on the trackpad, for a moment that's done (Accessibility allowed, setup finished).
enum Haptic {
    static func done() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
}
