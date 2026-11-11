# Ejecución de PLAN_AUDITORIA.md

Fecha: 2026-11-10. Rama: `fix/auditoria-estabilizacion`. Base: `1f39899774ef3b9fa6b5d5afc6ff0058e413fe3c`.

Se implementó la estabilización de reproducción, metadatos, imágenes, playlists, acceso al servicio y dependencias. Se conserva la API y la diferencia entre pausa, parada suave y parada completa. No se crearon commits, tags ni releases; los manifests se actualizaron a 2.0.0 por petición de César. Los paquetes se generan en `ios/dist` y `android/dist`; esto no crea una publicación en GitHub.

## Cobertura del plan

| Fase | Cambios realizados |
| --- | --- |
| 1 | Intención de reproducción separada del estado, cancelación de reintentos/reanudación, guardas KVO tras stop, estado foreground real y errores de arranque/foco. La prueba en OPPO descubrió y permitió corregir una carrera adicional de hardStop/setStream/start. |
| 2 | Metadatos recibidos separados de los publicados, campos manuales omitidos conservados, borrado explícito, texto inmediato y sustituciones regex inválidas contenidas. |
| 3 | Identidad por petición de imagen y por fila CarPlay, fallback ante fallo/borrado, caché y URIs locales Android para catálogo/reanudación/reproducción, permisos a lectores multimedia conocidos y clientes de navegación tardíos. FileProvider continúa no exportado. Límites de descarga y downsampling. |
| 4 | M3U/PLS relativas y firmadas, queries/fragmentos, detección HLS y conservación de su MIME en reconexiones, preparación en frío, descarte de resoluciones antiguas y clasificación de errores anidados/temporales. |
| 5 | Capacidad privada por proceso para órdenes internas; navegador y transporte legítimos conservados. Dependencias actualizadas y comprobadas tanto en módulo como en app consumidora. |
| 6 | Carga HTTP/playlists y decodificación de imágenes aisladas en helpers iOS; fuentes Android tipadas y diagnóstico separado. Logs detallados iOS apagados por defecto; Android respeta configuración Titanium y redacta URLs. Alias play en ambas plataformas; búsqueda nativa de catálogo Android implementada y Lint satisfecho. |

La migración completa de sesiones Android a Media3, la retirada de APIs CarPlay obsoletas y las extracciones estructurales más amplias quedan como trabajo posterior a la estabilización, sin cambiar contratos públicos en esta entrega. F18 sigue aceptado provisionalmente: no se parchearon assets regenerados.

## Resultados reproducibles

| Verificación | Resultado |
| --- | --- |
| `python3 tests/android_regressions.py` | 60 comprobaciones satisfactorias |
| `python3 tests/ios_regressions.py` | 24 comprobaciones satisfactorias |
| `python3 tests/ios_content.py` | 17 comprobaciones satisfactorias, HTTP local real |
| `python3 tests/carplay_regressions.py` | 4 comprobaciones satisfactorias de callbacks asíncronos |
| Android, Titanium 13.4.1.GA | Compilación y paquete correctos; 4 ABI |
| Requisito Android actualizado | Titanium 13.4.1.GA+, compileSdk 36+; minSdk de dispositivo 24 |
| iOS, Titanium 13.4.1.GA / Xcode 27.2 | Dispositivo arm64; simulador y Mac Catalyst arm64+x86_64 correctos; deployment target 15 |
| Analizador iOS | ANALYZE SUCCEEDED; sin avisos de análisis de flujo tras excluir trabajo exclusivo de diagnóstico. Persisten advertencias del SDK, APIs obsoletas y generador F18 |
| Android Lint | 0 errores, 7 advertencias: herramientas/recursos/integración Titanium; búsqueda por voz ya no produce error |
| Estáticas | 5 XML correctos, sintaxis JS correcta, `git diff --check` correcto |
| ZIP | Integridad correcta y xcframework con las 3 variantes/arquitecturas anteriores |

Los tests de métodos compilan código de producción con sustitutos del sistema: demuestran regresiones concretas, no equivalen a ejecutar un MediaSession, AVPlayer o automóvil completos. Hubo ciclos fallo/corrección para pausa/reanudación, KVO, publicación de título, errores anidados, regex, cambios durante preparación, playlists firmadas/HLS, catálogo, cambios de política de imágenes y ciclo de vida foreground. Quitar la guarda de identidad de fila CarPlay también hace fallar su prueba.

## Pruebas físicas

La actualización final de dependencias afecta Android; el OPPO completó de nuevo 16/16 comprobaciones con Media3 1.11.1/Guava 33.8.0. Las versiones se confirmaron también en la resolución Gradle de la app consumidora. Los resultados iPad corresponden a la implementación iOS sin cambios, basada en frameworks del sistema.

Se copió Audio Stream Test a una ubicación temporal, con identificador `mx.codigomovil.audiostreamaudit`, sin modificar las fuentes ni sustituir la app original. Se instaló el módulo compilado y el guion versionado en `tests/device/app.js`.

