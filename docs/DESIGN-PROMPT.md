Design the full UI for **Bower**, a native macOS window and workspace manager (macOS 14+, Swift/AppKit). It's free and open source and runs only on your Mac. Every project gets a named layout covering all monitors, and ⌥1–9 switches the whole desk at once with no animation. The attached screenshot shows a radial "Snap Wheel" from another app. Use it for the interaction idea and the level of polish, but give Bower its own visual identity rather than copying it.

## Look and feel
- It should feel like a built-in part of macOS: system materials (HUD/vibrancy blur), SF Pro, SF Symbols-style line icons, 1px hairlines, generous corner radii. No gradients-for-decoration, no glow, no purple "AI" styling.
- Provide both dark and light versions. Use one accent color, which must also read as a state color (active layout, hovered wedge). Propose it.
- Overlays (the wheel, the bar, snap previews) are translucent and sit above any wallpaper. Show them over a busy real-looking desktop so contrast gets tested.
- Hit targets of at least 28pt, visible keyboard focus, and Reduce Motion / Increase Contrast variants for the wheel.

## Screens and components (in priority order)

1. **Snap Wheel.** A radial menu that opens centered on the cursor (middle-click or ⌃⌥Space) and runs the action you release on.
   - Center: cancel (×).
   - Inner ring, 8 wedges: left / right / top / bottom half, and the four quarters. Each wedge has a tiny screen glyph with the target area filled in.
   - Outer ring, 8 slots: Maximize, Thirds ▸, Window Mode ▸ (Native / Bento / Tabs), Layouts ▸ (1–9), Send to layout ▸, Retile, AI Recipe, Settings.
   - States: idle, hover on an inner wedge (with a live ghost preview of the window's target frame drawn on screen), hover on an outer slot, a ▸ submenu expanded into a third arc, and a disabled slot.
   - Size: about 300pt diameter. Show it at 1× and 2×.
2. **Snap preview overlay.** The translucent rectangle showing where a window will land, used by both the wheel and keyboard snapping (halves, thirds, quarters, maximize).
3. **Menu bar item and menu.**
   - The status item shows `3 · Dev` (layout number and name). Also show the variants: icon only, number only, window count.
   - Menu: layouts 1–9 (✓ on the current one, ⌥n shortcut on the right) / Mode for this display ▸ / Workspaces ▸ (Save current…, saved list) / Route "Slack" to layout ▸ / Pin this display / Recipes ▸ / Settings… / About / Quit.
4. **Layouts Bar** (⌥↑). A floating HUD strip at the top of the active display.
   - One chip per layout: number, name, and stacked app icons of its windows. The current layout is highlighted.
   - Dragging a window icon onto a chip assigns it. Show the drag-over state.
   - Also show an "unassigned" bucket and a pinned-display indicator.
5. **Tabs Mode tab strip.** A thin native-looking tab bar drawn above a screen pane, holding windows from different apps (app icon + title). Show the active tab, hover, and close states, and a pane split into two tab groups side by side.
6. **Bento Box.** A small explainer illustration of a display auto-tiled into a grid (2, 3, 5 and 7 windows), plus the "retiled" transient toast.
7. **Settings window**, a standard macOS toolbar-tab preferences window with these tabs:
   - **General:** launch at login, menu bar item contents.
   - **Layouts:** reorderable list of 9 layouts (name and per-display Mode), plus an app-routing table (app → layout).
   - **Displays:** an arrangement diagram of the connected displays. Each one has Mode, Pin, and an "Offline shelf" section listing disconnected displays with their saved state and "Move to…".
   - **Shortcuts:** a grouped list with key recorders and an ANSI / ISO preset picker.
   - **Snap Wheel:** an interactive editor of the wheel where you drag actions from a palette onto slots or hide a slot.
   - **AI:** endpoint URL (presets: Ollama, LM Studio, OpenAI-compatible), model picker, API key field (stored in Keychain), and a "Test connection" button with success and error states.
8. **Recipe editor.** A sheet with a Markdown text editor on the left (with `@` autocomplete popover for apps and displays) and a **Preview** on the right: mini diagrams of each display with the planned windows and the mode badge. Buttons: Preview, Apply. Show the states loading, plan ready, validation warning ("@Figma isn't running"), and error. Sample recipe:
   ```
   ## Projects & Layouts
   - Dev — @VS Code + @Terminal on @main monitor
   - Comms — @Slack on @side monitor
   ## Window modes
   - @main monitor uses Tabs
   - @side monitor uses Bento Box
   ```
9. **Workspace save/load.** A small sheet to name a workspace, and a list of saved ones ("Docked Dev · 3 displays · 6 layouts", "Travel · 1 display").
10. **First run.** A welcome window with three steps (Grant Accessibility → Try ⌥1/⌥2 → Open the Snap Wheel), including the "waiting for permission" state.
11. **App icon.** A macOS-style icon for "Bower" (named after the bowerbird, which arranges objects carefully). Provide 1024pt plus a monochrome menu bar template glyph at 16/18pt.

## Deliverables
- High-fidelity frames for every screen and state above, in dark and light.
- A small component sheet: colors (as named tokens with dark/light values), type scale, spacing, radii, material/blur levels, icon set, and wheel geometry (inner and outer radius, wedge angles, gap). These will be implemented by hand in AppKit/SwiftUI, so give exact numbers.
- Annotate interaction timing: wheel open/close duration, hover response, and the snap preview fade. Layout switching itself has no animation.
