# Notchi

A Dynamic Island for the Mac. On a notched MacBook display it grows out of the camera notch. On a main display without a notch it floats as an island capsule. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design.

Requirements: macOS 14+, Apple Silicon, Xcode 16+ (developed with Xcode 27.1).

## Run

Open `Notchi.xcodeproj` in Xcode and press ⌘R. Or from a terminal:

```bash
xcodebuild -project Notchi.xcodeproj -scheme Notchi build
open ~/Library/Developer/Xcode/DerivedData/Notchi-*/Build/Products/Debug/Notchi.app
```

The project is signed with an Apple Development identity, so macOS permissions (Accessibility, System Audio Recording) survive rebuilds. To build on another machine, set your own team under Signing & Capabilities.

Notchi has no Dock icon or menu bar item. To quit it, right-click the notch and choose **Quit Notchi**, or use the **⋯** menu in the expanded panel.

Keep build output out of iCloud-synced folders such as `~/Documents`. iCloud adds file attributes that make `codesign` fail with "resource fork, Finder information, or similar detritus not allowed". Xcode's default DerivedData location is fine.

## Test

```bash
xcodebuild -project Notchi.xcodeproj -scheme Notchi test
```

## Debug helpers (Debug builds only)

- `-NotchiForceIsland YES` shows the Dynamic Island style even on a notched display. It's a disabled launch argument in the scheme; tick it under Product › Scheme › Edit Scheme › Arguments.
- Drive the notch without the mouse by posting a distributed notification named `dev.notchi.debug` with the object `expand`, `collapse`, `show:clock`/`show:media`/`show:system`, `settings:general` (or another tab), `closeSettings` or `audioTap` (6-second audio capture check, logged under subsystem `dev.notchi.Notchi`):

  ```bash
  swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("dev.notchi.debug"), object: "expand", userInfo: nil, deliverImmediately: true)'
  ```

## Milestones

- [x] **a. Notch window and animations.** Notch and island styles, follows the main display, hover/click/click-away, spring transitions, Reduce Motion, haptics, adjustable widths, demo module.
- [x] **b. Media.** Now playing from music apps (MediaRemote adapter, with a Music/Spotify AppleScript fallback), artwork and accent color, progress and seeking, transport controls, and a real audio visualizer.
- [x] **Clock app timers.** Running and paused timers and the stopwatch from Apple's Clock app, live in the notch.
- [ ] c. Stopwatch and timer
- [x] **d. System activity.** Battery with plug-in and low-battery toasts, the volume and brightness HUD replacing the system's (needs Accessibility), Focus status and toasts, and volume and brightness sliders.
- [x] **e. Settings.** Settings window with General, Modules (reorder and enable), per-module panes and About, launch at login, click-only mode, and hiding the island at rest.
