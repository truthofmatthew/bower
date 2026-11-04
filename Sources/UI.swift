import SwiftUI

/// Window tokens shared by Settings and the first-run window (SetGeneral.dc.html, FirstRun.dc.html).
enum Palette {
    private static func dyn(_ dark: NSColor, _ light: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { Theme.isDark($0) ? dark : light })
    }

    private static func r(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat) -> NSColor { Theme.rgba(r, g, b, a) }
    private static func h(_ v: UInt32) -> NSColor { Theme.hex(v) }
    static let label = dyn(r(255, 255, 255, 0.92), r(0, 0, 0, 0.88))
    static let label2 = dyn(r(235, 235, 245, 0.64), r(60, 60, 67, 0.74))
    static let label3 = dyn(r(235, 235, 245, 0.38), r(60, 60, 67, 0.40))
    static let hair = dyn(r(255, 255, 255, 0.10), r(0, 0, 0, 0.10))
    static let fill = dyn(r(255, 255, 255, 0.07), r(0, 0, 0, 0.045))
    static let fill2 = dyn(r(255, 255, 255, 0.14), r(0, 0, 0, 0.09))
    static let window = dyn(h(0x1E1E20), h(0xF2F2F4))
    static let chrome = dyn(h(0x2A2A2D), h(0xE6E6E9))
    static let group = dyn(r(255, 255, 255, 0.05), h(0xFFFFFF))
    static let control = dyn(h(0x3A3A3E), h(0xFFFFFF))
    static let accent = dyn(h(0x3FD3C2), h(0x0B7A72))
    static let accentFill = dyn(r(63, 211, 194, 0.20), r(11, 122, 114, 0.14))
    static let onAccent = dyn(h(0x04231F), h(0xFFFFFF))
    static let ok = dyn(h(0x4CD97B), h(0x1E7F3C))
    static let warn = dyn(h(0xFFC94D), h(0x9A6200))
    static let danger = dyn(h(0xFF7066), h(0xC9302C))
    static let stage = dyn(r(0, 0, 0, 0.25), r(0, 0, 0, 0.05))
    static let screen = dyn(h(0x2E3A52), h(0x5E7FA3))  // light: dark enough for white text
    static let groupSolid = dyn(h(0x2A2A2D), h(0xFFFFFF))
    static let field = dyn(r(255, 255, 255, 0.06), h(0xFFFFFF))
}

/// A 1.5 pt round-stroked icon from a design path string, on a `size`-point grid.
struct PathIcon: Shape {
    let d: String
    var grid: CGFloat = 16
    func path(in rect: CGRect) -> Path {
        let s = rect.width / grid
        return Path(Icon.path(d)).applying(CGAffineTransform(scaleX: s, y: s))
    }
}

struct Glyph: View {
    let d: String
    var grid: CGFloat = 16
    var size: CGFloat = 16
    var width: CGFloat = 1.5
    var body: some View {
        PathIcon(d: d, grid: grid)
            .stroke(style: StrokeStyle(lineWidth: width * size / grid, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// `.group`: 9 pt radius box with a 0.5 pt hairline; rows separated by 1 pt hairlines.
struct FormGroup<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Palette.group, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.hair, lineWidth: 0.5))
    }
}

/// `.row`: at least 40 tall, 12 pt horizontal padding, hairline on top except the first.
struct FormRow<Content: View>: View {
    var first = false
    @ViewBuilder let content: Content
    var body: some View {
        // The 40 pt minimum comes from a 28 pt strut plus padding rather than .frame(minHeight:), which inside a
        // ScrollView pins the row to 40 and lets wrapped (translated) text spill out.
        HStack(spacing: 0) {
            Color.clear.frame(width: 0, height: 28)
            HStack(spacing: 12) { content }
        }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .overlay(alignment: .top) { if !first { Palette.hair.frame(height: 1) } }
    }
}

struct RowText: View {
    let title: Text
    var sub: Text?

