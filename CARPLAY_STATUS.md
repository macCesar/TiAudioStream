# CarPlay Status — TiAudioStream

## Estado real al 2026-04-10

La integración de CarPlay en `ti.audiostream` quedó en un estado usable pero no completamente resuelto para apps Titanium.

### Qué quedó funcionando

- `NotiGAPE` y `AudiostreamTest` muestran la lista de estaciones en CarPlay.
- La selección de estaciones desde CarPlay sí llega a JS y sí cambia la reproducción en la app host.
- La metadata manual, artwork y `playbackState` sí se publican al sistema.
- `NotiGAPE` volvió a cambiar correctamente la carátula del programa actual al cambiar de estación.
- `AudiostreamTest` sigue mostrando metadata/artwork dinámicos del stream.

### Qué sigue pendiente

- Las apps Titanium **no son adoptadas de forma consistente** como fuente activa en el sidebar de CarPlay desde `cold start`.
- La vista de reproducción del sistema (`Now Playing`) **no es confiable** desde la primera apertura en apps Titanium.
- La app nativa de comparación `CarPlayNowPlayingProbe` sí es adoptada correctamente y sigue siendo la referencia funcional.

## Cierre real de esta tanda

Quedaron tres conclusiones claras:

- **El problema principal sigue siendo el `cold start ownership`**: CarPlay sigue sin adoptar de forma consistente a `NotiGAPE` o `AudiostreamTest` como fuente activa al abrir el display por primera vez.
- **La regresión de artwork sí quedó corregida**: `NotiGAPE` ya vuelve a cambiar la imagen del programa actual al cambiar de estación, igual que su mini-player.
- **Se dejó un fallback de navegación más limpio**: la lista de CarPlay ya no depende del row manual `Now Playing`, y el browse quedó más usable aunque el ownership siga pendiente.

En corto:

- `Now Playing` desde `cold start`: **pendiente**
- cambio de carátula del programa actual en `NotiGAPE`: **corregido**
- lista/browsing de estaciones: **funcionando**
- modo lista-only en CarPlay Titanium: **habilitado**
- marcador de estación activa en browse: **ajustado en 1.2.7**

## Hallazgo importante de hoy

Durante varias pruebas, Titanium estaba reutilizando una build vieja del host app.

Síntoma:

- `tn iphone` o `ti build` llegaban a `Skipping xcodebuild`

Consecuencia:

- se copiaba una librería nueva del módulo
- pero la app host no siempre era relinkada contra ese binario nuevo

Conclusión:

- varias pruebas anteriores no eran totalmente confiables
- las pruebas válidas se hicieron con:

```bash
ti build -p ios -F iphone -T simulator --force
```

## Qué sí funciona hoy

### Módulo iOS

- `MPNowPlayingSession` creada y activada en iOS 16+
- fallback a centros compartidos (`MPNowPlayingInfoCenter.defaultCenter` y `MPRemoteCommandCenter.sharedCommandCenter`)
- publicación de `nowPlayingInfo` y `playbackState`
- artwork manual y app icon fallback
- comandos remotos registrados en centros de sesión y compartidos
- `togglePlayPauseCommand`
- delegates de escenas:
  - `TiAudiostreamCarPlaySceneDelegate`
  - `TiAudiostreamWindowSceneDelegate`
- lista raíz de CarPlay con `CPListTemplate`
- estación actual persistida y lista de estaciones persistida
- selección de estación desde CarPlay hacia JS con `automotivestationselected`
- logs/snapshots detallados de sesión, metadata, artwork, playback rate y conexión de CarPlay
- browse list en modo lista-only, sin row manual `Now Playing`
- actualización in-place de items en la lista para evitar reconstruir toda la plantilla al cambiar de estación

### Módulo Android

- API Automotive alineada:
  - `setAutomotiveStations(...)`
  - `setCurrentAutomotiveStation(...)`
  - evento `automotivestationselected`
- persistencia de lista y estación actual
- semántica de `setStream()` alineada para no borrar metadata implícitamente

### NotiGAPE

- bundle id iOS corregido a `com.grupogape.notigape`
- `UIApplicationSceneManifest` presente
- entitlements de CarPlay presentes
- lista de estaciones y estación actual publicadas al módulo
- caché local de estaciones y última estación
- selección desde CarPlay sincronizada de regreso a la UI de la app
- al cambiar estación desde CarPlay:
  - la app sí cambia de frecuencia
  - sí actualiza programa
  - sí actualiza artwork en la UI

## Problema principal (diagnosticado 2026-04-10)

CarPlay no adoptaba a la app Titanium como fuente activa de audio en el sidebar.

### Hipótesis corregida

Tres cables desconectados entre el scene delegate y el módulo:

