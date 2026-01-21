# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-01-21
*Initial Release Candidate 1*

### Features
- **Unified Audio Engine**: Unified playback logic for Android (Media3) and iOS (AVPlayer).
- **Professional Audio Focus**: Intelligent handling of system interruptions (calls, Siri, other apps).
- **Background Persistence**: Reliable background playback using a Foreground Service (Android) and proper Audio Session management (iOS).
- **Media Controls**: Full integration with Lock Screen and Notification Center.
- **Remote Commands**: Support for Play, Pause, Stop, Next, and Previous from external devices (Bluetooth/Headsets).

### Fixed & Improved
- **Thread Safety (Android)**: Enforced main-thread execution for player commands to prevent "Wrong Thread" crashes.
- **Smart Reconnection**: Improved reconnection logic that validates URLs and prevents overlapping background tasks.
- **Notification Stability**: Controls now remain interactive even after network failures or stream timeouts.
- **Memory Management**: Optimized native resource cleanup on both platforms.

### Platform Status
- **Android**: Fully verified on physical devices (Stability: Production-ready).
- **iOS**: Verified on Simulator (Stability: RC - Physical device testing pending).
