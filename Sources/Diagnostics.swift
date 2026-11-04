import AppKit
import OSLog
import SwiftUI

/// Bower's log: the system log (Console.app, subsystem com.truthofmatthew.Bower) plus a plain file that
/// Report a Problem attaches, ~/Library/Logs/Bower/Bower.log, kept under 1 MB.
enum Log {
    private static let logger = Logger(subsystem: "com.truthofmatthew.Bower", category: "app")
    private static let queue = DispatchQueue(label: "Bower.log")
    static let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Bower", isDirectory: true)
    static var file: URL { folder.appendingPathComponent("Bower.log") }

    static func info(_ s: String) {
        logger.info("\(s, privacy: .public)")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(s)\n"
        queue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int, size > 1_000_000 {
                try? FileManager.default.removeItem(at: folder.appendingPathComponent("Bower.old.log"))
                try? FileManager.default.moveItem(at: file, to: folder.appendingPathComponent("Bower.old.log"))
            }
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            } else {
                try? Data(line.utf8).write(to: file)
            }
        }
    }
}

/// Developer and support tools: launch arguments, dumps, a second copy, and Report a Problem.
enum Diagnostics {
    /// Where state.json lives: Application Support/Bower, or `-storeFolder <path>`, or with `-newSession` a fresh
    /// folder in Logs/Bower, so a run can start from defaults without touching your own layouts.
    static var storeDirectory: URL {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-storeFolder"), args.indices.contains(i + 1) {
            return URL(fileURLWithPath: (args[i + 1] as NSString).expandingTildeInPath, isDirectory: true)
        }
        if args.contains("-newSession") {
            let dir = Log.folder.appendingPathComponent("Session \(Int(Date().timeIntervalSince1970))", isDirectory: true)
            Log.info("STORE from a new session in \(dir.path) (-newSession)")
            return dir
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Bower", isDirectory: true)
    }

    /// `-dumpLayout` and `-dumpAX` write what Bower sees to Logs/Bower and quit; `-newSession` starts from defaults.
    static func handleLaunchArguments(store: Store, engine: Engine) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-dumpAX") { dumpAX(); return true }
        if args.contains("-dumpLayout") { dumpLayout(store.state); return true }
        return false
    }

    @discardableResult
    static func dumpAX() -> URL {
        let wins = AX.windows().map { w -> [String: Any] in
            var d: [String: Any] = ["key": w.key, "app": w.appName, "bundleID": w.bundleID ?? "", "title": w.title, "pid": w.pid]
            if let f = w.frame { d["frame"] = NSStringFromRect(f) }
            if let doc = w.document { d["document"] = doc }
            if let id = w.identifier { d["identifier"] = id }
            d["space"] = SkyLight.space(of: w.id).map(String.init) ?? ""
            return d
        }
        let url = Log.folder.appendingPathComponent("ax.json")
        write(wins, to: url)
        return url
    }

    @discardableResult
    static func dumpLayout(_ st: DeskState) -> URL {
        let url = Log.folder.appendingPathComponent("layout.json")
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: Log.folder, withIntermediateDirectories: true)
        try? enc.encode(redacted(st)).write(to: url)
        return url
    }

    private static func write(_ obj: Any, to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) { try? d.write(to: url) }
    }

    /// Window titles can be private (mail subjects, documents); a report keeps their length, not their words.
    static func redacted(_ st: DeskState) -> DeskState {
        var s = st
        func hide(_ r: inout WindowRecord) { r.title = String(repeating: "•", count: min(r.title.count, 12)) }
        for k in s.records.keys { hide(&s.records[k]!) }
        for i in s.orphans.indices { hide(&s.orphans[i]) }
        for i in s.prefs.closed.indices { hide(&s.prefs.closed[i]) }
        for i in s.workspaces.indices { for j in s.workspaces[i].windows.indices { hide(&s.workspaces[i].windows[j]) } }
        return s
    }

    /// Quits other running copies of Bower, so two never move the same windows.
    static func quitOtherCopies() {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app.processIdentifier != me {
            Log.info("QUIT other copy pid \(app.processIdentifier)")
            app.terminate()
        }
    }

    static var systemSummary: String {
        let v = ProcessInfo.processInfo.operatingSystemVersionString
        let app = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let displays = NSScreen.screens.map { "\($0.localizedName) \(Int($0.frame.width))×\(Int($0.frame.height))" }.joined(separator: ", ")
        return """
        Bower \(app) (\(build))
        macOS \(v)
        Mac \(String(cString: model))
        Displays: \(displays)
        Accessibility: \(AX.trusted ? "allowed" : "not allowed"), Screen Recording: \(Capture.allowed ? "allowed" : "not allowed")
        """
    }

    /// Writes a report folder (log, redacted state, what Bower sees) and opens a new email with it attached.
    /// Nothing is sent: the user sees all of it first, and Finder shows the folder too.
    static func report(what: String, before: String, state: DeskState) {
        let dir = Log.folder.appendingPathComponent("Report \(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let summary = "\(systemSummary)\n\nWhat happened:\n\(what)\n\nJust before:\n\(before)\n"
        try? summary.write(to: dir.appendingPathComponent("summary.txt"), atomically: true, encoding: .utf8)
        for f in [Log.file, Log.folder.appendingPathComponent("Bower.old.log")] where FileManager.default.fileExists(atPath: f.path) {
            try? FileManager.default.copyItem(at: f, to: dir.appendingPathComponent(f.lastPathComponent))
        }
        try? FileManager.default.copyItem(at: dumpLayout(state), to: dir.appendingPathComponent("layout.json"))
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        NSWorkspace.shared.activateFileViewerSelecting([dir])
        guard let mail = NSSharingService(named: .composeEmail) else { return }
        mail.recipients = ["bower@truthofmatthew.com"]
        mail.subject = "Bower problem report"
        mail.perform(withItems: [summary as NSString] + files.map { $0 as NSURL })
    }
}

/// Help › Report a Problem…: two questions, then a draft email with the details attached.
struct ReportView: View {
    let state: DeskState
    let close: () -> Void
    @State private var what = ""
    @State private var before = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report a Problem").font(.system(size: 15, weight: .semibold))
            Text("Writes an email with your Mac's details and Bower's logs attached. You see all of it before it's sent; window titles are left out.")
                .font(.system(size: 12)).foregroundStyle(Palette.label2).fixedSize(horizontal: false, vertical: true)
            Text("What happened, and what did you expect?").font(.system(size: 12, weight: .medium))
            TextEditor(text: $what).font(.system(size: 12)).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair))
            Text("What were you doing just before? (If it happens again, the steps that bring it on help most.)")
                .font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $before).font(.system(size: 12)).frame(height: 60)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair))
            HStack {
                Spacer()
                Button("Cancel", action: close).buttonStyle(BowerButton())
                Button("Write Email…") {
                    Diagnostics.report(what: what, before: before, state: state)
                    close()
                }
                .buttonStyle(BowerButton(primary: true))
                .disabled(what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .background(Palette.window)
    }
}
