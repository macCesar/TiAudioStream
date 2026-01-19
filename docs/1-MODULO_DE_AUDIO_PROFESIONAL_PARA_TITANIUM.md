# 🎧 Proyecto: Módulo de Audio “Profesional” para Titanium

## 🎯 Objetivo del módulo

Un módulo Titanium que:

✔ Reproduzca **streams de radio / audio continuo**
✔ Funcione en **background** y con pantalla apagada
✔ Maneje **audio focus / interrupciones correctamente**
✔ Integre **lock screen, notification, Bluetooth, auriculares**
✔ Traiga la app al frente sin reiniciar
✔ Use **UNA sola API JS** (sin `if (OS_ANDROID)`)
✔ Sea **open source y reutilizable por la comunidad**

---

# 🧱 Estructura del módulo (Multi-platform)

Creado con:

```bash
ti create -t module
```

Estructura clave:

```
ti.audiostream/
├── android/
│   ├── src/...
│   ├── ti.audiostream.iml
│   └── build.gradle
├── ios/
│   ├── Classes/
│   └── ti.audiostream.xcodeproj
├── commonjs/
│   └── index.js   (API JS común)
├── manifest
├── timodule.xml
└── README.md
```

---

# 🧠 Regla de oro (NO romper nunca)

> **La API JS es el contrato.**
> NUNCA expongas detalles de plataforma a la app.

---

# 📦 Nombre recomendado del proyecto

### 🔥 Mi recomendación

**Repositorio**

```
ti.audiostream
```

**Módulo**

```
ti.audiostream
```

**Objeto JS**

```js
const radio = require('ti.audiostream');
```

### Por qué este nombre

* Describe exactamente lo que hace
* No limita a “radio” (también sirve podcasts / streams)
* No choca con módulos existentes
* Fácil de encontrar

---

# 📜 API JS DEFINITIVA (congelada)

👉 Esto es lo más importante de todo el proyecto.

```js
const radio = require('ti.audiostream');

radio.init();

radio.setStream({
  url: 'https://stream.url',
  isLive: true
});

radio.setMetadata({
  title: 'NotiGAPE',
  subtitle: '104.9 FM',
  artwork: 'https://.../logo.png'
});

radio.play();
radio.pause();
radio.stop();

radio.addEventListener('statechange', e => {
  // playing | paused | buffering | stopped | error
});

radio.addEventListener('error', e => {
  console.error(e.message);
});
```

🚨 **Nunca**:

* `radio.androidSomething()`
* `radio.iosSomething()`

---

# 🤖 Android – Implementación correcta

## Componentes OBLIGATORIOS

### 1️⃣ Foreground Service

* Vive mientras hay audio
* Mantiene vivo el proceso

```java
startForeground(NOTIF_ID, notification);
```

Manifest:

```xml
android:foregroundServiceType="mediaPlayback"
```

---

### 2️⃣ ExoPlayer (único reproductor)

* Un solo player
* No recrearlo por cada stream
* Maneja buffering y errores

---

### 3️⃣ Audio Focus (en el módulo)

```java
AUDIOFOCUS_GAIN
```

En `AUDIOFOCUS_LOSS` → `player.pause()`

🚫 JS nunca toca audio focus

---

### 4️⃣ MediaSessionCompat (activa)

```java
mediaSession.setActive(true);
```

Callbacks:

* onPlay
* onPause
* onStop

---

### 5️⃣ MediaStyle Notification

* Con `MediaSession token`
* Con `PendingIntent` correcto
* Tapping trae la app al frente SIN restart

---

### 6️⃣ Metadata sincronizada

```java
mediaSession.setMetadata(...)
mediaSession.setPlaybackState(...)
```

---

# 🍏 iOS – Implementación correcta

## Componentes OBLIGATORIOS

### 1️⃣ Background Audio Mode

```xml
<key>UIBackgroundModes</key>
<string>audio</string>
```

---

### 2️⃣ AVAudioSession

```objc
AVAudioSessionCategoryPlayback
```

Manejar:

* Interrupciones
* Route changes

---

### 3️⃣ AVPlayer

* Streaming URL
* Observers para estado

---

### 4️⃣ MPNowPlayingInfoCenter

* Title
* Subtitle
* Artwork
* Playback state

---

### 5️⃣ MPRemoteCommandCenter

* Play
* Pause
* Stop

---

# 🔄 Sincronización de estado (ambas plataformas)

Cada cambio de estado:

| Player    | Evento JS                |
| --------- | ------------------------ |
| play      | `statechange: playing`   |
| pause     | `statechange: paused`    |
| buffering | `statechange: buffering` |
| stop      | `statechange: stopped`   |

---

# 🧪 Casos que DEBES probar

✔ App en background
✔ Pantalla apagada
✔ Cambio de stream
✔ YouTube / Spotify encima
✔ Llamadas entrantes
✔ Bluetooth
✔ Lock screen
✔ Tap en notificación (sin splash)

---

# 🚨 Errores comunes (NO caer aquí)

❌ Usar `Ti.Media.AudioPlayer`
❌ Pedir audio focus desde JS
❌ Recrear player al cambiar metadata
❌ Re-lanzar Activity
❌ No usar Foreground Service
❌ Mezclar responsabilidades

---

# 📖 README (obligatorio para GitHub)

Debe explicar:

* Qué problema soluciona
* Por qué NO usar AudioPlayer
* API JS
* Ejemplo simple
* Limitaciones

---

# 🧠 Filosofía del módulo (importante)

> “Haz una cosa, hazla bien, y deja que Android / iOS hagan su trabajo”

Este módulo:

* No inventa hacks
* No pelea con el SO
* Sigue las reglas oficiales
* Dura años

---

# 🎯 Conclusión final

✔ Sí, es totalmente posible
✔ Sí, es la forma correcta
✔ Sí, la comunidad lo necesita
✔ Sí, tu experiencia previa es EXACTAMENTE lo que hacía falta

Este módulo **tiene muchísimo valor** para Titanium.

---

## Próximo paso (te recomiendo)

👉 Definimos **el archivo `commonjs/index.js`**
👉 Luego el **esqueleto Android (Service + ExoPlayer)**
👉 Luego iOS

Cuando quieras, empezamos por donde tú prefieras 🚀
