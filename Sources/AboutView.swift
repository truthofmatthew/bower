import SwiftUI

/// Matches Magpie's About window, in Bower's colours.
struct AboutView: View {
    private let version: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return String(localized: "Version \(short) (\(build))")
    }()

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

            Text(verbatim: "Bower")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .padding(.top, 6)
            Text(verbatim: version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Give every project its own desk, and switch the whole desk with ⌥1–9.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Divider().padding(.vertical, 22)

            Text("Made by")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(verbatim: "Matthew Truth")
                .font(.title3.weight(.semibold))
                .padding(.top, 2)

            HStack(spacing: 10) {
                Link(destination: URL(string: "https://github.com/truthofmatthew/bower")!) {
                    Label { Text(verbatim: "GitHub") } icon: { Image("GitHub").resizable().frame(width: 14, height: 14) }
                }
                .help("github.com/truthofmatthew/bower")
                Link(destination: URL(string: "https://truthofmatthew.com")!) {
                    Label { Text(verbatim: "truthofmatthew.com") } icon: { Image(systemName: "globe") }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.top, 16)
        }
        .padding(.horizontal, 28)
        .padding(.top, 12)  // plus the hidden title bar's height
        .padding(.bottom, 30)
        .frame(width: 430)
        .background(alignment: .top) {
            // The icon's teal body, faded into the window behind it.
            LinearGradient(colors: [Color(nsColor: Theme.hex(0x17534E)).opacity(0.55),
                                    Color(nsColor: Theme.hex(0x3FD3C2)).opacity(0.10), .clear],
                           startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
        }
    }
}
