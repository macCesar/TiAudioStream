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
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioManager;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.support.v4.media.MediaMetadataCompat;
import android.support.v4.media.session.MediaSessionCompat;
import android.support.v4.media.session.PlaybackStateCompat;

import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.core.app.NotificationCompat;
import androidx.core.app.ServiceCompat;
import androidx.media.app.NotificationCompat.MediaStyle;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;

import org.appcelerator.kroll.common.Log;

import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Pattern;

import org.json.JSONArray;
import org.json.JSONObject;

@OptIn(markerClass = UnstableApi.class)
public class MediaPlaybackService extends Service
{
	private static final String LCAT = "AudiostreamService";
	private static final String CHANNEL_ID = "audiostream_media";
	private static final int NOTIFICATION_ID = 10062;

	// Service actions
	public static final String ACTION_SET_STREAM = "ti.audiostream.SET_STREAM";
	public static final String ACTION_PLAY = "ti.audiostream.PLAY";
	public static final String ACTION_PAUSE = "ti.audiostream.PAUSE";
	public static final String ACTION_STOP = "ti.audiostream.STOP";
	public static final String ACTION_SET_METADATA = "ti.audiostream.SET_METADATA";
	public static final String ACTION_SET_AUTO_UPDATE_METADATA = "ti.audiostream.SET_AUTO_UPDATE_METADATA";
	public static final String ACTION_SET_METADATA_RULES = "ti.audiostream.SET_METADATA_RULES";
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
	public static final String EXTRA_HARD_STOP = "hardStop";

	        // Media3 ExoPlayer
	        private ExoPlayer player;
	        private String currentUrl;
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
	private Bitmap transparentArtwork = null;
	private boolean sessionHadArtwork = false;
	private final AtomicLong artworkGeneration = new AtomicLong(0);
	private String lastEmittedTitle = null;
	private String lastEmittedArtist = null;
	private String lastEmittedArtwork = null;

	// Reconnection
	private int retryCount = 0;
	private static final int MAX_RETRIES = 5;
	private static final long RETRY_DELAY_MS = 3000;
	private Future<?> pendingReconnectTask = null;

	// Executor for background tasks
	private ExecutorService executor;
	private Handler mainHandler;

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