- **iPad de 9.ª generación, iPadOS 27.2:** 16/16 comprobaciones correctas.
- **OPPO CPH2639, Android API 36:** 16/16 comprobaciones correctas tras corregir la carrera foreground.
- En ambos: audio directo, start repetido, eventos de metadatos con publicación automática desactivada, pausa persistente, parada suave, alias play, PLS/M3U relativas tras hardStop y cancelación de reintento pendiente.
- En ambos: reproducción y pausa de **Radio Paradise**, **Heart London HLS** y **The VIP Lounge 2** desde sus servidores públicos.
- Android recibió metadatos reales de las tres emisoras; iPad de Heart y VIP durante la ventana de observación. Radio Paradise reprodujo en iPad, pero no llegó título durante esos 12 segundos.
- La inspección Android de MediaSession durante la fase manual mostró `Updated Title, Manual Artist`, mientras el evento recibido contenía `Fixture Song, Fixture Artist`.

Los resultados completos están en [android.json](results/android.json) e [ipad.json](results/ipad.json). La primera ejecución de iPad quedó esperando el permiso de red local; se repitió después de autorizarlo. Las señales controladas procedían de la Mac y enviaban audio sintético/metadatos ICY conocidos; las tres emisoras públicas se comprobaron por separado dentro del mismo guion.

La primera ejecución Android se cerró con `ForegroundServiceDidNotStartInTimeException` al encadenar hardStop y otra estación. Se reprodujo la pérdida de órdenes con start IDs en la regresión, se sustituyó stopSelf incondicional por parada condicionada al ID entregado y se atendió foreground antes de salidas tempranas. La repetición física completa pasó sin ese cierre. La autorización de parada pendiente se libera también cuando falla la entrega de la orden.

## Dependencias y decisiones

- **Media3 1.11.1**, todos los componentes alineados en la versión estable vigente; requiere compileSdk 36. El requisito Android se eleva a **Titanium 13.4.1.GA+**, comprobado también en el manifest. La selección anterior de 1.9.4 para conservar compatibilidad antigua quedó revocada por César: la prioridad explícita es actualizar las librerías y documentar la transición.
- **Guava 33.8.0-android**, estable vigente; **AndroidX Media 1.8.0**; **Error Prone 2.52.0**, **Checker Qual 4.4.0**, **JSR305 3.0.2**. Las constraints mantienen alineadas las anotaciones entre compilación y runtime.
- Los errores de reproductor de ambas plataformas pueden emitir error antes de un reintento y volver después a buffering. Un error aislado no demuestra que se hayan agotado los reintentos; el consumidor debe consultar state. Esta descripción corrige la imprecisión anterior del informe, que atribuía a Android notificación exclusivamente terminal.
- El trabajo permanece en la nueva rama del checkout compartido, sin worktree adicional ni integración Git. Las primeras compilaciones usaron una copia temporal para preservar el banco de pruebas original; el empaquetado 2.0.0 se realiza desde este repositorio.

