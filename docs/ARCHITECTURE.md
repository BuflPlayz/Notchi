# Notchi: Architecture Plan

Status: **approved with changes (2026-10-30)** · Toolchain checked on: macOS 27.2, Xcode 27.1, Swift 6.4, Apple M5

Decisions from review:
- Notchi lives on the **main display** (the one with the menu bar, `NSScreen.screens[0]`). On a notched built-in display it is drawn as a **notch**. When the main display has no notch (external monitor, lid closed), it is drawn as a floating **Dynamic Island** capsule, like on iPhone.
- Volume and brightness **fully replace the system HUD** (Accessibility permission, see section 7).
- All other open questions take the proposed defaults.

---

## 1. Principles

- **The panel never resizes.** Each display gets one fixed, transparent panel, sized for the widest settings allowed plus room for spring overshoot. Only the SwiftUI shape inside it animates, top-centered, so every transition grows from the notch's center. An earlier version resized the panel at transition boundaries. That made the shape's position inside the window jump, and when the jump fell inside the spring's transaction the surface slid in from the side.
- **Only the visible shape is interactive.** `HoverController` uses mouse-moved monitors, which are event-driven and fire only while the mouse moves. It compares the cursor with the shape's *target* frame. Inside, the panel takes mouse events. Outside, `ignoresMouseEvents` lets them fall through to the apps below. A shape that grows under a resting cursor doesn't count as a hover.
- **Sizes are user settings.** Live activity width (compact slots, 24–80 pt, default 36) and Panel width (380–600 pt, default 460) apply live. While a slider moves, the notch previews that state.
- **Event-driven, never polled.** IOKit power notifications, Core Audio property listeners, distributed notifications, and the MediaRemote adapter's stdout stream drive updates. Timers redraw with `Text(timerInterval:)` and `TimelineView`, which cost nothing while the notch is idle.
- **Modules are plugins.** The core knows nothing about media or batteries. It only knows `NotchModule`.
- **Providers sit behind protocols.** Every system integration (now playing, battery, volume) is a protocol with a live and a mock implementation. Mocks power the `#Preview`s and the unit tests.
- **Swift 6 strict concurrency.** UI state is `@MainActor @Observable`. Providers are actors or `Sendable` types that publish through `AsyncStream`.

## 2. Folder structure

