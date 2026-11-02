<p align="center"><img src="docs/icon.png" width="160" alt="Bower app icon: an arch of golden sticks over four tiles in teal, cream and blue, on a dark teal background"></p>

# Bower

A window and workspace manager for macOS. Give each project a named layout and switch your whole desk, across every display, with ⌥1–9. There's no Spaces animation: windows from other layouts move out of the way and the layout you picked comes back where you left it.

It's native Swift with no dependencies, no account and no telemetry. It needs only the Accessibility permission, and SIP stays on.

<p align="center"><img src="docs/screenshots/wheel.png" width="560" alt="The Snap Wheel: a radial menu with snap targets on the inner ring, actions on the outer ring and the Layouts arc open, hovering layout 2, Design"></p>

## What it does

The UI follows the design canvas in [docs/design/](docs/design/); the plan is in [docs/DESIGN.md](docs/DESIGN.md).

- **9 named layouts** across every display: switch instantly, send a window to another layout, route apps to layouts so their new windows land there.
- **Window Modes per display, per layout:**
  - **Native**: windows where you put them, with snapping.
  - **Bento Box**: auto-tiled; it retiles the moment a window opens or closes.
  - **Tabs**: windows from any app share a pane under a tab strip. Drag a tab to the pane's right edge to split it into two groups, or onto the other strip to move it. ⌃Tab cycles tabs in the focused group.
- **Snapping** with a live preview: halves, quarters, thirds, two thirds, maximize.
- **Snap Wheel** (middle-click or ⌃⌥Space). Its outer ring is yours to arrange in Settings › Snap Wheel, with extra actions: Center, Almost Maximize, Next Display, Restore, Minimize, Hide Others, and the presets Split, Four Corners and Focus + Stack.
- **Layouts Bar** (⌥↑): every layout and its windows; drag a window onto a layout.
- **Workspaces**: save every layout, mode and window position under a name and load it later.
- **Continuity**: when an app quits and comes back (or the Mac restarts), its windows return to their layouts and places. A display that disconnects keeps its windows on the Offline shelf until it's back.
- **AI Recipes**: describe your desk in Markdown and let a local or hosted model plan it.
- **Shortcuts**: every one can be rebound in Settings › Shortcuts, with an ISO keyboard preset and conflict warnings.

## Screenshots

<p align="center"><img src="docs/screenshots/layouts-bar.png" alt="The Layouts Bar: nine layout chips with the app icons of their windows; layout 3, Dev, is current"></p>

| | |
| --- | --- |
| <img src="docs/screenshots/settings-layouts.png" alt="Settings, Layouts tab: nine layouts with a Window Mode each, and app routing"> | <img src="docs/screenshots/settings-wheel.png" alt="Settings, Snap Wheel tab: the wheel and a palette of actions to drag onto its outer slots"> |
| <img src="docs/screenshots/recipe.png" alt="The Recipe editor: a Markdown recipe on the left, the planned layout for each display on the right"> | <img src="docs/screenshots/settings-shortcuts.png" alt="Settings, Shortcuts tab: every shortcut with a recorder, and the ANSI or ISO keyboard choice"> |
| <img src="docs/screenshots/first-run.png" alt="The welcome window: grant Accessibility, try ⌥1 and ⌥2, open the Snap Wheel"> | <img src="docs/screenshots/about.png" alt="The About window: Bower's icon, version, Made by Matthew Truth, GitHub and website links"> |

## Shortcuts

| Key | Action |
| --- | --- |
| ⌥1 – ⌥9 | Switch layout |
| ⇧⌥1 – ⇧⌥9 | Send the focused window to a layout |
| ⌥Tab | Next layout |
| ⌥N | Next empty layout |
| ⌃⌥← → ↑ ↓ | Halves |
| ⌃⌥U I J K | Quarters |
| ⌃⌥D F G | Thirds (ISO keyboards: ⌃⌥D < G) |
| ⌃⌥E / ⌃⌥T | First / last two thirds |
| ⌃⌥↩ | Maximize |
| ⌃⌥R | Retile the display (Bento Box) |
| ⌃⌥⌘← → ↑ ↓ | Focus the window to the left / right / above / below |
| ⌃Tab | Next tab in the focused group (Tabs Mode) |
| ⌃⌥Space, middle-click, or a three-finger tap | Snap Wheel |
| ⌥↑ | Layouts Bar |
| ⌃⌥S | Save the current workspace |

Every shortcut can be changed or cleared in Settings › Shortcuts. A snap shortcut shows where the window will land while you hold it, and moves the window when you let go.

**Snap Wheel:** hold the middle button, move onto an action and release. Or click (or three-finger tap) once to keep it open and click an action. From the keyboard: an arrow picks a wedge, arrows step around the ring, Tab switches rings, → opens a ▸ arc, Return runs, Esc closes. The three-finger tap is off when macOS already uses it for Look Up; it reads the trackpad through a private macOS framework.

## AI Recipes

A Recipe is a Markdown file that describes your desk:

```md
## Projects & Layouts
- Dev — @Code + @Terminal on @main monitor
- Comms — @Slack on @side monitor

## Window modes
- @side monitor uses Bento Box
```

Type `@` for running apps and displays. **Preview** asks a model for a plan and draws it per display; **Apply** names the layouts, moves each app's windows into them and routes the apps so new windows follow. Nothing moves until you press Apply.

Bower talks to any OpenAI-compatible endpoint: [Ollama](https://ollama.com) and LM Studio on your Mac, or a hosted one. Set it up in Settings › AI. With a local model, nothing leaves your Mac. An API key, if you use one, is stored in your login Keychain. Recipes live in `~/Library/Application Support/Bower/Recipes/`.

## How hiding works

Bower can't use real Spaces with SIP on. Windows from other layouts are parked just off the bottom-right corner of a display instead (a few points may stay visible there). When Bower quits, every parked window comes back.

Bower works on the Space you're in. macOS only shows it that Space's windows, so switch layouts from your desktop, not from a full-screen app's Space.

## Languages

English, Persian, Japanese, German, French, Spanish, Brazilian Portuguese and Italian, following your Mac's language. Persian is laid out right to left; key combinations stay left to right. Translations live in `Sources/Localizable.xcstrings`; `docs/import-translations.py` checks and merges new ones.

## Known limits

- AI Recipes are tested against a stand-in OpenAI-compatible endpoint, not yet against a real model. How well a plan comes back depends on the model you pick.

## Your data

Everything is in `~/Library/Application Support/Bower/state.json`: layout names, which window is in which layout, routes, pinned displays and Window Modes. It's plain JSON, and everything in it can also be changed in Settings.

## Install

You need Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

1. Clone the repo.
2. In `project.yml`, set `DEVELOPMENT_TEAM` to your own Apple team ID and `PRODUCT_BUNDLE_IDENTIFIER` to your own bundle ID.
3. Run `./install.sh`. It builds a Release copy, puts it in `/Applications` and launches it.

On first launch macOS asks you to allow Bower under System Settings → Privacy & Security → Accessibility. Bower checks once a second and starts working as soon as you do.

## License

MIT. See [LICENSE](LICENSE).
