# 🟦 Paso 2: Interfaz nativa ANDROID del módulo

## 🎯 Objetivo de este paso

✔ Que Android exponga **exactamente** los métodos que el JS espera
✔ Que los eventos estén definidos desde ahora
✔ Que luego podamos implementar sin cambiar la API

---

# 🧠 Regla de oro (repetimos porque es crítica)

> **El JS manda.
> El nativo obedece.**

El módulo Android **NO inventa métodos nuevos**.

---

# 📜 Métodos que DEBE exponer Android

El proxy nativo debe implementar:

```js
native.init()
native.setStream(url, isLive)
native.setMetadata({ title, subtitle, artwork })
native.play()
native.pause()
native.stop()
```

Y debe emitir eventos:

```js
fireEvent('state', { state })
fireEvent('error', { message })
```

---

# 📂 Archivos Android clave

Dentro del módulo:

```
android/
└── src/com/tuempresa/audiostream/
    ├── AudioStreamModule.java        ← PROXY JS
    ├── MediaPlaybackService.java     ← FOREGROUND SERVICE
    └── PlayerManager.java            ← EXOPLAYER + MEDIASESSION
```

Hoy **solo definimos `AudioStreamModule.java`**.

---

# 🧩 `AudioStreamModule.java` (esqueleto limpio)

```java
package com.tuempresa.audiostream;

import org.appcelerator.kroll.KrollModule;
import org.appcelerator.kroll.annotations.Kroll;
import org.appcelerator.kroll.KrollDict;

@Kroll.module(name = "Audiostream", id = "ti.audiostream")
public class AudioStreamModule extends KrollModule {

    private static MediaPlaybackService service;

    public AudioStreamModule() {
        super();
    }

    // ======================
    // API expuesta a JS
    // ======================

    @Kroll.method
    public void init() {
        MediaPlaybackService.start(getActivity());
    }

    @Kroll.method
    public void setStream(String url, boolean isLive) {
        MediaPlaybackService.get().setStream(url, isLive);
    }

    @Kroll.method
    public void setMetadata(KrollDict meta) {
        MediaPlaybackService.get().setMetadata(
            meta.optString("title"),
            meta.optString("subtitle"),
            meta.optString("artwork")
        );
    }

    @Kroll.method
    public void play() {
        MediaPlaybackService.get().play();
    }

    @Kroll.method
    public void pause() {
        MediaPlaybackService.get().pause();
    }

    @Kroll.method
    public void stop() {
        MediaPlaybackService.get().stop();
    }

    // ======================
    // Eventos hacia JS
    // ======================

    public static void fireState(String state) {
        if (service == null) return;

        KrollDict payload = new KrollDict();
        payload.put("state", state);
        service.fireEvent("state", payload);
    }

    public static void fireError(String message) {
        if (service == null) return;

        KrollDict payload = new KrollDict();
        payload.put("message", message);
        service.fireEvent("error", payload);
    }
}
```

👉 **Esto compila aunque no haga nada aún**
👉 Ya define el contrato Android ↔ JS

---

# 🧠 Qué NO estamos haciendo todavía (a propósito)

❌ No ExoPlayer aún
❌ No Audio Focus aún
❌ No MediaSession aún
❌ No Notification aún

Solo:
✔ Interfaz
✔ Responsabilidades claras

---

# 🔁 Flujo que ya queda definido

```
JS
 └─ radio.play()
      ↓
AudioStreamModule.play()
      ↓
MediaPlaybackService.play()
      ↓
(implementación real luego)
```

---

# 🧪 Cómo probar este paso

En tu app:

```js
const radio = require('ti.audiostream');

radio.init();
radio.play();
radio.pause();
```

Resultado esperado:

* No crashea
* No errores
* Métodos existen

👉 **Perfecto.**

---

# 🧱 Por qué este paso es CRÍTICO

✔ Congelas la API Android
✔ Evitas refactors dolorosos
✔ El Service puede evolucionar libremente
✔ El JS no cambia
✔ iOS puede copiar exactamente el mismo contrato

---

# ➡️ Siguiente paso (el grande)

Ahora sí viene lo bueno 🔥

### Paso 3

👉 **`MediaPlaybackService` + ExoPlayer + Audio Focus + MediaSession**

Aquí:

* resolvemos el problema original
* entra el audio focus real
* entra el background estable

Cuando quieras, seguimos con **Paso 3** y lo armamos **línea por línea**.
