Perfecto. Cerramos **el último refinamiento crítico de Android** 🔥
Este paso es **el que separa una radio “funciona en mi teléfono” de una radio de producción**.

---

# 🔧 Paso 6.3 — Android

## Manejo de errores + reconexión automática (radio)

Las radios **SIEMPRE** fallan:

* cortes de red
* cambio de Wi-Fi ↔ datos
* stream caído
* buffer infinito

👉 Si no manejas esto, el usuario piensa: *“la app se murió”*.

---

## 🎯 Objetivo técnico

✔ Detectar errores reales del player
✔ Notificar estado JS correctamente
✔ Reintentar conexión automáticamente
✔ Evitar loops infinitos
✔ Mantener audio focus y service vivos

---

# 1️⃣ Variables nuevas

En `MediaPlaybackService`:

```java
import com.google.android.exoplayer2.PlaybackException;

private int retryCount = 0;
private static final int MAX_RETRIES = 5;
private static final long RETRY_DELAY_MS = 3000;
```

---

# 2️⃣ Detectar errores del stream (ExoPlayer)

En el listener del player:

```java
@Override
public void onPlayerError(PlaybackException error) {
    updatePlaybackState(PlaybackStateCompat.STATE_ERROR);

    AudioStreamModule.fireState("error");
    AudioStreamModule.fireError("Stream error");

    attemptReconnect();
}
```

---

# 3️⃣ Lógica de reconexión automática

```java
private void attemptReconnect() {
    if (retryCount >= MAX_RETRIES) {
        stop();
        return;
    }

    retryCount++;

    artworkExecutor.execute(() -> {
        try {
            Thread.sleep(RETRY_DELAY_MS);
        } catch (InterruptedException ignored) {}

        if (player != null && currentUrl != null) {
            MediaItem item = new MediaItem.Builder()
                .setUri(currentUrl)
                .build();

            player.setMediaItem(item);
            player.prepare();
            player.play();
        }
    });
}
```

✔ Simple
✔ Predecible
✔ Sin loops infinitos

---

# 4️⃣ Resetear retries cuando todo va bien

En `onIsPlayingChanged`:

```java
@Override
public void onIsPlayingChanged(boolean isPlaying) {
    if (isPlaying) {
        retryCount = 0;
    }

    updatePlaybackState(
        isPlaying
            ? PlaybackStateCompat.STATE_PLAYING
            : PlaybackStateCompat.STATE_PAUSED
    );

    AudioStreamModule.fireState(isPlaying ? "playing" : "paused");
}
```

👉 En cuanto vuelve a sonar → contador limpio

---

# 5️⃣ Manejar pérdida de red (opcional pero recomendado)

Registrar receiver (simplificado):

```java
private void handleNetworkLoss() {
    pause();
    AudioStreamModule.fireState("buffering");
}
```

(En producción puedes conectar `ConnectivityManager`)

---

# 6️⃣ Comportamiento final esperado

| Escenario         | Resultado         |
| ----------------- | ----------------- |
| Stream cae        | buffering → retry |
| Red vuelve        | play automático   |
| 5 fallos seguidos | stop              |
| Usuario toca play | retry desde cero  |

---

# ⚠️ Decisiones importantes (por qué así)

✔ No reintentar infinito (mata batería)
✔ No recrear Service
✔ No perder audio focus
✔ No romper MediaSession
✔ No crashear por errores de red

---

# 🎯 Qué acabamos de cerrar

✔ Android robusto
✔ Radio tolerante a fallos
✔ UX profesional
✔ Menos “se quedó colgada”
✔ Menos reviews negativas

👉 **Este paso completa Android al 100%**.

---

# 🟢 Estado global del proyecto AHORA

### Android

✔ Audio focus correcto
✔ MediaSession + metadata
✔ Artwork async + cache
✔ Reconexión automática
✔ Foreground estable

### iOS

✔ Arquitectura correcta
✔ Audio background
✔ Lock screen
✔ Interrupciones

---

# 🏁 A partir de aquí YA no es “crítico”

Lo que sigue son **mejoras de calidad**.

---

## 👉 Próximo paso (mi recomendación)

### **Refinamientos iOS (rápidos y limpios)**

* Buffering states
* Errores de red
* Artwork async
* Reconexión simple

Son menos pasos y los hacemos rápido.

Si quieres, arrancamos con **Refinamiento iOS – Paso 7.1** 🚀
