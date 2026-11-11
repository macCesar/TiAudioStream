/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */
package ti.audiostream;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.view.KeyEvent;

public class MediaActionReceiver extends BroadcastReceiver
{
	@Override
	public void onReceive(Context context, Intent intent)
	{
		if (intent == null) {
			return;
		}

		KeyEvent keyEvent;
		try {
			if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
				keyEvent = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent.class);
			} else {
				@SuppressWarnings("deprecation")
				android.os.Parcelable legacyKeyEvent = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
				keyEvent = legacyKeyEvent instanceof KeyEvent ? (KeyEvent) legacyKeyEvent : null;
			}
		} catch (RuntimeException malformedExtra) {
			return; // An external malformed Parcelable must not crash the receiver.
		}

		String action = intent.getAction();
		if (Intent.ACTION_MEDIA_BUTTON.equals(action)) {
			if (keyEvent == null || keyEvent.getAction() != KeyEvent.ACTION_DOWN) return;
			switch (keyEvent.getKeyCode()) {
				case KeyEvent.KEYCODE_MEDIA_PLAY: action = MediaPlaybackService.ACTION_PLAY; break;
				case KeyEvent.KEYCODE_MEDIA_PAUSE: action = MediaPlaybackService.ACTION_PAUSE; break;
				case KeyEvent.KEYCODE_MEDIA_STOP: action = MediaPlaybackService.ACTION_STOP; break;
				case KeyEvent.KEYCODE_MEDIA_NEXT: action = MediaPlaybackService.ACTION_NEXT; break;
				case KeyEvent.KEYCODE_MEDIA_PREVIOUS: action = MediaPlaybackService.ACTION_PREV; break;
				case KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE:
				case KeyEvent.KEYCODE_HEADSETHOOK: action = MediaPlaybackService.ACTION_PLAY_PAUSE; break;
				default: return;
			}
		}
		if (action == null) return;
		int remote;
		switch (action) {
			case MediaPlaybackService.ACTION_PLAY: remote = AudiostreamModule.REMOTE_CONTROL_PLAY; break;
			case MediaPlaybackService.ACTION_PAUSE: remote = AudiostreamModule.REMOTE_CONTROL_PAUSE; break;
			case MediaPlaybackService.ACTION_STOP: remote = AudiostreamModule.REMOTE_CONTROL_STOP; break;
			case MediaPlaybackService.ACTION_PLAY_PAUSE: remote = AudiostreamModule.REMOTE_CONTROL_PLAY_PAUSE; break;
			case MediaPlaybackService.ACTION_NEXT:
			case MediaPlaybackService.ACTION_PREV: remote = -1; break; // service handles native fallback
			default: return; // never forward configuration actions from the exported receiver
		}
		Intent command = MediaPlaybackService.authorizeCommand(new Intent(context, MediaPlaybackService.class).setAction(action));
		try {
			boolean mayPlay = MediaPlaybackService.ACTION_PLAY.equals(action)
				|| MediaPlaybackService.ACTION_PLAY_PAUSE.equals(action);
			if (mayPlay && !MediaPlaybackService.isForegroundReady() && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
				context.startForegroundService(command);
			} else context.startService(command);
			if (remote != -1) AudiostreamModule.fireRemoteControl(remote);
		} catch (RuntimeException failure) {
			MediaPlaybackService.releaseHardStopRequest(command);
			AudiostreamModule.fireState("error");
			AudiostreamModule.fireError("Cannot deliver media control: " + failure.getMessage());
		}
	}
}
