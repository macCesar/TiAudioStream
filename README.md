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

### Audio Focus (Android)
- Proper `AUDIOFOCUS_GAIN` request before playback
- Responds to `AUDIOFOCUS_LOSS` (pause when other apps play)
- Responds to `AUDIOFOCUS_LOSS_TRANSIENT` (pause for notifications)
- Responds to `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` (lower volume)
- Abandons focus on stop

### Media Controls
- Lock screen controls
- Notification with play/pause/next/prev buttons
- Bluetooth/headphone controls
- MediaSession integration

### Metadata
- Title and artist display
- Album artwork (local or remote URLs)
- Asynchronous artwork loading (no UI freeze)

## Requirements

- Titanium SDK 12.0.0+
- Android: API 24+ (Android 7.0+)
- iOS: 13.0+

## Installation

### Local Installation

Copy the module zip to your project root:

```bash
cp ti.audiostream-android-1.0.0.zip /path/to/your/project/
```

### Global Installation

**macOS:**
```bash
cp ti.audiostream-android-1.0.0.zip ~/Library/Application\ Support/Titanium/
```

**Linux:**
```bash
cp ti.audiostream-android-1.0.0.zip ~/.titanium/
```

**Windows:**
```bash
copy ti.audiostream-android-1.0.0.zip C:\ProgramData\Titanium\
```

### Register in tiapp.xml

```xml
<modules>
  <module platform="android">ti.audiostream</module>
  <module platform="iphone">ti.audiostream</module>
</modules>
```

## API Reference

### Methods

#### `setStream(options)`

Configure the audio stream URL.

```javascript
audioStream.setStream({
  url: 'https://stream.example.com/radio.mp3',
  isLive: true  // default: true (for radio streams)
});
```

| Parameter | Type    | Default  | Description                   |
| --------- | ------- | -------- | ----------------------------- |
| url       | String  | required | The stream URL                |
| isLive    | Boolean | true     | Whether this is a live stream |

#### `start()`

Start or resume playback. Requests audio focus automatically.

```javascript
audioStream.start();
```

#### `pause()`

Pause playback. Does NOT release audio focus.

```javascript
audioStream.pause();
```

#### `stop()`

Stop playback and release all resources. Abandons audio focus.

```javascript
audioStream.stop();
```

#### `setMetadata(options)`

Set metadata for lock screen and notification display.

```javascript
audioStream.setMetadata({
  title: 'Morning Show',
  artist: 'Radio Station',
  artwork: 'https://example.com/artwork.jpg'  // or '/images/local.png' for local
});
```

| Parameter | Type   | Default | Description                                      |
| --------- | ------ | ------- | ------------------------------------------------ |
| title     | String | ''      | Track/program title                              |
| artist    | String | ''      | Artist/station name                              |
| artwork   | String | null    | URL (http/https) or local path (auto-detected)   |

### Properties

#### `playing` (read-only)

Returns the current playback state.

```javascript
if (audioStream.playing) {
  console.log('Audio is playing');
}
```

### Events

#### `state`

Fired when playback state changes.

```javascript
audioStream.addEventListener('state', function(e) {
  console.log('State:', e.state);
  // e.state: 'buffering', 'playing', 'paused', 'stopped', 'error'
});
```

| State     | Description                       |
| --------- | --------------------------------- |
| buffering | Loading/buffering audio data      |
| playing   | Audio is playing                  |
| paused    | Audio is paused                   |
| stopped   | Audio stopped, resources released |
| error     | An error occurred                 |

#### `error`

Fired when an error occurs.

```javascript
audioStream.addEventListener('error', function(e) {
  console.error('Error:', e.message);
});
```

#### `audiofocuschange`

Fired when audio focus changes (Android only).

```javascript
audioStream.addEventListener('audiofocuschange', function(e) {
  console.log('Focus change:', e.focusChange);
  console.log('Has focus:', e.focused);
});
```

| Property    | Type    | Description                 |
| ----------- | ------- | --------------------------- |
| focusChange | Number  | Audio focus constant        |
| focused     | Boolean | true if app has audio focus |

#### `remotecontrol`

Fired when user interacts with lock screen/notification controls.

