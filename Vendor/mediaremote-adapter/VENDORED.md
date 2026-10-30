# Vendored: mediaremote-adapter

- Upstream: https://github.com/ungive/mediaremote-adapter
- Version: v0.7.7 (commit e3ff5021eb0875858bd05f48d2e9ba2e962d1cf6, 2026-09-03)
- License: BSD 3-Clause (see LICENSE)
- Local changes: none. Only the files needed to build the adapter framework are copied: `bin/`, `include/`, `src/adapter`, `src/private`, `src/utility`, plus `src/test/NowPlayingTest.h`, which `test.m` includes. The test client executable is not built, and Notchi never runs `test` (see docs/ARCHITECTURE.md §5).

Built by the `MediaRemoteAdapter` framework target in `Notchi.xcodeproj` and embedded in `Notchi.app/Contents/Frameworks`. The Perl loader ships inside the framework's Resources.

To update: copy the same paths from a newer upstream tag, rebuild, and check that the stream JSON keys in `NowPlayingInfo+Adapter.swift` still match `src/adapter/keys.m`.
