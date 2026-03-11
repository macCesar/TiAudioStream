# Changelog

All notable changes to this project will be documented in this file.

## [1.1.2] - 2026-03-11

### Added
- **`hardStop()` for explicit live reconnect behavior**: Added a dedicated hard-stop API for cases where apps want a real teardown and a fresh reconnect to the live edge on the next `start()`. `stop({ hard: true })` is also supported for parity.

### Changed
- **`stop()` now stays a soft stop**: `stop()` preserves fast-resume behavior for live streams while hiding system controls. This avoids changing the practical behavior expected by radio-style apps, while `hardStop()` covers the explicit teardown case.

### Fixed
- **Manual lock screen metadata no longer gets overwritten on iOS**: When `autoUpdateMetadata` is `false`, timed stream metadata still fires the `metadata` event for app UI, but it no longer mutates the internal Now Playing fields or replaces values previously set with `setMetadata()`.
- **Duplicate `metadata` events on iOS / Mac Catalyst**: Timed metadata that included a `StreamUrl` artwork link could emit the same payload twice. The module now deduplicates repeated payloads and only emits artwork to app UI once the artwork URL has been resolved.
- **`remotecontrol` PLAY/STOP parity on Android**: Added `remotecontrol` emission from the `MediaSessionCompat.Callback` path so devices like Pixel that route transport commands through the media session deliver `PLAY`, `PAUSE`, and `STOP` events consistently.

---

## [1.1.1] - 2026-02-20

### Fixed
- **Metadata parity (Android/iOS)**: Android metadata parsing now matches iOS for common formats like `"Artist - Title - ..."` so `title` and `artist` stay consistent across platforms.
- **Metadata rules reliability (Android)**: `metadataRules` serialization now supports Titanium payload variants more reliably when rules are passed in `setStream()` or `setMetadataRules()`.
- **Duplicate metadata emissions (Android)**: Prevented repeated `metadata` events when overlapping native callbacks (`onMediaMetadataChanged` and `onMetadata`) report the same values.
- **Stale artwork race conditions (Android/iOS)**: Added guards so delayed artwork fetches from a previous stream cannot overwrite the current stream artwork.
- **Lock screen artwork clearing (Android OEM skins)**: Improved artwork reset behavior when switching to streams without artwork, including explicit metadata cleanup and icon replacement fallback to avoid showing the previous station cover.

---

## [1.1.0] - 2026-02-17

### Added
- **`setMetadataRules(rules)`**: New method for automatic regex-based metadata cleanup. Define `match`/`replace` rules for `title` and `artist` fields, and the module applies them in order **after** its built-in parsing (ICY split, "Artist - Title" split) and **before** updating the lock screen, notification, and firing the `metadata` event. No need to disable `autoUpdateMetadata` — rules and auto-update coexist. Pass `null` to clear all rules. `setMetadata()` (manual override) is intentionally not affected by rules.
- **`metadataRules` in `setStream()`**: Rules can now be passed inline as part of `setStream()` options. Omitting the key preserves existing rules; passing `null` clears them. The standalone `setMetadataRules()` method still works independently.

### Fixed
- **UI freeze during buffering (iOS/Mac Catalyst)**: `setStream:` no longer blocks the main thread. AVPlayerItem creation (DNS + connection) now runs on a background thread, so the app stays responsive while buffering. Switching stations mid-buffer discards the obsolete item automatically.
- **`isLive` on Android**: Now sets `METADATA_KEY_DURATION` to `-1` so the system hides the seek bar on lock screen and notification, matching the iOS behavior (`MPNowPlayingInfoPropertyIsLiveStream`).
- **Duplicate `state` events**: The `state` event now only fires on actual state transitions. Previously, native engines could trigger multiple identical callbacks (e.g., several `buffering` events in a row during stream startup), which were forwarded directly to JavaScript. Both platforms now deduplicate before emitting.

---

## [1.0.1] - 2026-02-13

### Docs
- **README rewrite**: Complete rewrite with installation guide, quick start, API reference with parameter tables, 5 practical guides (app UI updates, playlist rotation, custom metadata cleaning, error handling, platform-specific behavior), metadata extraction reference, and technical implementation table.
- **Metadata clarification**: Documented that lock screen/notification updates are automatic while app UI requires the `metadata` event listener.

### Changed
- **Example app**: Removed semicolons, standardized all property assignments to use `applyProperties()` for consistency and reduced bridge crossings.

### Added
- `.editorconfig` for consistent formatting across editors.

---

## [1.0.0] - 2026-01-22
*Initial Stable Release*

### Features
- **Unified Audio Engine**: Unified playback logic for Android (Media3) and iOS (AVPlayer).
- **Deep Metadata Inspection**: Automatically extracts song titles from standard sources (ICY, HLS) AND hidden formats (JSON inside ID3 tags), ensuring support for networks like **Global Player** (Heart, Capital).
- **Automatic Stream Artwork**: Automatically extracts and displays album art embedded in audio streams directly on the system lock screen and notification drawer. Supports embedded artwork (ID3 APIC) AND remote URLs (ICY_URL/StreamUrl for streams like Radio Paradise).
- **Smart Audio Focus**: Handles system interruptions (calls, Siri, other apps) with resume logic that respects user intent. Automatically resumes after calls if the app was playing, but stays paused if the user manually paused.
- **Background Persistence**: Reliable background playback using a Foreground Service (Android) and proper Audio Session management (iOS).
- **Media Controls**: Seamless integration with Lock Screen and Notification Center.
- **Remote Commands**: Support for Play, Pause, Stop, Next, and Previous from external devices (Bluetooth/Headsets).
- **Metadata Auto-Update Control**: `autoUpdateMetadata` flag allows apps to control whether stream metadata automatically updates Lock Screen/Notification controls. Perfect for radio stations that want to display station branding vs. song information on demand.

### Improved
- **Robust Metadata Parsing**: Scans `commonMetadata`, raw ID3 frames, and timed metadata ensuring compatibility with a wide range of streaming providers (including Global Player, Heart, Capital).
- **Title Splitting**: Automatically separates "Artist - Title" strings into distinct fields for the Lock Screen.
- **Terminal Error Detection (iOS)**: Monitors the native `ErrorLog` to detect HTTP 404/500 errors and immediately stops playback instead of attempting useless retries.
- **Audio Interruption Handling**: Correctly distinguishes between system interruptions (calls) and manual pauses with smart resume logic.
- **Thread Safety (Android)**: Enforced main-thread execution for player commands to prevent "Wrong Thread" crashes.
- **Simplified Playback Logic**: Removed aggressive re-prepare logic that caused audio repeats. Now lets native players handle state naturally.

### Fixed
- **Artwork Clearing**: When changing to a stream without artwork, the previous station's artwork is now properly cleared on both platforms.
- **Artwork Download Failures**: If an artwork URL fails to load (404, timeout, invalid image), the artwork is now cleared instead of keeping the previous image.
- **Android Artwork Events**: Remote artwork URLs (e.g., from Radio Paradise ICY_URL) now fire the `metadata` event with the artwork URL, allowing apps to update their UI.

### Platform Status
- **Android**: Fully verified on physical devices (Stability: Production-ready).
- **iOS**: Verified on Simulator & Device (Stability: Production-ready).