    /// Literals are looked up in the String Catalog.
    init(title: LocalizedStringKey, sub: LocalizedStringKey? = nil) {
        self.title = Text(title)
        self.sub = sub.map { Text($0) }
    }

    /// Text that is already translated or shouldn't be (display names, dates).
    init(verbatim title: String, sub: String? = nil) {
        self.title = Text(verbatim: title)
        self.sub = sub.map { Text(verbatim: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title.font(.system(size: 13)).foregroundStyle(Palette.label)
            if let sub { sub.font(.system(size: 11)).foregroundStyle(Palette.label2) }
        }
        // Wraps rather than truncates: translations run longer than the English.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `.gh`: 12 pt semibold group heading.
struct GroupHeading: View {
    let text: Text
    init(text: LocalizedStringKey) { self.text = Text(text) }
    init(verbatim: String) { text = Text(verbatim: verbatim) }
    var body: some View {
        text.font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.label2).padding(.horizontal, 4)
    }
}

/// `.toggle`: 34 × 20 track, 16 pt white knob.
struct BowerToggle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Palette.accent : Palette.fill2).frame(width: 34, height: 20)
                Circle().fill(.white).frame(width: 16, height: 16).shadow(color: .black.opacity(0.3), radius: 1, y: 1).padding(2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "on" : "off")
    }
}

/// `.radio`: 16 pt; on = accent disc with a 6 pt on-accent dot.
struct Radio: View {
    let on: Bool
    var body: some View {
        ZStack {
            if on {
                Circle().fill(Palette.accent)
                Circle().fill(Palette.onAccent).frame(width: 6, height: 6)
            } else {
                Circle().strokeBorder(Palette.label3, lineWidth: 1)
            }
        }
        .frame(width: 16, height: 16)
    }
}

/// `.btn` / `.btn.primary`: 28 tall, 14 pt padding, radius 7.
struct BowerButton: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: primary ? .medium : .regular))
            .foregroundStyle(primary ? Palette.onAccent : Palette.label)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(primary ? Palette.accent : Palette.control, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.hair, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 0.75, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.16), value: configuration.isPressed)
            .opacity(enabled ? 1 : 0.45)
    }
}

