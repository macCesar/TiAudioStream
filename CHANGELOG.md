# Changelog

All notable changes to this project will be documented in this file.

## [1.5.0] - 2026-07-01

### Added
- **CarPlay: Play/Pause row at the top of the station list.** The module deliberately stays on the station list instead of pushing the Now Playing template, which left no on-screen transport control (only the car's hardware buttons worked). A leading row now toggles playback and shows "Pausar" while playing / "Reproducir" while paused, kept in sync with the actual player state.
- **Per-station thumbnail in the car browse list (Android Auto + CarPlay).** The station list now shows each station's `artwork` URL as its leading thumbnail (the DJ/program photo) instead of a generic grey icon — the same image that already feeds the now-playing screen. Apps that register `artwork` per station get it automatically, no new API. Android Auto downloads the remote image itself (`MediaDescriptionCompat.setIconUri`); on CarPlay the module downloads it in the background and caches it (`NSCache`) so re-registering the list doesn't re-fetch.

### Fixed
- **Android: next/previous now also works when the app was opened and then swiped away.** 1.4.2 added native skip, but it only ran when the app's JS had no `remotecontrol` listeners. After the app was launched and then closed, its `activeModule` static kept a stale proxy whose listener registry still reported `true`, so the service deferred to a dead V8 runtime — the skip fired `Runtime disposed, cannot fire event 'remotecontrol'` and nothing advanced. `hasRemoteControlListeners()` now also checks `KrollRuntime.isDisposed()`, so a torn-down runtime correctly routes the skip to the native station list.
- **CarPlay: the now-playing indicator now appears on the correct station when you switch from the app.** The station list was refreshed at the moment of the change, while the new stream was still buffering (`rate == 0`), so `CPListItem.playing` stayed off and never turned on once playback actually started — only the "On Air" subtitle updated. The list is now refreshed when the player reaches the playing state (and cleared on pause), so the indicator tracks app-driven station changes. (CarPlay's grey row highlight is the system focus cursor and has no public API to move it programmatically; the playing indicator plus "On Air" are the markers we control.)

## [1.4.2] - 2026-07-01

### Fixed
- **Android: next/previous stations now work in the car when the app isn't running.** Skip-next/prev from the head unit only forwarded a `remotecontrol` event to the app's JS, which isn't alive when playback is launched cold from the car, so the buttons did nothing. The service now advances through the persisted Android Auto station list natively — still firing the event first, so an app that IS running handles it as before.
- **Android: Android Auto no longer shows a stale cover from a previous session.** Cached artwork files used a per-process counter (`art_1.jpg`, `art_2.jpg`, …) that reset on each launch, so a reused `content://` URI made Android Auto — which caches artwork by URI — serve an old image. Filenames are now unique per write (timestamped) and the few most recent files are kept instead of deleted immediately, so Android Auto always fetches the current cover.

### Notes
- iOS has no functional changes in this release; its version is bumped only to keep both platforms in sync.

## [1.4.1] - 2026-07-01

### Fixed
- **Android: per-song artwork now updates in Android Auto**: The now-playing screen kept showing the first cover (usually the station logo) while the phone notification and lock screen updated correctly. Android Auto ignores `http(s)` artwork URIs and caches embedded bitmaps, so it never re-rendered later covers. The module now also writes each cover to a private cache file and exposes it through a `FileProvider` `content://` URI (`METADATA_KEY_ALBUM_ART_URI`), granting read access to the connected media browser clients, so Android Auto re-fetches and shows the current song's art. The embedded bitmap is kept, so the notification, lock screen, and Bluetooth AVRCP are unchanged.

### Documentation
- Documented the Android Auto / CarPlay station-list API — `setAutomotiveStations()`, `setCurrentAutomotiveStation()`, and the `automotivestationselected` event — and wired it into the example app (`example/app.js`). The README now distinguishes the zero-code "now playing" integration from the browsable station list.

## [1.4.0] - 2026-06-22

### Added
- **Android: `allowCrossProtocolRedirects` property**: Exposes the cross-protocol redirect behavior (added in 1.3.3) as a module property. Defaults to `true` (parity with iOS/AVPlayer and browsers; required by CDNs like radiojar). Set `audioStream.allowCrossProtocolRedirects = false` before `start()` to forbid HTTPS→HTTP downgrades when you want strict transport. Read when the player is built. Android-only; no-op on iOS.

### Security
- Documented the transport-security tradeoff of cross-protocol redirects in the README: with the default on, an `https://` entry URL may be downgraded to `http://` by a server redirect, so it no longer guarantees encrypted transport. The data is public radio audio, so the risk is low; the new property lets security-conscious apps opt out.

## [1.3.3] - 2026-06-22

### Fixed
- **Android: follow cross-protocol redirects (HTTPS↔HTTP)**: Streams that redirect an HTTPS entry URL to a tokenized HTTP edge node (e.g. radiojar: `https://stream.radiojar.com/…` → `http://nNN.radiojar.com/…?rj-tok=…`) failed with a fatal `Response code: 302`. ExoPlayer's `DefaultHttpDataSource` rejects cross-protocol redirects by default; `setAllowCrossProtocolRedirects(true)` makes it follow them, matching iOS/AVPlayer and browsers.

## [1.3.2] - 2026-06-20

### Changed
- **Android: use a media-player User-Agent instead of a browser one**: The HTTP data source now identifies as `ti.audiostream (Android) ExoPlayerLib/1.5.1`. SHOUTcast/Icecast servers serve their HTML status page to browser-style User-Agents (which then fail to decode) but stream audio to media players, and some CDNs (e.g. Live365) reject the default `Dalvik/...` User-Agent with HTTP 403. A media-player User-Agent satisfies all of them — the same reason iOS/AVPlayer "just works". This **supersedes and removes** the `/;` URL rewriting added in 1.3.0/1.3.1, which is no longer needed: SHOUTcast bare-root and directory-style mount URLs now play as-is.

### Fixed
- **Android: unplayable streams fail fast instead of retrying 5×**: Unparseable content — e.g. a SHOUTcast/Icecast "Stream is Offline" page, or any non-audio response — is now treated as a terminal error (`ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED` / `_MANIFEST_UNSUPPORTED`). The player stops and fires a single `error` event, matching iOS. Previously these were retried 5 times (~15s), firing a repeated error/alert on each attempt.

### Notes
- `.pls`/`.m3u` playlist resolution (added in 1.3.0) is retained.
- iOS is unchanged — it already used a media-player User-Agent (AVPlayer) and treated decode failures as terminal.

## [1.3.1] - 2026-06-20

### Fixed
- **Android: SHOUTcast directory-style mount points now play**: Stream URLs whose path ends in `/` (e.g. `https://stream.radiocaroline.net/north/`) now get the SHOUTcast `/;` stream hint appended, just like bare-root URLs. Previously only path-less roots were normalized, so these mounts returned the HTML status page and failed to play.

## [1.3.0] - 2026-06-19

### Added
- **Android: SHOUTcast/Icecast playlist resolution**: `.pls` and `.m3u` stream URLs are now resolved to the underlying audio stream on a background thread before playback, matching iOS. ExoPlayer only parses `.m3u8` (HLS) natively, so these formats previously failed with `UnrecognizedInputFormatException`.

### Fixed
- **Android: SHOUTcast bare-root URLs no longer fail**: Root URLs such as `http://host:8000` now get the SHOUTcast `/;` stream hint appended, so the server returns the audio stream instead of its HTML status page. The browser User-Agent kept for strict servers (that 403 non-browser clients) was not enough on its own.
- **iOS: CarPlay reasserts audio source ownership across the playback lifecycle**: Ownership is refreshed on scene connect, playback start, and prepare-resume, with connect/disconnect tracking and deferred stream-item preparation, so CarPlay reliably adopts the app as the active Now Playing source.

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