1. `TiAudiostreamCarPlayDidConnectNotification` estaba **definida pero NUNCA se posteaba** desde el scene delegate
2. `handleCarPlaySceneDidConnect:` existía en el módulo pero **NUNCA se registraba** como observer
3. `handleCarPlaySceneDidConnect:` era un **stub vacío** — solo hacía log

Resultado esperado: cuando CarPlay conectaba mientras el audio ya estaba reproduciéndose, el módulo debía enterarse y reassertar la sesión Now Playing.

Un ajuste UX previo (remover auto-push de Now Playing en `scene-connect`) empeoró el síntoma porque el push condicional que lo reemplazó dependía de que el módulo primero hiciera la reasserción... que nunca ocurría.

### Fix aplicado, pero insuficiente

- Scene delegate ahora postea la notificación después de `setRootTemplate` exitoso
- Módulo registra el observer en `startup`
- Handler reasserts: re-activa AVAudioSession, re-publica Now Playing, re-registra remote commands, llama `becomeActiveIfPossible`
- Auto-push condicional de Now Playing con 0.5s delay (solo si hay playback activo)
- `reassertNowPlayingContextForReason:` convertido de stub a funcional con reintentos

### Estado validado

El fix sí mejoró los logs internos y confirmó que el módulo tiene metadata válida al conectar CarPlay, pero **no resolvió** la adopción inicial del sidebar ni el `Now Playing` vacío desde `cold start`.

## Comparación contra la app nativa

`CarPlayNowPlayingProbe` sí hace esto correctamente:

- al abrirla desde el simulador, CarPlay cambia el icono lateral a la app nativa
- `Now Playing` aparece con metadata
- `Now Playing` muestra fondo con artwork
- `play/pause` funciona

Eso prueba que el simulador sí puede mostrar metadata y artwork.

También acota el problema:

- el fallo no está en CarPlay “en abstracto”
- el fallo está en cómo una app Titanium queda adoptada como fuente activa

## Ajustes realizados en iOS

### 1. Escenas CarPlay

Se agregaron:

- `ios/Classes/TiAudiostreamCarPlaySceneDelegate.h`
- `ios/Classes/TiAudiostreamCarPlaySceneDelegate.m`
- `ios/Classes/TiAudiostreamWindowSceneDelegate.h`
- `ios/Classes/TiAudiostreamWindowSceneDelegate.m`

Objetivo:

- participar correctamente en el `UIApplicationSceneManifest`
- separar escena normal y escena CarPlay

### 2. Swizzle de configuración de escenas

Se implementó un `swizzle` en:

- `ios/Classes/TiAudiostreamModule.m`

Intercepta:

- `application:configurationForConnectingSceneSession:options:`

Y despacha:

- `CPTemplateApplicationSceneSessionRoleApplication` → `TiAudiostreamCarPlaySceneDelegate`
- `UIWindowSceneSessionRoleApplication` → `TiAudiostreamWindowSceneDelegate`
- otros casos → original de Titanium

Resultado:

- el swizzle sí entra
- CarPlay sí conecta la escena
- pero no resolvió la adopción como fuente activa

### 3. Dual-publishing como la probe nativa

Se replicó el patrón de la app nativa:

- publicación a `MPNowPlayingSession.nowPlayingInfoCenter`
- publicación también a `MPNowPlayingInfoCenter.defaultCenter`
- registro de comandos en:
  - `session.remoteCommandCenter`
  - `MPRemoteCommandCenter.sharedCommandCenter`

Resultado:

- tampoco resolvió por sí solo la adopción de la fuente activa

### 4. Reasserts de contexto Now Playing

Se agregaron reafirmaciones de contexto al:

- conectar CarPlay
- presentar `Now Playing`
- cambiar la ruta de audio

Resultado:

- los snapshots muestran metadata válida
- pero CarPlay sigue sin adoptar consistentemente la app como fuente activa

### 5. Corrección de regresión en `setStream()`

Se detectó una regresión real:

- `NotiGAPE` mandaba metadata manual con `setMetadata(...)`
- luego llamaba `setStream({ url, isLive, autoUpdateMetadata })`
- `setStream()` volvía a limpiar `title`, `artist` y `artwork`

Se corrigió en:

- `ios/Classes/TiAudiostreamModule.m`

Estado actual:

- la metadata ya no se borra si `setStream()` no recibe explícitamente `title`, `artist` o `artwork`
- los snapshots válidos ya muestran:
  - `title='NotiGAPE Estatal 1era. Emisión'`
  - `artist='104.1 Nvo. Laredo - Laredo'`
  - `artwork=YES`
  - `playbackState=1`

### 6. Ajuste UX en CarPlay list

Se detectó un mal comportamiento:

- al cambiar estación desde la app host o refrescar estaciones
- CarPlay brincaba o parpadeaba hacia `Now Playing`
- pero `Now Playing` seguía vacío