/// The menu bar glyph from AppIcon.dc.html, on an 18 pt grid.
struct BowerGlyph: View {
    var size: CGFloat = 13
    var body: some View {
        Canvas { ctx, sz in
            let s = sz.width / 18
            var arch = Path()
            arch.move(to: CGPoint(x: 3 * s, y: 15.5 * s))
            arch.addLine(to: CGPoint(x: 3 * s, y: 9 * s))
            arch.addArc(center: CGPoint(x: 9 * s, y: 9 * s), radius: 6 * s, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            arch.addLine(to: CGPoint(x: 15 * s, y: 15.5 * s))
            ctx.stroke(arch, with: .foreground, style: StrokeStyle(lineWidth: 1.7 * s, lineCap: .round))
            ctx.fill(Path(roundedRect: CGRect(x: 6 * s, y: 10.5 * s, width: 2.6 * s, height: 5 * s), cornerRadius: 0.6 * s), with: .foreground)
            ctx.fill(Path(roundedRect: CGRect(x: 9.4 * s, y: 10.5 * s, width: 2.6 * s, height: 5 * s), cornerRadius: 0.6 * s), with: .foreground)
        }
        .frame(width: size, height: size)
    }
}

/// The app icon artwork from FirstRun.dc.html / AppIcon.dc.html, drawn on its 1024 grid.
struct BowerIcon: View {
    var size: CGFloat = 64
    var body: some View {
        Canvas { ctx, sz in
            ctx.scaleBy(x: sz.width / 824, y: sz.height / 824)
            ctx.translateBy(x: -100, y: -100)
            BowerIcon.draw(into: &ctx)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Bower icon")
    }

    static func draw(into ctx: inout GraphicsContext) {
        func rect(_ x: CGFloat, _ y: CGFloat, _ hex: UInt32) {
            ctx.fill(Path(roundedRect: CGRect(x: x, y: y, width: 200, height: 120), cornerRadius: 22), with: .color(Color(nsColor: Theme.hex(hex))))
        }
        ctx.fill(Path(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerRadius: 185), with: .color(Color(nsColor: Theme.hex(0x0F3F3C))))
        rect(300, 540, 0x3FD3C2); rect(524, 540, 0xF3E6C8); rect(300, 684, 0x4C7BE8); rect(524, 684, 0x9FE8DD)
        // M234 830C234 400 360 226 512 226S790 400 790 830, and the inner arch; S reflects the previous control point.
        for (x0, y1, top, c1, hex) in [(234.0, 400.0, 226.0, 360.0, UInt32(0xF0D9A3)), (266, 430, 266, 380, 0xD9B66E)] {
            var p = Path()
            p.move(to: CGPoint(x: x0, y: 830))
            p.addCurve(to: CGPoint(x: 512, y: top), control1: CGPoint(x: x0, y: y1), control2: CGPoint(x: c1, y: top))
            p.addCurve(to: CGPoint(x: 1024 - x0, y: 830), control1: CGPoint(x: 1024 - c1, y: top), control2: CGPoint(x: 1024 - x0, y: y1))
            ctx.stroke(p, with: .color(Color(nsColor: Theme.hex(hex))), style: StrokeStyle(lineWidth: 22, lineCap: .round))
        }
    }
}

/// Hosts a SwiftUI view in a standard titled window that matches the design's chrome colour.
final class HostedWindow: NSWindow {
    init<V: View>(title: String, size: CGSize, bareTitlebar: Bool = false, hideButtons: Bool = false, @ViewBuilder content: () -> V) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: bareTitlebar ? [.titled, .closable, .fullSizeContentView] : [.titled, .closable],
                   backing: .buffered, defer: false)
        self.title = title
        if bareTitlebar {
            titlebarAppearsTransparent = true
            titleVisibility = .hidden
        }
        isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace]
        if hideButtons { [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true } }
        // Without window buttons nothing needs the titlebar's strip, so the design starts at the very top; otherwise
        // SwiftUI keeps that strip free and the bottom of a fixed-height design is cut off.
        let host = NSHostingView(rootView: content().ignoresSafeArea(.container, edges: hideButtons ? .top : []))
        // With the content under the titlebar, the window is exactly the design's size; left to itself the hosting
        // view would size the content area to fit and the titlebar would be added on top.
        if bareTitlebar { host.sizingOptions = [] }
        contentView = host
        if bareTitlebar {
            let fit = host.fittingSize
            setFrame(NSRect(origin: frame.origin, size: CGSize(width: size.width, height: max(size.height, fit.height))), display: false)
        }
        center()
    }

    func show() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
        // On macOS 14 activation is a request the active app can decline; the window still comes to the front.
        orderFrontRegardless()
    }
}

/// An app's name and icon from its bundle identifier, for rows that would otherwise show "com.apple.TextEdit".
enum AppInfo {
    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }

    static func name(_ id: String) -> String {
        if let n = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id })?.localizedName { return n }
        if let u = url(id) {
            let b = Bundle(url: u)
            if let n = (b?.localizedInfoDictionary?["CFBundleDisplayName"] ?? b?.infoDictionary?["CFBundleDisplayName"]
                        ?? b?.infoDictionary?["CFBundleName"]) as? String, !n.isEmpty { return n }
            return FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
        }
        // An app that's gone: its identifier's last part reads better than the whole thing.
        return id.split(separator: ".").last.map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? id
    }

    static func icon(_ id: String) -> NSImage? { url(id).map { NSWorkspace.shared.icon(forFile: $0.path) } }
}

/// A row that names an app with its icon.
struct AppRow: View {
    let bundleID: String
    var title: String?
    var sub: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppInfo.icon(bundleID) ?? NSImage()).resizable().frame(width: 22, height: 22).accessibilityHidden(true)
            RowText(verbatim: title ?? AppInfo.name(bundleID), sub: sub)
        }
    }
}
