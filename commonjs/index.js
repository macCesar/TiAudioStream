'use strict';

/**
 * ti.audiostream - CommonJS API Layer
 * This file acts as a bridge between the Titanium app and the native modules.
 */

const native = require('ti.audiostream');

/**
 * Initialize the player
 */
exports.init = function () {
  // Android has an init in docs, but current native doesn't expose it.
  // We handle it gracefully.
  if (typeof native.init === 'function') {
    native.init();
  }
};

/**
 * Set the audio stream
 * @param {Object} options { url: string, isLive: boolean }
 */
exports.setStream = function (options) {
  if (!options || !options.url) {
    throw new Error('ti.audiostream: setStream requires an object with a "url" property.');
  }

  // The native module expects a dictionary/KrollDict
  native.setStream({
    url: options.url,
    isLive: (options.isLive !== undefined) ? options.isLive : true
  });
};

/**
 * Set metadata for lock screen and notifications
 * @param {Object} meta { title, artist, artwork, artworkLocal }
 */
exports.setMetadata = function (meta) {
  if (!meta) return;

  native.setMetadata({
    title: meta.title || '',
    artist: meta.artist || meta.subtitle || '', // Support both naming conventions
    artwork: meta.artwork || null,
    artworkLocal: !!meta.artworkLocal
  });
};

/**
 * Official playback method (as per docs)
 */
exports.play = function () {
  native.start();
};

/**
 * Compatibility alias (as per current app usage)
 */
exports.start = function () {
  console.warn('ti.audiostream: .start() is deprecated. Please use .play() instead to match documentation.');
  native.start();
};

/**
 * Pause playback
 */
exports.pause = function () {
  native.pause();
};

/**
 * Stop playback
 */
exports.stop = function () {
  native.stop();
};

/**
 * Event Listener bridge
 */
native.addEventListener('state', function (e) {
  // Normalize native 'state' event to 'statechange' as per docs
  exports.fireEvent('statechange', {
    state: e.state
  });
});

native.addEventListener('error', function (e) {
  exports.fireEvent('error', {
    message: e.message || 'Unknown stream error'
  });
});

native.addEventListener('remotecontrol', function (e) {
  exports.fireEvent('remotecontrol', {
    subtype: e.subtype,
    command: mapSubtypeToCommand(e.subtype)
  });
});

/**
 * Helper to map numeric subtypes to string commands
 */
function mapSubtypeToCommand(subtype) {
  const map = {
    100: 'play',
    101: 'pause',
    102: 'stop',
    103: 'play_pause',
    104: 'next',
    105: 'prev'
  };
  return map[subtype] || 'unknown';
}

// Ensure the JS layer can also emit events
const EventEmitter = require('events').EventEmitter;
const bridge = new EventEmitter();
exports.addEventListener = bridge.on.bind(bridge);
exports.removeEventListener = bridge.removeListener.bind(bridge);
exports.fireEvent = bridge.emit.bind(bridge);