Se ajustó `TiAudiostreamCarPlaySceneDelegate.m` para:

- dejar de empujar automáticamente `Now Playing`
- quitar el row manual `Now Playing` / `Open current playback`
- dejar la raíz en modo lista

Objetivo:

- mantener estable la lista
- evitar el salto a un `Now Playing` vacío
- dejar una UX honesta mientras el ownership siga pendiente

### 7. Corrección de metadata parcial / artwork persistente

Se detectó otro bug real separado del ownership:

- `setMetadata()` estaba borrando `title`, `artist` y `artwork` cuando el payload no incluía explícitamente todos los campos.

Se corrigió para:

- preservar metadata existente cuando el caller solo actualiza un subconjunto
- evitar que cambios parciales vacíen la carátula actual

Resultado confirmado:

- `AudiostreamTest` siguió cambiando artwork dinámico correctamente
- `NotiGAPE` recuperó el cambio de imagen del programa actual al cambiar de estación

### 8. Ajuste de browse en 1.2.6 y 1.2.7

Se detectó otro problema de UX en la lista de CarPlay:

- la estación seleccionada no parecía quedarse marcada
- CarPlay terminaba resaltando el primer renglón visible
- esto ocurría porque el delegate reconstruía toda la lista y perdía el foco del item tocado

Se corrigió en `1.2.6`:

- se eliminó la fila fija superior de “estación actual”
- la lista ya no se reconstruye completa al cambiar estación
- los `CPListItem` se actualizan in-place

Después se detectó que `CPListItem.playing = YES` causaba otro efecto visual confuso:

- CarPlay podía mostrar doble resaltado gris
- el foco visual podía quedarse en un renglón distinto al activo
- al tocar una estación, el estado `playing` peleaba contra la selección temporal del sistema

Se ajustó en `1.2.7`:

- ya no se usa `CPListItem.playing` para marcar la estación activa
- la estación activa se indica con el subtítulo `On Air • ...`
- la lista conserva actualización in-place
- no se fuerza selección ni scroll porque `CPListTemplate` no expone una API pública para eso

Resultado esperado:

- el browse debe ser más legible y estable
- el usuario puede identificar la estación activa sin depender del highlight gris del sistema

## Estado del documento

Este archivo ya quedó alineado con:

- fallback lista-only
- corrección de artwork en `NotiGAPE`
- eliminación del row manual `Now Playing`
- marcador estable de estación activa en browse (`1.2.7`)

Lo que **no** está marcado como resuelto, porque no lo está, es:

- adopción inicial de fuente activa en el sidebar
- confiabilidad total de la vista del sistema `Now Playing` en apps Titanium

### 9. Ajuste JS en NotiGAPE para fijar artwork inicial del stream

Se ajustó `audioService.js` para que `controlStreamer()` mande también al módulo:

- `title`
- `artist`
- `artwork`

dentro del `setStream(...)` inicial, en lugar de depender solo de un `setMetadata(...)` separado.

Objetivo:

- arrancar el item nuevo ya con su imagen correcta
- evitar la carrera entre `setMetadata()` y `setStream()`
- alinear mejor el mini-player de la app con el `Now Playing` del sistema

### 10. Fallback lista-only en CarPlay

Se removió del `CPListTemplate` el renglón:

- `Now Playing`
- `Open current playback`

Motivo:

- en Titanium seguía llevando con frecuencia a una pantalla vacía
- el browse/listado de estaciones sí es confiable
- la estación actual y el catálogo siguen funcionando sin obligar al usuario a entrar a un `Now Playing` inconsistente

Este cambio **no arregla** el ownership inicial de CarPlay.
Solo cambia la UX para que la integración quede usable mientras ese bug sigue pendiente.

## Cambios realizados en NotiGAPE

Archivo principal:

- `/Users/cesar/Developer/Apps/notiGAPE/app/lib/services/audioService.js`

Cambios relevantes:

- serialización de estaciones a payload Automotive
- persistencia local de lista de estaciones
- persistencia local de estación actual
- escucha de `automotivestationselected`
- reconstrucción correcta de la estación seleccionada desde CarPlay
- republicación de metadata manual al sincronizar selección Automotive
- corrección de artwork roto cuando no existe `conductor.filename`

Otros archivos ajustados:

- `/Users/cesar/Developer/Apps/notiGAPE/tiapp.xml`
- `/Users/cesar/Developer/Apps/notiGAPE/build-titanium.sh`
- `/Users/cesar/Developer/Apps/notiGAPE/build-seguro.sh`

## Estado observable más reciente

### En corrida válida con rebuild forzado

Antes de abrir CarPlay, el módulo ya tenía:

