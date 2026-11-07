import AppKit
import Security

// MARK: - Keychain

/// API keys, one per provider, in the login Keychain (SetAI.dc.html: "never in Bower's settings file").
enum Keychain {
    /// "api-key" is the key from before there were several providers; it stays the "Other" endpoint's.
    private static func query(_ p: AIPreset) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "Bower AI",
         kSecAttrAccount as String: p == .custom ? "api-key" : "api-key-\(p.rawValue)"]
    }

    static func key(for p: AIPreset) -> String {
        guard !p.isLocal else { return "" }
        var q = query(p)
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return "" }
        return String(decoding: d, as: UTF8.self)
    }

    static func set(_ key: String, for p: AIPreset) {
        SecItemDelete(query(p) as CFDictionary)
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        var q = query(p)
        q[kSecValueData as String] = Data(k.utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

// MARK: - Plan

/// What the model returns for a Recipe: layouts with their apps and displays, and a Window Mode per display.
struct RecipePlan: Codable, Equatable {
    struct Window: Codable, Equatable { var app: String; var display: String? }
    struct Layout: Codable, Equatable { var number: Int; var name: String; var windows: [Window] }
    struct Mode: Codable, Equatable { var display: String; var mode: String }

    var layouts: [Layout]
    var modes: [Mode]

    init(layouts: [Layout], modes: [Mode]) { self.layouts = layouts; self.modes = modes }

    /// Lenient: models drop keys they think are empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layouts = try c.decodeIfPresent([Layout].self, forKey: .layouts) ?? []
        modes = try c.decodeIfPresent([Mode].self, forKey: .modes) ?? []
    }

    var windowCount: Int { layouts.reduce(0) { $0 + $1.windows.count } }

    func mode(for display: String) -> WindowMode {
        switch modes.first(where: { $0.display.caseInsensitiveCompare(display) == .orderedSame })?.mode.lowercased() ?? "" {
        case let m where m.contains("bento"): .bento
        case let m where m.contains("tab"): .tabs
        default: .native
        }
    }

    /// Pulls the first JSON object out of a reply, ignoring prose or ``` fences around it.
    static func parse(_ reply: String) -> RecipePlan? {
        guard let start = reply.firstIndex(of: "{"), let end = reply.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(RecipePlan.self, from: Data(reply[start...end].utf8))
    }
}

// MARK: - Mentions

/// What `@` can refer to: running apps and displays ("main monitor", "side monitor" or a display's own name).
struct MentionContext {
    struct Suggestion: Identifiable, Equatable {
        enum Kind { case app, display }
        let kind: Kind
        let name: String
        let detail: String
        let icon: NSImage?
        var id: String { name }
    }

    let apps: [Suggestion]
    let displays: [Suggestion]
    let screens: [String: NSScreen]

    static func current() -> MentionContext {
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != me && $0.localizedName != nil }
            .sorted { $0.localizedName! < $1.localizedName! }
            .map { Suggestion(kind: .app, name: $0.localizedName!, detail: String(localized: "running"), icon: $0.icon) }
        var screens: [String: NSScreen] = [:]
        var displays: [Suggestion] = []
        for (i, s) in NSScreen.screens.enumerated() {
            if i < 2 {
                let alias = i == 0 ? "main monitor" : "side monitor"
                screens[alias] = s
                displays.append(Suggestion(kind: .display, name: alias, detail: s.localizedName, icon: nil))
            }
            screens[s.localizedName.lowercased()] = s
        }
        return MentionContext(apps: apps, displays: displays, screens: screens)
    }

    var known: [String] { (apps + displays).map(\.name) + Array(screens.keys) }

    func screen(_ name: String?) -> NSScreen? {
        guard let name else { return nil }
        let n = name.lowercased().replacingOccurrences(of: "@", with: "").trimmingCharacters(in: .whitespaces)
        return screens[n] ?? screens.first { n.contains($0.key) || $0.key.contains(n) }?.value
    }
}

enum Mentions {
    struct Found: Equatable { let range: NSRange; let name: String; let known: Bool }

