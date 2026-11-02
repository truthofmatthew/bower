import SwiftUI

/// Recipe.dc.html / RecipePreview.dc.html colours.
private enum RC {
    private static func dyn(_ d: NSColor, _ l: NSColor) -> NSColor { NSColor(name: nil) { Theme.isDark($0) ? d : l } }
    static let sheet = dyn(Theme.hex(0x232325), Theme.hex(0xF2F2F4))
    static let editor = dyn(Theme.hex(0x1C1C1E), Theme.hex(0xFFFFFF))
    static let menu = dyn(Theme.rgba(44, 44, 48, 0.92), Theme.rgba(250, 250, 252, 0.94))
    static let label = dyn(Theme.rgba(255, 255, 255, 0.92), Theme.rgba(0, 0, 0, 0.88))
    static let label3 = dyn(Theme.rgba(235, 235, 245, 0.38), Theme.rgba(60, 60, 67, 0.40))
    static let accent = dyn(Theme.hex(0x3FD3C2), Theme.hex(0x0B7A72))
    static let accentFill = dyn(Theme.rgba(63, 211, 194, 0.20), Theme.rgba(11, 122, 114, 0.14))
    static let warn = dyn(Theme.hex(0xFFC94D), Theme.hex(0x8A5800))
    // Preview pane
    static let paneBG = dyn(Theme.hex(0x1A1A1C), Theme.hex(0xFAFAFB))
    static let paneFill = dyn(Theme.rgba(255, 255, 255, 0.06), Theme.rgba(0, 0, 0, 0.05))
    static let screen = dyn(Theme.hex(0x2B3348), Theme.hex(0xC3D3E3))
    static let strip = dyn(Theme.hex(0x202022), Theme.hex(0xE4E4E7))
    static let tile = dyn(Theme.hex(0x2E2E31), Theme.hex(0xFFFFFF))
    static let warnBG = dyn(Theme.rgba(255, 201, 77, 0.12), Theme.rgba(255, 190, 40, 0.20))
}

private extension Color { init(_ c: NSColor) { self.init(nsColor: c) } }

// MARK: - Model

final class RecipeModel: ObservableObject {
    enum Phase { case idle, loading, ready(RecipePlan), failed(AIClient.Failure) }

    @Published var name: String
    @Published var text: String
    @Published var phase: Phase = .idle
    let context = MentionContext.current()
    private var savedName: String?
    private let engine: Engine

    init(name: String?, engine: Engine) {
        self.engine = engine
        savedName = name
        self.name = name ?? String(localized: "New Recipe")
        text = name.flatMap(RecipeFiles.read) ?? RecipeFiles.starter
    }

    var ai: AISettings { engine.state.ai }

    var mentions: [Mentions.Found] { Mentions.find(in: text, known: context.known) }

    /// Apps the recipe or the plan names that aren't running: "@Figma isn't running."
    var warnings: [String] {
        var names = mentions.filter { !$0.known }.map(\.name)
        if case .ready(let plan) = phase {
            let running = Set(context.apps.map { $0.name.lowercased() })
            names += plan.layouts.flatMap(\.windows).map(\.app).filter { !running.contains($0.lowercased()) }
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0.lowercased()).inserted }
    }

    func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if let old = savedName, old != n { RecipeFiles.delete(old) }
        RecipeFiles.write(n, text)
        savedName = n
    }

    func preview() {
        save()
        phase = .loading
        let client = AIClient(settings: ai, key: Keychain.apiKey)
        let text = text, context = context, layouts = engine.state.layouts.map(\.name)
        Task { @MainActor in
            do { phase = .ready(try await client.plan(recipe: text, context: context, layouts: layouts)) } catch let f as AIClient.Failure {
                phase = .failed(f)
            } catch {
                phase = .failed(.notAPlan)
            }
        }
    }

    func apply() {
        guard case .ready(let plan) = phase else { return }
        save()
        engine.apply(plan, context: context)
    }
}

// MARK: - Sheet

