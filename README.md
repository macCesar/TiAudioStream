# ti.audiostream

Professional Audio Engine for Titanium SDK. High-performance, autonomous audio streaming with integrated system-level controls for Android and iOS.

## Architectural Overview

Unlike standard implementations that separate the audio player from the system media session, `ti.audiostream` employs a **unified engine architecture**. By using **Media3 ExoPlayer** (Android) and **AVPlayer** (iOS) as the single source of truth for both playback and system integration, the module eliminates common synchronization issues, audio focus conflicts, and background termination.

### Core Capabilities

- **Autonomous Lifecycle Management**: Handles background persistence using a native Foreground Service (Android) and optimized Audio Session management (iOS).
- **Intelligent Live Stream Recovery**: Automatically detects stale HLS segments or buffer expiration after long pauses, forcing a "Live Edge" resurrection to prevent infinite buffering or silent failures.
- **Deep Metadata Inspection**: An advanced parsing engine that extracts real-time metadata from standard ICY/ID3 tags and non-standard nested formats (e.g., JSON embedded in ID3 frames used by Global Player/Heart Radio).
- **Proactive Audio Focus**: Built-in logic to handle system interruptions (calls, Siri, notifications) with smart-resume capabilities based on user intent.
- **Native OS Integration**: Full support for system UI components:
    - **Android**: Compact Media Notification (Lock Screen), Expanded Media Notification (Drawer), and System Media Player (Quick Settings / Output Switcher).
    - **iOS**: Lock Screen Media Controls, Control Center Player, and Now Playing Info Center (Apple Watch / CarPlay).

## Technical Implementation

| Feature         | Android Implementation  | iOS Implementation             |
| :-------------- | :---------------------- | :----------------------------- |
| **Engine**      | Media3 ExoPlayer (1.5+) | AVFoundation (AVPlayer)        |
| **Persistence** | Foreground Service      | AVAudioSession (Playback)      |
| **Controls**    | MediaSessionCompat      | MPRemoteCommandCenter          |
| **Metadata**    | ID3 / ICY / Deep JSON   | TimedMetadata / CommonMetadata |

## Requirements

- Titanium SDK 13.1.0.GA+
- Android: API 24+ (Nougat) or higher.
- iOS: 13.0 or higher.

## API Reference

### Methods

#### `setStream({ url, isLive })`
Initializes the audio source. 
- `url` (String): The HLS (.m3u8) or direct audio stream URL.
- `isLive` (Boolean): If true, enables specialized "Live Edge" recovery logic.

#### `start()` / `play()`
Starts or resumes playback. It handles Audio Focus requests and system control synchronization automatically.

#### `pause()` / `stop()`
`pause()` halts the audio but keeps the notification alive. `stop()` clears all resources and removes system UI components.

#### `setMetadata({ title, artist, artwork })`
Manually overrides or complements stream metadata. `artwork` supports remote URLs or local asset paths.

### Events

#### `state`
Fired on playback lifecycle changes.
- `state` (String): `playing`, `buffering`, `paused`, `stopped`, `error`.

#### `error`
Fired on terminal or recoverable network failures.
- `message` (String): Error description.

#### `metadata`
Fired when the engine extracts new information from the stream.
- `title`, `artist`: Standardized strings.
- `raw`: A raw Map/Dictionary containing every tag found in the stream for deep inspection.

#### `remotecontrol`
Fired on system-level interactions. Note: Transport actions (Play/Pause) are handled autonomously to ensure OS-level stability.
- `subtype` (Number): Numeric constant.
- `action` (String): Readable string (`PLAY`, `PAUSE`, `STOP`, `NEXT`, `PREV`).

## License
MIT License - Copyright (c) 2026 César Estrada (macCesar)
