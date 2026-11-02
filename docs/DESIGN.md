# Bower: an open-source, local Paneo

Working name: **Bower**, after the bowerbird, which arranges everything around it with care. It sits next to Magpie. Rename it freely.

---

## Part 1. Audit of paneo.work (v1.3.4, read 2026-11-02)

Paneo is a native macOS window and workspace manager (Swift/AppKit, macOS 14+). It needs only the Accessibility permission. SIP stays on, and it collects no telemetry. Its main idea: every project gets a **named layout** that covers every monitor. When you switch projects, the whole desk changes in one step with no Spaces animation (they claim 16 ms).

### Features

| # | Feature | What it does | Paneo tier |
|---|---|---|---|
| 1 | **Named layouts** | Up to 9 (Free: 3). Each layout owns a set of windows across all monitors. ⌥1–9 switches, ⌥⇧1–9 sends the focused window, ⌥Tab cycles, ⌥N creates a new one. | Free / Pro |
| 2 | **Instant switching** | No Spaces slide. Windows not in the active layout are hidden. | Free |
| 3 | **Window Mode per monitor** | Each monitor in each layout has one of three modes: | |
| 3a | Supercharged Native | Windows float freely, with snapping and shortcuts added. | Free |
| 3b | Bento Box | Tiles every window into a grid automatically. ⌥↓ retiles. | Pro |
| 3c | Tabs Mode | Windows are stacked behind a tab strip inside saved panes (e.g. Split View). | Pro |
| 4 | **Snapping** | 15 snap zones: halves ⌃⌥←/→, thirds ⌃⌥A/S/D, quarters ⌃⌥U/I/J/K, maximize ⌃⌥↩. Snap presets (Split, Four Corners, Focus + Stack, custom ones per layout). | Free |
| 5 | **Snap Wheel** | A radial menu that opens under the cursor (trackpad flick, middle-click or hotkey). It has two rings: halves and quarters on the outer one, presets, modes, layouts and retile one level deeper. Every slot can be remapped. | Free |
| 6 | **Keyboard** | Every action can be rebound. ANSI and European presets. Focus moves with ⌘⌥J/K/I/L. | Free |
| 7 | **Workspace Continuity** | Brings layouts back automatically after Paneo restarts, the Mac wakes, or displays reconnect. Saves a checkpoint locally. | Free |
| 8 | **Save / load Workspaces** | Named snapshots of the whole desk (e.g. "Docked Dev: 3 displays, 6 layouts" or "Travel"). | Pro |
| 9 | **Offline Display Shelf** | When a display disconnects, its layout state is kept until the display comes back or you move that state to another screen. | Pro |
| 10 | **Pinned Displays** | A pinned monitor keeps its windows when you switch layouts (Slack and docs stay where they are). | Pro |
| 11 | **App Routing** | Apps are assigned to layouts automatically. | Pro |
| 12 | **Layouts Bar** | A visual overview of layouts. You drag a window onto a layout to assign it. ⌥↑ toggles it. | Free |
| 13 | **Custom menu bar item** | Shows any of: logo, layout index (3/7), window count, layout name, mode. | Free |
| 14 | **AI Layouts** | A plain-English Markdown "Recipe" with @-mentions of apps and monitors. Paneo shows a plan and you approve it before anything moves. Works with your own API key, Ollama or LM Studio, or hosted "Paneo AI" ($4.99/mo). | Pro |
| 15 | i18n | 7 languages. | n/a |

**Price:** Free (3 layouts), Pro $19.99 one-time with a 90-day trial, Paneo AI $4.99/mo. **Competitors it compares itself to:** Stage Manager, Spaces, yabai (needs SIP off), and AeroSpace (open source, MIT, config files only, no GUI).

### Example Recipe (Paneo's format)

```md
## Projects & Layouts
- Dev — signals: vscode, terminal — @VS Code + @Terminal on @main monitor
- Comms — signals: slack, discord — @Slack on @side monitor
## Window modes
- @main monitor uses Tabs: Split View
- @side monitor uses Bento Box
## Rules
- @Chat windows always on @side monitor
```

### How it most likely works (with SIP on)

- **Moving windows:** `AXUIElement` set position and size, which needs Accessibility.
- **Instant hide:** Paneo can't use real Spaces without SIP off, and minimizing animates. The 16 ms switch and the "Offline Display Shelf" both point to the method AeroSpace uses: windows outside the active layout are moved just off-screen into a corner and moved back when their layout becomes active.
- **Window identity:** `_AXUIElementGetWindow` maps an AX window to its `CGWindowID`. It's a private symbol but works with SIP on, and AeroSpace and Rectangle both use it.
- **Hotkeys:** Carbon `RegisterEventHotKey`, which needs no Input Monitoring. Magpie already does this.
- **Middle-click and trackpad trigger:** a `CGEventTap`. Mouse events are covered by Accessibility. The trackpad flick likely reads private MultitouchSupport data.
- **Displays:** keyed by `CGDisplayCreateUUIDFromDisplayID`, so they're recognized again after a reconnect.

---

## Part 2. Product design

### Principles (taken from Magpie)

