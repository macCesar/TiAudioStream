# ti.audiostream

Professional audio streaming module for Titanium SDK with proper audio focus handling, lock screen controls, and background playback.

## Why This Module?

The standard `Ti.Media.AudioPlayer` combined with media session modules creates an **audio focus conflict**:

```
Ti.Media.AudioPlayer → requests audio focus (internally)
TiMediaSession       → requests audio focus (separately)
                     = TWO systems competing = callbacks never arrive correctly
```

**Result**: YouTube and your app play audio simultaneously instead of one pausing the other.

**Solution**: This module uses **Media3 ExoPlayer** (Android) and **AVPlayer** (iOS) as the ONLY audio source, with audio focus handling integrated in the same component that plays audio.

```
ti.audiostream → ExoPlayer/AVPlayer → audio focus (single system) ✓
```

## Features

### Audio Playback
- Stream audio from URLs (HTTP/HTTPS)
- HLS streaming support
- Background playback
- Automatic reconnection on network errors (up to 5 retries)

### Audio Focus (Android & iOS)
- Proper audio focus request before playback.
- Responds to interruptions (pause when other apps play or during calls).
- Abandons focus on stop.

### Media Controls
- Lock screen controls (MPNowPlayingInfoCenter / MediaSession).
- Notification with play/pause/next/prev buttons.
- Bluetooth/headphone controls.

### Metadata
- Title and artist display.
- Album artwork (local or remote URLs).
- Asynchronous artwork loading (no UI freeze).

## Requirements

- Titanium SDK 12.0.0+
- Android: API 24+ (Android 7.0+)
- iOS: 13.0+

## Installation

### Register in tiapp.xml

```xml
<modules>
  <module platform="android">ti.audiostream</module>
  <module platform="iphone">ti.audiostream</module>
</modules>
```

## API Reference

### Methods

#### `play()`
Starts or resumes playback. Requests audio focus automatically. (Alias: `start()`).

#### `pause()`
Pauses playback.

#### `stop()`
Stops playback and releases all resources.

#### `setStream(options)`
Configure the audio stream URL.
```javascript
radio.setStream({
  url: 'https://stream.example.com/radio.mp3',
  isLive: true
});
```

#### `setMetadata(options)`
Set metadata for lock screen and notification display.
```javascript
radio.setMetadata({
  title: 'Morning Show',
  artist: 'Radio Station',
  artwork: 'https://example.com/artwork.jpg'
});
```

### Events

#### `statechange`
Fired when playback state changes.
- States: `buffering`, `playing`, `paused`, `stopped`, `error`.

#### `remotecontrol`
Fired when user interacts with lock screen/notification controls.
- Payload includes `command` (string) and `subtype` (number).

## iOS Configuration
Add to `tiapp.xml`:
```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

## License
MIT License - Copyright (c) 2026 César Estrada (macCesar)