```
Notchi/
├── Notchi.xcodeproj                 # file-system-synchronized groups (Xcode 16+): new files appear automatically
├── Notchi/
│   ├── App/
│   │   ├── NotchiApp.swift          # @main, Settings scene only (no main window)
│   │   ├── AppDelegate.swift        # boots the window controller; LSUIElement = YES (no Dock icon, no menu bar)
│   │   └── AppEnvironment.swift     # tiny DI container: creates providers, registers modules
│   ├── Core/
│   │   ├── Window/
│   │   │   ├── NotchPanel.swift             # NSPanel subclass: borderless, non-activating, level, collection behavior
│   │   │   ├── NotchWindowController.swift  # owns the panel, positions it, swaps screens
│   │   │   └── ScreenTracker.swift          # "active screen" resolution + screen-change events
│   │   ├── Geometry/
│   │   │   └── NotchGeometry.swift          # notch rect from safeAreaInsets + auxiliaryTop{Left,Right}Area; virtual pill fallback
│   │   ├── State/
│   │   │   ├── NotchState.swift             # enum: .idle / .compact / .expanded
│   │   │   └── NotchViewModel.swift         # state machine, activity arbitration, transition rules
│   │   ├── Modules/
│   │   │   ├── NotchModule.swift            # the protocol (section 4)
│   │   │   ├── LiveActivity.swift           # what a module shows in compact mode + its priority
│   │   │   └── ModuleRegistry.swift         # enable/disable/order modules; picks the winning activity
│   │   ├── Interaction/
│   │   │   ├── HoverController.swift        # tracking area + debounce (enter/exit delays) + click-away monitor
│   │   │   └── Haptics.swift                # NSHapticFeedbackManager wrapper (opt-in)
│   │   ├── Design/
│   │   │   ├── NotchShape.swift             # animatable shape: concave top "shoulders" + rounded bottom
│   │   │   ├── NotchContainerView.swift     # root SwiftUI view: shape + compact/expanded content + matched geometry
│   │   │   ├── Motion.swift                 # spring presets; Reduce Motion substitutes
│   │   │   └── Theme.swift                  # colors, typography (SF Pro), accent handling
│   │   └── Services/
│   │       ├── Permissions.swift            # lazy permission requests with an "explain first" sheet
│   │       ├── Preferences.swift            # @AppStorage-backed settings model
│   │       └── LaunchAtLogin.swift          # SMAppService.mainApp
│   ├── Modules/
│   │   ├── Media/
│   │   │   ├── MediaModule.swift
│   │   │   ├── MediaViewModel.swift
│   │   │   ├── Providers/
│   │   │   │   ├── NowPlayingProvider.swift          # protocol + NowPlayingInfo model
│   │   │   │   ├── MediaRemoteAdapterProvider.swift  # primary: bundled adapter (section 5)
│   │   │   │   ├── AppleScriptProvider.swift         # fallback: Music + Spotify via ScriptingBridge
│   │   │   │   └── MockNowPlayingProvider.swift
│   │   │   ├── ArtworkPalette.swift                  # accent color from artwork (Core Image, downsampled)
│   │   │   └── Views/  CompactMediaView, ExpandedMediaView, VisualizerView, ProgressScrubber
│   │   ├── Timer/
│   │   │   ├── TimerModule.swift, TimerStore.swift   # Date-based; persists across relaunch
│   │   │   └── Views/  CompactTimerView, ExpandedTimerView
│   │   └── System/
│   │       ├── SystemModule.swift
│   │       ├── Providers/  BatteryProvider (IOPS notifications), VolumeProvider (Core Audio listener),
│   │       │               BrightnessProvider, FocusProvider (INFocusStatusCenter)
│   │       └── Views/  BatteryToastView, LevelHUDView, FocusBadgeView
│   ├── Settings/
│   │   └── SettingsView.swift + one pane per module (each module provides its own settings view)
│   └── Resources/
│       ├── Assets.xcassets
│       └── MediaRemoteAdapter/              # vendored, pinned: mediaremote-adapter.pl + MediaRemoteAdapter.framework
└── NotchiTests/                             # geometry, state machine, timer math, palette extraction
```

## 3. Window and notch behavior

