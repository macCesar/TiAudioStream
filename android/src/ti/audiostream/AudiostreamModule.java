/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 *
 * A native audio streaming module using ExoPlayer with proper audio focus handling
 */
package ti.audiostream;

import android.content.Context;
import android.content.Intent;
import android.media.AudioManager;
import android.os.Build;
import android.view.KeyEvent;

import org.appcelerator.kroll.KrollDict;
import org.appcelerator.kroll.KrollModule;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.common.Log;
import org.appcelerator.kroll.common.TiConfig;
import org.appcelerator.titanium.TiApplication;
import org.appcelerator.titanium.util.TiConvert;

@Kroll.module(name="Audiostream", id="ti.audiostream")
public class AudiostreamModule extends KrollModule
{
	private static final String LCAT = "AudiostreamModule";
	private static final boolean DBG = TiConfig.LOGD;

	// Action constants
	private static final String ACTION_PLAY = "ti.audiostream.PLAY";
	private static final String ACTION_PAUSE = "ti.audiostream.PAUSE";
	private static final String ACTION_PLAY_PAUSE = "ti.audiostream.PLAY_PAUSE";
	private static final String ACTION_STOP = "ti.audiostream.STOP";
	private static final String ACTION_NEXT = "ti.audiostream.NEXT";
	private static final String ACTION_PREV = "ti.audiostream.PREV";
	private static final String ACTION_MEDIA_BUTTON = "android.intent.action.MEDIA_BUTTON";

	// Remote control constants
	@Kroll.constant public static final int REMOTE_CONTROL_PLAY = 100;
	@Kroll.constant public static final int REMOTE_CONTROL_PAUSE = 101;
	@Kroll.constant public static final int REMOTE_CONTROL_STOP = 102;
	@Kroll.constant public static final int REMOTE_CONTROL_PLAY_PAUSE = 103;
	@Kroll.constant public static final int REMOTE_CONTROL_NEXT = 104;
	@Kroll.constant public static final int REMOTE_CONTROL_PREV = 105;
	@Kroll.constant public static final int REMOTE_CONTROL_START_SEEK_BACK = 106;
	@Kroll.constant public static final int REMOTE_CONTROL_END_SEEK_BACK = 107;
	@Kroll.constant public static final int REMOTE_CONTROL_START_SEEK_FORWARD = 108;
	@Kroll.constant public static final int REMOTE_CONTROL_END_SEEK_FORWARD = 109;

	// Audio focus constants
	@Kroll.constant public static final int AUDIOFOCUS_GAIN = AudioManager.AUDIOFOCUS_GAIN;
	@Kroll.constant public static final int AUDIOFOCUS_LOSS = AudioManager.AUDIOFOCUS_LOSS;
	@Kroll.constant public static final int AUDIOFOCUS_LOSS_TRANSIENT = AudioManager.AUDIOFOCUS_LOSS_TRANSIENT;
	@Kroll.constant public static final int AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK = AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK;

	// Static reference for callbacks from service
	private static AudiostreamModule activeModule;

	// State
	private boolean serviceStarted = false;
	private boolean isPlaying = false;

	public AudiostreamModule()
	{
		super();
		activeModule = this;
	}

	@Kroll.onAppCreate
	public static void onAppCreate(TiApplication app)
	{
		if (DBG) {
			Log.d(LCAT, "onAppCreate");
		}
	}

	// ========== Public API Methods ==========

	/**
	 * Set the stream URL
	 * @param args Dictionary with 'url' and optional 'isLive' (default true)
	 */
	@Kroll.method
	public void setStream(KrollDict args)
	{
		if (args == null) {
			Log.e(LCAT, "setStream: args is null");
			return;
		}

		String url = TiConvert.toString(args.get("url"), null);
		if (url == null || url.isEmpty()) {
			Log.e(LCAT, "setStream: url is required");
			return;
		}

		boolean isLive = TiConvert.toBoolean(args.get("isLive"), true);
		boolean autoUpdateMetadata = TiConvert.toBoolean(args.get("autoUpdateMetadata"), true);

		Log.d(LCAT, "setStream: " + url + " (live: " + isLive + ", autoUpdateMetadata: " + autoUpdateMetadata + ")");

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_SET_STREAM);
		intent.putExtra(MediaPlaybackService.EXTRA_URL, url);
		intent.putExtra(MediaPlaybackService.EXTRA_IS_LIVE, isLive);
		intent.putExtra(MediaPlaybackService.EXTRA_AUTO_UPDATE_METADATA, autoUpdateMetadata);

		// Check if title, artist, artwork are provided and set them
		String title = TiConvert.toString(args.get("title"), "");
		String artist = TiConvert.toString(args.get("artist"), "");
		String artwork = TiConvert.toString(args.get("artwork"), null);

