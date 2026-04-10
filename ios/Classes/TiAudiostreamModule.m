/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiAudiostreamModule.h"
#import "TiAudiostreamCarPlaySceneDelegate.h"
#import "TiAudiostreamWindowSceneDelegate.h"
#import "TiBase.h"
#import "TiHost.h"
#import "TiUtils.h"
#import <AVFoundation/AVFoundation.h>
#import <CarPlay/CarPlay.h>
#import <ImageIO/ImageIO.h>
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

// Original IMP for TiApp's application:configurationForConnectingSceneSession:options:
static IMP _originalConfigurationForConnecting = NULL;

// Swizzled implementation: dispatch CarPlay scene to our delegate
static UISceneConfiguration *TiAudiostream_configurationForConnecting(id self, SEL _cmd,
    UIApplication *application,
    UISceneSession *connectingSceneSession,
    UISceneConnectionOptions *options) API_AVAILABLE(ios(13.0))
{
  NSString *role = connectingSceneSession.role;
  NSLog(@"[ti.audiostream] configurationForConnecting role=%@", role);

  // CarPlay scene: dispatch to our CarPlay delegate with explicit scene class
  if ([role isEqualToString:@"CPTemplateApplicationSceneSessionRoleApplication"]) {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"CarPlay Configuration"
                                                                  sessionRole:connectingSceneSession.role];
    config.delegateClass = [TiAudiostreamCarPlaySceneDelegate class];
    config.sceneClass = [CPTemplateApplicationScene class];
    NSLog(@"[ti.audiostream] Dispatching CarPlay scene to TiAudiostreamCarPlaySceneDelegate");
    return config;
  }

  // Window scene: dispatch to our bridge delegate that attaches Titanium's window
  if ([role isEqualToString:UIWindowSceneSessionRoleApplication]) {
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Default Configuration"
                                                                  sessionRole:connectingSceneSession.role];
    config.delegateClass = [TiAudiostreamWindowSceneDelegate class];
    config.sceneClass = [UIWindowScene class];
    NSLog(@"[ti.audiostream] Dispatching window scene to TiAudiostreamWindowSceneDelegate");
    return config;
  }

  // Other roles: call original TiApp implementation
  if (_originalConfigurationForConnecting) {
    return ((UISceneConfiguration *(*)(id, SEL, UIApplication *, UISceneSession *, UISceneConnectionOptions *))
        _originalConfigurationForConnecting)(self, _cmd, application, connectingSceneSession, options);
  }

  // Fallback: generic config
  return [[UISceneConfiguration alloc] initWithName:connectingSceneSession.configuration.name
                                        sessionRole:connectingSceneSession.role];
}

// Force linker to keep scene delegate classes + swizzle TiApp's scene dispatch
__attribute__((used)) static Class _cpClassRef;
__attribute__((used)) static Class _wsClassRef;
__attribute__((constructor))
static void TiAudiostreamRegisterSceneClasses(void)
{
  _cpClassRef = [TiAudiostreamCarPlaySceneDelegate class];
  _wsClassRef = [TiAudiostreamWindowSceneDelegate class];

  // Swizzle TiApp's application:configurationForConnectingSceneSession:options:
  // TiApp returns a bare UISceneConfiguration with no delegateClass or sceneClass,
  // which prevents CarPlay from reaching our TiAudiostreamCarPlaySceneDelegate.
  // This swizzle adds explicit dispatch for CarPlay and window scene roles.
  Class tiAppClass = NSClassFromString(@"TiApp");
  if (!tiAppClass) {
    return;
  }

  SEL selector = @selector(application:configurationForConnectingSceneSession:options:);
  Method original = class_getInstanceMethod(tiAppClass, selector);

  if (original) {
    _originalConfigurationForConnecting = method_getImplementation(original);
    method_setImplementation(original, (IMP)TiAudiostream_configurationForConnecting);
    NSLog(@"[ti.audiostream] Swizzled TiApp scene configuration dispatch");
  } else {
    class_addMethod(tiAppClass, selector, (IMP)TiAudiostream_configurationForConnecting, "@@:@@@");
    NSLog(@"[ti.audiostream] Added scene configuration dispatch to TiApp");
  }
}

static NSString *const TiAudiostreamCarPlayDidConnectNotification = @"TiAudiostreamCarPlayDidConnectNotification";
static NSString *const TiAudiostreamCarPlayDidPresentNowPlayingNotification = @"TiAudiostreamCarPlayDidPresentNowPlayingNotification";
static NSString *const TiAudiostreamAutomotiveStationSelectedNotification = @"TiAudiostreamAutomotiveStationSelectedNotification";
static NSString *const TiAudiostreamAutomotiveStationsDidChangeNotification = @"TiAudiostreamAutomotiveStationsDidChangeNotification";
static NSString *const TiAudiostreamDefaultsAutomotiveStationsKey = @"ti.audiostream.automotive.stations";
static NSString *const TiAudiostreamDefaultsCurrentAutomotiveStationKey = @"ti.audiostream.automotive.currentStation";
static NSString *const TiAudiostreamAutomotiveSourceCarPlay = @"carplay";
static TiAudiostreamModule *TiAudiostreamActiveModule = nil;

@interface TiAudiostreamModule () <AVPlayerItemMetadataOutputPushDelegate
#if TARGET_OS_IOS
, MPNowPlayingSessionDelegate
#endif
> {
  AVPlayer *_player;
  AVPlayerItem *_currentItem;
  AVPlayerItemMetadataOutput *_metadataOutput;
  BOOL _isLive;
  NSString *_currentURL;
  NSString *_currentTitle;
  NSString *_currentArtist;
  UIImage *_currentArtwork;
  BOOL _resumeOnInterruption;
  BOOL _autoUpdateMetadata;
  BOOL _playRequested;
  NSArray *_titleRules;
  NSArray *_artistRules;
  NSString *_lastEmittedState;
  NSString *_lastEmittedMetadataTitle;
  NSString *_lastEmittedMetadataArtist;
  NSString *_lastEmittedMetadataArtwork;
  BOOL _pendingPlay;
  NSUInteger _artworkGeneration;
  UIImage *_appIconImage;
  int _retryCount;
  int _maxRetries;
  double _retryDelay;
  NSTimer *_retryTimer;
#if TARGET_OS_IOS
  MPNowPlayingSession *_nowPlayingSession API_AVAILABLE(ios(16.0));
  MPRemoteCommandCenter *_registeredSessionRemoteCommandCenter;
  MPRemoteCommandCenter *_registeredSharedRemoteCommandCenter;
#endif
}
@end

