import AppKit

/// Reports when any app opens or closes a window, through per-app AX observers (Accessibility only).
/// Bursts are coalesced: `onChange` runs once, 150 ms after the last event.
final class WindowWatcher {
    var onChange: () -> Void = {}
    /// A window was resized (by anyone; Bower's own writes are told apart by `AX.recentlyWrote`).
    var onResized: (AXUIElement) -> Void = { _ in }
    /// When a window last closed: macOS then activates some other app on its own, which isn't the user picking it.
    private(set) var lastClosed = Date.distantPast
    private var observers: [pid_t: AXObserver] = [:]
    private var pending: DispatchWorkItem?

    func start() {
        for (pid, _) in AX.apps() { observe(pid) }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            // An app's AX interface isn't ready the instant it launches.
            // A launcher-script app is announced with pid -1, so look the apps up again rather than trusting this one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { for (pid, _) in AX.apps() { self?.observe(pid) }; self?.changed() }
        }
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.stop(app.processIdentifier)
            self?.changed()
        }
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.changed() }
        }
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, { _, element, note, refcon in
            let me = Unmanaged<WindowWatcher>.fromOpaque(refcon!).takeUnretainedValue()
            // A new window gets its own "destroyed" registration so closing it is reported too.
            if note as String == kAXWindowCreatedNotification { me.watchDestroyed(element) }
            if note as String == kAXUIElementDestroyedNotification { me.lastClosed = Date() }
            if note as String == kAXWindowResizedNotification { me.resized(element); return }
            me.changed()
        }, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for note in [kAXWindowCreatedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
                     kAXWindowResizedNotification] {
            AXObserverAddNotification(obs, el, note as CFString, me)
        }
        var raw: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXWindowsAttribute as CFString, &raw) == .success, let wins = raw as? [AXUIElement] {
            for w in wins { AXObserverAddNotification(obs, w, kAXUIElementDestroyedNotification as CFString, me) }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observers[pid] = obs
    }

    private func watchDestroyed(_ window: AXUIElement) {
        var pid: pid_t = 0
        AXUIElementGetPid(window, &pid)
        guard let obs = observers[pid] else { return }
        AXObserverAddNotification(obs, window, kAXUIElementDestroyedNotification as CFString, Unmanaged.passUnretained(self).toOpaque())
    }

    private func stop(_ pid: pid_t) {
        guard let obs = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    private var resizePending: DispatchWorkItem?

    /// A drag by a window's edge sends many; act once it has stopped for a moment.
    private func resized(_ el: AXUIElement) {
        resizePending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onResized(el) }
        resizePending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
