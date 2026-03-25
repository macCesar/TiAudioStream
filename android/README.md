# ti.audiostream - Android

Platform-specific details for the Android implementation of `ti.audiostream`.

For the full API reference, see the [main README](../README.md).

## Android-specific behavior

### Background playback

Audio runs inside a **Foreground Service** with a persistent media notification. The notification has three views:

- **Compact** - lock screen
- **Expanded** - notification drawer
- **System media player** - Quick Settings panel

### MediaSession

The module creates a `MediaSession` that exposes playback state and metadata to:

- Bluetooth devices (AVRCP)
- Android Auto head units
- The system output switcher (media routing)

### Auto-retry on stream failure

When a stream connection drops, the engine retries automatically: **5 attempts** with a **3-second delay** between each. The `error` event only fires after all retries are exhausted.

### Audio focus handling

| Scenario                                               | Behavior                                                          |
| :----------------------------------------------------- | :---------------------------------------------------------------- |
| Transient loss (notification sound, navigation prompt) | Volume ducks to 20%                                               |
| Full loss (phone call, another media app)              | Playback pauses                                                   |
| Focus regained                                         | Playback resumes (only if it was playing before the interruption) |

### Permissions

All permissions are declared in the module's `timodule.xml` and merged into your build automatically. No manual manifest editing needed:

- `INTERNET` - stream access
- `WAKE_LOCK` - prevents CPU sleep during playback
- `FOREGROUND_SERVICE` - keeps audio alive in the background
- `FOREGROUND_SERVICE_MEDIA_PLAYBACK` - Android 14+ foreground service type

## Android Auto

Android Auto works without any app-level setup. The module already includes:

- `MediaBrowserServiceCompat` implementation with `onGetRoot` / `onLoadChildren`
- `automotive_app_desc.xml` resource descriptor
- `meta-data` declaration and `intent-filter` in `timodule.xml`
- Session token binding via `setSessionToken`

No app-level configuration is required.

### What appears on the head unit

When connected to an Android Auto head unit, the car display shows:

- App icon
- Stream title and artist
- Artwork (scaled to 512x512)
- Transport controls: play, pause, stop, next, previous

### Handling controls from Android Auto

The `remotecontrol` event fires the same way from Android Auto as it does from the lock screen or notification. Play, pause, and stop are handled automatically. You handle `NEXT` and `PREV` to switch stations:

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
| Artwork               | Depends on AVRCP version     | Always       |
| App icon on head unit | No                           | Yes          |
| Playback controls     | Basic (play/pause/next/prev) | Full         |
| Content browsing      | No                           | Yes          |

### Artwork notes

- Artwork is scaled to **512x512** for MediaSession metadata to stay within Binder IPC transaction limits.
- The full-size bitmap remains on the phone notification.
- If artwork does not show over Bluetooth, the car stereo likely uses AVRCP 1.3 or below, which only transmits title and artist.

## Testing

### Sideloaded apps (not from Play Store)

Android Auto hides apps that were not installed from Google Play by default. To show your app during development:

1. Open the **Android Auto** app on your phone (or Settings > Apps > Android Auto)
2. Go to **Settings** > scroll to **About** or **Version**
3. Tap **Version** 10 times to enable Developer Mode
4. Tap the three-dot menu (top right) > **Developer settings**
5. Enable **"Unknown sources"** (in Spanish: "Mostrar las aplicaciones externas")

Without this, your app will not appear on the car head unit even if the module is correctly configured.

### Desktop Head Unit (DHU)

1. Install DHU: Android Studio > SDK Manager > SDK Tools > check "Android Auto Desktop Head Unit Emulator"
2. Enable developer mode on the phone (steps above)
3. Connect the phone via USB and launch the DHU from the command line
4. Your app should appear as an audio source on the DHU

## Troubleshooting

### App does not appear in Android Auto

- **Most common cause**: "Unknown sources" is not enabled in Android Auto Developer settings (see Testing section above)
- Verify you are using a module version that includes the MediaBrowserService changes
- Rebuild your app with the latest module to ensure the manifest entries are merged
- Check that Android Auto is installed and updated on the phone

### No artwork on Android Auto

- Confirm that `setStream()` or `setMetadata()` includes an `artwork` URL
- The URL must be reachable from the device (test it in a browser)

### Controls do not respond

- Make sure you have a `remotecontrol` event listener set up
- `NEXT` and `PREV` require your app code to handle them. The module only handles play, pause, and stop automatically.
