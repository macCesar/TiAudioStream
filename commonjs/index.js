'use strict';

/**
 * ti.audiostream - CommonJS API Layer
 * This file acts as a bridge between the Titanium app and the native modules.
 */

const native = require('ti.audiostream');

/**
 * Set the audio stream
 * @param {Object} options { url: string, isLive: boolean }
 */
exports.setStream = function(options) {
    if (!options || !options.url) {
        throw new Error('ti.audiostream: setStream requires an object with a "url" property.');
    }
    
    native.setStream({
        url: options.url,
        isLive: (options.isLive !== undefined) ? options.isLive : true
    });
};

/**
 * Set metadata for lock screen and notifications
 * @param {Object} meta { title, artist, artwork }
 */
exports.setMetadata = function(meta) {
    if (!meta) return;
    
    native.setMetadata({
        title: meta.title || '',
        artist: meta.artist || meta.subtitle || '',
        artwork: meta.artwork || null
    });
};

/**
 * Playback controls
 */
exports.play = function() {
    native.play();
};

exports.start = function() {
    // Compatibility alias
    native.play();
};

exports.pause = function() {
    native.pause();
};

exports.stop = function() {
    native.stop();
};

/**
 * Event Listeners
 */
native.addEventListener('state', function(e) {
    exports.fireEvent('statechange', {
        state: e.state
    });
});

native.addEventListener('error', function(e) {
    exports.fireEvent('error', {
        message: e.message || 'Unknown stream error'
    });
});

native.addEventListener('remotecontrol', function(e) {
    exports.fireEvent('remotecontrol', {
        subtype: e.subtype,
        command: mapSubtypeToCommand(e.subtype)
    });
});

function mapSubtypeToCommand(subtype) {
    const map = {
        100: 'play',
        101: 'pause',
        102: 'stop',
        103: 'toggle',
        104: 'next',
        105: 'prev'
    };
    return map[subtype] || 'unknown';
}

// Event Emitter logic
const EventEmitter = require('events').EventEmitter;
const bridge = new EventEmitter();
exports.addEventListener = bridge.on.bind(bridge);
exports.removeEventListener = bridge.removeListener.bind(bridge);
exports.fireEvent = bridge.emit.bind(bridge);
