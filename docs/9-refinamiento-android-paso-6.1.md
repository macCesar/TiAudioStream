Perfecto 👍
Entonces **arrancamos ya** con lo prometido.

---

# 🔧 Paso 6.1 — Android

## PlaybackState + MediaMetadata (HECHO CORRECTAMENTE)

Este paso es **clave** porque:

* Android **decide el audio focus** basándose en `PlaybackState`
* Lock screen y Bluetooth **leen SOLO esto**
* Muchos bugs “fantasma” vienen de metadata mal sincronizada

👉 Esto **no cambia tu API JS**
👉 Solo fortalece el módulo

---

## 🎯 Objetivo técnico

✔ MediaSession siempre sincronizada
✔ Estado REAL del player reflejado al sistema
✔ Android entiende cuándo:

* estás reproduciendo
* estás pausado
* estás bufferizando

---

# 1️⃣ Variables nuevas en `MediaPlaybackService`

```java
import androidx.media.session.PlaybackStateCompat;
import androidx.media.MediaMetadataCompat;

private PlaybackStateCompat.Builder playbackStateBuilder;
private MediaMetadataCompat.Builder metadataBuilder;
```

---

# 2️⃣ Inicializar PlaybackState (una sola vez)

En `initMediaSession()`:

```java
private void initMediaSession() {
    if (mediaSession != null) return;

    mediaSession = new MediaSessionCompat(this, "AudioStream");

    playbackStateBuilder = new PlaybackStateCompat.Builder()
        .setActions(
            PlaybackStateCompat.ACTION_PLAY |
            PlaybackStateCompat.ACTION_PAUSE |
            PlaybackStateCompat.ACTION_STOP
        );

    mediaSession.setPlaybackState(
        playbackStateBuilder
            .setState(
                PlaybackStateCompat.STATE_STOPPED,
                PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
                1f
            )
            .build()
    );

    mediaSession.setCallback(new MediaSessionCompat.Callback() {
        @Override
        public void onPlay() {
            play();
        }

        @Override
        public void onPause() {
            pause();
        }

        @Override
        public void onStop() {
            stop();
        }
    });

    mediaSession.setActive(true);
}
```

---

# 3️⃣ Helper para actualizar el estado (MUY importante)

```java
private void updatePlaybackState(int state) {
    if (mediaSession == null || playbackStateBuilder == null) return;

    playbackStateBuilder.setState(
        state,
        PlaybackStateCompat.PLAYBACK_POSITION_UNKNOWN,
        state == PlaybackStateCompat.STATE_PLAYING ? 1f : 0f
    );

    mediaSession.setPlaybackState(playbackStateBuilder.build());
}
```

---

# 4️⃣ Conectar ExoPlayer → PlaybackState

En el listener del player:

```java
player.addListener(new Player.Listener() {

    @Override
    public void onPlaybackStateChanged(int state) {
        if (state == Player.STATE_BUFFERING) {
            updatePlaybackState(PlaybackStateCompat.STATE_BUFFERING);
            AudioStreamModule.fireState("buffering");
        }

        if (state == Player.STATE_READY && player.isPlaying()) {
            updatePlaybackState(PlaybackStateCompat.STATE_PLAYING);
            AudioStreamModule.fireState("playing");
        }
    }

    @Override
    public void onIsPlayingChanged(boolean isPlaying) {
        updatePlaybackState(
            isPlaying
                ? PlaybackStateCompat.STATE_PLAYING
                : PlaybackStateCompat.STATE_PAUSED
        );

        AudioStreamModule.fireState(isPlaying ? "playing" : "paused");
    }
});
```

👉 **Esto es lo que antes te faltaba**
👉 Ahora Android *sí* sabe cuándo debe pausar a otros

---

# 5️⃣ Actualizar estado en `pause()` y `stop()`

```java
public void pause() {
    if (player != null) {
        player.pause();
        updatePlaybackState(PlaybackStateCompat.STATE_PAUSED);
    }
}

public void stop() {
    if (player != null) {
        player.stop();
        player.release();
        player = null;
    }

    updatePlaybackState(PlaybackStateCompat.STATE_STOPPED);

    if (audioManager != null && focusRequest != null) {
        audioManager.abandonAudioFocusRequest(focusRequest);
    }

    stopForeground(true);
    stopSelf();
}
```

---

# 6️⃣ Metadata del stream (título / subtitle / artwork)

En `setMetadata(...)` del Service:

```java
public void setMetadata(String title, String subtitle, String artworkUrl) {
    initMediaSession();

    metadataBuilder = new MediaMetadataCompat.Builder()
        .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
        .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, subtitle);

    mediaSession.setMetadata(metadataBuilder.build());
}
```

⚠️ **NO cargamos artwork aún**
Eso es el **Paso 6.2 (async)**

---

# 🎯 Qué mejora INMEDIATAMENTE con esto

✔ Audio focus más fiable
✔ Spotify / YouTube pausan bien
✔ Lock screen refleja estado real
✔ Bluetooth responde correctamente
✔ Menos “ambos audios suenan”

Este paso **ataca directamente tu bug original**.

---

# 🧪 Cómo verificar (muy importante)

1. Inicia radio
2. Abre YouTube
3. YouTube debería:

   * pausar tu radio
   * tomar el foco
4. Regresa a tu app
5. Play → recupera foco

Si esto falla:

* logs de `updatePlaybackState`
* logs de `onAudioFocusChange`

---

# 🟢 Estado actual

✔ API intacta
✔ Android mucho más sólido
✔ MediaSession “bien educada”
✔ Sistema operativo coopera

---

## 👉 Siguiente paso (ya decidido)

### **Paso 6.2 — Artwork asíncrono + cache**

Esto evita:

* ANR
* freezes
* descargas repetidas

Cuando estés listo, seguimos 👌
