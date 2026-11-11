# ti.audiostream - Android

Platform-specific details for the Android implementation of `ti.audiostream`.

For the full API reference, see the [main README](../README.md).

## Build requirements

Use Titanium SDK 13.4.1.GA+ and Android compileSdk 36+. The minimum device version is API 24. This build uses Media3 1.11.1 and Guava 33.8.0-android. Upgrade older Titanium apps before installing it.

## Android-specific behavior

### Background playback

Audio runs inside a Foreground Service with a persistent media notification. The notification has three views:

- Compact - lock screen
- Expanded - notification drawer
- System media player - Quick Settings panel

Start playback from a visible activity or a supported system media control. Android can reject a new foreground service started from the background. If a restart after `hardStop()` is rejected, handle the `error` event and let the user start again from the app. [Android foreground service rules](https://developer.android.com/develop/background-work/services/fgs/launch)

### MediaSession

The module creates a `MediaSession` that exposes playback state and metadata to:

- Bluetooth devices (AVRCP)
- Android Auto head units
- The system output switcher (media routing)

### Station transitions

When you select a source, the module stops the previous audio and reports `buffering` while it loads the new one. If you pause or stop while the module is resolving the URL, the response leaves playback in the state you requested. When an external controller prepares a station by ID, the module selects it and clears the old item without taking audio focus. Play then loads the selected station.

Media3 opens audio and HLS URLs with recognized suffixes directly. The module resolves `.pls`, `.m3u` and extensionless HTTP URLs, including relative playlist entries and mixed-case MIME types. It can cancel a playlist request without cancelling the artwork download.

The initial connection and an in-app station change show a foreground notification with Pause while the source loads. The SystemUI media card is linked when native audio starts. Browsers can read buffering state and cancel loading. Explicit SystemUI resume or play also establishes transport control immediately. Stopping playback or selecting a station in the app retires the current card so a delayed Stop from it cannot cancel the new load.

If Android temporarily takes audio focus while a source is loading, the module reports paused. It holds the prepared item until focus returns, then resumes if playback is still requested. A manual pause, a stop or permanent loss of focus cancels the resume. The module uses `isPlaying` to confirm playback after Media3 reaches READY.

### Auto-retry on stream failure

For retryable transport failures, the engine retries automatically: 5 attempts with a 3-second delay between each. Player failures can emit `error` before a retry and then return to `buffering`. Follow `state` to distinguish recovery from a terminal failure. Missing resources
(404), invalid certificates and unsupported content are terminal. Pause, stop
and station changes cancel obsolete retries.

### Audio focus handling

| Scenario                                               | Behavior                                                          |
| :----------------------------------------------------- | :---------------------------------------------------------------- |
| Transient loss with permission to duck | Volume ducks to 20% |
| Transient loss without ducking | Playback pauses. It can resume on focus gain while playback is still requested. |
| Permanent loss | Playback pauses and requires a new playback request. |
| Manual pause or stop during an interruption | The manual command cancels automatic resume. |

Android exposes the focus change via [`audiofocuschange`](../README.md#audiofocuschange-android).

### Permissions

The module declares these permissions in `timodule.xml`. Titanium merges them into the app manifest during the build:

- `INTERNET` - stream access
- `WAKE_LOCK` - prevents CPU sleep during playback
- `FOREGROUND_SERVICE` - keeps audio alive in the background
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK` - Android 14+ foreground service type

## Android Auto

The module supplies Android Auto discovery and transport integration:

- `MediaBrowserServiceCompat` implementation with `onGetRoot` / `onLoadChildren`
- `automotive_app_desc.xml` resource descriptor
- `meta-data` declaration and `intent-filter` in `timodule.xml`
- Session token binding via `setSessionToken`

For browsing before playback, register a station catalog with
`setAutomotiveStations()` and update `setCurrentAutomotiveStation()` on selection.
The catalog also provides native next/previous when no JavaScript listener is active.
See the [automotive API](../README.md#setautomotivestationsstations).

### What appears on the head unit

When connected to an Android Auto head unit, the car display shows:

- App icon
- Stream title and artist
- Artwork when supplied. The receiver can choose between the embedded bitmap and the cached URI.
- Transport controls: play, pause, stop, next, previous

### Handling controls from Android Auto

The `remotecontrol` event fires the same way from Android Auto as it does from the lock screen or notification. Play, pause, and stop are handled automatically. If you register a `remotecontrol` listener, handle `NEXT` and `PREV` there to switch stations:

```javascript
const audioStream = require('ti.audiostream')

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
  // Works from lock screen, notification, Bluetooth, AND Android Auto
  if (e.action === 'NEXT') {
    loadStation((currentIndex + 1) % STREAMS.length)
  }
  if (e.action === 'PREV') {
    loadStation((currentIndex - 1 + STREAMS.length) % STREAMS.length)
  }
})

loadStation(0)
```

### Bluetooth vs Android Auto

| Feature               | Bluetooth (AVRCP)            | Android Auto |
| :-------------------- | :--------------------------- | :----------- |
| Title / Artist        | Yes (AVRCP 1.3+)             | Always       |
| Artwork               | Depends on AVRCP version     | When provided |
| App icon on head unit | No                           | Yes          |
| Playback controls     | Basic (play/pause/next/prev) | Full         |
| Content browsing      | No                           | Yes          |

### Artwork notes

- Artwork is scaled to 512x512 for MediaSession metadata to stay within Binder IPC transaction limits.
- The module limits network artwork to 8 MiB and decodes it near 1024 pixels for the notification. It scales a separate copy to 512 pixels for MediaSession. Catalog and resume entries use local cached URIs with read grants. The FileProvider stays private.
- If artwork does not show over Bluetooth, the car stereo likely uses AVRCP 1.3 or below, which only transmits title and artist.

Registered catalog stations also support native next/previous and voice search without a live JavaScript handler. Search selects only registered stations.

## Testing

### Sideloaded apps (not from Play Store)

Android Auto hides apps that were not installed from Google Play by default. To show your app during development:

1. Open the Android Auto app on your phone (or Settings > Apps > Android Auto)
2. Go to Settings > scroll to About or Version
3. Tap Version 10 times to enable Developer Mode
4. Tap the three-dot menu (top right) > Developer settings
5. Enable "Unknown sources" (in Spanish: "Mostrar las aplicaciones externas")

Without this, your app will not appear on the car head unit even if the module is correctly configured.

### Desktop Head Unit (DHU)

1. Install DHU: Android Studio > SDK Manager > SDK Tools > check "Android Auto Desktop Head Unit Emulator"
2. Enable developer mode on the phone, unlock it, and connect it by USB.
3. Start DHU 2.x with `./desktop-head-unit --usb`. If you use ADB tunneling, start the head unit server on the phone and follow Google's port forwarding steps. [Official DHU setup](https://developer.android.com/training/cars/testing/dhu)
4. Open your app from the DHU's audio sources and exercise the station list and playback controls.

## Troubleshooting

### App does not appear in Android Auto

- Most common cause: "Unknown sources" is not enabled in Android Auto Developer settings (see Testing section above)
- Verify you are using a module version that includes the MediaBrowserService changes
- Rebuild your app with the latest module to ensure the manifest entries are merged
- Check that Android Auto is installed and updated on the phone

### No artwork on Android Auto

- Confirm that `setStream()` or `setMetadata()` includes an `artwork` URL
- The URL must be reachable from the device (test it in a browser)

### Controls do not respond

- If your app listens for `remotecontrol`, handle `NEXT` and `PREV` in that listener. Without a listener, the module uses the registered automotive catalog to choose the adjacent station.
- Play, pause, and stop are handled automatically.
