/**
 * ti.audiostream - Complete Example
 *
 * This example demonstrates all features of the ti.audiostream module:
 * - Stream configuration and playback control
 * - Metadata and artwork display
 * - State change handling
 * - Audio focus events (Android)
 * - Remote control events (lock screen, notification, headphones)
 * - Error handling and automatic reconnection
 *
 * @author César Estrada (macCesar)
 * @license MIT
 */

'use strict'

// =============================================================================
// MODULE IMPORT
// =============================================================================

const audioStream = require('ti.audiostream')

// =============================================================================
// CONFIGURATION
// =============================================================================

// Sample radio streams for testing (replace with your own)
const STREAMS = {
  // Live radio streams
  radioParadise: {
    url: 'https://stream.radioparadise.com/aac-320',
    title: 'Radio Paradise',
    artist: 'Commercial-Free Radio',
    artwork: 'https://radioparadise.com/graphics/fb_logo.png',
    isLive: true
  },
  jazzFM: {
    url: 'https://jazz-wr15.ice.infomaniak.ch/jazz-wr15-128.mp3',
    title: 'Jazz FM',
    artist: 'Smooth Jazz Radio',
    artwork: 'https://www.jazzradio.com/images/jazzradio-logo.png',
    isLive: true
  },
  classicFM: {
    url: 'https://media-ice.musicradio.com/ClassicFMMP3',
    title: 'Classic FM',
    artist: 'Classical Music',
    artwork: 'https://www.classicfm.com/images/og-image.jpg',
    isLive: true
  },

  // On-demand audio (for testing non-live playback)
  podcast: {
    url: 'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
    title: 'Sample Track',
    artist: 'SoundHelix Demo',
    artwork: null,
    isLive: false
  }
}

// Current stream selection
let currentStreamKey = 'radioParadise'
let currentStream = STREAMS[currentStreamKey]

// =============================================================================
// UI CREATION
// =============================================================================

const win = Ti.UI.createWindow({
  backgroundColor: '#1a1a2e',
  title: 'ti.audiostream Demo'
})

// Main container with vertical layout
const mainContainer = Ti.UI.createScrollView({
  layout: 'vertical',
  top: 50,
  left: 20,
  right: 20,
  bottom: 20,
  contentHeight: Ti.UI.SIZE
})

// -----------------------------------------------------------------------------
// Header Section
// -----------------------------------------------------------------------------

const headerLabel = Ti.UI.createLabel({
  text: 'ti.audiostream',
  font: { fontSize: 28, fontWeight: 'bold' },
  color: '#e94560',
  top: 0
})

const subtitleLabel = Ti.UI.createLabel({
  text: 'Professional Audio Streaming Module',
  font: { fontSize: 14 },
  color: '#888888',
  top: 5
})

// -----------------------------------------------------------------------------
// Artwork Section
// -----------------------------------------------------------------------------

const artworkContainer = Ti.UI.createView({
  width: 200,
  height: 200,
  top: 30,
  backgroundColor: '#16213e',
  borderRadius: 10
})

const artworkImage = Ti.UI.createImageView({
  width: Ti.UI.FILL,
  height: Ti.UI.FILL,
  defaultImage: '/images/default_artwork.png' // Add a default image to your assets
})
artworkContainer.add(artworkImage)

// -----------------------------------------------------------------------------
// Track Info Section
// -----------------------------------------------------------------------------

const trackTitleLabel = Ti.UI.createLabel({
  text: currentStream.title,
  font: { fontSize: 20, fontWeight: 'bold' },
  color: '#ffffff',
  top: 20,
  textAlign: 'center'
})

const trackArtistLabel = Ti.UI.createLabel({
  text: currentStream.artist,
  font: { fontSize: 16 },
  color: '#888888',
  top: 5,
  textAlign: 'center'
})

// -----------------------------------------------------------------------------
// Status Section
// -----------------------------------------------------------------------------

const statusContainer = Ti.UI.createView({
  layout: 'horizontal',
  top: 20,
  height: Ti.UI.SIZE,
  width: Ti.UI.SIZE
})

