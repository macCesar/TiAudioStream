# Changelog

All notable changes to ti.audiostream will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-01-18

### Added

#### Core Features
- Initial release of ti.audiostream module
- Cross-platform support for Android and iOS
- Unified JavaScript API across both platforms

#### Android Implementation
- **Media3 ExoPlayer 1.5.1** integration (modern, non-deprecated APIs)
- **Audio Focus** handling with full support for:
  - `AUDIOFOCUS_GAIN` - Request exclusive audio focus
  - `AUDIOFOCUS_LOSS` - Stop playback when another app takes focus
  - `AUDIOFOCUS_LOSS_TRANSIENT` - Pause for temporary interruptions
  - `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` - Lower volume (20%) for notifications
- **Foreground Service** with `mediaPlayback` type for Android 14+ compliance
- **MediaSessionCompat** integration for:
  - Lock screen controls
  - Bluetooth/headphone controls
  - Notification media controls
- **MediaStyle Notification** with play/pause/stop actions
- **Automatic reconnection** on stream errors (5 retries, 3 second delay)
- **Asynchronous artwork loading** with ExecutorService
- **HLS streaming** support via media3-exoplayer-hls
- Proper cleanup with `onTaskRemoved` when app is closed

#### iOS Implementation
- **AVPlayer** integration for audio playback
- **AVAudioSession** with `.playback` category for background audio
- **MPNowPlayingInfoCenter** for lock screen metadata display
- **MPRemoteCommandCenter** for:
  - Lock screen play/pause/stop controls
  - Headphone button controls
  - Next/previous track controls
- **KVO Observers** for player state:
  - `status` - Ready to play / failed
  - `playbackBufferEmpty` - Buffering detection
  - `playbackLikelyToKeepUp` - Buffer ready
- **Interruption handling** for phone calls
- **Route change handling** for headphone unplug (auto-pause)
- **Automatic reconnection** on stream errors (5 retries, 3 second delay)
- **Asynchronous artwork loading** with dispatch_async

#### API
- `setStream(options)` - Configure stream URL and live mode
- `start()` - Begin playback with audio focus request
- `pause()` - Pause without releasing audio focus
- `stop()` - Stop and release all resources
- `setMetadata(options)` - Set title, artist, and artwork
- `playing` property - Check current playback state
- `state` event - Playback state changes
- `error` event - Error notifications
- `audiofocuschange` event - Audio focus changes (Android)
- `remotecontrol` event - Lock screen/notification control actions

#### Constants
- `REMOTE_CONTROL_PLAY` (100)
- `REMOTE_CONTROL_PAUSE` (101)
- `REMOTE_CONTROL_STOP` (102)
- `REMOTE_CONTROL_PLAY_PAUSE` (103)
- `REMOTE_CONTROL_NEXT` (104)
- `REMOTE_CONTROL_PREV` (105)
- `REMOTE_CONTROL_START_SEEK_BACK` (106) - iOS only
- `REMOTE_CONTROL_END_SEEK_BACK` (107) - iOS only
- `REMOTE_CONTROL_START_SEEK_FORWARD` (108) - iOS only
- `REMOTE_CONTROL_END_SEEK_FORWARD` (109) - iOS only
- `AUDIOFOCUS_GAIN` - Android only
- `AUDIOFOCUS_LOSS` - Android only
- `AUDIOFOCUS_LOSS_TRANSIENT` - Android only
- `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` - Android only

### Technical Details

#### Why This Module Exists
The standard `Ti.Media.AudioPlayer` combined with media session modules creates an audio focus conflict where both systems request audio focus separately. This results in apps like YouTube continuing to play audio simultaneously with your app.

This module solves the problem by using native audio players (Media3 ExoPlayer / AVPlayer) as the ONLY audio source, with audio focus handling integrated in the same component.

#### Dependencies
- **Android**: Media3 1.5.1 (androidx.media3:media3-exoplayer)
- **iOS**: AVFoundation, MediaPlayer frameworks

#### Requirements
- Titanium SDK 12.0.0+
- Android API 24+ (Android 7.0+)
- iOS 13.0+

---

## Future Releases

### Planned for 1.1.0
- [ ] LruCache for artwork caching (Android)
- [ ] NSCache for artwork caching (iOS)
- [ ] Seek functionality for non-live streams
- [ ] Playback speed control
- [ ] Volume control API

### Planned for 1.2.0
- [ ] Playlist/queue support
- [ ] Gapless playback
- [ ] Sleep timer
- [ ] Equalizer support (Android)