@implementation TiAudiostreamModule

#pragma mark - Lifecycle

- (id)moduleGUID
{
  return @"04e2decf-6370-43f1-bf1d-457c4b417325";
}
- (NSString *)moduleId
{
  return @"ti.audiostream";
}

- (void)startup
{
  [super startup];
  TiAudiostreamActiveModule = self;

  // Default: auto-update metadata from stream
  _autoUpdateMetadata = YES;

  // Reconnection defaults
  _retryCount = 0;
  _maxRetries = 5;
  _retryDelay = 3.0;

#if TARGET_OS_IOS
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
  [session setActive:YES error:nil];
  [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  [self ensurePlayerInitialized];
  [self configureRemoteCommandHandlingIfNeeded];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
#endif

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleErrorLogEntry:)
                                               name:AVPlayerItemNewErrorLogEntryNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleAutomotiveStationSelectedNotification:)
                                               name:TiAudiostreamAutomotiveStationSelectedNotification
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleCarPlaySceneDidConnect:)
                                               name:TiAudiostreamCarPlayDidConnectNotification
                                             object:nil];
}

#pragma mark - JS API

- (void)setStream:(id)args
{
  ENSURE_SINGLE_ARG(args, NSDictionary);
  [self resetRetryLogic];
  _artworkGeneration++;
  _lastEmittedMetadataTitle = nil;
  _lastEmittedMetadataArtist = nil;
  _lastEmittedMetadataArtwork = nil;
  _currentURL = [TiUtils stringValue:@"url" properties:args];
  _isLive = [TiUtils boolValue:@"isLive" properties:args def:YES];
  _autoUpdateMetadata = [TiUtils boolValue:@"autoUpdateMetadata" properties:args def:YES];

  // Check if title, artist, artwork are provided
  NSString *title = [TiUtils stringValue:@"title" properties:args];
  NSString *artist = [TiUtils stringValue:@"artist" properties:args];
  id artworkValue = [args objectForKey:@"artwork"];
  BOOL hasTitleKey = [args objectForKey:@"title"] != nil;
  BOOL hasArtistKey = [args objectForKey:@"artist"] != nil;
  BOOL hasArtworkKey = [args objectForKey:@"artwork"] != nil;

  // Preserve existing metadata unless the caller explicitly passes new values.
  // NotiGAPE sets metadata first and then calls setStream() with only URL/isLive,
  // so clearing here wipes Now Playing just before CarPlay reads it.
  if (hasTitleKey || hasArtistKey || hasArtworkKey) {
    NSMutableDictionary *metaDict = [NSMutableDictionary dictionary];
    if (hasTitleKey) {
      [metaDict setObject:(title ?: @"") forKey:@"title"];
    }
    if (hasArtistKey) {
      [metaDict setObject:(artist ?: @"") forKey:@"artist"];
    }
    if (hasArtworkKey) {
      if (artworkValue != [NSNull null]) {
        NSString *artwork = [TiUtils stringValue:@"artwork" properties:args];
        [metaDict setObject:(artwork ?: @"") forKey:@"artwork"];
      } else {
        [metaDict setObject:@"" forKey:@"artwork"];
      }
    }

    [self setMetadata:metaDict];
  }

  // Handle metadataRules: present + dict -> set, present + null -> clear, absent -> preserve
  if ([args objectForKey:@"metadataRules"] != nil) {
    id rulesValue = [args objectForKey:@"metadataRules"];
    if ([rulesValue isKindOfClass:[NSDictionary class]]) {
      [self setMetadataRules:rulesValue];
    } else {
      [self setMetadataRules:nil];
    }
  }

  [self prepareCurrentStreamItem];
}

- (void)start:(id)unused
{
  if (!_player)
    return;

  [self resetRetryLogic];
  _playRequested = YES;

  // Guard clause: If already playing, don't re-prepare or interrupt
  if (_player.rate > 0 && _currentItem.status == AVPlayerItemStatusReadyToPlay) {
    return;
  }

#if TARGET_OS_IOS
  [[AVAudioSession sharedInstance] setActive:YES
                                       error:nil];
#endif

  // If player is IDLE or has no valid item, prepare the stream
  if (!_currentItem || !_player.currentItem || _currentItem.status == AVPlayerItemStatusFailed) {
    if (_currentURL) {
      [self prepareCurrentStreamItem];
    }
  }

  // Si el item aun no esta conectado (async en progreso), diferir el play
  if (!_currentItem || !_player.currentItem) {
    _pendingPlay = YES;
    return;
  }

  [_player play];
  [self updateNowPlaying];
  [self activateNowPlayingSessionIfPossible];
}

- (void)pause:(id)unused
{
  if (_player && _player.rate > 0) {
    _playRequested = NO;
    [_player pause];
    [self updateNowPlaying];
  }
}

- (void)stop:(id)args
{
  if ([args isKindOfClass:[NSDictionary class]] && [TiUtils boolValue:@"hard" properties:args def:NO]) {
    [self hardStop:nil];
    return;
  }

  [self resetRetryLogic];
  _artworkGeneration++;
  _lastEmittedMetadataTitle = nil;
  _lastEmittedMetadataArtist = nil;
  _lastEmittedMetadataArtwork = nil;
  _playRequested = NO;
  _pendingPlay = NO;
  if (_player) {
    [_player pause];
  }
  [self fireState:@"stopped"];
#if TARGET_OS_IOS
  [self setPlaybackState:MPNowPlayingPlaybackStateStopped];
  for (MPNowPlayingInfoCenter *center in [self activeNowPlayingInfoCenters]) {
    center.nowPlayingInfo = nil;
  }
  [[AVAudioSession sharedInstance] setActive:NO
                                 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                       error:nil];
#endif
}

- (void)hardStop:(id)unused
{
  [self resetRetryLogic];
  _artworkGeneration++;
  _lastEmittedMetadataTitle = nil;
  _lastEmittedMetadataArtist = nil;
  _lastEmittedMetadataArtwork = nil;
  _playRequested = NO;
  _pendingPlay = NO;
  if (_player) {
    [_player pause];
    @try {
      [_player replaceCurrentItemWithPlayerItem:nil];
    } @catch (id e) {
    }
  }
  if (_currentItem) {
    @try {
      [_currentItem removeObserver:self forKeyPath:@"status"];
    } @catch (id e) {
    }
    if (_metadataOutput) {
      [_currentItem removeOutput:_metadataOutput];
      _metadataOutput = nil;
    }
    _currentItem = nil;
  }
  [self fireState:@"stopped"];
#if TARGET_OS_IOS
  [self setPlaybackState:MPNowPlayingPlaybackStateStopped];
  for (MPNowPlayingInfoCenter *center in [self activeNowPlayingInfoCenters]) {
    center.nowPlayingInfo = nil;
  }
  [[AVAudioSession sharedInstance] setActive:NO
                                 withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                       error:nil];
#endif
}

