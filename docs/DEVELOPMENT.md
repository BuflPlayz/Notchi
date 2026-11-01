# Developing Notchi

Building, testing, debugging and releasing. For what Notchi is and how to install it, see the [README](../README.md); for the design, [ARCHITECTURE.md](ARCHITECTURE.md).

## Requirements

- macOS 14 or later, Apple Silicon
- Xcode 26 or later (the app icon is an Icon Composer document); developed with Xcode 27.1

## Build and run

Open `Notchi.xcodeproj` in Xcode and press ⌘R. Or from a terminal:

```bash
xcodebuild -project Notchi.xcodeproj -scheme Notchi build
```

```bash
open ~/Library/Developer/Xcode/DerivedData/Notchi-*/Build/Products/Debug/Notchi.app
```

The project is signed with an Apple Development identity, so macOS permissions survive rebuilds. To build on another machine, set your own team under Signing & Capabilities.

Keep build output out of iCloud-synced folders such as `~/Documents`. iCloud adds file attributes that make `codesign` fail with "resource fork, Finder information, or similar detritus not allowed". Xcode's default DerivedData location is fine.

## Make the DMG

```bash
scripts/make-dmg.sh
```

This builds Release and writes `build/Notchi-<version>.dmg`, holding `Notchi.app`, an `Applications` shortcut to drag it onto, and the license. The version comes from `MARKETING_VERSION`.

- By default it signs with the project's Apple Development identity. That's fine for your own Macs.
- For a public release, sign with Developer ID and notarize, so it opens without Gatekeeper warnings:

  ```bash
  xcrun notarytool store-credentials notchi-notary   # once: Apple ID, team, app-specific password
  scripts/make-dmg.sh --identity "Developer ID Application: Your Name (TEAMID)" --notarize notchi-notary
  ```

- With no Apple Developer account, use `--adhoc`. The hardened runtime is off then, and other Macs need **Open Anyway**.

Run `scripts/make-dmg.sh --help` for every option.

### Releases

[`.github/workflows/release.yml`](../.github/workflows/release.yml) builds the DMG on GitHub and publishes it, so it becomes the download in [Install](../README.md#install). Bump `MARKETING_VERSION`, then push a matching tag:

```bash
git tag v0.1.0 && git push origin v0.1.0
```

The workflow fails if the tag and the version differ.

No terminal handy (on a phone, say)? Open the **Actions** tab, pick **Release** and tap **Run workflow**. It publishes release `v<MARKETING_VERSION>` and creates the tag. Untick **Publish a release** to only build a DMG you can download from the run.

With no secrets set, release DMGs are signed ad hoc. To sign with Developer ID and notarize, add the repository secrets listed at the top of the workflow: the certificate as a base64 `.p12` and its password, plus an App Store Connect API key for notarization.

## Test

```bash
xcodebuild -project Notchi.xcodeproj -scheme Notchi test
```

## Debug helpers (Debug builds only)

- `-NotchiForceIsland YES` shows the island style even on a notched display. It's a disabled launch argument in the scheme; tick it under Product › Scheme › Edit Scheme › Arguments.
- Drive Notchi from a terminal by posting a distributed notification named `dev.notchi.debug`:

  ```bash
  swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(.init("dev.notchi.debug"), object: "expand", userInfo: nil, deliverImmediately: true)'
  ```

  | Object | Does |
  |---|---|
  | `expand`, `collapse` | Opens or closes the panel |
  | `show:<module>` | Opens a module's page (`media`, `clock`, `shelf`, `system`) |
  | `swap:<module>` | Clicks that module's bubble beside the notch |
  | `hud:volume:0.6`, `hud:brightness:0.3`, `hud:mute` | Shows the HUD without pressing keys |
  | `hud:charging:0.76`, `hud:low:0.1` | Shows a battery toast |
  | `focus:<name>`, `focus:off` | Pretends a Focus turned on or off |
  | `focusDump`, `focusTrace` | Writes what the Focus monitor sees (a snapshot, or a 40 s timed trace) to `$TMPDIR` |
  | `settings`, `settings:<tab>`, `closeSettings` | Opens Settings (at `general`, `modules`, a module's tab, or `about`), or closes it |
  | `audioTap` | Runs the visualizer's audio tap for 6 s and logs the result under subsystem `dev.notchi.Notchi` |