/// Recipe.dc.html: 1020 × 604. Header 48, Markdown editor beside a 480 pt preview, footer 56.
struct RecipeEditorView: View {
    @ObservedObject var model: RecipeModel
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Recipe").fontWeight(.semibold)
                TextField("Name", text: $model.name)
                    .textFieldStyle(.plain).padding(.horizontal, 9).frame(width: 240, height: 28)
                    .background(Color(RC.editor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair, lineWidth: 0.5))
                    .accessibilityLabel("Recipe name")
                Spacer()
                Text(endpointLabel).font(.system(size: 12)).foregroundStyle(Palette.label2)
            }
            .padding(.horizontal, 16).frame(height: 48)
            .overlay(alignment: .bottom) { Palette.hair.frame(height: 1) }

            HStack(spacing: 0) {
                RecipeTextView(model: model)
                    .overlay(alignment: .trailing) { Palette.hair.frame(width: 1) }
                RecipePreviewPane(model: model).frame(width: 480)
            }
            .frame(maxHeight: .infinity)

            HStack(spacing: 8) {
                Text(footer).font(.system(size: 12)).foregroundStyle(Palette.label2)
                Spacer()
                Button("Cancel") { model.save(); close() }.buttonStyle(BowerButton()).keyboardShortcut(.cancelAction)
                Button("Preview", action: model.preview).buttonStyle(BowerButton())
                    .disabled(!model.ai.configured || isLoading)
                Button("Apply") { model.apply(); close() }.buttonStyle(BowerButton(primary: true))
                    .disabled(!hasPlan).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16).frame(height: 56)
            .overlay(alignment: .top) { Palette.hair.frame(height: 1) }
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.label)
        .frame(width: 1020, height: 604)
        .background(Color(RC.sheet))
    }

    private var isLoading: Bool { if case .loading = model.phase { true } else { false } }
    private var hasPlan: Bool { if case .ready = model.phase { true } else { false } }

    /// "llama3.1:8b · localhost"
    private var endpointLabel: String {
        guard model.ai.configured else { return String(localized: "No AI endpoint · Settings › AI") }
        return "\(model.ai.model) · \(URL(string: model.ai.endpoint)?.host ?? model.ai.endpoint)"
    }

    private var footer: String {
        switch model.phase {
        case .idle: return model.ai.configured ? String(localized: "Write the desk you want, then Preview.") : String(localized: "Set up an endpoint in Settings › AI to preview.")
        case .loading: return String(localized: "Planning…")
        case .failed: return String(localized: "No plan")
        case .ready(let plan):
            let w = model.warnings.count
            if w > 0 { return w == 1 ? String(localized: "1 warning · Apply still works") : String(localized: "\(w) warnings · Apply still works") }
            return plan.layouts.count == 1 ? String(localized: "Plan ready · 1 layout") : String(localized: "Plan ready · \(plan.layouts.count) layouts")
        }
    }
}

// MARK: - Editor

/// Plain Markdown in SF Mono 13/24: headings bold, list dashes dimmed, known @mentions tinted,
/// unknown ones underlined in the warning colour. Typing @ opens suggestions.
struct RecipeTextView: NSViewRepresentable {
    @ObservedObject var model: RecipeModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        // TextKit 1, so WavyLayoutManager can draw the design's wavy underline.
        let storage = NSTextStorage()
        let layout = WavyLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = NSTextView(frame: .zero, textContainer: container)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = tv
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.backgroundColor = RC.editor
        tv.insertionPointColor = RC.accent
        tv.textContainerInset = NSSize(width: 12, height: 14)
        tv.string = model.text
        tv.setAccessibilityLabel(String(localized: "Recipe text"))
        scroll.drawsBackground = true
        scroll.backgroundColor = RC.editor
        context.coordinator.textView = tv
        context.coordinator.highlight()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: RecipeModel
        weak var textView: NSTextView?
        private let popup = SuggestionPopup()
        private var atLocation: Int?

