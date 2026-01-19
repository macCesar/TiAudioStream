# TiAudioStream

Professional audio streaming module for Titanium SDK with proper audio focus handling, lock screen controls, and background playback.

## Why This Module?

The standard `Ti.Media.AudioPlayer` combined with separate media session modules often creates **audio focus conflicts**. This module uses **Media3 ExoPlayer** (Android) and **AVPlayer** (iOS) as the unified source for both audio and system controls.

## Features

- **Background Playback**: High-performance streaming with foreground service (Android).
- **Audio Focus**: Built-in handling for interruptions (calls, other media).
- **Smart Reconnection**: Interruptible retry logic that doesn't conflict with new streams.
- **Terminal Error Detection**: Surgical detection of HTTP 404/302/500 errors to stop retrying immediately.
- **Media Controls**: Seamless integration with Lock Screen and Notification Center.
- **Persistent Controls**: Controls remain visible even after a stream error, allowing station skipping.

## Requirements

- Titanium SDK 12.0.0+ (Tested on 13.1.0.GA)
- Android: API 24+
- iOS: 13.0+

## API Reference

### Methods

#### `start()` / `play()`
Starts or resumes playback. Requests audio focus automatically.

#### `pause()`
Pauses playback.

#### `stop()`
Stops playback and clears notification controls.

#### `setStream({ url, isLive })`
Configures the source. Resetting retry logic automatically.

#### `setMetadata({ title, artist, artwork })`
Sets metadata for system controls. `artwork` can be a remote URL or local path.

### Events

#### `state`
Fired when playback state changes.
- Payload: `state` (String: `playing`, `buffering`, `paused`, `stopped`, `error`).

#### `error`
Fired when a playback or network error occurs.
- Payload: `message` (String).

#### `remotecontrol`
Fired on system control interaction (Lock screen / Headsets / Bluetooth).
- Payload: `subtype` (Number). Matches module constants.

## Constants (Remote Control)
- `REMOTE_CONTROL_PLAY`
- `REMOTE_CONTROL_PAUSE`
- `REMOTE_CONTROL_STOP`
- `REMOTE_CONTROL_PLAY_PAUSE`
- `REMOTE_CONTROL_NEXT`
- `REMOTE_CONTROL_PREV`

## License
MIT License - Copyright (c) 2026 César Estrada (macCesar)
