/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 *
 * MediaPlaybackService - Foreground service with Media3 ExoPlayer for audio streaming
 */
package ti.audiostream;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.Drawable;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.support.v4.media.MediaBrowserCompat;
import android.support.v4.media.MediaDescriptionCompat;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;
import androidx.core.content.FileProvider;
import androidx.media.MediaBrowserServiceCompat;
import androidx.media.app.NotificationCompat.MediaStyle;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;


import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Pattern;

import org.json.JSONArray;
import org.json.JSONObject;

@OptIn(markerClass = UnstableApi.class)
public class MediaPlaybackService extends MediaBrowserServiceCompat
{
	private static final String LCAT = "AudiostreamService";
	private static final String CHANNEL_ID = "audiostream_media";
	private static final int NOTIFICATION_ID = 10062;

	// Service actions
	public static final String ACTION_SET_STREAM = "ti.audiostream.SET_STREAM";
	public static final String ACTION_PLAY_PAUSE = "ti.audiostream.PLAY_PAUSE";
	public static final String ACTION_PLAY = "ti.audiostream.PLAY";
	public static final String ACTION_PAUSE = "ti.audiostream.PAUSE";
	public static final String ACTION_STOP = "ti.audiostream.STOP";
	public static final String ACTION_SET_METADATA = "ti.audiostream.SET_METADATA";
	public static final String ACTION_SET_AUTO_UPDATE_METADATA = "ti.audiostream.SET_AUTO_UPDATE_METADATA";
	public static final String ACTION_SET_METADATA_RULES = "ti.audiostream.SET_METADATA_RULES";
	public static final String ACTION_SET_AUTOMOTIVE_STATIONS = "ti.audiostream.SET_AUTOMOTIVE_STATIONS";
	public static final String ACTION_SET_CURRENT_AUTOMOTIVE_STATION = "ti.audiostream.SET_CURRENT_AUTOMOTIVE_STATION";
	public static final String ACTION_NEXT = "ti.audiostream.NEXT";
	public static final String ACTION_PREV = "ti.audiostream.PREV";

	// Intent extras
	public static final String EXTRA_URL = "url";
	public static final String EXTRA_IS_LIVE = "isLive";
	public static final String EXTRA_TITLE = "title";
	public static final String EXTRA_ARTIST = "artist";
	public static final String EXTRA_ARTWORK_URL = "artworkUrl";
	public static final String EXTRA_AUTO_UPDATE_METADATA = "autoUpdateMetadata";
	public static final String EXTRA_METADATA_RULES = "metadataRules";
	public static final String EXTRA_AUTOMOTIVE_STATIONS = "automotiveStations";
	public static final String EXTRA_CURRENT_AUTOMOTIVE_STATION = "currentAutomotiveStation";
	public static final String EXTRA_HARD_STOP = "hardStop";
	private static final String PREFS_NAME = "ti.audiostream.automotive";
	private static final String PREF_AUTOMOTIVE_STATIONS = "stations";
	private static final String PREF_CURRENT_AUTOMOTIVE_STATION = "currentStation";
	private static final String ROOT_ID = "ROOT";
	// Dedicated root the car requests (via EXTRA_RECENT) to offer resume-on-connect: it
	// must expose exactly ONE playable item — the last station — not the full browse list.
	private static final String RESUMPTION_ROOT_ID = "__recent__";
	private static final String RESUME_MEDIA_ID = "__resume__";

	        // Media3 ExoPlayer
	        private ExoPlayer player;
	static volatile boolean foregroundActive = false;
	private static volatile boolean hardStopPending = false;
	private static long nextHardStopMarker;
	private static final java.util.Set<Long> pendingHardStopMarkers = new java.util.HashSet<>();
	private static final String EXTRA_HARD_STOP_MARKER = "ti.audiostream.hardStopMarker";
	private int lastStartId;
	static boolean isForegroundReady() { return foregroundActive && !hardStopPending; }
	private boolean playbackRequested = false;
	private boolean playbackFailed = false;
	private volatile boolean serviceDestroyed = false;
	private boolean controlsVisible = false;
	private boolean sessionPublishedToSystemUi = false;
	private boolean playlistPending = false;
	private final AtomicLong playbackGeneration = new AtomicLong(0);
	private String receivedTitle = "", receivedArtist = "";
	private Bitmap receivedArtwork;
	private static final String COMMAND_TOKEN = java.util.UUID.randomUUID().toString();
	private static final String EXTRA_COMMAND_TOKEN = "ti.audiostream.commandToken";
	static synchronized Intent authorizeCommand(Intent intent) {
		if (ACTION_STOP.equals(intent.getAction()) && intent.getBooleanExtra(EXTRA_HARD_STOP, false)) {
			long marker = ++nextHardStopMarker;
			pendingHardStopMarkers.add(marker);
			hardStopPending = true;
			intent.putExtra(EXTRA_HARD_STOP_MARKER, marker);
		}
		return intent.putExtra(EXTRA_COMMAND_TOKEN, COMMAND_TOKEN);
	}
	static synchronized void releaseHardStopRequest(Intent intent) {
		long marker = intent.getLongExtra(EXTRA_HARD_STOP_MARKER, 0);
		if (marker != 0) pendingHardStopMarkers.remove(marker);
		hardStopPending = !pendingHardStopMarkers.isEmpty();
	}

	private final android.content.BroadcastReceiver noisyReceiver = new android.content.BroadcastReceiver() {
		@Override public void onReceive(Context context, Intent intent) {
			if (AudioManager.ACTION_AUDIO_BECOMING_NOISY.equals(intent.getAction())) pause();
		}
	};
	        // Whether the HTTP data source follows cross-protocol redirects (HTTPS<->HTTP).
	        // Default true for parity with iOS/AVPlayer and browsers (needed by CDNs like
	        // radiojar that redirect an HTTPS entry URL to an HTTP edge node). Apps that want
	        // strict transport can set it false via the module's allowCrossProtocolRedirects
	        // property; read when the player is built, so set it before the first play.
	        static volatile boolean sAllowCrossProtocolRedirects = true;
	        private String currentUrl;
		private String currentMimeType;
		private static final class PlaybackSource {
			final String url;
			final String mimeType;
			PlaybackSource(String url, String mimeType) { this.url = url; this.mimeType = mimeType; }
		}
	        private boolean isLive = true;
	        private boolean autoUpdateMetadata = true;
	        private boolean resumeOnFocusGain = false;
		// Audio Focus
	private AudioManager audioManager;
	private AudioFocusRequest audioFocusRequest;
	private boolean hasAudioFocus = false;

	// MediaSession (using compat for notification compatibility)
	private MediaSessionCompat mediaSession;
	private String currentTitle = "";
	private String currentArtist = "";
	private Bitmap currentArtwork = null;
	// Android Auto reads album art by content:// URI (it ignores http and caches embedded
	// bitmaps), so we cache each cover to a file and expose it through a FileProvider.
	private android.net.Uri currentArtworkUri = null;
	private final Map<String, Bitmap> artworkCache = java.util.Collections.synchronizedMap(new java.util.LinkedHashMap<String, Bitmap>(8, 0.75f, true) {
		@Override protected boolean removeEldestEntry(Map.Entry<String, Bitmap> entry) { return size() > 8; }
	});
	private final Map<Bitmap, android.net.Uri> bitmapUris = java.util.Collections.synchronizedMap(new java.util.WeakHashMap<Bitmap, android.net.Uri>());
	private final Map<String, android.net.Uri> catalogArtwork = new HashMap<>();
	private final Map<String, Long> catalogArtworkRetryAfter = new HashMap<>();
	private final java.util.Set<String> catalogArtworkPending = new java.util.HashSet<>();
	private final long serviceCreatedAt = System.currentTimeMillis();
	private Bitmap publishedArtwork;
	private android.net.Uri publishedArtworkUri;
	private final java.util.Set<android.net.Uri> publishedArtworkUris = new java.util.concurrent.CopyOnWriteArraySet<>();
	private final AtomicLong artworkFileCounter = new AtomicLong(0);
	// System controls may read metadata artwork without first opening the browser.
	// Grants are limited to this image URI and these installed media consumers.
	private static final String[] SYSTEM_ARTWORK_READERS = {
		"com.android.systemui", "com.google.android.projection.gearhead",
		"com.android.car.media", "com.google.android.carassistant",
		"com.google.android.googlequicksearchbox"
	};
	private final java.util.Set<String> browserClients = new java.util.concurrent.CopyOnWriteArraySet<>();
	private Bitmap transparentArtwork = null;
	private Bitmap appIconBitmap = null;
	private boolean sessionHadArtwork = false;
	private final AtomicLong artworkGeneration = new AtomicLong(0);
	private final AtomicLong autoMetadataGeneration = new AtomicLong(0);
	// Bumped on every stream change so a late playlist resolution can't clobber a newer stream
	private final AtomicLong streamGeneration = new AtomicLong(0);
	private String lastEmittedTitle = null;
	private String lastEmittedArtist = null;
	private String lastEmittedArtwork = null;

	// onEvents() state: both onMediaMetadataChanged and onMetadata collect state,
	// onEvents() emits exactly once per batch with complete data.
	private boolean metadataDirty = false;
	private String pendingArtworkUrl = null;
	private java.util.Map<String, Object> pendingRawData = null;

	// Reconnection
	private int retryCount = 0;
	private static final int MAX_RETRIES = 5;
	private static final long RETRY_DELAY_MS = 3000;
	private Future<?> pendingReconnectTask = null;

	// Executor for background tasks
	private ExecutorService executor;
	private Handler mainHandler;
	private final ExecutorService playlistExecutor = Executors.newSingleThreadExecutor();
	private Future<?> playlistTask;
	private HttpURLConnection playlistConnection;
	private final Object playlistConnectionLock = new Object();

	// Metadata rules for regex-based cleanup
	private static class MetadataRule {
		final Pattern pattern;
		final String replace;

		MetadataRule(Pattern pattern, String replace) {
			this.pattern = pattern;
			this.replace = replace;
		}
	}
	private List<MetadataRule> titleRules;
	private List<MetadataRule> artistRules;
	private final List<JSONObject> automotiveStations = new ArrayList<>();
	private JSONObject currentAutomotiveStation;

