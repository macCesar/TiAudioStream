# 🟦 Paso 3: `MediaPlaybackService` (Actualizado v1.1.0)

**(Foreground Service + ExoPlayer + Audio Focus + MediaSession)**

Este paso es el corazón del módulo y garantiza una experiencia de usuario profesional similar a Spotify o YouTube Music.

---

## 🎯 Mejoras de Estabilidad (v1.1.0)

Tras las pruebas de campo, se han implementado tres refinamientos críticos:

### 1. Reconexión Inteligente e Interrumpible
El sistema de reintento automático ahora es consciente del estado de la aplicación.
- **Cancelación Activa**: Si el usuario cambia de estación o detiene el reproductor mientras hay un reintento pendiente (en el delay de 3 segundos), la tarea se cancela inmediatamente.
- **Validación de URL**: Antes de ejecutar el reintento, el servicio verifica que la URL que falló siga siendo la URL activa. Esto evita que una señal caída interrumpa a una señal nueva y activa.

### 2. Detección Quirúrgica de Errores (Terminal Errors)
No todas las fallas merecen un reintento. 
- **Aborto Inmediato**: Si el servidor responde con errores permanentes como **404 (Not Found)**, **302 (Redirect no seguido)** o **500 (Server Error)**, el módulo detiene los reintentos al primer intento.
- **Feedback Instantáneo**: Al abortar rápido, la aplicación puede mostrar el diálogo de "Señal no disponible" al usuario sin esperas innecesarias.

### 3. Persistencia de la Notificación
- **Paro Suave**: En caso de error de señal, el `ExoPlayer` se detiene (`player.stop()`), pero el **Servicio de Primer Plano se mantiene vivo**. 
- **Control Total**: Esto permite que los controles en el Centro de Notificaciones y la Pantalla de Bloqueo sigan visibles, permitiendo al usuario saltar a la siguiente estación incluso si la actual falló.

---

## 🧱 Arquitectura interna (Android)

```
MediaPlaybackService (Foreground)
   |
   +-- ExoPlayer (Media3)
   |     ↳ Maneja el flujo de audio
   |     ↳ Reporta errores de red (onPlayerError)
   |
   +-- Reconnection Manager
   |     ↳ Maneja reintentos asíncronos (Future tasks)
   |     ↳ Valida URLs antes de reconectar
   |
   +-- MediaSessionCompat
   |     ↳ Sincroniza metadatos y arte
   |     ↳ Recibe eventos de hardware (Bluetooth/Auriculares)
```

---

## 🛠️ Lógica de Reintento (v1.1.0)

```java
private void attemptReconnect() {
    // ... lógica de conteo ...
    
    // Cancelar cualquier tarea previa
    if (pendingReconnectTask != null) pendingReconnectTask.cancel(true);

    pendingReconnectTask = executor.submit(() -> {
        Thread.sleep(3000);
        
        mainHandler.post(() -> {
            // SOLO si la URL no ha cambiado y el usuario no puso STOP
            if (player != null && currentUrl != null && currentUrl.equals(targetUrl)) {
                player.prepare();
                player.play();
            }
        });
    });
}
```

---

## 🎯 Resultados logrados

✔ **Cero Crashes por Hilos**: Todas las llamadas al player se ejecutan en el `MainThread`.
✔ **Navegación Fluida**: Cambiar entre estaciones caídas y activas no genera inestabilidad.
✔ **Consumo de Datos Eficiente**: Se detienen los reintentos en URLs permanentemente rotas.
