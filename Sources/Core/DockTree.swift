import CoreGraphics
import Foundation

// Dock mode's arrangement: windows never overlap, they sit in a tree of rows and columns nested as deep as you
// like. Pure values and geometry, no AppKit or Accessibility, so it's tested on its own (Tests/DockTreeTests).

enum DockAxis: String, Codable { case h, v }

enum DockEdge: String, Codable, CaseIterable {
    case left, right, top, bottom

    var axis: DockAxis { self == .left || self == .right ? .h : .v }
    /// The new node goes before the target (left or top) or after it.
    var before: Bool { self == .left || self == .top }
}

struct DockNode: Codable, Equatable {
    enum Kind: String, Codable { case split, window, desktop, tabs }

    var kind: Kind
    var axis: DockAxis = .h
    /// Split: one share per child, summing to 1.
    var weights: [Double] = []
    var children: [DockNode] = []
    /// Window: its key. Tabs: unused (children are windows).
    var key: String?
    /// Tabs: the child shown.
    var selected = 0

    static func window(_ key: String) -> DockNode { DockNode(kind: .window, key: key) }
    static let desktop = DockNode(kind: .desktop)

    static func split(_ axis: DockAxis, _ children: [DockNode], weights: [Double]? = nil) -> DockNode {
        DockNode(kind: .split, axis: axis, weights: weights ?? Array(repeating: 1 / Double(children.count), count: children.count),
                 children: children)
    }

    /// Every window key, depth first; a tab group's windows in tab order.
    var keys: [String] {
        switch kind {
        case .window: key.map { [$0] } ?? []
        case .desktop: []
        case .split, .tabs: children.flatMap(\.keys)
        }
    }

    var hasDesktop: Bool { kind == .desktop || children.contains(where: \.hasDesktop) }

    subscript(path: [Int]) -> DockNode? {
        guard let i = path.first else { return self }
        return children.indices.contains(i) ? children[i][Array(path.dropFirst())] : nil
    }

    /// The path of the leaf (window, or tab group holding it) for a key.
    func path(of key: String) -> [Int]? {
        if kind == .window { return self.key == key ? [] : nil }
        if kind == .tabs { return children.contains { $0.key == key } ? [] : nil }
        for (i, c) in children.enumerated() { if let p = c.path(of: key) { return [i] + p } }
        return nil
    }

    var desktopPath: [Int]? {
        if kind == .desktop { return [] }
        for (i, c) in children.enumerated() { if let p = c.desktopPath { return [i] + p } }
        return nil
    }

    mutating func modify(_ path: [Int], _ f: (inout DockNode) -> Void) {
        guard let i = path.first else { return f(&self) }
        children[i].modify(Array(path.dropFirst()), f)
    }

    // MARK: Changing the tree

    /// Puts `node` at `edge` of the node at `path`. Inside a split along the same axis it becomes a sibling and
    /// takes half the target's share; otherwise the target becomes a two-way split.
    mutating func insert(_ node: DockNode, at edge: DockEdge, of path: [Int]) {
        if let parentPath = path.isEmpty ? nil : Array(path.dropLast()), let i = path.last,
           let parent = self[parentPath], parent.kind == .split, parent.axis == edge.axis {
            modify(parentPath) { p in
                let half = p.weights[i] / 2
                p.weights[i] = half
                let at = edge.before ? i : i + 1
                p.children.insert(node, at: at)
                p.weights.insert(half, at: at)
            }
            return
        }
        modify(path) { t in
            t = .split(edge.axis, edge.before ? [node, t] : [t, node])
        }
        normalize()
    }

    /// Adds a window next to `beside` (or to the whole tree), along the longer side of where it is now.
    mutating func add(_ key: String, beside: String?, frames: [String: CGRect]) {
        let target = beside.flatMap { path(of: $0) } ?? []
        let r = beside.flatMap { frames[$0] }
        let edge: DockEdge = r.map { $0.width >= $0.height ? .right : .bottom } ?? (axis == .v && kind == .split ? .bottom : .right)
        if target.isEmpty, kind == .split, axis == edge.axis {
            // A new window at the end of the top row shares it evenly with the rest.
            let n = Double(children.count + 1)
            weights = weights.map { $0 * (n - 1) / n } + [1 / n]
            children.append(.window(key))
        } else {
            insert(.window(key), at: edge, of: target)
        }
    }