1. Native Swift/AppKit, **no dependencies**, XcodeGen `project.yml`, `install.sh`.
2. Accessibility is the only permission. SIP stays on.
3. Everything stays local: `~/Library/Application Support/Bower/state.json`. No account, no telemetry.
4. Everything is free. Paneo's Pro features ship in the main app with no license checks.
5. Settings are visual, but the state is plain JSON you can read and edit, so you get AeroSpace-style config files without being forced to use them.

### Mental model

```
Desk ── Display (by UUID) ─┐
  └─ Layout 1…9 ──────────┼─ per-display Mode: native | bento | tabs
        └─ Window refs ───┘   (bundleID + title hint + CGWindowID)
Workspace = named snapshot of the whole Desk
```

- A window belongs to exactly one layout, or it's **unassigned**. Unassigned windows stay visible everywhere.
- A **pinned** display is left out of layout switching.
- **App routing:** `bundleID → layout`. New windows from that app go to that layout.

### Surfaces

1. **Menu bar item.** It shows `3 · Dev` by default, and you choose which parts appear. The menu has: layouts list (✓ current), Mode for this display ▸, Workspaces ▸ (Save current…, load list), Route [frontmost app] to ▸, Pin this display, Recipes ▸, Settings…, About.
2. **Layouts Bar** (⌥↑). A floating HUD at the top of the screen that shows a chip per layout with its app icons. Drag a window's icon onto a chip to move it. Clicking a chip switches to that layout. Esc closes it.
3. **Snap Wheel** (middle-click or ⌃⌥Space). A radial menu at the cursor. Inner ring: ← → ↑ ↓ halves and 4 quarters. Outer ring: Maximize, Thirds ▸, Mode ▸, Layout ▸. You release on a slot to run it. Slots are set in Settings.
4. **Settings window** with four tabs: **Layouts** (rename, reorder, routing table), **Shortcuts** (rebinding recorder, ANSI/ISO preset), **Wheel**, **AI** (endpoint URL, model, key in Keychain).
5. **Recipe sheet.** A plain text editor where @ autocompletes apps and displays. **Preview** draws a mini diagram of each display with the planned windows, and **Apply** runs it. Recipes are `.md` files in `Bower/Recipes/`.

### Keyboard (same defaults as Paneo, all rebindable)

| Action | Key |
|---|---|
| Switch / send to / cycle / new layout | ⌥1–9 / ⌥⇧1–9 / ⌥Tab / ⌥N |
| Retile screen / cycle mode / Layouts Bar | ⌥↓ / ⌥B / ⌥↑ |
| Focus window | ⌘⌥J/K/I/L |
| Halves / thirds / quarters / maximize | ⌃⌥←→ / ⌃⌥A S D / ⌃⌥U I J K / ⌃⌥↩ |

### AI Recipes, kept local

- There is one client: the **OpenAI-compatible `/v1/chat/completions`** API. It covers Ollama, LM Studio, llama.cpp, OpenRouter, OpenAI and most hosted providers, and an Anthropic endpoint can be reached through any compatible gateway. There is no hosted Bower service.
- The prompt includes the Recipe, the current windows (app and title), and the displays with their sizes. The model must return **strict JSON**: `{layouts:[{name, displays:[{display, mode, windows:[{app, titleContains?, frame?}]}]}], routes:[…]}`.
- Bower validates the plan against the real windows, shows the preview, and changes nothing until you press Apply.

---

## Part 3. Build plan

| Milestone | Scope | Notes |
|---|---|---|
| **M1: Core** | Window discovery (AX + CGWindowID), named layouts 1–9, instant switching by moving windows off-screen, send-to-layout, menu bar, hotkeys, `state.json` persistence | The core of the product. Without it nothing else matters. |
| **M2: Snapping** | 15 snap zones, presets, focus movement, multi-monitor, pinned displays | Short. Most of it is frame math. |
| **M3: Continuity** | Restore after relaunch, wake and display reconnect. Offline display shelf. Save/load Workspaces. App routing. | Rematching windows after a relaunch, by bundle ID plus title, is the hard part. |
| **M4: Bento Box** | Auto-tiling grid per display, retile, new windows tile automatically | The AX observer for window created/closed. |
| **M5: Snap Wheel + Layouts Bar** | Radial menu with an `NSPanel` and a `CGEventTap` for middle-click; HUD bar with drag-to-assign | No trackpad flick gesture because it needs private multitouch APIs. |
| **M6: AI Recipes** | Recipe editor, @-completion, OpenAI-compatible client, JSON plan, preview, apply | |
| **M7: Tabs Mode** | A tab strip window over a pane. Inactive tabs are parked off-screen. | The riskiest part. macOS doesn't support tabbing other apps' windows, so this one is faked. |
| **Open source** | MIT, README in Magpie's style, icon, GitHub `truthofmatthew/bower`, unsigned DMG via GitHub Releases | |

### Known risks

- **Off-screen parking:** macOS keeps a small strip of a window on screen when you push it off. AeroSpace parks windows in the bottom-right corner of the rightmost display, and some apps (for example Electron apps with min sizes) still show a few pixels there. This is acceptable, and it's what AeroSpace users live with.
- **Fullscreen and native Spaces:** windows in macOS fullscreen can't be moved. They're ignored and appear as "unassigned".
- **Rematching windows after a relaunch** only works as well as the title heuristics. Some windows will come back unassigned.
- **`_AXUIElementGetWindow`** is private API, so the app can't be sold on the Mac App Store. It can still be distributed outside the store, the same way Magpie is.