const stateIndicator = Ti.UI.createView({
  width: 12,
  height: 12,
  borderRadius: 6,
  backgroundColor: '#888888' // Gray = stopped
})

const stateLabel = Ti.UI.createLabel({
  text: 'Stopped',
  font: { fontSize: 14 },
  color: '#888888',
  left: 10
})

statusContainer.add(stateIndicator)
statusContainer.add(stateLabel)

// -----------------------------------------------------------------------------
// Control Buttons Section
// -----------------------------------------------------------------------------

const controlsContainer = Ti.UI.createView({
  layout: 'horizontal',
  top: 30,
  height: 80,
  width: Ti.UI.SIZE
})

const btnPrev = Ti.UI.createButton({
  title: '⏮',
  font: { fontSize: 24 },
  width: 60,
  height: 60,
  borderRadius: 30,
  backgroundColor: '#16213e',
  color: '#ffffff'
})

const btnPlayPause = Ti.UI.createButton({
  title: '▶',
  font: { fontSize: 32 },
  width: 80,
  height: 80,
  borderRadius: 40,
  backgroundColor: '#e94560',
  color: '#ffffff',
  left: 15
})

const btnStop = Ti.UI.createButton({
  title: '⏹',
  font: { fontSize: 24 },
  width: 60,
  height: 60,
  borderRadius: 30,
  backgroundColor: '#16213e',
  color: '#ffffff',
  left: 15
})

const btnNext = Ti.UI.createButton({
  title: '⏭',
  font: { fontSize: 24 },
  width: 60,
  height: 60,
  borderRadius: 30,
  backgroundColor: '#16213e',
  color: '#ffffff',
  left: 15
})

controlsContainer.add(btnPrev)
controlsContainer.add(btnPlayPause)
controlsContainer.add(btnStop)
controlsContainer.add(btnNext)

// -----------------------------------------------------------------------------
// Stream Selection Section
// -----------------------------------------------------------------------------

const streamSectionLabel = Ti.UI.createLabel({
  text: 'Select Stream:',
  font: { fontSize: 14, fontWeight: 'bold' },
  color: '#e94560',
  top: 30
})

// Stream selection buttons
const streamButtonsContainer = Ti.UI.createView({
  layout: 'vertical',
  top: 10,
  width: Ti.UI.FILL,
  height: Ti.UI.SIZE
})

Object.keys(STREAMS).forEach(function (key) {
  const stream = STREAMS[key]
  const btn = Ti.UI.createButton({
    title: stream.title,
    streamKey: key,
    font: { fontSize: 14 },
    height: 40,
    top: 5,
    backgroundColor: key === currentStreamKey ? '#e94560' : '#16213e',
    color: '#ffffff',
    borderRadius: 5
  })

  btn.addEventListener('click', function () {
    // Update button styles
    streamButtonsContainer.children.forEach(function (child) {
      child.backgroundColor = '#16213e'
    })
    btn.backgroundColor = '#e94560'

    // Load the stream
    loadStream(key)
  })

  streamButtonsContainer.add(btn)
})

// -----------------------------------------------------------------------------
// Debug Log Section
// -----------------------------------------------------------------------------

const logSectionLabel = Ti.UI.createLabel({
  text: 'Event Log:',
  font: { fontSize: 14, fontWeight: 'bold' },
  color: '#e94560',
  top: 20
})

const logContainer = Ti.UI.createScrollView({
  top: 10,
  height: 150,
  backgroundColor: '#0f0f23',
  borderRadius: 5,
  contentHeight: Ti.UI.SIZE,
  scrollType: 'vertical'
})

const logLabel = Ti.UI.createLabel({
  text: '',
  font: { fontSize: 11, fontFamily: Ti.Platform.osname === 'android' ? 'monospace' : 'Courier' },
  color: '#00ff00',
  top: 5,
  left: 10,
  right: 10
})
logContainer.add(logLabel)

// -----------------------------------------------------------------------------
// Audio Focus Section (Android only)
// -----------------------------------------------------------------------------