- (void)setMetadata:(id)args
{
  ENSURE_SINGLE_ARG(args, NSDictionary);
  _artworkGeneration++;
  NSUInteger expectedGeneration = _artworkGeneration;
  _currentTitle = [TiUtils stringValue:@"title" properties:args def:@""];
  _currentArtist = [TiUtils stringValue:@"artist" properties:args def:@""];

  // Check if artwork key exists in args
  id artworkValue = [args objectForKey:@"artwork"];

  if (artworkValue != nil && artworkValue != [NSNull null]) {
    NSString *artworkURL = [TiUtils stringValue:@"artwork" properties:args];

    // If null, empty string, or just whitespace -> clear artwork
    if (artworkURL == nil || [artworkURL length] == 0 || [[artworkURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
      _currentArtwork = nil;
      [self updateNowPlaying];
    } else {
      // Valid URL -> load it
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:artworkURL]];
        UIImage *img = [UIImage imageWithData:data];
        dispatch_async(dispatch_get_main_queue(), ^{
          if (expectedGeneration != self->_artworkGeneration) {
            return;
          }
          if (img) {
            self->_currentArtwork = img;
          } else {
            self->_currentArtwork = nil;
          }
          [self updateNowPlaying];
        });
      });
    }
  } else {
    // Key not provided -> clear artwork (new stream behavior)
    _currentArtwork = nil;
    [self updateNowPlaying];
  }
}

- (void)setAutoUpdateMetadata:(id)args
{
  ENSURE_SINGLE_ARG(args, NSNumber);
  _autoUpdateMetadata = [TiUtils boolValue:args def:YES];
  NSLog(@"[ti.audiostream] Auto-update metadata: %@", _autoUpdateMetadata ? @"YES" : @"NO");
}

#pragma mark - Properties

- (id)playing
{
  return NUMBOOL(_player != nil && _player.rate > 0);
}

#pragma mark - Constants

- (id)REMOTE_CONTROL_PLAY
{
  return @(100);
}
- (id)REMOTE_CONTROL_PAUSE
{
  return @(101);
}
- (id)REMOTE_CONTROL_STOP
{
  return @(102);
}
- (id)REMOTE_CONTROL_PLAY_PAUSE
{
  return @(103);
}
- (id)REMOTE_CONTROL_NEXT
{
  return @(104);
}
- (id)REMOTE_CONTROL_PREV
{
  return @(105);
}

- (void)setMetadataRules:(id)args
{
  if (args == nil || args == [NSNull null]) {
    _titleRules = nil;
    _artistRules = nil;
    NSLog(@"[ti.audiostream] Metadata rules cleared");
    return;
  }

  ENSURE_SINGLE_ARG(args, NSDictionary);
  NSDictionary *rules = (NSDictionary *)args;

  _titleRules = [rules objectForKey:@"title"];
  _artistRules = [rules objectForKey:@"artist"];

  NSLog(@"[ti.audiostream] Metadata rules set: title=%lu, artist=%lu",
    (unsigned long)(_titleRules ? _titleRules.count : 0),
    (unsigned long)(_artistRules ? _artistRules.count : 0));
}

- (void)setAutomotiveStations:(id)args
{
  id stations = args;
  if ([args isKindOfClass:[NSArray class]]) {
    NSArray *argArray = (NSArray *)args;
    if (argArray.count == 1) {
      stations = [argArray objectAtIndex:0];
    }
  }

  if (stations == nil || stations == [NSNull null]) {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:TiAudiostreamDefaultsAutomotiveStationsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamAutomotiveStationsDidChangeNotification object:nil];
    return;
  }

  if (![stations isKindOfClass:[NSArray class]]) {
    NSLog(@"[ti.audiostream] setAutomotiveStations expected array payload, got %@", NSStringFromClass([stations class]));
    return;
  }

  NSData *data = [NSJSONSerialization dataWithJSONObject:stations options:0 error:nil];
  if (!data) {
    NSLog(@"[ti.audiostream] Failed to serialize automotive stations");
    return;
  }

  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  [[NSUserDefaults standardUserDefaults] setObject:json forKey:TiAudiostreamDefaultsAutomotiveStationsKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamAutomotiveStationsDidChangeNotification object:nil];
}

- (void)setCurrentAutomotiveStation:(id)args
{
  id station = args;
  if ([args isKindOfClass:[NSArray class]]) {
    NSArray *argArray = (NSArray *)args;
    if (argArray.count == 1) {
      station = [argArray objectAtIndex:0];
    }
  }

  if (station == nil || station == [NSNull null]) {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:TiAudiostreamDefaultsCurrentAutomotiveStationKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamAutomotiveStationsDidChangeNotification object:nil];
    return;
  }

  if (![station isKindOfClass:[NSDictionary class]]) {
    NSLog(@"[ti.audiostream] setCurrentAutomotiveStation expected dictionary payload, got %@", NSStringFromClass([station class]));
    return;
  }

  NSData *data = [NSJSONSerialization dataWithJSONObject:station options:0 error:nil];
  if (!data) {
    NSLog(@"[ti.audiostream] Failed to serialize current automotive station");
    return;
  }

  NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
  [[NSUserDefaults standardUserDefaults] setObject:json forKey:TiAudiostreamDefaultsCurrentAutomotiveStationKey];
  [[NSUserDefaults standardUserDefaults] synchronize];
  [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamAutomotiveStationsDidChangeNotification object:nil];
}

- (NSString *)applyRules:(NSArray *)rules toString:(NSString *)input
{
  if (!rules || rules.count == 0 || !input) return input;

  NSString *result = input;
  for (NSDictionary *rule in rules) {
    NSString *pattern = rule[@"match"];
    NSString *replacement = rule[@"replace"];
    if (!pattern || !replacement) continue;

    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    if (regex) {
      result = [regex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:replacement];
    }
  }
  return result;
}