		if (!title.isEmpty() || !artist.isEmpty() || artwork != null) {
			intent.putExtra(MediaPlaybackService.EXTRA_TITLE, title);
			intent.putExtra(MediaPlaybackService.EXTRA_ARTIST, artist);
			if (artwork != null) {
				intent.putExtra(MediaPlaybackService.EXTRA_ARTWORK_URL, artwork);
			}
		}

		startServiceSafely(intent);
	}

	/**
	 * Start playback
	 */
	@Kroll.method
	public void start()
	{
		Log.d(LCAT, "start");
		isPlaying = true;

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_PLAY);

		startForegroundServiceSafely(intent);
	}

	/**
	 * Pause playback
	 */
	@Kroll.method
	public void pause()
	{
		Log.d(LCAT, "pause");
		isPlaying = false;

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_PAUSE);

		startServiceSafely(intent);
	}

	/**
	 * Stop playback and release resources
	 */
	@Kroll.method
	public void stop()
	{
		Log.d(LCAT, "stop");
		isPlaying = false;
		serviceStarted = false;

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_STOP);

		startServiceSafely(intent);
	}

	/**
	 * Set metadata for display in notification and lock screen
	 * @param args Dictionary with 'title', 'artist', 'artwork'
	 */
	@Kroll.method
	public void setMetadata(KrollDict args)
	{
		if (args == null) {
			return;
		}

		String title = TiConvert.toString(args.get("title"), "");
		String artist = TiConvert.toString(args.get("artist"), "");
		String artwork = TiConvert.toString(args.get("artwork"), null);

		Log.d(LCAT, "setMetadata: " + title + " - " + artist);

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_SET_METADATA);
		intent.putExtra(MediaPlaybackService.EXTRA_TITLE, title);
		intent.putExtra(MediaPlaybackService.EXTRA_ARTIST, artist);

		if (artwork != null) {
			intent.putExtra(MediaPlaybackService.EXTRA_ARTWORK_URL, artwork);
		}

		startServiceSafely(intent);
	}

	/**
	 * Set whether to automatically update remote controls from stream metadata
	 * @param enabled true to auto-update, false to only use manual setMetadata
	 */
	@Kroll.method
	public void setAutoUpdateMetadata(boolean enabled)
	{
		Log.d(LCAT, "setAutoUpdateMetadata: " + enabled);

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_SET_AUTO_UPDATE_METADATA);
		intent.putExtra(MediaPlaybackService.EXTRA_AUTO_UPDATE_METADATA, enabled);

		startServiceSafely(intent);
	}

	/**
	 * Get current playing state
	 */
	@Kroll.getProperty
	public boolean getPlaying()
	{
		return isPlaying;
	}

	// ========== Service Helpers ==========

	private void startServiceSafely(Intent intent)
	{
		try {
			getContext().startService(intent);
			serviceStarted = true;
		} catch (Exception e) {
			Log.e(LCAT, "Failed to start service: " + e.getMessage());
		}
	}

	private void startForegroundServiceSafely(Intent intent)
	{
		try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
				getContext().startForegroundService(intent);
			} else {
				getContext().startService(intent);
			}
			serviceStarted = true;
		} catch (Exception e) {
			Log.e(LCAT, "Failed to start foreground service: " + e.getMessage());
		}
	}

	private Context getContext()
	{
		return TiApplication.getInstance().getApplicationContext();
	}

	// ========== Static Callbacks from Service ==========

	/**
	 * Called by MediaPlaybackService when state changes
	 */
	public static void fireState(String state)
	{
		if (activeModule == null || !activeModule.hasListeners("state")) {
			return;
		}

		KrollDict event = new KrollDict();
		event.put("state", state);
		activeModule.fireEvent("state", event);

		// Update internal state
		activeModule.isPlaying = "playing".equals(state);

		if (DBG) {
			Log.d(LCAT, "State event fired: " + state);
		}
	}

	/**
	 * Called by MediaPlaybackService when error occurs
	 */
	public static void fireError(String message)
	{
		if (activeModule == null || !activeModule.hasListeners("error")) {
			return;
		}

		KrollDict event = new KrollDict();
		event.put("message", message);
		activeModule.fireEvent("error", event);

		if (DBG) {
			Log.d(LCAT, "Error event fired: " + message);
		}
	}

	/**
	 * Called by MediaPlaybackService when audio focus changes
	 */
	public static void fireAudioFocusChange(int focusChange)
	{
		if (activeModule == null || !activeModule.hasListeners("audiofocuschange")) {
			return;
		}

		KrollDict event = new KrollDict();
		event.put("focusChange", focusChange);
		event.put("focused", focusChange == AudioManager.AUDIOFOCUS_GAIN);
		activeModule.fireEvent("audiofocuschange", event);

		if (DBG) {
			Log.d(LCAT, "Audio focus event fired: " + focusChange);
		}
	}

	/**
	 * Called by MediaPlaybackService when remote control events occur
	 */
	public static void fireRemoteControl(int subtype)
	{
		if (activeModule == null || !activeModule.hasListeners("remotecontrol")) {
			return;
		}

		String action = "UNKNOWN";
		switch (subtype) {
			case REMOTE_CONTROL_PLAY: action = "PLAY"; break;
			case REMOTE_CONTROL_PAUSE: action = "PAUSE"; break;
			case REMOTE_CONTROL_STOP: action = "STOP"; break;
			case REMOTE_CONTROL_PLAY_PAUSE: action = "PLAY_PAUSE"; break;
			case REMOTE_CONTROL_NEXT: action = "NEXT"; break;
			case REMOTE_CONTROL_PREV: action = "PREV"; break;
		}

		KrollDict event = new KrollDict();
		event.put("subtype", subtype);
		event.put("action", action);
		activeModule.fireEvent("remotecontrol", event);

		if (DBG) {
			Log.d(LCAT, "Remote control event fired: " + action + " (" + subtype + ")");
		}
	}

	/**
	 * Called by MediaPlaybackService when stream metadata changes
	 */
	public static void fireMetadata(String title, String artist, String artwork, java.util.Map<String, Object> raw)
	{
		if (activeModule == null || !activeModule.hasListeners("metadata")) {
			return;
		}

		KrollDict event = new KrollDict();
		event.put("title", title);
		event.put("artist", artist);
		event.put("artwork", artwork);
		if (raw != null) {
			event.put("raw", new KrollDict(raw));
		}
		activeModule.fireEvent("metadata", event);

		if (DBG) {
			Log.d(LCAT, "Metadata event fired: " + title + " - " + artist);
		}
	}

	/**
	 * Called by MediaActionReceiver for media button/notification actions
	 */
	public static void handleMediaAction(String action, KeyEvent keyEvent)
	{
		if (activeModule == null) {
			return;
		}

		if (ACTION_MEDIA_BUTTON.equals(action) && keyEvent != null) {
			activeModule.handleMediaButton(keyEvent);
			return;
		}

		if (action == null) {
			return;
		}

		Intent intent = new Intent(activeModule.getContext(), MediaPlaybackService.class);

		switch (action) {
			case ACTION_PLAY:
				intent.setAction(MediaPlaybackService.ACTION_PLAY);
				activeModule.startServiceSafely(intent);
				fireRemoteControl(REMOTE_CONTROL_PLAY);
				break;

			case ACTION_PAUSE:
				intent.setAction(MediaPlaybackService.ACTION_PAUSE);
				activeModule.startServiceSafely(intent);
				fireRemoteControl(REMOTE_CONTROL_PAUSE);
				break;

			case ACTION_STOP:
				intent.setAction(MediaPlaybackService.ACTION_STOP);
				activeModule.startServiceSafely(intent);
				fireRemoteControl(REMOTE_CONTROL_STOP);
				break;

			case ACTION_NEXT:
				fireRemoteControl(REMOTE_CONTROL_NEXT);
				break;

			case ACTION_PREV:
				fireRemoteControl(REMOTE_CONTROL_PREV);
				break;
		}
	}

	private void handleMediaButton(KeyEvent keyEvent)
	{
		int action = keyEvent.getAction();
		int keyCode = keyEvent.getKeyCode();
		boolean isDown = action == KeyEvent.ACTION_DOWN;

		if (!isDown) {
			return;
		}

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);

		switch (keyCode) {
			case KeyEvent.KEYCODE_MEDIA_PLAY:
				intent.setAction(MediaPlaybackService.ACTION_PLAY);
				startForegroundServiceSafely(intent);
				fireRemoteControl(REMOTE_CONTROL_PLAY);
				break;

			case KeyEvent.KEYCODE_MEDIA_PAUSE:
				intent.setAction(MediaPlaybackService.ACTION_PAUSE);
				startServiceSafely(intent);
				fireRemoteControl(REMOTE_CONTROL_PAUSE);
				break;

			case KeyEvent.KEYCODE_MEDIA_STOP:
				intent.setAction(MediaPlaybackService.ACTION_STOP);
				startServiceSafely(intent);
				fireRemoteControl(REMOTE_CONTROL_STOP);
				break;

			case KeyEvent.KEYCODE_MEDIA_NEXT:
				fireRemoteControl(REMOTE_CONTROL_NEXT);
				break;

			case KeyEvent.KEYCODE_MEDIA_PREVIOUS:
				fireRemoteControl(REMOTE_CONTROL_PREV);
				break;
		}
	}
}