	        // Audio focus listener
	        private final AudioManager.OnAudioFocusChangeListener audioFocusListener = focusChange -> {
	                switch (focusChange) {
	                        case AudioManager.AUDIOFOCUS_GAIN:
	                                Log.d(LCAT, "Audio focus gained");
	                                hasAudioFocus = true;
	                                if (player != null) {
	                                        player.setVolume(1.0f);
	                                        if (resumeOnFocusGain) {
	                                                player.play();
	                                                resumeOnFocusGain = false;
	                                        }
	                                }
	                                AudiostreamModule.fireAudioFocusChange(focusChange);
	                                break;
	
	                        case AudioManager.AUDIOFOCUS_LOSS:
	                                Log.d(LCAT, "Audio focus lost permanently");
	                                hasAudioFocus = false;
	                                resumeOnFocusGain = false;
	                                if (player != null) {
	                                        player.pause();
	                                }
	                                AudiostreamModule.fireAudioFocusChange(focusChange);
	                                break;
	
	                        case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT:
	                                Log.d(LCAT, "Audio focus lost temporarily");
	                                hasAudioFocus = false;
	                                if (player != null) {
	                                        resumeOnFocusGain = player.getPlayWhenReady();
	                                        player.pause();
	                                }
	                                AudiostreamModule.fireAudioFocusChange(focusChange);
	                                break;
	
	                        case AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK:
	                                Log.d(LCAT, "Audio focus lost - ducking");
	                                if (player != null) {
	                                        player.setVolume(0.2f);
	                                }
	                                AudiostreamModule.fireAudioFocusChange(focusChange);
	                                break;
	                }
	        };
		// Media3 Player listener
	private final Player.Listener playerListener = new Player.Listener() {
		@Override
		public void onPlaybackStateChanged(int playbackState)
		{
			switch (playbackState) {
				case Player.STATE_BUFFERING:
					Log.d(LCAT, "Player state: BUFFERING");
					updatePlaybackState(PlaybackStateCompat.STATE_BUFFERING);
					AudiostreamModule.fireState("buffering");
					break;

				case Player.STATE_READY:
					Log.d(LCAT, "Player state: READY");
					if (player != null && player.getPlayWhenReady()) {
						updatePlaybackState(PlaybackStateCompat.STATE_PLAYING);
						AudiostreamModule.fireState("playing");
					}
					break;

				case Player.STATE_ENDED:
					Log.d(LCAT, "Player state: ENDED");
					updatePlaybackState(PlaybackStateCompat.STATE_STOPPED);
					AudiostreamModule.fireState("stopped");
					break;

				                                case Player.STATE_IDLE:

				                                        Log.d(LCAT, "Player state: IDLE");

				                                        updatePlaybackState(PlaybackStateCompat.STATE_STOPPED);

				                                        AudiostreamModule.fireState("stopped");

				                                        break;

				
			}
		}

		                @Override
		                public void onIsPlayingChanged(boolean isPlaying)
		                {
		                        Log.d(LCAT, "isPlaying changed: " + isPlaying);
		                        if (isPlaying) {
		                                resetRetryLogic();
		                                updatePlaybackState(PlaybackStateCompat.STATE_PLAYING);
		                                AudiostreamModule.fireState("playing");
		                        } else {
		                                int state = player != null ? player.getPlaybackState() : Player.STATE_IDLE;
		                                // Only fire paused if we are not IDLE or ENDED (which are 'stopped')
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
			Log.e(LCAT, "Player error (" + error.errorCode + "): " + error.getMessage());
			
			updatePlaybackState(PlaybackStateCompat.STATE_ERROR);
			AudiostreamModule.fireState("error");
			AudiostreamModule.fireError("Stream error: " + error.getMessage());

			// Detect terminal errors (Source Errors)
			boolean isSourceError = 
				error.errorCode == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS ||
				error.errorCode == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND ||
				error.errorCode == PlaybackException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE ||
				error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED;

			if (isSourceError) {
				Log.w(LCAT, "Terminal source error detected. Stopping player but keeping notification controls.");
				
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
					Log.d(LCAT, "onMediaMetadataChanged triggered");
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
							if (!cleanedTitle.equals(currentTitle)) {
								currentTitle = cleanedTitle;
								changed = true;
							}
						}
					}

					if (incomingArtist != null && !incomingArtist.isEmpty()) {
						String cleanedArtist = applyRules(artistRules, incomingArtist);
						if (!cleanedArtist.equals(currentArtist)) {
							currentArtist = cleanedArtist;
							changed = true;
						}
					}

					// Intelligence: Extract artwork from stream if available
					if (mediaMetadata.artworkData != null) {
						try {
							Log.i(LCAT, "Artwork data found in stream! Updating notification icon.");
							byte[] data = mediaMetadata.artworkData;
							currentArtwork = BitmapFactory.decodeByteArray(data, 0, data.length);
							changed = true;
						} catch (Exception e) {
							Log.e(LCAT, "Failed to decode artwork from stream: " + e.getMessage());
						}
					}

					// Only update remote controls if auto-update is enabled
					if (changed && autoUpdateMetadata) {
						updateMediaSessionMetadata();
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
							Log.d(LCAT, "Firing metadata event with " + rawData.size() + " raw fields");
							emitMetadataIfChanged(null, rawData);
						}
					}
		
				@Override
				public void onMetadata(androidx.media3.common.Metadata metadata) {
					Log.d(LCAT, "onMetadata received (" + metadata.length() + " entries)");
					boolean changed = false;
					java.util.Map<String, Object> rawData = new java.util.HashMap<>();
					
					for (int i = 0; i < metadata.length(); i++) {
						androidx.media3.common.Metadata.Entry entry = metadata.get(i);

						// Collect raw data for debugging (using values.get(0) to avoid deprecation warnings)
						if (entry instanceof androidx.media3.extractor.metadata.id3.TextInformationFrame) {
							androidx.media3.extractor.metadata.id3.TextInformationFrame frame = (androidx.media3.extractor.metadata.id3.TextInformationFrame) entry;
							String value = (frame.values != null && !frame.values.isEmpty()) ? frame.values.get(0) : "";
							rawData.put(frame.id, value);
							Log.d(LCAT, "RAW ID3: " + frame.id + "=" + value);
						} else if (entry instanceof androidx.media3.extractor.metadata.icy.IcyInfo) {
							androidx.media3.extractor.metadata.icy.IcyInfo frame = (androidx.media3.extractor.metadata.icy.IcyInfo) entry;
							rawData.put("ICY_TITLE", frame.title);
							rawData.put("ICY_URL", frame.url);
							Log.d(LCAT, "RAW ICY: " + frame.title);
							if (frame.url != null) Log.d(LCAT, "RAW ICY URL: " + frame.url);
						} else if (entry instanceof androidx.media3.extractor.metadata.id3.CommentFrame) {
							androidx.media3.extractor.metadata.id3.CommentFrame frame = (androidx.media3.extractor.metadata.id3.CommentFrame) entry;
							rawData.put("COMM_" + frame.description, frame.text);
							Log.d(LCAT, "RAW COMM: " + frame.text);
						} else {
							rawData.put(entry.getClass().getSimpleName(), entry.toString());
							Log.d(LCAT, "RAW UNKNOWN: " + entry.toString());
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
									Log.i(LCAT, "Found artwork URL in ICY_URL: " + artworkUrl);
									fetchArtworkFromUrl(artworkUrl, artworkGeneration.get());
								}
							}
							}
						// 2. Check for ID3 Text Frames (TIT2, etc)
						else if (entry instanceof androidx.media3.extractor.metadata.id3.TextInformationFrame) {
							androidx.media3.extractor.metadata.id3.TextInformationFrame textFrame = (androidx.media3.extractor.metadata.id3.TextInformationFrame) entry;
							String value = (textFrame.values != null && !textFrame.values.isEmpty()) ? textFrame.values.get(0) : "";
							if ("TIT2".equals(textFrame.id)) {
								currentTitle = applyRules(titleRules, value);
								changed = true;
							} else if ("TPE1".equals(textFrame.id)) {
								currentArtist = applyRules(artistRules, value);
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

					// Emit only when title/artist actually changed to avoid duplicate UI updates.
					if (changed) {
						// Only update remote controls if auto-update is enabled
						if (autoUpdateMetadata) {
							updateMediaSessionMetadata();
							updateNotification();
						}
						emitMetadataIfChanged(null, rawData);
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
								Log.d(LCAT, "Extracted Title: " + title);
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
					if (!title.equals(currentTitle)) {
						currentTitle = title;
						changed = true;
					}
					if (!artist.isEmpty() && !artist.equals(currentArtist)) {
						currentArtist = artist;
						changed = true;
					}
					return changed;
				}
			};
	@Override
	public void onCreate()
	{
		super.onCreate();
		Log.d(LCAT, "Service created");

		executor = Executors.newSingleThreadExecutor();
		mainHandler = new Handler(Looper.getMainLooper());
		audioManager = (AudioManager) getSystemService(Context.AUDIO_SERVICE);

		ensureNotificationChannel();
		initializePlayer();
		initializeMediaSession();
	}

	private void initializePlayer()
	{
		DefaultHttpDataSource.Factory httpFactory = new DefaultHttpDataSource.Factory()
			.setUserAgent("Mozilla/5.0 (Linux; Android) AppleWebKit/537.36 (KHTML, like Gecko) Mobile Safari/537.36");
		DefaultMediaSourceFactory mediaSourceFactory = new DefaultMediaSourceFactory(this)
			.setDataSourceFactory(httpFactory);
		player = new ExoPlayer.Builder(this)
			.setMediaSourceFactory(mediaSourceFactory)
			.build();
		player.addListener(playerListener);
		Log.d(LCAT, "Media3 ExoPlayer initialized");
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
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PLAY);
				play();
			}

			@Override
			public void onPause()
			{
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PAUSE);
				pause();
			}

