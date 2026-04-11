# Changelog

All notable changes to this project will be documented in this file.

## [1.2.7] - 2026-04-10

### Changed
- **iOS: CarPlay browse no longer uses the system `playing` selection state for the active station**: The active station is now marked with a stable `On Air` subtitle instead of CarPlay's own playing highlight, avoiding the double-gray / wrong-row selection effect during browse updates.

### Notes
- This patch is focused only on making the CarPlay station list easier to read while the system `Now Playing` ownership issue remains unresolved.

## [1.2.6] - 2026-04-10

### Changed
- **iOS: CarPlay browse list no longer duplicates the current station in a pinned first row**: The active station now stays in its own position in the list and is marked with CarPlay's playing indicator instead of jumping to the first row.
- **iOS: CarPlay root template is forced into list-only mode more aggressively**: The module now clears navigation bar buttons on the root list and suppresses all app-driven pushes to `CPNowPlayingTemplate`.

### Notes
- This patch is intended to remove the confusing "selection jumps to the first row" behavior while keeping CarPlay on the station list.

## [1.2.2] - 2026-04-10

### Changed
- **iOS: experimental CarPlay source-ownership refresh**: The module now re-runs the same audio-session ownership steps not only at startup, but also when playback starts, when the app returns to foreground, and when CarPlay connects. This mirrors the behavior observed when opening a second Titanium app caused CarPlay to finally adopt the active source.
- **iOS: CarPlay station list refresh no longer reinstalls the root template**: The delegate now updates list sections in place, which removes the visible flicker in `AudiostreamTest` when stations or metadata refresh.
- **iOS: current-station row no longer prefixes `Resume` while playback is active**: The CarPlay list now labels the current station directly instead of showing a stale `Resume ...` prefix during active playback.

### Notes
- This patch is intentionally for ongoing CarPlay ownership experiments so the build can be identified unambiguously in host apps as `1.2.2`.

## [1.2.3] - 2026-04-10

### Changed
- **iOS: delayed CarPlay refresh after scene connect/presentation**: When CarPlay connects or `Now Playing` is presented, the module now republishes the active item after a short delay instead of relying only on the initial publish path.
- **iOS: explicit external content identifier for live items**: `updateNowPlaying()` now sets `MPNowPlayingInfoPropertyExternalContentIdentifier` plus a single-item playback queue so MediaRemote sees a clearer item identity during CarPlay adoption experiments.

### Notes
- This patch is still experimental and focused only on reproducing and narrowing the CarPlay cold-start adoption bug.

## [1.2.4] - 2026-04-10

### Fixed
- **iOS: partial `setMetadata()` calls no longer wipe existing title, artist, or artwork**: The module now preserves existing now-playing fields unless the caller explicitly provides replacement values. This restores artwork updates that were being lost after ownership experiments and prevents incomplete metadata payloads from blanking the current item.

### Notes
- This patch is separate from the unresolved CarPlay cold-start ownership issue.

## [1.2.5] - 2026-04-10

### Changed
- **iOS: CarPlay list-only fallback**: Removed the `Now Playing` row from the CarPlay browse list so Titanium host apps stay on the station list instead of navigating into an empty `Now Playing` screen.

### Notes
- This does not resolve the underlying CarPlay cold-start ownership bug. It is an explicit list-only fallback for Titanium host apps while ownership remains under investigation.

## [1.2.1] - 2026-04-10

### Fixed
- **iOS: CarPlay now consistently recognizes Titanium apps as active audio source**: Removed `MPNowPlayingSession` (iOS 16+) which was preventing CarPlay from adopting the app as the active audio source. The session-based API added an async activation layer (`becomeActiveIfPossible`) that could silently fail, leaving metadata published to an inactive session center invisible to CarPlay. The module now uses `MPNowPlayingInfoCenter.defaultCenter` and `MPRemoteCommandCenter.sharedCommandCenter` exclusively — the same direct approach that native CarPlay audio apps use — ensuring the system always sees the app's now-playing info immediately.
- **iOS: CarPlay sidebar adoption when audio is already playing**: Connected three wires that were left disconnected: (1) `TiAudiostreamCarPlayDidConnectNotification` was defined but never posted from the scene delegate, (2) `handleCarPlaySceneDidConnect:` was never registered as an observer, (3) the handler was an empty stub. Now, when CarPlay connects while audio is playing, the module reasserts the audio session, re-publishes Now Playing info, re-registers remote commands, and calls `becomeActiveIfPossible`. The scene delegate also conditionally auto-pushes Now Playing with a 0.5s delay to allow the reassertion to complete first.
- **iOS: `reassertNowPlayingContextForReason:` now functional**: Was a logging-only stub. Now re-activates the audio session, re-publishes metadata, promotes the Now Playing session, and supports retries with 1s delay between attempts.
- **iOS: CarPlay play/pause toggle button now works**: Added `togglePlayPauseCommand` registration. CarPlay's Now Playing screen uses this command for the main play/pause button. Without it, CarPlay could not toggle playback from the car display.
- **iOS: Titanium scene lifecycle compatibility for CarPlay**: Added dedicated CarPlay and window scene delegates so Titanium apps can participate in the `UIScene` lifecycle required by CarPlay without breaking the main app window.