| Concern | Approach |
|---|---|
| Panel | `NSPanel`, `[.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `level = .statusBar + 1`, so it sits above the menu bar. |
| Spaces / fullscreen | `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]` |
| Interaction without stealing focus | `becomesKeyOnlyIfNeeded = true`. Hosting view returns `acceptsFirstMouse = true`, so buttons work on the first click without activating Notchi. |
| Notch detection | `screen.safeAreaInsets.top > 0` gives the notch height. Notch width is `screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`. The notch x position is `auxiliaryTopLeftArea.maxX`. |
| No notch / external display | **Dynamic Island.** At rest it is a black capsule (~120 pt wide) centered in the menu bar. Compact widens it into a taller capsule that floats slightly below the top edge. Expanded is a detached rounded card (continuous corners) with a soft shadow. The shadow is the one place a glow helps, because the island doesn't blend into hardware. |
| Multi-display | Notchi always follows the **main display** (`NSScreen.screens[0]`). On `didChangeScreenParametersNotification` (display plugged in, lid closed, main display changed in Settings), it rebuilds the geometry and switches between notch and island automatically. Debug: launch with `-NotchiForceIsland YES` to see the island on a notched Mac. |
| States | `idle` (notch: tucked behind the hardware notch, so it is invisible; island: small resting capsule) → `compact` (widens; leading and trailing slots) → `expanded` (full panel). Transient **toasts** (plug-in, HUD) are compact presentations with an auto-dismiss deadline. |
| Animation | One `NotchShape` whose width, height, and corner radii animate. Content uses `matchedGeometryEffect` (for example, artwork moves from the compact slot to the expanded hero). Default spring: `.spring(response: 0.35, dampingFraction: 0.82)`. Springs are interruptible by nature. |
| Hover | Mouse-moved monitors hit-test the cursor against the shape (see Principles). Expand after **150 ms** dwell, collapse **300 ms** after exit (both configurable). Click-away uses a global `leftMouseDown` monitor, which needs no Accessibility permission. |
| Haptics | `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, …)` on expand. Opt-in. Only felt if a finger is on a Force Touch trackpad. |
| Reduce Motion | Springs become a 0.2 s opacity and scale cross-fade. Matched-geometry flights are disabled. |
| Light/dark | The notch surface stays pure black in both modes, because it must match the hardware. Content is white/secondary on black. The Settings window and the accent follow the system appearance. |

### Full screen (implemented)

While a full-screen app is in front of the notch's display, the notch hides and ignores hover and clicks, so the top edge belongs to the app's revealable menu bar. It returns when you leave full screen. Activities can opt in with `LiveActivity.showsInFullScreen`; only the volume and brightness HUD does, because the system HUD is suppressed. It can be turned off in Settings › General › "Hide in full screen".

Detection (`FullScreenMonitor`), measured on macOS 27.2:
- `NSApp.currentSystemPresentationOptions` is 0 for other apps' full screen (it only describes the caller).
- On a notched display, a full-screen window's frame (0, 33, 1512×949) is identical to a zoomed window with a hidden Dock.
- The menu bar window stays "on screen" in the window list.
- **What works:** the window server tags full-screen Spaces as type 4 in `CGSCopyManagedDisplaySpaces` (private, SIP-safe, loaded with `dlsym`). The monitor matches the notch's display by UUID (or the shared "Main" entry when Spaces aren't per display) and re-checks only on `activeSpaceDidChangeNotification` and display changes.

## 4. `NotchModule` protocol (sketch)

```swift
@MainActor
protocol NotchModule: AnyObject, Identifiable where ID == String {
    var id: String { get }
    var title: String { get }
    var symbol: String { get }                 // SF Symbol for the expanded-mode tab bar

    /// Non-nil when the module wants compact-mode real estate. Observable, so the registry reacts.
    var liveActivity: LiveActivity? { get }

    func compactLeading() -> AnyView           // left of the notch
    func compactTrailing() -> AnyView          // right of the notch
    func expandedView() -> AnyView             // a tab/page in the expanded panel
    func settingsView() -> AnyView?            // optional settings pane

    func start()                               // subscribe to providers
    func stop()                                // tear down (module disabled)
}

struct LiveActivity: Equatable {
    enum Priority: Int, Comparable { case ambient, active, urgent, transient } // transient = toast
    var priority: Priority
    var expiresAt: Date?                       // toasts auto-dismiss
}
```

The registry picks the highest-priority live activity for the compact slots. If two activities are active (for example, music plus a running timer), the winner gets both slots and the runner-up shows as a small indicator dot (see open question 6).

Later-phase modules plug in through the same protocol: File Shelf, AirPods, Clipboard, and Agent Activity. **Agent integration** gets a local inbound channel in the core: a `notchi://` URL scheme plus a small bundled `notchi` CLI that talks to the app over a Unix-domain socket. Claude Code hooks (or any agent) can then run `notchi notify --source claude --status running "Editing 3 files"`, and an `AgentModule` renders it as a live activity.

## 5. Media: research and trade-offs

Since macOS 15.4, `MediaRemote.framework` only serves callers with an Apple-entitled bundle ID, so `dlopen` plus `MRMediaRemoteGetNowPlayingInfo` silently returns nothing for third-party apps.

