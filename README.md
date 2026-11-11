# ti.audiostream

Audio streaming module for Titanium SDK. It handles background playback, system media controls, and live metadata on Android and iOS through one API.

<div align="center">

![Platform](https://img.shields.io/badge/platform-Android%20%7C%20iOS-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Android Titanium SDK](https://img.shields.io/badge/Android%20Titanium%20SDK-13.4.1.GA%2B-orange)
![iOS Titanium SDK](https://img.shields.io/badge/iOS%20Titanium%20SDK-13.1.1.GA%2B-orange)
</div>

## Playback engine

`Ti.Media.AudioPlayer` handles simple playback. For a radio app, you would usually add platform code for lock screen controls, metadata, background playback, and audio focus.

`ti.audiostream` uses Media3 ExoPlayer on Android and AVPlayer on iOS behind a single JavaScript API. The module parses ICY/ID3 metadata, updates artwork and handles interruption and resume requests. The platform guides describe differences in system controls and automotive behavior.

## Features

- Same JavaScript API for Android (Media3 ExoPlayer) and iOS (AVPlayer)
- Plays direct MP3/AAC and HLS (`.m3u8`) and resolves `.pls`/`.m3u` playlists automatically. Use SHOUTcast and Icecast URLs as supplied, including bare-root URLs such as `http://host:8000` and directory mounts.
- Metadata parsing from ICY headers, ID3 tags, and non-standard payloads (for example embedded JSON used by some stations)
- Artwork updates for lock screen and notification/control surfaces, with automatic app icon fallback when no artwork is available
- Audio focus and interruption handling (calls, Siri, other apps) with resume logic that respects manual pauses
- Background playback support via Foreground Service (Android) and AVAudioSession (iOS)
- System media controls support: lock screen, notification shade, Control Center, CarPlay, Apple Watch, Android Auto
- Optional metadata auto-update control when you want to keep station branding instead of live track metadata

## Requirements

|              | Version          |
| :----------- | :--------------- |
| Titanium SDK | Android: 13.4.1.GA+; iOS: 13.1.1.GA+ |
| Android      | API 24+ (Nougat) |
| iOS          | 15.0+            |

Media3 1.11.1 requires Android builds to use compileSdk 36+. The module still runs on devices with Android API 24 or later. If your Android app uses an older Titanium SDK, upgrade to 13.4.1.GA or later. The Android module manifest enforces that minimum.

### Mac Catalyst note

The iOS module includes Mac Catalyst support (`mac: true` in manifest). Mac Catalyst apps are supported starting with Titanium SDK `13.1.1.GA`, the minimum declared by the prebuilt package. Building the module from source with `mac: true` requires the CLI fix merged in February 2026 and included in Titanium SDK `13.2.0.GA+`. [Titanium SDK fix](https://github.com/tidev/titanium-sdk/pull/14391)

## Installation

### 1. Install 2.0.0 and declare it in `tiapp.xml`

Extract the ZIP for each platform you target at the root of your Titanium app. Each archive contains the `modules/` directory structure Titanium expects. Then declare the version in your app. [Android ZIP](android/dist/ti.audiostream-android-2.0.0.zip) · [iOS ZIP](ios/dist/ti.audiostream-iphone-2.0.0.zip)

```xml
<modules>
  <module version="2.0.0">ti.audiostream</module>
</modules>
```

### 2. iOS: enable background audio

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
- `WAKE_LOCK` - acquired by Media3 network wake mode during playback
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
  // artwork: 'https://example.com/logo.png', // Optional. Use your station's artwork URL.
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

### Run the example

Install the module in a Titanium Classic app and copy the shared sample into `Resources/app.js`. Both ZIPs include a copy under the module's `example/` directory. On iOS, enable the background audio mode above. Open the app and press Play or pick a station. While a stream is loading, the same button lets you pause it. The sample logs playback states and retry errors and keeps its selection in sync with the automotive catalog. Enable the CarPlay entitlement and scene setup if you want to test the car interface. [Sample source](example/app.js) · [CarPlay setup](ios/README.md#carplay)

## API reference

### Methods

#### `setStream(options)`

Configures the audio source. For a user-selected station, call `setStream()` and `start()` together. Android stops the previous source before announcing the new load. While paused, selecting a source preserves the pause until you request playback.

| Parameter            | Type          | Required | Description                                                                                                                  |
| :------------------- | :------------ | :------- | :--------------------------------------------------------------------------------------------------------------------------- |
| `url`                | String        | Yes      | Direct audio stream, HLS (`.m3u8`), or a `.pls`/`.m3u` playlist (resolved automatically). SHOUTcast/Icecast URLs work as-is. |
| `isLive`             | Boolean       | No       | Hides seek bar and shows live indicator on system controls. Default: `true`.                                                 |
| `autoUpdateMetadata` | Boolean       | No       | Update system controls from stream metadata. Defaults to `true` on each call to `setStream()`.                                |
| `title`              | String        | No       | Initial title for lock screen / notification                                                                                 |
| `artist`             | String        | No       | Initial artist for lock screen / notification                                                                                |
| `artwork`            | String / null | No       | Initial artwork URL for system controls. Pass `null` to clear it.                                                            |
| `metadataRules`      | Object / null | No       | Regex cleanup rules (see [`setMetadataRules()`](#setmetadatarulesrules)). Omit to keep existing rules, `null` to clear.      |
| `force`              | Boolean       | No       | iOS only. Rebuild the player item even if the URL is unchanged. Defaults to `false`.                                           |

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

Starts or resumes playback. `play()` is an alias of `start()` on both platforms. The module requests audio focus and enables system controls automatically. Calling either method again while already playing keeps the active stream. On Android, start a new playback session from a visible app or a supported system media control. [Android foreground service rules](https://developer.android.com/develop/background-work/services/fgs/launch)

#### `pause()`

Pauses playback and cancels automatic reconnect/resume authorization, including during an interruption. The notification stays visible so the user can resume from the lock screen. A new explicit playback command is required after a manual pause.

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

Manually sets lock screen and notification metadata without changing the stream. Omitted fields are preserved. Title and artist publish immediately, independently of artwork downloading. Invalid or failed artwork uses the app icon fallback.

| Parameter | Type          | Description                                           |
| :-------- | :------------ | :---------------------------------------------------- |
| `title`   | String        | Track or station title                                |
| `artist`  | String        | Artist or description                                 |
| `artwork` | String / null | Artwork URL, `null` to clear, or omit to keep current |

Artwork updates follow these rules:
- Set `artwork` to `null` or `""`: clears the artwork
- Set `artwork` to a URL: loads and displays the new image
- Omit `artwork`: keeps whatever artwork is currently showing

Some Android vendor lock screens need an explicit image replacement:
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
- `false` - keep the station or manual metadata on system controls while the `metadata` event continues to deliver track data

```javascript
// Switch an already configured stream to manual metadata.
audioStream.setAutoUpdateMetadata(false)
```

```javascript
// Keep station branding on the lock screen when configuring a source.
audioStream.setStream({
  url: 'https://stream.radioparadise.com/aac-320',
  title: 'Radio Paradise',
  autoUpdateMetadata: false
})
audioStream.start()
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

Rules are applied in array order. `setMetadata()` (manual override) is not affected by rules. You can also pass `metadataRules` directly in [`setStream()`](#setstreamoptions).

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

Registers the stations that Android Auto and CarPlay show when you open the app on the head unit. Without a catalog, the head unit can show the current "now playing" item during playback. Opening the app from the head unit with no active stream shows no stations. The module saves the list natively so it survives app termination.

Pass an array of station objects, or `null` to clear:

| Field       | Type    | Description                                                            |
| :---------- | :------ | :--------------------------------------------------------------------- |
| `id`        | String  | Stable, unique ID returned in `automotivestationselected`               |
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

Android Auto and CarPlay use each station's `artwork` URL for the thumbnail at the start of its row. An app that already supplies `artwork` for each station needs no extra thumbnail code. The module downloads and caches the image, then reuses the local copy when it sees the same URL again. Android gives media consumers read access to catalog, resume and playback artwork through local `content://` URIs. The FileProvider stays private. CarPlay checks that a download still belongs to the row before displaying it.

Both methods are cross-platform (Android Auto + CarPlay). On builds without car support they are simply absent, so feature-detect with `typeof audioStream.setAutomotiveStations === 'function'`.

### Properties

| Property                      | Type                | Description                                                                                         |
| :---------------------------- | :------------------ | :-------------------------------------------------------------------------------------------------- |
| `playing`                     | Boolean (read-only) | `true` if audio is currently playing                                                                |
| `allowCrossProtocolRedirects` | Boolean (Android)   | Follow cross-protocol redirects (HTTPS↔HTTP). Default `true`. Set before the playback service creates its player. See note below. |

#### Transport security note (`allowCrossProtocolRedirects`)

Many radio CDNs redirect an `https://` entry URL to an `http://` edge node (for example radiojar, `https://stream.radiojar.com/…` redirects to `http://nNN.radiojar.com/…?rj-tok=…`). ExoPlayer rejects these cross-protocol redirects by default with `Response code: 302`. The Android module enables them to match iOS/AVPlayer and browser behavior.

The tradeoff: with this enabled (the default), an `https://` URL may be downgraded to `http://` by a redirect, so it no longer guarantees encrypted transport. The data here is public radio audio, so the risk is low, but if you only stream from CDNs that keep HTTPS end-to-end and want to forbid downgrades, set it off before the first `setStream()` or `start()`. It is read when the Android player is created; changing it on an existing player takes effect after `hardStop()` recreates the service:

```javascript
audioStream.allowCrossProtocolRedirects = false // Android only; iOS/AVPlayer is unaffected
```

This is Android-only; on iOS it is a no-op (AVPlayer follows these redirects natively).

### Events

#### `state`

Fires on playback state changes.

`buffering` covers source resolution and native player loading. Use `playing` to show confirmed playback. Repeated identical states are deduplicated, and callbacks from retired sources are discarded. A finite stream reports `stopped` at the end. Calling `start()` again restarts the item.

| Property | Type   | Values                                               |
| :------- | :----- | :--------------------------------------------------- |
| `state`  | String | `playing`, `buffering`, `paused`, `stopped`, `error` |

#### `metadata`

Fires when the engine extracts new metadata from the stream. This event fires regardless of the `autoUpdateMetadata` setting, so your app code always receives it.

| Property  | Type   | Description                                        |
| :-------- | :----- | :------------------------------------------------- |
| `title`   | String | Parsed track title                                 |
| `artist`  | String | Parsed artist name                                 |
| `artwork` | String / null | Artwork URL when available                  |
| `raw`     | Object | Parsed source tags when available                  |

#### `error`

Fires on playback errors.

| Property  | Type   | Description       |
| :-------- | :----- | :---------------- |
| `message` | String | Error description |

Temporary transport failures are retried up to 5 times with a 3-second delay. DNS/connectivity errors, timeouts and temporary HTTP failures such as 429/503 are retryable; missing resources (404), invalid certificates and unsupported content are terminal. Pausing, stopping or changing stations cancels obsolete retries. Both Android and iOS can emit `error` for a player failure that will be retried, before returning to `buffering`. An error event alone does not mean that retries have finished; follow the `state` event to track recovery.

#### `remotecontrol`

Fires when the user interacts with system media controls (lock screen, notification, Control Center).

| Property  | Type   | Description                             |
| :-------- | :----- | :-------------------------------------- |
| `action`  | String | `PLAY`, `PAUSE`, `STOP`, `PLAY_PAUSE`, `NEXT`, `PREV` |
| `subtype` | Number | Numeric constant (see table below)      |

The engine handles `PLAY`, `PAUSE`, and `STOP` on its own. `NEXT` and `PREV` fire the event so your app can decide what to do. Without a JavaScript listener, the native automotive catalog handles adjacent stations, including when JavaScript is not running.

Transport constants:

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

Fires when the driver selects a station from Android Auto or CarPlay. The module requests playback natively. Use this handler to sync the phone's selection and the `state` event to show when playback begins. Calling `setStream()` or `start()` in this handler would issue another playback request.

| Property  | Type   | Description                                                         |
| :-------- | :----- | :------------------------------------------------------------------ |
| `station` | Object | The selected station object (same shape you registered, incl. `id`) |
| `source`  | String | Car surface that triggered it: `androidauto` or `carplay`                 |

Requires registering stations first with [`setAutomotiveStations()`](#setautomotivestationsstations).

#### `audiofocuschange` (Android)

Fires when Android notifies the service of an audio focus change. Use the `state` event to update the playback UI.

| Property | Type | Description |
| :-- | :-- | :-- |
| `focusChange` | Number | One of `AUDIOFOCUS_GAIN`, `AUDIOFOCUS_LOSS`, `AUDIOFOCUS_LOSS_TRANSIENT`, or `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`. |
| `focused` | Boolean | `true` for `AUDIOFOCUS_GAIN`. |

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

### Showing loading state

Call `setStream()` and `start()` consecutively when the user selects a station. No timer is required between them. The `buffering` event covers URL resolution and native loading; `playing` confirms playback. The read-only `playing` property is false during loading, so use state events if your Play/Pause button must also cancel a pending start.

A manual `pause()` or `stop()` cancels pending retries and interruption resume. After either command, playback needs an explicit request. When a finite item ends, the module reports `stopped`; `start()` reopens it.

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

A catalog URL can stop serving audio independently of the module. Check the HTTP
status and response body when a station fails. A successful playlist response also
needs reachable media entries; an HTML error page is not an audio stream.


```javascript
audioStream.addEventListener('error', (e) => {
  const msg = e.message || 'Stream unavailable'
  Ti.API.error('[AudioStream] ' + msg)
})

audioStream.addEventListener('state', (e) => {
  stateLabel.text = e.state.toUpperCase()
})
```

Temporary failures can emit `error` before the next retry. A later `buffering` or `playing` event updates the UI as the module recovers. See the [retry behavior](#error).

### Platform-specific behavior

#### iOS

- Background audio requires `UIBackgroundModes: audio` in your plist (see [Installation](#installation))
- Lock screen controls appear in Control Center and on Apple Watch / CarPlay through MPRemoteCommandCenter
- Audio session uses the Playback category, so audio continues when the screen locks or the app backgrounds
- After an interruption such as a phone call, playback resumes when the system permits it and the playback request is still active

#### Android

- Background playback runs inside a Foreground Service with a persistent media notification
- The Foreground Service keeps streaming even if Android tears down and relaunches your app's UI (a notification tap, the media output switcher, or an OS task kill spawn a fresh JavaScript runtime). On that new runtime, `playing` reflects the live service state instead of resetting to `false`, so on startup you can check `playing` and re-sync your UI to the station that is still on air. Persist the current station yourself (the module does not restore your app UI across the relaunch) and restore it when `playing` is `true`
- The notification has compact (lock screen), expanded (drawer), and system media player (Quick Settings) views
- Uses MediaSession for Bluetooth devices and the system output switcher
- Android Auto support via MediaBrowserService: the module registers as a media source so Android Auto can discover, display, and control the stream (see [Android Auto](#android-auto))
- All permissions are declared in the module's `timodule.xml` and merged automatically. No manual manifest editing needed

## Android Auto

The module registers as a `MediaBrowserService` so Android Auto discovers it as a media source automatically. There are two levels of integration:

- During playback, the car shows the title, artist, artwork and controls automatically.
- Register stations with [`setAutomotiveStations()`](#setautomotivestationsstations) so drivers can browse the list, including when they open the app from the car before playback starts. Mark the active station with [`setCurrentAutomotiveStation()`](#setcurrentautomotivestationstation) and use [`automotivestationselected`](#automotivestationselected) to sync the phone UI when the driver selects a station. See `example/app.js` for a complete implementation.

For setup details, testing with Desktop Head Unit, and troubleshooting, see the [Android-specific documentation](android/README.md#android-auto).

## CarPlay

The module uses MediaPlayer integration that CarPlay reads from, including `MPNowPlayingSession` on iOS 16+ and the shared Now Playing centers on older versions. In Titanium apps, CarPlay also requires the proper entitlement and `UIApplicationSceneManifest` entries in `tiapp.xml`.

CarPlay lists the stations registered with [`setAutomotiveStations()`](#setautomotivestationsstations), with an `artwork` thumbnail for each station that has one. Selecting a station keeps the list open. Use the Play/Pause row at the top to control playback. The active station has a now-playing indicator and an "On Air" subtitle.

You can translate the Play/Pause row label, the "On Air" subtitle and the empty-list text. See [Localization](#localization).

For the step-by-step entitlement setup, testing with CarPlay Simulator, and troubleshooting, see the [iOS-specific documentation](ios/README.md#carplay).

### Car integration comparison

| Feature               | Bluetooth (AVRCP)            | Android Auto | CarPlay                    |
| :-------------------- | :--------------------------- | :----------- | :------------------------- |
| Title / Artist        | Yes (AVRCP 1.3+)             | Always       | Always                     |
| Artwork               | Depends on AVRCP version     | When provided | When provided              |
| App icon on head unit | No                           | Yes          | Yes                        |
| Playback controls     | Basic (play/pause/next/prev) | Full         | Full                       |
| Content browsing      | No                           | Station list | Station list               |
| Setup required        | None                         | None         | Apple entitlement approval |

### Artwork on car stereos

On Android, the embedded MediaSession bitmap fits within 512 × 512 pixels to limit Binder transaction size. Authorized media consumers can read the separate cached image at up to 1024 pixels on its longest edge. Android Auto uses the media browser integration and the head unit chooses which representation to display. Over plain Bluetooth, the stereo's AVRCP support determines whether it can display artwork as well as title and artist. [Android artwork details](android/README.md#artwork-notes)

## Localization

The module uses your app's i18n strings for notification buttons, the Android notification channel, Android Auto lists, CarPlay rows and the fallback lock screen title. It uses each key you define and falls back to English for missing keys.

Add the keys to `app/i18n/<lang>/strings.xml` (Alloy) or `i18n/<lang>/strings.xml` (Classic):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<resources>
  <string name="ti_audiostream_play">Reproducir</string>
  <string name="ti_audiostream_pause">Pausar</string>
  <string name="ti_audiostream_next">Siguiente</string>
  <string name="ti_audiostream_previous">Anterior</string>
  <string name="ti_audiostream_live_stream">Transmisión en vivo</string>
  <string name="ti_audiostream_resume_last_station">Reanudar última estación</string>
  <string name="ti_audiostream_last_station">Última estación</string>
  <string name="ti_audiostream_channel_name">Reproducción de audio</string>
  <string name="ti_audiostream_channel_description">Controles de reproducción de audio</string>
  <string name="ti_audiostream_on_air">Al aire</string>
  <string name="ti_audiostream_empty_title">Sin opciones de reproducción</string>
  <string name="ti_audiostream_empty_subtitle">Abre la app en el iPhone para actualizar la reproducción.</string>
</resources>
```

### Keys

| Key                                  | Default                                       | Where it shows                                            | Platform |
| :----------------------------------- | :-------------------------------------------- | :-------------------------------------------------------- | :------- |
| `ti_audiostream_play`                | `Play`                                        | Notification button; CarPlay transport row                 | Both     |
| `ti_audiostream_pause`               | `Pause`                                       | Notification button; CarPlay transport row                 | Both     |
| `ti_audiostream_next`                | `Next`                                        | Notification button                                        | Android  |
| `ti_audiostream_previous`            | `Previous`                                    | Notification button                                        | Android  |
| `ti_audiostream_live_stream`         | `Live Stream`                                 | Fallback title for notification, lock screen and car list | Both     |
| `ti_audiostream_resume_last_station` | `Resume last station`                         | Android Auto resume item                                   | Android  |
| `ti_audiostream_last_station`        | `Last station`                                | Android Auto resume item subtitle                          | Android  |
| `ti_audiostream_channel_name`        | `Audio Streaming`                             | Notification channel name, in Android system settings      | Android  |
| `ti_audiostream_channel_description` | `Audio streaming playback controls`           | Notification channel description                           | Android  |
| `ti_audiostream_on_air`              | `On Air`                                      | Subtitle of the station currently playing in CarPlay       | iOS      |
| `ti_audiostream_empty_title`         | `No playback options`                         | CarPlay list when no stations are registered               | iOS      |
| `ti_audiostream_empty_subtitle`      | `Open the app on iPhone to refresh playback.` | Subtitle of that empty list                                | iOS      |

Keys you don't define keep the English default, so translating a subset is fine.

### Android: `<defaultLang>` is required for single-language apps

On Android, Titanium compiles `app/i18n/<lang>/` into `res/values-<lang>/`. The locale named by `<defaultLang>` (which defaults to `en`) becomes the default `res/values/`. A locale absent from the default configuration is dropped from the APK. This was verified in a compiled APK with Titanium SDK 13.3.0.

| Your app's i18n                         | Result on Android                                   |
| :-------------------------------------- | :--------------------------------------------------- |
| `en/` only                              | Works (`en` is the default)                        |
| `en/` + `es/`                           | English by default, Spanish on Spanish devices |
| `es/` only, no `<defaultLang>`          | Silently ignored. The module shows English.    |
| `es/` only + `<defaultLang>es</defaultLang>` | Spanish on every device                    |

If your app ships a single non-English language, add this to `tiapp.xml`:

```xml
<defaultLang>es</defaultLang>
```

Without it, the strings compile without a warning and the module shows English. iOS resolves its locale through `CFBundleDevelopmentRegion`.

## How metadata extraction works

Both platforms parse metadata through multiple layers so they can handle different stream formats:

| Format                 | Source                            | Example                          |
| :--------------------- | :-------------------------------- | :------------------------------- |
| ICY headers        | Shoutcast/Icecast `StreamTitle`   | `StreamTitle='Artist - Song';`   |
| ID3 text frames    | `TIT2` (title), `TPE1` (artist)   | Standard MP3 metadata            |
| ID3 comment frames | `COMM` field with embedded data   | Global Player / Heart Radio      |
| Embedded JSON      | JSON inside ID3 frames            | `{"title":"...","artist":"..."}` |
| Stream URL artwork | ICY URL ending in image extension | `http://...cover.jpg`            |
| Embedded artwork   | Binary image data in metadata     | APIC frames, CommonMetadata      |

When a stream sends `Artist - Title` as a single string, which is common with ICY, the module splits it automatically. The `raw` property in the `metadata` event includes parsed source tags when available.

## Technical implementation

| Feature             | Android                     | iOS                                         |
| :------------------ | :-------------------------- | :------------------------------------------ |
| Engine          | Media3 ExoPlayer 1.11.1     | AVFoundation (AVPlayer)                     |
| Background      | Foreground Service          | AVAudioSession (Playback)                   |
| System controls | MediaSessionCompat          | MPRemoteCommandCenter + MPNowPlayingSession |
| Metadata        | ID3 / ICY / Deep JSON       | TimedMetadata / CommonMetadata              |
| Audio focus     | AudioManager + MediaSession | AVAudioSession interruption handling        |
| Reconnect       | 5 retries, 3s delay         | 5 retries, 3s delay                         |

## Development verification

Durable regression commands and device-test instructions are in [tests/README.md](tests/README.md). See [second-pass results](tests/SEGUNDA_PASADA.md) for the recorded measurements, including runs that exceeded the latency budget and the remaining stress and hardware checks. These results do not establish a maximum startup time.

Detailed iOS binary diagnostics default to off (`TI_AUDIOSTREAM_DIAGNOSTICS=1` opts in at compile time and redacts URLs); Android debug/info logging follows Titanium's `TiConfig.LOGD`. JavaScript events remain enabled independently.

Native builds are checked with Titanium 13.4.1.GA. Physical vehicle, Bluetooth, long suspension and OEM artwork acceptance require their own checks; automated method tests do not certify these surfaces.

When packaging a release, use `example/app.js` as the shared source for the sample in both archives. The Titanium 13.4.1.GA Android module builder omits the example, so include it at `modules/android/ti.audiostream/<version>/example/app.js` in the distribution ZIP.

## License

MIT License. Copyright (c) 2026 César Estrada ([macCesar](https://github.com/macCesar))