let focusLabel = null
if (Ti.Platform.osname === 'android') {
  const focusSectionLabel = Ti.UI.createLabel({
    text: 'Audio Focus (Android):',
    font: { fontSize: 14, fontWeight: 'bold' },
    color: '#e94560',
    top: 15
  })
  mainContainer.add(focusSectionLabel)

  focusLabel = Ti.UI.createLabel({
    text: 'No focus events yet',
    font: { fontSize: 12 },
    color: '#888888',
    top: 5
  })
  mainContainer.add(focusLabel)
}

// -----------------------------------------------------------------------------
// Property Check Section
// -----------------------------------------------------------------------------

const propSectionLabel = Ti.UI.createLabel({
  text: 'Module Properties:',
  font: { fontSize: 14, fontWeight: 'bold' },
  color: '#e94560',
  top: 20
})

const playingLabel = Ti.UI.createLabel({
  text: 'playing: false',
  font: { fontSize: 12 },
  color: '#888888',
  top: 5
})

// Refresh playing status periodically
setInterval(function () {
  playingLabel.text = 'playing: ' + (audioStream.playing ? 'true' : 'false')
  playingLabel.color = audioStream.playing ? '#00ff00' : '#888888'
}, 500)

// -----------------------------------------------------------------------------
// Assemble UI
// -----------------------------------------------------------------------------

mainContainer.add(headerLabel)
mainContainer.add(subtitleLabel)
mainContainer.add(artworkContainer)
mainContainer.add(trackTitleLabel)
mainContainer.add(trackArtistLabel)
mainContainer.add(statusContainer)
mainContainer.add(controlsContainer)
mainContainer.add(streamSectionLabel)
mainContainer.add(streamButtonsContainer)
mainContainer.add(propSectionLabel)
mainContainer.add(playingLabel)
mainContainer.add(logSectionLabel)
mainContainer.add(logContainer)

win.add(mainContainer)

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/**
 * Add message to the event log
 */
let logMessages = []
function log(message) {
  const timestamp = new Date().toLocaleTimeString()
  const entry = '[' + timestamp + '] ' + message

  Ti.API.info('[ti.audiostream] ' + message)

  logMessages.unshift(entry) // Add to beginning
  if (logMessages.length > 50) {
    logMessages = logMessages.slice(0, 50) // Keep last 50 entries
  }

  logLabel.text = logMessages.join('\n')
}

/**
 * Update UI state indicator
 */
function updateStateUI(state) {
  const stateColors = {
    buffering: '#ffcc00', // Yellow
    playing: '#00ff00', // Green
    paused: '#ff9900', // Orange
    stopped: '#888888', // Gray
    error: '#ff0000' // Red
  }

  stateIndicator.backgroundColor = stateColors[state] || '#888888'
  stateLabel.text = state.charAt(0).toUpperCase() + state.slice(1)
  stateLabel.color = stateColors[state] || '#888888'

  // Update play/pause button
  if (state === 'playing') {
    btnPlayPause.title = '⏸'
  } else {
    btnPlayPause.title = '▶'
  }
}

/**
 * Update track info UI
 */
function updateTrackInfo(stream) {
  trackTitleLabel.text = stream.title
  trackArtistLabel.text = stream.artist

  if (stream.artwork) {
    artworkImage.image = stream.artwork
  } else {
    artworkImage.image = null
  }
}

/**
 * Load and configure a stream (does NOT auto-start)
 */
function loadStream(streamKey) {
  currentStreamKey = streamKey
  currentStream = STREAMS[streamKey]

  log('Loading stream: ' + currentStream.title)

  // Configure the stream
  audioStream.setStream({
    url: currentStream.url,
    isLive: currentStream.isLive
  })

  // Set metadata for lock screen / notification
  audioStream.setMetadata({
    title: currentStream.title,
    artist: currentStream.artist,
    artwork: currentStream.artwork,
  })

  // Update UI
  updateTrackInfo(currentStream)
}

/**
 * Get next stream key
 */
