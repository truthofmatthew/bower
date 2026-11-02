import SwiftUI

private enum WS {
    private static func dyn(_ d: NSColor, _ l: NSColor) -> Color { Color(nsColor: NSColor(name: nil) { Theme.isDark($0) ? d : l }) }
    static let sheet = dyn(Theme.hex(0x232325), Theme.hex(0xF2F2F4))
    static let editor = dyn(Theme.hex(0x1C1C1E), Theme.hex(0xFFFFFF))
}

/// Workspaces.dc.html, save sheet: name, what will be saved, Cancel / Save.
struct SaveWorkspaceView: View {
    let summary: (displays: Int, layouts: Int, apps: Int)
    let save: (String) -> Void
    let cancel: () -> Void
    @State var name: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Workspace").font(.system(size: 15, weight: .semibold))
            Text("Name").font(.system(size: 12)).foregroundStyle(Palette.label2)
            TextField("", text: $name)
                .textFieldStyle(.plain)
                .focused($focused)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(WS.editor, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(focused ? Palette.accent : Palette.hair, lineWidth: 1))
                .overlay(RoundedRectangle(cornerRadius: 7).inset(by: -3).strokeBorder(focused ? Palette.accentFill : .clear, lineWidth: 3))
                .accessibilityLabel("Name")
                .onSubmit(commit)
            Text(verbatim: String(localized: "Saves \(count(summary.displays, one: String(localized: "1 display"), many: String(localized: "\(summary.displays) displays"))), \(count(summary.layouts, one: String(localized: "1 layout"), many: String(localized: "\(summary.layouts) layouts"))) and window positions for \(count(summary.apps, one: String(localized: "1 app"), many: String(localized: "\(summary.apps) apps"))). Windows aren't closed or moved."))
                .font(.system(size: 12)).lineSpacing(3).foregroundStyle(Palette.label2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(BowerButton()).keyboardShortcut(.cancelAction)
                Button("Save", action: commit).buttonStyle(BowerButton(primary: true)).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 640)
        .font(.system(size: 13))
        .foregroundStyle(Palette.label)
        .background(WS.sheet)
        .onAppear { focused = true }
    }

    private func commit() {
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { save(n) }
    }
}

/// Workspaces.dc.html, saved list: a row per workspace with its displays drawn small.
struct WorkspaceListView: View {
    @ObservedObject var store: Store
    let load: (String) -> Void
    let update: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            if store.state.workspaces.isEmpty {
                Text("No saved workspaces. Use Save Current Workspace (⌃⌥S) to keep this arrangement.")
                    .font(.system(size: 12)).foregroundStyle(Palette.label2)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            ForEach(Array(store.state.workspaces.enumerated()), id: \.element.name) { i, ws in row(ws, first: i == 0) }
        }
        .frame(width: 640)
        .font(.system(size: 13))
        .foregroundStyle(Palette.label)
        .background(WS.sheet)
    }

    private func row(_ ws: Workspace, first: Bool) -> some View {
        let cur = ws.name == store.state.currentWorkspace
        let date = ws.saved.formatted(.dateTime.month(.abbreviated).day())
        let meta = [count(ws.displays.count, one: String(localized: "1 display"), many: String(localized: "\(ws.displays.count) displays")),
                    count(ws.layoutsInUse, one: String(localized: "1 layout"), many: String(localized: "\(ws.layoutsInUse) layouts")),
                    cur ? String(localized: "current") : String(localized: "saved \(date)")].joined(separator: " · ")
        return HStack(spacing: 12) {
            Mini(displays: ws.displays, current: cur)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ws.name).fontWeight(.semibold)
                Text(verbatim: meta).font(.system(size: 12)).foregroundStyle(Palette.label2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(cur ? "Update" : "Load") { cur ? update(ws.name) : load(ws.name) }.buttonStyle(BowerButton())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(minHeight: 56)
        .background(cur ? Palette.accentFill : .clear)
        .overlay(alignment: .top) { if !first { Palette.hair.frame(height: 1) } }
        .contextMenu {
            Button("Delete “\(ws.name)”", role: .destructive) { deleteAction(ws.name) }
        }
    }

    var deleteAction: (String) -> Void = { _ in }
}

/// `.mini`: the workspace's displays at a common scale, the largest 22 pt wide, bottom-aligned in 56 pt.
private struct Mini: View {
    let displays: [DisplayRecord]
    let current: Bool
    var body: some View {
        let scale = 22 / (displays.map(\.size.width).max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(displays.prefix(4), id: \.uuid) { d in
                RoundedRectangle(cornerRadius: 2)
                    .fill(current ? Palette.accent.opacity(0.55) : Palette.fill2)
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Palette.hair, lineWidth: 0.5))
                    .frame(width: max(d.size.width * scale, 6), height: max(d.size.height * scale, 6))
            }
        }
        .frame(width: 56, alignment: .leading)
        .accessibilityHidden(true)
    }
}

