# Correcciones de la segunda auditoría (2.0.0)

Rama: `fix/auditoria-estabilizacion`. Fecha: 2026-11-10. Implementación autorizada por César después del diagnóstico. El informe original se conserva sin reescribir en `/Users/cesar/Developer/validation-evidence/TiAudioStream-audit2-20261110/AUDITORIA_SEGUNDA_PASADA.md`; sus expresiones «sin aplicar» describen el estado anterior a estas correcciones.

## Cambios y aceptación por hallazgo

| ID | Corrección implementada | Comprobación |
| --- | --- | --- |
| F22 | Listener Android por fuente y generación; también se comprueba su identidad para retries con la misma URL. Callbacks retirados no publican error, estado ni metadatos. | `android_transitions.py`: errores, metadatos y callbacks antiguos; pausa y destrucción. |
| F23 | `prepareFromMediaId(B)` retira el item A, configura B y permanece pausado hasta play; no adquiere foco durante prepare. | Regresión con métodos reales y controlador externo físico. |
| F24 | Resolver Android independiente, cancelación de Future y conexión HTTP; comprobar generación antes de conectar y al terminar. | HTTP real retenido: la selección nueva conecta sin liberar respuestas antiguas. |
| F25 | iOS retira el output de metadatos al cambiar URL aunque la preparación quede diferida; callbacks comprueban item/URL. | Regresión de selección pausada y metadatos tardíos. |
| F26 | Android retira audio/item anterior antes de resolver otra estación y anunciar su carga. | Orden stop/clear → buffering → preparación; pausa durante HTTP lento en dispositivo. |
| F27 | Retirar BOM UTF-8 antes de interpretar M3U. | Playlist local con BOM. |
| F28 | Comparación de MIME de playlist sin distinguir mayúsculas. | Respuestas HTTP con MIME mixto. |
| F29 | URLs con sufijo de audio nativo/HLS reconocido pasan directamente al motor en ambas plataformas. Las playlists sin extensión conservan resolución. | Pruebas del loader real y resolución Android. Esto elimina el sondeo en esos casos, no todas las peticiones del motor. |
| F30 | CarPlay valida strings, URLs e identificadores null; conserva identificadores numéricos y fallback a URL activa. | 29 regresiones iOS, incluidas entradas null/número. |
| F31 | Una descarga por URL pendiente, múltiples filas esperando; caché del resultado válido independiente de la reutilización de filas. | 7 regresiones CarPlay: coalescencia, cambio de fila y caché compartida. |
| F32 | iOS observa fin del item, publica stopped y permite reconstruirlo al reiniciar; duración/tiempo deben ser numéricos. Android también retira intención/foco al terminar. | EOF/restart físico y regresiones iOS. |
| R01 | Botones Android legacy/typed comprueban KeyEvent y contienen Parcelable malformado. | 6 regresiones, incluidos botones válidos en ambas rutas. |

## Hallazgos adicionales reproducidos durante la corrección

### F33. Gravedad alta, coordinación con SystemUI

Una orden Stop de una tarjeta multimedia anterior podía alcanzar un nuevo arranque todavía sin audio. La traza identificó al paquete `com.android.systemui` mediante `getCurrentControllerInfo`. La orden procedía de SystemUI y la app no tenía un temporizador que la enviara. La sesión se publica cuando hay reproducción efectiva. Durante la primera conexión se muestra una notificación de servicio normal con acción de pausa.

Mientras el arranque aún no tiene tarjeta publicada, se descarta únicamente el Stop de SystemUI. Una petición play explícita de SystemUI autoriza su cancelación inmediatamente. Los otros controladores conservan Stop durante buffering. Las sesiones retiradas dejan de reenviar callbacks. Esta guarda depende del estado de la sesión y prescinde de una ventana temporal. La regresión comprueba controles legítimos y callbacks retirados. Pasó la prueba instrumentada de 160 arranques, cuyo registro se conserva por separado del correspondiente al paquete final.

### F34. Gravedad alta, foco durante conexión

Perder foco mientras se resolvía una URL no siempre emitía paused. Si la preparación terminaba después, podía llamar play sin foco. Ahora esa pérdida de foco publica paused inmediatamente. La preparación exige foco y una petición activa de reproducción. READY sólo anuncia playing si `isPlaying()` lo confirma. Al recuperar foco se respeta la pausa o el stop del usuario. La prueba del listener real falló antes de la corrección y pasó después. También se ignoran callbacks de foco de un servicio destruido.

La validación posterior reprodujo F33 al cambiar de estación con la sesión activa. La traza atribuyó a SystemUI una orden Stop durante el `buffering` de la estación nueva. Ahora una selección válida desde la app también retira la tarjeta anterior antes de publicar los metadatos de la fuente nueva. La notificación de carga conserva Pausa y la tarjeta se activa al comenzar la reproducción. La regresión de transición falló antes de este ajuste y pasó después.