| Approach | Coverage | Permissions | Stability | Distribution |
|---|---|---|---|---|
| **A. mediaremote-adapter** (BSD-3). The app runs `/usr/bin/perl`, which identifies as `com.apple.perl` and is therefore allowed. Perl loads a small framework that streams now-playing JSON to stdout. Controls (play/pause/next/seek) go through the same tool. | **Everything** that reports to Now Playing: Music, Spotify, Safari/Chrome/Arc tabs, Podcasts, IINA, and others | None | Relies on a loophole Apple could close in any update. Actively maintained. The README shows it tested on macOS 27.0, and it ships a `test` command to detect breakage at runtime. | Not sandboxable, so no Mac App Store. Developer ID + notarization is fine. |
| **B. ScriptingBridge/AppleScript** for Music and Spotify, with change events from distributed notifications (`com.apple.Music.playerInfo`, `com.spotify.client.PlaybackStateChanged`) | Music and Spotify only. **No browser media.** | Automation prompt per app ("Notchi wants to control Spotify") | Public and stable | App Store-compatible with the right entitlements |
| C. Linking private MediaRemote directly | Broken for third-party apps since 15.4 | n/a | n/a | n/a |

**Implemented (milestone b): A as primary, B as automatic fallback.**
- The adapter is vendored as source (`Vendor/mediaremote-adapter`, v0.7.7, see VENDORED.md). The `MediaRemoteAdapter` framework target builds it and embeds it in `Contents/Frameworks`, with the Perl loader in the framework's Resources. There's no CMake step and no prebuilt binary.
- `MediaRemoteAdapterProvider` runs one long-lived `stream --micros --debounce=50` process. It parses JSON lines off the main thread (`AdapterStreamParser` merges the diffs), restarts the stream with backoff if it dies, and sends commands as one-shot `send <id>` and `seek <µs>` calls.
- **Notchi never runs the adapter's `test` command.** When nothing is playing, `test` publishes a fake track for a moment. Instead, `NowPlayingService` listens to Music's and Spotify's public distributed notifications, which are free and need no permission. If either says *Playing* and the adapter reports nothing within 4 s, the loophole has been closed, and the service switches to `AppleScriptNowPlayingProvider` for the session.
- The fallback reads track changes from those notifications without any permission. AppleScript (with the Automation prompt) is only used for controls, Music's position and artwork. It covers Music and Spotify only.
- Quirks handled: artwork that arrives late keeps the previous image for the same track, a 2.5 s pause linger absorbs the pause/play blip between tracks, and browser media is attributed to the parent app (Safari or Chrome, not the WebKit helper).

**Visualizer: real audio (implemented).**
- `SystemAudioTap` (macOS 14.2+): a Core Audio process tap on system output (`CATapDescription(stereoGlobalTapButExcludeProcesses: [])`, private, unmuted) inside a private aggregate device. The IO block mixes to mono and feeds `SpectrumAnalyzer`.
- `SpectrumAnalyzer`: 1024-point FFT from Accelerate, Hann window, 50% overlap, 4 bands spaced logarithmically from 60 Hz to 12 kHz. Levels are in dB, auto-gained per band, with fast attack and slow release, published about 30 times a second.
- Cost control: the FFT runs only when a frame is due (~30/s), not for every audio buffer. The bars draw at that rate without interpolation, and a dedicated view reads the levels so only the bars re-render.
- `AudioLevelMonitor` runs the tap **only while music plays**, so the recording indicator and the CPU cost exist only then. If no audio has ever arrived (permission denied or pending), the bars fall back to the synthetic animation.
- Permission: "System Audio Recording Only" (`NSAudioCaptureUsageDescription` in `Config/Info.plist`, plus the `com.apple.security.device.audio-input` entitlement). It can be turned off under Settings › Media.

**Sources: music apps only (default).** `MediaSourceFilter` allows Music, Podcasts, Spotify, TIDAL, Deezer and Amazon Music. Browsers and video players are hidden unless Settings › Media › "Show media from browsers and video apps" is on.

**Accent color:** downsample the artwork to 24×24, then pick the most saturated dominant cluster, with a luminance floor so it stays legible on black. Fall back to white.

## 5b. Apple Clock app timers (implemented)

