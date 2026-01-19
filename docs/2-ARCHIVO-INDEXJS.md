Sí. **Exactamente.** ✅
Ese es **el siguiente paso correcto** y además es el **menos riesgoso** para empezar.

Vamos a hacerlo **bien hecho**, no solo “crear el archivo”.

---

# 🟢 Paso 1 del proyecto: crear `commonjs/index.js`

Este archivo **define el contrato público del módulo**.
Todo lo demás (Android / iOS) se adapta a **esto**, no al revés.

---

## 📂 Dónde va

En el **root del módulo**:

```
ti.audiostream/
└── commonjs/
    └── index.js
```

> ⚠️ Si la carpeta no existe, **créala manualmente**.

---

## 🎯 Qué debe hacer (y qué NO)

### Debe

✔ Exponer la API unificada
✔ Validar parámetros
✔ Normalizar eventos
✔ Mantener estado JS mínimo

### NO debe

❌ Reproducir audio
❌ Manejar audio focus
❌ Acceder a APIs del SO
❌ Tener lógica por plataforma

---

## 📜 `commonjs/index.js` – versión BASE (recomendada)

Este es **el archivo que debes crear ahora** 👇

```js
'use strict';

/**
 * ti.audiostream
 * CommonJS API layer
 */

// Proxy nativo (Android / iOS)
const native = require('ti.audiostream');

// Estado interno
let currentState = 'stopped';
let initialized = false;

// Helper: emitir eventos
function emit(event, data) {
  exports.fireEvent(event, data || {});
}

// Helper: setear estado
function setState(state) {
  if (currentState === state) return;
  currentState = state;
  emit('statechange', { state });
}

/**
 * Inicialización
 */
exports.init = function () {
  if (initialized) return;
  initialized = true;
  native.init();
};

/**
 * Define el stream
 */
exports.setStream = function (options) {
  if (!options || typeof options.url !== 'string') {
    throw new Error('setStream requires { url: string }');
  }

  native.setStream(
    options.url,
    !!options.isLive
  );
};

/**
 * Metadata (lock screen / notification)
 */
exports.setMetadata = function (meta) {
  if (!meta) return;

  native.setMetadata({
    title: meta.title || '',
    subtitle: meta.subtitle || '',
    artwork: meta.artwork || null
  });
};

/**
 * Controles
 */
exports.play = function () {
  native.play();
};

exports.pause = function () {
  native.pause();
};

exports.stop = function () {
  native.stop();
};

/**
 * Eventos desde nativo
 */
native.addEventListener('state', function (e) {
  // e.state = playing | paused | buffering | stopped | error
  setState(e.state);
});

native.addEventListener('error', function (e) {
  emit('error', e);
});
```

---

## 🧪 Cómo probar que está funcionando (sin Android / iOS aún)

1️⃣ Compila el módulo
2️⃣ En tu app:

```js
const radio = require('ti.audiostream');

radio.init();

radio.addEventListener('statechange', e => {
  Ti.API.info('STATE = ' + e.state);
});
```

Si el módulo carga:

* No crashea
* No lanza errores
* El API existe

👉 **Perfecto.**

---

## 🧠 Importante (detalle fino)

Sí, `require('ti.audiostream')` se usa **dos veces**:

* Una en la app
* Una dentro del propio módulo

Titanium:

* Detecta el contexto
* Devuelve el proxy nativo internamente
* No entra en loop

Esto es **comportamiento esperado**.

---

## 🎯 Por qué empezar aquí

✔ No dependes de Android / iOS aún
✔ Defines el contrato definitivo
✔ Todo el código nativo se alinea
✔ Evitas romper la API después
✔ Es el paso más limpio

---

## 👉 Qué sigue después (elige)

1️⃣ Definir **interfaz nativa Android** (métodos + eventos)
2️⃣ Crear **Service + ExoPlayer**
3️⃣ Definir **interfaz nativa iOS**
4️⃣ Escribir tests manuales de API

Dime el siguiente paso y seguimos construyendo 💪
