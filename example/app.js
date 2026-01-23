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

const STREAMS = {
  radioParadise: {
    url: 'https://stream.radioparadise.com/aac-320',
    title: 'Radio Paradise',
    artist: 'Eclectic Rock',
    artwork: 'https://radioparadise.com/graphics/fb_logo.png',
    isLive: true
  },
  grooveSalad: {
    url: 'http://ice1.somafm.com/groovesalad-128-mp3',
    title: 'Groove Salad (Metadata Test)',
    artist: 'Waiting for stream data...',
    artwork: 'https://somafm.com/img/groovesalad120.png',
    isLive: true
  },
  kcrw: {
    url: 'https://kcrw.streamguys1.com/kcrw_128k_mp3_e24',
    title: 'All Things Considered',
    artist: 'NPR wraps up the day with all the context and original reporting you need.',
    artwork: 'https://images.ctfassets.net/2658fe8gbo8o/0c84b6ea052973af8bbd15b91b69acdb-photo-asset/9ac95678981cb62b73c760010e8aae97/All-Things-Considered_Tile_NPR-Network-01_Full.jpg?w=750&h=750&fm=webp&q=80&fit=fill&f=center',
    isLive: true
  },
  jazz24: {
    url: 'https://live.jazz24.org/jazz24-mp3',
    title: 'Jazz24',
    artist: 'Seattle Public Radio',
    artwork: 'https://www.jazz24.org/wp-content/uploads/2014/10/jazz24_logo_300.png',
    isLive: true
  },
  sample: {
    isLive: true,
    title: 'Reference Audio Streams',
    artist: 'Sample live audio streams',
    url: 'https://streams.radiomast.io/ref-128k-mp3-stereo/hls.m3u8',
    artwork: ''
  }
}

let currentStreamKey = 'radioParadise'
let currentStream = STREAMS[currentStreamKey]

const LABELS = {
  PREV: 'BACK',
  PLAY: 'PLAY',
  PAUSE: 'PAUSE',
  STOP: 'STOP',
  NEXT: 'NEXT'
};

// =============================================================================
// UI CREATION
// =============================================================================

const win = Ti.UI.createWindow({
  backgroundColor: '#1a1a2e',
  title: 'ti.audiostream Demo',
  width: Ti.UI.FILL,
  height: Ti.UI.FILL
})

const mainContainer = Ti.UI.createScrollView({
  layout: 'vertical',
  top: 50,
  left: 20,
  right: 20,
  bottom: 20,
  width: Ti.UI.FILL,
  contentHeight: Ti.UI.SIZE
})

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
  defaultImage: '/images/default_artwork.png'
})
artworkContainer.add(artworkImage)

const trackTitleLabel = Ti.UI.createLabel({
  text: currentStream.title,
  font: { fontSize: 20, fontWeight: 'bold' },
  color: '#ffffff',
  top: 20,
  left: 10,
  right: 10,
  height: Ti.UI.SIZE,
  textAlign: 'center'
})

const trackArtistLabel = Ti.UI.createLabel({
  text: currentStream.artist,
  font: { fontSize: 16 },
  color: '#888888',
  top: 5,
  left: 10,
  right: 10,
  height: Ti.UI.SIZE,
  textAlign: 'center'
})

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
  backgroundColor: '#888888'
})

const stateLabel = Ti.UI.createLabel({
  text: 'Stopped',
  font: { fontSize: 14 },
  color: '#888888',
  left: 10
})

statusContainer.add(stateIndicator)
statusContainer.add(stateLabel)

const controlsContainer = Ti.UI.createView({
  layout: 'horizontal',
  top: 30,
  height: 80,
  width: Ti.UI.SIZE
})

const btnPrev = Ti.UI.createButton({
  title: LABELS.PREV,
  font: { fontSize: 11, fontWeight: 'bold' },
  width: 60,
  height: 60,
  borderRadius: 30,
  backgroundColor: '#16213e',
  color: '#ffffff'
})

const btnPlayPause = Ti.UI.createButton({
  title: LABELS.PLAY,
  font: { fontSize: 15, fontWeight: 'bold' },
  width: 80,
  height: 80,
  borderRadius: 40,
  backgroundColor: '#e94560',
  color: '#ffffff',
  left: 15
})

const btnStop = Ti.UI.createButton({
  title: LABELS.STOP,
  font: { fontSize: 11, fontWeight: 'bold' },
  width: 60,
  height: 60,
  borderRadius: 30,
  backgroundColor: '#16213e',
  color: '#ffffff',
  left: 15
})

