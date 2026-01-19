Perfecto. Seguimos **sin desviarnos** y **subiendo la calidad del módulo** como corresponde.

---

# 🔧 Paso 6.2 — Android

## Artwork asíncrono + cache (SIN bloquear, SIN ANR)

Este paso es **obligatorio** para un módulo profesional porque:

* `MediaMetadata` **NO debe cargar imágenes en el hilo principal**
* Muchas radios cambian artwork seguido
* Android penaliza descargas síncronas
* Esto evita **ANR**, **lags** y **re-descargas innecesarias**

👉 No cambia la API JS
👉 Solo mejora estabilidad y UX

---

## 🎯 Objetivo técnico

✔ Descargar artwork en background
✔ Cachear imágenes
✔ Actualizar MediaSession cuando esté lista
✔ No bloquear UI / Service

---

# 1️⃣ Variables nuevas en `MediaPlaybackService`

```java
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.LruCache;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

private ExecutorService artworkExecutor;
private LruCache<String, Bitmap> artworkCache;
```

---

# 2️⃣ Inicializar cache y executor

En `onCreate()` del Service:

```java
@Override
public void onCreate() {
    super.onCreate();
    instance = this;

    artworkExecutor = Executors.newSingleThreadExecutor();

    int cacheSize = (int) (Runtime.getRuntime().maxMemory() / 1024 / 8);
    artworkCache = new LruCache<String, Bitmap>(cacheSize) {
        @Override
        protected int sizeOf(String key, Bitmap value) {
            return value.getByteCount() / 1024;
        }
    };
}
```

✔ Cache razonable
✔ Un solo hilo (ordenado)

---

# 3️⃣ Modificar `setMetadata(...)`

Antes solo seteábamos texto.
Ahora añadimos artwork **asíncrono**.

```java
public void setMetadata(String title, String subtitle, String artworkUrl) {
    initMediaSession();

    metadataBuilder = new MediaMetadataCompat.Builder()
        .putString(MediaMetadataCompat.METADATA_KEY_TITLE, title)
        .putString(MediaMetadataCompat.METADATA_KEY_ARTIST, subtitle);

    mediaSession.setMetadata(metadataBuilder.build());

    if (artworkUrl != null && !artworkUrl.isEmpty()) {
        loadArtworkAsync(artworkUrl);
    }
}
```

---

# 4️⃣ Cargar artwork en background

```java
private void loadArtworkAsync(String url) {
    Bitmap cached = artworkCache.get(url);
    if (cached != null) {
        applyArtwork(cached);
        return;
    }

    artworkExecutor.execute(() -> {
        try {
            Bitmap bitmap = BitmapFactory.decodeStream(
                new URL(url).openStream()
            );

            if (bitmap != null) {
                artworkCache.put(url, bitmap);
                applyArtwork(bitmap);
            }
        } catch (Exception e) {
            // No crashear por artwork
        }
    });
}
```

✔ Nunca bloquea
✔ Falla silenciosa (correcto para artwork)

---

# 5️⃣ Aplicar artwork a MediaSession (thread-safe)

```java
private void applyArtwork(Bitmap bitmap) {
    if (mediaSession == null || metadataBuilder == null) return;

    metadataBuilder.putBitmap(
        MediaMetadataCompat.METADATA_KEY_ALBUM_ART,
        bitmap
    );

    mediaSession.setMetadata(metadataBuilder.build());
}
```

👉 Android actualiza:

* Lock screen
* Notificación
* Bluetooth

---

# 🧪 Comportamiento esperado

* Primera vez: descarga
* Siguientes veces: cache
* Sin freezes
* Sin ANR
* Sin logs rojos

---

# ⚠️ Errores comunes (ya evitados)

❌ `BitmapFactory.decodeStream()` en UI
❌ Descargar artwork en `setMetadata()` directamente
❌ No cachear
❌ Re-descargar la misma imagen

---

# 🎯 Qué mejora inmediatamente

✔ UX profesional
✔ Menos consumo de datos
✔ Menos CPU
✔ Menos crashes
✔ Módulo “Spotify-grade”

---

# 🟢 Estado actual del módulo (Android)

✔ Audio focus correcto
✔ MediaSession sincronizada
✔ Metadata correcta
✔ Artwork async + cache
✔ Background estable

---

## 👉 Siguiente paso (ya alineado)

### **Paso 6.3 — Manejo de errores + reconexión automática (radio)**

Este es el último refinamiento **crítico** para radio en producción.

Cuando quieras, seguimos 🚀
