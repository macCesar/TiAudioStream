# Guía Completa: Implementación de ti.audiostream

## Objetivo

Crear un módulo Titanium profesional para audio streaming que:
- Reproduzca streams de radio/audio en background
- Maneje audio focus correctamente (YouTube/Spotify pausan tu app y viceversa)
- Integre lock screen, notificaciones, Bluetooth, auriculares
- Use UNA sola API JS (sin código condicional por plataforma)
- Sea open source y reutilizable

---

## Por qué este módulo (y no TiMediaSession + Ti.Media.AudioPlayer)

El problema que NO pudimos resolver:
- `Ti.Media.AudioPlayer` maneja audio focus internamente
- `TiMediaSession` también solicita audio focus
- **Dos sistemas compitiendo** = callbacks que nunca llegan
- Resultado: YouTube y NotiGAPE suenan simultáneamente

La solución:
- **ExoPlayer** (Android) / **AVPlayer** (iOS) como ÚNICO reproductor
- Audio focus integrado en el mismo componente que reproduce
- Sin Ti.Media.AudioPlayer

---

## Documentos de Referencia (en orden)

| #   | Archivo                                          | Contenido                                        |
| --- | ------------------------------------------------ | ------------------------------------------------ |
| 1   | `1-MODULO_DE_AUDIO_PROFESIONAL_PARA_TITANIUM.md` | Visión general, arquitectura, API JS definitiva  |
| 3   | `3-interfaze-nativa-android.md`                  | Esqueleto `AudioStreamModule.java`               |
| 4   | `4-MediaPlaybackService.md`                      | Service + ExoPlayer + Audio Focus + MediaSession |
| 5   | `5-ios.md`                                       | AVPlayer + AVAudioSession + MPNowPlaying         |
| 6   | `6-readme-para-github.md`                        | README para publicar                             |
| 7   | `7-checklist-android.md`                         | Checklist Android 12-14                          |
| 8   | `8-refinamiento-android.md`                      | Plan de refinamientos Android                    |
| 9   | `9-refinamiento-android-paso-6.1.md`             | PlaybackState + MediaMetadata                    |
| 10  | `10-refinamiento-android-paso-6.2.md`            | Artwork async + cache                            |
| 11  | `11-refinamiento-android-paso-6.3.md`            | Errores + reconexión automática                  |
| 12  | `12-refinamiento-ios-paso-7.md`                  | Refinamientos iOS completos                      |
| 13  | `13-checklist-ios+release-1.0.0.md`              | Checklist iOS + Release                          |

---

## Estructura del Módulo

```
ti.audiostream/
├── android/
│   ├── manifest
│   ├── build.gradle
│   ├── timodule.xml
│   └── src/ti/audiostream/
│       ├── AudiostreamModule.java      ← Proxy JS
│       └── MediaPlaybackService.java   ← Service + ExoPlayer
├── ios/
│   ├── manifest
│   ├── timodule.xml
│   └── Classes/
│       ├── TiAudiostreamModule.h
│       ├── TiAudiostreamModule.m       ← Proxy JS
│       ├── AudioPlayerManager.h
│       └── AudioPlayerManager.m        ← AVPlayer + sesión
├── example/
│   └── app/...                         ← App de ejemplo
├── manifest
├── LICENSE
└── README.md
```

---

## Fases de Implementación

### FASE 1: Esqueleto (sin funcionalidad)

**Objetivo**: Que el módulo compile y se pueda importar

