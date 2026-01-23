/**
 * ti.audiostream - Professional Example App (Refined)
 *
 * Demonstrates:
 * - Optimized Light Mode UI
 * - Matrix-style Terminal Console (Auto-scrolling)
 * - Error handling for dead streams
 * - Real-time metadata and station synchronization
 */

const audioStream = require('ti.audiostream')

// =============================================================================
// CONFIGURATION & COLORS
// =============================================================================

const COLORS = {
  text: '#1c1c1e',
  card: '#ffffff',
  background: '#f2f2f7',
  secondaryBtn: '#e5e5ea',
  secondaryText: '#8e8e93',
  error: '#ff3b30',
  accent: '#007aff',
  success: '#34c759',
  matrixBg: '#000000',
  matrixText: '#00ff00'
};

const STREAMS = {
  radioParadise: {
    isLive: true,
    title: 'Radio Paradise',
    artist: 'Eclectic Rock',
    url: 'https://stream.radioparadise.com/aac-320',
    artwork: 'https://upload.wikimedia.org/wikipedia/commons/7/78/Radio_Paradise_logo.png',
  },
  grooveSalad: {
    isLive: true,
    title: 'Groove Salad',
    artist: 'Ambient Beats',
    url: 'http://ice1.somafm.com/groovesalad-128-mp3',
    artwork: 'https://somafm.com/img3/groovesalad-400.png',
  },
  heart: {
    isLive: true,
    title: 'Heart Radio UK',
    artist: 'London\'s No.1 Hit Music Station',
    url: 'https://hls.thisisdax.com/hls/HeartLondon/master.m3u8',
    artwork: 'https://www.jazz24.org/wp-content/uploads/2014/10/jazz24_logo_300.png',
  },
  sample: {
    isLive: true,
    title: 'Reference Streams',
    artist: 'Metadata Compliance Test',
    url: 'https://streams.radiomast.io/ref-128k-mp3-stereo/hls.m3u8',
    artwork: 'https://www.radiomast.io/wp-content/uploads/2022/01/logo-radiomast-vertical.png',
  },
  jazz24: {
    isLive: true,
    title: 'Jazz24',
    artist: 'Public Radio from Seattle',
    url: 'https://knkx-live-a.edge.audiocdn.com/6285_256k/playlist.m3u8',
    artwork: 'https://www.jazz24.org/wp-content/uploads/2014/10/jazz24_logo_300.png',
  },
  offline: {
    isLive: true,
    title: 'Offline Test',
    artist: 'Intentionally broken signal',
    url: 'https://invalid-url-for-test.org/dead.m3u8',
    artwork: 'https://www.radiomast.io/wp-content/uploads/2022/01/logo-radiomast-vertical.png',
  }
}

let currentStreamKey = 'radioParadise'
let currentStream = STREAMS[currentStreamKey]

// =============================================================================
// UI COMPONENTS
// =============================================================================

const win = Ti.UI.createWindow({
  barColor: COLORS.card,
  extendSafeArea: false,
  title: 'ti.audiostream',
  backgroundColor: COLORS.background,
  titleAttributes: { color: COLORS.text }
})

const mainContainer = Ti.UI.createScrollView({
  layout: 'vertical',
  contentHeight: Ti.UI.SIZE
})

// Header Section (Reduced spacing)
const header = Ti.UI.createView({ height: 80, top: 10, layout: 'vertical' });
header.add(Ti.UI.createLabel({
  text: 'ti.audiostream',
  font: { fontSize: 28, fontWeight: 'bold' },
  color: COLORS.accent
}));
header.add(Ti.UI.createLabel({
  text: 'Unified Audio Engine v1.0.0',
  font: { fontSize: 13 },
  color: COLORS.secondaryText
}));
mainContainer.add(header);

// Artwork Card (Reduced top margin)
const playerCard = Ti.UI.createView({
  width: '90%', height: 300, top: 5,
  backgroundColor: COLORS.card,
  borderRadius: 20,
  elevation: 5,
  shadowColor: '#000', shadowOffset: { width: 0, height: 2 }, shadowOpacity: 0.1, shadowRadius: 10
});

