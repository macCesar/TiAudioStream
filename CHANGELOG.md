# Changelog

All notable changes to this project will be documented in this file.

## [1.1.0] - 2026-01-19

### Fixed
- **Thread Safety (Android)**: Fixed "Player is accessed on the wrong thread" crash when attempting to reconnect. All player calls are now enforced on the Main Thread via Handler.
- **Blind Reconnection**: Fixed "instability" bug where background reconnection tasks would interrupt new active streams. Reconnection is now fully interruptible and validates the URL before waking up.
- **Terminal Error Handling**: Added surgical detection for IO/HTTP errors (404, 302, 500). The module now stops retrying immediately on dead streams, preventing redundant "buffering" loops.
- **Notification Persistence**: Fixed bug where terminal errors would kill the foreground service/notification. Controls now remain visible in the Notification Center/Lock Screen even after an error, allowing users to skip to the next station.

### Added
- **iOS Remote Control Expansion**: Added support for `Next` and `Previous` track commands in `MPRemoteCommandCenter`, matching Android behavior.
- **Enhanced Logging**: Improved native console logging for better debugging of network-related failures.

## [1.0.0] - 2026-01-18

### Added
- Initial release of **TiAudioStream** (ti.audiostream).
- **Android**: Implementation using Media3 ExoPlayer with foreground service and proper Audio Focus handling.
- **iOS**: Implementation using AVPlayer, AVAudioSession, and MPNowPlayingInfoCenter.
- **Unified API**: Native API providing a consistent `start()`, `pause()`, `stop()` interface.
- **Features**: Background playback, lock screen controls, automatic reconnection, and async artwork loading.
- **Fixes**: Resolved iOS linker errors and PCH conflicts by unifying core logic into the main module.