Las correcciones mantienen los timeouts de red y backoff existentes, sin añadir esperas para ocultar carreras. Aunque el player ya esté inicializado, cada fuente nueva necesita crear y preparar su item y recibir datos.

## Verificación

Las regresiones compilan métodos de producción con sustitutos pequeños del sistema. Pasaron **168 comprobaciones** (Android 63 + buffering 12 + transiciones 26 + receptor 6 + foco 8, iOS 29 + contenido 17 + CarPlay 7). [Resultados nativos](results/second-pass/native-regressions.json).

Ambos módulos se recompilaron desde este repositorio con `ti build -p <plataforma> --build-only --sdk 13.4.1.GA`. ZIP íntegro y manifest 2.0.0 verificados; hashes en [packages.json](results/second-pass/packages.json). Lint Android Release terminó con 0 errores y 6 advertencias: recursos por nombre, clases TLS del JAR de Titanium, servicio público multimedia y comprobación de SDK redundante. El informe íntegro se conserva con la evidencia externa. Las pruebas físicas usan exclusivamente la app descartable `mx.codigomovil.audiostreamaudit`, con MP3 silencioso y servidor determinista. NotiGAPE y Audio Stream Test originales no se modificaron en esta fase.

| Prueba física | Resultado / alcance |
| --- | --- |
| iPad, funcional | 129 comprobaciones correctas. |
| iPad, estabilidad final | 124 comprobaciones correctas; 1829.772 s de soak, más EOF/restart previo. Engine de este ZIP idéntico al probado; después sólo se endurecieron campos/IDs de CarPlay, comprobados con regresiones y compilación. |
| OPPO, diagnóstico instrumentado | 160/160 arranques; buffering mediana 186.5 ms, p95 256 ms, máximo 284 ms. Mismo proceso, servicio recreado; no son 160 lanzamientos fríos del proceso ni latencia acústica. |
| OPPO, paquete final | Primer intento incompleto: 60/60 reproducciones iniciales y 10/10 soft restart; múltiples presupuestos de 300 ms incumplidos. Hubo rechazo foreground con teléfono bloqueado y terminación del proceso antes de completar EOF. Se conserva [la muestra](results/second-pass/android-incomplete-locked.json); requiere repetición con el teléfono desbloqueado. |
| Controlador nativo externo en OPPO desbloqueado | Leyó el bitmap embebido de 512 × 512 y el URI de 1024 × 1024 desde otro paquete. Los hashes se conservaron al volver a publicar la misma imagen. Prepare/play seleccionó B, Stop impidió la reanudación tardía y el foco transitorio respetó la pausa manual. El banco marcó Stop como fallo al comparar la hora de la Mac con la del OPPO. El registro del teléfono confirma el Stop y el banco ahora compara secuencias de eventos del mismo dispositivo. [Resultados del controlador](results/second-pass/android-controller-unlocked.json). |
| OPPO, estabilidad por USB | 64 comprobaciones funcionales correctas en 575 s, incluidos EOF y reinicio. Dos arranques superaron 300 ms y el máximo fue 794 ms. La app de prueba siguió en segundo plano durante dos visitas a Audio Stream Test. La Mac perdió el dispositivo USB y con él la ruta a las señales. [Registro parcial](results/second-pass/android-soak-usb-interrupted.json). |
| OPPO, estabilidad por Wi‑Fi antes del ajuste final de F33 | 1861.103 s transcurridos, 152/154 comprobaciones. Los primeros 49 ciclos pasaron. En el ciclo 50 la app estaba en segundo plano cuando intentó reiniciar el servicio y Android rechazó dos arranques con `ForegroundServiceStartNotAllowedException`. La ejecución quedó suspendida hasta volver a primer plano y cerró entonces. En 49 arranques medidos, `buffering` tuvo mediana de 268 ms, p95 de 300 ms y máximo de 306 ms. Dos superaron 300 ms. [Registro de la corrida](results/second-pass/android-stability-wifi.json). |
| OPPO, funcional antes del ajuste final de F33 | 138/140 comprobaciones. `buffering` en los 60 arranques tuvo mediana de 193 ms, p95 de 282 ms y máximo de 342 ms. Un cambio adicional a A emitió `buffering` a los 77 ms y luego `stopped` un milisegundo después. [Registro funcional](results/second-pass/android-functional-wifi.json). |
| OPPO, cambios de estación después del ajuste final de F33 | Pasaron los 24 cambios de estación. La versión anterior instrumentada falló en 2 de 24 cambios. En los 240 pares Stop → Start separados por 10 ms del mismo ensayo, tres reinicios publicaron `playing` y enseguida `stopped`. La prueba final registró la secuencia sin identificar al emisor de esos tres Stop. [Registro anterior](results/second-pass/android-warm-before-fix.json) y [registro con el ZIP final](results/second-pass/android-warm-fixed.json). |
| OPPO, funcional con el ZIP final | 138/140 comprobaciones. Pasaron todas las de comportamiento, incluidos 60 arranques, 10 reinicios rápidos, cambio activo a A, pausa durante playlist lenta, selección rápida de C y fin/reinicio de archivo. Los dos fallos fueron de latencia de `buffering` (396 y 307 ms frente al objetivo de 300 ms). Mediana de 200 ms y p95 de 275 ms en 60 arranques. [Registro final](results/second-pass/android-functional-fixed.json). |
| Controlador nativo externo con el ZIP final | 33/33 comprobaciones, incluidos Stop durante la resolución, carátulas y recuperación de foco con y sin pausa manual. [Resumen](results/second-pass/android-controller-fixed.json). |

