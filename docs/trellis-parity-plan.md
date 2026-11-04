# Plan: everything TrellisWM has that Bower doesn't

Source: static read of TrellisWM 0.10.0 (build 560): its symbols, 489 UI strings, `ReleaseSettings.json`, bundled lessons and disassembly. Unpacked copy: `/Volumes/Datas/Scratch/trellis-re`. No Trellis code is copied; each item below is rebuilt from public or documented-by-community APIs.

**What Bower already has** (so it isn't in this plan):
- Layouts 1–9 and switching between them
- Sending a window to a layout, and app routes
- Workspaces, and display pinning and reconnects (Continuity)
- Snap Wheel, snap presets, and Native, Bento and Tabs modes
- Tab strips with drag between groups
- AI recipes
- First-run permission screen and a login item
- Parking windows, and putting a quit app's windows back (orphans)
- Three-finger tap and swipe, the layout ghost preview, keeping full-screen windows in place, and 8 languages

How each item reads: **Trellis** = what it does. **Bower now** = the gap. **Build** = how, which files. Size: S ≤ ½ day, M 1–2 days, L 3–5 days, XL > 1 week.

---

## Phase 0: Foundations (everything else stands on these)

### 0.1 Window-server layer: windows and Spaces across all desktops (L)
- **Trellis:**
  - Lists every window on every Space through private SkyLight calls: `SLSWindowQueryWindows`, `SLSWindowQueryResultCopyWindows`, the `SLSWindowIterator*` family (window ID, parent, level, tags, attributes) and `SLSCopyWindowsWithOptionsAndTags`.
  - Lists each display's Spaces with `SLSCopyManagedDisplaySpaces`, and finds a window's Space with `SLSCopySpacesForWindows`.
  - Types: `MacSpaces` (`Space`, `Listed`), `DesktopsInUse`, `CGSSessionUniqueSessionUUID` (to tell login sessions apart).
- **Bower now:** Accessibility (AX) only, which sees the current Space only. That is the root of the full-screen and "windows on another desktop" problems.
- **Build:**
  - New `Sources/SkyLight.swift`: `dlsym` wrappers that fail soft (return nil and log) if a symbol is missing.
  - `MacSpaces.all() -> [displayUUID: [Space]]` and `space(of: CGWindowID)`.
  - `AX.windows()` stays the source for moving windows. SkyLight only answers "which windows exist where".
- **Tests:** a parser test on a captured `CopyManagedDisplaySpaces` plist fixture.

### 0.2 Window identity v2 (M)
- **Trellis:** `TrackedWindow` keeps:
  - `key`, `windowID`, `pid`, `bundleID`, `appName`, `title`
  - `document` (AXDocument), `identifier` (AXIdentifier), `profile` (browser profile)
  - `appLaunched`, `firstSeen`, `seenAtStart`
  - `dockable`, and `writesInFlight` (ignores its own move echoes)

  Its `Sightings` type records pid start times, so it can tell "the app restarted" from "the window is new".
- **Bower now:** matches by title, then profile suffix, then bundle ID. It has no document, AXIdentifier or launch time, and uses a time guard instead of counting its own writes.
- **Build:**
  - Add `document`, `identifier`, `appLaunched` and `firstSeen` to `Win` and `WindowRecord` in `Desk.swift`.
  - New match order in `Desk.match` and `Engine.orphanIndex`: identifier → document → exact title → profile → bundleID.
  - Add a `writesInFlight` counter on `Win.setFrame` so `kAXMoved`/`kAXResized` notifications Bower caused itself are dropped. This replaces the `lastSwitch`/`lastSpaceChange` time guards where possible.
  - Keep reading old `state.json` files: new fields are optional, extending `testOldStateFileStillLoads`.

### 0.3 Split the logic into a testable core (M)
- **Trellis:** layout logic lives in a separate `SpacesEngine` module (`Engine`, `Arrival`, `Departure`, `Ghost`, `SavedDisplay`, `WindowInfo`) with no AppKit, so it can be tested on its own.
- **Bower now:** `Engine.swift` mixes logic with AX calls.
- **Build:**
  - New target `BowerCore` in `project.yml` (a framework or plain sources) for `Geometry`, the layout tree (2.1), matching (0.2) and history (3.6).
  - `Engine` calls into it. Tests import `BowerCore`.

### 0.4 One event tap for mouse, keys and gestures (M)
- **Trellis:** `EventTap` (an active session tap) sees mouse down, drag and up, scroll, flag changes and gestures. It also calls `CGSSetConnectionProperty(…, "SetsCursorInBackground", true)` so it can change the cursor while it isn't the front app.
- **Bower now:** middle-click uses a monitor. There is no general tap, so title-bar drags, double-clicks and green-button clicks can't be seen or changed.
- **Build:**
  - New `Sources/EventTap.swift`: one `CGEventTapCreate(.cgSessionEventTap, .headInsertEventTap, .defaultTap, mask, …)`.
  - Callers register handlers: title-bar drag (2.3), double-click (3.2), green button (2.7), ⌘⇧-drag marquee (1.6), "a click ends the animation" (0.6).
  - Re-enable the tap on `tapDisabledByTimeout` and `tapDisabledByUserInput`.
  - Add the cursor property call.

### 0.5 Window pictures with ScreenCaptureKit (L)
- **Trellis:** `MacCapture`, `ShareableContent`, `CapturedFrame` and `WallpaperCapture` take still pictures of windows and the wallpaper.
  - Screen Recording permission is optional. Without it, windows show as their app's colour and icon (`appColours`, `appColourAmount` 0.25).
  - "Nothing is recorded or kept."
- **Bower now:** the layout ghost draws boxes.
- **Build:**
  - New `Sources/Capture.swift`: `SCShareableContent` plus `SCScreenshotManager.captureImage` for each window, with a small cache keyed by window ID that is cleared when a window changes.
  - App colour = the main colour of the app icon (average of a 16×16 downsample), mixed into grey by `appColourAmount`.
  - Add a Screen Recording step to `FirstRun.swift`, marked optional.
  - Use the pictures in `LayoutGhostView` right away. This is a visible win before Phase 3.

### 0.6 Animation engine and redraw handling (L)
- **Trellis:**
  - `animationSpeed`; Reduce Motion makes windows jump straight to their spot.
  - `interruptLandings`: a click during an animation ends it.
  - `redrawWait` 0.5 s: after a resize, cover the window with its old picture until the app has drawn at the new size (`PictureLayer`, `ProxyLayer`, `RestingProxy`).
  - `stretchPictures`: the picture stretches as the window moves, otherwise it is revealed or cropped.
  - "Wait for apps to redraw" slider.
- **Bower now:** windows are set to their final frame at once, and some apps flash.
- **Build:**
  - New `Sources/Motion.swift`: animate a transparent overlay of pictures (from 0.5) from the old frames to the new ones, set the real frames under the cover, then fade the overlay out after `redrawWait`.
  - Settings: speed slider, redraw wait (ms), stretch toggle, and "A click during an animation ends it".

### 0.7 Diagnostics and developer tools (M)
- **Trellis:**
  - `Report a Problem…`: a form ("What happened…", "What were you doing just before?") that writes an email with Mac details and logs attached. The user sees everything before it is sent.
  - Debug dumps to `/tmp/trelliswm-layout.json`, `-ax.json`, `-places.json` and `-still`.
  - `debug-new-session`, `debug-store-folder` and `debug-getting-started` launch flags.
  - Separate `.dev` and `.customer` bundle IDs.
  - Notes when another copy is running ("QUIT other copy pid").
  - `PERMISSIONS` log line.
- **Bower now:** no structured log, no report flow, no dump.
- **Build:**
  - Use `os.Logger` with a file mirror under `~/Library/Logs/Bower`.
  - Help menu → "Report a Problem…": a SwiftUI form, then `NSSharingService(named: .composeEmail)` with the logs, `state.json` with titles redacted, and the macOS version. Reveal the folder in Finder too ("Please attach the files…").
  - Launch arguments `-dumpLayout`, `-dumpAX`, `-storeFolder <path>` and `-newSession`.
  - Detect and quit a second running copy.

### 0.8 Settings by level, and release defaults (S)
- **Trellis:**
  - Each setting is tagged `standard`, `advanced` or `hidden` (the `offered` map in `ReleaseSettings.json`).
  - "Show advanced settings" toggle.
  - Dev builds: "View settings as a customer" and "Save Current Settings as Defaults", which writes the JSON.
  - "Restore Defaults".
- **Bower now:** every setting always shows, and defaults are hard-coded.
- **Build:**
  - Add `Resources/Defaults.json` and a `SettingVisibility` enum.
  - A `SettingRow` wrapper in `Settings.swift` hides by level.
  - Add the "Show advanced settings" toggle at the bottom of General.

---

## Phase 1: Gestures and taking over from macOS

### 1.1 Take the Dock swipe from macOS (M) ← highest value
- **Trellis:** `DockSwipeTap` has two active session taps.
  - One for event type **30** (`1<<30`, Dock control). This is where the swipe data lives:
    - field **110** = HID event type, 23 for a Dock swipe
    - field **123** = axis: 1 for horizontal, 2 for vertical
    - field **132** = phase
    - field **124** = progress (double)
    - field **129** = velocity (double)
    - it also reads field 42
  - One "envelope" tap for type **29** (`1<<29`, gesture).
  - Its `DockSwipeFilter` (with `State` and `Action`) decides what to do:
    - sideways swipes are dropped (`droppingSideways`), so macOS never switches Spaces;
    - other events are held (`held: [CGEvent]`) and passed back if the gesture isn't Trellis's;
    - **fn** held means pass through to macOS.
- **Bower now:** reads MultitouchSupport and asks the user to change macOS settings. Both act on the same swipe.
- **Build:**
  - New `Sources/DockSwipe.swift`. Swipe direction comes from field 123 and its sign from progress. Steps happen at phase end, using the progress threshold and velocity.
  - `Engine.step(±1)` at the end. fn passes through.
  - Keep the MultitouchSupport path only for three-finger *taps*.
  - Remove the conflict note from Settings and replace it with 1.2.
- **Needs:** macOS's own swipe for Spaces set to the matching finger count. That is the reverse of today. Trellis says: "Needs three-finger swipes turned on for switching Spaces and Mission Control".

### 1.2 Finger-count choice and plain-language conflict text (S)
- **Trellis:** a Three fingers / Four fingers picker for moving around.
  - Text explains exactly what will stop working, for each combination of Spaces, Mission Control and Show Apps or Desktop.
  - It checks the macOS trackpad settings: `TrackpadThreeFingerHorizSwipeGesture`, `TrackpadThreeFingerVertSwipeGesture`, `TrackpadFourFingerHorizSwipeGesture`, `TrackpadFourFingerVertSwipeGesture`, `TrackpadFourFingerPinchGesture` and `TrackpadThreeFingerDrag`.
  - "Needs three-finger drag turned off".
  - "Open macOS Trackpad Settings" button.
- **Build:**
  - In the Shortcuts tab, replace "Three-finger swipe changes layout" with a finger-count picker.
  - Build the explanation text from the current defaults, with every combination as its own localized string so translations stay whole sentences.

### 1.3 Mission Control replacement (L, after 3.4)
- **Trellis:**
  - `MissionControl` attaches an AXObserver to the Dock app for `AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeShowDesktop` and `AXExposeExit`.
  - It turns off macOS's own Mission Control shortcuts with `CGSSetSymbolicHotKeyEnabled` (reading `CGSGetSymbolicHotKeyValue` and `CGSIsSymbolicHotKeyEnabled`), and turns them back on when it quits.
  - It sends Mission Control itself with `CoreDockSendNotification("com.apple.expose.awake")`.
  - "Show TrellisWM's overview instead". Opened another way (Dock icon, hot corner), macOS's Mission Control shows for a moment first. fn keeps the real one.
  - Option `overviewSwipesSpaces` (experimental): swipe between Spaces inside the overview.
- **Build:**
  - New `Sources/MissionControl.swift`.
  - Restore the shortcuts in `applicationWillTerminate`, and on the next launch if Bower crashed. Keep a "disabled by Bower" marker in state.

### 1.4 Find and turn off macOS features that fight Bower (M)
- **Trellis:** `MacConflicts` (`Conflict`, `State`) checks:
  - Edge tiling, from the `com.apple.WindowManager` tiling keys. "Holding ⌥ to tile still works."
  - "Click wallpaper to reveal desktop (Always)" (`EnableStandardClickToShowDesktop`)
  - Stage Manager (`GloballyEnabled`)
  - The trackpad gestures from 1.2

  The screen offers "Turn Them Off" or "Turn Back On" for each one. When none are on: "None in the way". It also reminds "Uninstalling? Turn them back on first."
- **Build:**
  - New `Sources/Conflicts.swift`, which reads and writes those defaults and then restarts `WindowManager` or the Dock as needed.
  - Add a step in `FirstRun.swift` and a section in General.
  - Turning things off needs a clear button the user presses; Bower never does it silently.

### 1.5 Pinch and pan (M, after 3.1)
- **Trellis:**
  - ⌥-pinch anywhere zooms.
  - Pinching on bare desktop works without ⌥ (`deskPinchSteps`, "Pinching on the Desk").
  - Two-finger pan with ⌥, and `touchPinchPan` (pinch and pan together).
  - `panSensitivity` 1.8.
  - Stepping mode (pinch out = in a level toward the pointer, pinch in = out a level), with `stepTowardPointer`.
  - Four-finger pinch can be taken over.
- **Build:**
  - Use magnify and scroll gesture events from the event tap (0.4, types 29 and 22).
  - Settings: "Pinch to zoom: Anywhere with ⌥ / on bare desktop", "Pinch steps a level", "Pan speed".

### 1.6 Zoom to a rectangle (S, after 3.1)
- **Trellis:** ⌘⇧-drag (or ⌘⌥⇧) a rectangle around windows, and the view zooms to fit them. Esc cancels. Built with a `MarqueePanel`.
- **Build:** a marquee overlay driven by 0.4, which calls `Zoom.frame(rect)`.

---

## Phase 2: Docking, a never-overlap tiling tree

Trellis's core idea: windows don't overlap. They sit in a nested tree you zoom through. In Bower this becomes a new **Window Mode, "Dock"**, next to Native, Bento and Tabs, chosen per display per layout. The other modes stay as they are.

### 2.1 Layout tree model (L)
- **Trellis node kinds:**
  - `desktop`
  - `split` (`axis`, `weights`, `children`)
  - `tabbed` (`selected`)
  - `panel`
  - `floating` / `docked`
  - `hiddenDesktop`
  - `group`, plus `parent`, `order` and `scale`

  It keeps one "World" for each display and Space. Its solver works with axis, edge, seam, boundary, the "cramped" flag and the return path. Free version: limited to a few docked windows per desktop.
- **Build:**
  - `BowerCore/DockTree.swift` with a `Node` enum, `solve(in rect, gap) -> [key: CGRect]`, `insert(key, at: edge, of: node)`, `remove(key, share: Bool)` and `resize(seam, by:)`.
  - Store it in `Layout.modes` next to the existing mode, keyed by display.
  - Add property tests: inserting then removing a window gives back the same tree, and frames never overlap.

### 2.2 Dock mode in the wheel and menus (S)
- Add `WindowMode.dock` with a demo in `Demo.swift` and translated text.

### 2.3 Drag to dock (XL)
- **Trellis:**
  - Drag a window by its title bar to the edge of the screen or of another window. A drop preview (`DropPreviewPanel`) shows where it will land.
  - "Hold over a target" sets the delay before the layout makes room. Letting go drops it there at once.
  - `previewDrags` and `previewStyle` (`tinted`): "Move the real window, show where it will land" or "Move a picture and make room, like Overview".
  - `reflowWhileDragging`: windows make room live, otherwise they're covered until you let go and resized once.
  - `keepPushed`: pushed windows stay pushed while dragging, otherwise dragging back undoes each push.
  - `tuckStrips`: tuck the tab strip away while its window moves.
  - Dropping on the *middle* of another window makes a tab group (4.1).
- **Build:**
  - Find title-bar drags with the 0.4 tap. Hit-test the AX title bar with the `AXTitleUIElement` area, falling back to the top 28 pt.
  - Work out the drop target from the pointer against tree leaves: the edge band is 25% of the size, the middle is a tab target.
  - Draw the preview with a picture (0.5) or a tinted box. Reflow by solving a trial tree.

### 2.4 Gaps and dragging gaps to resize (M)
- **Trellis:**
  - `gap` 12 ("Space between windows"), and `desktopEdgeStrength` (how strongly the screen edge pulls).
  - `deskGapHandles`: drag the gaps between windows to resize them (`GapHandleWindow`/`GapHandleView`), with `gapHandlesAlwaysShown` or show on hover ("Always show drag handles").
- **Bower now:** a fixed 6 pt gap in Bento.
- **Build:**
  - Add a gap setting used by Bento and Dock.
  - Put thin transparent panels over each seam that change the cursor (needs 0.4 cursor property) and drag to update `weights`.

### 2.5 What happens when a window closes (S)
- **Trellis:** `shareRemovedSpace`. On: closing exactly undoes adding (the whole row shares the space). Off: the neighbour after it takes all its space (`neighbourLeaves`).
- **Build:** a flag for `DockTree.remove`, plus a setting.

### 2.6 Minimum sizes and windows that don't fit (M)
- **Trellis:**
  - `squeezeBelowMinimum`: windows can be squeezed below their app's minimum.
  - `fixedMinimum`: "Only when the app can't go smaller".
  - A window too small for its app shows as its icon until there's room; double-click it to go in (`CollapsedGroupPanel`/`Layer`/`View`). It becomes a real window again as soon as it fits.
  - Option "Below 480 × 320".
  - `AppLimitStore` caches each app's minimum size.
- **Build:**
  - After `setFrame`, read back the actual size. A larger result means the app's minimum, so cache it in `AppLimitStore`.
  - The solver respects minimums, or collapses the window to an icon panel.

### 2.7 Float and dock with the green button (M)
- **Trellis:**
  - `TrafficLights` takes over the green button. Click: float on the Desktop or dock again. fn-click: real full screen. ⌥-click: zoom.
  - "Float All Windows on Desktop".
  - `soleFloatTakesDesktop`: a window that's the only one floating fills the Desktop's space, and the Desktop hides until it's floated again.
- **Build:**
  - Hit-test `AXFullScreenButton` on mouse-down in the 0.4 tap, swallow the click, and toggle the node between floating and docked.
  - Add a menu item and a wheel action, "Float All".

### 2.8 The Desktop as a tile (M)
- **Trellis:**
  - The Desktop has its own tile; "the Desktop's own space always stays clear".
  - "Hide Desktop in This Space" / "Show Desktop in This Space". Status: "The Desktop is hidden in this Space".
  - `hiddenDesktopReturns`: floating a window brings the Desktop back.
  - "Allow docking into the Desktop's tile".
  - A window that can't be docked gets a Desktop of its own while it's open.
- **Build:** a `desktop` node in the tree, plus menu items, a setting and a shortcut (`desktop`).

### 2.9 Turn tiling on per desktop (S, after 0.1)
- **Trellis:**
  - "Use TrellisWM on This Desktop" in the menu.
  - Setting: arrange as first seen, either "First desktop only" or "All desktops". Each one arranged uses more memory.
  - Status: "TrellisWM: off on this desktop".
- **Build:** store a Space ID set in state, and gate `Engine` on the current Space (from 0.1).

### 2.10 Leave some apps alone (S)
- **Trellis:**
  - "Don't Arrange “X”" / "Arrange “X” Again" in the menu.
  - A Settings list: "Windows of these apps are left alone: they float freely and are never arranged."
- **Bower now:** only routes. There is no exclusion list.
- **Build:**
  - `state.ignoredApps: Set<bundleID>`, checked in `Engine` retile, Bento, Tabs and Dock.
  - Add a menu item and a list with − in Settings.

### 2.11 Arrange and split commands (S)
- **Trellis shortcut and command list:** `everything`, `stepOut`, `stepIn`, `left`, `right`, `up`, `down`, `back`, `forward`, `maximize`, `desktop`, `split`, `arrange`, plus save and go for views 1–9.
  - "Arrange every window into tiles" (`arrange`, `arrangeAllDesktops`).
  - "Split the active tile with a new Finder window".
- **Build:** add these to the `ShortcutID` enum and the wheel action palette.

### 2.12 Full screen as a tile (M)
- **Trellis:**
  - `FullScreenTile` (`Layer`/`View`): full-screen windows show as tiles in the overview.
  - `WindowTracker.fullScreen` tracks them separately.
  - The green button frames the window instead of going full screen.
- **Bower now:** turns full screen off and maximizes (`keepFullScreenHere`).
- **Build:** use 0.1 to see full-screen Spaces, and show them as tiles in the overview (3.4).

### 2.13 Park hidden windows small (S)
- **Trellis:** `parkOutOfViewSmall`. Windows out of view, and a group's other tabs, are made small, which leaves room for the rest in Mission Control. Each one is resized when shown again.
- **Build:** an option in `Engine.park`: shrink to 200×150 at the parking spot, and use the `saved[]` frame to restore it.

---

## Phase 3: Zoom, overview and getting around

### 3.1 Desk renderer (XL)
- **Trellis:**
  - `StagePanel` / `StageView` / `StageRenderer` draw every window as a picture layer on a full-screen panel, so zooming and panning are smooth, then hand off to the real windows.
  - `BlurredBackdrop` and `SlideBackdrop`.
  - `DimPanel` / `DimLayer`: `dimOpacity` 0.3, `dimBlur` 20, `dimDocked` ("Darken the background behind arranged windows").
  - Preview look: "Picture under colour and icon", "Colour and app icon", `tintOpacity`.
- **Build:**
  - New `Sources/Stage.swift`: a borderless panel above everything, with Core Animation layers from 0.5 pictures. A camera transform supports zoom and pan.
  - On finish, set the real window frames (0.6) and hide the stage.

### 3.2 Zoom levels and framing one window (L)
- **Trellis:**
  - "Everything": zoom out from where you are to everything.
  - Step in and out a level.
  - "Frame the focused window on its own" ("Focus on one window"): double-click a title bar to frame it, double-click again to go back, ⌥-double-click still zooms (`windows.Title bar` setting).
  - Feedback text: "Framed on its own." "Zoomed." "Zoomed to fit."
- **Build:**
  - Zoom state = which tree node fills the screen.
  - A double-click handler in the 0.4 tap on the title-bar area.
  - Add shortcuts.

### 3.3 Move to the neighbouring window or space (M)
- **Trellis:** shortcuts and swipes go to the neighbouring space left, right, up or down. Past the layout's edge, a sideways swipe switches macOS Spaces.
- **Build:**
  - Find the neighbour in the tree by geometry.
  - At the edge, call 1.1's pass-through or post a Space switch (⌃→ via `CGEvent`).

### 3.4 Overview (M after 3.1)
- **Trellis:**
  - "Every window on every display, your Spaces along the top. Click one to go to it." (`SpacesBarPanel`, `SpaceTileView`)
  - "Click or drag a rectangle to go in · Esc to go out · Pinch or scroll to zoom · ⌥-drag to rearrange"
  - "Release to focus X · Esc to cancel"
  - "Stay in Overview" and "After pinching out" settings.
  - Opened with a swipe up with N fingers, a shortcut or the menu.
- **Build:**
  - The stage from 3.1 at the zoomed-out level, plus a Spaces bar from 0.1.
  - ⌥-drag in the overview edits the tree (2.1).

### 3.5 Minimap (M)
- **Trellis:** `MinimapView` (with tiles) shows a small map of the arrangement while moving around.
- **Build:** a SwiftUI panel drawn from the tree's frames, shown during 3.3 and 3.2 moves and faded after 1 s.

### 3.6 Back and forward history (S)
- **Trellis:**
  - "Press X to go back to where you were, Y to go forward."
  - Menu-bar arrows (`historyButtons`), also on each tab strip.
  - "Go to where it settles".
- **Build:**
  - A `BowerCore/History.swift` stack of view states (layout, zoom node, focused key).
  - Push on every switch, zoom and frame. Add shortcuts and menu buttons.

### 3.7 Saved views 1–9 (M)
- **Trellis:**
  - "⌃⌥1–9 saves what you're looking at; another modifier with 1–9 brings it back."
  - Menu: Save This View, Go to view N, Forget View N, "View N: name".
  - Saved views show in the menu bar, with a right-click menu.
  - Modifier conflict checks ("Going to and saving views need different modifiers").
- **Conflict:** Bower already uses ⌥1–9 for layouts and ⇧⌥1–9 for sending a window.
  - Saved view = a zoom or frame target *inside* a layout.
  - Default it to ⌃⌥1–9 to go and ⌃⌥⇧1–9 to save, and check modifiers against Bower's own shortcuts.
- **Build:** `state.views: [Int: ViewState]`, using the shortcut recorder conflict checks from 6.4.

### 3.8 Space switch animation (M)
- **Trellis:** `SpaceZoom` (`run(from:covered:)`, `finish()`) and a "Space carousel" animate the change of Space.
- **Build:** after 1.1 steps a Space, show a stage snapshot that slides, while macOS switches underneath.

### 3.9 Feedback toasts and hover labels (S)
- **Trellis:**
  - `HUDView` messages: "Docked. Its neighbours made room.", "Grouped. Click a tab to switch.", "Floating on the Desktop.", "Moved with your fingers.", "There and back.", "%ld windows put back".
  - `HoverLabel` shows a window's name in the overview.
- **Build:** reuse Bower's `OverlayPanel` with a short-lived HUD. Respect Reduce Motion.

---

## Phase 4: Tab groups, brought level

Bower already has tab strips in Tabs mode. Trellis adds the following.

### 4.1 Group any windows by dropping on the middle (M, after 2.3)
- **Trellis:** drag a window onto the middle of another and pause a moment. Let go, and they share a strip of tabs. This works for any apps, floating or docked.
- **Build:** the middle target from 2.3 creates a `tabbed` node, or a Bower tab group in any mode.

### 4.2 The group's window buttons act on the whole group (M)
- **Trellis:**
  - `windowButtonsActOnGroup`: a group's red, yellow and green buttons close, minimise, and dock or float the whole group.
  - ⇧-click acts on the other choice ("The whole group" vs "The tab shown"). fn-click uses macOS's own.
  - Green on the tab shown takes it out of the group.
- **Build:** use the 0.4 tap to hit-test the window buttons of grouped windows.

### 4.3 Tab right-click menu (S)
- **Trellis:** Close Tab, Minimize Tab, Move Tab to New Window.
- **Build:** a `contextMenu` on the strip's tab view in `Tabs.swift`.

### 4.4 Tab strip appearance (M)
- **Trellis settings:**
  - `tabStyle`: material, glass ("the wallpaper, blurred"; "darker to the left, lighter to the right") or solid.
  - Selected tab: rounded chip (`tabSelectedChip`), with `tabChipMargin` 4.
  - `tabInset` 2, `tabPadding` 8, `tabTint`.
  - `tabStripLights`: traffic lights on the strip.
  - `tabCloseButtons`, and `tabCloseOnRight`.
  - `tabGlassOpaqueWhenInactive`.
  - A dragged tab is always a chip, with corners concentric with the strip.
  - "Follows light and dark mode."
  - `tabSort`.
- **Build:** a Tabs section in Settings, mostly advanced level (0.8). `TabStripView` reads the values.

### 4.5 Tuck the strip while moving (S)
- **Trellis:** `tuckStrips` hides the strip while its window is dragged.
- **Build:** hide the strip panel during title-bar drag (0.4) and show it on mouse-up.

---

## Phase 5: Window memory

### 5.1 Putting windows back (M)
- **Trellis:** `returnReopenedWindows` has three choices:
  - Never
  - After a quit or restart (`afterQuit`)
  - Also when reopened: a window closed and opened again goes back, but only if it can be told apart by its document, and only within a day.

  A "%ld windows put back" notice (`PutBackNotice`) appears.
- **Bower now:** orphans return after a quit, with no choice, no "closed and reopened" case and no notice.
- **Build:**
  - Add a setting.
  - Keep closed-window records with `closedAt` and `document` (0.2), and match them within 24 h.
  - Show the HUD from 3.9.

### 5.2 Missing windows: see and forget (S)
- **Trellis:**
  - A list of "Windows that haven't come back since they closed, their app quit or the Mac restarted: their places, and what TrellisWM knows them by."
  - "Forget Missing Windows…" with a count: "%1$@ (%2$ld missing)".
- **Build:** a Settings section that lists `state.orphans`, with Forget for each and Forget all, plus a confirm dialog.

---

## Phase 6: App shell

### 6.1 Menu-bar control strip (M)
- **Trellis:**
  - `MenuBarControl`, `MenuBarStrip` (segments) and `MenuBarControlsEditor`: several menu-bar buttons (Everything, back, forward, saved views…) that you drag into order.
  - The app's icon opens its menu; right-clicking any button does too.
  - `menuBarFill` 0.12 sets how white the frame around them is.
  - Update reminders put a dot on the icon.
- **Build:**
  - Several `NSStatusItem`s, or one with a custom segmented view.
  - An editor list in Settings. The update dot comes from 6.2.

### 6.2 Self-update with Sparkle (M)
- **Trellis:**
  - Sparkle 2 with an appcast, an EdDSA public key and automatic checks.
  - "Get beta versions": "Turned off, you stay on the beta you have until the next release."
  - "Update reminders", and "Update to X…" in the menu.
  - Dev builds say "This build doesn't update itself", and only releases from the website check for updates.
- **Build:**
  - Add Sparkle through SPM in `project.yml`.
  - Host `appcast.xml` (GitHub Releases plus Pages on the user's site), with a generated EdDSA key kept in the Keychain and CI.
  - Add a beta channel through Sparkle `channels`.

### 6.3 Command links: `bower://` (S)
- **Trellis:** `trelliswm://` links let Raycast, Alfred, Shortcuts or a script run every command.
- **Build:**
  - Add `CFBundleURLTypes` in `Info.plist` and `application(_:open:)` in `AppDelegate`.
  - Commands: `bower://layout/3`, `send/3`, `snap/leftHalf`, `wheel`, `mode/bento`, `workspace/<name>`, `view/2`, `back`, `everything`, and so on.
  - Document them on the help page.
  - Add App Intents for Shortcuts later.

### 6.4 Shortcut recorder conflict messages (S)
- **Trellis:**
  - "%1$@ was %2$@; that has no shortcut now." (taking a key moves it from the old action)
  - "Shortcuts need ⌃, ⌥ or ⌘."
  - "That key isn't for TrellisWM."
  - "%1$@ with a number is %2$@. Change that first."
  - "Delete clears it; Esc cancels."
- **Build:** add these checks to the recorder in `Settings.swift`.

### 6.5 Onboarding: welcome, lessons, what's new (L)
- **Trellis:**
  - `WelcomeWindow` steps: Accessibility (moves on by itself once allowed), Screen Recording (optional), "Turn off what gets in the way" (1.4), gestures, then "Start Using TrellisWM".
  - `GettingStarted`: interactive lessons. Each step waits for you to *do* the move: dock a window, float, zoom out, frame, save a view, make a tab group, zoom to a rectangle…
  - Lesson cards show "Getting started · n of m", with "Keep Learning", "Skip", "Skip all" and "That's the basics".
  - "What's New (n of m)" for new releases.
  - Lessons are bundled HTML in a WKWebView.
  - "New to this? Read the guide".
- **Bower now:** a first-run permission screen and a static help site.
- **Build:**
  - A `Lessons.swift` step list. Each step has a text and a completion check hooked to Engine events (switched layout, opened wheel, snapped, sent window, saved workspace…).
  - A floating `GettingStartedCard` panel.
  - A What's New list keyed by version.
  - Reopen everything from Settings ▸ General.

### 6.6 Appearance settings (S)
- **Trellis:** animation speed, app colour on or off and amount, tint, background darkness and blur, desktop edge, frame, and preview style.
- **Build:** an Appearance tab in Settings that gathers settings from 0.5, 0.6, 3.1 and 4.4.

### 6.7 Simplified Chinese (S)
- **Trellis:** ships `zh-Hans`.
- **Build:** add zh-Hans to `Localizable.xcstrings` (Bower has 8 languages today).

### 6.8 Paid Pro tier (decision, not build)
- **Trellis:**
  - Free tier: a limited number of docked windows for each desktop.
  - Pro: monthly, yearly or lifetime. It unlocks unlimited windows, tab groups, saved views and command links.
  - Keychain license store, activations for each Mac, and an upgrade prompt.
- **Bower:** free and open source. Listed so nothing is skipped. Recommendation: **don't port**. If wanted later, add a Sponsor link in About instead.

---

## Order and size

| # | Phase | Depends on | Size |
|---|---|---|---|
| 1 | 0.2 identity, 0.3 core split, 0.8 setting levels | — | M+M+S |
| 2 | 1.1 swipe takeover, 1.2 finger choice | — | M+S |
| 3 | 0.4 event tap, 0.7 diagnostics, 6.3 URL, 6.4 recorder, 2.10 ignore apps, 4.3 tab menu, 5.2 missing windows | — | ~1 week |
| 4 | 0.1 SkyLight, 2.9 per-desktop, 1.4 conflicts | 0.1 | L+S+M |
| 5 | 0.5 pictures, 0.6 motion | 0.4 | L+L |
| 6 | 2.1–2.8, 2.11–2.13 Dock mode | 0.3, 0.4, 0.6 | XL (≈3 weeks) |
| 7 | 3.1–3.9 stage, zoom, overview, views, history | 0.5, 0.6, 2.1 | XL (≈3 weeks) |
| 8 | 1.3 Mission Control, 1.5 pinch, 1.6 marquee | 3.1, 3.4 | L+M+S |
| 9 | 4.1, 4.2, 4.4, 4.5 tabs | 2.3, 0.4 | M+M+M+S |
| 10 | 5.1 put back, 6.1 menu strip, 6.2 Sparkle, 6.5 lessons, 6.6 appearance, 6.7 zh-Hans | most of the above | ~2 weeks |

Total: about 12–14 weeks for one person. Steps 1–3 are shippable on their own and fix today's pain (swipe conflict, matching, missing tools).

## Risks
- **Private APIs:**
  - Exposed: SkyLight/CGS, `CoreDockSendNotification`, symbolic hotkeys, MultitouchSupport, Dock event fields 110/123/124/129/132.
  - Each must fail soft and log. Test on every macOS beta.
  - Not allowed in the Mac App Store. Bower ships outside it already.
- **Changing system settings** (1.3, 1.4): always through a button the user presses, always restored on quit or uninstall. Keep a marker so a crash restores them on the next launch.
- **Event taps** add input lag if slow: the handlers must return in < 1 ms, with anything heavy run asynchronously.
- **Two models side by side:** Bower's "swap the whole desk" layouts and Trellis's "zoom through one tree". Keep Dock as a mode inside a layout, so Native, Bento and Tabs users see no change.
- **Screen Recording** permission is optional everywhere. Every picture feature needs the colour-and-icon fallback.