- (void)prepareCurrentStreamItem
{
  _pendingPlay = NO;

  [self ensurePlayerInitialized];

  if (_player) {
    [_player pause];
    @try {
      [_player removeObserver:self forKeyPath:@"timeControlStatus"];
    } @catch (id e) {
    }
  }

  if (_currentItem) {
    @try {
      [_currentItem removeObserver:self forKeyPath:@"status"];
    } @catch (id e) {
    }
    if (_metadataOutput) {
      [_currentItem removeOutput:_metadataOutput];
      _metadataOutput = nil;
    }
    _currentItem = nil;
  }

  [self fireState:@"buffering"];
  [_player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:nil];

  NSString *urlString = [_currentURL copy];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    AVPlayerItem *newItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:urlString]];

    dispatch_async(dispatch_get_main_queue(), ^{
      if (![urlString isEqualToString:self->_currentURL]) {
        return;
      }

      self->_currentItem = newItem;
      [self->_currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];

      self->_metadataOutput = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:nil];
      [self->_metadataOutput setDelegate:self queue:dispatch_get_main_queue()];
      [self->_currentItem addOutput:self->_metadataOutput];

      [self->_player replaceCurrentItemWithPlayerItem:self->_currentItem];

      if (self->_pendingPlay) {
        self->_pendingPlay = NO;
        [self->_player play];
        [self updateNowPlaying];
        [self activateNowPlayingSessionIfPossible];
      }
    });
  });
}

- (void)emitMetadataIfChangedWithTitle:(NSString *)title artist:(NSString *)artist artwork:(NSString *)artwork raw:(NSDictionary *)raw
{
  NSString *safeTitle = title ?: @"";
  NSString *safeArtist = artist ?: @"";
  NSString *safeArtwork = artwork ?: @"";

  if ((_lastEmittedMetadataTitle == safeTitle || [_lastEmittedMetadataTitle isEqualToString:safeTitle]) &&
      (_lastEmittedMetadataArtist == safeArtist || [_lastEmittedMetadataArtist isEqualToString:safeArtist]) &&
      (_lastEmittedMetadataArtwork == safeArtwork || [_lastEmittedMetadataArtwork isEqualToString:safeArtwork])) {
    return;
  }

  _lastEmittedMetadataTitle = [safeTitle copy];
  _lastEmittedMetadataArtist = [safeArtist copy];
  _lastEmittedMetadataArtwork = [safeArtwork copy];

  if ([self _hasListeners:@"metadata"]) {
    [self fireEvent:@"metadata"
         withObject:@{
           @"title" : safeTitle,
           @"artist" : safeArtist,
           @"artwork" : safeArtwork,
           @"raw" : raw ?: @{}
         }];
  }
}

#pragma mark - Internal

+ (TiAudiostreamModule *)activeModule
{
  return TiAudiostreamActiveModule;
}

+ (NSArray<NSDictionary *> *)persistedAutomotiveStations
{
  NSString *json = [[NSUserDefaults standardUserDefaults] stringForKey:TiAudiostreamDefaultsAutomotiveStationsKey];
  if (json.length == 0) {
    return @[];
  }

  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  NSArray *stations = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [stations isKindOfClass:[NSArray class]] ? stations : @[];
}

+ (NSDictionary *)persistedCurrentAutomotiveStation
{
  NSString *json = [[NSUserDefaults standardUserDefaults] stringForKey:TiAudiostreamDefaultsCurrentAutomotiveStationKey];
  if (json.length == 0) {
    return nil;
  }

  NSData *data = [json dataUsingEncoding:NSUTF8StringEncoding];
  NSDictionary *station = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [station isKindOfClass:[NSDictionary class]] ? station : nil;
}

- (BOOL)carPlayNowPlayingReady
{
#if TARGET_OS_IOS
  BOOL hasMetadata = _currentTitle.length > 0 || _currentArtist.length > 0 || _currentArtwork != nil;
  BOOL isPlaying = _player != nil && _player.rate > 0;
  BOOL isStable = _player != nil && _player.timeControlStatus == AVPlayerTimeControlStatusPlaying;
  return hasMetadata && isPlaying && isStable;
#else
  return NO;
#endif
}

- (void)emitAutomotiveStationSelected:(NSDictionary *)station source:(NSString *)source
{
  if (![self _hasListeners:@"automotivestationselected"]) {
    return;
  }

  NSMutableDictionary *event = [NSMutableDictionary dictionary];
  event[@"source"] = source ?: TiAudiostreamAutomotiveSourceCarPlay;
  if (station) {
    event[@"station"] = station;
  }
  [self fireEvent:@"automotivestationselected" withObject:event];
}

- (void)playAutomotiveStation:(NSDictionary *)station emitEvent:(BOOL)emitEvent
{
  if (![station isKindOfClass:[NSDictionary class]]) {
    return;
  }

  NSString *streamURL = [TiUtils stringValue:@"streamUrl" properties:station];
  if (streamURL.length == 0) {
    return;
  }

  [self setCurrentAutomotiveStation:station];

  NSString *title = [TiUtils stringValue:@"title" properties:station def:[TiUtils stringValue:@"programName" properties:station def:@"Live Stream"]];
  NSString *artist = [TiUtils stringValue:@"artist" properties:station def:[TiUtils stringValue:@"stationName" properties:station def:[TiUtils stringValue:@"subtitle" properties:station def:@""]]];
  NSString *artwork = [TiUtils stringValue:@"artwork" properties:station];
  BOOL isLive = [TiUtils boolValue:@"isLive" properties:station def:YES];

  NSMutableDictionary *stream = [NSMutableDictionary dictionary];
  stream[@"url"] = streamURL;
  stream[@"isLive"] = @(isLive);
  stream[@"autoUpdateMetadata"] = @NO;
  if (title) {
    stream[@"title"] = title;
  }
  if (artist) {
    stream[@"artist"] = artist;
  }
  if (artwork) {
    stream[@"artwork"] = artwork;
  }

  [self setStream:stream];
  [self start:nil];

  if (emitEvent) {
    [self emitAutomotiveStationSelected:station source:TiAudiostreamAutomotiveSourceCarPlay];
  }
}