    /// Takes a window out. With `share`, every sibling grows by its share, so removing exactly undoes adding;
    /// without, the next sibling (or the previous, for the last) takes all of it.
    mutating func remove(_ key: String, share: Bool) {
        guard let p = path(of: key) else { return }
        if self[p]?.kind == .tabs {
            modify(p) { t in
                t.children.removeAll { $0.key == key }
                t.selected = min(t.selected, max(t.children.count - 1, 0))
            }
            if self[p]?.children.count == 1 { modify(p) { $0 = $0.children[0] } }
            return
        }
        removeNode(at: p, share: share)
    }

    mutating func removeNode(at p: [Int], share: Bool) {
        guard let i = p.last else { self = .split(.h, []); return }
        let parentPath = Array(p.dropLast())
        modify(parentPath) { s in
            let w = s.weights[i]
            s.children.remove(at: i)
            s.weights.remove(at: i)
            guard !s.weights.isEmpty else { return }
            if share {
                let rest = s.weights.reduce(0, +)
                s.weights = s.weights.map { rest > 0 ? $0 / rest : 1 / Double(s.weights.count) }
            } else {
                s.weights[min(i, s.weights.count - 1)] += w
            }
        }
        normalize()
    }

    /// Splits with one child become that child, empty splits go, and a split inside a split along the same axis
    /// is flattened into it.
    mutating func normalize() {
        guard kind == .split else { return }
        for i in children.indices { children[i].normalize() }
        var kids: [DockNode] = [], ws: [Double] = []
        for (c, w) in zip(children, weights) {
            if c.kind == .split, c.children.isEmpty { continue }
            if c.kind == .split, c.axis == axis {
                kids += c.children
                ws += c.weights.map { $0 * w }
            } else {
                kids.append(c)
                ws.append(w)
            }
        }
        let total = ws.reduce(0, +)
        children = kids
        weights = ws.map { total > 0 ? $0 / total : 1 / Double(ws.count) }
        if children.count == 1 { self = children[0] }
    }

    /// Two windows trade places (⌥-drag in the overview).
    mutating func swap(_ a: String, _ b: String) {
        guard let pa = path(of: a), let pb = path(of: b), self[pa]?.kind == .window, self[pb]?.kind == .window else { return }
        modify(pa) { $0.key = b }
        modify(pb) { $0.key = a }
    }

    /// Makes `key` a tab of the leaf holding `onto` (dropping a window on the middle of another).
    mutating func group(_ key: String, onto: String, share: Bool) {
        guard key != onto else { return }
        remove(key, share: share)
        guard let p = path(of: onto) else { return }
        modify(p) { t in
            if t.kind == .tabs {
                t.children.append(.window(key))
                t.selected = t.children.count - 1
            } else {
                t = DockNode(kind: .tabs, children: [t, .window(key)], selected: 1)
            }
        }
    }

    /// Takes a tab out of its group and puts it beside the group.
    mutating func ungroup(_ key: String) {
        guard let p = path(of: key), self[p]?.kind == .tabs else { return }
        remove(key, share: true)
        insert(.window(key), at: .right, of: path(of: self[p]?.children.first?.key ?? "") ?? p)
    }

    mutating func select(_ key: String) {
        guard let p = path(of: key), self[p]?.kind == .tabs else { return }
        modify(p) { t in t.selected = t.children.firstIndex { $0.key == key } ?? t.selected }
    }

    /// Moves the seam after child `i` of the split at `path` by `delta` points of a `length`-point row.
    mutating func resize(_ path: [Int], seam i: Int, by delta: CGFloat, length: CGFloat, minShare: Double = 0.05) {
        modify(path) { s in
            guard s.kind == .split, s.weights.indices.contains(i + 1), length > 0 else { return }
            let d = Double(delta / length)
            let a = s.weights[i] + d, b = s.weights[i + 1] - d
            guard a >= minShare, b >= minShare else { return }
            s.weights[i] = a
            s.weights[i + 1] = b
        }
    }

    // MARK: Geometry

    struct Solved: Equatable {
        /// Window key → frame. Every tab of a group gets the group's frame.
        var frames: [String: CGRect] = [:]
        var desktop: CGRect?
        /// The seams between a split's children: split path, seam index, axis, and the gap's rectangle.
        var seams: [Seam] = []
    }