const btnNext = Ti.UI.createButton({
  title: LABELS.NEXT,
  font: { fontSize: 11, fontWeight: 'bold' },
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

const streamSectionLabel = Ti.UI.createLabel({
  text: 'Select Stream:',
  font: { fontSize: 14, fontWeight: 'bold' },
  color: '#e94560',
  top: 30
})

const streamButtonsContainer = Ti.UI.createView({
  top: 10,
  width: Ti.UI.SIZE,
  height: Ti.UI.SIZE,
  layout: 'horizontal'
})

Object.keys(STREAMS).forEach(function (key) {
  const stream = STREAMS[key]
  const btn = Ti.UI.createButton({
    top: 5,
    left: 2,
    right: 2,
    height: 40,
    streamKey: key,
    borderRadius: 5,
    width: Ti.UI.SIZE,
    color: '#ffffff',
    font: { fontSize: 14 },
    title: `   ${stream.title}   `,
    backgroundColor: key === currentStreamKey ? '#e94560' : '#16213e'
  })

  btn.addEventListener('click', function () {
    streamButtonsContainer.children.forEach(function (child) { child.backgroundColor = '#16213e' })
    btn.backgroundColor = '#e94560'
    loadStream(key)
    audioStream.start()
  })

  streamButtonsContainer.add(btn)
})

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

mainContainer.add(headerLabel)
mainContainer.add(subtitleLabel)
mainContainer.add(artworkContainer)
mainContainer.add(trackTitleLabel)
mainContainer.add(trackArtistLabel)
mainContainer.add(statusContainer)
mainContainer.add(controlsContainer)
mainContainer.add(streamSectionLabel)
mainContainer.add(streamButtonsContainer)
mainContainer.add(logSectionLabel)
mainContainer.add(logContainer)

win.add(mainContainer)

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

let logMessages = []
function log(message) {
  const entry = '[' + new Date().toLocaleTimeString() + '] ' + message
  Ti.API.info('[ti.audiostream] ' + message)
  logMessages.unshift(entry)
  if (logMessages.length > 50) logMessages = logMessages.slice(0, 50)
  logLabel.text = logMessages.join('\n')
}

function clearLog() {
  logMessages = []
  logLabel.text = ''
}

function updateStateUI(state) {
  const stateColors = { buffering: '#ffcc00', playing: '#00ff00', paused: '#ff9900', stopped: '#888888', error: '#ff0000' }
  stateIndicator.backgroundColor = stateColors[state] || '#888888'
  stateLabel.text = state.charAt(0).toUpperCase() + state.slice(1)
  stateLabel.color = stateColors[state] || '#888888'
  btnPlayPause.title = (state === 'playing') ? LABELS.PAUSE : LABELS.PLAY;
}

function updateTrackInfo(stream) {
  trackTitleLabel.text = stream.title
  trackArtistLabel.text = stream.artist
  artworkImage.image = stream.artwork || null
}

function loadStream(streamKey) {
  clearLog()
  currentStreamKey = streamKey
  currentStream = STREAMS[streamKey]
  log('Loading stream: ' + currentStream.title)
  audioStream.setStream({ url: currentStream.url, isLive: currentStream.isLive })
  audioStream.setMetadata({ title: currentStream.title, artist: currentStream.artist, artwork: currentStream.artwork })
  updateTrackInfo(currentStream)
}

function getNextStreamKey() {
  const keys = Object.keys(STREAMS);
  return keys[(keys.indexOf(currentStreamKey) + 1) % keys.length];
}
function getPrevStreamKey() {
  const keys = Object.keys(STREAMS);
  const idx = keys.indexOf(currentStreamKey);
  return keys[(idx - 1 + keys.length) % keys.length];
}

// =============================================================================
// EVENT LISTENERS
// =============================================================================

audioStream.addEventListener('state', (e) => { log('State: ' + e.state); updateStateUI(e.state); })
audioStream.addEventListener('error', (e) => { log('ERROR: ' + e.message); updateStateUI('error'); })
audioStream.addEventListener('metadata', (e) => {
  log('RAW METADATA: ' + JSON.stringify(e))
  if (e.title) trackTitleLabel.text = e.title
  if (e.artist) trackArtistLabel.text = e.artist
})

audioStream.addEventListener('remotecontrol', (e) => {
  log('Remote control event: ' + e.action)
  switch (e.subtype) {
    case audioStream.REMOTE_CONTROL_NEXT: loadStream(getNextStreamKey()); audioStream.start(); break;
    case audioStream.REMOTE_CONTROL_PREV: loadStream(getPrevStreamKey()); audioStream.start(); break;
  }
})

btnPlayPause.addEventListener('click', () => {
  if (audioStream.playing) audioStream.pause()
  else {
    if (stateLabel.text === 'Stopped' || stateLabel.text === 'Error') loadStream(currentStreamKey);
    audioStream.start()
  }
})

btnStop.addEventListener('click', () => audioStream.stop())
btnPrev.addEventListener('click', () => { loadStream(getPrevStreamKey()); audioStream.start(); })
btnNext.addEventListener('click', () => { loadStream(getNextStreamKey()); audioStream.start(); })

win.addEventListener('close', () => audioStream.stop())

loadStream(currentStreamKey)
win.open()
