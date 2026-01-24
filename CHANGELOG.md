# Changelog

All notable changes to this project will be documented in this file.

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