    /// Finds `@mentions`. A mention is the longest known name after the `@`; otherwise it runs to the next
    /// " + ", " on ", " uses ", comma or line end, and is reported as unknown.
    static func find(in text: String, known: [String]) -> [Found] {
        let ns = text as NSString
        let names = known.sorted { $0.count > $1.count }
        var out: [Found] = []
        var i = 0
        while i < ns.length {
            let at = ns.range(of: "@", range: NSRange(location: i, length: ns.length - i))
            guard at.location != NSNotFound else { break }
            // NSRange counts UTF-16 units, so every length here does too.
            let rest = ns.substring(from: at.location + 1)
            let restNS = rest as NSString
            if let n = names.first(where: { rest.lowercased().hasPrefix($0.lowercased()) && boundary(rest, $0.count) }) {
                let len = (n as NSString).length
                out.append(Found(range: NSRange(location: at.location, length: len + 1), name: n, known: true))
                i = at.location + len + 1
                continue
            }
            let stops = [" + ", " on ", " uses ", ",", "\n", " —", " - "]
            let end = stops.map { restNS.range(of: $0).location }.filter { $0 != NSNotFound }.min() ?? restNS.length
            let raw = restNS.substring(to: end)
            let name = raw.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                out.append(Found(range: NSRange(location: at.location, length: (raw as NSString).length + 1), name: name, known: false))
            }
            i = at.location + 1 + end
        }
        return out
    }

    private static func boundary(_ s: String, _ n: Int) -> Bool {
        guard s.count > n else { return true }
        let c = s[s.index(s.startIndex, offsetBy: n)]
        return !(c.isLetter || c.isNumber)
    }
}

// MARK: - Client

/// One client for every OpenAI-compatible endpoint (Ollama, LM Studio, llama.cpp, OpenRouter, OpenAI…) and for Claude.
struct AIClient {
    let settings: AISettings
    let key: String

    enum Failure: LocalizedError {
        case unreachable(String), http(Int, String), notAPlan, badURL

        var errorDescription: String? {
            switch self {
            case .unreachable(let host): String(localized: "Couldn't reach \(host)")
            case .http(let code, _) where code == 401 || code == 403: String(localized: "\(code) Unauthorized · check the API key")
            case .http(let code, let msg): "HTTP \(code)\(msg.isEmpty ? "" : " · \(msg)")"
            case .notAPlan: String(localized: "The model's reply wasn't a plan")
            case .badURL: String(localized: "The endpoint URL isn't valid")
            }
        }

        var hint: String {
            switch self {
            case .unreachable: String(localized: "Check that it's running, or pick another endpoint in Settings › AI. Your recipe hasn't changed.")
            case .notAPlan: String(localized: "Try again, or pick a larger model in Settings › AI. Your recipe hasn't changed.")
            default: String(localized: "Check Settings › AI. Your recipe hasn't changed.")
            }
        }
    }

    /// "Ollama at localhost:11434", for messages.
    var hostLabel: String {
        let host = URL(string: settings.endpoint).map { "\($0.host ?? "")\($0.port.map { ":\($0)" } ?? "")" } ?? settings.endpoint
        return settings.preset == .custom ? host : String(localized: "\(settings.preset.rawValue) at \(host)")
    }