			@Override
			public void onStop()
			{
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_STOP);
				stop();
			}

			@Override
			public void onSkipToNext()
			{
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_NEXT);
			}

			@Override
			public void onSkipToPrevious()
			{
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PREV);
			}
		});

		mediaSession.setActive(true);
		Log.d(LCAT, "MediaSession initialized");
	}

	@Override
	public int onStartCommand(Intent intent, int flags, int startId)
	{
		if (intent == null) {
			Log.w(LCAT, "Service started with null intent");
			return START_NOT_STICKY;
		}

		String action = intent.getAction();
		Log.d(LCAT, "onStartCommand: " + action);

		if (action == null) {
			return START_STICKY;
		}

		switch (action) {
			case ACTION_SET_STREAM:
				handleSetStream(intent);
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

			case ACTION_NEXT:
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_NEXT);
				break;

			case ACTION_PREV:
				AudiostreamModule.fireRemoteControl(AudiostreamModule.REMOTE_CONTROL_PREV);
				break;
		}

		return START_STICKY;
	}

	private void handleSetStream(Intent intent)
	{
		currentUrl = intent.getStringExtra(EXTRA_URL);
		isLive = intent.getBooleanExtra(EXTRA_IS_LIVE, true);
		autoUpdateMetadata = intent.getBooleanExtra(EXTRA_AUTO_UPDATE_METADATA, true);
		long generation = artworkGeneration.incrementAndGet();

		if (currentUrl == null || currentUrl.isEmpty()) {
			Log.e(LCAT, "No URL provided");
			return;
		}

		Log.d(LCAT, "Setting stream: " + currentUrl + " (live: " + isLive + ", autoUpdateMetadata: " + autoUpdateMetadata + ")");
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

			Log.d(LCAT, "Setting metadata from setStream: " + title + " - " + artist);

				// Always clear previous artwork first when switching streams.
				currentArtwork = null;

				// Handle artwork (if valid and non-empty after normalization).
				if (artworkUrl != null) {
					loadArtworkAsync(artworkUrl, generation);
				}

				updateMediaSessionMetadata();
				updateNotification();
		}

		// Handle metadataRules if present in setStream intent
		if (intent.hasExtra(EXTRA_METADATA_RULES)) {
			handleSetMetadataRules(intent);
		}

		resetRetryLogic();

		MediaItem mediaItem = MediaItem.fromUri(currentUrl);
		player.setMediaItem(mediaItem);
		player.prepare();
	}

	private void handleSetMetadata(Intent intent)
	{
		currentTitle = intent.getStringExtra(EXTRA_TITLE);
		currentArtist = intent.getStringExtra(EXTRA_ARTIST);

		if (currentTitle == null) currentTitle = "";
		if (currentArtist == null) currentArtist = "";

		Log.d(LCAT, "Setting metadata: " + currentTitle + " - " + currentArtist);

		// Check if artwork key exists in intent
		if (intent.hasExtra(EXTRA_ARTWORK_URL)) {
			String artworkUrl = normalizeArtworkUrl(intent.getStringExtra(EXTRA_ARTWORK_URL));
			// null, empty, or whitespace-only → clear artwork
			if (artworkUrl == null) {
				currentArtwork = null;
				updateMediaSessionMetadata();
				updateNotification();
			} else {
				// Valid URL → load it
				loadArtworkAsync(artworkUrl, artworkGeneration.get());
			}
		}
		// If artwork key doesn't exist → keep current artwork (do nothing)
	}

	private void handleSetAutoUpdateMetadata(Intent intent)
	{
		boolean value = intent.getBooleanExtra(EXTRA_AUTO_UPDATE_METADATA, true);
		autoUpdateMetadata = value;
		Log.d(LCAT, "Auto-update metadata set to: " + autoUpdateMetadata);
	}

	private void handleSetMetadataRules(Intent intent)
	{
		String jsonStr = intent.getStringExtra(EXTRA_METADATA_RULES);

		if (jsonStr == null || jsonStr.isEmpty()) {
			titleRules = null;
			artistRules = null;
			Log.d(LCAT, "Metadata rules cleared");
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

			Log.d(LCAT, "Metadata rules set: title=" + (titleRules != null ? titleRules.size() : 0)
				+ ", artist=" + (artistRules != null ? artistRules.size() : 0));
		} catch (Exception e) {
			Log.e(LCAT, "Failed to parse metadata rules: " + e.getMessage());
			titleRules = null;
			artistRules = null;
		}
	}

	private String applyRules(List<MetadataRule> rules, String input)
	{
		if (rules == null || rules.isEmpty() || input == null) return input;

		String result = input;
		for (MetadataRule rule : rules) {
			result = rule.pattern.matcher(result).replaceAll(rule.replace);
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
			Log.i(LCAT, "Ignoring invalid artwork value: " + artworkUrl);
			return null;
		}
		return value;
	}

	private void resetMetadataEventDedup()
	{
		lastEmittedTitle = null;
		lastEmittedArtist = null;
		lastEmittedArtwork = null;
	}

	private boolean sameString(String a, String b)
	{
		if (a == null) return b == null;
		return a.equals(b);
	}

	private void emitMetadataIfChanged(String artwork, java.util.Map<String, Object> rawData)
	{
		String title = currentTitle != null ? currentTitle : "";
		String artist = currentArtist != null ? currentArtist : "";

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

		// Guard clause: If already playing, don't re-prepare or interrupt current playback
		if (player.isPlaying()) {
			Log.d(LCAT, "Play command ignored: Player is already playing.");
			return;
		}

		Log.i(LCAT, "Play command received. URL: " + currentUrl + " (Live: " + isLive + ")");

		if (mediaSession != null && !mediaSession.isActive()) {
			mediaSession.setActive(true);
		}

		startForegroundWithNotification();

		if (!requestAudioFocus()) {
			Log.w(LCAT, "Could not get audio focus");
			return;
		}

		int state = player.getPlaybackState();
		// Intelligence: Only re-prepare if truly necessary (IDLE, ENDED, or URL changed)
		// Do NOT re-prepare if just BUFFERING or PAUSED to avoid audio repeats
		if (state == Player.STATE_IDLE || state == Player.STATE_ENDED) {
			Log.i(LCAT, "Player is IDLE/ENDED, preparing source.");
			if (currentUrl != null && !currentUrl.isEmpty()) {
				MediaItem mediaItem = MediaItem.fromUri(currentUrl);
				player.setMediaItem(mediaItem);
				player.prepare();
			}
		}
		// For live streams that are PAUSED/BUFFERING, just resume without re-preparing
		// This prevents "repeating" audio from cached buffers

		player.play();
	}

	private void pause()
	{
		if (player == null) return;

		// Guard clause: If already paused or stopped, do nothing
		if (!player.isPlaying() && player.getPlaybackState() != Player.STATE_BUFFERING) {
			Log.d(LCAT, "Pause command ignored: Player is not playing.");
			return;
		}

		resumeOnFocusGain = false;
		player.pause();
		updateNotification();
	}

	private void handleStop(Intent intent)
	{
		boolean hardStop = intent != null && intent.getBooleanExtra(EXTRA_HARD_STOP, false);
		if (hardStop) {
			hardStop();
			return;
		}
		stop();
	}

	private void stop()
	{
		Log.d(LCAT, "Soft stop: pausing playback and hiding controls");
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
		Log.d(LCAT, "Hard stop: tearing down playback and service");
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
		Log.d(LCAT, "Audio focus request: " + (hasAudioFocus ? "granted" : "denied"));
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
		Log.d(LCAT, "Audio focus abandoned");
	}

	private void attemptReconnect()
	{
		if (retryCount >= MAX_RETRIES) {
			Log.w(LCAT, "Max retries reached, stopping player logic");
			// Stop player but keep service so user can skip
			if (player != null) player.stop();
			updatePlaybackState(PlaybackStateCompat.STATE_ERROR);
			updateNotification();
			return;
		}

		retryCount++;
		Log.d(LCAT, "Attempting reconnect (" + retryCount + "/" + MAX_RETRIES + ")");

		final String targetUrl = currentUrl;
		cancelPendingReconnect();

		pendingReconnectTask = executor.submit(() -> {
			try {
				Thread.sleep(RETRY_DELAY_MS);
			} catch (InterruptedException ignored) {
				return;
			}

			mainHandler.post(() -> {
				if (player != null && currentUrl != null && currentUrl.equals(targetUrl)) {
					Log.d(LCAT, "Executing scheduled reconnect for: " + currentUrl);
					MediaItem item = MediaItem.fromUri(currentUrl);
					player.setMediaItem(item);
					player.prepare();
					player.play();
				} else {
					Log.d(LCAT, "Scheduled reconnect aborted: URL changed or player stopped");
				}
			});
		});
	}

	private void cancelPendingReconnect()
	{
		if (pendingReconnectTask != null && !pendingReconnectTask.isDone()) {
			Log.d(LCAT, "Cancelling existing reconnect task");
			pendingReconnectTask.cancel(true);
		}
		pendingReconnectTask = null;
	}

	private void resetRetryLogic()
	{
		retryCount = 0;
		cancelPendingReconnect();
	}

	private void updateMediaSessionMetadata()
	{
		if (mediaSession == null) {
			return;
		}

		boolean hasArtwork = currentArtwork != null;

		// Some OEM lock screens keep stale art unless ART/ALBUM_ART are explicitly cleared.
		if (!hasArtwork) {
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

		metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ALBUM_ART, currentArtwork);
		metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_ART, currentArtwork);
		metadata.putBitmap(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON, currentArtwork);
		if (!hasArtwork) {
			metadata.putString(MediaMetadataCompat.METADATA_KEY_ALBUM_ART_URI, "");
			metadata.putString(MediaMetadataCompat.METADATA_KEY_ART_URI, "");
			metadata.putString(MediaMetadataCompat.METADATA_KEY_DISPLAY_ICON_URI, "");
		}

		mediaSession.setMetadata(metadata.build());
		sessionHadArtwork = hasArtwork;
	}

	/**
	 * Fetch artwork from a URL asynchronously (for Radio Paradise style streams)
	 */
	private void fetchArtworkFromUrl(String urlString, long expectedGeneration) {
		executor.execute(() -> {
			if (artworkGeneration.get() != expectedGeneration) {
				return;
			}
			try {
				Log.d(LCAT, "Fetching artwork from: " + urlString);
				java.net.URL url = new java.net.URL(urlString);
				java.net.HttpURLConnection connection = (java.net.HttpURLConnection) url.openConnection();
				connection.setDoInput(true);
				connection.connect();
				java.io.InputStream input = connection.getInputStream();
				Bitmap bitmap = BitmapFactory.decodeStream(input);
				if (bitmap != null) {
					mainHandler.post(() -> {
							if (artworkGeneration.get() != expectedGeneration) {
								Log.d(LCAT, "Ignoring stale fetched artwork for old stream: " + urlString);
								return;
							}
							currentArtwork = bitmap;
							updateMediaSessionMetadata();
							updateNotification();
							// Fire metadata event with artwork URL for app UI
							emitMetadataIfChanged(urlString, null);
							Log.i(LCAT, "Artwork updated from URL: " + urlString);
						});
				} else {
					Log.w(LCAT, "Failed to decode bitmap from: " + urlString);
				}
			} catch (Exception e) {
				Log.e(LCAT, "Error fetching artwork: " + e.getMessage());
			}
		});
	}

	private void updatePlaybackState(int state)
	{
		if (mediaSession == null) {
			return;
		}

		long position = player != null ? player.getCurrentPosition() : 0;
		float speed = (state == PlaybackStateCompat.STATE_PLAYING) ? 1.0f : 0.0f;

		PlaybackStateCompat playbackState = new PlaybackStateCompat.Builder()
			.setState(state, position, speed)
			.setActions(
				PlaybackStateCompat.ACTION_PLAY |
				PlaybackStateCompat.ACTION_PAUSE |
				PlaybackStateCompat.ACTION_STOP |
				PlaybackStateCompat.ACTION_PLAY_PAUSE |
				PlaybackStateCompat.ACTION_SKIP_TO_NEXT |
				PlaybackStateCompat.ACTION_SKIP_TO_PREVIOUS
			)
			.build();

		mediaSession.setPlaybackState(playbackState);
	}

	private void loadArtworkAsync(String artworkUrl, long expectedGeneration)
	{
		executor.execute(() -> {
			if (artworkGeneration.get() != expectedGeneration) {
				return;
			}
			try {
				Bitmap bitmap = null;
				boolean isRemoteURL = artworkUrl.startsWith("http://") || artworkUrl.startsWith("https://");

				if (isRemoteURL) {
					URL url = new URL(artworkUrl);
					HttpURLConnection connection = (HttpURLConnection) url.openConnection();
					connection.setConnectTimeout(5000);
					connection.setReadTimeout(8000);
					connection.connect();
					InputStream is = connection.getInputStream();
					bitmap = BitmapFactory.decodeStream(is);
					is.close();
					connection.disconnect();
				} else {
					try {
						InputStream is = getAssets().open("Resources/" + artworkUrl);
						bitmap = BitmapFactory.decodeStream(is);
						is.close();
					} catch (Exception e) {
						try {
							InputStream is = getAssets().open(artworkUrl);
							bitmap = BitmapFactory.decodeStream(is);
							is.close();
						} catch (Exception e2) {
							Log.w(LCAT, "Could not load local artwork: " + artworkUrl);
						}
					}
				}

				if (bitmap != null) {
					final Bitmap finalBitmap = bitmap;
					mainHandler.post(() -> {
						if (artworkGeneration.get() != expectedGeneration) {
							Log.d(LCAT, "Ignoring stale artwork load for old stream: " + artworkUrl);
							return;
						}
						currentArtwork = finalBitmap;
						updateMediaSessionMetadata();
						updateNotification();
					});
				} else {
					// Failed to load → clear artwork
					mainHandler.post(() -> {
						if (artworkGeneration.get() != expectedGeneration) {
							return;
						}
						currentArtwork = null;
						updateMediaSessionMetadata();
						updateNotification();
					});
				}
			} catch (Exception e) {
				Log.e(LCAT, "Failed to load artwork: " + e.getMessage());
			}
		});
	}

	private void startForegroundWithNotification()
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
			Log.d(LCAT, "Foreground service started");
		} catch (Exception e) {
			Log.e(LCAT, "Failed to start foreground: " + e.getMessage());
		}
	}

	private void updateNotification()
	{
		NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
		if (manager != null) {
			manager.notify(NOTIFICATION_ID, buildNotification());
		}
	}

	private Bitmap getTransparentArtwork()
	{
		// TODO(macCesar): Revisit this workaround.
		// Some OEM lock screens (e.g. OPPO/ColorOS) keep stale artwork when largeIcon is null.
		// We force-replace it with a transparent 1x1 bitmap for now.
		// Future: find an official way to restore the system generic placeholder icon on lock screen.
		if (transparentArtwork == null || transparentArtwork.isRecycled()) {
			transparentArtwork = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
		}
		return transparentArtwork;
	}

	private Notification buildNotification()
	{
		int smallIcon = getResources().getIdentifier("appicon", "drawable", getPackageName());
		if (smallIcon == 0) {
			smallIcon = android.R.drawable.ic_media_play;
		}

		boolean isPlaying = player != null && player.isPlaying();
		Bitmap largeIcon = currentArtwork != null ? currentArtwork : getTransparentArtwork();

		NotificationCompat.Builder builder = new NotificationCompat.Builder(this, CHANNEL_ID)
			.setContentTitle(currentTitle)
			.setContentText(currentArtist)
			.setSmallIcon(smallIcon)
			.setLargeIcon(largeIcon)
			.setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
			.setOnlyAlertOnce(true)
			.setOngoing(isPlaying)
			.addAction(buildAction(android.R.drawable.ic_media_previous, "Previous", ACTION_PREV))
			.addAction(isPlaying
				? buildAction(android.R.drawable.ic_media_pause, "Pause", ACTION_PAUSE)
				: buildAction(android.R.drawable.ic_media_play, "Play", ACTION_PLAY))
			.addAction(buildAction(android.R.drawable.ic_media_next, "Next", ACTION_NEXT));

		MediaStyle mediaStyle = new MediaStyle()
			.setShowActionsInCompactView(0, 1, 2);

		if (mediaSession != null) {
			mediaStyle.setMediaSession(mediaSession.getSessionToken());
		}

		builder.setStyle(mediaStyle);

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
		Log.d(LCAT, "Removing playback notification");
		ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE);
		NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
		if (manager != null) {
			manager.cancel(NOTIFICATION_ID);
		}
	}

	private void stopForegroundService()
	{
		Log.d(LCAT, "Stopping foreground service");
		removeNotification();
		stopSelf();
	}

	private void ensureNotificationChannel()
	{
		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
			NotificationManager manager = (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);
			if (manager != null && manager.getNotificationChannel(CHANNEL_ID) == null) {
				NotificationChannel channel = new NotificationChannel(
					CHANNEL_ID,
					"Audio Streaming",
					NotificationManager.IMPORTANCE_LOW
				);
				channel.setDescription("Audio streaming playback controls");
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

	@Nullable
	@Override
	public IBinder onBind(Intent intent)
	{
		return null;
	}

	@Override
	public void onDestroy()
	{
		Log.d(LCAT, "Service destroyed");
		resetRetryLogic();
		abandonAudioFocus();

		if (player != null) {
			player.removeListener(playerListener);
			player.release();
			player = null;
		}

		if (mediaSession != null) {
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
		Log.d(LCAT, "App task removed - cleaning up");
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
