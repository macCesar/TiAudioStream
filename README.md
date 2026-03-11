# ti.audiostream

Audio streaming module for Titanium SDK. It gives you background playback, system media controls, and real-time metadata on Android and iOS through one API.

<div align="center">

![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![SDK](https://img.shields.io/badge/Titanium%20SDK-13.1.0.GA%2B-orange)

</div>

## Why ti.audiostream?

`Ti.Media.AudioPlayer` is fine for simple playback, but radio and live streams usually need more: lock screen controls, metadata parsing, reliable background behavior, and proper audio focus handling. Without that, you end up adding platform-specific patches in app code.

`ti.audiostream` uses Media3 ExoPlayer on Android and AVPlayer on iOS behind one JavaScript API. Playback and system integration are handled in the module, so ICY/ID3 parsing, artwork updates, and interruption/resume behavior stay consistent across platforms.

## Features

- Same JavaScript API for Android (Media3 ExoPlayer) and iOS (AVPlayer)
- Metadata parsing from ICY headers, ID3 tags, and non-standard payloads (for example embedded JSON used by some stations)
- Artwork updates for lock screen and notification/control surfaces
- Audio focus and interruption handling (calls, Siri, other apps) with resume logic that respects manual pauses
- Background playback support via Foreground Service (Android) and AVAudioSession (iOS)
- System media controls support: lock screen, notification shade, Control Center, CarPlay, Apple Watch
- Optional metadata auto-update control when you want to keep station branding instead of live track metadata

## Requirements

|              | Version          |
| :----------- | :--------------- |
| Titanium SDK | 13.1.1.GA+       |
| Android      | API 24+ (Nougat) |
| iOS          | 13.0+            |

### Mac Catalyst note

The iOS module includes Mac Catalyst support (`mac: true` in manifest). Running Mac Catalyst **apps** is supported since Titanium SDK `13.1.1.GA`. However, building the **module from source** with `mac: true` requires additional CLI fixes that are not yet in a GA release (currently provided by a local SDK build).

The required fixes are in an open Titanium SDK PR: [tidev/titanium-sdk#14391](https://github.com/tidev/titanium-sdk/pull/14391)

Once the PR is merged, building from source will work out of the box with the SDK version that includes these fixes. The pre-built module zip works on `13.1.1.GA+` without any custom SDK.

## Installation

### 1. Add the module to tiapp.xml

```xml
<modules>
  <module>ti.audiostream</module>
</modules>
```

### 2. iOS: Enable background audio

Add the `audio` background mode to your `tiapp.xml` inside the `<ios><plist><dict>` section:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Without this, iOS will suspend audio when the app goes to the background.

### 3. Android: Permissions (automatic)

The module's `timodule.xml` declares the required permissions, and Titanium merges them into your build automatically:

- `INTERNET` - stream access
- `WAKE_LOCK` - prevents CPU sleep during playback
- `FOREGROUND_SERVICE` - keeps audio alive in the background
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK` - Android 14+ foreground service type

You don't need to add these to your `tiapp.xml`.

## Quick Start

```javascript
const audioStream = require('ti.audiostream')

// Configure the stream
audioStream.setStream({
  isLive: true,
  title: 'Radio Paradise',
  artist: 'Eclectic Rock',
  artwork: 'https://example.com/logo.png',
  url: 'https://stream.radioparadise.com/aac-320'
})

// Listen for state changes
audioStream.addEventListener('state', (e) => {
  Ti.API.info('State: ' + e.state) // playing, buffering, paused, stopped, error
})

// Listen for metadata updates
audioStream.addEventListener('metadata', (e) => {
  Ti.API.info(e.artist + ' - ' + e.title)
  if (e.artwork) {
    Ti.API.info('Artwork: ' + e.artwork)
  }
})

// Start playback
audioStream.start()
```

## API Reference

### Methods

#### `setStream(options)`

Initializes the audio source. Call this before `start()` or to switch streams.

| Parameter            | Type          | Required | Description                                                                                                             |
| :------------------- | :------------ | :------- | :---------------------------------------------------------------------------------------------------------------------- |
| `url`                | String        | Yes      | HLS (`.m3u8`) or direct audio stream URL                                                                                |
| `isLive`             | Boolean       | No       | Hides seek bar and shows live indicator on system controls. Default: `true`.                                            |
| `autoUpdateMetadata` | Boolean       | No       | Auto-update lock screen from stream metadata. Default: `true`.                                                          |
| `title`              | String        | No       | Initial title for lock screen / notification                                                                            |
| `artist`             | String        | No       | Initial artist for lock screen / notification                                                                           |
| `artwork`            | String        | No       | Initial artwork URL for lock screen / notification                                                                      |
| `metadataRules`      | Object / null | No       | Regex cleanup rules (see [`setMetadataRules()`](#setmetadatarulesrules)). Omit to keep existing rules, `null` to clear. |

```javascript
audioStream.setStream({
  isLive: true,
  title: 'Radio Paradise',
  artist: 'Eclectic Rock',
  artwork: 'https://example.com/cover.png',
  url: 'https://stream.radioparadise.com/aac-320',
  metadataRules: {
    artist: [
      { match: '^(.+),\\s*The$', replace: 'The $1' }
    ]
  }
})
```

#### `start()` / `play()`

Starts or resumes playback. Requests audio focus and activates system controls automatically.

#### `pause()`

Pauses playback. The notification stays visible so the user can resume from the lock screen.

#### `stop()`

Soft-stops playback for live streams. It hides system controls and releases audio focus, but keeps the current stream prepared when possible so `start()` can resume quickly.

Use this when you want fast resume behavior similar to many radio/music apps.

#### `hardStop()`

Stops playback completely and tears down the active stream/session so the next `start()` performs a fresh reconnect.

Use this for live radio when you want to return to the live edge instead of resuming from buffered audio.

```javascript
// Fast resume
audioStream.stop()

// Fresh reconnect to live edge
audioStream.hardStop()
// or, on both platforms:
audioStream.stop({ hard: true })
```

#### `setMetadata(options)`

Manually sets lock screen and notification metadata without changing the stream.

| Parameter | Type          | Description                                           |
| :-------- | :------------ | :---------------------------------------------------- |
| `title`   | String        | Track or station title                                |
| `artist`  | String        | Artist or description                                 |
| `artwork` | String / null | Artwork URL, `null` to clear, or omit to keep current |

**Artwork behavior:**
- Set `artwork` to `null` or `""` → clears the artwork
- Set `artwork` to a URL → loads and displays the new image
- Omit `artwork` → keeps whatever artwork is currently showing

**Android OEM lock screen note:**
- On some vendor lock screens, stale artwork can persist when `largeIcon` is sent as `null`.
- The module forces a real icon replacement when no artwork is available to ensure previous covers are cleared.

```javascript
audioStream.setMetadata({
  title: 'Station Branding',
  artist: 'Your Radio App'
  // artwork omitted, keeps current artwork
})
```

#### `setAutoUpdateMetadata(enabled)`

Toggles whether stream metadata automatically updates the lock screen and notification.

- `true` - stream metadata updates system controls automatically (default)
- `false` - only `setMetadata()` calls update system controls. The `metadata` event still fires either way

```javascript
// Take manual control
audioStream.setAutoUpdateMetadata(false)
```

#### `setMetadataRules(rules)`

Defines regex-based cleanup rules that the module applies automatically to parsed metadata before updating the lock screen and firing the `metadata` event. `autoUpdateMetadata` stays on; rules and auto-update work together.

| Parameter | Type          | Description                                                             |
| :-------- | :------------ | :---------------------------------------------------------------------- |
| `rules`   | Object / null | Object with `title` and/or `artist` arrays of rules, or `null` to clear |

Each rule is an object with:

| Property  | Type   | Description                                                    |
| :-------- | :----- | :------------------------------------------------------------- |
| `match`   | String | Regex pattern to match against the field value                 |
| `replace` | String | Replacement string (supports capture groups: `$1`, `$2`, etc.) |

Rules are applied in array order. `setMetadata()` (manual override) is **not** affected by rules. You can also pass `metadataRules` directly in [`setStream()`](#setstreamoptions).

```javascript
// Example: Radio sends "Mission, The - Tower Of Strength (1987) - Single"
// After built-in "Artist - Title" split:
//   artist = "Mission, The"
//   title  = "Tower Of Strength (1987) - Single"

audioStream.setMetadataRules({
  artist: [
    // "Mission, The" → "The Mission"
    { match: '^(.+),\\s*The$', replace: 'The $1' }
  ],
  title: [
    // Remove (YYYY) y también (YYYY) - ... al final del título
    { match: '\\s*\\(\\d{4}\\)(?:\\s*-\\s*.+)?$', replace: '' }
  ]
})

// Result on lock screen: "The Mission" - "Tower Of Strength"

// Clear all rules (raw metadata shows again)
audioStream.setMetadataRules(null)
```

### Properties

| Property  | Type                | Description                          |
| :-------- | :------------------ | :----------------------------------- |
| `playing` | Boolean (read-only) | `true` if audio is currently playing |

### Events

#### `state`

Fired on playback state changes.

| Property | Type   | Values                                               |
| :------- | :----- | :--------------------------------------------------- |
| `state`  | String | `playing`, `buffering`, `paused`, `stopped`, `error` |

#### `metadata`

Fired when the engine extracts new metadata from the stream. This event fires regardless of the `autoUpdateMetadata` setting, so your app code always gets it.

| Property  | Type   | Description                                        |
| :-------- | :----- | :------------------------------------------------- |
| `title`   | String | Parsed track title                                 |
| `artist`  | String | Parsed artist name                                 |
| `artwork` | String | Artwork URL (when available)                       |
| `raw`     | Object | Every tag found in the stream, for deep inspection |

#### `error`

Fired on playback errors.

| Property  | Type   | Description       |
| :-------- | :----- | :---------------- |
| `message` | String | Error description |

On Android, the module automatically retries failed connections up to **5 times** with a **3-second delay** between attempts before firing this event.

#### `remotecontrol`

Fired when the user interacts with system media controls (lock screen, notification, Control Center).

| Property  | Type   | Description                             |
| :-------- | :----- | :-------------------------------------- |
| `action`  | String | `PLAY`, `PAUSE`, `STOP`, `NEXT`, `PREV` |
| `subtype` | Number | Numeric constant (see table below)      |

The engine handles `PLAY`, `PAUSE`, and `STOP` on its own. `NEXT` and `PREV` fire the event so your app can decide what to do (the module doesn't know your playlist).

**Constants:**

| Constant                            | Value | Platform |
| :---------------------------------- | :---- | :------- |
| `REMOTE_CONTROL_PLAY`               | 100   | Both     |
| `REMOTE_CONTROL_PAUSE`              | 101   | Both     |
| `REMOTE_CONTROL_STOP`               | 102   | Both     |
| `REMOTE_CONTROL_PLAY_PAUSE`         | 103   | Both     |
| `REMOTE_CONTROL_NEXT`               | 104   | Both     |
| `REMOTE_CONTROL_PREV`               | 105   | Both     |
| `REMOTE_CONTROL_START_SEEK_BACK`    | 106   | Android  |
| `REMOTE_CONTROL_END_SEEK_BACK`      | 107   | Android  |
| `REMOTE_CONTROL_START_SEEK_FORWARD` | 108   | Android  |
| `REMOTE_CONTROL_END_SEEK_FORWARD`   | 109   | Android  |

## Guides

### Updating your app UI from stream metadata

The lock screen, notification, and Control Center update automatically when the stream sends new metadata. You don't need any code for that.

Your app UI is a different story. To keep your own labels and images in sync, listen for the `metadata` event:

```javascript
const audioStream = require('ti.audiostream')

audioStream.setStream({
  isLive: true,
  title: 'Radio Paradise',
  artist: 'Eclectic Rock',
  artwork: 'https://example.com/logo.png',
  url: 'https://stream.radioparadise.com/aac-320'
})

audioStream.addEventListener('metadata', (e) => {
  if (e.title) titleLabel.text = e.title
  if (e.artist) artistLabel.text = e.artist
  if (e.artwork) artworkImage.image = e.artwork
})

audioStream.start()
```

System controls are fully automatic. Your in-app UI is manual via the event.

### Handling remote controls (playlist rotation)

Play/Pause/Stop are handled automatically by the engine. You only need to handle `NEXT` and `PREV`:

```javascript
const STREAMS = [
  { url: 'https://stream.radioparadise.com/aac-320', title: 'Radio Paradise', artist: 'Eclectic Rock' },
  { url: 'http://ice1.somafm.com/groovesalad-128-mp3', title: 'Groove Salad', artist: 'Ambient Beats' },
  { url: 'https://knkx-live-a.edge.audiocdn.com/6285_256k/playlist.m3u8', title: 'Jazz24', artist: 'Public Radio' }
]

let currentIndex = 0

function loadStation(index) {
  currentIndex = index
  const station = STREAMS[currentIndex]

  audioStream.setStream({
    isLive: true,
    url: station.url,
    title: station.title,
    artist: station.artist
  })

  audioStream.start()
}

audioStream.addEventListener('remotecontrol', (e) => {
  if (e.action === 'NEXT') {
    loadStation((currentIndex + 1) % STREAMS.length)
  }
  if (e.action === 'PREV') {
    loadStation((currentIndex - 1 + STREAMS.length) % STREAMS.length)
  }
})

loadStation(0)
```

### Custom metadata cleaning

Some streams send messy metadata with extra tags, weird formatting, or raw codes. Use `setMetadataRules()` to define regex cleanup rules that the module applies automatically, without disabling auto-update or writing manual event handling:

```javascript
// Stream sends: "Mission, The - Tower Of Strength (1987) - Single"
// Define rules to clean it up automatically
audioStream.setMetadataRules({
  artist: [
    // "Mission, The" → "The Mission"
    { match: '^(.+),\\s*The$', replace: 'The $1' }
  ],
  title: [
    { match: '\\s*\\[.*?\\]\\s*', replace: '' },       // Remove [tags]
    { match: '\\s*\\(\\d{4}\\)(?:\\s*-\\s*.+)?$', replace: '' }  // Remove (YYYY) y también (YYYY) - ... al final del título
  ]
})
```

Rules are applied after the module's built-in parsing (ICY split, "Artist - Title" split) and before updating the lock screen. The `metadata` event fires with the cleaned values. Call `setMetadataRules(null)` to clear all rules.

For cases where regex rules aren't enough, you can still take full manual control:

```javascript
// Disable automatic lock screen updates
audioStream.setAutoUpdateMetadata(false)

audioStream.addEventListener('metadata', (e) => {
  // Clean up the title
  let title = e.title || ''
  title = title.replace(/\s*\[.*?\]\s*/g, '')  // Remove [tags]
  title = title.replace(/\s*\(.*?HD\)/gi, '')   // Remove (quality markers)
  title = title.trim()

  let artist = e.artist || ''

  // Push cleaned metadata to lock screen
  audioStream.setMetadata({
    title: title || 'Unknown Track',
    artist: artist || 'Live Radio'
  })

  // Update your app UI too
  titleLabel.text = title
  artistLabel.text = artist
})
```

The `metadata` event always fires regardless of `autoUpdateMetadata`. That flag only controls whether the lock screen gets updated automatically.

### Error handling

```javascript
audioStream.addEventListener('error', (e) => {
  const msg = e.message || 'Stream unavailable'
  Ti.API.error('[AudioStream] ' + msg)

  // Show user-friendly message
  Ti.UI.createAlertDialog({
    title: 'Connection Failed',
    message: 'Could not connect to the station. Check your internet connection and try again.',
    buttonNames: ['OK']
  }).show()
})

audioStream.addEventListener('state', (e) => {
  if (e.state === 'error') {
    // Update UI to reflect error state
    stateLabel.text = 'ERROR'
    stateLabel.color = '#ff3b30'
  }
})
```

On Android, the engine retries failed connections automatically (5 attempts, 3 seconds apart) before firing the error event.

### Platform-specific behavior

#### iOS

- Background audio requires `UIBackgroundModes: audio` in your plist (see [Installation](#installation))
- Lock screen controls appear in Control Center and on Apple Watch / CarPlay through MPRemoteCommandCenter
- Audio session uses the Playback category, so audio continues when the screen locks or the app backgrounds
- If a phone call interrupts playback, audio resumes when the call ends (only if it was playing before the interruption)

#### Android

- Background playback runs inside a Foreground Service with a persistent media notification
- The notification has compact (lock screen), expanded (drawer), and system media player (Quick Settings) views
- Uses MediaSession for Bluetooth devices, Android Auto, and the system output switcher
- If the stream drops, the engine retries 5 times with a 3-second delay before reporting an error
- All permissions are declared in the module's `timodule.xml` and merged automatically. No manual manifest editing needed

## How metadata extraction works

Both platforms parse metadata through multiple layers to handle different stream formats:

| Format                 | Source                            | Example                          |
| :--------------------- | :-------------------------------- | :------------------------------- |
| **ICY headers**        | Shoutcast/Icecast `StreamTitle`   | `StreamTitle='Artist - Song';`   |
| **ID3 text frames**    | `TIT2` (title), `TPE1` (artist)   | Standard MP3 metadata            |
| **ID3 comment frames** | `COMM` field with embedded data   | Global Player / Heart Radio      |
| **Embedded JSON**      | JSON inside ID3 frames            | `{"title":"...","artist":"..."}` |
| **Stream URL artwork** | ICY URL ending in image extension | `http://...cover.jpg`            |
| **Embedded artwork**   | Binary image data in metadata     | APIC frames, CommonMetadata      |

When a stream sends `Artist - Title` as a single string (common with ICY), the module splits it automatically. The `raw` property in the `metadata` event gives you every tag the parser found, which is useful for debugging non-standard formats.

## Technical implementation

| Feature             | Android                     | iOS                                  |
| :------------------ | :-------------------------- | :----------------------------------- |
| **Engine**          | Media3 ExoPlayer (1.5+)     | AVFoundation (AVPlayer)              |
| **Background**      | Foreground Service          | AVAudioSession (Playback)            |
| **System controls** | MediaSessionCompat          | MPRemoteCommandCenter                |
| **Metadata**        | ID3 / ICY / Deep JSON       | TimedMetadata / CommonMetadata       |
| **Audio focus**     | AudioManager + MediaSession | AVAudioSession interruption handling |
| **Reconnect**       | 5 retries, 3s delay         | Managed by AVPlayer                  |

## License

MIT License. Copyright (c) 2026 César Estrada ([macCesar](https://github.com/macCesar))