There's no public API for Clock's timers, but `mobiletimerd` keeps them in the `com.apple.mobiletimerd` preferences domain. A non-sandboxed app can read it without a prompt (the daemon's own group container is TCC-protected, but this domain isn't).
- `MobileTimerClockProvider` reads `MTTimers` and `MTStopwatches` through `UserDefaults(suiteName:)`, which goes via `cfprefsd` and is current within milliseconds. The plist on disk lags by 5 to 13 seconds. Key-value observing on the suite reports changes from other processes, so nothing is polled. None of the `MobileTimer` Darwin notifications fired on stopwatch or timer changes in testing.
- Observed codes (macOS 27.2): timer `1` stopped / `2` paused (remaining in `MTTimerTimeInterval`) / `3` running (fire date in `MTTimerTimeDate`). Stopwatch `1` paused or reset (`MTStopwatchOffset`) / `2` running (`MTStopwatchStartDate` + offset). Unknown shapes decode to "nothing active".
- `ClockModule` registers before media, so a running timer wins the compact slots. Paused timers are `ambient`. When a timer ends, a 5-second "Done" toast shows. Countdowns use `Text(timerInterval:)`, which redraws itself, and the ring steps once a second without animation, so a live countdown costs about 0.6% CPU.
- Read-only: Clock's timers can't be paused or started from outside Clock, so tapping opens the Clock app.
- Risk: this is undocumented private data and may change in a future macOS. The decoder fails closed.

## 6. Stopwatch and timer

- The model is `Date`-based (`startedAt`, `accumulated`, `duration`), so no `Timer` ticks in the background. Views render with `Text(timerInterval:)`/`TimelineView(.periodic)` only while visible.
- A running timer is a live activity (`active`). In its last 10 seconds it becomes `urgent`, which pulses gently. On completion it shows a toast and plays a sound. A notification via `UNUserNotificationCenter` is optional, requested lazily the first time the user enables it.
- State persists in `UserDefaults`, so timers survive relaunch.

## 7. Mac activity (implemented, milestone d)

All of it lives in `SystemModule`. Toasts are `transient` live activities, so they briefly take the compact slots over anything else.