        init(model: RecipeModel) { self.model = model }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            model.text = tv.string
            highlight()
            updateSuggestions()
        }

        func highlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let text = tv.string as NSString
            let all = NSRange(location: 0, length: text.length)
            let para = NSMutableParagraphStyle()
            para.minimumLineHeight = 24
            para.maximumLineHeight = 24
            let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            storage.beginEditing()
            storage.setAttributes([.font: mono, .foregroundColor: RC.label, .paragraphStyle: para, .baselineOffset: 4], range: all)
            text.enumerateSubstrings(in: all, options: .byLines) { line, range, _, _ in
                guard let line else { return }
                if line.hasPrefix("#") {
                    storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: 13, weight: .bold), range: range)
                } else if let dash = line.range(of: "^\\s*-", options: .regularExpression) {
                    let r = NSRange(dash, in: line)
                    storage.addAttribute(.foregroundColor, value: RC.label3, range: NSRange(location: range.location + r.location, length: r.length))
                }
            }
            for m in Mentions.find(in: tv.string, known: model.context.known) where NSMaxRange(m.range) <= text.length {
                if m.known {
                    storage.addAttributes([.foregroundColor: RC.accent, .backgroundColor: RC.accentFill], range: m.range)
                } else {
                    storage.addAttributes([.foregroundColor: RC.warn, .wavyUnderline: RC.warn,
                                           .underlineStyle: NSUnderlineStyle.single.rawValue], range: m.range)
                }
            }
            storage.endEditing()
            tv.typingAttributes = [.font: mono, .foregroundColor: RC.label, .paragraphStyle: para, .baselineOffset: 4]
        }

        /// The word being typed after an @ on the same line, if any.
        private func updateSuggestions() {
            guard let tv = textView else { return }
            let caret = tv.selectedRange().location
            let text = tv.string as NSString
            let lineStart = text.lineRange(for: NSRange(location: max(caret - 1, 0), length: 0)).location
            let before = text.substring(with: NSRange(location: lineStart, length: caret - lineStart))
            guard let at = before.range(of: "@", options: .backwards) else { return hide() }
            let query = String(before[at.upperBound...])
            guard query.count <= 30, !query.contains("  ") else { return hide() }
            let q = query.lowercased()
            let match: (MentionContext.Suggestion) -> Bool = { q.isEmpty || $0.name.lowercased().contains(q) }
            let apps = Array(model.context.apps.filter(match).prefix(5))
            let displays = model.context.displays.filter(match)
            guard !(apps.isEmpty && displays.isEmpty), !(apps + displays).contains(where: { $0.name.lowercased() == q }) else { return hide() }
            atLocation = lineStart + (before as NSString).range(of: "@", options: .backwards).location
            let rect = tv.firstRect(forCharacterRange: NSRange(location: atLocation!, length: 1), actualRange: nil)
            popup.show(apps: apps, displays: displays, below: rect, parent: tv.window) { [weak self] s in self?.accept(s) }
        }

        private func hide() {
            atLocation = nil
            popup.hide()
        }

        private func accept(_ s: MentionContext.Suggestion) {
            guard let tv = textView, let at = atLocation else { return }
            let caret = tv.selectedRange().location
            let range = NSRange(location: at + 1, length: max(caret - at - 1, 0))
            if tv.shouldChangeText(in: range, replacementString: s.name + " ") {
                tv.replaceCharacters(in: range, with: s.name + " ")
                tv.didChangeText()
            }
            hide()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard popup.isVisible else { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)): popup.move(1)
            case #selector(NSResponder.moveUp(_:)): popup.move(-1)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                if let s = popup.selected { accept(s) }
            case #selector(NSResponder.cancelOperation(_:)): hide()
            default: return false
            }
            return true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            if popup.isVisible { updateSuggestions() }
        }
    }
}

extension NSAttributedString.Key {
    /// Marks an unknown @mention; WavyLayoutManager draws its underline as a wave in this colour.
    static let wavyUnderline = NSAttributedString.Key("BowerWavyUnderline")
}