function getNextStreamKey() {
  const keys = Object.keys(STREAMS)
  const currentIndex = keys.indexOf(currentStreamKey)
  return keys[(currentIndex + 1) % keys.length]
}

/**
 * Get previous stream key
 */
function getPrevStreamKey() {
  const keys = Object.keys(STREAMS)
  const currentIndex = keys.indexOf(currentStreamKey)
  return keys[(currentIndex - 1 + keys.length) % keys.length]
}

// =============================================================================
// EVENT LISTENERS - MODULE EVENTS
// =============================================================================

/**
 * State change event
 * Fired when playback state changes: buffering, playing, paused, stopped, error
 */
audioStream.addEventListener('state', function (e) {
  log('State: ' + e.state)
  updateStateUI(e.state)
})

/**
 * Error event
 * Fired when an error occurs during playback
 */
audioStream.addEventListener('error', function (e) {
  log('ERROR: ' + (e.message || 'Unknown error'))
  updateStateUI('error')

  // Show alert for errors
  Ti.UI.createAlertDialog({
    title: 'Playback Error',
    message: e.message || 'An error occurred during playback',
    buttonNames: ['OK']
  }).show()
})

/**
 * Audio focus change event (Android only)
 * Fired when audio focus is gained or lost
 */
audioStream.addEventListener('audiofocuschange', function (e) {
  let focusType = 'Unknown'

  // Decode the focus change constant
  if (e.focusChange === audioStream.AUDIOFOCUS_GAIN) {
    focusType = 'GAIN (restored)'
  } else if (e.focusChange === audioStream.AUDIOFOCUS_LOSS) {
    focusType = 'LOSS (permanent)'
  } else if (e.focusChange === audioStream.AUDIOFOCUS_LOSS_TRANSIENT) {
    focusType = 'LOSS_TRANSIENT (temporary)'
  } else if (e.focusChange === audioStream.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK) {
    focusType = 'LOSS_TRANSIENT_CAN_DUCK (lowered volume)'
  }

  log('Audio Focus: ' + focusType)

  if (focusLabel) {
    focusLabel.text = 'Focus: ' + focusType + ' | Has Focus: ' + e.focused
    focusLabel.color = e.focused ? '#00ff00' : '#ff9900'
  }
})

/**
 * Remote control event
 * Fired when user interacts with lock screen, notification, or headphone controls
 */
audioStream.addEventListener('remotecontrol', function (e) {
  let action = 'Unknown (' + e.subtype + ')'

  // Decode the remote control command
  switch (e.subtype) {
    case audioStream.REMOTE_CONTROL_PLAY:
      action = 'PLAY'
      // Auto-start playback when play is pressed from lock screen
      audioStream.start()
      break

    case audioStream.REMOTE_CONTROL_PAUSE:
      action = 'PAUSE'
      audioStream.pause()
      break

    case audioStream.REMOTE_CONTROL_STOP:
      action = 'STOP'
      audioStream.stop()
      break

    case audioStream.REMOTE_CONTROL_PLAY_PAUSE:
      action = 'PLAY/PAUSE (toggle)'
      // Toggle based on current state
      if (audioStream.playing) {
        audioStream.pause()
      } else {
        audioStream.start()
      }
      break

    case audioStream.REMOTE_CONTROL_NEXT:
      action = 'NEXT'
      // Load and play next stream
      loadStream(getNextStreamKey())
      audioStream.start()
      break

    case audioStream.REMOTE_CONTROL_PREV:
      action = 'PREV'
      // Load and play previous stream
      loadStream(getPrevStreamKey())
      audioStream.start()
      break

    // iOS-specific seek controls
    case audioStream.REMOTE_CONTROL_START_SEEK_FORWARD:
      action = 'START_SEEK_FORWARD'
      break

    case audioStream.REMOTE_CONTROL_END_SEEK_FORWARD:
      action = 'END_SEEK_FORWARD'
      break

    case audioStream.REMOTE_CONTROL_START_SEEK_BACK:
      action = 'START_SEEK_BACK'
      break

    case audioStream.REMOTE_CONTROL_END_SEEK_BACK:
      action = 'END_SEEK_BACK'
      break
  }

  log('Remote Control: ' + action)
})

