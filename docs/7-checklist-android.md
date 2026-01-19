Perfecto 👍
Entonces vamos **directo y sin rodeos** con lo que pediste.

A continuación tienes el **Checklist Android 12–14**
específicamente enfocado a **audio streaming profesional** (radio / música), **Titanium module friendly**, y **sin humo**.

Este checklist es **lo que evita que Android te rompa el módulo en producción**.

---

# ✅ Checklist ANDROID 12–14

**Audio Streaming / Media Playback**

---

## 1️⃣ Foreground Service (NO negociable)

### ✔ Manifest

```xml
<service
  android:name=".MediaPlaybackService"
  android:exported="false"
  android:foregroundServiceType="mediaPlayback" />
```

📌 **Obligatorio desde Android 12**
Sin esto:

* El sistema mata el servicio
* Audio se corta
* No hay warning claro

---

## 2️⃣ startForeground() en ≤ 5 segundos

Android 12+:

* Si llamas `startForegroundService()`
* **Debes** llamar `startForeground()` rápido

✔ En `play()`
✔ Con notificación válida
✔ Antes de reproducir

❌ Llamarlo tarde = service kill silencioso

---

## 3️⃣ MediaStyle Notification correcta

### ✔ Usar MediaSession

```java
new NotificationCompat.MediaStyle()
  .setMediaSession(mediaSession.getSessionToken())
```

### ✔ Acciones reales (Play / Pause)

Si no:

* Controles no aparecen
* Lock screen incompleto
* BT no funciona

---

## 4️⃣ PendingIntent (Android 12+)

### ✔ SIEMPRE declarar flags

```java
PendingIntent.getActivity(
  context,
  0,
  intent,
  PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
);
```

❌ Sin esto:

* Crash
* O la app no vuelve al frente
* O comportamiento errático

---

## 5️⃣ Intent correcto para volver a la app

### ✔ Usar Launch Intent

```java
Intent intent = getPackageManager()
  .getLaunchIntentForPackage(getPackageName());

intent.addFlags(
  Intent.FLAG_ACTIVITY_CLEAR_TOP |
  Intent.FLAG_ACTIVITY_SINGLE_TOP
);
```

✔ No recrea Activity
✔ No muestra splash
✔ No corta audio

👉 **Esto tú ya lo solucionaste bien** 👌

---

## 6️⃣ Audio Focus (forma correcta)

### ✔ Usar `AudioFocusRequest`

```java
AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
```

### ✔ Pausar en:

* `AUDIOFOCUS_LOSS`
* `AUDIOFOCUS_LOSS_TRANSIENT`

### ✔ Abandonar focus en `stop()`

```java
audioManager.abandonAudioFocusRequest(focusRequest);
```

❌ No abandonar focus = otros players no funcionan bien

---

## 7️⃣ UN solo dueño del audio

✔ ExoPlayer SOLO en el Service
✔ NO Ti.Media.AudioPlayer
✔ NO doble AudioManager

Esto evita:

* Audio simultáneo
* Callbacks que no llegan
* Focus “fantasma”

---

## 8️⃣ MediaSession ACTIVA

```java
mediaSession.setActive(true);
```

Si no:

* Lock screen no responde
* BT ignora controles
* Audio focus no se integra bien

---

## 9️⃣ Metadata sincronizada

Actualizar SIEMPRE:

* PlaybackState
* MediaMetadata

Especialmente:

* `STATE_PLAYING`
* `STATE_PAUSED`

Android usa esto para:

* Prioridad
* Focus
* Lock screen

---

## 🔟 WAKE_LOCK (caso OEM agresivo)

En algunos dispositivos (Samsung / Xiaomi):

```xml
<uses-permission android:name="android.permission.WAKE_LOCK"/>
```

No siempre obligatorio, pero:

* **Altamente recomendado** para radio

---

## 1️⃣1️⃣ Battery Optimization (OEMs)

Android “stock” → OK
Fabricantes → problema

✔ Foreground Service
✔ Notificación visible
✔ Sin hacks ocultos

(Esto es lo máximo permitido legalmente)

---

## 1️⃣2️⃣ targetSdkVersion

✔ Compilar con:

```
targetSdkVersion 33 o 34
```

⚠️ Compilar con SDK viejo:

* Play Store warnings
* Comportamientos inconsistentes

---

## 1️⃣3️⃣ Android 13+ (Notificaciones)

Si target ≥ 33:

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

Solicitarlo en runtime si usas notificación visible.

---

## 1️⃣4️⃣ Logging REAL (debug)

Siempre tener logs en:

* requestAudioFocus result
* onAudioFocusChange
* startForeground
* player state

Porque:

* Android falla silenciosamente
* Sin logs, no sabes por qué

---

# 🧪 Checklist rápido (copiar/pegar mental)

✔ Foreground service
✔ MediaSession activa
✔ ExoPlayer en service
✔ AudioFocusRequest
✔ Abandonar focus
✔ PendingIntent con flags
✔ targetSdk moderno
✔ Notification permission (13+)

---

# 🍏 ¿Y iOS?

iOS **NO necesita checklist de supervivencia**.

Solo refinamientos:

* Observers de buffering
* Reconexión
* Artwork async
* Errores de red

👉 Eso es **mejora**, no **requisito para que funcione**.

---

# 🏁 Estado actual del proyecto

✔ Arquitectura sólida
✔ Checklist Android completo
✔ Problema original explicado y resuelto
✔ Listo para refinamiento final

---

## 👉 Próximo paso (elige)

1️⃣ Refinamientos ANDROID (metadata, artwork async, reconexión)
2️⃣ Refinamientos iOS (buffering + errores)
3️⃣ Checklist iOS (rápido, corto)
4️⃣ Preparar **release 1.0.0**

Dime cómo seguimos y lo dejamos **cerrado profesionalmente** 💪
