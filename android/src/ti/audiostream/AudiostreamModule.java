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

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.List;
import java.util.Map;

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
	private static final String AUTOMOTIVE_SOURCE_ANDROID_AUTO = "androidauto";

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
	private static String lastEmittedState = null;

	public AudiostreamModule()
	{
		super();
		activeModule = this;
	}

	private void appendMetadataRule(JSONArray target, Object item) throws Exception
	{
		String match = null;
		String replace = "";

		if (item instanceof KrollDict) {
			KrollDict rule = (KrollDict) item;
			match = TiConvert.toString(rule.get("match"), null);
			replace = TiConvert.toString(rule.get("replace"), "");
		} else if (item instanceof Map) {
			Map<?, ?> rule = (Map<?, ?>) item;
			match = TiConvert.toString(rule.get("match"), null);
			replace = TiConvert.toString(rule.get("replace"), "");
		}

		if (match == null || match.isEmpty()) {
			return;
		}

		JSONObject ruleJson = new JSONObject();
		ruleJson.put("match", match);
		ruleJson.put("replace", replace);
		target.put(ruleJson);
	}

	private JSONArray serializeMetadataRulesArray(Object value) throws Exception
	{
		JSONArray result = new JSONArray();
		if (value == null) {
			return result;
		}

		if (value instanceof Object[]) {
			for (Object item : (Object[]) value) {
				appendMetadataRule(result, item);
			}
			return result;
		}

		if (value instanceof List) {
			for (Object item : (List<?>) value) {
				appendMetadataRule(result, item);
			}
			return result;
		}

		// Titanium may pass a single object instead of an array in edge cases.
		appendMetadataRule(result, value);
		return result;
	}

	private Object serializeJsonValue(Object value) throws Exception
	{
		if (value == null) {
			return JSONObject.NULL;
		}

		if (value instanceof KrollDict) {
			JSONObject json = new JSONObject();
			KrollDict dict = (KrollDict) value;
			for (String key : dict.keySet()) {
				json.put(key, serializeJsonValue(dict.get(key)));
			}
			return json;
		}

		if (value instanceof Map) {
			JSONObject json = new JSONObject();
			Map<?, ?> map = (Map<?, ?>) value;
			for (Map.Entry<?, ?> entry : map.entrySet()) {
				if (entry.getKey() == null) {
					continue;
				}
				json.put(String.valueOf(entry.getKey()), serializeJsonValue(entry.getValue()));
			}
			return json;
		}

		if (value instanceof Object[]) {
			JSONArray array = new JSONArray();
			for (Object item : (Object[]) value) {
				array.put(serializeJsonValue(item));
			}
			return array;
		}

		if (value instanceof List) {
			JSONArray array = new JSONArray();
			for (Object item : (List<?>) value) {
				array.put(serializeJsonValue(item));
			}
			return array;
		}

		if (value instanceof Boolean || value instanceof Number || value instanceof String) {
			return value;
		}

		return JSONObject.wrap(value);
	}

	private JSONArray serializeAutomotiveStationsArray(Object value) throws Exception
	{
		JSONArray result = new JSONArray();
		if (value == null) {
			return result;
		}

		if (value instanceof Object[]) {
			for (Object item : (Object[]) value) {
				Object serialized = serializeJsonValue(item);
				if (serialized instanceof JSONObject) {
					result.put(serialized);
				}
			}
			return result;
		}

		if (value instanceof List) {
			for (Object item : (List<?>) value) {
				Object serialized = serializeJsonValue(item);
				if (serialized instanceof JSONObject) {
					result.put(serialized);
				}
			}
			return result;
		}

		Object serialized = serializeJsonValue(value);
		if (serialized instanceof JSONObject) {
			result.put(serialized);
		}
		return result;
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

		if (args.containsKey("title")) {
			intent.putExtra(MediaPlaybackService.EXTRA_TITLE, TiConvert.toString(args.get("title"), ""));
		}

		if (args.containsKey("artist")) {
			intent.putExtra(MediaPlaybackService.EXTRA_ARTIST, TiConvert.toString(args.get("artist"), ""));
		}

		if (args.containsKey("artwork")) {
			intent.putExtra(MediaPlaybackService.EXTRA_ARTWORK_URL, TiConvert.toString(args.get("artwork"), ""));
		}

		// Handle metadataRules: present + KrollDict → serialize, present + null → clear, absent → preserve
		if (args.containsKey("metadataRules")) {
			Object rulesObj = args.get("metadataRules");
			if (rulesObj instanceof KrollDict || rulesObj instanceof Map) {
				try {
					JSONObject json = new JSONObject();
					Object titleRules = null;
					Object artistRules = null;
					if (rulesObj instanceof KrollDict) {
						KrollDict rulesDict = (KrollDict) rulesObj;
						if (rulesDict.containsKey("title")) titleRules = rulesDict.get("title");
						if (rulesDict.containsKey("artist")) artistRules = rulesDict.get("artist");
					} else {
						Map<?, ?> rulesMap = (Map<?, ?>) rulesObj;
						if (rulesMap.containsKey("title")) titleRules = rulesMap.get("title");
						if (rulesMap.containsKey("artist")) artistRules = rulesMap.get("artist");
					}

					if (titleRules != null) {
						json.put("title", serializeMetadataRulesArray(titleRules));
					}
					if (artistRules != null) {
						json.put("artist", serializeMetadataRulesArray(artistRules));
					}

					Log.d(LCAT, "setStream: metadataRules: " + json.toString());
					intent.putExtra(MediaPlaybackService.EXTRA_METADATA_RULES, json.toString());
				} catch (Exception e) {
					Log.e(LCAT, "setStream: failed to serialize metadataRules: " + e.getMessage());
				}
			} else {
				// null → signal clear rules
				Log.d(LCAT, "setStream: clearing metadataRules");
				intent.putExtra(MediaPlaybackService.EXTRA_METADATA_RULES, "");
			}
		}
		// Key not present → don't add the extra (rules preserved in service)

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

		if (serviceStarted) {
			// Service already in foreground — just deliver the play intent.
			// Avoids Android 12+ background startForegroundService() restriction.
			startServiceSafely(intent);
		} else {
			startForegroundServiceSafely(intent);
		}
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
	 * Soft-stop playback while keeping the stream ready for quick resume
	 */
	@Kroll.method
	public void stop(@Kroll.argument(optional = true) KrollDict args)
	{
		Log.d(LCAT, "stop");
		isPlaying = false;
		boolean hardStop = args != null && TiConvert.toBoolean(args.get("hard"), false);
		if (hardStop) {
			serviceStarted = false;
		}

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_STOP);
		intent.putExtra(MediaPlaybackService.EXTRA_HARD_STOP, hardStop);

		startServiceSafely(intent);
	}

	/**
	 * Stop playback completely, release resources, and force a fresh reconnect on next start
	 */
	@Kroll.method
	public void hardStop()
	{
		Log.d(LCAT, "hardStop");
		isPlaying = false;
		serviceStarted = false;

		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_STOP);
		intent.putExtra(MediaPlaybackService.EXTRA_HARD_STOP, true);

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
	 * Set metadata rules for automatic regex-based cleanup of stream metadata.
	 * Rules are applied after the module's built-in parsing (ICY split, "Artist - Title" split)
	 * and before updating the lock screen / notification.
	 * Pass null to clear all rules.
	 * @param args Dictionary with 'title' and/or 'artist' arrays of {match, replace} rules, or null
	 */
	@Kroll.method
	public void setMetadataRules(@Kroll.argument(optional = true) KrollDict args)
	{
		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_SET_METADATA_RULES);

		if (args == null) {
			Log.d(LCAT, "setMetadataRules: clearing rules");
			// Send empty string to signal "clear rules"
			intent.putExtra(MediaPlaybackService.EXTRA_METADATA_RULES, "");
		} else {
			try {
				JSONObject json = new JSONObject();

				if (args.containsKey("title")) {
					json.put("title", serializeMetadataRulesArray(args.get("title")));
				}

				if (args.containsKey("artist")) {
					json.put("artist", serializeMetadataRulesArray(args.get("artist")));
				}

				Log.d(LCAT, "setMetadataRules: " + json.toString());
				intent.putExtra(MediaPlaybackService.EXTRA_METADATA_RULES, json.toString());
			} catch (Exception e) {
				Log.e(LCAT, "setMetadataRules: failed to serialize rules: " + e.getMessage());
				return;
			}
		}

		startServiceSafely(intent);
	}

	@Kroll.method
	public void setAutomotiveStations(@Kroll.argument(optional = true) Object stations)
	{
		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_SET_AUTOMOTIVE_STATIONS);

		if (stations == null) {
			Log.d(LCAT, "setAutomotiveStations: clearing stations");
			intent.putExtra(MediaPlaybackService.EXTRA_AUTOMOTIVE_STATIONS, "");
			startServiceSafely(intent);
			return;
		}

		try {
			JSONArray json = serializeAutomotiveStationsArray(stations);
			Log.d(LCAT, "setAutomotiveStations: " + json.length() + " stations");
			intent.putExtra(MediaPlaybackService.EXTRA_AUTOMOTIVE_STATIONS, json.toString());
			startServiceSafely(intent);
		} catch (Exception e) {
			Log.e(LCAT, "setAutomotiveStations: failed to serialize stations: " + e.getMessage());
		}
	}

	@Kroll.method
	public void setCurrentAutomotiveStation(@Kroll.argument(optional = true) Object station)
	{
		Intent intent = new Intent(getContext(), MediaPlaybackService.class);
		intent.setAction(MediaPlaybackService.ACTION_SET_CURRENT_AUTOMOTIVE_STATION);

		if (station == null) {
			Log.d(LCAT, "setCurrentAutomotiveStation: clearing current station");
			intent.putExtra(MediaPlaybackService.EXTRA_CURRENT_AUTOMOTIVE_STATION, "");
			startServiceSafely(intent);
			return;
		}

		try {
			Object serialized = serializeJsonValue(station);
			if (!(serialized instanceof JSONObject)) {
				Log.e(LCAT, "setCurrentAutomotiveStation: station must serialize to an object");
				return;
			}
			intent.putExtra(MediaPlaybackService.EXTRA_CURRENT_AUTOMOTIVE_STATION, serialized.toString());
			startServiceSafely(intent);
		} catch (Exception e) {
			Log.e(LCAT, "setCurrentAutomotiveStation: failed to serialize station: " + e.getMessage());
		}
	}

	/**
	 * Get current playing state
	 */
	@Kroll.getProperty
	public boolean getPlaying()
	{
		return isPlaying;
	}

	/**
	 * Whether the HTTP data source follows cross-protocol redirects (HTTPS<->HTTP).
	 * Default true: parity with iOS/AVPlayer and browsers, and required by CDNs that redirect
	 * an HTTPS entry URL to an HTTP edge node (e.g. radiojar). Set false for strict transport
	 * (an https:// URL will then never be downgraded to http://). Read when the player is
	 * built, so set it before the first play().
	 */
	@Kroll.getProperty
	public boolean getAllowCrossProtocolRedirects()
	{
		return MediaPlaybackService.sAllowCrossProtocolRedirects;
	}

	@Kroll.setProperty
	public void setAllowCrossProtocolRedirects(boolean value)
	{
		MediaPlaybackService.sAllowCrossProtocolRedirects = value;
		Log.d(LCAT, "allowCrossProtocolRedirects set to " + value);
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
			fireError("Cannot start playback from background: " + e.getMessage());
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
		if (activeModule == null) {
			return;
		}

		// Update internal state regardless of listeners
		activeModule.isPlaying = "playing".equals(state);

		// Deduplicate: only emit on actual state transitions
		if (state.equals(lastEmittedState)) {
			return;
		}
		lastEmittedState = state;

		if (!activeModule.hasListeners("state")) {
			return;
		}

		KrollDict event = new KrollDict();
		event.put("state", state);
		activeModule.fireEvent("state", event);

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

	public static void fireAutomotiveStationSelected(Map<String, Object> station)
	{
		if (activeModule == null || !activeModule.hasListeners("automotivestationselected")) {
			return;
		}

		KrollDict event = new KrollDict();
		event.put("source", AUTOMOTIVE_SOURCE_ANDROID_AUTO);
		if (station != null) {
			event.put("station", new KrollDict(station));
		}
		activeModule.fireEvent("automotivestationselected", event);

		if (DBG) {
			Log.d(LCAT, "Automotive station selected event fired");
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
