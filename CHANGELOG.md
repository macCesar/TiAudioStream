# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2026-01-18

### Added
- Initial release of **TiAudioStream** (ti.audiostream).
- **Android**: Implementation using Media3 ExoPlayer with foreground service and proper Audio Focus handling.
- **iOS**: Implementation using AVPlayer, AVAudioSession, and MPNowPlayingInfoCenter.
- **Unified API**: CommonJS bridge to provide a consistent `play()`, `pause()`, `stop()` API across platforms.
- **Features**: Background playback, lock screen controls, automatic reconnection, and async artwork loading.
- **Fixes**: Resolved iOS linker errors and PCH conflicts by unifying core logic into the main module.
