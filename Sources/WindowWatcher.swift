import AppKit

/// Reports when any app opens or closes a window, through per-app AX observers (Accessibility only).
/// Bursts are coalesced: `onChange` runs once, 150 ms after the last event.
final class WindowWatcher {
    var onChange: () -> Void = {}
    private var observers: [pid_t: AXObserver] = [:]
    private var pending: DispatchWorkItem?

    func start() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { observe(app) }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
            guard let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            // An app's AX interface isn't ready the instant it launches.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self?.observe(app); self?.changed() }
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

    private func observe(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { return }
        var obs: AXObserver?
        guard AXObserverCreate(pid, { _, element, note, refcon in
            let me = Unmanaged<WindowWatcher>.fromOpaque(refcon!).takeUnretainedValue()
            // A new window gets its own "destroyed" registration so closing it is reported too.
            if note as String == kAXWindowCreatedNotification { me.watchDestroyed(element) }
            me.changed()
        }, &obs) == .success, let obs else { return }
        let el = AXUIElementCreateApplication(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for note in [kAXWindowCreatedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
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

    private func changed() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