	// Audio focus listener
	private final AudioManager.OnAudioFocusChangeListener audioFocusListener = focusChange -> {
		if (serviceDestroyed) return;
		switch (focusChange) {
			case AudioManager.AUDIOFOCUS_GAIN:
				hasAudioFocus = true;
				if (player != null) {
					player.setVolume(1.0f);
					if (resumeOnFocusGain && playbackRequested) {
						resumeOnFocusGain = false;
						play();
					}
				}
				break;
			case AudioManager.AUDIOFOCUS_LOSS:
				hasAudioFocus = false;
				pause();
				break;
			case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
				hasAudioFocus = false;
				if (player != null) {
					resumeOnFocusGain = playbackRequested;
					cancelPendingReconnect();
					player.pause();
					if (controlsVisible) {
						updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
						AudiostreamModule.fireState("paused");
						updateNotification();
					}
				}
				break;
			case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
				if (player != null) player.setVolume(0.2f);
				break;
		}
		AudiostreamModule.fireAudioFocusChange(focusChange);
	};
		// Media3 Player listener
	private Player.Listener playerListener;
	private Player.Listener createPlayerListener(final long generation)
	{
		return new Player.Listener() {
		@Override
		public void onPlaybackStateChanged(int playbackState)
		{
			if (this != playerListener || serviceDestroyed || generation != streamGeneration.get() || playlistPending) return;
			if (!controlsVisible || (playbackFailed && playbackState == Player.STATE_IDLE)) return;
			switch (playbackState) {
				case Player.STATE_BUFFERING:
					if (!playbackRequested || !hasAudioFocus) return;
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Player state: BUFFERING");
					updatePlaybackState(PlaybackStateCompat.STATE_BUFFERING);
					AudiostreamModule.fireState("buffering");
					break;

				case Player.STATE_READY:
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Player state: READY");
					if (player != null && playbackRequested && hasAudioFocus && player.isPlaying()) {
						updatePlaybackState(PlaybackStateCompat.STATE_PLAYING);
						AudiostreamModule.fireState("playing");
					}
					break;

				case Player.STATE_ENDED:
					playbackRequested = false;
					resumeOnFocusGain = false;
					resetRetryLogic();
					abandonAudioFocus();
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Player state: ENDED");
					updatePlaybackState(PlaybackStateCompat.STATE_STOPPED);
					AudiostreamModule.fireState("stopped");
					break;

				                                case Player.STATE_IDLE:

				                                        if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Player state: IDLE");

				                                        updatePlaybackState(PlaybackStateCompat.STATE_STOPPED);

				                                        AudiostreamModule.fireState("stopped");

				                                        break;

				
			}
		}

		@Override
		public void onIsPlayingChanged(boolean isPlaying)
		{
			if (this != playerListener || serviceDestroyed || generation != streamGeneration.get() || playlistPending) return;
			if (!controlsVisible || playbackFailed) {
				return;
			}
			if (isPlaying) {
				if (!playbackRequested || !hasAudioFocus) return;
				sessionPublishedToSystemUi = true;
				resetRetryLogic();
				updatePlaybackState(PlaybackStateCompat.STATE_PLAYING);
				if (mediaSession != null && !mediaSession.isActive()) mediaSession.setActive(true);
				AudiostreamModule.fireState("playing");
			} else {
				int state = player != null ? player.getPlaybackState() : Player.STATE_IDLE;
				if (state != Player.STATE_IDLE && state != Player.STATE_ENDED && state != Player.STATE_BUFFERING) {
					updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
					AudiostreamModule.fireState("paused");
				}
			}
			updateNotification();
		}
				@Override
		public void onPlayerError(PlaybackException error)
		{
			if (this != playerListener || serviceDestroyed || generation != streamGeneration.get() || playlistPending) return;
			if (!playbackRequested) return;
			playbackFailed = true;
			DiagnosticLog.e(LCAT, "Player error (" + error.errorCode + "): " + error.getClass().getSimpleName());
			
			updatePlaybackState(PlaybackStateCompat.STATE_ERROR);
			AudiostreamModule.fireState("error");
			AudiostreamModule.fireError("Stream error: " + error.getMessage());

			boolean isTerminalError = isTerminalPlaybackError(error);

			if (isTerminalError) {
				playbackRequested = false;
				DiagnosticLog.w(LCAT, "Terminal source error detected. Stopping player but keeping notification controls.");

				// REFINEMENT: Stop player but DO NOT kill the service/notification
				resetRetryLogic();
				abandonAudioFocus();
				if (player != null) {
					player.stop();
				}
				updatePlaybackState(PlaybackStateCompat.STATE_ERROR);
				updateNotification(); // Ensure "Play" icon is shown
			} else {
				attemptReconnect();
			}
		}

				@Override
				public void onMediaMetadataChanged(androidx.media3.common.MediaMetadata mediaMetadata)
				{
					if (this != playerListener || serviceDestroyed || generation != streamGeneration.get() || playlistPending) return;
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "onMediaMetadataChanged triggered");
					boolean changed = false;
					String incomingTitle = mediaMetadata.title != null ? mediaMetadata.title.toString() : null;
					String incomingArtist = null;
					if (mediaMetadata.artist != null) {
						incomingArtist = mediaMetadata.artist.toString();
					} else if (mediaMetadata.albumArtist != null) {
						incomingArtist = mediaMetadata.albumArtist.toString();
					}

					// When Media3 delivers "Artist - Title - Suffix" only in title, parse like iOS.
					if (incomingTitle != null) {
						if ((incomingArtist == null || incomingArtist.isEmpty()) && incomingTitle.contains(" - ")) {
							if (parseStreamTitle(incomingTitle)) {
								changed = true;
							}
						} else {
							String cleanedTitle = applyRules(titleRules, incomingTitle);
							if (!cleanedTitle.equals(receivedTitle)) {
								receivedTitle = cleanedTitle;
								changed = true;
							}
						}
					}

					if (incomingArtist != null && !incomingArtist.isEmpty()) {
						String cleanedArtist = applyRules(artistRules, incomingArtist);
						if (!cleanedArtist.equals(receivedArtist)) {
							receivedArtist = cleanedArtist;
							changed = true;
						}
					}

					// Intelligence: Extract artwork from stream if available
					if (mediaMetadata.artworkData != null) {
						try {
							if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.i(LCAT, "Artwork data found in stream! Updating notification icon.");
							byte[] data = mediaMetadata.artworkData;
							receivedArtwork = decodeArtwork(new java.io.ByteArrayInputStream(data));
							changed = true;
						} catch (Exception e) {
							DiagnosticLog.e(LCAT, "Failed to decode artwork from stream: " + e.getClass().getSimpleName());
						}
					}

					// Only update remote controls if auto-update is enabled
					if (changed && autoUpdateMetadata) {
						publishReceivedMetadata();
						updateNotification();
					}
					
					// Create a RICH raw map with everything Media3 found
					java.util.Map<String, Object> rawData = new java.util.HashMap<>();
					if (mediaMetadata.title != null) rawData.put("title", mediaMetadata.title.toString());
					if (mediaMetadata.artist != null) rawData.put("artist", mediaMetadata.artist.toString());
					if (mediaMetadata.albumTitle != null) rawData.put("album", mediaMetadata.albumTitle.toString());
					if (mediaMetadata.artworkData != null) rawData.put("has_artwork", true);
					if (mediaMetadata.displayTitle != null) rawData.put("displayTitle", mediaMetadata.displayTitle.toString());
					
						if (changed) {
							metadataDirty = true;
							if (pendingRawData == null) {
								pendingRawData = new java.util.HashMap<>(rawData);
							} else {
								pendingRawData.putAll(rawData);
							}
						}
					}
		
				@Override
				public void onMetadata(androidx.media3.common.Metadata metadata) {
					if (this != playerListener || serviceDestroyed || generation != streamGeneration.get() || playlistPending) return;
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "onMetadata received (" + metadata.length() + " entries)");
					boolean changed = false;
					java.util.Map<String, Object> rawData = new java.util.HashMap<>();

					for (int i = 0; i < metadata.length(); i++) {
						androidx.media3.common.Metadata.Entry entry = metadata.get(i);

						// Collect raw data for debugging (using values.get(0) to avoid deprecation warnings)
						if (entry instanceof androidx.media3.extractor.metadata.id3.TextInformationFrame) {
							androidx.media3.extractor.metadata.id3.TextInformationFrame frame = (androidx.media3.extractor.metadata.id3.TextInformationFrame) entry;
							String value = (frame.values != null && !frame.values.isEmpty()) ? frame.values.get(0) : "";
							rawData.put(frame.id, value);
							if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata or error event processed");
						} else if (entry instanceof androidx.media3.extractor.metadata.icy.IcyInfo) {
							androidx.media3.extractor.metadata.icy.IcyInfo frame = (androidx.media3.extractor.metadata.icy.IcyInfo) entry;
							rawData.put("ICY_TITLE", frame.title);
							rawData.put("ICY_URL", frame.url);
							if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata or error event processed");
							if (frame.url != null) if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata or error event processed");
						} else if (entry instanceof androidx.media3.extractor.metadata.id3.CommentFrame) {
							androidx.media3.extractor.metadata.id3.CommentFrame frame = (androidx.media3.extractor.metadata.id3.CommentFrame) entry;
							rawData.put("COMM_" + frame.description, frame.text);
							if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata or error event processed");
						} else {
							rawData.put(entry.getClass().getSimpleName(), entry.toString());
							if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata or error event processed");
						}

						// 1. Check for standard ICY info (Shoutcast/Icecast)
						if (entry instanceof androidx.media3.extractor.metadata.icy.IcyInfo) {
							androidx.media3.extractor.metadata.icy.IcyInfo icy = (androidx.media3.extractor.metadata.icy.IcyInfo) entry;
							String streamTitle = icy.title;
							if (streamTitle != null && !streamTitle.isEmpty()) {
								if (parseStreamTitle(streamTitle)) changed = true;
							}

							// Check if ICY_URL contains an artwork URL (Radio Paradise, etc.)
							String artworkUrl = icy.url;
							if (artworkUrl != null && !artworkUrl.isEmpty()) {
								if (artworkUrl.contains(".jpg") || artworkUrl.contains(".jpeg") ||
									artworkUrl.contains(".png") || artworkUrl.contains(".gif") ||
									artworkUrl.contains(".webp")) {
									if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.i(LCAT, "Found artwork URL in ICY_URL: " + artworkUrl);
									pendingArtworkUrl = artworkUrl;
								}
							}
							}
						// 2. Check for ID3 Text Frames (TIT2, etc)
						else if (entry instanceof androidx.media3.extractor.metadata.id3.TextInformationFrame) {
							androidx.media3.extractor.metadata.id3.TextInformationFrame textFrame = (androidx.media3.extractor.metadata.id3.TextInformationFrame) entry;
							String value = (textFrame.values != null && !textFrame.values.isEmpty()) ? textFrame.values.get(0) : "";
							if ("TIT2".equals(textFrame.id)) {
								receivedTitle = applyRules(titleRules, value);
								changed = true;
							} else if ("TPE1".equals(textFrame.id)) {
								receivedArtist = applyRules(artistRules, value);
								changed = true;
							} else {
                                // Deep inspect other text frames for embedded JSON/StreamTitle
                                if (value != null && value.contains("StreamTitle='")) {
                                    if (parseStreamTitle(value)) changed = true;
                                }
                            }
						}
						// 3. Check for ID3 Comment Frames (COMM) - This is where Global Player hides metadata
						else if (entry instanceof androidx.media3.extractor.metadata.id3.CommentFrame) {
							androidx.media3.extractor.metadata.id3.CommentFrame commFrame = (androidx.media3.extractor.metadata.id3.CommentFrame) entry;
							if (commFrame.text != null && commFrame.text.contains("StreamTitle='")) {
								if (parseStreamTitle(commFrame.text)) changed = true;
							}
						}
					}

					if (changed || pendingArtworkUrl != null) {
						if (autoUpdateMetadata) {
							publishReceivedMetadata();
							updateNotification();
						}
						metadataDirty = true;
						if (pendingRawData == null) {
							pendingRawData = new java.util.HashMap<>(rawData);
						} else {
							pendingRawData.putAll(rawData);
						}
					}
				}

				@Override
				public void onEvents(Player player, Player.Events events) {
					if (this != playerListener || serviceDestroyed || generation != streamGeneration.get() || playlistPending) return;
					if (!metadataDirty) return;

					metadataDirty = false;
					String artworkUrl = pendingArtworkUrl;
					java.util.Map<String, Object> rawData = pendingRawData;
					pendingArtworkUrl = null;
					pendingRawData = null;

					emitMetadataIfChanged(artworkUrl, rawData);

					if (artworkUrl != null && autoUpdateMetadata) {
						fetchArtworkFromUrl(artworkUrl, artworkGeneration.incrementAndGet());
					}
				}