- (UIImage *)appIconImage
{
  if (!_appIconImage) {
    // Method 1: Load icon PNG directly from bundle (most reliable)
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSArray *candidates = @[@"AppIcon60x60@3x.png", @"AppIcon60x60@2x.png",
                            @"AppIcon76x76@2x.png", @"AppIcon83.5x83.5@2x.png",
                            @"AppIcon60x60.png", @"AppIcon76x76.png"];
    for (NSString *name in candidates) {
      NSString *path = [bundlePath stringByAppendingPathComponent:name];
      if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        _appIconImage = [UIImage imageWithContentsOfFile:path];
        if (_appIconImage) {
          NSLog(@"[ti.audiostream] App icon loaded from bundle: %@ (%gx%g)", name, _appIconImage.size.width, _appIconImage.size.height);
          break;
        }
      }
    }

    // Method 2: CFBundleIcons -> imageNamed
    if (!_appIconImage) {
      NSArray *iconFiles = [[NSBundle mainBundle] infoDictionary][@"CFBundleIcons"][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"];
      if (iconFiles.count > 0) {
        _appIconImage = [UIImage imageNamed:iconFiles.lastObject];
        if (_appIconImage) {
          NSLog(@"[ti.audiostream] App icon loaded via CFBundleIcons: %@", iconFiles.lastObject);
        }
      }
    }

    // Method 3: Try AppIcon by name
    if (!_appIconImage) {
      _appIconImage = [UIImage imageNamed:@"AppIcon"];
      if (_appIconImage) {
        NSLog(@"[ti.audiostream] App icon loaded via imageNamed:AppIcon");
      }
    }

    // Method 4: Load from .icns file (Mac Catalyst)
    if (!_appIconImage) {
      NSString *icnsPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
      if (icnsPath) {
        NSData *data = [NSData dataWithContentsOfFile:icnsPath];
        if (data) {
          CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
          if (source) {
            CGImageRef largest = NULL;
            size_t largestWidth = 0;
            size_t count = CGImageSourceGetCount(source);
            for (size_t i = 0; i < count; i++) {
              CGImageRef img = CGImageSourceCreateImageAtIndex(source, i, NULL);
              if (img) {
                size_t w = CGImageGetWidth(img);
                if (w > largestWidth) {
                  if (largest) CGImageRelease(largest);
                  largest = img;
                  largestWidth = w;
                } else {
                  CGImageRelease(img);
                }
              }
            }
            if (largest) {
              _appIconImage = [UIImage imageWithCGImage:largest];
              CGImageRelease(largest);
              NSLog(@"[ti.audiostream] App icon loaded from .icns (%gx%g)", _appIconImage.size.width, _appIconImage.size.height);
            }
            CFRelease(source);
          }
        }
      }
    }

    if (!_appIconImage) {
      NSLog(@"[ti.audiostream] WARNING: Could not load app icon from any source");
    }
  }
  return _appIconImage;
}

#if TARGET_OS_IOS
- (void)ensurePlayerInitialized
{
  if (_player) {
    return;
  }

  _player = [AVPlayer playerWithPlayerItem:nil];
  _player.automaticallyWaitsToMinimizeStalling = YES;

  if (@available(iOS 16.0, *)) {
    _nowPlayingSession = [[MPNowPlayingSession alloc] initWithPlayers:@[ _player ]];
    _nowPlayingSession.delegate = self;
    _nowPlayingSession.automaticallyPublishesNowPlayingInfo = NO;
  }
}

- (void)logNowPlayingSnapshot:(NSString *)reason
{
  NSDictionary *info = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo ?: @{};
  id rawTitle = info[MPMediaItemPropertyTitle];
  id rawArtist = info[MPMediaItemPropertyArtist];
  NSString *title = [rawTitle isKindOfClass:[NSString class]] ? rawTitle : @"";
  NSString *artist = [rawArtist isKindOfClass:[NSString class]] ? rawArtist : @"";
  NSNumber *rate = info[MPNowPlayingInfoPropertyPlaybackRate];
  NSNumber *isLive = info[MPNowPlayingInfoPropertyIsLiveStream];
  BOOL hasArtwork = info[MPMediaItemPropertyArtwork] != nil;

  if (@available(iOS 16.0, *)) {
    NSLog(@"[ti.audiostream] Snapshot(%@) session=%@ active=%@ canBecomeActive=%@ playerRate=%.2f title='%@' artist='%@' infoRate=%@ live=%@ artwork=%@ playbackState=%ld",
      reason,
      _nowPlayingSession ? @"YES" : @"NO",
      _nowPlayingSession && _nowPlayingSession.isActive ? @"YES" : @"NO",
      _nowPlayingSession && _nowPlayingSession.canBecomeActive ? @"YES" : @"NO",
      _player.rate,
      title,
      artist,
      rate ?: @(-1),
      isLive ?: @(NO),
      hasArtwork ? @"YES" : @"NO",
      (long)[MPNowPlayingInfoCenter defaultCenter].playbackState);
  } else {
    NSLog(@"[ti.audiostream] Snapshot(%@) playerRate=%.2f title='%@' artist='%@' infoRate=%@ live=%@ artwork=%@ playbackState=%ld",
      reason,
      _player.rate,
      title,
      artist,
      rate ?: @(-1),
      isLive ?: @(NO),
      hasArtwork ? @"YES" : @"NO",
      (long)[MPNowPlayingInfoCenter defaultCenter].playbackState);
  }
}

// Matches probe pattern: publish to BOTH session center AND shared center
- (NSArray<MPNowPlayingInfoCenter *> *)activeNowPlayingInfoCenters
{
  NSMutableArray<MPNowPlayingInfoCenter *> *centers = [NSMutableArray array];

  if (@available(iOS 16.0, *)) {
    if (_nowPlayingSession) {
      [centers addObject:_nowPlayingSession.nowPlayingInfoCenter];
    }
  }

  MPNowPlayingInfoCenter *sharedCenter = [MPNowPlayingInfoCenter defaultCenter];
  if (![centers containsObject:sharedCenter]) {
    [centers addObject:sharedCenter];
  }

  return centers;
}

// Matches probe pattern: register commands on BOTH session center AND shared center
- (void)registerRemoteCommandHandlersOnCenter:(MPRemoteCommandCenter *)commandCenter
{
  if (!commandCenter) {
    return;
  }

  [commandCenter.playCommand setEnabled:YES];
  [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self start:nil];
    [self fireRemoteControl:100];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.pauseCommand setEnabled:YES];
  [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self pause:nil];
    [self fireRemoteControl:101];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.togglePlayPauseCommand setEnabled:YES];
  [commandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    if (self->_player && self->_player.rate > 0) {
      [self pause:nil];
      [self fireRemoteControl:101];
    } else {
      [self start:nil];
      [self fireRemoteControl:100];
    }
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.stopCommand setEnabled:YES];
  [commandCenter.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self stop:nil];
    [self fireRemoteControl:102];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.nextTrackCommand setEnabled:YES];
  [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self fireRemoteControl:104];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.previousTrackCommand setEnabled:YES];
  [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self fireRemoteControl:105];
    return MPRemoteCommandHandlerStatusSuccess;
  }];
}