- `session=YES active=YES`
- `playerRate=1.00`
- `title='NotiGAPE Estatal 1era. Emisión'`
- `artist='104.1 Nvo. Laredo - Laredo'`
- `artwork=YES`
- `playbackState=1`

Al abrir CarPlay:

- la escena de CarPlay sí conecta
- la lista de estaciones sí aparece
- el sidebar no adopta a `NotiGAPE` como fuente activa
- si se entra a `Now Playing`, puede seguir vacío

## Hallazgo nuevo: adopción tardía / transferencia de fuente

Se encontró un patrón reproducible que cambia el diagnóstico.

Escenario:

1. `AudiostreamTest` estaba reproduciendo y ya visible en CarPlay
2. se abrió `NotiGAPE` en el simulador
3. se puso a reproducir una estación en `NotiGAPE`
4. se cerró `AudiostreamTest`

Resultado:

- el icono del sidebar cambió al de `NotiGAPE`
- `Now Playing` de `NotiGAPE` sí mostró metadata
- el fondo sí tomó los colores/artwork del programa actual
- los tres controles sí quedaron activos
- `prev/next` ya hicieron round-trip contra `NotiGAPE`

Conclusión:

- Titanium sí puede llegar a ser adoptado como fuente activa por CarPlay
- el problema no es un “no se puede”
- el problema real parece ser el `cold start` / `initial ownership`
- CarPlay puede transferir ownership hacia `NotiGAPE`, pero no lo está haciendo desde cero

Esto vuelve mucho más importante comparar contra la probe nativa el momento exacto en que la app se vuelve fuente activa.

### Comportamiento de la fila “Resume …”

La fila gris `Resume ...`:

- no es un error por sí misma
- representa la estación actual persistida como “última estación”

Lo incorrecto era:

- que al tocar o refrescar estaciones CarPlay brincara a `Now Playing` vacío

Ese comportamiento se ajustó en el delegate para dejar la lista estable.

## AudiostreamTest: ajuste reciente de UX

En `AudiostreamTest` se confirmó y corrigió un problema visual del delegate:

- antes, al refrescar estaciones o cambiar playback, la lista podía reinstalar la raíz y provocar un parpadeo breve
- también el renglón superior usaba `Resume ...` aunque la estación ya estuviera reproduciendo

Se ajustó `TiAudiostreamCarPlaySceneDelegate.m` para:

- actualizar las secciones de la lista con `updateSections:` en lugar de reinstalar siempre la raíz
- dejar de anteponer `Resume ` al renglón de estación actual

Resultado observado:

- la lista de `AudiostreamTest` ya no parpadea
- el renglón gris superior dejó de quedarse pegado con `Resume ...`

Nota de UX:

- hoy `AudiostreamTest` muestra:
  - `Now Playing`
  - una fila dinámica con la estación/canción actual
  - luego el catálogo de estaciones
- esto funciona, aunque todavía puede refinarse para que la fila dinámica no duplique visualmente una estación del catálogo

## Lectura técnica actual

La evidencia acumulada hoy apunta a esto:

- no era sólo metadata faltante
- no era sólo `MPNowPlayingSession`
- no era sólo el dispatch de escenas
- no era sólo una build vieja del host app

Hoy el cuello más fuerte sigue siendo:

- qué condición adicional hace que CarPlay adopte a la app Titanium como fuente activa en el sidebar desde un arranque en frío

Mientras ese icono lateral no cambie, `Now Playing` seguirá siendo poco confiable aunque el módulo ya tenga metadata correcta.

## Siguiente foco técnico

Si el fix no resuelve la adopción del sidebar, comparar quirúrgicamente contra `CarPlayNowPlayingProbe`:

1. timing exacto de `AVAudioSession setActive:YES`
2. timing exacto de `MPNowPlayingSession becomeActiveIfPossible`
3. orden entre `play`, `updateNowPlaying` y conexión de CarPlay
4. qué señal concreta hace que el sidebar adopte a la app nativa como fuente activa
5. por qué la transferencia de ownership sí ocurre cuando ya existe otra fuente activa en CarPlay

## Resumen corto

Ya quedó:

- browsing de CarPlay
- lista de estaciones
- persistencia de última estación
- selección desde CarPlay a la app host
- metadata viva en la sesión
- rebuild forzado confiable
- notificación de conexión CarPlay → módulo (era stub)
- reasserción de Now Playing al conectar CarPlay con playback activo
- auto-push condicional de Now Playing con delay
- lista estable sin parpadeo en `AudiostreamTest`
- evidencia de transferencia de ownership de una app a otra dentro de CarPlay

Pendiente de validación:

- que CarPlay adopte a la app Titanium como fuente activa en el sidebar desde cold start
- que `Now Playing` aparezca con metadata al entrar desde el sidebar