				private boolean parseStreamTitle(String rawText) {
					String title = rawText;
					String artist = "";
					
					// If it looks like the custom JSON/StreamTitle format: StreamTitle='...';
					if (rawText.contains("StreamTitle='")) {
						int start = rawText.indexOf("StreamTitle='");
						if (start != -1) {
							start += 13; // Length of StreamTitle='
							int end = rawText.indexOf("';", start);
							if (end != -1) {
								title = rawText.substring(start, end);
								if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata or error event processed");
							}
						}
					}

					// Keep parity with iOS parsing:
					// "Artist - Title - Single" -> artist=Artist, title=Title
					String[] parts = title.split(" - ");
					if (parts.length >= 2) {
						artist = parts[0].trim();
						title = parts[1].trim();
					}

					// Apply metadata rules (user-defined regex transformations)
					title = applyRules(titleRules, title);
					artist = applyRules(artistRules, artist);

					boolean changed = false;
					if (!title.equals(receivedTitle)) {
						receivedTitle = title;
						changed = true;
					}
					if (!artist.isEmpty() && !artist.equals(receivedArtist)) {
						receivedArtist = artist;
						changed = true;
					}
					return changed;
				}
		};
	}

	@Override
	public void onCreate()
	{
		super.onCreate();
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Service created");

		executor = Executors.newFixedThreadPool(3);
		androidx.core.content.ContextCompat.registerReceiver(this, noisyReceiver,
			new android.content.IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
			androidx.core.content.ContextCompat.RECEIVER_NOT_EXPORTED);
		mainHandler = new Handler(Looper.getMainLooper());
		audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

		ensureNotificationChannel();
		initializePlayer();
		initializeMediaSession();
		loadPersistedAutomotiveData();

		// Android Auto: expose session token so browser clients can control playback
		setSessionToken(mediaSession.getSessionToken());

		// If a station was restored, publish its metadata in a paused/ready state so a car that
		// reconnects sees the last station ready to resume before playback is even requested.
		if (currentUrl != null && !currentUrl.isEmpty()) {
			updateMediaSessionMetadata();
			updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
		}
	}

	private void initializePlayer()
	{
		// Identify as a media player — NOT a browser, and NOT the bare Android/Dalvik default.
		// SHOUTcast DNAS serves its HTML status page to browser-style User-Agents (Mozilla/...),
		// and some CDNs (e.g. Live365) reject the default "Dalvik/..." UA with HTTP 403. A
		// media-player UA satisfies both — this is what lets iOS "just work" with AVPlayer and
		// removes any need for "/;" URL rewriting on our side.
		// Follow cross-protocol redirects (HTTPS<->HTTP). ExoPlayer rejects them by default and
		// reports the 3xx as a fatal "Response code: 302" error. Many radio CDNs (e.g. radiojar,
		// which redirects an HTTPS entry URL to a tokenized HTTP edge node) rely on this, and it
		// is what browsers and iOS/AVPlayer do — so this brings Android to parity.
		DefaultHttpDataSource.Factory httpFactory = new DefaultHttpDataSource.Factory()
			.setUserAgent("ti.audiostream (Android) ExoPlayerLib/" + androidx.media3.common.MediaLibraryInfo.VERSION)
			.setAllowCrossProtocolRedirects(sAllowCrossProtocolRedirects);
		DefaultMediaSourceFactory mediaSourceFactory = new DefaultMediaSourceFactory(this)
			.setDataSourceFactory(httpFactory);
		player = new ExoPlayer.Builder(this)
			.setMediaSourceFactory(mediaSourceFactory)
			.build();
		player.setWakeMode(androidx.media3.common.C.WAKE_MODE_NETWORK);
		playerListener = createPlayerListener(streamGeneration.get());
		player.addListener(playerListener);
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Media3 ExoPlayer initialized");
	}

	private boolean isSystemUiController() {
		return mediaSession != null && "com.android.systemui".equals(
			mediaSession.getCurrentControllerInfo().getPackageName());
	}

	private void rememberSystemUiPlayRequest() {
		if (isSystemUiController()) sessionPublishedToSystemUi = true;
	}

	@SuppressWarnings("deprecation")
	private void initializeMediaSession()
	{
		mediaSession = new MediaSessionCompat(this, LCAT);
		mediaSession.setFlags(
			MediaSessionCompat.FLAG_HANDLES_MEDIA_BUTTONS |
			MediaSessionCompat.FLAG_HANDLES_TRANSPORT_CONTROLS
		);

		mediaSession.setCallback(new MediaSessionCompat.Callback() {
			@Override
			public void onPlay()
			{
				if (serviceDestroyed) return;
				rememberSystemUiPlayRequest();
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PLAY);
				play();
			}

			@Override
			public void onPause()
			{
				if (serviceDestroyed) return;
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PAUSE);
				pause();
			}

			@Override
			public void onStop()
			{
				if (serviceDestroyed) return;
				// This new token has no SystemUI card yet. Its normal loading notification
				// uses an explicit Pause action; an unsolicited SystemUI Stop still belongs
				// to the retired card. Explicit SystemUI resume/play grants control immediately.
				if (playbackRequested && !sessionPublishedToSystemUi && isSystemUiController()) {
					DiagnosticLog.d(LCAT, "Ignored stale SystemUI stop for unpublished session");

					return;
				}

				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_STOP);
				stop();
			}

			@Override
			public void onSkipToNext()
			{
				if (serviceDestroyed) return;
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_NEXT);
				// App JS not running (e.g. launched from the car)? Advance natively.
				if (!AudiostreamModule.hasRemoteControlListeners()) {
					playAdjacentAutomotiveStation(1);
				}
			}

			@Override
			public void onSkipToPrevious()
			{
				if (serviceDestroyed) return;
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PREV);
				if (!AudiostreamModule.hasRemoteControlListeners()) {
					playAdjacentAutomotiveStation(-1);
				}
			}

			@Override
			public void onPlayFromMediaId(String mediaId, Bundle extras)
			{
				if (serviceDestroyed) return;
				rememberSystemUiPlayRequest();
				if (RESUME_MEDIA_ID.equals(mediaId)) {
					if (currentAutomotiveStation != null && playAutomotiveStation(currentAutomotiveStation, true)) {
						return;
					}
				}

				JSONObject station = findAutomotiveStation(mediaId);
				if (station != null && playAutomotiveStation(station, true)) {
					return;
				}

				if ("CURRENT_STREAM".equals(mediaId)) {
					play();
				}
			}

			@Override
			public void onPlayFromSearch(String query, Bundle extras) {
				if (serviceDestroyed) return;
				rememberSystemUiPlayRequest();
				String term = query == null ? "" : query.trim().toLowerCase(Locale.ROOT);
				if (term.isEmpty()) { play(); return; }
				for (JSONObject station : automotiveStations) {
					String title = getStationString(station, "title", getStationString(station, "stationName", ""));
					if (title.toLowerCase(Locale.ROOT).contains(term)) {
						playAutomotiveStation(station, true);
						return;
					}
				}
				AudiostreamModule.fireError("No matching station for voice search");
			}

			@Override
			public void onPrepare()
			{
				if (serviceDestroyed) return;
				if (playbackRequested) return; // A resumption probe must not overwrite active playback.
				// Resumption handshake: publish the last station's metadata in a paused, ready
				// state so the car shows it. We deliberately do NOT pre-buffer here — the async
				// ExoPlayer prepare would flip the session to BUFFERING (a spinner on the head
				// unit) with nothing to correct it; the stream is prepared lazily on actual play.
				if (currentUrl == null || currentUrl.isEmpty()) {
					seedPlaybackFieldsFromStation(currentAutomotiveStation);
				}
				if (currentUrl != null && !currentUrl.isEmpty()) {
					updateMediaSessionMetadata();
					updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
				}
			}

			@Override
			public void onPrepareFromMediaId(String mediaId, Bundle extras)
			{
				if (serviceDestroyed) return;
				JSONObject station = RESUME_MEDIA_ID.equals(mediaId)
					? currentAutomotiveStation
					: findAutomotiveStation(mediaId);
				if (station == null || getStationString(station, "streamUrl", "").isEmpty()) {
					return;
				}
				currentAutomotiveStation = station;
				playbackRequested = false;
				streamGeneration.incrementAndGet();
				cancelPlaylistResolution();
				playlistPending = false;
				resetRetryLogic();
				abandonAudioFocus();
				if (player != null) {
					if (playerListener != null) player.removeListener(playerListener);
					player.stop();
					player.clearMediaItems();
				}
				seedPlaybackFieldsFromStation(station);
				resetMetadataEventDedup();
				persistCurrentAutomotiveStation();
				long artworkVersion = artworkGeneration.incrementAndGet();
				currentArtwork = null;
				String artworkUrl = normalizeArtworkUrl(getStationString(station, "artwork", null));
				if (artworkUrl != null) loadArtworkAsync(artworkUrl, artworkVersion);
				// Metadata + paused state only; the stream is prepared lazily on play (see onPrepare).
				updateMediaSessionMetadata();
				updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
				AudiostreamModule.fireState("paused");
				updateNotification();
			}
		});

		mediaSession.setActive(false);
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "MediaSession initialized");
	}

	@Override
	public int onStartCommand(Intent intent, int flags, int startId)
	{
		lastStartId = startId;
		if (intent == null) {
			DiagnosticLog.w(LCAT, "Service started with null intent");
			return START_NOT_STICKY;
		}

		String action = intent.getAction();
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "onStartCommand: " + action);

		if (action == null) {
			return START_STICKY;
		}

		// The browser/session remains exported for Android Auto. Configuration intents
		// require the process-private capability; external transport uses MediaSession.
		if (action.startsWith("ti.audiostream.") && !COMMAND_TOKEN.equals(intent.getStringExtra(EXTRA_COMMAND_TOKEN))) {
			DiagnosticLog.w(LCAT, "Rejected unauthorized service command");
			if (!foregroundActive) stopSelf(startId);
			return START_NOT_STICKY;
		}
		switch (action) {
			case ACTION_SET_STREAM:
				handleSetStream(intent);
				break;

			case ACTION_PLAY_PAUSE:
				if (playbackRequested) pause(); else play();
				break;

			case ACTION_PLAY:
				play();
				break;

			case ACTION_PAUSE:
				pause();
				break;

			case ACTION_STOP:
				handleStop(intent);
				break;

			case ACTION_SET_METADATA:
				handleSetMetadata(intent);
				break;
			case ACTION_SET_AUTO_UPDATE_METADATA:
				handleSetAutoUpdateMetadata(intent);
				break;

			case ACTION_SET_METADATA_RULES:
				handleSetMetadataRules(intent);
				break;

			case ACTION_SET_AUTOMOTIVE_STATIONS:
				handleSetAutomotiveStations(intent);
				break;

			case ACTION_SET_CURRENT_AUTOMOTIVE_STATION:
				handleSetCurrentAutomotiveStation(intent);
				break;

			case ACTION_NEXT:
				if (!AudiostreamModule.hasRemoteControlListeners()) playAdjacentAutomotiveStation(1);
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_NEXT);
				break;

			case ACTION_PREV:
				if (!AudiostreamModule.hasRemoteControlListeners()) playAdjacentAutomotiveStation(-1);
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PREV);
				break;
		}

		return START_STICKY;
	}

	private void handleSetStream(Intent intent)
	{
		currentUrl = intent.getStringExtra(EXTRA_URL);
		currentMimeType = null;
		isLive = intent.getBooleanExtra(EXTRA_IS_LIVE, true);
		autoUpdateMetadata = intent.getBooleanExtra(EXTRA_AUTO_UPDATE_METADATA, true);
		long generation = artworkGeneration.incrementAndGet();
		currentArtwork = null;

		if (currentUrl == null || currentUrl.isEmpty()) {
			DiagnosticLog.e(LCAT, "No URL provided");
			return;
		}

		// The current card represents the previous item. During a host selection
		// expose the loading notification until this item actually starts playing.
		sessionPublishedToSystemUi = false;
		if (mediaSession != null && mediaSession.isActive()) {
			mediaSession.setActive(false);
		}

		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Setting stream: " + currentUrl + " (live: " + isLive + ", autoUpdateMetadata: " + autoUpdateMetadata + ")");
		resetMetadataEventDedup();

			// Check if metadata (title, artist, artwork) are provided in setStream
			String title = intent.getStringExtra(EXTRA_TITLE);
			String artist = intent.getStringExtra(EXTRA_ARTIST);
			String artworkUrl = normalizeArtworkUrl(intent.getStringExtra(EXTRA_ARTWORK_URL));

			if (title != null || artist != null || artworkUrl != null) {
				if (title == null) title = "";
				if (artist == null) artist = "";

			currentTitle = title;
			currentArtist = artist;

			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata or error event processed");

				// Always clear previous artwork first when switching streams.
				currentArtwork = null;

				// Handle artwork (if valid and non-empty after normalization).
				if (artworkUrl != null) {
					loadArtworkAsync(artworkUrl, generation);
				}

				updateMediaSessionMetadata();
				updateNotification();
		}

		updateMediaSessionMetadata();
		updateNotification();

		// Handle metadataRules if present in setStream intent
		if (intent.hasExtra(EXTRA_METADATA_RULES)) {
			handleSetMetadataRules(intent);
		}

		resetRetryLogic();

		preparePlayback();
	}

	/**
	 * Prepare playback for the current URL. SHOUTcast/Icecast playlist files (.pls/.m3u)
	 * are resolved to the underlying audio URL on a background thread, because ExoPlayer
	 * only parses .m3u8 (HLS) natively — it treats .pls/.m3u as raw audio and fails.
	 * HTTP URLs are also probed for extensionless playlists before Media3 preparation.
	 */
	private void preparePlayback()
	{
		final String requested = currentUrl;
		if (requested == null || requested.isEmpty()) {
			return;
		}
		final long generation = streamGeneration.incrementAndGet();
		cancelPlaylistResolution();
		playlistPending = true;
		if (player != null) {
			if (playerListener != null) player.removeListener(playerListener);
			player.stop();
			player.clearMediaItems();
		}

		if ((requested.startsWith("http://") || requested.startsWith("https://")) && !isNativeAudioUrl(requested)) {
			playlistPending = true;
			// Source resolution is part of loading, even before Media3 has a media item.
			if (playbackRequested && controlsVisible) {
				updatePlaybackState(PlaybackStateCompat.STATE_BUFFERING);
				AudiostreamModule.fireState("buffering");
			}
			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Resolving playlist URL: " + requested);
			playlistTask = playlistExecutor.submit(() -> {
				if (generation != streamGeneration.get() || Thread.currentThread().isInterrupted()) return;
				PlaybackSource resolved = resolvePlaylist(requested);
				final boolean ok = resolved != null;
				final String playUrl = ok ? resolved.url : requested;
				final String mimeType = ok ? resolved.mimeType : null;
				mainHandler.post(() -> {
					if (serviceDestroyed || streamGeneration.get() != generation) {
						if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Ignoring stale playlist resolution for: " + requested);
						return;
					}
					if (ok) {
						if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.i(LCAT, "Playlist resolved to: " + playUrl);
					} else {
						DiagnosticLog.e(LCAT, "Could not resolve playlist, trying original URL: " + requested);
					}
					playlistPending = false;
					currentUrl = playUrl;
					currentMimeType = mimeType;
					setMediaItemAndPrepare(playUrl);
				});
			});
		} else {
			playlistPending = false;
			currentMimeType = requested.toLowerCase(Locale.ROOT).split("[?#]", 2)[0].endsWith(".m3u8") ? androidx.media3.common.MimeTypes.APPLICATION_M3U8 : null;
			setMediaItemAndPrepare(requested);
		}
	}

	private void cancelPlaylistResolution() {
		if (playlistTask != null) { playlistTask.cancel(true); playlistTask = null; }
		HttpURLConnection connection;
		synchronized (playlistConnectionLock) {
			connection = playlistConnection;
			playlistConnection = null;
		}
		if (connection != null) connection.disconnect();
	}

	private boolean isNativeAudioUrl(String url) {
		try {
			String path = new java.net.URI(url).getPath().toLowerCase(Locale.ROOT);
			return path.matches(".*\\.(mp3|aac|aacp|m4a|mp4|ogg|oga|opus|wav|flac|m3u8)$");
		} catch (Exception ignored) { return false; }
	}

	private void setMediaItemAndPrepare(String url)
	{
		if (player == null || url == null || url.isEmpty()) {
			return;
		}
		if (playerListener != null) player.removeListener(playerListener);
		playerListener = createPlayerListener(streamGeneration.get());
		player.addListener(playerListener);
		MediaItem.Builder itemBuilder = new MediaItem.Builder().setUri(url);
		if (currentMimeType != null) {
			itemBuilder.setMimeType(currentMimeType);
		}
		MediaItem mediaItem = itemBuilder.build();
		if (!playbackRequested || !hasAudioFocus) player.pause(); // stop() retains PlayWhenReady.
		player.setMediaItem(mediaItem);
		player.prepare();
		if (playbackRequested && hasAudioFocus) player.play();
	}

	/**
	 * True when the URL points to a .pls or .m3u playlist file. .m3u8 is deliberately
	 * excluded — it is HLS and handled natively by ExoPlayer. Query strings are ignored.
	 */
	private boolean isPlaylistUrl(String url)
	{
		if (url == null) {
			return false;
		}
		try {
			String path = new java.net.URI(url).getPath().toLowerCase(Locale.ROOT);
			return path.endsWith(".pls") || path.endsWith(".m3u");
		} catch (Exception ignored) { return false; }
	}

	/**
	 * Download a .pls/.m3u playlist and return the first audio stream URL it references,
	 * or null if it could not be fetched or parsed. Runs on a background thread.
	 */
	private PlaybackSource resolvePlaylist(String urlString)
	{
		HttpURLConnection connection = null;
		try {
			URL url = new URL(urlString);
			connection = (HttpURLConnection) url.openConnection();
			synchronized (playlistConnectionLock) {
				if (Thread.currentThread().isInterrupted()) return null;
				playlistConnection = connection;
			}
			connection.setConnectTimeout(5000);
			connection.setReadTimeout(8000);
			connection.setInstanceFollowRedirects(true);
			connection.setRequestProperty("User-Agent", "ti.audiostream (Android)");
			connection.connect();
			String type = connection.getContentType();
			if (type != null) type = type.toLowerCase(Locale.ROOT);
			boolean playlistType = type != null && (type.contains("mpegurl") || type.contains("scpls") || type.contains("text/"));
			if (!isPlaylistUrl(urlString) && !playlistType) return new PlaybackSource(urlString, null);

			String text;
			try (InputStream input = connection.getInputStream()) { text = readPlaylistBody(input); }
			// HLS can use .m3u too: preserve the manifest URL and let Media3 parse it.
			if (text.contains("#EXT-X-")) return new PlaybackSource(connection.getURL().toString(), androidx.media3.common.MimeTypes.APPLICATION_M3U8);
			String entry = parsePlaylist(text);
			if (entry == null) return null;
			URL resolved = new URL(connection.getURL(), entry);
			String protocol = resolved.getProtocol();
			return "http".equals(protocol) || "https".equals(protocol) ? new PlaybackSource(resolved.toString(), null) : null;
		} catch (Exception e) {
			if (!serviceDestroyed && !Thread.currentThread().isInterrupted())
				DiagnosticLog.e(LCAT, "Error resolving playlist: " + e.getClass().getSimpleName());
			return null;
		} finally {
			synchronized (playlistConnectionLock) {
				if (playlistConnection == connection) playlistConnection = null;
			}
			if (connection != null) {
				connection.disconnect();
			}
		}
	}

	private String readPlaylistBody(InputStream input) throws java.io.IOException {
		ByteArrayOutputStream body = new ByteArrayOutputStream();
		byte[] buffer = new byte[8192];
		int count;
		while ((count = input.read(buffer)) != -1) {
			if (body.size() + count > 262144) throw new java.io.IOException("Playlist exceeds 256 KB");
			body.write(buffer, 0, count);
		}
		return new String(body.toByteArray(), java.nio.charset.StandardCharsets.UTF_8);
	}

	/**
	 * Extract the first stream URL from playlist text. Supports PLS ("FileN=URL") and
	 * M3U (first non-comment URL line).
	 */
	private String parsePlaylist(String body)
	{
		if (body == null || body.contains("#EXT-X-")) return null;
		if (body.startsWith("\uFEFF")) body = body.substring(1);
		String[] lines = body.split("\\r?\\n");
		boolean isPls = body.trim().toLowerCase(Locale.ROOT).startsWith("[playlist]")
			|| (!body.contains("#EXTM3U") && Pattern.compile("(?mi)^\\s*File[0-9]+\\s*=").matcher(body).find());
		// PLS: FileN=http://...
		for (String raw : lines) {
			String line = raw.trim();
			if (isPls && line.matches("(?i)File[0-9]+\\s*=.*")) {
				int eq = line.indexOf('=');
				if (eq > 0) {
					String value = line.substring(eq + 1).trim();
					if (!value.isEmpty()) {
						return value;
					}
				}
			}
		}
		if (isPls) return null;
		// M3U: first non-comment URL line (query parameters may contain =).
		for (String raw : lines) {
			String line = raw.trim();
			if (line.isEmpty() || line.startsWith("#")) {
				continue;
			}
			if (!line.startsWith("[") && !line.contains("<") && !line.matches(".*\\s.*")) {
				return line;
			}
		}
		return null;
	}

	private void handleSetMetadata(Intent intent)
	{
		if (intent.hasExtra(EXTRA_TITLE)) currentTitle = intent.getStringExtra(EXTRA_TITLE);
		if (intent.hasExtra(EXTRA_ARTIST)) currentArtist = intent.getStringExtra(EXTRA_ARTIST);
		if (currentTitle == null) currentTitle = "";
		if (currentArtist == null) currentArtist = "";
		if (intent.hasExtra(EXTRA_ARTWORK_URL)) {
			long generation = artworkGeneration.incrementAndGet();
			String artworkUrl = normalizeArtworkUrl(intent.getStringExtra(EXTRA_ARTWORK_URL));
			currentArtwork = null;
			if (artworkUrl != null) loadArtworkAsync(artworkUrl, generation);
		}
		updateMediaSessionMetadata();
		updateNotification();
	}

	private void handleSetAutoUpdateMetadata(Intent intent)
	{
		boolean value = intent.getBooleanExtra(EXTRA_AUTO_UPDATE_METADATA, true);
		autoUpdateMetadata = value;
		autoMetadataGeneration.incrementAndGet();
		receivedArtwork = null;
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Auto-update metadata set to: " + autoUpdateMetadata);
	}

	private void handleSetMetadataRules(Intent intent)
	{
		String jsonStr = intent.getStringExtra(EXTRA_METADATA_RULES);

		if (jsonStr == null || jsonStr.isEmpty()) {
			titleRules = null;
			artistRules = null;
			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata rules cleared");
			return;
		}

		try {
			JSONObject json = new JSONObject(jsonStr);

			if (json.has("title")) {
				JSONArray arr = json.getJSONArray("title");
				titleRules = new ArrayList<>();
				for (int i = 0; i < arr.length(); i++) {
					JSONObject rule = arr.getJSONObject(i);
					Pattern pattern = Pattern.compile(rule.getString("match"));
					titleRules.add(new MetadataRule(pattern, rule.getString("replace")));
				}
			} else {
				titleRules = null;
			}

			if (json.has("artist")) {
				JSONArray arr = json.getJSONArray("artist");
				artistRules = new ArrayList<>();
				for (int i = 0; i < arr.length(); i++) {
					JSONObject rule = arr.getJSONObject(i);
					Pattern pattern = Pattern.compile(rule.getString("match"));
					artistRules.add(new MetadataRule(pattern, rule.getString("replace")));
				}
			} else {
				artistRules = null;
			}

			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Metadata rules set: title=" + (titleRules != null ? titleRules.size() : 0)
				+ ", artist=" + (artistRules != null ? artistRules.size() : 0));
		} catch (Exception e) {
			DiagnosticLog.e(LCAT, "Failed to parse metadata rules: " + e.getClass().getSimpleName());
			titleRules = null;
			artistRules = null;
		}
	}

	private SharedPreferences getAutomotivePreferences()
	{
		return getSharedPreferences(PREFS_NAME, MODE_PRIVATE);
	}

	private void loadPersistedAutomotiveData()
	{
		SharedPreferences prefs = getAutomotivePreferences();
		restoreAutomotiveStations(prefs.getString(PREF_AUTOMOTIVE_STATIONS, ""));
		restoreCurrentAutomotiveStation(prefs.getString(PREF_CURRENT_AUTOMOTIVE_STATION, ""));
	}

	private void persistAutomotiveStations()
	{
		SharedPreferences prefs = getAutomotivePreferences();
		JSONArray array = new JSONArray();
		for (JSONObject station : automotiveStations) {
			array.put(station);
		}
		prefs.edit().putString(PREF_AUTOMOTIVE_STATIONS, array.toString()).apply();
	}

	private void persistCurrentAutomotiveStation()
	{
		SharedPreferences prefs = getAutomotivePreferences();
		prefs.edit().putString(PREF_CURRENT_AUTOMOTIVE_STATION,
			currentAutomotiveStation != null ? currentAutomotiveStation.toString() : "").apply();
	}

	private void restoreAutomotiveStations(String json)
	{
		automotiveStations.clear();
		if (json == null || json.isEmpty()) {
			return;
		}

		try {
			JSONArray array = new JSONArray(json);
			for (int i = 0; i < array.length(); i++) {
				JSONObject station = array.optJSONObject(i);
				if (station != null) {
					automotiveStations.add(station);
				}
			}
		} catch (Exception e) {
			DiagnosticLog.e(LCAT, "Failed to restore automotive stations: " + e.getClass().getSimpleName());
		}
	}

	private void restoreCurrentAutomotiveStation(String json)
	{
		currentAutomotiveStation = null;
		if (json == null || json.isEmpty()) {
			return;
		}

		try {
			currentAutomotiveStation = new JSONObject(json);
			// Rehydrate the scalar playback fields from the persisted station so a bare onPlay /
			// onPrepare after the service is recreated (car reconnects, JS not alive) resumes the
			// last station instead of doing nothing (currentUrl would otherwise be null).
			if (currentUrl == null || currentUrl.isEmpty()) {
				seedPlaybackFieldsFromStation(currentAutomotiveStation);
			}
		} catch (Exception e) {
			DiagnosticLog.e(LCAT, "Failed to restore current automotive station: " + e.getClass().getSimpleName());
		}
	}

	/**
	 * Populate the scalar playback fields (url/live/title/artist) from a station WITHOUT touching
	 * the player. Lets a bare onPlay/onPrepare from the car resume the last station after the
	 * service was recreated. Mirrors the field-setting half of playAutomotiveStation().
	 */
	private void seedPlaybackFieldsFromStation(JSONObject station)
	{
		if (station == null) {
			return;
		}
		String streamUrl = getStationString(station, "streamUrl", null);
		if (streamUrl == null || streamUrl.isEmpty()) {
			return;
		}
		currentUrl = streamUrl;
		currentMimeType = null;
		isLive = getStationBoolean(station, "isLive", true);
		currentTitle = getStationString(station, "title", getStationString(station, "programName", localized("ti_audiostream_live_stream", "Live Stream")));
		currentArtist = getStationString(station, "artist", getStationString(station, "stationName", getStationString(station, "subtitle", "")));
	}

	private void handleSetAutomotiveStations(Intent intent)
	{
		String json = intent.getStringExtra(EXTRA_AUTOMOTIVE_STATIONS);
		restoreAutomotiveStations(json);
		persistAutomotiveStations();
		notifyChildrenChanged(ROOT_ID);
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Automotive stations updated: " + automotiveStations.size());
	}

	private void handleSetCurrentAutomotiveStation(Intent intent)
	{
		String json = intent.getStringExtra(EXTRA_CURRENT_AUTOMOTIVE_STATION);
		restoreCurrentAutomotiveStation(json);
		persistCurrentAutomotiveStation();
		notifyChildrenChanged(ROOT_ID);
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Current automotive station updated: " + (currentAutomotiveStation != null));
	}

	/**
	 * Resolve a module string through the host app's i18n. Titanium compiles
	 * app/i18n/<lang>/strings.xml into the app's res/values-<lang>/ti_i18n_strings.xml, so any
	 * key the app defines wins and the device language picks the right one; apps that define
	 * nothing get the English fallback. Keys MUST use underscores — aapt2 silently drops
	 * resource names containing dots, so "ti.audiostream.play" would never resolve.
	 */
	private String localized(String key, String fallback)
	{
		try {
			int id = getResources().getIdentifier(key, "string", getPackageName());
			return id != 0 ? getString(id) : fallback;
		} catch (Exception e) {
			return fallback;
		}
	}

	private String getStationString(JSONObject station, String key, String fallback)
	{
		if (station == null || !station.has(key)) {
			return fallback;
		}
		String value = station.optString(key, fallback);
		return value != null && !value.isEmpty() ? value : fallback;
	}

	private boolean getStationBoolean(JSONObject station, String key, boolean fallback)
	{
		if (station == null || !station.has(key)) {
			return fallback;
		}
		return station.optBoolean(key, fallback);
	}

	private JSONObject findAutomotiveStation(String mediaId)
	{
		if (mediaId == null || mediaId.isEmpty()) {
			return null;
		}

		for (JSONObject station : automotiveStations) {
			if (mediaId.equals(station.optString("id"))) {
				return station;
			}
		}

		if (currentAutomotiveStation != null && mediaId.equals(currentAutomotiveStation.optString("id"))) {
			return currentAutomotiveStation;
		}

		return null;
	}

	private Map<String, Object> jsonToMap(JSONObject json)
	{
		Map<String, Object> map = new HashMap<>();
		if (json == null) {
			return map;
		}

		JSONArray names = json.names();
		if (names == null) {
			return map;
		}

		for (int i = 0; i < names.length(); i++) {
			String key = names.optString(i, null);
			if (key == null) {
				continue;
			}

			Object value = json.opt(key);
			if (value == JSONObject.NULL) {
				map.put(key, null);
			} else {
				map.put(key, value);
			}
		}
		return map;
	}

	private boolean playAutomotiveStation(JSONObject station, boolean emitEvent)
	{
		if (station == null) {
			return false;
		}

		String streamUrl = getStationString(station, "streamUrl", null);
		if (streamUrl == null || streamUrl.isEmpty()) {
			return false;
		}

		currentAutomotiveStation = station;
		resetMetadataEventDedup();
		persistCurrentAutomotiveStation();

		currentUrl = streamUrl;
		currentMimeType = null;
		isLive = getStationBoolean(station, "isLive", true);
		currentTitle = getStationString(station, "title", getStationString(station, "programName", localized("ti_audiostream_live_stream", "Live Stream")));
		currentArtist = getStationString(station, "artist", getStationString(station, "stationName", getStationString(station, "subtitle", "")));

		long generation = artworkGeneration.incrementAndGet();
		currentArtwork = null;

		String artworkUrl = normalizeArtworkUrl(getStationString(station, "artwork", null));
		if (artworkUrl != null) {
			loadArtworkAsync(artworkUrl, generation);
		}

		updateMediaSessionMetadata();
		updateNotification();
		resetRetryLogic();

		preparePlayback();
		play();

		if (emitEvent) {
			AudiostreamModule.fireAutomotiveStationSelected(jsonToMap(station));
		}
		return true;
	}

	/**
	 * Advance to the next/previous station in the persisted Android Auto list and play it.
	 * Used when the car sends skip-next/prev but the app's JS isn't running to handle it.
	 */
	private void playAdjacentAutomotiveStation(int direction)
	{
		if (automotiveStations == null || automotiveStations.isEmpty()) {
			return;
		}

		int currentIndex = -1;
		if (currentAutomotiveStation != null) {
			String currentId = getStationString(currentAutomotiveStation, "id", null);
			if (currentId != null) {
				for (int i = 0; i < automotiveStations.size(); i++) {
					String id = getStationString(automotiveStations.get(i), "id", null);
					if (currentId.equals(id)) {
						currentIndex = i;
						break;
					}
				}
			}
		}

		int size = automotiveStations.size();
		int nextIndex = (currentIndex < 0)
			? (direction > 0 ? 0 : size - 1)
			: (((currentIndex + direction) % size) + size) % size;

		playAutomotiveStation(automotiveStations.get(nextIndex), true);
	}

	private void publishReceivedMetadata() {
		if (!autoUpdateMetadata) return;
		currentTitle = receivedTitle;
		currentArtist = receivedArtist;
		if (receivedArtwork != null) {
			artworkGeneration.incrementAndGet();
			currentArtwork = receivedArtwork;
			receivedArtwork = null;
		}
		updateMediaSessionMetadata();
	}

	private boolean isTerminalPlaybackError(PlaybackException error) {
		java.util.Set<Throwable> seen = java.util.Collections.newSetFromMap(new java.util.IdentityHashMap<Throwable, Boolean>());
		for (Throwable cause = error; cause != null && seen.add(cause); cause = cause.getCause()) {
			if (cause instanceof androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException) {
				int status = ((androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException) cause).responseCode;
				return status != 408 && status != 429 && status < 500;
			}
			if (cause instanceof javax.net.ssl.SSLHandshakeException || cause instanceof java.security.cert.CertificateException) return true;
			if (cause instanceof java.net.SocketTimeoutException || cause instanceof java.net.UnknownHostException) return false;
		}
		return error.errorCode == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS
			|| error.errorCode == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND
			|| error.errorCode == PlaybackException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE
			|| error.errorCode == PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED
			|| error.errorCode == PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED;
	}

	private String applyRules(List<MetadataRule> rules, String input)
	{
		if (rules == null || rules.isEmpty() || input == null) return input;

		String result = input;
		for (MetadataRule rule : rules) {
			try {
				result = rule.pattern.matcher(result).replaceAll(rule.replace);
			} catch (IllegalArgumentException | IndexOutOfBoundsException e) {
				DiagnosticLog.w(LCAT, "Ignoring invalid metadata replacement: " + e.getClass().getSimpleName());
			}
		}
		return result;
	}

	private String normalizeArtworkUrl(String artworkUrl)
	{
		if (artworkUrl == null) return null;
		String value = artworkUrl.trim();
		if (value.isEmpty()) return null;
		String lower = value.toLowerCase(Locale.ROOT);
		if ("null".equals(lower) || "undefined".equals(lower)) {
			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.i(LCAT, "Ignoring invalid artwork value: " + artworkUrl);
			return null;
		}
		return value;
	}

	private void resetMetadataEventDedup()
	{
		receivedTitle = "";
		receivedArtist = "";
		receivedArtwork = null;
		lastEmittedTitle = null;
		lastEmittedArtist = null;
		lastEmittedArtwork = null;
		metadataDirty = false;
		pendingArtworkUrl = null;
		pendingRawData = null;
	}

	private boolean sameString(String a, String b)
	{
		if (a == null) return b == null;
		return a.equals(b);
	}

	private void emitMetadataIfChanged(String artwork, java.util.Map<String, Object> rawData)
	{
		String title = receivedTitle != null ? receivedTitle : "";
		String artist = receivedArtist != null ? receivedArtist : "";

		if (sameString(lastEmittedTitle, title)
			&& sameString(lastEmittedArtist, artist)
			&& sameString(lastEmittedArtwork, artwork)) {
			return;
		}

		lastEmittedTitle = title;
		lastEmittedArtist = artist;
		lastEmittedArtwork = artwork;
		AudiostreamModule.fireMetadata(title, artist, artwork, rawData);
	}

	private void play()
	{
		if (player == null) return;
		// A startForegroundService request must be acknowledged even when playback is
		// already active or configuration is missing. Do this before every early exit.
		controlsVisible = true;
		playbackRequested = true;
		// SystemUI reads the session as soon as the notification appears. Publish the
		// new transport intent first, so it cannot attach using a stale STOPPED/PAUSED state.
		if (!player.isPlaying() && currentUrl != null && !currentUrl.isEmpty()) {
			updatePlaybackState(PlaybackStateCompat.STATE_BUFFERING);
		}
		if (!startForegroundWithNotification()) {
			updatePlaybackState(PlaybackStateCompat.STATE_ERROR);
			playbackRequested = false;
			controlsVisible = false;
			stopSelfResult(lastStartId);
			return;
		}
		if (currentUrl == null || currentUrl.isEmpty()) {
			playbackRequested = false;
			AudiostreamModule.fireError("No stream URL configured");
			AudiostreamModule.fireState("error");
			controlsVisible = false;
			removeNotification();
			stopSelfResult(lastStartId);
			return;
		}
		playbackRequested = true;
		playbackFailed = false;
		controlsVisible = true;
		// setStream may have begun resolving while playback was stopped or paused.
		if (playlistPending || player.getPlaybackState() == Player.STATE_BUFFERING) {
			updatePlaybackState(PlaybackStateCompat.STATE_BUFFERING);
			AudiostreamModule.fireState("buffering");
		}

		// Guard clause: If already playing, don't re-prepare or interrupt current playback
		if (player.isPlaying()) {
			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Play command ignored: Player is already playing.");
			return;
		}

		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.i(LCAT, "Play command received. URL: " + currentUrl + " (Live: " + isLive + ")");



		if (!requestAudioFocus()) {
			DiagnosticLog.w(LCAT, "Could not get audio focus");
			playbackRequested = false;
			AudiostreamModule.fireError("Could not get audio focus");
			AudiostreamModule.fireState("paused");
			updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
			removeNotification();
			return;
		}

		int state = player.getPlaybackState();
		// Intelligence: Only re-prepare if truly necessary (IDLE, ENDED, or URL changed)
		// Do NOT re-prepare if just BUFFERING or PAUSED to avoid audio repeats
		if (state == Player.STATE_IDLE || state == Player.STATE_ENDED) {
			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.i(LCAT, "Player is IDLE/ENDED, preparing source.");
			if (currentUrl != null && !currentUrl.isEmpty()) {
				if (!playlistPending) preparePlayback();
			}
		}
		// For live streams that are PAUSED/BUFFERING, just resume without re-preparing
		// This prevents "repeating" audio from cached buffers

		player.play();
	}

	private void pause()
	{
		playbackRequested = false;
		resumeOnFocusGain = false;
		resetRetryLogic();
		if (player == null) return;
		player.pause();
		if (controlsVisible) {
			updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
			AudiostreamModule.fireState("paused");
			updateNotification();
		}
	}

	private void handleStop(Intent intent)
	{
		boolean hardStop = intent != null && intent.getBooleanExtra(EXTRA_HARD_STOP, false);
		if (hardStop) {
			try { hardStop(); } finally { releaseHardStopRequest(intent); }
			return;
		}
		stop();
	}

	private void stop()
	{
		sessionPublishedToSystemUi = false;
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Soft stop: pausing playback and hiding controls");
		playbackRequested = false;
		controlsVisible = false;
		artworkGeneration.incrementAndGet();

		resumeOnFocusGain = false;
		resetRetryLogic();
		abandonAudioFocus();
		if (player != null) {
			player.pause();
		}

		updatePlaybackState(PlaybackStateCompat.STATE_STOPPED);
		AudiostreamModule.fireState("stopped");

		if (mediaSession != null) {
			mediaSession.setActive(false);
		}

		removeNotification();
	}

	private void hardStop()
	{
		sessionPublishedToSystemUi = false;
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Hard stop: tearing down playback and service");
		playbackRequested = false;
		controlsVisible = false;
		streamGeneration.incrementAndGet();
		cancelPlaylistResolution();
		playlistPending = false;
		artworkGeneration.incrementAndGet();

		resumeOnFocusGain = false;
		resetRetryLogic();
		abandonAudioFocus();
		if (player != null) {
			player.stop();
		}

		updatePlaybackState(PlaybackStateCompat.STATE_STOPPED);
		AudiostreamModule.fireState("stopped");

		if (mediaSession != null) {
			mediaSession.setActive(false);
		}

		stopForegroundService();
	}

	@SuppressWarnings("deprecation")
	private boolean requestAudioFocus()
	{
		if (audioManager == null) {
			return false;
		}

		int result;
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			AudioAttributes audioAttributes = new AudioAttributes.Builder()
				.setUsage(AudioAttributes.USAGE_MEDIA)
				.setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
				.build();

			audioFocusRequest = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
				.setAudioAttributes(audioAttributes)
				.setOnAudioFocusChangeListener(audioFocusListener)
				.setWillPauseWhenDucked(true)
				.build();

			result = audioManager.requestAudioFocus(audioFocusRequest);
		} else {
			result = audioManager.requestAudioFocus(
				audioFocusListener,
				AudioManager.STREAM_MUSIC,
				AudioManager.AUDIOFOCUS_GAIN
			);
		}

		hasAudioFocus = (result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED);
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Audio focus request: " + (hasAudioFocus ? "granted" : "denied"));
		return hasAudioFocus;
	}

	@SuppressWarnings("deprecation")
	private void abandonAudioFocus()
	{
		if (audioManager == null) {
			return;
		}

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			if (audioFocusRequest != null) {
				audioManager.abandonAudioFocusRequest(audioFocusRequest);
				audioFocusRequest = null;
			}
		} else {
			audioManager.abandonAudioFocus(audioFocusListener);
		}

		hasAudioFocus = false;
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Audio focus abandoned");
	}

	private void attemptReconnect()
	{
		if (!playbackRequested) return;
		if (retryCount >= MAX_RETRIES) {
			playbackRequested = false;
			abandonAudioFocus();
			DiagnosticLog.w(LCAT, "Max retries reached, stopping player logic");
			// Stop player but keep service so user can skip
			if (player != null) player.stop();
			updatePlaybackState(PlaybackStateCompat.STATE_ERROR);
			updateNotification();
			return;
		}

		retryCount++;
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Attempting reconnect (" + retryCount + "/" + MAX_RETRIES + ")");

		final String targetUrl = currentUrl;
		cancelPendingReconnect();
		final long generation = playbackGeneration.get();

		pendingReconnectTask = executor.submit(() -> {
			try {
				Thread.sleep(RETRY_DELAY_MS);
			} catch (InterruptedException ignored) {
				return;
			}

			mainHandler.post(() -> {
				if (playbackRequested && hasAudioFocus && playbackGeneration.get() == generation && player != null && currentUrl != null && currentUrl.equals(targetUrl)) {
					playbackFailed = false;
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Executing scheduled reconnect for: " + currentUrl);
					setMediaItemAndPrepare(currentUrl);
					player.play();
				} else {
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Scheduled reconnect aborted: URL changed or player stopped");
				}
			});
		});
	}

	private void cancelPendingReconnect()
	{
		playbackGeneration.incrementAndGet();
		if (pendingReconnectTask != null && !pendingReconnectTask.isDone()) {
			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Cancelling existing reconnect task");
			pendingReconnectTask.cancel(true);
		}
		pendingReconnectTask = null;
	}

	private void resetRetryLogic()
	{
		retryCount = 0;
		cancelPendingReconnect();
	}

	private static final int MAX_ARTWORK_SIZE = 512;

	/**
	 * Scale a bitmap down to MAX_ARTWORK_SIZE if it exceeds that dimension.
	 * Large bitmaps can exceed Binder transaction limits when passed through
	 * MediaSession metadata, causing Bluetooth AVRCP and Android Auto to
	 * silently drop the artwork.
	 */
	private static Bitmap scaleArtwork(Bitmap source)
	{
		if (source == null) {
			return null;
		}
		int w = source.getWidth();
		int h = source.getHeight();
		if (w <= MAX_ARTWORK_SIZE && h <= MAX_ARTWORK_SIZE) {
			return source;
		}
		float scale = Math.min((float) MAX_ARTWORK_SIZE / w, (float) MAX_ARTWORK_SIZE / h);
		int newW = Math.round(w * scale);
		int newH = Math.round(h * scale);
		return Bitmap.createScaledBitmap(source, newW, newH, true);
	}

	private void updateMediaSessionMetadata()
	{
		if (mediaSession == null) {
			return;
		}

		boolean hasArtwork = currentArtwork != null;
		Bitmap effectiveArtwork = currentArtwork != null ? currentArtwork : getAppIconBitmap();
		Bitmap sessionArtwork = scaleArtwork(effectiveArtwork);

		// Some OEM lock screens keep stale art unless ART/ALBUM_ART are explicitly cleared.
		// When we have no stream artwork but DO have app icon fallback, we still need to
		// clear first to force the OEM to pick up the new (fallback) bitmap.
		if (!hasArtwork && sessionHadArtwork) {
			MediaMetadataCompat.Builder clearMetadata = new MediaMetadataCompat.Builder()
				.putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
				.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist)
				.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, null)
				.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, null)
				.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, null)
				.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, "")
				.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, "")
				.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, "");

			if (isLive) {
				clearMetadata.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, -1);
			}

			mediaSession.setMetadata(clearMetadata.build());
		}

		MediaMetadataCompat.Builder metadata = new MediaMetadataCompat.Builder()
			.putString(MediaMetadataCompat.METADATA_KEY_TITLE, currentTitle)
			.putString(MediaMetadataCompat.METADATA_KEY_ARTIST, currentArtist);

		if (isLive) {
			metadata.putLong(MediaMetadataCompat.METADATA_KEY_DURATION, -1);
		}

		metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, sessionArtwork);
		metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, sessionArtwork);
		metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, sessionArtwork);
		if (effectiveArtwork != null) {
			// Android Auto caches embedded bitmaps and won't re-render on change; give it a
			// fresh content:// URI each time so the now-playing cover actually updates.
			if (publishedArtwork != effectiveArtwork || publishedArtworkUri == null) {
				publishedArtwork = effectiveArtwork;
				publishedArtworkUri = publishArtworkUri(effectiveArtwork);
			}
			android.net.Uri artUri = publishedArtworkUri;
			currentArtworkUri = artUri;
			if (artUri != null) {
				String uriString = artUri.toString();
				metadata.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, uriString);
				metadata.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, uriString);
				metadata.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, uriString);
			}
		} else if (sessionArtwork == null) {
			metadata.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, "");
			metadata.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, "");
			metadata.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, "");
		}

		mediaSession.setMetadata(metadata.build());
		sessionHadArtwork = hasArtwork;

		// NOTE: do NOT notifyChildrenChanged here. Track info travels via MediaMetadata +
		// PlaybackState, not the browse tree. Rebuilding the tree on every song made the car's
		// station list flicker / reset its scroll each time the live metadata changed. The tree
		// is only refreshed when the station list itself changes (handleSet*AutomotiveStation*).
	}

	/**
	 * Write the current cover to a private cache file and return a content:// URI for it.
	 * Android Auto ignores http artwork URIs and caches embedded bitmaps, so we hand it a
	 * fresh URI on every change and grant read access to the media browser clients.
	 */
	private void grantArtworkRead(String packageName, android.net.Uri uri) {
		try { grantUriPermission(packageName, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION); }
		catch (RuntimeException unavailable) {
			// Optional consumer absent on this device, or no longer installed.
			if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Artwork reader unavailable");
		}
	}

	private synchronized android.net.Uri publishArtworkUri(Bitmap bitmap)
	{
		if (serviceDestroyed) return null;
		if (bitmap == null) return null;
		android.net.Uri cached = bitmapUris.get(bitmap);
		if (cached != null) return cached;
		try {
			java.io.File dir = new java.io.File(getCacheDir(), "artwork");
			if (!dir.exists()) {
				dir.mkdirs();
			}
			// Unique filename (never reused across sessions) so Android Auto — which caches
			// artwork by URI — always sees a new URI and re-fetches, instead of serving a
			// stale cached image for a name reused after a restart.
			java.io.File file = new java.io.File(dir, "art_" + System.currentTimeMillis() + "_" + artworkFileCounter.incrementAndGet() + ".jpg");
			java.io.FileOutputStream out = new java.io.FileOutputStream(file);
			bitmap.compress(Bitmap.CompressFormat.JPEG, 90, out);
			out.flush();
			out.close();

			// Retain files for late readers for at least a day. Never prune an URI
			// published during this service lifetime.
			java.io.File[] existing = dir.listFiles();
			if (existing != null) for (java.io.File old : existing) {
				if (old.lastModified() < serviceCreatedAt - 86400000L) old.delete();
			}

			android.net.Uri uri = FileProvider.getUriForFile(this, getPackageName() + ".tiaudiostream.fileprovider", file);
			publishedArtworkUris.add(uri);
			bitmapUris.put(bitmap, uri);
			for (String pkg : browserClients) grantArtworkRead(pkg, uri);
			for (String pkg : SYSTEM_ARTWORK_READERS) grantArtworkRead(pkg, uri);
			return uri;
		} catch (Exception e) {
			DiagnosticLog.w(LCAT, "Could not publish artwork URI: " + e.getClass().getSimpleName());
			return null;
		}
	}

	/**
	 * Fetch artwork from a URL asynchronously (for Radio Paradise style streams)
	 */
	private Bitmap decodeArtwork(InputStream input) throws java.io.IOException {
		ByteArrayOutputStream bytes = new ByteArrayOutputStream();
		byte[] buffer = new byte[8192];
		int count;
		while ((count = input.read(buffer)) != -1) {
			if (bytes.size() + count > 8 * 1024 * 1024) throw new java.io.IOException("Artwork exceeds 8 MB");
			bytes.write(buffer, 0, count);
		}
		byte[] data = bytes.toByteArray();
		BitmapFactory.Options options = new BitmapFactory.Options();
		options.inJustDecodeBounds = true;
		BitmapFactory.decodeByteArray(data, 0, data.length, options);
		options.inSampleSize = 1;
		while (options.outWidth / options.inSampleSize > 1024 || options.outHeight / options.inSampleSize > 1024) options.inSampleSize *= 2;
		options.inJustDecodeBounds = false;
		return BitmapFactory.decodeByteArray(data, 0, data.length, options);
	}

	private Bitmap readArtwork(String url) throws java.io.IOException {
		Bitmap cached = artworkCache.get(url);
		if (cached != null) return cached;
		Bitmap bitmap;
		if (url.startsWith("http://") || url.startsWith("https://")) {
			HttpURLConnection connection = (HttpURLConnection) new URL(url).openConnection();
			connection.setConnectTimeout(5000);
			connection.setReadTimeout(8000);
			try (InputStream input = connection.getInputStream()) { bitmap = decodeArtwork(input); }
			finally { connection.disconnect(); }
		} else {
			InputStream asset;
			try { asset = getAssets().open("Resources/" + url); }
			catch (java.io.IOException missing) { asset = getAssets().open(url); }
			try (InputStream input = asset) { bitmap = decodeArtwork(input); }
		}
		if (bitmap != null) artworkCache.put(url, bitmap);
		return bitmap;
	}

	private android.net.Uri getCatalogArtwork(String url) {
		android.net.Uri cached = catalogArtwork.get(url);
		if (cached != null) return cached;
		long now = android.os.SystemClock.elapsedRealtime();
		Long retryAfter = catalogArtworkRetryAfter.get(url);
		if ((retryAfter == null || now >= retryAfter) && catalogArtworkPending.add(url)) executor.execute(() -> {
			android.net.Uri loaded = null;
			try { loaded = publishArtworkUri(readArtwork(url)); }
			catch (Exception e) { DiagnosticLog.w(LCAT, "Could not load catalog artwork"); }
			final android.net.Uri uri = loaded;
			mainHandler.post(() -> {
				// Exact URL identity prevents obsolete completions changing another row.
				catalogArtworkPending.remove(url);
				if (serviceDestroyed) return;
				if (uri != null) {
					catalogArtwork.put(url, uri);
					catalogArtworkRetryAfter.remove(url);
					notifyChildrenChanged(ROOT_ID);
					notifyChildrenChanged(RESUMPTION_ROOT_ID);
				} else {
					// A later browse may retry. Do not notify here: that would refetch
					// failed URLs endlessly as the browser responds to our own refresh.
					catalogArtworkRetryAfter.put(url, android.os.SystemClock.elapsedRealtime() + 30000L);
				}
			});
		});
		return publishArtworkUri(getAppIconBitmap());
	}

	private void fetchArtworkFromUrl(String urlString, long expectedGeneration) {
		loadArtworkAsync(urlString, expectedGeneration, true, autoMetadataGeneration.get());
	}

	private boolean isArtworkRequestCurrent(long generation, boolean automatic, long metadataGeneration) {
		return artworkGeneration.get() == generation && (!automatic
			|| (autoUpdateMetadata && autoMetadataGeneration.get() == metadataGeneration));
	}

	private void clearFailedArtwork(long generation) {
		clearFailedArtwork(generation, false, 0);
	}

	private void clearFailedArtwork(long generation, boolean automatic, long metadataGeneration) {
		mainHandler.post(() -> {
			if (!isArtworkRequestCurrent(generation, automatic, metadataGeneration)) return;
			currentArtwork = null;
			updateMediaSessionMetadata();
			updateNotification();
		});
	}

	private void updatePlaybackState(int state)
	{
		if (mediaSession == null) {
			return;
		}

		long position = player != null ? player.getCurrentPosition() : 0;
		float speed = (state == PlaybackStateCompat.STATE_PLAYING) ? 1.0f : 0.0f;

		long actions =
			PlaybackStateCompat.ACTION_PLAY |
			PlaybackStateCompat.ACTION_PAUSE |
			PlaybackStateCompat.ACTION_STOP |
			PlaybackStateCompat.ACTION_PLAY_PAUSE |
			PlaybackStateCompat.ACTION_PLAY_FROM_SEARCH |
			PlaybackStateCompat.ACTION_PLAY_FROM_MEDIA_ID |
			PlaybackStateCompat.ACTION_PREPARE |
			PlaybackStateCompat.ACTION_PREPARE_FROM_MEDIA_ID;

		// Only advertise skip when there's more than one station to move between; otherwise a
		// voice/UI "next" has nowhere to go and the car shows dead skip buttons.
		if (automotiveStations.size() > 1) {
			actions |= PlaybackStateCompat.ACTION_SKIP_TO_NEXT | PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS;
		}

		PlaybackStateCompat playbackState = new PlaybackStateCompat.Builder()
			.setState(state, position, speed)
			.setActions(actions)
			.build();

		mediaSession.setPlaybackState(playbackState);
	}

	private void loadArtworkAsync(String artworkUrl, long expectedGeneration) {
		loadArtworkAsync(artworkUrl, expectedGeneration, false, 0);
	}

	private void loadArtworkAsync(String artworkUrl, long expectedGeneration, boolean automatic, long metadataGeneration)
	{
		executor.execute(() -> {
			if (!isArtworkRequestCurrent(expectedGeneration, automatic, metadataGeneration)) return;
			try {
				Bitmap bitmap = readArtwork(artworkUrl);
				// Compress and write files on the worker; MediaSession publication reuses this URI.
				publishArtworkUri(bitmap);
				mainHandler.post(() -> {
					if (!isArtworkRequestCurrent(expectedGeneration, automatic, metadataGeneration)) return;
					currentArtwork = bitmap;
					updateMediaSessionMetadata();
					updateNotification();
				});
			} catch (Exception e) {
				DiagnosticLog.w(LCAT, "Could not load artwork");
				clearFailedArtwork(expectedGeneration, automatic, metadataGeneration);
			}
		});
	}

	private boolean startForegroundWithNotification()
	{
		Notification notification = buildNotification();
		try {
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				ServiceCompat.startForeground(
					this,
					NOTIFICATION_ID,
					notification,
					ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
				);
			} else {
				startForeground(NOTIFICATION_ID, notification);
			}
			foregroundActive = true;
			return true;
		} catch (Exception e) {
			// Android 12+/14 can refuse to start a foreground service from the background
			// (ForegroundServiceStartNotAllowedException). A failed startForeground means playback
			// won't run, so surface it instead of silently swallowing it.
			DiagnosticLog.e(LCAT, "Failed to start foreground: " + e.getClass().getSimpleName());
			AudiostreamModule.fireError("Cannot start playback service: " + e.getMessage());
			AudiostreamModule.fireState("error");
			foregroundActive = false;
			return false;
		}
	}

	private void updateNotification()
	{
		if (!controlsVisible) return;
		NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
		if (manager != null) {
			manager.notify(NOTIFICATION_ID, buildNotification());
		}
	}

	private Bitmap getTransparentArtwork()
	{
		// Some OEM lock screens (e.g. OPPO/ColorOS) keep stale artwork when largeIcon is null.
		// We force-replace it with a transparent 1x1 bitmap for now.
		if (transparentArtwork == null || transparentArtwork.isRecycled()) {
			transparentArtwork = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
		}
		return transparentArtwork;
	}

	private static final int APP_ICON_SIZE = 512;

	private Bitmap getAppIconBitmap()
	{
		if (appIconBitmap == null || appIconBitmap.isRecycled()) {
			try {
				Drawable d = getPackageManager().getApplicationIcon(getPackageName());
				if (d != null) {
					appIconBitmap = Bitmap.createBitmap(APP_ICON_SIZE, APP_ICON_SIZE, Bitmap.Config.ARGB_8888);
					Canvas canvas = new Canvas(appIconBitmap);
					d.setBounds(0, 0, APP_ICON_SIZE, APP_ICON_SIZE);
					d.draw(canvas);
					if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.i(LCAT, "App icon loaded: " + APP_ICON_SIZE + "x" + APP_ICON_SIZE);
				}
			} catch (Exception e) {
				DiagnosticLog.w(LCAT, "Could not load app icon: " + e.getClass().getSimpleName());
			}
		}
		return appIconBitmap;
	}

	private Notification buildNotification()
	{
		int smallIcon = getResources().getIdentifier("appicon", "drawable", getPackageName());
		if (smallIcon == 0) {
			smallIcon = android.R.drawable.ic_media_play;
		}

		Bitmap largeIcon = currentArtwork != null ? currentArtwork : (getAppIconBitmap() != null ? getAppIconBitmap() : getTransparentArtwork());

		NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
			.setContentTitle(currentTitle)
			.setContentText(currentArtist)
			.setSmallIcon(smallIcon)
			.setLargeIcon(largeIcon)
			.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
			.setOnlyAlertOnce(true)
			.setOngoing(playbackRequested)
			.addAction(buildAction(android.R.drawable.ic_media_previous, localized("ti_audiostream_previous", "Previous"), ACTION_PREV))
			.addAction(playbackRequested
				? buildAction(android.R.drawable.ic_media_pause, localized("ti_audiostream_pause", "Pause"), ACTION_PAUSE)
				: buildAction(android.R.drawable.ic_media_play, localized("ti_audiostream_play", "Play"), ACTION_PLAY))
			.addAction(buildAction(android.R.drawable.ic_media_next, localized("ti_audiostream_next", "Next"), ACTION_NEXT));

		// A token-less MediaStyle is still classified as a media card by SystemUI.
		// Keep the loading notification ordinary until the session owns playing audio.
		if (mediaSession != null && mediaSession.isActive()) {
			MediaStyle mediaStyle = new MediaStyle()
				.setShowActionsInCompactView(0, 1, 2);
			mediaStyle.setMediaSession(mediaSession.getSessionToken());
			builder.setStyle(mediaStyle);
		}

		Intent launchIntent = getPackageManager().getLaunchIntentForPackage(getPackageName());
		if (launchIntent != null) {
			launchIntent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED);
			PendingIntent contentIntent = PendingIntent.getActivity(this, 0, launchIntent, pendingIntentFlags());
			builder.setContentIntent(contentIntent);
		}

		return builder.build();
	}

	private NotificationCompat.Action buildAction(int icon, String title, String action)
	{
		Intent intent = new Intent(this, MediaActionReceiver.class);
		intent.setAction(action);
		PendingIntent pendingIntent = PendingIntent.getBroadcast(
			this,
			action.hashCode(),
			intent,
			pendingIntentFlags()
		);
		return new NotificationCompat.Action(icon, title, pendingIntent);
	}

	private void removeNotification()
	{
		foregroundActive = false;
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Removing playback notification");
		ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE);
		NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
		if (manager != null) {
			manager.cancel(NOTIFICATION_ID);
		}
	}

	private void stopForegroundService()
	{
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Stopping foreground service");
		removeNotification();
		// stopSelf() discards newer commands already queued by ActivityManager. The
		// startId check keeps this instance alive for immediate setStream()/play().
		stopSelfResult(lastStartId);
	}

	private void ensureNotificationChannel()
	{
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
			if (manager != null && manager.getNotificationChannel(CHANNEL_ID) == null) {
				NotificationChannel channel = new NotificationChannel(
					CHANNEL_ID,
					localized("ti_audiostream_channel_name", "Audio Streaming"),
					NotificationManager.IMPORTANCE_LOW
				);
				channel.setDescription(localized("ti_audiostream_channel_description", "Audio streaming playback controls"));
				channel.setShowBadge(false);
				manager.createNotificationChannel(channel);
			}
		}
	}

	private int pendingIntentFlags()
	{
		int flags = PendingIntent.FLAG_UPDATE_CURRENT;
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			flags |= PendingIntent.FLAG_IMMUTABLE;
		}
		return flags;
	}

	// --- Android Auto: MediaBrowserServiceCompat ---

	@Nullable
	@Override
	public BrowserRoot onGetRoot(@NonNull String clientPackageName, int clientUid, @Nullable Bundle rootHints)
	{
		// Remember who browses us (Android Auto, Assistant, ...) so we can grant them read
		// access to the artwork content:// URI. Grant the current one to a late-joining client.
		if (clientPackageName != null) {
			browserClients.add(clientPackageName);
			for (android.net.Uri uri : publishedArtworkUris) {
				grantArtworkRead(clientPackageName, uri);
			}
		}

		// Resume-on-connect: when the car asks for the recents root (EXTRA_RECENT) and we have a
		// last station, hand back a dedicated root that exposes exactly one playable item, so the
		// car offers "resume last station" on its media launcher.
		if (rootHints != null && rootHints.getBoolean(BrowserRoot.EXTRA_RECENT) && currentAutomotiveStation != null) {
			Bundle extras = new Bundle();
			extras.putBoolean(BrowserRoot.EXTRA_RECENT, true);
			return new BrowserRoot(RESUMPTION_ROOT_ID, extras);
		}

		return new BrowserRoot(ROOT_ID, null);
	}

	/** Build the single "resume last station" playable item shown for resume-on-connect. */
	private MediaBrowserCompat.MediaItem buildResumeItem()
	{
		MediaDescriptionCompat.Builder resume = new MediaDescriptionCompat.Builder()
			.setMediaId(RESUME_MEDIA_ID)
			.setTitle(localized("ti_audiostream_resume_last_station", "Resume last station"))
			.setSubtitle(getStationString(currentAutomotiveStation, "title",
				getStationString(currentAutomotiveStation, "stationName", localized("ti_audiostream_last_station", "Last station"))));

		String resumeArtwork = getStationString(currentAutomotiveStation, "artwork", null);
		if (resumeArtwork != null && !resumeArtwork.isEmpty()) {
			resume.setIconUri(getCatalogArtwork(resumeArtwork));
		}

		return new MediaBrowserCompat.MediaItem(resume.build(), MediaBrowserCompat.MediaItem.FLAG_PLAYABLE);
	}

	@Override
	public void onLoadChildren(@NonNull String parentId, @NonNull Result<List<MediaBrowserCompat.MediaItem>> result)
	{
		List<MediaBrowserCompat.MediaItem> items = new ArrayList<>();

		// Recents root: exactly one playable item — the last station — for resume-on-connect.
		if (RESUMPTION_ROOT_ID.equals(parentId)) {
			if (currentAutomotiveStation != null) {
				items.add(buildResumeItem());
			}
			result.sendResult(items);
			return;
		}

		if (ROOT_ID.equals(parentId) && currentAutomotiveStation != null) {
			items.add(buildResumeItem());
		}

		if (ROOT_ID.equals(parentId) && !automotiveStations.isEmpty()) {
			for (JSONObject station : automotiveStations) {
				String stationId = getStationString(station, "id", null);
				String title = getStationString(station, "title",
					getStationString(station, "programName", getStationString(station, "stationName", localized("ti_audiostream_live_stream", "Live Stream"))));
				String subtitle = getStationString(station, "subtitle",
					getStationString(station, "stationName", getStationString(station, "artist", "")));

				if (stationId == null || stationId.isEmpty()) {
					continue;
				}

				MediaDescriptionCompat.Builder desc = new MediaDescriptionCompat.Builder()
					.setMediaId(stationId)
					.setTitle(title)
					.setSubtitle(subtitle);

				String artworkUrl = getStationString(station, "artwork", null);
				if (artworkUrl != null && !artworkUrl.isEmpty()) {
					desc.setIconUri(getCatalogArtwork(artworkUrl));
				}

				items.add(new MediaBrowserCompat.MediaItem(desc.build(),
					MediaBrowserCompat.MediaItem.FLAG_PLAYABLE));
			}
		}

		if (ROOT_ID.equals(parentId) && items.isEmpty() && currentUrl != null && !currentUrl.isEmpty()) {
			MediaDescriptionCompat.Builder desc = new MediaDescriptionCompat.Builder()
				.setMediaId("CURRENT_STREAM")
				.setTitle(currentTitle != null && !currentTitle.isEmpty() ? currentTitle : localized("ti_audiostream_live_stream", "Live Stream"))
				.setSubtitle(currentArtist != null ? currentArtist : "");

			Bitmap effectiveIcon = currentArtwork != null ? currentArtwork : getAppIconBitmap();
			Bitmap icon = scaleArtwork(effectiveIcon);
			if (icon != null) {
				desc.setIconBitmap(icon);
			}

			items.add(new MediaBrowserCompat.MediaItem(desc.build(),
				MediaBrowserCompat.MediaItem.FLAG_PLAYABLE));
		}

		result.sendResult(items);
	}

	@Override
	public void onDestroy()
	{
		serviceDestroyed = true;
		cancelPlaylistResolution();
		playlistExecutor.shutdownNow();
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "Service destroyed");
		foregroundActive = false;
		controlsVisible = false;
		playbackRequested = false;
		streamGeneration.incrementAndGet();
		artworkGeneration.incrementAndGet();
		unregisterReceiver(noisyReceiver);
		AudiostreamModule.fireState("stopped");
		resetRetryLogic();
		abandonAudioFocus();

		if (player != null) {
			player.removeListener(playerListener);
			player.release();
			player = null;
		}

		if (mediaSession != null) {
			mediaSession.setCallback(null);
			mediaSession.setActive(false);
			mediaSession.release();
			mediaSession = null;
		}

		if (executor != null) {
			executor.shutdown();
		}

		NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
		if (manager != null) {
			manager.cancel(NOTIFICATION_ID);
		}

		super.onDestroy();
	}

	@Override
	public void onTaskRemoved(Intent rootIntent)
	{
		if (org.appcelerator.kroll.common.TiConfig.LOGD) DiagnosticLog.d(LCAT, "App task removed - cleaning up");
		hardStop();
		super.onTaskRemoved(rootIntent);
	}

	public boolean isPlaying()
	{
		return player != null && player.isPlaying();
	}

	public static byte[] bitmapToByteArray(Bitmap bitmap)
	{
		if (bitmap == null) {
			return null;
		}
		ByteArrayOutputStream stream = new ByteArrayOutputStream();
		bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream);
		return stream.toByteArray();
	}
}