- (void)configureRemoteCommandHandlingIfNeeded
{
  // Matches probe: register on session center if available
  if (@available(iOS 16.0, *)) {
    if (!_nowPlayingSession) {
      [self ensurePlayerInitialized];
    }

    MPRemoteCommandCenter *sessionCommandCenter = _nowPlayingSession.remoteCommandCenter;
    if (sessionCommandCenter && _registeredSessionRemoteCommandCenter != sessionCommandCenter) {
      _registeredSessionRemoteCommandCenter = sessionCommandCenter;
      [self registerRemoteCommandHandlersOnCenter:sessionCommandCenter];
      NSLog(@"[ti.audiostream] Registered remote commands on session command center");
    }
  }

  // Matches probe: ALSO register on shared center
  MPRemoteCommandCenter *sharedCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  if (sharedCommandCenter && _registeredSharedRemoteCommandCenter != sharedCommandCenter) {
    _registeredSharedRemoteCommandCenter = sharedCommandCenter;
    [self registerRemoteCommandHandlersOnCenter:sharedCommandCenter];
    NSLog(@"[ti.audiostream] Registered remote commands on shared command center");
  }
}

- (void)activateNowPlayingSessionIfPossible
{
  if (@available(iOS 16.0, *)) {
    if (_nowPlayingSession && !_nowPlayingSession.isActive) {
      NSLog(@"[ti.audiostream] Requesting now playing session activation");
      [_nowPlayingSession becomeActiveIfPossibleWithCompletion:^(BOOL isActive) {
        NSLog(@"[ti.audiostream] Now playing session activation completed: %@", isActive ? @"YES" : @"NO");
        [self logNowPlayingSnapshot:@"session-activation-completion"];
      }];
    }
  }
}

- (void)setPlaybackState:(MPNowPlayingPlaybackState)playbackState
{
  for (MPNowPlayingInfoCenter *center in [self activeNowPlayingInfoCenters]) {
    center.playbackState = playbackState;
  }
}

- (void)handleCarPlaySceneDidConnect:(NSNotification *)notification
{
  NSLog(@"[ti.audiostream] Received CarPlay scene connect notification");

#if TARGET_OS_IOS
  if (!_playRequested || !_player || _player.rate <= 0) {
    NSLog(@"[ti.audiostream] CarPlay connected but no active playback — skipping reassertion");
    return;
  }

  NSLog(@"[ti.audiostream] CarPlay connected with active playback — reasserting Now Playing");

  // Re-activate audio session
  [[AVAudioSession sharedInstance] setActive:YES error:nil];

  // Re-publish Now Playing info to both centers
  [self updateNowPlaying];

  // Re-register remote commands
  [self configureRemoteCommandHandlingIfNeeded];

  // Promote our session as the active Now Playing source
  [self activateNowPlayingSessionIfPossible];
#endif
}

- (void)handleCarPlayNowPlayingDidPresent:(NSNotification *)notification
{
  NSLog(@"[ti.audiostream] Received CarPlay Now Playing presentation notification");
}

- (void)handleAutomotiveStationSelectedNotification:(NSNotification *)notification
{
  NSDictionary *station = [notification.object isKindOfClass:[NSDictionary class]] ? notification.object : notification.userInfo[@"station"];
  if (!station) {
    return;
  }

  [self playAutomotiveStation:station emitEvent:YES];
}

- (void)nowPlayingSessionDidChangeActive:(MPNowPlayingSession *)nowPlayingSession API_AVAILABLE(ios(16.0))
{
  NSLog(@"[ti.audiostream] Now playing session active=%@", nowPlayingSession.isActive ? @"YES" : @"NO");
}

- (void)nowPlayingSessionDidChangeCanBecomeActive:(MPNowPlayingSession *)nowPlayingSession API_AVAILABLE(ios(16.0))
{
  NSLog(@"[ti.audiostream] Now playing session canBecomeActive=%@", nowPlayingSession.canBecomeActive ? @"YES" : @"NO");
}
#endif

- (void)updateNowPlaying
{
  if (!_player)
    return;

#if TARGET_OS_IOS
  BOOL shouldAdvertisePlaying = _playRequested && (_isLive || _pendingPlay ||
    _player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate ||
    _player.timeControlStatus == AVPlayerTimeControlStatusPlaying || _player.rate > 0);
  float effectiveRate = shouldAdvertisePlaying ? 1.0f : _player.rate;
  MPNowPlayingPlaybackState playbackState = shouldAdvertisePlaying ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;

  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  info[MPMediaItemPropertyTitle] = _currentTitle ?: @"";
  info[MPMediaItemPropertyArtist] = _currentArtist ?: @"";
  info[MPNowPlayingInfoPropertyMediaType] = @(MPNowPlayingInfoMediaTypeAudio);
  info[MPNowPlayingInfoPropertyPlaybackRate] = @(effectiveRate);
  if (_isLive)
    info[MPNowPlayingInfoPropertyIsLiveStream] = @YES;
  UIImage *artworkToShow = _currentArtwork ?: [self appIconImage];
  if (artworkToShow) {
    info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkToShow.size
                                                                       requestHandler:^UIImage *(CGSize size) {
                                                                         return artworkToShow;
                                                                       }];
  }
  for (MPNowPlayingInfoCenter *center in [self activeNowPlayingInfoCenters]) {
    center.nowPlayingInfo = info;
    center.playbackState = playbackState;
  }
  [self activateNowPlayingSessionIfPossible];
  [self logNowPlayingSnapshot:@"update-now-playing"];
#endif
}

- (void)reassertNowPlayingContextForReason:(NSString *)reason attemptsRemaining:(NSUInteger)attemptsRemaining
{
#if TARGET_OS_IOS
  if (!_player || _player.rate <= 0) {
    NSLog(@"[ti.audiostream] reassert(%@) skipped — no active playback", reason);
    return;
  }

  NSLog(@"[ti.audiostream] reassert(%@) attempts=%lu", reason, (unsigned long)attemptsRemaining);

  // Re-activate audio session
  [[AVAudioSession sharedInstance] setActive:YES error:nil];

  // Re-publish Now Playing info
  [self updateNowPlaying];

  // Promote session
  [self activateNowPlayingSessionIfPossible];

  [self logNowPlayingSnapshot:reason];

  // Retry if needed — the system may not pick up the first attempt
  if (attemptsRemaining > 0) {
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [weakSelf reassertNowPlayingContextForReason:reason attemptsRemaining:attemptsRemaining - 1];
    });
  }