| Feature | Approach | Permission |
|---|---|---|
| Battery % / charging / time left | `IOPSNotificationCreateRunLoopSource` (event-driven), `BatteryState(description:)` | None |
| Plug-in toast, low battery at 20/10/5% | `BatteryAlerts` compares consecutive readings. The first reading is a baseline, not a change. | None |
| Volume HUD (replaces the system's) | `MediaKeyInterceptor`: an active `CGEventTap` on `NX_SYSDEFINED` subtype 8 swallows the volume and mute keys. `VolumeController` sets the virtual main volume and mute through Core Audio, and its property listeners (which follow the default output device) drive the HUD for changes from any source. | **Accessibility** |
| Brightness HUD (replaces the system's) | Same tap for the brightness keys. `BrightnessController` uses private DisplayServices through `dlsym` (SIP-safe), for the built-in display or Apple displays. | **Accessibility** |
| Focus on/off + name, toast on change | `FocusMonitor`: Accessibility read of Control Center's Focus menu bar item, which shows while a Focus is active (default "Show When Active"), plus an `AXObserver` on Control Center. | **Accessibility** (shared) |
| Expanded page | Battery and Focus tiles, Control Center-style volume and brightness sliders, and the permission prompt | None |

Details:
- **Keys Notchi declines go to the system:** an output without software volume, a brightness controller that can't change the display, and ⌥ alone (the shortcut that opens Sound/Displays settings). ⌥⇧ gives fine steps (1/64), and levels snap to the system's 16-step grid. The tap re-enables itself after `tapDisabledByTimeout`. If Notchi quits, the tap dies with it.
- **HUD animation:** each update happens inside one `Motion.hud` spring, so the level bar eases, the percentage digits roll (`numericText`), the speaker's waves fill, mute bounces the icon, and the sun turns with brightness. Holding a key retargets the spring instead of stepping.
- **The volume HUD only shows while Notchi owns the keys.** Without Accessibility the system HUD stays, so you never get two HUDs.
- **The volume "pop"** plays only if the system setting "Play feedback when volume is changed" is on.
- **Focus, investigated alternatives:** `INFocusStatusCenter` needs a provisioned entitlement, and `~/Library/DoNotDisturb/DB` is TCC-protected. No `com.apple.donotdisturbd` preference holds state, and no public Darwin notification signals changes. If the user hides the Focus menu bar item entirely, Focus reads as off.
- **Permission flow:** `AccessibilityPermission` is requested only from the System page or Settings. Grants are picked up through the `com.apple.accessibility.api` distributed notification, with no polling. The project is signed with the Apple Development identity, so grants survive rebuilds (ad-hoc signatures change every build).
- **Not handled yet:** keyboard backlight keys (left to the system), DDC/CI brightness for third-party monitors, and an AirPods/output-device toast (later phase).

## 8. Settings, permissions, distribution (implemented, milestone e)

- **Settings window:** a SwiftUI `Settings` scene with toolbar tabs: General, Modules, one pane per module, and About. It opens from the notch's right-click menu or its ⋯ menu, and remembers the last tab. Each module supplies its own pane through `NotchModule.settingsView()`, so a new module gets a Settings tab just by implementing it.
- **General:** launch at login (`SMAppService.mainApp`, with a shortcut to Login Items if the user turned it off there), open on hover or click only, open/close delays, haptics, live activity width, panel width, the island at rest, and Reset All Settings.
- **Modules:** drag to reorder and switch each module on or off (`ModuleRegistry`, persisted as `moduleOrder`/`disabledModules`). The order sets the expanded tabs and breaks compact-mode ties. Disabled modules are stopped. The last enabled module can't be switched off.
- **Module panes:** Now Playing (sources, active provider, visualizer), Clock (paused items, open Clock), System (HUD, Focus, Accessibility status, battery toasts).
- Everything writes to `UserDefaults` and applies live through `UserDefaults.didChangeNotification` or direct registry calls. No restart is needed.
- `Permissions`: Accessibility is requested only from the System page or Settings, with the reason shown next to the button. Audio recording is requested by macOS the first time music plays with the visualizer on.
- **No sandbox** (required for the adapter process and the Core Audio tap), hardened runtime on, signed with the Apple Development identity for local builds, and Developer ID plus notarization for distribution. Nothing requires SIP changes.

## 9. Milestones

| # | Scope | Done when |
|---|---|---|
| a | Xcode project, panel, geometry, state machine, hover/click, springs, Reduce Motion, virtual pill, screen following, previews with a demo module | Hovering the notch expands it smoothly. It collapses on exit or click-away. No flicker. It works on the built-in and an external display. |
| b | Media module (adapter + AppleScript fallback, artwork accent, controls, progress, visualizer) | Music, Spotify, and a YouTube tab all show and can be controlled |
| c | Stopwatch + timer | Start, pause, and reset from the notch. A running timer shows in compact mode. Timers survive relaunch. |
| d | Battery, plug-in toast, volume/brightness HUD, Focus | Toasts and HUDs appear on events. Idle CPU stays near 0% (checked in Activity Monitor and Instruments). |
| e | Settings window, module enable/order, launch at login | All toggles persist and apply live |

Each milestone ends with: what works, how to run it (`xcodebuild` command + "open in Xcode, ⌘R"), and known limitations. I build and launch it locally after each milestone to check it.

## 10. Assumptions

1. Deployment target is macOS 14.0, Apple Silicon only, Swift 6 language mode with strict concurrency.
2. The bundle ID is a placeholder, `dev.notchi.Notchi`, and signing is "Sign to Run Locally" until you provide a team.
3. No third-party Swift packages. The only vendored code is the BSD-3 mediaremote-adapter (justified above).
4. Notchi has no Dock icon and no menu bar item. Settings opens from the notch's context menu.
5. The Xcode project uses file-system-synchronized groups, so it can be built from the CLI and opened in Xcode with no generator tools.
