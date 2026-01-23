# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-01-22
*Initial Stable Release*

### Features
- **Unified Audio Engine**: Unified playback logic for Android (Media3) and iOS (AVPlayer).
- **Deep Metadata Inspection**: Automatically extracts song titles from standard sources (ICY, HLS) AND hidden formats (JSON inside ID3 tags), ensuring support for networks like **Global Player** (Heart, Capital).
- **Automatic Stream Artwork**: Automatically extracts and displays album art embedded in audio streams directly on the system lock screen and notification drawer.
- **Professional Audio Focus**: Intelligent handling of system interruptions (calls, Siri, other apps) with "smart resume" logic that respects user intent.
- **Background Persistence**: Reliable background playback using a Foreground Service (Android) and proper Audio Session management (iOS).
- **Media Controls**: Seamless integration with Lock Screen and Notification Center.
- **Remote Commands**: Support for Play, Pause, Stop, Next, and Previous from external devices (Bluetooth/Headsets).

### Improved
- **Robust HLS Parsing**: Aggressively scans `timedMetadata`, `commonMetadata`, and raw ID3 frames ensuring compatibility with a wider range of streaming providers.
- **Intelligent Title Splitting**: Automatically separates "Artist - Title" strings into distinct fields for the Lock Screen.
- **Terminal Error Detection (iOS)**: The module now monitors the native `ErrorLog` to detect HTTP 404/500 errors and immediately stop playback instead of attempting useless retries.
- **Audio Interruption Fix**: Correctly distinguishes between system interruptions (calls) and manual pauses.
- **Thread Safety (Android)**: Enforced main-thread execution for player commands to prevent "Wrong Thread" crashes.

### Platform Status
- **Android**: Fully verified on physical devices (Stability: Production-ready).
- **iOS**: Verified on Simulator & Device (Stability: Production-ready).