#endif
}

- (void)parseMetadataItems:(NSArray<AVMetadataItem *> *)items
{
  if (!items || items.count == 0)
    return;

  __block NSString *title = nil;
  __block NSString *artist = nil;
  __block UIImage *artwork = nil;
  __block NSString *artworkURL = nil;

  for (AVMetadataItem *item in items) {
    id key = item.key;
    NSString *commonKey = item.commonKey;
    id value = item.value;
    NSString *keyString = [key isKindOfClass:[NSString class]] ? (NSString *)key : [key description];
    NSString *stringValue = [value isKindOfClass:[NSString class]] ? (NSString *)value : nil;

    if ([commonKey isEqualToString:AVMetadataCommonKeyTitle]) {
      title = (NSString *)value;
    } else if ([commonKey isEqualToString:AVMetadataCommonKeyArtist]) {
      artist = (NSString *)value;
    } else if ([commonKey isEqualToString:AVMetadataCommonKeyArtwork]) {
      if ([value isKindOfClass:[NSData class]]) {
        artwork = [UIImage imageWithData:(NSData *)value];
      } else if ([value isKindOfClass:[NSDictionary class]]) {
        NSData *data = [value objectForKey:@"data"];
        if (data)
          artwork = [UIImage imageWithData:data];
      }
    }
    // Direct Key Match
    else if ([keyString isEqualToString:@"title"] || [keyString isEqualToString:@"StreamTitle"]) {
      title = (NSString *)value;
    } else if ([keyString isEqualToString:@"artist"]) {
      artist = (NSString *)value;
    }
    // Artwork URL from StreamUrl (Radio Paradise, etc.)
    else if ([keyString isEqualToString:@"StreamUrl"] && stringValue) {
      if ([stringValue hasSuffix:@".jpg"] || [stringValue hasSuffix:@".jpeg"] ||
          [stringValue hasSuffix:@".png"] || [stringValue hasSuffix:@".gif"] ||
          [stringValue containsString:@".jpg?"] || [stringValue containsString:@".png?"]) {
        artworkURL = stringValue;
        NSLog(@"[ti.audiostream] Found artwork URL in StreamUrl: %@", artworkURL);
      }
    }

    // Deep Inspection for Embedded Metadata (Global Player / ID3 COMM frames)
    if (stringValue && !title) {
      if ([stringValue containsString:@"StreamTitle='"]) {
        NSRange startRange = [stringValue rangeOfString:@"StreamTitle='"];
        if (startRange.location != NSNotFound) {
          NSUInteger startPos = startRange.location + startRange.length;
          NSRange endRange = [stringValue rangeOfString:@"';" options:0 range:NSMakeRange(startPos, stringValue.length - startPos)];
          if (endRange.location != NSNotFound) {
            title = [stringValue substringWithRange:NSMakeRange(startPos, endRange.location - startPos)];
          }
        }
      }
    }
  }

  if (title || artist || artwork || artworkURL) {
    NSMutableDictionary *rawSource = [NSMutableDictionary dictionary];
    for (AVMetadataItem *item in items) {
      id key = item.key;
      id value = item.value;
      NSString *keyString = [key isKindOfClass:[NSString class]] ? (NSString *)key : [key description];
      if (value)
        rawSource[keyString] = [value description];
    }

    // Handle "Artist - Title" combined format
    if (title && !artist && [title containsString:@" - "]) {
      NSArray *parts = [title componentsSeparatedByString:@" - "];
      artist = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      title = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }

    // Apply metadata rules (user-defined regex transformations)
    if (_titleRules) title = [self applyRules:_titleRules toString:title];
    if (_artistRules) artist = [self applyRules:_artistRules toString:artist];

    NSString *eventTitle = title ?: @"";
    NSString *eventArtist = artist ?: @"";
    BOOL changed = NO;
    if (_autoUpdateMetadata) {
      if (title && ![title isEqualToString:_currentTitle]) {
        _currentTitle = title;
        changed = YES;
      }
      if (artist && ![artist isEqualToString:_currentArtist]) {
        _currentArtist = artist;
        changed = YES;
      }
      if (artwork) {
        _currentArtwork = artwork;
        changed = YES;
      }
    }

    // Fetch artwork bitmap from URL for lock screen
    if (artworkURL) {
      NSUInteger expectedGeneration = _artworkGeneration;
      NSString *expectedURL = [_currentURL copy];
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:artworkURL]];
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (expectedGeneration != self->_artworkGeneration) {
              return;
            }
            if (expectedURL && self->_currentURL && ![expectedURL isEqualToString:self->_currentURL]) {
              return;
            }
            if (self->_autoUpdateMetadata) {
              self->_currentArtwork = img;
              [self updateNowPlaying];
            }
          });
        }
      });
      changed = YES;
    }

    if (changed && !artworkURL && self->_autoUpdateMetadata) {
      [self updateNowPlaying];
    }

    [self emitMetadataIfChangedWithTitle:eventTitle
                                  artist:eventArtist
                                 artwork:(artworkURL ?: @"")
                                     raw:rawSource];
  }
}

#pragma mark - AVPlayerItemMetadataOutputPushDelegate

