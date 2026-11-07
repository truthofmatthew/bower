# Trackpad test plan

What a person has to test by hand: real touches can't be simulated, and the three-finger tap comes straight from the
trackpad hardware. About 20 minutes. Tick each box; for anything that fails, note what you did and what happened, then
use Help › Report a Problem.

## Before you start

- [ ] Bower is the latest build (About shows the version you expect).
- [ ] Settings › General › Mac setup says "Everything's set", or only lists Screen Recording.
- [ ] Write down your macOS trackpad settings (System Settings › Trackpad › More Gestures): Swipe between full-screen
      applications (three or four fingers), Mission Control (three or four fingers, swipe up), App Exposé. Bower adapts
      to them, so the results depend on them.
- [ ] Three layouts with windows: one in Dock mode with 3–4 windows, one in Tabs mode, one in Native.

## 1. Swiping between layouts (three or four fingers, sideways)

Settings › Gestures › Move around with: set it to the fingers macOS uses for "Swipe between full-screen applications".

- [ ] Swipe left: the next layout slides in under your fingers and stays when you let go.
- [ ] Swipe right: the previous layout.
- [ ] Slow, short swipe and let go early: it springs back to where you were; nothing changes.
- [ ] Quick flick: it changes layout even though your fingers barely moved.
- [ ] Past the last layout with windows: macOS's own desktop switch happens instead.
- [ ] Hold fn while swiping: macOS's own swipe, never Bower's.
- [ ] Settings › Gestures › Swipe the other way round: directions flip.
- [ ] Ten fast swipes back and forth: it ends on the right layout, every window where it belongs, no stuck windows.
- [ ] Right after a swipe, pinch in Safari or Preview: it zooms. (Swipes used to block pinches until the next swipe.)
- [ ] Swipe with the other number of fingers (not the one chosen): Bower does nothing; macOS does what it usually does.

## 2. Swiping up (Mission Control)

Settings › Gestures › Show Bower's overview instead.

- [ ] Off: swiping up opens macOS Mission Control as usual.
- [ ] On: swiping up opens Bower's overview; swiping up or Esc closes it.
- [ ] On, holding fn: macOS Mission Control.
- [ ] The Mission Control key and the Dock's Mission Control icon follow the same setting.

## 3. Three-finger tap (Snap Wheel)

Settings › Gestures › Snap Wheel. If macOS uses a three-finger tap for Look Up, Mac setup says so: change Look Up to
"Force click with one finger" first.

- [ ] Tap with three fingers over a window: the wheel opens under the pointer, acting on that window.
- [ ] Tap again without moving: it closes.
- [ ] Tap, move onto an action, tap or click: the action happens to the window that was under the pointer.
- [ ] Tap over the bare desktop: it acts on the focused window.
- [ ] Three-finger drag (if turned on in Accessibility) still drags windows, and doesn't open the wheel.
- [ ] Typing with a palm resting on the trackpad doesn't open the wheel.

## 4. Pinch (Expand and the overview)

Settings › Gestures › Pinching: "With ⌥ anywhere, or on bare desktop".

- [ ] Pinch in Safari, Preview and Maps without ⌥: the app zooms; Bower does nothing.
- [ ] Pinch in over the bare desktop: the overview opens. Pinch out: it closes.
- [ ] Dock mode, hold ⌥, pinch out over a window: one level of Expand, toward the focused window. Again: one more level.
- [ ] Hold ⌥, pinch in: back a level; at the whole layout, the overview opens.
- [ ] One long pinch moves one level, not two.
- [ ] Bower off on a desktop (This Display › Use Bower on This Desktop): ⌥-pinch out says Bower is off there.
- [ ] Switch Pinching to "Anywhere, without ⌥": pinching in apps now drives Bower. Switch it back.

## 5. Two fingers

- [ ] Scroll in any app: it scrolls normally, with and without Bower.
- [ ] Dock mode, expanded onto one window, hold ⌥ and scroll sideways: the expand moves to the next window. Past the
      last window: the next layout.
- [ ] Settings › Gestures › Pan speed (shown with advanced settings on): faster and slower feel right.
- [ ] Two-finger click (right-click) on a tab in a tab strip: the tab menu (Close, Minimize, Move to New Window).

## 6. One finger: clicks and drags

- [ ] Dock mode: drag a title bar onto another window's edge, hold briefly: neighbours make room; let go: it docks.
- [ ] Drag onto the middle of a window: they become a tab group with a strip.
- [ ] Drag a gap between windows: both sides resize; the tab strips follow when you let go.
- [ ] Double-click a title bar: that window on its own; again: back.
- [ ] Green button: floats; again: docks. fn-click: macOS full screen. ⌥-click: macOS zoom.
- [ ] ⌘⇧-drag a rectangle around two windows: those expand. Around everything: it says so.
- [ ] Tabs mode: click a tab, drag a tab along the strip, drag a tab to the pane's right edge to split.
- [ ] Drag a file from Finder onto another tab and hold: that tab opens after about half a second; drop it into the
      window. Same with a link from Safari.
- [ ] Force click (if Look Up is on force click): Look Up works in apps; Bower ignores it.
- [ ] Tap to click on: tabs, the wheel and the overview all respond to taps, not only to presses.

## 7. Multiple displays

Only with a second display connected.

- [ ] Each display swipes, pinches and expands on its own: the gesture acts on the display under the pointer.
- [ ] ⌃⌥⌘ and an arrow at the edge of one display carries focus to the other.
- [ ] ⌃⌥M sends the focused window to the other display; Dock and Bento displays re-arrange.
- [ ] Unplug the second display: its windows go to the Offline shelf; plug it back: they return.

## 8. Under load

- [ ] With 15+ windows across layouts: swiping still follows the fingers without stutter.
- [ ] While an app is busy (exporting, compiling): swipes and pinches still respond.
- [ ] After waking from sleep: swipe, pinch, three-finger tap still work without restarting Bower.
- [ ] Activity Monitor: Bower near 0% CPU when idle, under ~100 MB of memory after an hour of use.

## Results

| Section | Pass | Notes |
| --- | --- | --- |
| 1. Swiping | | |
| 2. Swiping up | | |
| 3. Three-finger tap | | |
| 4. Pinch | | |
| 5. Two fingers | | |
| 6. One finger | | |
| 7. Displays | | |
| 8. Under load | | |