/// `.at.bad`: `text-decoration: underline wavy`, offset 3 pt below the baseline.
final class WavyLayoutManager: NSLayoutManager {
    override func drawUnderline(forGlyphRange glyphRange: NSRange, underlineType: NSUnderlineStyle, baselineOffset: CGFloat,
                                lineFragmentRect: NSRect, lineFragmentGlyphRange: NSRange, containerOrigin: NSPoint) {
        let chars = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard let storage = textStorage, chars.location < storage.length,
              let color = storage.attribute(.wavyUnderline, at: chars.location, effectiveRange: nil) as? NSColor,
              let container = textContainers.first else {
            return super.drawUnderline(forGlyphRange: glyphRange, underlineType: underlineType, baselineOffset: baselineOffset,
                                       lineFragmentRect: lineFragmentRect, lineFragmentGlyphRange: lineFragmentGlyphRange, containerOrigin: containerOrigin)
        }
        let r = boundingRect(forGlyphRange: glyphRange, in: container)
        let baseline = lineFragmentRect.minY + location(forGlyphAt: glyphRange.location).y + containerOrigin.y
        let y = baseline + 3, x0 = r.minX + containerOrigin.x, x1 = r.maxX + containerOrigin.x
        let wave = NSBezierPath()
        wave.move(to: NSPoint(x: x0, y: y))
        var x = x0
        while x < x1 {  // 4 pt wavelength, 1.5 pt amplitude
            wave.curve(to: NSPoint(x: min(x + 2, x1), y: y), controlPoint1: NSPoint(x: x + 1, y: y - 1.5), controlPoint2: NSPoint(x: x + 1, y: y - 1.5))
            if x + 2 < x1 {
                wave.curve(to: NSPoint(x: min(x + 4, x1), y: y), controlPoint1: NSPoint(x: x + 3, y: y + 1.5), controlPoint2: NSPoint(x: x + 3, y: y + 1.5))
            }
            x += 4
        }
        wave.lineWidth = 1
        color.setStroke()
        wave.stroke()
    }
}

// MARK: - @ suggestions

/// The `.pop` listbox: 250 wide, "Apps" and "Displays" groups, 28 pt rows, the selected one filled with the accent.
final class SuggestionPopup {
    private let panel: NSPanel
    private let model = Model()