// =============================================================================
// EVENT LISTENERS - UI BUTTONS
// =============================================================================

/**
 * Play/Pause button
 */
btnPlayPause.addEventListener('click', function () {
  if (audioStream.playing) {
    log('User pressed: PAUSE')
    audioStream.pause()
  } else {
    log('User pressed: PLAY')
    audioStream.start()
  }
})

/**
 * Stop button
 */
btnStop.addEventListener('click', function () {
  log('User pressed: STOP')
  audioStream.stop()
})

/**
 * Previous button
 */
btnPrev.addEventListener('click', function () {
  log('User pressed: PREV')
  loadStream(getPrevStreamKey())
  audioStream.start()
})

/**
 * Next button
 */
btnNext.addEventListener('click', function () {
  log('User pressed: NEXT')
  loadStream(getNextStreamKey())
  audioStream.start()
})

// =============================================================================
// WINDOW EVENTS
// =============================================================================

/**
 * Window close - cleanup
 */
win.addEventListener('close', function () {
  log('Window closing - stopping playback')
  audioStream.stop()
})

// =============================================================================
// INITIALIZATION
// =============================================================================

// Load the default stream on startup
loadStream(currentStreamKey)

// Log module constants (for debugging)
log('--- Module Loaded ---')
log('Platform: ' + Ti.Platform.osname)
log('REMOTE_CONTROL_PLAY: ' + audioStream.REMOTE_CONTROL_PLAY)
log('REMOTE_CONTROL_PAUSE: ' + audioStream.REMOTE_CONTROL_PAUSE)
log('REMOTE_CONTROL_STOP: ' + audioStream.REMOTE_CONTROL_STOP)

if (Ti.Platform.osname === 'android') {
  log('AUDIOFOCUS_GAIN: ' + audioStream.AUDIOFOCUS_GAIN)
  log('AUDIOFOCUS_LOSS: ' + audioStream.AUDIOFOCUS_LOSS)
}

log('Ready to play!')

// Open the window
win.open()

// =============================================================================
// USAGE NOTES
// =============================================================================
/*

## Testing Audio Focus (Android)

1. Start playback in this app
2. Open YouTube and play a video
   - This app should PAUSE automatically
   - YouTube should have exclusive audio
3. Pause YouTube
   - This app can resume (if you press play)
4. Play a short notification sound
   - This app should temporarily lower volume or pause
   - Resume automatically after notification

## Testing Lock Screen Controls

1. Start playback
2. Lock the phone
3. Use the lock screen media controls
4. Check the notification controls (Android)

## Testing Headphone Controls

1. Connect Bluetooth headphones
2. Start playback
3. Use the headphone play/pause button
4. Disconnect headphones - app should pause (iOS)

## Testing Automatic Reconnection

1. Start playback
2. Toggle airplane mode briefly
3. The module will attempt to reconnect (up to 5 times)
4. Check the log for reconnection attempts

## Constants Reference

### Remote Control (both platforms)
- REMOTE_CONTROL_PLAY: 100
- REMOTE_CONTROL_PAUSE: 101
- REMOTE_CONTROL_STOP: 102
- REMOTE_CONTROL_PLAY_PAUSE: 103
- REMOTE_CONTROL_NEXT: 104
- REMOTE_CONTROL_PREV: 105

### iOS Only
- REMOTE_CONTROL_START_SEEK_BACK: 106
- REMOTE_CONTROL_END_SEEK_BACK: 107
- REMOTE_CONTROL_START_SEEK_FORWARD: 108
- REMOTE_CONTROL_END_SEEK_FORWARD: 109

### Android Only - Audio Focus
- AUDIOFOCUS_GAIN: 1
- AUDIOFOCUS_LOSS: -1
- AUDIOFOCUS_LOSS_TRANSIENT: -2
- AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK: -3

*/