```javascript
audioStream.addEventListener('remotecontrol', function(e) {
  switch (e.subtype) {
    case audioStream.REMOTE_CONTROL_PLAY:
      // User pressed play
      break;
    case audioStream.REMOTE_CONTROL_PAUSE:
      // User pressed pause
      break;
    case audioStream.REMOTE_CONTROL_NEXT:
      // User pressed next
      break;
    case audioStream.REMOTE_CONTROL_PREV:
      // User pressed previous
      break;
  }
});
```

### Constants

#### Remote Control
- `REMOTE_CONTROL_PLAY` (100)
- `REMOTE_CONTROL_PAUSE` (101)
- `REMOTE_CONTROL_STOP` (102)
- `REMOTE_CONTROL_PLAY_PAUSE` (103)
- `REMOTE_CONTROL_NEXT` (104)
- `REMOTE_CONTROL_PREV` (105)

#### Audio Focus (Android)
- `AUDIOFOCUS_GAIN`
- `AUDIOFOCUS_LOSS`
- `AUDIOFOCUS_LOSS_TRANSIENT`
- `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`

## Complete Example

```javascript
const audioStream = require('ti.audiostream');

// Configure stream
audioStream.setStream({
  url: 'https://stream.example.com/radio.mp3',
  isLive: true
});

// Set metadata
audioStream.setMetadata({
  title: 'Live Radio',
  artist: 'My Station',
  artwork: 'https://example.com/logo.png'
});

// Listen for state changes
audioStream.addEventListener('state', function(e) {
  Ti.API.info('[AudioStream] State: ' + e.state);

  switch (e.state) {
    case 'buffering':
      // Show loading indicator
      break;
    case 'playing':
      // Update UI to playing state
      break;
    case 'paused':
      // Update UI to paused state
      break;
    case 'error':
      // Handle error
      break;
  }
});

// Listen for remote control events
audioStream.addEventListener('remotecontrol', function(e) {
  Ti.API.info('[AudioStream] Remote control: ' + e.subtype);

  if (e.subtype === audioStream.REMOTE_CONTROL_PLAY) {
    audioStream.start();
  } else if (e.subtype === audioStream.REMOTE_CONTROL_PAUSE) {
    audioStream.pause();
  }
});

// Listen for audio focus changes
audioStream.addEventListener('audiofocuschange', function(e) {
  Ti.API.info('[AudioStream] Audio focus: ' + (e.focused ? 'gained' : 'lost'));
});

// Start playback
audioStream.start();

// Later: pause
// audioStream.pause();

// Later: stop and release resources
// audioStream.stop();
```

## Android Configuration

The module automatically configures:

### Permissions (in timodule.xml)
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
```

### Foreground Service
- Type: `mediaPlayback`
- Notification channel: `audiostream_media`
- Continues playing when app is in background

## iOS Configuration

Add to your `tiapp.xml`:

```xml
<ios>
  <plist>
    <dict>
      <key>UIBackgroundModes</key>
      <array>
        <string>audio</string>
      </array>
    </dict>
  </plist>
</ios>
```

## Implementation Status

| Feature               | Android | iOS |
| --------------------- | ------- | --- |
| Basic playback        | ✅       | ✅   |
| Audio focus           | ✅       | ✅   |
| Lock screen controls  | ✅       | ✅   |
| Notification controls | ✅       | N/A |
| Background playback   | ✅       | ✅   |
| Metadata display      | ✅       | ✅   |
| Artwork loading       | ✅       | ✅   |
| Auto reconnection     | ✅       | ✅   |
| HLS streaming         | ✅       | ✅   |

## Technical Details

### Android
- Uses **Media3 ExoPlayer 1.5.1** (latest stable)
- MediaSessionCompat for lock screen/notification integration
- Foreground service for background playback
- Automatic retry on stream errors (5 attempts, 3 second delay)

### iOS
- AVPlayer for playback
- AVAudioSession with `.playback` category
- MPNowPlayingInfoCenter for lock screen metadata
- MPRemoteCommandCenter for lock screen/headphone controls
- Handles interruptions (phone calls) and route changes (headphone unplug)
- Automatic retry on stream errors (5 attempts, 3 second delay)

## Building from Source

```bash
# Clone the repository
git clone https://github.com/macCesar/ti.audiostream.git
cd ti.audiostream

# Build Android
cd android
ti build -p android --build-only

# Build iOS (when implemented)
cd ../ios
ti build -p ios --build-only
```

## License

MIT License - Copyright (c) 2026 César Estrada (macCesar)

## Credits

Inspired by the challenges faced integrating audio streaming with proper system integration in Titanium SDK applications.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.
