# TiAudioStream v1.0.0

Professional audio streaming module for Titanium SDK with proper audio focus handling, lock screen controls, and background playback.

## Why This Module?

The standard `Ti.Media.AudioPlayer` often creates **audio focus conflicts** and lacks deep integration with modern system controls. This module uses **Media3 ExoPlayer** (Android) and **AVPlayer** (iOS) as the unified source for both audio and system controls, ensuring your app behaves like a "good citizen" in the OS.

> **Note:** This is the first public release (Release Candidate 1). Android is fully verified on physical devices, while iOS is verified on Simulator (device testing pending).

## Current Status

| Platform | Version | Status |
| :--- | :--- | :--- |
| **Android** | 1.0.0 | **Stable** (Verified on physical devices) |
| **iOS** | 1.0.0 | **RC** (Verified on Simulator, Device pending) |

## Features

- **Background Playback**: High-performance streaming with a Foreground Service (Android).
- **Audio Focus**: Intelligent handling of interruptions (calls, notifications, Siri).
- **Smart Reconnection**: Interruptible retry logic that validates streams before reconnecting.
- **Terminal Error Detection**: Stops retrying immediately on HTTP 404/500 errors.
- **Media Controls**: Seamless integration with Lock Screen and Notification Center.
- **Remote Commands**: Support for headset/Bluetooth controls (Play, Pause, Skip, Stop).

## Requirements

- Titanium SDK 13.1.0.GA+
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
Configures the audio source. Resets internal error states.

#### `setMetadata({ title, artist, artwork })`
Sets metadata for system controls. `artwork` can be a remote URL or a local path.

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

## License
MIT License - Copyright (c) 2026 César Estrada (macCesar)
