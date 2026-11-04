import AppKit
import ScreenCaptureKit

/// Still pictures of windows, for the overview, drag previews and moving windows smoothly. Needs Screen Recording,
/// which is optional: without it every picture is the app's colour and icon instead. Nothing is recorded or kept;
/// pictures live in memory for a few seconds.
enum Capture {
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccess() { CGRequestScreenCaptureAccess() }

    private static var content: (SCShareableContent, Date)?
    private static var cache: [CGWindowID: (CGImage, Date)] = [:]

    private static func shareable() async -> SCShareableContent? {
        if let (c, t) = content, Date().timeIntervalSince(t) < 1 { return c }
        let c = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        if let c { content = (c, Date()) }
        return c
    }

    /// Pictures of these windows, by ID; missing ones (no permission, off screen, minimized) are left out.
    static func images(_ ids: [CGWindowID], maxSide: CGFloat = 1200) async -> [CGWindowID: CGImage] {
        guard allowed, let c = await shareable() else { return [:] }
        var out: [CGWindowID: CGImage] = [:]
        await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            for id in ids {
                if let (img, t) = cache[id], Date().timeIntervalSince(t) < 0.4 { out[id] = img; continue }
                guard let w = c.windows.first(where: { $0.windowID == id }) else { continue }
                group.addTask {
                    let cfg = SCStreamConfiguration()
                    let scale = min(1, maxSide / max(w.frame.width, w.frame.height)) * 2
                    cfg.width = Int(w.frame.width * scale)
                    cfg.height = Int(w.frame.height * scale)
                    cfg.showsCursor = false
                    cfg.ignoreShadowsSingleWindow = true
                    let img = try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: w),
                                                                          configuration: cfg)
                    return (id, img)
                }
            }
            for await (id, img) in group { if let img { out[id] = img; cache[id] = (img, Date()) } }
        }
        return out
    }

    /// The desktop picture of a display, blurred later by whoever draws it.
    static func wallpaper(_ s: NSScreen) -> NSImage? {
        NSWorkspace.shared.desktopImageURL(for: s).flatMap(NSImage.init(contentsOf:))
    }

    // MARK: App colour

    private static var colours: [String: NSColor] = [:]

    /// The main colour of an app's icon: the average of its opaque pixels at 16 × 16.
    static func colour(of app: NSRunningApplication?) -> NSColor {
        guard let app, let key = app.bundleIdentifier ?? app.localizedName else { return .gray }
        if let c = colours[key] { return c }
        var c = NSColor.gray
        if let icon = app.icon, let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            var px = [UInt8](repeating: 0, count: 16 * 16 * 4)
            if let ctx = CGContext(data: &px, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                                   space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 16, height: 16))
                var r = 0.0, g = 0.0, b = 0.0, n = 0.0
                for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] > 200 {
                    r += Double(px[i]); g += Double(px[i + 1]); b += Double(px[i + 2]); n += 1
                }
                if n > 0 { c = NSColor(srgbRed: r / n / 255, green: g / n / 255, blue: b / n / 255, alpha: 1) }
            }
        }
        colours[key] = c
        return c
    }

    /// What a window shows as without a picture: grey, tinted by `amount` of its app's colour.
    static func tint(for pid: pid_t, amount: Double, on: Bool) -> NSColor {
        let grey = NSColor(white: 0.5, alpha: 1)
        guard on else { return grey }
        return grey.blended(withFraction: amount, of: colour(of: NSRunningApplication(processIdentifier: pid))) ?? grey
    }
}