    struct Seam: Equatable {
        var path: [Int]
        var index: Int
        var axis: DockAxis
        var rect: CGRect
        var length: CGFloat
    }

    /// Lays the tree out in `rect`, with `gap` points between neighbours. Frames are whole points.
    func solve(in rect: CGRect, gap: CGFloat, path: [Int] = []) -> Solved {
        var out = Solved()
        switch kind {
        case .window:
            if let key { out.frames[key] = rect.integral }
        case .desktop:
            out.desktop = rect.integral
        case .tabs:
            for c in children { if let k = c.key { out.frames[k] = rect.integral } }
        case .split:
            guard !children.isEmpty else { break }
            let length = axis == .h ? rect.width : rect.height
            let usable = max(length - gap * CGFloat(children.count - 1), 0)
            let total = weights.reduce(0, +)
            var pos = axis == .h ? rect.minX : rect.minY
            for (i, c) in children.enumerated() {
                let size = (usable * CGFloat(total > 0 ? weights[i] / total : 1 / Double(children.count))).rounded()
                let isLast = i == children.count - 1
                let end = isLast ? (axis == .h ? rect.maxX : rect.maxY) : pos + size
                let r = axis == .h ? CGRect(x: pos, y: rect.minY, width: end - pos, height: rect.height)
                                   : CGRect(x: rect.minX, y: pos, width: rect.width, height: end - pos)
                let sub = c.solve(in: r, gap: gap, path: path + [i])
                out.frames.merge(sub.frames) { a, _ in a }
                out.desktop = out.desktop ?? sub.desktop
                out.seams += sub.seams
                if !isLast {
                    let seam = axis == .h ? CGRect(x: end, y: rect.minY, width: gap, height: rect.height)
                                          : CGRect(x: rect.minX, y: end, width: rect.width, height: gap)
                    out.seams.append(Seam(path: path, index: i, axis: axis, rect: seam, length: usable))
                }
                pos = end + gap
            }
        }
        return out
    }
}

/// Where a dragged window would land over another: an edge band docks beside it, the middle makes tabs.
enum DropTarget: Equatable {
    case edge(DockEdge, of: String)
    case screenEdge(DockEdge)
    case middle(of: String)

    /// `p` over a window's frame `r`: the outer quarter on each side is that edge, the rest is the middle.
    static func over(_ key: String, frame r: CGRect, at p: CGPoint, band: CGFloat = 0.25) -> DropTarget? {
        guard r.contains(p) else { return nil }
        let fx = (p.x - r.minX) / r.width, fy = (p.y - r.minY) / r.height
        let d: [(DockEdge, CGFloat)] = [(.left, fx), (.right, 1 - fx), (.top, fy), (.bottom, 1 - fy)]
        let nearest = d.min { $0.1 < $1.1 }!
        return nearest.1 < band ? .edge(nearest.0, of: key) : .middle(of: key)
    }

    /// Within `margin` points of the display's edge.
    static func screen(_ screen: CGRect, at p: CGPoint, margin: CGFloat = 24) -> DropTarget? {
        if p.x - screen.minX < margin { return .screenEdge(.left) }
        if screen.maxX - p.x < margin { return .screenEdge(.right) }
        if p.y - screen.minY < margin { return .screenEdge(.top) }
        if screen.maxY - p.y < margin { return .screenEdge(.bottom) }
        return nil
    }
}

/// Back and forward through where you've been, like a browser. A new step after going back drops the forward list.
struct History<T: Equatable> {
    private(set) var back: [T] = []
    private(set) var forward: [T] = []
    var limit = 50

    mutating func push(_ from: T) {
        if back.last == from { return }
        back.append(from)
        if back.count > limit { back.removeFirst() }
        forward = []
    }

    mutating func goBack(from current: T) -> T? {
        guard let t = back.popLast() else { return nil }
        forward.append(current)
        return t
    }

    mutating func goForward(from current: T) -> T? {
        guard let t = forward.popLast() else { return nil }
        back.append(current)
        return t
    }
}

/// One display's Dock mode in one layout: its tree, the windows floating over it, and the part zoomed into.
struct DockLayout: Codable, Equatable {
    var root = DockNode.split(.h, [])
    var floating: Set<String> = []
    /// Path of the node filling the display; nil shows the whole tree.
    var zoom: [Int]?
}
