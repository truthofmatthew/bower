import SwiftUI

/// SetAI.dc.html: provider, URL (local or "Other" only), model, API key (Keychain, one per provider), Test Connection.
struct AITab: View {
    @ObservedObject var store: Store
    let engine: Engine
    @State private var key = ""
    @State private var url = ""
    @State private var models: [String] = []
    @State private var status: Status = .untested

    enum Status: Equatable { case untested, testing, ok(String), failed(String) }

    private var ai: AISettings { store.state.ai }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FormGroup {
                FormRow(first: true) {
                    Text("Provider").frame(width: 110, alignment: .leading)
                    Segmented(options: AIPreset.allCases.map(\.title), selected: ai.preset.title) { name in
                        guard let p = AIPreset.allCases.first(where: { $0.title == name }), p != ai.preset else { return }
                        var a = ai
                        a.preset = p
                        if p != .custom { a.endpoint = p.endpoint }
                        a.model = ""
                        url = a.endpoint
                        key = Keychain.key(for: p)
                        models = []
                        status = .untested
                        engine.setAI(a)
                        refresh()
                    }
                    Spacer(minLength: 0)
                }
                if ai.preset.isLocal || ai.preset == .custom {
                    FormRow {
                        Text("Endpoint URL").frame(width: 110, alignment: .leading)
                        TextField("https://api.example.com/v1", text: $url)
                            .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 9).frame(height: 28)
                            .background(Palette.field, in: RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair, lineWidth: 0.5))
                            .onSubmit(saveURL)
                            .accessibilityLabel("Endpoint URL")
                    }
                }
                if !ai.preset.isLocal {
                    FormRow {
                        Text("API key").frame(width: 110, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            SecureField(ai.preset == .custom ? String(localized: "If the endpoint needs one") : String(localized: "Paste your key"), text: $key)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 9).frame(height: 28)
                                .background(Palette.field, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair, lineWidth: 0.5))
                                .onSubmit(refresh)
                                .onChange(of: key) { _, k in Keychain.set(k, for: ai.preset) }
                                .accessibilityLabel("API key")
                            HStack(spacing: 4) {
                                Image(systemName: "lock").font(.system(size: 9, weight: .medium))  // the component sheet's SF equivalent
                                Text("Stored in your login Keychain, never in Bower's settings file.")
                                if let page = ai.preset.keysPage {
                                    Link("Get a key", destination: page).foregroundStyle(Palette.accent)
                                }
                            }
                            .font(.system(size: 11)).foregroundStyle(Palette.label2)
                        }
                    }
                }
                FormRow {
                    Text("Model").frame(width: 110, alignment: .leading)
                    Menu {
                        if models.isEmpty { Button(ai.preset.isLocal ? String(localized: "No models found. Is it running?") : String(localized: "No models found. Check the key.")) {}.disabled(true) }
                        ForEach(models, id: \.self) { m in
                            Button(m) { var a = ai; a.model = m; engine.setAI(a) }
                        }
                    } label: { PopLabel(text: ai.model.isEmpty ? String(localized: "Choose a model") : ai.model, height: 28) }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                    Button(action: refresh) {
                        Glyph(d: "M13.25 2.25V5.5H10", size: 14).overlay(RetileArc().stroke(style: StrokeStyle(lineWidth: 1.5 * 14 / 16, lineCap: .round)))
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(BowerButton()).accessibilityLabel("Refresh model list")
                }
            }

            HStack(spacing: 12) {
                Button("Test Connection", action: test).buttonStyle(BowerButton())
                statusView
            }
            Text(ai.preset.isLocal ? "Recipes are sent only to this endpoint. With Ollama or LM Studio nothing leaves your Mac."
                                   : "Recipes, with the names of your running apps and displays, are sent to this provider when you run them. Nothing else is.")
                .font(.system(size: 11)).foregroundStyle(Palette.label2)
        }
        .onAppear { url = ai.endpoint; key = Keychain.key(for: ai.preset); refresh() }
    }

    @ViewBuilder private var statusView: some View {
        switch status {
        case .untested: Text("Not tested").font(.system(size: 12)).foregroundStyle(Palette.label2)
        case .testing:
            HStack(spacing: 6) { Spinner(); Text("Testing…") }.font(.system(size: 12))
        case .ok(let s):
            HStack(spacing: 6) { Text("✓").fontWeight(.bold); Text(s) }.font(.system(size: 12)).foregroundStyle(Palette.ok)
        case .failed(let s):
            HStack(spacing: 6) { Text("✕").fontWeight(.bold); Text(s) }.font(.system(size: 12)).foregroundStyle(Palette.danger)
        }
    }

    private func saveURL() {
        var a = ai
        a.endpoint = url.trimmingCharacters(in: .whitespaces)
        engine.setAI(a)
        refresh()
    }

    /// Lists the models, and picks one when none is chosen yet so a new provider works without another click.
    private func refresh() {
        let client = AIClient(settings: store.state.ai, key: key)
        Task { @MainActor in
            models = (try? await client.models()) ?? []
            if ai.model.isEmpty, let m = AIClient.suggested(models, for: ai.preset) { var a = ai; a.model = m; engine.setAI(a) }
        }
    }

    /// "Connected · 4 models · 142 ms", or the failure.
    private func test() {
        if url.trimmingCharacters(in: .whitespaces) != ai.endpoint { saveURL() }
        status = .testing
        let client = AIClient(settings: store.state.ai, key: key)
        Task { @MainActor in
            let start = Date()
            do {
                let list = try await client.models()
                models = list
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                status = .ok(list.count == 1 ? String(localized: "Connected · 1 model · \(ms) ms") : String(localized: "Connected · \(list.count) models · \(ms) ms"))
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }
}

/// `.seg`: 2 pt inset track, the selected segment raised.
struct Segmented: View {
    let options: [String]
    let selected: String
    let pick: (String) -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { o in
                Button { pick(o) } label: {
                    Text(o).font(.system(size: 12, weight: o == selected ? .medium : .regular))
                        .padding(.horizontal, 12).frame(height: 24)
                        .background {
                            if o == selected {
                                RoundedRectangle(cornerRadius: 6).fill(Palette.control)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hair, lineWidth: 0.5))
                                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(o == selected ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 8))
    }
}

/// The arc of the retile/refresh icon (its straight part is a path string).
struct RetileArc: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 16
        var p = Path()
        p.addArc(center: CGPoint(x: 8 * s, y: 8 * s), radius: 5.25 * s, startAngle: .zero, endAngle: .radians(-.pi / 4 + 2 * .pi), clockwise: false)
        return p
    }
}

/// 14 pt ring with a quarter accent arc, turning once every 0.7 s.
struct Spinner: View {
    @State private var turn = false
    var body: some View {
        ZStack {
            Circle().stroke(Palette.fill2, lineWidth: 2)
            Circle().trim(from: 0, to: 0.25).stroke(Palette.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(turn ? 270 : -90))
        }
        .frame(width: 12, height: 12)
        .onAppear {
            guard !Theme.reduceMotion else { return }
            withAnimation(.linear(duration: 0.7).repeatForever(autoreverses: false)) { turn = true }
        }
    }
}