### Changed
- **Version alignment (Android/iOS)**: Both platform manifests now move to `1.2.1` so the release stays aligned across Android and iOS even though the runtime fix is iOS-focused.

### Documentation
- **CarPlay setup guide refreshed**: Updated the README and iOS-specific guide to document the real Titanium setup for CarPlay, including entitlements, `UIApplicationSceneManifest`, built-in scene delegates, simulator testing, and current limitations.
- **Platform comparison updated**: Clarified the Android Auto vs CarPlay behavior and technical implementation tables to match the current runtime behavior.

---

## [1.2.0] - 2026-04-08

### Added
- **Android Auto support**: The module now registers as a `MediaBrowserService`, so Android Auto can discover, display, and control the stream. The car display shows the current title, artist, artwork, and playback controls automatically. No app code changes needed.
- **App icon fallback artwork**: When no artwork is available from the stream or from `setStream()`/`setMetadata()`, the module automatically uses the app icon as fallback artwork for lock screen, notification, Control Center, CarPlay, and Android Auto.
- **Automatic retry with error classification (Android/iOS)**: When a stream fails due to a transient network error (connection lost, timeout, no internet), the module retries up to 5 times with a 3-second delay between attempts. Terminal errors (bad domain, SSL/certificate failures) stop playback immediately with no retries. On Android, the retry logic now classifies the root cause of error code 2001 by inspecting the exception chain. On iOS, retry logic is entirely new — previous versions had no automatic reconnection.

### Fixed
- **Android/iOS: duplicate `metadata` events when stream includes artwork URL**: Streams like Live365 that include artwork URLs in ICY metadata fired the `metadata` event twice, first without artwork, then again ~1s later with the URL after the async fetch completed. On Android, metadata collection now goes through Media3's `onEvents()` so both `onMediaMetadataChanged` and `onMetadata` merge into a single emit. On iOS, the async artwork fetch no longer emits a second event. Both platforms now fire one `metadata` event with the artwork URL included from the start.
- **Android: artwork not showing on Bluetooth car stereos**: Large bitmaps could exceed Binder transaction limits, causing the AVRCP stack to silently drop the artwork. The module now scales artwork to 512x512 max before passing it to the MediaSession.
- **Android: ForegroundServiceStartNotAllowedException on retry**: When the playback service was already running in the foreground, calling `start()` again (e.g., after retries exhausted) used `startForegroundService()` which crashes on Android 12+ if the app is in the background. Now uses `startService()` when the service is already active, and fires an error event if the foreground service fails to start.

### Changed
- **iOS: removed verbose metadata parsing logs**: Repetitive `NSLog` calls that fired every HLS segment (~8s) were visible in production builds. Removed them. Only errors, config changes, and artwork URL discovery are logged now.

### Documentation
- **CarPlay setup guide**: Instructions for requesting Apple's CarPlay Audio entitlement and configuring `tiapp.xml`. The module's existing `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter` integration already powers CarPlay, only the entitlement is needed.
- **Bluetooth artwork note**: Artwork display over Bluetooth depends on the car stereo's AVRCP version (1.4+ required), a hardware limitation outside the module's control.

---

## [1.1.3] - 2026-03-23

### Fixed
- **Android: 403 errors on streams that block ExoPlayer's default User-Agent (Live365, etc.)**: ExoPlayer sends `ExoPlayer/<version>` as its User-Agent, which some streaming servers reject. The module now uses a standard mobile browser User-Agent so these streams connect successfully.

---

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