// Container to prevent distortion
const artworkContainer = Ti.UI.createView({
  width: 160, height: 160, top: 20,
  backgroundColor: '#f8f8f8',
  borderRadius: 15
});

const artworkImage = Ti.UI.createImageView({
  width: 160, height: Ti.UI.SIZE, // Fix width, auto height to maintain ratio
  defaultImage: '/images/default_artwork.png',
  image: currentStream.artwork
});
artworkContainer.add(artworkImage);
playerCard.add(artworkContainer);

const trackTitleLabel = Ti.UI.createLabel({
  text: currentStream.title,
  font: { fontSize: 18, fontWeight: 'bold' },
  color: COLORS.text,
  top: 210, textAlign: 'center', width: '90%', height: 24
});
playerCard.add(trackTitleLabel);

const trackArtistLabel = Ti.UI.createLabel({
  text: currentStream.artist,
  font: { fontSize: 15 },
  color: COLORS.secondaryText,
  top: 235, textAlign: 'center', width: '90%', height: 20
});
playerCard.add(trackArtistLabel);

const stateLabel = Ti.UI.createLabel({
  text: 'READY',
  font: { fontSize: 11, fontWeight: 'bold' },
  color: COLORS.accent,
  top: 265
});
playerCard.add(stateLabel);

mainContainer.add(playerCard);

// Controls (Improved buttons)
const controls = Ti.UI.createView({ top: 15, height: 60, width: Ti.UI.SIZE, layout: 'horizontal' });

const btnPrev = Ti.UI.createButton({
  title: ' BACK ', backgroundColor: COLORS.secondaryBtn, color: COLORS.accent,
  backgroundSelectedColor: 'transparent',
  borderRadius: 15, height: 40, width: 80, font: { fontWeight: 'bold', fontSize: 12 }
});
const btnPlayPause = Ti.UI.createButton({
  title: '  PLAY  ', backgroundColor: COLORS.accent, color: '#fff',
  backgroundSelectedColor: '#0051d5',
  borderRadius: 25, height: 50, width: 100, left: 15, right: 15
});
const btnNext = Ti.UI.createButton({
  title: ' NEXT ', backgroundColor: COLORS.secondaryBtn, color: COLORS.accent,
  backgroundSelectedColor: 'transparent',
  borderRadius: 15, height: 40, width: 80, font: { fontWeight: 'bold', fontSize: 12 }
});

controls.add(btnPrev);
controls.add(btnPlayPause);
controls.add(btnNext);
mainContainer.add(controls);

// Station Selection (Reduced spacing)
mainContainer.add(Ti.UI.createLabel({
  top: 20,
  left: 25,
  text: 'SELECT STATION',
  color: COLORS.secondaryText,
  font: { fontSize: 11, fontWeight: 'bold' }
}));

const stationList = Ti.UI.createView({
  top: 5, height: Ti.UI.SIZE, width: Ti.UI.SIZE, layout: 'horizontal'
});

const stationButtons = {};

Object.keys(STREAMS).forEach(key => {
  const s = STREAMS[key];
  const btn = Ti.UI.createButton({
    title: s.title,
    streamKey: key,
    borderRadius: 10,
    color: COLORS.text,
    font: { fontSize: 11 },
    width: '46%', height: 40,
    backgroundColor: COLORS.card,
    backgroundSelectedColor: COLORS.card,
    left: 2, right: 2, top: 2, bottom: 2
  });

  btn.addEventListener('click', () => loadStream(key, true));
  stationList.add(btn);
  stationButtons[key] = btn;
});
mainContainer.add(stationList);

// Terminal Matrix Console
const logHeader = Ti.UI.createView({ top: 20, left: 25, right: 25, height: 25 });
logHeader.add(Ti.UI.createLabel({
  left: 0,
  text: 'SYSTEM LOG',
  color: COLORS.secondaryText,
  font: { fontSize: 11, fontWeight: 'bold' }
}));

const btnClear = Ti.UI.createLabel({
  right: 0,
  text: 'CLEAR',
  color: COLORS.accent,
  font: { fontSize: 10, fontWeight: 'bold' }
});
logHeader.add(btnClear);
mainContainer.add(logHeader);

