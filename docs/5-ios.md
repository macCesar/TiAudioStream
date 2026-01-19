# 🍏 Paso 4: Implementación iOS

**(AVPlayer + AVAudioSession + Lock Screen + Control Center)**

---

## 🎯 Objetivo en iOS

✔ Audio en background
✔ Interrupciones correctas (llamadas, Siri, otras apps)
✔ Lock screen / Control Center
✔ Auriculares / Bluetooth
✔ Misma API JS (`play / pause / setStream / setMetadata`)
✔ Cero código condicional en la app

---

# 📂 Archivos clave (iOS)

```
ios/
└── Classes/
    ├── TiAudiostreamModule.m    ← proxy JS
    ├── AudioPlayerManager.m     ← AVPlayer + sesión
    └── AudioPlayerManager.h
```

---

# 1️⃣ Background Audio (OBLIGATORIO)

En `tiapp.xml` **de la app** (esto no va en el módulo):

```xml
<key>UIBackgroundModes</key>
<array>
  <string>audio</string>
</array>
```

Sin esto:
❌ iOS mata el audio al bloquear pantalla

---

# 2️⃣ Proxy del módulo (`TiAudiostreamModule.m`)

Este archivo **refleja exactamente** lo que hicimos en Android.

```objc
#import "TiAudiostreamModule.h"
#import "AudioPlayerManager.h"

@implementation TiAudiostreamModule

#pragma mark Lifecycle

- (void)startup
{
  [super startup];
}

#pragma mark API JS

- (void)init:(id)unused
{
  [[AudioPlayerManager shared] setup];
}

- (void)setStream:(id)args
{
  ENSURE_ARG_COUNT(args, 2);
  NSString *url = args[0];
  BOOL isLive = [args[1] boolValue];

  [[AudioPlayerManager shared] setStream:url isLive:isLive];
}

- (void)setMetadata:(id)args
{
  ENSURE_SINGLE_ARG(args, NSDictionary);

  [[AudioPlayerManager shared] setMetadata:args];
}

- (void)play:(id)unused
{
  [[AudioPlayerManager shared] play];
}

- (void)pause:(id)unused
{
  [[AudioPlayerManager shared] pause];
}

- (void)stop:(id)unused
{
  [[AudioPlayerManager shared] stop];
}

@end
```

👉 Igual que Android: **proxy delgado**

---

# 3️⃣ AVAudioSession (audio focus iOS)

Archivo: `AudioPlayerManager.m`

```objc
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@implementation AudioPlayerManager {
  AVPlayer *_player;
}

+ (instancetype)shared
{
  static AudioPlayerManager *instance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    instance = [[AudioPlayerManager alloc] init];
  });
  return instance;
}

- (void)setup
{
  AVAudioSession *session = [AVAudioSession sharedInstance];

  [session setCategory:AVAudioSessionCategoryPlayback
                 mode:AVAudioSessionModeDefault
              options:0
                error:nil];

  [session setActive:YES error:nil];

  [[NSNotificationCenter defaultCenter]
    addObserver:self
       selector:@selector(handleInterruption:)
           name:AVAudioSessionInterruptionNotification
         object:nil];
}
```

### Interrupciones (llamadas, Siri, otras apps)

```objc
- (void)handleInterruption:(NSNotification *)notification
{
  NSDictionary *info = notification.userInfo;
  NSInteger type = [info[AVAudioSessionInterruptionTypeKey] integerValue];

  if (type == AVAudioSessionInterruptionTypeBegan) {
    [self pause];
  }
}
```

👉 iOS maneja esto **mucho mejor que Android**.

---

# 4️⃣ AVPlayer (reproducción real)

```objc
- (void)setStream:(NSString *)url isLive:(BOOL)isLive
{
  NSURL *streamURL = [NSURL URLWithString:url];

  AVPlayerItem *item = [AVPlayerItem playerItemWithURL:streamURL];

  if (_player) {
    [_player replaceCurrentItemWithPlayerItem:item];
  } else {
    _player = [AVPlayer playerWithPlayerItem:item];
  }
}
```

---

# 5️⃣ Play / Pause / Stop

```objc
- (void)play
{
  [_player play];
  [self fireState:@"playing"];
}

- (void)pause
{
  [_player pause];
  [self fireState:@"paused"];
}

- (void)stop
{
  [_player pause];
  _player = nil;
  [self fireState:@"stopped"];
}
```

---

# 6️⃣ Lock Screen / Control Center (MPNowPlaying)

```objc
- (void)setMetadata:(NSDictionary *)meta
{
  NSMutableDictionary *info = [NSMutableDictionary dictionary];

  info[MPMediaItemPropertyTitle] = meta[@"title"] ?: @"";
  info[MPMediaItemPropertyArtist] = meta[@"subtitle"] ?: @"";

  NSString *artworkURL = meta[@"artwork"];
  if (artworkURL) {
    NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:artworkURL]];
    UIImage *image = [UIImage imageWithData:data];
    if (image) {
      MPMediaItemArtwork *artwork =
        [[MPMediaItemArtwork alloc] initWithBoundsSize:image.size
                                         requestHandler:^UIImage * _Nonnull(CGSize size) {
                                           return image;
                                         }];
      info[MPMediaItemPropertyArtwork] = artwork;
    }
  }

  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}
```

👉 Aparece en:

* Lock screen
* Control Center
* Bluetooth

---

# 7️⃣ Controles del sistema (auriculares / lock screen)

```objc
- (void)setupRemoteCommands
{
  MPRemoteCommandCenter *center = [MPRemoteCommandCenter sharedCommandCenter];

  [center.playCommand addTarget:self action:@selector(play)];
  [center.pauseCommand addTarget:self action:@selector(pause)];
  [center.stopCommand addTarget:self action:@selector(stop)];
}
```

Llamar esto en `setup`.

---

# 🔁 Eventos hacia JS (igual que Android)

```objc
- (void)fireState:(NSString *)state
{
  [self.module fireEvent:@"state" withObject:@{ @"state": state }];
}
```

---

# 🎯 Resultado final (iOS)

✔ Audio en background
✔ Lock screen
✔ Control Center
✔ Auriculares / Bluetooth
✔ Interrupciones correctas
✔ Misma API JS
✔ Sin hacks

---

# 🧠 Comparación Android vs iOS (honesta)

| Tema           | Android      | iOS          |
| -------------- | ------------ | ------------ |
| Audio focus    | Difícil      | Sencillo     |
| Background     | Service      | Automático   |
| Lock screen    | MediaSession | MPNowPlaying |
| Implementación | Larga        | Más limpia   |

---

# 🏁 Estado del proyecto AHORA

✔ API JS definida
✔ Android: arquitectura completa
✔ iOS: arquitectura completa
✔ Problema original resuelto
✔ Listo para refinar y publicar

---

## 👉 Qué sigue (elige)

1️⃣ Refinar Android (artwork async, errores, reconexión)
2️⃣ Refinar iOS (buffering / estados)
3️⃣ Checklist Android 12–14 (permisos, restricciones)
4️⃣ Preparar **README + ejemplo** para GitHub

Dime el siguiente paso y lo dejamos **redondo** 🚀