    final class Model: ObservableObject {
        @Published var apps: [MentionContext.Suggestion] = []
        @Published var displays: [MentionContext.Suggestion] = []
        @Published var index = 0
        var pick: (MentionContext.Suggestion) -> Void = { _ in }
        var all: [MentionContext.Suggestion] { apps + displays }
    }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        let host = NSHostingView(rootView: SuggestionList(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
    }

    var isVisible: Bool { panel.isVisible }
    var selected: MentionContext.Suggestion? { model.all.indices.contains(model.index) ? model.all[model.index] : nil }

    func show(apps: [MentionContext.Suggestion], displays: [MentionContext.Suggestion], below rect: NSRect, parent: NSWindow?,
              pick: @escaping (MentionContext.Suggestion) -> Void) {
        if model.apps != apps || model.displays != displays { model.index = 0 }
        model.apps = apps
        model.displays = displays
        model.pick = pick
        DispatchQueue.main.async { [self] in
            let size = panel.contentView!.fittingSize
            panel.setFrame(NSRect(x: rect.minX - 8, y: rect.minY - size.height - 4, width: size.width, height: size.height), display: true)
            if !panel.isVisible { parent?.addChildWindow(panel, ordered: .above) }
        }
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func move(_ d: Int) {
        guard !model.all.isEmpty else { return }
        model.index = (model.index + d + model.all.count) % model.all.count
    }
}

private struct SuggestionList: View {
    @ObservedObject var model: SuggestionPopup.Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !model.apps.isEmpty { header(String(localized: "Apps")) }
            ForEach(Array(model.apps.enumerated()), id: \.element.id) { i, s in row(s, i) }
            if !model.displays.isEmpty { header(String(localized: "Displays")) }
            ForEach(Array(model.displays.enumerated()), id: \.element.id) { i, s in row(s, model.apps.count + i) }
        }
        .padding(5)
        .frame(width: 250)
        .background(Color(RC.menu), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.hair, lineWidth: 0.5))
        .accessibilityLabel("Suggestions")
    }

    private func header(_ t: String) -> some View {
        Text(verbatim: t).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.label2)
            .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 2)
    }

    private func row(_ s: MentionContext.Suggestion, _ i: Int) -> some View {
        let on = i == model.index
        return HStack(spacing: 8) {
            if let icon = s.icon {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Glyph(d: "M2.5 3.5h15v10h-15zM7 17h6M10 13.5V17", grid: 20, size: 16)
            }
            Text(s.name).lineLimit(1)
            Spacer(minLength: 4)
            Text(s.detail).font(.system(size: 11)).lineLimit(1).opacity(on ? 0.8 : 1)
                .foregroundStyle(on ? Palette.onAccent : Palette.label2)
        }
        .font(.system(size: 13))
        .foregroundStyle(on ? Palette.onAccent : Palette.label)
        .padding(.horizontal, 8).frame(height: 28)
        .background(on ? Palette.accent : .clear, in: RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { model.pick(s) }
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - Preview pane

/// RecipePreview.dc.html: one diagram per display with its Window Mode, then warnings or the error.
struct RecipePreviewPane: View {
    @ObservedObject var model: RecipeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preview").fontWeight(.semibold)
                Spacer()
                Text(summary).font(.system(size: 12)).foregroundStyle(Palette.label2)
            }
            switch model.phase {
            case .idle:
                skeleton
            case .loading:
                skeleton
                HStack(spacing: 8) { Spinner(); Text("Planning with \(model.ai.model)…") }
                    .font(.system(size: 12)).foregroundStyle(Palette.label2)
            case .ready(let plan):
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(groups(plan).enumerated()), id: \.offset) { i, g in display(g, tall: i == 0) }
                        ForEach(model.warnings, id: \.self) { warning($0) }
                    }
                }
            case .failed(let f):
                failure(f)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(RC.paneBG))
    }

    private var skeleton: some View {
        VStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8).fill(Color(RC.paneFill)).frame(height: 150)
            RoundedRectangle(cornerRadius: 8).fill(Color(RC.paneFill)).frame(height: 150)
        }
    }

    private var summary: String {
        switch model.phase {
        case .idle: return String(localized: "Not previewed")
        case .loading: return String(localized: "Reading \(model.text.split(separator: "\n").count) lines…")
        case .failed: return String(localized: "No plan")
        case .ready(let plan):
            let displays = groups(plan).count, w = model.warnings.count
            return [count(plan.layouts.count, one: String(localized: "1 layout"), many: String(localized: "\(plan.layouts.count) layouts")),
                    count(plan.windowCount, one: String(localized: "1 window"), many: String(localized: "\(plan.windowCount) windows")),
                    w > 0 ? count(w, one: String(localized: "1 warning"), many: String(localized: "\(w) warnings"))
                          : count(displays, one: String(localized: "1 display"), many: String(localized: "\(displays) displays"))]
                .joined(separator: " · ")
        }
    }

    struct Group {
        let alias: String
        let screenName: String
        let mode: WindowMode
        let apps: [(name: String, waiting: Bool)]
        let caption: String
    }

    /// One group per display the plan uses; windows without a display go on the main one.
    private func groups(_ plan: RecipePlan) -> [Group] {
        let ctx = model.context
        let running = Set(ctx.apps.map { $0.name.lowercased() })
        let main = ctx.displays.first?.name ?? "main monitor"
        var order: [String] = []
        var byDisplay: [String: [(layout: RecipePlan.Layout, app: String)]] = [:]
        for l in plan.layouts.sorted(by: { $0.number < $1.number }) {
            for w in l.windows {
                let d = (w.display ?? main).replacingOccurrences(of: "@", with: "").lowercased()
                if byDisplay[d] == nil { order.append(d) }
                byDisplay[d, default: []].append((l, w.app))
            }
        }
        for m in plan.modes {
            let d = m.display.replacingOccurrences(of: "@", with: "").lowercased()
            if byDisplay[d] == nil { order.append(d); byDisplay[d] = [] }
        }
        return order.map { d in
            let items = byDisplay[d] ?? []
            let first = items.first?.layout.number
            let layouts = Dictionary(grouping: items, by: { $0.layout.number }).sorted { $0.key < $1.key }
            let caption = layouts.map { n, items in
                String(localized: "Layout \(n) · \(items[0].layout.name): ") + items.map { running.contains($0.app.lowercased()) ? $0.app : String(localized: "\($0.app) (waiting)") }
                    .joined(separator: ", ")
            }.joined(separator: " · ")
            return Group(alias: d, screenName: ctx.screen(d)?.localizedName ?? d,
                         mode: plan.mode(for: d),
                         apps: items.filter { $0.layout.number == first }.map { ($0.app, !running.contains($0.app.lowercased())) },
                         caption: caption.isEmpty ? String(localized: "No windows") : caption)
        }
    }

    private func display(_ g: Group, tall: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(g.screenName).fontWeight(.bold)
                Text("@\(g.alias)").foregroundStyle(Palette.label2)
                Spacer()
                Text(g.mode.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Palette.accentFill, in: Capsule())
            }
            .font(.system(size: 12))
            diagram(g).frame(height: tall ? 150 : 110)
            Text(g.caption).font(.system(size: 11)).foregroundStyle(Palette.label2)
        }
    }

    @ViewBuilder private func diagram(_ g: Group) -> some View {
        let screen = RoundedRectangle(cornerRadius: 7).fill(Color(RC.screen))
        switch g.mode {
        case .tabs:
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(g.apps.enumerated()), id: \.offset) { i, a in
                        appLabel(a.name, waiting: a.waiting)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 6).frame(height: 20)
                            .background(i == 0 ? Color(RC.tile) : .clear)
                            .overlay(alignment: .bottom) { if i == 0 { Palette.accent.frame(height: 2) } }
                    }
                }
                .background(Color(RC.strip))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 5, topTrailingRadius: 5))
                UnevenRoundedRectangle(bottomLeadingRadius: 5, bottomTrailingRadius: 5).fill(Color(RC.tile))
            }
            .padding(8).background(screen)
        default:
            GeometryReader { geo in
                let r = CGRect(origin: .zero, size: geo.size)
                let frames = g.mode == .bento ? Bento.tiles(count: g.apps.count, in: r.insetBy(dx: 2, dy: 2))
                    : g.apps.indices.map { i in CGRect(x: 8 + CGFloat(i) * 14, y: 8 + CGFloat(i) * 12, width: r.width * 0.6, height: r.height * 0.6) }
                ForEach(Array(zip(g.apps, frames).enumerated()), id: \.offset) { _, pair in
                    appLabel(pair.0.name, waiting: pair.0.waiting)
                        .padding(6)
                        .frame(width: pair.1.width, height: pair.1.height, alignment: .topLeading)
                        .background(Color(RC.tile), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(pair.0.waiting ? Color(RC.warn) : .clear, lineWidth: 1))
                        .offset(x: pair.1.minX, y: pair.1.minY)
                }
            }
            .padding(g.mode == .bento ? 6 : 0).background(screen)
        }
    }

    private func appLabel(_ name: String, waiting: Bool) -> some View {
        HStack(spacing: 5) {
            if waiting {
                RoundedRectangle(cornerRadius: 3).strokeBorder(Color(RC.warn), style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                    .frame(width: 10, height: 10)
            } else if let icon = model.context.apps.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame })?.icon {
                Image(nsImage: icon).resizable().frame(width: 10, height: 10).clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                RoundedRectangle(cornerRadius: 3).fill(Palette.fill2).frame(width: 10, height: 10)
            }
            Text(name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                .foregroundStyle(waiting ? Color(RC.warn) : Palette.label)
        }
    }

    private func warning(_ app: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Glyph(d: "M8 1.8 15 14H1zM8 6v3.6M8 11.6v.1", size: 16, width: 1.4).foregroundStyle(Color(RC.warn))
            (Text("@\(app) isn't running. ").bold().foregroundColor(Color(RC.warn))
                + Text("Apply anyway and Bower places its window when it opens."))
                .font(.system(size: 12)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(RC.warnBG), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func failure(_ f: AIClient.Failure) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Palette.danger, lineWidth: 2)
                Glyph(d: "M11 11l10 10M21 11 11 21", grid: 32, size: 28, width: 2).foregroundStyle(Palette.danger)
            }
            .frame(width: 28, height: 28)
            Text(f.errorDescription ?? "").fontWeight(.semibold)
            Text(f.hint).font(.system(size: 12)).foregroundStyle(Palette.label2).frame(maxWidth: 320)
            Button("Try Again", action: model.preview).buttonStyle(BowerButton())
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
    }
}

/// Picks the singular or plural sentence; each is its own catalog entry so every language can phrase both.
func count(_ n: Int, one: @autoclosure () -> String, many: @autoclosure () -> String) -> String { n == 1 ? one() : many() }