La primera prueba Android usó `adb reverse`. La repetición por Wi‑Fi recibió las señales y entregó resultados por la red local, igual que la prueba del iPad. Los tiempos miden desde la llamada JS hasta el evento del módulo. Se conservan las muestras fuera del presupuesto de 300 ms.

## Límites y pendientes reales

| Área | Estado y siguiente aceptación |
| --- | --- |
| CarPlay | Compilación y lógica de listas/imágenes comprobadas. Falta escena real con iPhone compatible; el iPad no la certifica. No se crearon simuladores adicionales. |
| Android Auto / OEM | Controlador nativo externo no equivale al coche ni a su UI. Falta aceptación en automóvil/DHU y sus lectores. |
| Nitidez de Patrick | Se comprueban permisos, dimensiones y contenido con imagen determinista desde otro paquete. Falta su archivo/dispositivo/lector y comparación visual en su superficie. |
| Interrupciones físicas | Pruebas de foco no sustituyen llamada real, Bluetooth, auriculares, Siri ni cambio físico de red. |
| OPPO, estabilidad y estrés | La corrida larga incluyó una suspensión en segundo plano. El último ajuste se verificó con las pruebas dirigidas, funcionales y de controlador. Quedan tres paradas observadas después de reanudar en 240 pares Stop → Start separados por 10 ms. |
| R02, retención de caché | La política de conservar URIs para lectores tardíos sigue vigente. No se demuestra una fuga con sólo contar archivos de la prueba intensiva; ampliar requiere medir crecimiento y definir una política compatible. |
| R03, hilo principal | Queda trabajo de imagen/archivo en el hilo principal. Sin un perfil causal no se declara resuelto todo el coste ni se aplica una reescritura especulativa. Los tiempos medidos delimitan la aceptación. |

La matriz T01–T14 describe la cobertura prevista. Las pruebas pendientes siguen sin un resultado que permita confirmar o descartar un defecto. Los hallazgos F22–F34 tienen corrección implementada. Para decidir si se publica, deben tenerse en cuenta las limitaciones anteriores.

## Qué cambió en cada clase

| Archivo | Primera pasada / segunda pasada |
| --- | --- |
| `AudiostreamModule.java` | Primera: envío de órdenes, estado y metadatos coherentes; capability para configuración interna. Sin cambio adicional de producción en esta segunda pasada. |
| `MediaPlaybackService.java` | Primera: foco, foreground, metadatos, carátulas/URI y catálogo. Segunda: identidad de listeners, retirar fuente anterior, cancelación HTTP, prepare/play, MIME/BOM, SystemUI, foco pendiente y EOF. |
| `MediaActionReceiver.java` | Primera: frontera de órdenes permitidas. Segunda: Parcelable legacy/typed seguro y rechazo de datos malformados. |
| `DiagnosticLog.java` | Primera: diagnósticos configurables y redacción de URLs. Sin nuevas trazas de auditoría en el ZIP final. |
| `TiAudiostreamModule.h/.m` | Primera: alias play, intención, metadatos y guardas. Segunda: retirar output al cambiar pausado, validar callbacks y manejar EOF/restart. Header sin ampliación nueva. |
| `TiAudiostreamCarPlaySceneDelegate.m` | Primera: identidad de filas/carátulas. Segunda: coalescer URLs pendientes, caché independiente de fila y entradas null. Se conserva navegación por lista y marca única; no se impuso pantalla Now Playing. |
| `TiAudiostreamWindowSceneDelegate.m` | Primera: diagnósticos configurables. Sin nueva reestructuración funcional de escenas en la segunda pasada. |
| `TiAudiostreamContentLoader.h/.m` | Primera: resolución/HTTP acotado. Segunda: evitar sondeo para sufijos nativos reconocidos. |
| `TiAudiostreamArtwork.h` | Primera: decodificación/downsampling acotados. Sin cambio adicional en la segunda pasada. |
| `TiAudiostreamDiagnostics.h` | Primera: diagnósticos iOS opt-in y redacción. Sin cambio adicional en la segunda pasada. |
| Configuración/dependencias | Primera: versión 2.0.0 y bibliotecas Android actualizadas, Media3 1.11.1; requiere Titanium 13.4.1.GA+. Sin otra actualización de dependencias en esta fase. |

Se actualizaron CHANGELOG, Android README, plan y pruebas. No se crearon commits, tags ni releases.