1. Crear módulo con `ti create -t module -n audiostream -id ti.audiostream`
2. Crear esqueleto `AudiostreamModule.java` (documento #3)
3. Crear esqueleto iOS `TiAudiostreamModule.m` (documento #5)
4. Compilar ambas plataformas
5. Verificar que `require('ti.audiostream')` no crashea

### FASE 2: Android Core

**Objetivo**: Audio funcionando con audio focus correcto

1. Agregar Media3 (ExoPlayer moderno) a `build.gradle`:
   ```gradle
   dependencies {
       // Media3 - última versión estable (NO usar ExoPlayer 2.x que está deprecado)
       implementation 'androidx.media3:media3-exoplayer:1.5.1'
       implementation 'androidx.media3:media3-exoplayer-hls:1.5.1'
       implementation 'androidx.media3:media3-session:1.5.1'
   }
   ```

2. Implementar `MediaPlaybackService.java` (documento #4):
   - Foreground Service
   - ExoPlayer inicialización
   - Audio Focus con `AudioFocusRequest`
   - MediaSessionCompat
   - Notificación MediaStyle

3. Registrar servicio en `timodule.xml`:
   ```xml
   <service android:name="ti.audiostream.MediaPlaybackService"
            android:exported="false"
            android:foregroundServiceType="mediaPlayback"
            android:stopWithTask="false" />
   ```

4. Agregar permisos en `timodule.xml`:
   ```xml
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
   <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
   <uses-permission android:name="android.permission.WAKE_LOCK" />
   <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
   ```

5. Probar:
   - [ ] Audio reproduce
   - [ ] Audio sigue en background
   - [ ] YouTube pausa tu app
   - [ ] Tu app pausa YouTube

### FASE 3: Android Refinamientos

**Objetivo**: Calidad de producción

1. PlaybackState sincronizado (documento #9)
2. Artwork async + LruCache (documento #10)
3. Reconexión automática (documento #11)
4. Notification Channel para Android 8+
5. onTaskRemoved cleanup (ver sección GAPS)

### FASE 4: iOS Core

**Objetivo**: Audio funcionando con interrupciones correctas

1. Implementar `AudioPlayerManager.m` (documento #5):
   - AVPlayer
   - AVAudioSession (Playback)
   - MPNowPlayingInfoCenter
   - MPRemoteCommandCenter
   - Manejo de interrupciones

2. Probar:
   - [ ] Audio reproduce
   - [ ] Audio sigue con pantalla bloqueada
   - [ ] Llamada entrante pausa audio
   - [ ] Lock screen muestra controles

### FASE 5: iOS Refinamientos

**Objetivo**: Calidad de producción

1. Estados buffering con KVO (documento #12)
2. Artwork async
3. Reconexión simple
4. Route change (auriculares)
5. Limpieza de observers

### FASE 6: Integración Final

1. Verificar API JS idéntica en ambas plataformas
2. Probar en app real (NotiGAPE)
3. Documentar
4. Release 1.0.0

---

## API JS Definitiva

```javascript
const radio = require('ti.audiostream');

// Inicializar
// radio.init(); // No necesario

// Configurar stream
radio.setStream({
    url: 'https://stream.example.com/radio.mp3',
    isLive: true
});

// Metadata para lock screen / notificación
radio.setMetadata({
    title: 'Nombre del Programa',
    artist: 'Nombre de la Estación', // artist instead of subtitle for consistency
    artwork: 'https://example.com/logo.png'
});

// Controles
radio.start(); // start instead of play to match native method
radio.pause();
radio.stop();

// Eventos
radio.addEventListener('state', function(e) {
    // e.state = 'playing' | 'paused' | 'buffering' | 'stopped' | 'error'
    Ti.API.info('Estado: ' + e.state);
});

radio.addEventListener('error', function(e) {
    Ti.API.error('Error: ' + e.message);
});

radio.addEventListener('remotecontrol', function(e) {
    // e.subtype = constant
    Ti.API.info('Comando remoto: ' + e.subtype);
});
```

---

## GAPS: Lo que falta en la documentación original

### 1. onTaskRemoved Cleanup

Agregar en `MediaPlaybackService.java`:

```java
@Override
public void onTaskRemoved(Intent rootIntent) {
    super.onTaskRemoved(rootIntent);

    // Opción A: Limpiar todo (como TiMediaSession actual)
    if (!isPlaying) {
        stop();
        return;
    }

    // Opción B: Seguir reproduciendo si está activo
    // (el usuario hizo swipe pero quiere seguir escuchando)
}
```

### 2. Next/Prev Callbacks

En MediaSession:

```java
mediaSession.setCallback(new MediaSessionCompat.Callback() {
    @Override
    public void onPlay() { play(); }

    @Override
    public void onPause() { pause(); }

    @Override
    public void onStop() { stop(); }

    // AGREGAR ESTOS:
    @Override
    public void onSkipToNext() {
        fireRemoteControl("next");
    }

    @Override
    public void onSkipToPrevious() {
        fireRemoteControl("prev");
    }
});
```

### 3. Notification Channel (Android 8+)

```java
private void createNotificationChannel() {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        NotificationChannel channel = new NotificationChannel(
            "ti_audiostream",
            "Audio Playback",
            NotificationManager.IMPORTANCE_LOW
        );
        channel.setDescription("Controls audio playback");
        channel.setShowBadge(false);

        NotificationManager manager = getSystemService(NotificationManager.class);
        manager.createNotificationChannel(channel);
    }
}
```

### 4. Evento remotecontrol hacia JS

En el módulo:

```java
public static void fireRemoteControl(String command) {
    KrollDict payload = new KrollDict();
    payload.put("command", command);
    getInstance().fireEvent("remotecontrol", payload);
}
```

### 5. Acciones en Notificación (Next/Prev)

```java
private Notification buildNotification() {
    return new NotificationCompat.Builder(this, "ti_audiostream")
        .setContentTitle(currentTitle)
        .setContentText(currentSubtitle)
        .setSmallIcon(R.drawable.ic_notification)
        .setLargeIcon(currentArtwork)
        .setStyle(new MediaStyle()
            .setMediaSession(mediaSession.getSessionToken())
            .setShowActionsInCompactView(0, 1, 2))  // prev, play/pause, next
        .addAction(R.drawable.ic_prev, "Previous", prevIntent)
        .addAction(isPlaying ? R.drawable.ic_pause : R.drawable.ic_play,
                   isPlaying ? "Pause" : "Play",
                   playPauseIntent)
        .addAction(R.drawable.ic_next, "Next", nextIntent)
        .setContentIntent(contentIntent)
        .setDeleteIntent(stopIntent)
        .build();
}
```

### 6. iOS Route Change (auriculares desconectados)

```objc
[[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(handleRouteChange:)
           name:AVAudioSessionRouteChangeNotification
         object:nil];

- (void)handleRouteChange:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    AVAudioSessionRouteChangeReason reason =
        [info[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];

    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        // Auriculares desconectados - pausar
        [self pause];
    }
}
```

---

## Checklist Final Pre-Release

### Android
- [ ] Compila sin warnings
- [ ] Audio reproduce en background
- [ ] Audio focus funciona (YouTube pausa tu app)
- [ ] Tu app pausa YouTube al iniciar
- [ ] Notificación visible y funcional
- [ ] Botones Play/Pause/Next/Prev funcionan
- [ ] Lock screen muestra controles
- [ ] Bluetooth funciona
- [ ] Tap en notificación trae app al frente (sin reiniciar)
- [ ] Reconexión automática funciona
- [ ] No hay ANR por artwork
- [ ] onTaskRemoved comportamiento correcto
- [ ] Funciona en Android 12, 13, 14

### iOS
- [ ] Compila sin warnings
- [ ] Audio reproduce en background
- [ ] Llamada entrante pausa audio
- [ ] Lock screen muestra controles
- [ ] Control Center funciona
- [ ] Auriculares/Bluetooth funcionan
- [ ] Desconectar auriculares pausa audio
- [ ] Artwork carga sin freeze
- [ ] Reconexión funciona
- [ ] Funciona en iOS 15, 16, 17

### API JS
- [ ] Misma API en ambas plataformas
- [ ] Eventos statechange funcionan
- [ ] Eventos error funcionan
- [ ] Eventos remotecontrol funcionan
- [ ] No hay código condicional en la app

---

## Orden de Lectura Recomendado

Para implementar desde cero:

1. **Visión general**: `1-MODULO_DE_AUDIO_PROFESIONAL_PARA_TITANIUM.md`
3. **Android básico**: `3-interfaze-nativa-android.md` → `4-MediaPlaybackService.md`
4. **Android checklist**: `7-checklist-android.md`
5. **Android refinamientos**: `9`, `10`, `11`
6. **iOS**: `5-ios.md`
7. **iOS refinamientos**: `12-refinamiento-ios-paso-7.md`
8. **iOS checklist**: `13-checklist-ios+release-1.0.0.md`
9. **README**: `6-readme-para-github.md`
10. **GAPS**: Esta sección del documento actual

---

## Notas Importantes

1. **NO usar Ti.Media.AudioPlayer** - Es el origen del problema de audio focus
2. **UN solo dueño del audio** - ExoPlayer en Android, AVPlayer en iOS
3. **El módulo reproduce** - No solo maneja metadata/controles
4. **Audio focus en el módulo** - No en JavaScript
5. **Probar con YouTube/Spotify** - Es el test definitivo de audio focus

---

## Migración desde TiMediaSession

Si ya usas TiMediaSession en tu app:

1. Reemplazar `Ti.Media.AudioPlayer` con `ti.audiostream`
2. Cambiar:
   ```javascript
   // ANTES
   const player = Ti.Media.createAudioPlayer({ url: '...' });
   const controlRemoto = require('com.maccesar.mediasession');
   controlRemoto.setNowPlayingInfo({...});
   player.start();

   // DESPUÉS
   const radio = require('ti.audiostream');
   // radio.init(); // No es necesario
   radio.setStream({ url: '...' });
   radio.setMetadata({...});
   radio.start();
   ```

3. El evento `remotecontrol` cambia ligeramente:
   ```javascript
   // ANTES
   controlRemoto.addEventListener('remotecontrol', e => {
       if (e.subtype === controlRemoto.REMOTE_CONTROL_PLAY) {...}
   });

   // DESPUÉS
   radio.addEventListener('remotecontrol', e => {
       if (e.subtype === radio.REMOTE_CONTROL_PLAY) {...}
   });
   ```

---

## Tiempo Estimado de Implementación

| Fase                          | Estimación      |
| ----------------------------- | --------------- |
| Fase 1: Esqueleto             | 2-3 horas       |
| Fase 2: Android Core          | 6-8 horas       |
| Fase 3: Android Refinamientos | 4-6 horas       |
| Fase 4: iOS Core              | 4-6 horas       |
| Fase 5: iOS Refinamientos     | 2-3 horas       |
| Fase 6: Integración           | 2-3 horas       |
| **Total**                     | **20-29 horas** |

---

---

## Código Completo de TiMediaSession a Reutilizar

### MediaActionReceiver.java (OBLIGATORIO)

Este archivo maneja los clicks en los botones de la notificación:

```java
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
```

### Constantes a Exponer en el Módulo

En `AudiostreamModule.java`:

```java
// Remote Control Constants
@Kroll.constant public static final int REMOTE_CONTROL_PLAY = 100;
@Kroll.constant public static final int REMOTE_CONTROL_PAUSE = 101;
@Kroll.constant public static final int REMOTE_CONTROL_STOP = 102;
@Kroll.constant public static final int REMOTE_CONTROL_PLAY_PAUSE = 103;
@Kroll.constant public static final int REMOTE_CONTROL_NEXT = 104;
@Kroll.constant public static final int REMOTE_CONTROL_PREV = 105;
@Kroll.constant public static final int REMOTE_CONTROL_START_SEEK_BACK = 106;
@Kroll.constant public static final int REMOTE_CONTROL_END_SEEK_BACK = 107;
@Kroll.constant public static final int REMOTE_CONTROL_START_SEEK_FORWARD = 108;
@Kroll.constant public static final int REMOTE_CONTROL_END_SEEK_FORWARD = 109;

// Audio Focus Constants (opcional, si quieres exponerlas)
@Kroll.constant public static final int AUDIOFOCUS_GAIN = 1;
@Kroll.constant public static final int AUDIOFOCUS_LOSS = -1;
@Kroll.constant public static final int AUDIOFOCUS_LOSS_TRANSIENT = -2;
@Kroll.constant public static final int AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK = -3;
```

### timodule.xml Completo (Android)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<ti:module xmlns:ti="http://ti.tidev.io" xmlns:android="http://schemas.android.com/apk/res/android">

    <android xmlns:android="http://schemas.android.com/apk/res/android">
        <manifest>
            <!-- Permisos -->
            <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
            <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
            <uses-permission android:name="android.permission.WAKE_LOCK" />
            <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
            <uses-permission android:name="android.permission.INTERNET" />

            <application>
                <!-- Foreground Service -->
                <service
                    android:name="ti.audiostream.MediaPlaybackService"
                    android:exported="false"
                    android:foregroundServiceType="mediaPlayback"
                    android:stopWithTask="false" />

                <!-- BroadcastReceiver para botones de notificación -->
                <receiver
                    android:name="ti.audiostream.MediaActionReceiver"
                    android:exported="false">
                    <intent-filter>
                        <action android:name="ti.audiostream.PLAY" />
                        <action android:name="ti.audiostream.PAUSE" />
                        <action android:name="ti.audiostream.STOP" />
                        <action android:name="ti.audiostream.PLAY_PAUSE" />
                        <action android:name="ti.audiostream.NEXT" />
                        <action android:name="ti.audiostream.PREV" />
                    </intent-filter>
                </receiver>
            </application>
        </manifest>
    </android>

</ti:module>
```

### handleMediaAction en el Módulo

```java
public static void handleMediaAction(String action, KeyEvent keyEvent)
{
    if (action == null) return;

    int subtype = -1;

    switch (action) {
        case "ti.audiostream.PLAY":
            subtype = REMOTE_CONTROL_PLAY;
            break;
        case "ti.audiostream.PAUSE":
            subtype = REMOTE_CONTROL_PAUSE;
            break;
        case "ti.audiostream.STOP":
            subtype = REMOTE_CONTROL_STOP;
            break;
        case "ti.audiostream.PLAY_PAUSE":
            subtype = REMOTE_CONTROL_PLAY_PAUSE;
            break;
        case "ti.audiostream.NEXT":
            subtype = REMOTE_CONTROL_NEXT;
            break;
        case "ti.audiostream.PREV":
            subtype = REMOTE_CONTROL_PREV;
            break;
    }

    if (subtype != -1) {
        fireRemoteControlEvent(subtype);
    }
}

private static void fireRemoteControlEvent(int subtype)
{
    if (instance == null) return;

    KrollDict payload = new KrollDict();
    payload.put("subtype", subtype);
    instance.fireEvent("remotecontrol", payload);
}
```

### PendingIntents para Notificación

```java
private PendingIntent createActionIntent(String action)
{
    Intent intent = new Intent(action);
    intent.setPackage(getPackageName());

    int flags = PendingIntent.FLAG_UPDATE_CURRENT;
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
        flags |= PendingIntent.FLAG_IMMUTABLE;
    }

    return PendingIntent.getBroadcast(this, 0, intent, flags);
}

// Uso en buildNotification():
PendingIntent playIntent = createActionIntent("ti.audiostream.PLAY");
PendingIntent pauseIntent = createActionIntent("ti.audiostream.PAUSE");
PendingIntent nextIntent = createActionIntent("ti.audiostream.NEXT");
PendingIntent prevIntent = createActionIntent("ti.audiostream.PREV");
```

### iOS: Constantes Equivalentes

En `TiAudiostreamModule.m`:

```objc
MAKE_SYSTEM_PROP(REMOTE_CONTROL_PLAY, 100);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_PAUSE, 101);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_STOP, 102);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_PLAY_PAUSE, 103);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_NEXT, 104);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_PREV, 105);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_START_SEEK_BACK, 106);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_END_SEEK_BACK, 107);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_START_SEEK_FORWARD, 108);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_END_SEEK_FORWARD, 109);

MAKE_SYSTEM_PROP(AUDIOFOCUS_GAIN, 1);
MAKE_SYSTEM_PROP(AUDIOFOCUS_LOSS, -1);
MAKE_SYSTEM_PROP(AUDIOFOCUS_LOSS_TRANSIENT, -2);
MAKE_SYSTEM_PROP(AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK, -3);
```

---

## Recursos Externos

- [ExoPlayer Documentation](https://exoplayer.dev/)
- [Android Media Session Guide](https://developer.android.com/guide/topics/media-apps/working-with-a-media-session)
- [Android Audio Focus Guide](https://developer.android.com/guide/topics/media-apps/audio-focus)
- [AVPlayer Documentation](https://developer.apple.com/documentation/avfoundation/avplayer)
- [MPNowPlayingInfoCenter](https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter)
- [Titanium Module Development](https://titaniumsdk.com/guide/Titanium_SDK/Titanium_SDK_How-tos/Extending_Titanium_Mobile/Titanium_Module_Concepts.html)

---

*Documento creado: Enero 2026*
*Última actualización: Enero 2026*