- (void)metadataOutput:(AVPlayerItemMetadataOutput *)output didOutputTimedMetadataGroups:(NSArray<AVTimedMetadataGroup *> *)groups fromPlayerItemTrack:(AVPlayerItemTrack *)track
{
  for (AVTimedMetadataGroup *group in groups) {
    NSArray<AVMetadataItem *> *items = group.items;
    if (items.count > 0) {
      [self parseMetadataItems:items];
    }
  }
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (object == _player && [keyPath isEqualToString:@"timeControlStatus"]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self->_player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
        [self fireState:@"buffering"];
        [self setPlaybackState:MPNowPlayingPlaybackStatePlaying];
      } else if (self->_player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
        self->_retryCount = 0;
        [self fireState:@"playing"];
        [self setPlaybackState:MPNowPlayingPlaybackStatePlaying];
        [self updateNowPlaying];
      } else if (self->_player.timeControlStatus == AVPlayerTimeControlStatusPaused) {
        [self fireState:@"paused"];
        [self setPlaybackState:MPNowPlayingPlaybackStatePaused];
        [self updateNowPlaying];
      }
    });
  }
  if (object == _currentItem && [keyPath isEqualToString:@"status"]) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (item.status == AVPlayerItemStatusReadyToPlay) {
      [self parseMetadataItems:item.asset.commonMetadata];
    } else if (item.status == AVPlayerItemStatusFailed) {
      NSError *error = item.error;
      NSLog(@"[ti.audiostream] Playback Failed: %@ (domain=%@, code=%ld)", error.localizedDescription, error.domain, (long)error.code);

      // Classify the error: retryable (transient network) vs terminal (permanent)
      BOOL isRetryable = NO;
      if ([error.domain isEqualToString:NSURLErrorDomain]) {
        switch (error.code) {
          case NSURLErrorNetworkConnectionLost:
          case NSURLErrorNotConnectedToInternet:
          case NSURLErrorTimedOut:
          case NSURLErrorDataNotAllowed:
          case NSURLErrorInternationalRoamingOff:
          case NSURLErrorCallIsActive:
            // Transient network issues -- worth retrying
            isRetryable = YES;
            break;
          case NSURLErrorCannotFindHost:
          case NSURLErrorDNSLookupFailed:
          case NSURLErrorSecureConnectionFailed:
          case NSURLErrorServerCertificateHasBadDate:
          case NSURLErrorServerCertificateUntrusted:
          case NSURLErrorServerCertificateHasUnknownRoot:
          case NSURLErrorServerCertificateNotYetValid:
          case NSURLErrorClientCertificateRejected:
            // Permanent -- bad DNS or bad SSL, won't change on retry
            isRetryable = NO;
            break;
          default:
            // Other NSURLErrorDomain errors -- attempt retry
            isRetryable = YES;
            break;
        }
      }

      [self fireState:@"error"];
      [self fireError:error.localizedDescription];

      if (isRetryable && _retryCount < _maxRetries) {
        [self attemptReconnect];
      } else {
        if (!isRetryable) {
          NSLog(@"[ti.audiostream] Permanent error -- no retry");
        } else {
          NSLog(@"[ti.audiostream] Max retries (%d) exhausted", _maxRetries);
        }
        [self stop:nil];
      }
    }
  }
}

- (void)handleErrorLogEntry:(NSNotification *)notification
{
  AVPlayerItem *item = (AVPlayerItem *)notification.object;
  AVPlayerItemErrorLogEvent *lastEvent = item.errorLog.events.lastObject;
  if (lastEvent && lastEvent.errorStatusCode >= 400) {
    NSLog(@"[ti.audiostream] HTTP Error Detected: %ld on domain %@", (long)lastEvent.errorStatusCode, lastEvent.errorDomain);

    [self fireState:@"error"];
    [self fireError:[NSString stringWithFormat:@"HTTP Error: %ld", (long)lastEvent.errorStatusCode]];

    [self stop:nil];
  }
}

#if TARGET_OS_IOS
- (void)handleInterruption:(NSNotification *)n
{
  int type = [n.userInfo[AVAudioSessionInterruptionTypeKey] intValue];
  if (type == AVAudioSessionInterruptionTypeBegan) {
    _resumeOnInterruption = (_player && _player.timeControlStatus == AVPlayerTimeControlStatusPlaying);
    [self pause:nil];
  } else if (type == AVAudioSessionInterruptionTypeEnded) {
    if (_resumeOnInterruption) {
      int options = [n.userInfo[AVAudioSessionInterruptionOptionKey] intValue];
      if (options == AVAudioSessionInterruptionOptionShouldResume) {
        [self start:nil];
      }
    }
    _resumeOnInterruption = NO;
  }
}

- (void)handleAudioRouteChange:(NSNotification *)notification
{
  NSNumber *reasonNumber = notification.userInfo[AVAudioSessionRouteChangeReasonKey];
  AVAudioSessionRouteChangeReason reason = (AVAudioSessionRouteChangeReason)[reasonNumber integerValue];
  NSLog(@"[ti.audiostream] Audio route changed reason=%ld currentRoute=%@", (long)reason, [AVAudioSession sharedInstance].currentRoute);

  if (!_player) {
    return;
  }

  if (_player.rate > 0 || _player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
    [self reassertNowPlayingContextForReason:@"audio-route-change" attemptsRemaining:2];
  }
}
#endif

- (void)attemptReconnect
{
  _retryCount++;
  NSLog(@"[ti.audiostream] Reconnect attempt %d/%d in %.0fs...", _retryCount, _maxRetries, _retryDelay);
  [self fireState:@"buffering"];
  _retryTimer = [NSTimer scheduledTimerWithTimeInterval:_retryDelay
                                                 target:self
                                               selector:@selector(reconnect)
                                               userInfo:nil
                                                repeats:NO];
}

- (void)reconnect
{
  _retryTimer = nil;
  if (_currentURL) {
    _playRequested = YES;
    [self prepareCurrentStreamItem];
    [_player play];
  }
}

- (void)resetRetryLogic
{
  _retryCount = 0;
  if (_retryTimer) {
    [_retryTimer invalidate];
    _retryTimer = nil;
  }
}

- (void)fireState:(NSString *)state
{
  // Deduplicate: only emit on actual state transitions
  if ([state isEqualToString:_lastEmittedState]) {
    return;
  }
  _lastEmittedState = state;

  if ([self _hasListeners:@"state"])
    [self fireEvent:@"state" withObject:@{ @"state" : state }];
}
- (void)fireError:(NSString *)msg
{
  if ([self _hasListeners:@"error"])
    [self fireEvent:@"error" withObject:@{ @"message" : msg }];
}
- (void)fireRemoteControl:(NSInteger)subtype
{
  if ([self _hasListeners:@"remotecontrol"]) {
    NSString *action = @"UNKNOWN";
    switch (subtype) {
    case 100:
      action = @"PLAY";
      break;
    case 101:
      action = @"PAUSE";
      break;
    case 102:
      action = @"STOP";
      break;
    case 103:
      action = @"PLAY_PAUSE";
      break;
    case 104:
      action = @"NEXT";
      break;
    case 105:
      action = @"PREV";
      break;
    }
    [self fireEvent:@"remotecontrol" withObject:@{ @"subtype" : @(subtype), @"action" : action }];
  }
}

@end
