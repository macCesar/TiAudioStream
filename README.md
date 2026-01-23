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
- **Deep Metadata Inspection**: Automatically extracts song titles from standard sources (ICY, HLS) AND hidden formats (JSON inside ID3 tags), ensuring support for networks like **Global Player** (Heart, Capital).
- **Terminal Error Detection**: Stops retrying immediately on HTTP 404/500 errors or down servers.
- **Media Controls**: Full integration with system UI components:
    - **Android**: Supports *Compact Media Notification* (lock screen), *Expanded Media Notification* (notification drawer), and the *System Media Player* (Quick Settings / Media Output).
    - **iOS**: Seamless integration with *Lock Screen Media Controls*, *Control Center Player*, and *Now Playing Info Center* (Apple Watch / CarPlay).
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

#### `metadata`
Fired when stream metadata (title, artist) is extracted automatically from the server.
- Payload: `title` (String), `artist` (String), `artwork` (String).

#### `remotecontrol`
Fired when the user interacts with system media controls (Lock screen, Headsets, Bluetooth).
- **Behavior**: The module follows industry standards by handling `PLAY`, `PAUSE`, and `STOP` commands **autonomously and immediately**. Redundant calls from the App in response to these events are automatically ignored to prevent playback conflicts.
- Payload: 
    - `subtype` (Number): Numeric constant.
    - `action` (String): Readable action name (`PLAY`, `PAUSE`, `STOP`, `NEXT`, `PREV`). 
- **Recommendation**: Use this event primarily for `NEXT` and `PREV` to switch stations/tracks. For transport actions (`PLAY`/`PAUSE`), the module ensures the system UI and audio engine remain in sync without App intervention.

## License
MIT License - Copyright (c) 2026 César Estrada (macCesar)
