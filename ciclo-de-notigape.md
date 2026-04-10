Déjame explicarte cómo funciona el arranque de la App de NotiGAPE...

Cuando arranca la App, consulta al backend si hay noticias nuevas en el servidor, consultando el endpoint 'version'. Si el backend responde con una versión diferente a la que tiene la App, entonces consulta el siguiente endpoint que es de noticias y descarga las 25 notas más recientes.

SE arma la portada con las 25 notas y en segundo plano se descarga más información de los endpoints..

Entre ellas las frecuencias, con los URLs del stream, datos de la estación, programa y conductor actual (cada media hora puede haber cambios de programación).

En ese punto.. se arma en el "TAB" (simualdo) de Radio.. las portadas de las estaciones, con su programación y conductor actual, ver foto adjunta.

Cómo podemos 'tener' la lista de frecuencias y el nombre de la estación para que Cuando Abran CarPlay.. puedan 'sintonizar' las frecuencias AUN cuando NO está abierta la App de NotiGAPE?

O acaso al abrir el icono de en CarPlay, se abre la App de NotiGAPE y se actualizan las frecuencias y programación en ese momento?

---

• Sí. El flujo correcto para NotiGAPE en CarPlay, pensando en radio en vivo, es este:

1. El usuario toca el icono de NotiGAPE en CarPlay.
2. iOS lanza el proceso de la app si no estaba vivo y crea la escena de CarPlay.
5. Cuando el usuario elige una estación, arrancas el stream y empujas Now Playing.

Para radio en vivo no existe un “continúa en el minuto exacto” como Spotify. Lo natural es una de estas dos:

- si la app ya estaba reproduciendo, CarPlay muestra la estación actual y sigue sonando
- si no estaba reproduciendo, CarPlay muestra la última estación seleccionada o una lista de estaciones para elegir

- refresh al conectar: cuando CarPlay abre la app, disparar la consulta al backend y refrescar la lista
- ambas, que es lo correcto: mostrar caché inmediata y luego actualizar en cuanto responda el backend

Entonces, para NotiGAPE, la arquitectura práctica sería:

- cuando la app descarga frecuencias/programación, guardarlas localmente
- al abrir CarPlay, mostrar primero esa lista cacheada
- en paralelo, pedir al backend la versión nueva y refrescar la lista si cambió
- cuando el usuario toca una estación en CarPlay, iniciar el stream y pasar a Now Playing

Y sí: lo que acabas de ver confirma el otro flujo importante. Como NotiGAPE sigue viva y el módulo ya publica metadata correctamente, cuando cambias de estación en la app, CarPlay se actualiza en tiempo real. Eso es exactamente lo esperado.

Apple confirma dos piezas de este flujo:

- la escena de CarPlay se conecta cuando la app es lanzada en CarPlay: https://developer.apple.com/videos/play/wwdc2020/10635
- el scene delegate de CPTemplateApplicationScene es el punto donde presentas tus templates:

https://developer.apple.com/documentation/bundleresources/information-property-list/uiapplicationscenemanifest/uisceneconfigurations/cptemplateapplicationscenesessionroleapplication/uiscenedelegateclassname

Siguiente paso técnico real para soportar “sintonizar frecuencias aunque no hayas abierto la app en el iPhone”:

- agregar al módulo una API tipo setCarPlayStations([...])
- persistir en NotiGAPE la última lista de estaciones
- hacer que CarPlay monte un CPListTemplate con esa caché y luego lo refresque con backend

Yo sigo con los cambios de release y documentación, pero ese sería el diseño correcto para la siguiente fase funcional.


---

› De hecho, después de cerrar la App de GAPE.. abrí el icono en CarPlay.. y solo me muestra los controles 'desactivados'!!

NO hace Play de la última estación reproducida.. O al menos que tocara la primera de la lista!! :-(


• Sí. Con el comportamiento actual eso es normal, no una falla nueva.

Lo que CarPlay está haciendo ahí es:

- lanzar la escena de CarPlay
- abrir Now Playing
- pero como no hay una estación activa ni una política de “resume last station”, la plantilla queda vacía con controles apagados

O sea, hoy tenemos esto:

- si NotiGAPE ya está viva o ya está reproduciendo, CarPlay refleja perfectamente el estado
- si la app estaba cerrada y abres el icono en CarPlay, no hay todavía una estación que reanudar ni una lista para escoger

Para radio en vivo hay que decidir el UX exacto. Hay dos opciones buenas:

1. Resume last station

- Al abrir NotiGAPE desde CarPlay, si no hay playback activo, la app recupera la última estación guardada y la arranca sola.
- Es lo más parecido a Spotify/YT Music, pero en radio significa “reanudar la última frecuencia”, no posición de tiempo.

2. Station list first

- Al abrir NotiGAPE desde CarPlay, muestras una lista de frecuencias cacheadas.
- El usuario elige una y entonces pasas a Now Playing.
- Para radio me parece más correcto y más controlable.

La solución seria para NotiGAPE es combinar ambas:

- si hay una última estación guardada, puedes mostrarla como opción rápida o incluso reanudarla
- además, ofrecer lista de estaciones cacheadas para elegir
- luego refrescar esa lista con el backend en cuanto la app conecte

Técnicamente, eso implica una fase nueva:

- persistir localmente la última estación y la lista de frecuencias
- agregar soporte de browsing en CarPlay (CPListTemplate) dentro del módulo
- exponer una API tipo setCarPlayStations([...])
- exponer también un evento de selección desde CarPlay hacia JS

Y sí: este caso exacto lo voy a dejar documentado como limitación actual.

Porque hoy el módulo ya resuelve Now Playing, pero todavía no resuelve “cold launch en CarPlay con selección de estación”.
