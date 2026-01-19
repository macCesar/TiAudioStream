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
		if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
			keyEvent = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent.class);
		} else {
			@SuppressWarnings("deprecation")
			KeyEvent legacyKeyEvent = intent.getParcelableExtra(Intent.EXTRA_KEY_EVENT);
			keyEvent = legacyKeyEvent;
		}
		AudiostreamModule.handleMediaAction(intent.getAction(), keyEvent);
	}
}