const consoleView = Ti.UI.createScrollView({
  top: 5, left: 20, right: 20, bottom: 40,
  height: 140,
  backgroundColor: COLORS.matrixBg,
  borderRadius: 10,
  contentHeight: Ti.UI.SIZE,
  scrollType: 'vertical'
});

const logLabel = Ti.UI.createLabel({
  height: Ti.UI.SIZE,
  color: COLORS.matrixText,
  top: 10, left: 10, right: 10,
  text: '> System initialized\n',
  font: { fontSize: 10, fontFamily: 'monospace' }
});
consoleView.add(logLabel);
mainContainer.add(consoleView);

win.add(mainContainer);

// =============================================================================
// LOGIC
// =============================================================================

function log(msg) {
  Ti.API.info('[ti.audiostream] ' + msg);
  const date = new Date().toLocaleTimeString();
  logLabel.text += `[${date}] ${msg}\n`;

  // Auto-scroll to bottom (standard terminal behavior)
  setTimeout(() => {
    consoleView.scrollToBottom();
  }, 100);
}

btnClear.addEventListener('click', () => {
  logLabel.text = '> Console cleared\n';
});
function updateButtonStyles(activeKey) {
  Object.keys(stationButtons).forEach(key => {
    const btn = stationButtons[key];
    if (key === activeKey) {
      btn.backgroundColor = COLORS.accent;
      btn.color = '#fff';
    } else {
      btn.backgroundColor = COLORS.card;
      btn.color = COLORS.text;
    }
  });
}

function loadStream(key, shouldStart) {
  currentStreamKey = key;
  currentStream = STREAMS[key];

  log('Loading: ' + currentStream.title);
  updateButtonStyles(key);

  trackTitleLabel.text = currentStream.title;
  trackArtistLabel.text = currentStream.artist;
  artworkImage.image = currentStream.artwork || null;

  audioStream.setStream({ url: currentStream.url, isLive: currentStream.isLive });
  if (shouldStart) audioStream.start();
}

function getNextKey() {
  const keys = Object.keys(STREAMS);
  return keys[(keys.indexOf(currentStreamKey) + 1) % keys.length];
}

function getPrevKey() {
  const keys = Object.keys(STREAMS);
  const idx = keys.indexOf(currentStreamKey);
  return keys[(idx - 1 + keys.length) % keys.length];
}

// =============================================================================
// EVENT LISTENERS
// =============================================================================

audioStream.addEventListener('state', (e) => {
  log('State: ' + e.state);
  stateLabel.text = e.state.toUpperCase();
  stateLabel.color = (e.state === 'error') ? COLORS.error : COLORS.accent;
  btnPlayPause.title = (e.state === 'playing') ? ' PAUSE ' : '  PLAY  ';
});

audioStream.addEventListener('error', (e) => {
  const errorMsg = e.message || 'The stream URL is invalid or the server is unreachable.';
  log('ERROR: ' + errorMsg);

  const dialog = Ti.UI.createAlertDialog({
    title: 'Connection Failed',
    message: `Station: ${currentStream.title}\n\nTechnical Details:\n${errorMsg}`,
    buttonNames: ['Understand']
  });
  dialog.show();
});

audioStream.addEventListener('metadata', (e) => {
  log('METADATA: ' + e.title + ' - ' + e.artist);
  if (e.raw) log('RAW: ' + JSON.stringify(e.raw));

  if (e.title) trackTitleLabel.text = e.title;
  if (e.artist) trackArtistLabel.text = e.artist;
  if (e.artwork) artworkImage.image = e.artwork;
});
audioStream.addEventListener('remotecontrol', (e) => {
  log('Remote Action: ' + e.action);
  if (e.action === 'NEXT') loadStream(getNextKey(), true);
  if (e.action === 'PREV') loadStream(getPrevKey(), true);
});

btnPlayPause.addEventListener('click', () => {
  if (audioStream.playing) audioStream.pause();
  else audioStream.start();
});

btnNext.addEventListener('click', () => loadStream(getNextKey(), true));
btnPrev.addEventListener('click', () => loadStream(getPrevKey(), true));

win.addEventListener('close', () => audioStream.stop());

// Initialize
win.open();
loadStream('radioParadise', true);