    private func request(_ path: String, body: [String: Any]? = nil, timeout: TimeInterval) throws -> URLRequest {
        guard let url = URL(string: settings.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + path) else { throw Failure.badURL }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        if settings.isAnthropic {
            r.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            if !key.isEmpty { r.setValue(key, forHTTPHeaderField: "x-api-key") }
        } else if !key.isEmpty {
            r.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            r.httpMethod = "POST"
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return r
    }

    private func send(_ r: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: r) } catch { throw Failure.unreachable(hostLabel) }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            let msg = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])
                .flatMap { ($0["error"] as? [String: Any])?["message"] as? String ?? $0["error"] as? String } ?? ""
            throw Failure.http(code, String(msg.prefix(80)))
        }
        return data
    }

    func models() async throws -> [String] {
        let data = try await send(request("/models", timeout: 8))
        let list = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        let ids = list.compactMap { $0["id"] as? String }
        guard settings.preset == .openAI else { return ids.sorted() }
        // OpenAI lists every model it has; only the chat ones can write a plan.
        let skip = ["audio", "realtime", "tts", "transcribe", "image", "search", "embedding", "moderation", "whisper", "dall-e", "instruct"]
        return ids.filter { id in (id.hasPrefix("gpt") || id.hasPrefix("o") || id.hasPrefix("chatgpt")) && !skip.contains { id.contains($0) } }
            .sorted()
    }

    /// The model to start with: the newest Sonnet for Claude, the newest full GPT for OpenAI, the only one anywhere else.
    static func suggested(_ models: [String], for p: AIPreset) -> String? {
        switch p {
        case .claude: models.last { $0.contains("sonnet") } ?? models.last
        case .openAI: models.last { $0.hasPrefix("gpt") && !$0.contains("mini") && !$0.contains("nano") } ?? models.last
        default: models.count == 1 ? models.first : nil
        }
    }

    func plan(recipe: String, context: MentionContext, layouts: [String]) async throws -> RecipePlan {
        let system = """
        You turn a Bower Recipe into a window plan. Bower has 9 layouts numbered 1 to 9; switching layouts shows that \
        layout's windows on every display. Each display has a Window Mode: "native", "bento" (auto-tiled) or "tabs".
        Reply with one JSON object and nothing else, in this shape:
        {"layouts":[{"number":1,"name":"Dev","windows":[{"app":"Code","display":"main monitor"}]}],
         "modes":[{"display":"main monitor","mode":"tabs"}]}
        Rules: write app and display names exactly as listed below when the recipe means one of them; an app that \
        isn't running may still appear, written as the recipe writes it. Number layouts in the order the recipe \
        lists them, from 1, unless the recipe gives numbers. Leave "display" out when the recipe doesn't say.
        """
        let user = """
        Running apps: \(context.apps.map(\.name).joined(separator: ", "))
        Displays: \(context.displays.map { "\($0.name) (\($0.detail))" }.joined(separator: ", "))
        Current layout names: \(layouts.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: ", "))

        Recipe:
        \(recipe)
        """
        let reply: String
        if settings.isAnthropic {
            let body: [String: Any] = ["model": settings.model, "max_tokens": 4096, "temperature": 0, "system": system,
                                       "messages": [["role": "user", "content": user]]]
            let data = try await send(request("/messages", body: body, timeout: 120))
            reply = ((((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["content"] as? [[String: Any]]) ?? [])
                .compactMap { $0["text"] as? String }.joined()
        } else {
            let body: [String: Any] = ["model": settings.model, "temperature": 0, "stream": false,
                                       "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
            let data = try await send(request("/chat/completions", body: body, timeout: 120))
            reply = (((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["choices"] as? [[String: Any]])?
                .first.flatMap { ($0["message"] as? [String: Any])?["content"] as? String } ?? ""
        }
        guard let plan = RecipePlan.parse(reply), !plan.layouts.isEmpty else { throw Failure.notAPlan }
        return plan
    }
}

// MARK: - Recipes on disk

/// Recipes are plain Markdown files in ~/Library/Application Support/Bower/Recipes.
enum RecipeFiles {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Bower/Recipes", isDirectory: true)

    static let starter = """
    ## Projects & Layouts
    - Dev — @Terminal on @main monitor
    - Comms — @Messages on @main monitor

    ## Window modes
    - @main monitor uses Bento Box
    """

    static func names() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".md") }.map { String($0.dropLast(3)) }.sorted()
    }

    static func read(_ name: String) -> String? { try? String(contentsOf: url(name), encoding: .utf8) }

    static func write(_ name: String, _ text: String) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? text.write(to: url(name), atomically: true, encoding: .utf8)
    }

    static func delete(_ name: String) { try? FileManager.default.removeItem(at: url(name)) }

    /// Slashes and colons can't be in a file name.
    private static func url(_ name: String) -> URL {
        folder.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") + ".md")
    }
}

// MARK: - Applying a plan

extension Engine {
    /// Names the layouts, assigns each app's windows (moving them to their display), routes the apps so
    /// windows that open later land in the same layout, sets Window Modes, then shows the first layout.
    func apply(_ plan: RecipePlan, context: MentionContext) {
        let wins = AX.windows()
        let layoutNumbers = plan.layouts.map { $0.number - 1 }.filter { (0..<9).contains($0) }
        for l in plan.layouts {
            let n = l.number - 1
            guard (0..<9).contains(n) else { continue }
            store.update { $0.layouts[n].name = l.name }
            for pw in l.windows {
                if let id = Self.bundleID(forApp: pw.app) { store.update { $0.routes[id] = n } }
                for w in wins where w.appName.caseInsensitiveCompare(pw.app) == .orderedSame {
                    store.update { $0.assignment[w.key] = n }
                    if let s = context.screen(pw.display) { move(w, to: s) }
                }
            }
        }
        for m in plan.modes {
            guard let s = context.screen(m.display) else { continue }
            let mode = plan.mode(for: m.display)
            for n in layoutNumbers { store.update { $0.layouts[n].modes[s.uuid] = mode } }
        }
        if let first = layoutNumbers.first { switchTo(first) } else { onChange() }
    }

    /// Keeps the window's size (shrunk to fit) and centres it on the target display.
    private func move(_ w: Win, to s: NSScreen) {
        guard let f = w.frame else { return }
        let parked = isParked(f)
        let current = parked ? state.saved[w.key] ?? f : f
        guard NSScreen.containing(ax: current) != s else { return }
        let v = s.axUsableFrame
        let size = CGSize(width: min(current.width, v.width), height: min(current.height, v.height))
        let target = CGRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height)
        if parked { store.update { $0.saved[w.key] = target } } else { w.setFrame(target) }
    }

    /// For apps that aren't running: finds them in the usual Applications folders by name.
    static func bundleID(forApp name: String) -> String? {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame }) {
            return app.bundleIdentifier
        }
        let dirs = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                    NSHomeDirectory() + "/Applications"]
        for d in dirs {
            if let b = Bundle(path: "\(d)/\(name).app") { return b.bundleIdentifier }
        }
        return nil
    }
}
