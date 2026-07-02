# ti.audiostream

Audio streaming module for Titanium SDK. It handles background playback, system media controls, and live metadata on Android and iOS through one API.

<div align="center">

![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![SDK](https://img.shields.io/badge/Titanium%20SDK-13.1.1.GA%2B-orange)

</div>

## Why ti.audiostream?

`Ti.Media.AudioPlayer` is fine for simple playback, but radio and live streams usually need more: lock screen controls, metadata parsing, reliable background behavior, and proper audio focus handling. Without that, you end up adding platform-specific patches in app code.

`ti.audiostream` uses Media3 ExoPlayer on Android and AVPlayer on iOS behind a single JavaScript API. The module handles playback and system integration, so ICY/ID3 parsing, artwork updates, and interruption or resume behavior stay consistent across platforms.

## Features

- Same JavaScript API for Android (Media3 ExoPlayer) and iOS (AVPlayer)
- Broad stream support out of the box: direct audio (MP3/AAC), HLS (`.m3u8`), `.pls`/`.m3u` playlists (resolved automatically), and SHOUTcast/Icecast servers (including bare-root URLs like `http://host:8000` and directory mounts), with no per-URL workarounds
- Metadata parsing from ICY headers, ID3 tags, and non-standard payloads (for example embedded JSON used by some stations)
- Artwork updates for lock screen and notification/control surfaces, with automatic app icon fallback when no artwork is available
- Audio focus and interruption handling (calls, Siri, other apps) with resume logic that respects manual pauses
- Background playback support via Foreground Service (Android) and AVAudioSession (iOS)
- System media controls support: lock screen, notification shade, Control Center, CarPlay, Apple Watch, Android Auto
- Optional metadata auto-update control when you want to keep station branding instead of live track metadata

## Requirements

|              | Version          |
| :----------- | :--------------- |
| Titanium SDK | 13.1.1.GA+       |
| Android      | API 24+ (Nougat) |
| iOS          | 13.0+            |

### Mac Catalyst note

The iOS module includes Mac Catalyst support (`mac: true` in manifest). Running Mac Catalyst **apps** is supported since Titanium SDK `13.1.1.GA`. Building the **module from source** with `mac: true` needs the CLI fix from [tidev/titanium-sdk#14391](https://github.com/tidev/titanium-sdk/pull/14391), which merged in February 2026 and ships in `13.2.0.GA+`. The pre-built module zip works on `13.1.1.GA+`.

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

### 3. Android: permissions

The module's `timodule.xml` declares the required permissions, and Titanium merges them into your build:

- `INTERNET` - stream access
- `WAKE_LOCK` - prevents CPU sleep during playback
- `FOREGROUND_SERVICE` - keeps audio alive in the background
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK` - Android 14+ foreground service type

You don't need to add these to your `tiapp.xml`.

## Quick start

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

## API reference

### Methods

#### `setStream(options)`

Initializes the audio source. Call this before `start()` or when switching streams.

| Parameter            | Type          | Required | Description                                                                                                                  |
| :------------------- | :------------ | :------- | :--------------------------------------------------------------------------------------------------------------------------- |
| `url`                | String        | Yes      | Direct audio stream, HLS (`.m3u8`), or a `.pls`/`.m3u` playlist (resolved automatically). SHOUTcast/Icecast URLs work as-is. |
| `isLive`             | Boolean       | No       | Hides seek bar and shows live indicator on system controls. Default: `true`.                                                 |
| `autoUpdateMetadata` | Boolean       | No       | Auto-update lock screen from stream metadata. Default: `true`.                                                               |
| `title`              | String        | No       | Initial title for lock screen / notification                                                                                 |
| `artist`             | String        | No       | Initial artist for lock screen / notification                                                                                |
| `artwork`            | String        | No       | Initial artwork URL for lock screen / notification                                                                           |
| `metadataRules`      | Object / null | No       | Regex cleanup rules (see [`setMetadataRules()`](#setmetadatarulesrules)). Omit to keep existing rules, `null` to clear.      |

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

Starts or resumes playback. The module requests audio focus and enables system controls automatically.

#### `pause()`

Pauses playback. The notification stays visible so the user can resume from the lock screen.

#### `stop()`

Soft-stops playback for live streams. It hides system controls and releases audio focus, but keeps the current stream prepared when possible so `start()` can resume quickly.

Use this when you want fast resume behavior, similar to many radio or music apps.

#### `hardStop()`

Stops playback completely and tears down the active stream or session so the next `start()` does a fresh reconnect.

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

Controls whether stream metadata updates the lock screen and notification automatically.

- `true` - stream metadata updates system controls automatically (default)
- `false` - only `setMetadata()` calls update system controls. The `metadata` event still fires either way

```javascript
// Take manual control
audioStream.setAutoUpdateMetadata(false)
```

#### `setMetadataRules(rules)`

Defines regex-based cleanup rules. The module applies them to parsed metadata before updating the lock screen and firing the `metadata` event. `autoUpdateMetadata` stays on, so rules and auto-update still work together.

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

#### `setAutomotiveStations(stations)`

Registers a list of stations for the Android Auto / CarPlay **browse list** — what the car shows when the app is opened from the head unit. Without this, the car only shows a single "now playing" item while something is already streaming (and nothing at all when opened cold from the car). The module persists the list natively, so it survives the app being killed.

Pass an array of station objects, or `null` to clear:

| Field       | Type    | Description                                                            |
| :---------- | :------ | :--------------------------------------------------------------------- |
| `id`        | String  | Stable, unique id — echoed back in `automotivestationselected`         |
| `streamUrl` | String  | Stream URL to play when the station is tapped                          |
| `title`     | String  | Station title shown in the list                                        |
| `subtitle`  | String  | Secondary line (e.g. frequency or slogan)                              |
| `artist`    | String  | Optional; used for now-playing metadata                                |
| `artwork`   | String  | Optional artwork URL; shown as the station's thumbnail in the car list |
| `isLive`    | Boolean | Optional; default `true`                                               |

#### `setCurrentAutomotiveStation(station)`

Marks which station is currently playing (same object shape as above, or `null`). The car uses it for the "Resume last station" shortcut and the now-playing screen. Call it whenever you switch stations.

```javascript
const stations = [
  { id: 'rp', title: 'Radio Paradise', subtitle: 'Eclectic Rock', streamUrl: 'https://stream.radioparadise.com/aac-320', artwork: 'https://example.com/rp.png' },
  { id: 'gs', title: 'Groove Salad', subtitle: 'Ambient Beats', streamUrl: 'http://ice1.somafm.com/groovesalad-128-mp3' }
]

audioStream.setAutomotiveStations(stations)
audioStream.setCurrentAutomotiveStation(stations[0])

// When the driver taps a station in the car, the module starts it natively
// and fires this so you can sync your phone UI:
audioStream.addEventListener('automotivestationselected', (e) => {
  const key = e.station.id
  // update your UI to reflect `key`
})
```

Each station's `artwork` URL is shown as its leading thumbnail in the car's browse list (Android Auto and CarPlay), so apps that already register `artwork` per station get the photo automatically — no extra code. The car downloads the remote image itself; on CarPlay the module also caches it so re-registering the list doesn't re-download.

Both methods are cross-platform (Android Auto + CarPlay). On builds without car support they are simply absent, so feature-detect with `typeof audioStream.setAutomotiveStations === 'function'`.

### Properties

| Property                      | Type                | Description                                                                                         |
| :---------------------------- | :------------------ | :-------------------------------------------------------------------------------------------------- |
| `playing`                     | Boolean (read-only) | `true` if audio is currently playing                                                                |
| `allowCrossProtocolRedirects` | Boolean (Android)   | Follow cross-protocol redirects (HTTPS↔HTTP). Default `true`. Set before `start()`. See note below. |

#### Transport security note (`allowCrossProtocolRedirects`)

Many radio CDNs answer an `https://` entry URL with a redirect to an `http://` edge node (for example radiojar: `https://stream.radiojar.com/…` → `http://nNN.radiojar.com/…?rj-tok=…`). ExoPlayer rejects such cross-protocol redirects by default and fails with `Response code: 302`, so on Android the module follows them — matching what iOS/AVPlayer and browsers already do.

The tradeoff: with this enabled (the default), an `https://` URL **may be downgraded to `http://`** by a redirect, so it no longer guarantees encrypted transport. The data here is public radio audio, so the risk is low, but if you only stream from CDNs that keep HTTPS end-to-end and want to forbid downgrades, set it off before playback:

```javascript
audioStream.allowCrossProtocolRedirects = false // Android only; iOS/AVPlayer is unaffected
```

This is Android-only; on iOS it is a no-op (AVPlayer follows these redirects natively).

### Events

#### `state`

Fires on playback state changes.

| Property | Type   | Values                                               |
| :------- | :----- | :--------------------------------------------------- |
| `state`  | String | `playing`, `buffering`, `paused`, `stopped`, `error` |

#### `metadata`

Fires when the engine extracts new metadata from the stream. This event fires regardless of the `autoUpdateMetadata` setting, so your app code always receives it.

| Property  | Type   | Description                                        |
| :-------- | :----- | :------------------------------------------------- |
| `title`   | String | Parsed track title                                 |
| `artist`  | String | Parsed artist name                                 |
| `artwork` | String | Artwork URL (when available)                       |
| `raw`     | Object | Every tag found in the stream, for deep inspection |

#### `error`

Fires on playback errors.

| Property  | Type   | Description       |
| :-------- | :----- | :---------------- |
| `message` | String | Error description |

On Android, transient connection failures are retried up to **5 times** with a **3-second delay** before this event fires. Unplayable responses, such as an offline station's HTML page or any non-audio content, fail immediately with a single event (the same as iOS).

#### `remotecontrol`

Fires when the user interacts with system media controls (lock screen, notification, Control Center).

| Property  | Type   | Description                             |
| :-------- | :----- | :-------------------------------------- |
| `action`  | String | `PLAY`, `PAUSE`, `STOP`, `NEXT`, `PREV` |
| `subtype` | Number | Numeric constant (see table below)      |

The engine handles `PLAY`, `PAUSE`, and `STOP` on its own. `NEXT` and `PREV` fire the event so your app can decide what to do. The module does not know your playlist.

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

#### `automotivestationselected`

Fires when the driver taps a station in the Android Auto / CarPlay browse list. The module starts that station **natively** before firing, so your handler only needs to sync the phone UI — don't call `setStream()`/`start()` again.

| Property  | Type   | Description                                                         |
| :-------- | :----- | :------------------------------------------------------------------ |
| `station` | Object | The selected station object (same shape you registered, incl. `id`) |
| `source`  | String | Which car surface triggered it (e.g. `androidAuto`)                 |

Requires registering stations first with [`setAutomotiveStations()`](#setautomotivestationsstations).

## Guides

### Updating your app UI from stream metadata

The lock screen, notification, and Control Center update automatically when the stream sends new metadata. You do not need any extra code for that.

Your app UI is separate. To keep your own labels and images in sync, listen for the `metadata` event:

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

System controls update automatically. Your in-app UI updates through the event.

### Handling remote controls (playlist rotation)

Play, pause, and stop are handled automatically by the engine. You only need to handle `NEXT` and `PREV`:

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

Some streams send messy metadata with extra tags, odd formatting, or raw codes. Use `setMetadataRules()` to define regex cleanup rules that the module applies automatically, without disabling auto-update or writing manual event handling:

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
    { match: '\\s*\\(\\d{4}\\)(?:\\s*-\\s*.+)?$', replace: '' }  // Remove trailing (YYYY) or (YYYY) - ...
  ]
})
```

Rules are applied after the module's built-in parsing (ICY split, "Artist - Title" split) and before updating the lock screen. The `metadata` event fires with the cleaned values. Call `setMetadataRules(null)` to clear all rules.

If regex rules are not enough, you can still take full manual control:

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

On Android, transient connection failures are retried automatically (5 attempts, 3 seconds apart) before the error event fires. Content that cannot be played, such as an offline station's HTML page, fails immediately instead of retrying.

### Platform-specific behavior

#### iOS

- Background audio requires `UIBackgroundModes: audio` in your plist (see [Installation](#installation))
- Lock screen controls appear in Control Center and on Apple Watch / CarPlay through MPRemoteCommandCenter
- Audio session uses the Playback category, so audio continues when the screen locks or the app backgrounds
- If a phone call interrupts playback, audio resumes when the call ends (only if it was playing before the interruption)

#### Android

- Background playback runs inside a Foreground Service with a persistent media notification
- The notification has compact (lock screen), expanded (drawer), and system media player (Quick Settings) views
- Uses MediaSession for Bluetooth devices and the system output switcher
- Android Auto support via MediaBrowserService: the module registers as a media source so Android Auto can discover, display, and control the stream (see [Android Auto](#android-auto))
- CarPlay support via Titanium scene delegates plus MediaPlayer integration: once the entitlement and scene manifest are in place, CarPlay can show the active stream with metadata, artwork, and controls (see [CarPlay](#carplay))
- If the connection drops, the engine retries 5 times with a 3-second delay before reporting an error; unplayable content (such as an offline station page) is reported immediately
- All permissions are declared in the module's `timodule.xml` and merged automatically. No manual manifest editing needed

## Android Auto

The module registers as a `MediaBrowserService` so Android Auto discovers it as a media source automatically. There are two levels of integration:

- **Now playing (zero code):** while a stream is playing, the car shows its title, artist, artwork, and playback controls automatically.
- **Browsable station list:** to show a list of stations the driver can pick from — including when the app is opened cold from the car — register them with [`setAutomotiveStations()`](#setautomotivestationsstations) and mark the active one with [`setCurrentAutomotiveStation()`](#setcurrentautomotivestationstation). Handle taps via the [`automotivestationselected`](#automotivestationselected) event. See `example/app.js` for a complete implementation.

For setup details, testing with Desktop Head Unit, and troubleshooting, see the [Android-specific documentation](android/README.md#android-auto).

## CarPlay

The module uses MediaPlayer integration that CarPlay reads from, including `MPNowPlayingSession` on iOS 16+ and the shared Now Playing centers on older versions. In Titanium apps, CarPlay also requires the proper entitlement and `UIApplicationSceneManifest` entries in `tiapp.xml`.

CarPlay shows the stations registered with [`setAutomotiveStations()`](#setautomotivestationsstations) as a list (each with its `artwork` thumbnail), and stays on that list rather than pushing a separate Now Playing screen. A **Play/Pause row** at the top is the on-screen transport control; the active station is marked with a now-playing indicator and an "On Air" subtitle.

For the step-by-step entitlement setup, testing with CarPlay Simulator, and troubleshooting, see the [iOS-specific documentation](ios/README.md#carplay).

### Car integration comparison

| Feature               | Bluetooth (AVRCP)            | Android Auto | CarPlay                    |
| :-------------------- | :--------------------------- | :----------- | :------------------------- |
| Title / Artist        | Yes (AVRCP 1.3+)             | Always       | Always                     |
| Artwork               | Depends on AVRCP version     | Always       | Always                     |
| App icon on head unit | No                           | Yes          | Yes                        |
| Playback controls     | Basic (play/pause/next/prev) | Full         | Full                       |
| Content browsing      | No                           | Yes          | No (Now Playing only)      |
| Setup required        | None                         | None         | Apple entitlement approval |

### Artwork on car stereos

Android Auto uses its own display protocol and always shows artwork when available. Plain Bluetooth uses the AVRCP profile, where artwork support depends on the car stereo hardware.

The module scales artwork to 512x512 before passing it to the MediaSession, which keeps bitmaps within the Binder transaction limits that the Bluetooth AVRCP stack requires. Without this, large artwork images are silently dropped and never reach the car display.

If your car stereo supports AVRCP cover art (most modern stereos do), artwork should appear over Bluetooth. If it does not, the stereo likely uses an older AVRCP version (1.3 or below) that only transmits title and artist.

## How metadata extraction works

Both platforms parse metadata through multiple layers so they can handle different stream formats:

| Format                 | Source                            | Example                          |
| :--------------------- | :-------------------------------- | :------------------------------- |
| **ICY headers**        | Shoutcast/Icecast `StreamTitle`   | `StreamTitle='Artist - Song';`   |
| **ID3 text frames**    | `TIT2` (title), `TPE1` (artist)   | Standard MP3 metadata            |
| **ID3 comment frames** | `COMM` field with embedded data   | Global Player / Heart Radio      |
| **Embedded JSON**      | JSON inside ID3 frames            | `{"title":"...","artist":"..."}` |
| **Stream URL artwork** | ICY URL ending in image extension | `http://...cover.jpg`            |
| **Embedded artwork**   | Binary image data in metadata     | APIC frames, CommonMetadata      |

When a stream sends `Artist - Title` as a single string, which is common with ICY, the module splits it automatically. The `raw` property in the `metadata` event gives you every tag the parser found, which helps when debugging non-standard formats.

## Technical implementation

| Feature             | Android                     | iOS                                         |
| :------------------ | :-------------------------- | :------------------------------------------ |
| **Engine**          | Media3 ExoPlayer (1.5+)     | AVFoundation (AVPlayer)                     |
| **Background**      | Foreground Service          | AVAudioSession (Playback)                   |
| **System controls** | MediaSessionCompat          | MPRemoteCommandCenter + MPNowPlayingSession |
| **Metadata**        | ID3 / ICY / Deep JSON       | TimedMetadata / CommonMetadata              |
| **Audio focus**     | AudioManager + MediaSession | AVAudioSession interruption handling        |
| **Reconnect**       | 5 retries, 3s delay         | 5 retries, 3s delay                         |

## License

MIT License. Copyright (c) 2026 César Estrada ([macCesar](https://github.com/macCesar))