Referencias de versiones: [Media3](https://developer.android.com/jetpack/androidx/releases/media3), [AndroidX Media](https://developer.android.com/jetpack/androidx/releases/media), [Guava 33.8.0](https://github.com/google/guava/releases/tag/v33.8.0).

## Aceptación pendiente y límites

No se certificaron automóvil físico/arranque en frío/búsqueda por voz, Bluetooth, desconexión real de auriculares, suspensión prolongada ni lectores OEM de carátulas. El lector y URI exactos del caso de Patrick siguen pendientes; los permisos del código son una corrección fundada, no una reproducción confirmada de su dispositivo. Tampoco se certificó nitidez en coche/pantalla de bloqueo.

Permanece trabajo de decodificación de imágenes embebidas y del icono inicial en el hilo principal; los límites de memoria no son una medición de fluidez. Se conservan archivos de la sesión Android para lectores tardíos y solo se podan archivos de sesiones anteriores con más de 24 horas; una sesión muy larga puede acumular archivos. El sondeo HTTP previo añade una petición: endpoints de uso único o que limiten conexiones requieren aceptación específica. Playlists Android sin extensión y servidas con MIME binario arbitrario aún pueden caer al motor nativo.

La revisión independiente corrigió los cinco hallazgos importantes iniciales y aprobó sus correcciones; también se revisó la corrección foreground descubierta en el teléfono. Las condiciones anteriores permanecen explícitas y no se presentan como certificadas.

Evidencia extensa de compilación/análisis y paquetes de prueba: `/tmp/tiaudiostream-validation-T0nEmi`. Los tests y resultados pertinentes de este informe no dependen de que esa carpeta temporal siga existiendo.

## Intento posterior de integración CarPlay

A petición de César se preparó y compiló una app interactiva con catálogo de dos estaciones, imágenes de colores y una respuesta de imagen retrasada (`tests/device/carplay.js`, `carplay_serve.py`). La compilación para iOS Simulator 27.2 fue correcta. **La escena CarPlay no se pudo ejecutar ni validar visualmente.**

La opción CarPlay Simulator de Device Hub aparece deshabilitada para el dispositivo simulado. Apple documenta que Device Hub/Xcode27.2 requiere conexión USB de un dispositivo físico y no admite iOS Simulator para CarPlay: [notas oficiales](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes). El iPad conectado no sustituye un iPhone con CarPlay. Esta limitación se investigó ahora; no fue una comprobación realizada durante la entrega inicial.

Crear un simulador adicional fue innecesario y contrario a la instrucción de César de reutilizar los existentes. Se eliminó únicamente el nuevo TiAudioStream CarPlay QA y se detuvo su servidor de fixtures. El código de producto no se modificó durante este intento. La evidencia temporal de compilación permanece en `/tmp/tiaudiostream-carplay-BouE97/build.log`.

## Empaquetado 2.0.0

Por petición de César, ambos manifests se actualizaron a **2.0.0**. Se recompilaron desde este repositorio con `ti build -p ios --build-only --sdk 13.4.1.GA` y `ti build -p android --build-only --sdk 13.4.1.GA`, dentro de la carpeta de cada plataforma. Ambas compilaciones finalizaron correctamente; se verificaron integridad ZIP y manifest interno 2.0.0.

- `ios/dist/ti.audiostream-iphone-2.0.0.zip`, SHA-256 `e165192e3be2ca72e634d9214cab7275a25a7ebd8c8d890b711a8918260845ed`.
- `android/dist/ti.audiostream-android-2.0.0.zip`, SHA-256 `6eee64cfdf7eaf9637d3cf7fd02488f9eba42111913e660bc5f727d4b409fd76`.

Logs: `/tmp/tiaudiostream-2.0.0-ios-build.log` y `/tmp/tiaudiostream-2.0.0-android-build.log`. Esta recompilación no añade aceptación visual de CarPlay ni confirma la nitidez o el lector OEM del caso de Patrick. No sustituye los módulos instalados en NotiGAPE ni crea commits, tags o releases. Los paquetes finales se copiaron al proyecto Audio Stream Test.

## Respuesta de eventos y segunda pasada

Se corrigieron F19–F21 añadidos a `PLAN_AUDITORIA.md`: Android anuncia buffering durante resolución HTTP y omite metadatos de la fuente anterior mientras esa resolución sigue pendiente. `tests/android_buffering.py` pasó 11 comprobaciones tras fallar inicialmente con la respuesta HTTP retenida; las 60 regresiones Android existentes pasaron.

Medición física final con `tests/device/latency.js`: 28 comprobaciones Android y 22 iPad correctas. Tres repeticiones, sin escritura a disco dentro de los callbacks medidos. Android: buffering al cambiar con servidor lento 75–136 ms, arranque frío 193–256 ms; pausa 49–61 ms; stop 13–15 ms. Pausa durante resolución: 29 ms y sin reanudación posterior. iPad: buffering al cambiar 2 ms, arranque frío 7–24 ms; pausa 0–1 ms; stop 0 ms; pausa durante resolución 1 ms, sin reanudación posterior. Son resoluciones del reloj/observaciones, no ausencia de trabajo cuando figura 0 ms.

Las señales Android tienen títulos distintos: ningún evento recibido correspondió a la estación anterior. En el iPad no llegó ICY durante esta ventana; sus 22 comprobaciones no incluyen identidad de esos metadatos. La primera medición Android sobrepasó el presupuesto de feedback de 300 ms en el primer arranque (337 ms); se conserva en `results/latency-android-before-metadata-guard.json`, no se descarta para afirmar cumplimiento universal. Las tres repeticiones no establecen percentiles ni garantizan tiempos en otros dispositivos.

El endpoint lento retiene cabeceras 2 s por petición: el tiempo hasta playing fue 4.77–4.83 s en Android y 8.47–8.59 s en iPad; el reporte temprano de buffering no elimina ese tiempo ni constituye una optimización de conexiones. La matriz T06 exige analizar número/tipo de peticiones, espera del motor y trabajo principal antes de optimizarlos. No se midió latencia acústica.

Se retiró el temporizador de 100 ms de `Resources/app.js` en Audio Stream Test; ambos módulos 2.0.0 se copiaron al proyecto desde los ZIP finales. No se recompiló ni reinstaló la app original de César: las pruebas físicas usan exclusivamente `mx.codigomovil.audiostreamaudit`. NotiGAPE no se modificó en esta corrección. La segunda auditoría completa queda planificada, no certificada.


## Implementación posterior de la segunda auditoría

Los hashes anteriores corresponden a los paquetes de la primera pasada. El informe de la segunda pasada registra las correcciones F22–F34, la validación de los paquetes recompilados y las pruebas pendientes de CarPlay y lectores OEM. Las pruebas de esa fase se hicieron con la app descartable, sin reinstalar las apps originales de César. [Informe de la segunda pasada](SEGUNDA_PASADA.md) · [Hashes actuales](results/second-pass/packages.json)
