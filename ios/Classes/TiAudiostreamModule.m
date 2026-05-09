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

static UISceneConfiguration *TiAudiostream_configurationForConnecting(id self, SEL _cmd,
    UIApplication *application,
    UISceneSession *connectingSceneSession,
    UISceneConnectionOptions *options) API_AVAILABLE(ios(13.0))
{
  NSLog(@"[ti.audiostream] configurationForConnecting role=%@", connectingSceneSession.role);

  UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:connectingSceneSession.configuration.name
                                                                       sessionRole:connectingSceneSession.role];
  if ([connectingSceneSession.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
    configuration.delegateClass = [TiAudiostreamWindowSceneDelegate class];
    configuration.sceneClass = [UIWindowScene class];
  } else if ([connectingSceneSession.role isEqualToString:@"CPTemplateApplicationSceneSessionRoleApplication"]) {
    configuration.delegateClass = [TiAudiostreamCarPlaySceneDelegate class];
    configuration.sceneClass = [CPTemplateApplicationScene class];
  }

  return configuration;
}

// Force linker to keep scene delegate classes.
__attribute__((used)) static Class _cpClassRef;
__attribute__((used)) static Class _wsClassRef;
__attribute__((constructor))
static void TiAudiostreamRegisterSceneClasses(void)
{
  _cpClassRef = [TiAudiostreamCarPlaySceneDelegate class];
  _wsClassRef = [TiAudiostreamWindowSceneDelegate class];

  Class tiAppClass = NSClassFromString(@"TiApp");
  SEL selector = @selector(application:configurationForConnectingSceneSession:options:);
  if (tiAppClass && !class_getInstanceMethod(tiAppClass, selector)) {
    class_addMethod(tiAppClass, selector, (IMP)TiAudiostream_configurationForConnecting, "@@:@@@");
    NSLog(@"[ti.audiostream] Added manifest-style scene configuration dispatch to TiApp");
  }

  NSLog(@"[ti.audiostream] Registered scene delegate classes for manifest-based dispatch");
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
, MPNowPlayingSessionDelegate, MPPlayableContentDataSource, MPPlayableContentDelegate
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
  BOOL _prepareInProgress;
  NSString *_preparingURL;
  NSUInteger _streamGeneration;
  NSUInteger _nowPlayingPublishSequence;
  BOOL _terminalErrorReportedForCurrentItem;
  NSUInteger _artworkGeneration;
  UIImage *_appIconImage;
  NSUInteger _carPlayRefreshGeneration;
  int _retryCount;
  int _maxRetries;
  double _retryDelay;
  NSTimer *_retryTimer;
#if TARGET_OS_IOS
  MPNowPlayingSession *_nowPlayingSession API_AVAILABLE(ios(16.0));
  MPRemoteCommandCenter *_registeredSessionRemoteCommandCenter;
  MPRemoteCommandCenter *_registeredSharedRemoteCommandCenter;
  BOOL _playableContentManagerConfigured;
#endif
}
- (BOOL)hasNowPlayingPublishIntent;
- (NSString *)timeControlStatusName:(AVPlayerTimeControlStatus)status;
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
  [session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:0
                 error:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppDidBecomeActive:) name:UIApplicationDidBecomeActiveNotification object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleAppWillEnterForeground:) name:UIApplicationWillEnterForegroundNotification object:nil];
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
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleCarPlayNowPlayingDidPresent:)
                                               name:TiAudiostreamCarPlayDidPresentNowPlayingNotification
                                             object:nil];
}

#pragma mark - JS API

- (void)setStream:(id)args
{
  if (![NSThread isMainThread]) {
    id copiedArgs = [args isKindOfClass:[NSDictionary class]] ? [NSDictionary dictionaryWithDictionary:args] : args;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self setStream:copiedArgs];
    });
    return;
  }

  ENSURE_SINGLE_ARG(args, NSDictionary);
  NSString *requestedURL = [TiUtils stringValue:@"url" properties:args];
  if (requestedURL.length == 0) {
    NSLog(@"[ti.audiostream] setStream ignored: missing url");
    return;
  }

  BOOL forceReload = [TiUtils boolValue:@"force" properties:args def:NO];
  BOOL sameURL = _currentURL.length > 0 && [requestedURL isEqualToString:_currentURL];
  BOOL hasReusableItem = sameURL && !forceReload &&
    (_prepareInProgress || (_currentItem && _currentItem.status != AVPlayerItemStatusFailed));

  [self resetRetryLogic];
  if (!sameURL || forceReload) {
    _artworkGeneration++;
    _lastEmittedMetadataTitle = nil;
    _lastEmittedMetadataArtist = nil;
    _lastEmittedMetadataArtwork = nil;
  }
  _currentURL = requestedURL;
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

  if (hasReusableItem) {
    NSLog(@"[ti.audiostream] setStream reused active item for %@", requestedURL);
    if ([self hasNowPlayingPublishIntent]) {
      [self updateNowPlaying];
      [self activateNowPlayingSessionIfPossible];
    }
    return;
  }

  [self prepareCurrentStreamItem];
}

- (void)start:(id)unused
{
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self start:unused];
    });
    return;
  }

  if (!_player)
    return;

  [self resetRetryLogic];
  _playRequested = YES;

  // Guard clause: If already playing, don't re-prepare or interrupt
  if (_player.rate > 0 && _currentItem.status == AVPlayerItemStatusReadyToPlay) {
    return;
  }

#if TARGET_OS_IOS
  [self primeSystemAudioOwnershipForPlaybackStart];
#endif

  if (_prepareInProgress) {
    _pendingPlay = YES;
    return;
  }

  // If player is IDLE or has no valid item, prepare once and let the async
  // completion consume _pendingPlay. Calling prepare twice for the same URL can
  // replace the item that CarPlay just selected.
  if (!_currentItem || !_player.currentItem || _currentItem.status == AVPlayerItemStatusFailed) {
    _pendingPlay = YES;
    if (_currentURL.length > 0) {
      [self prepareCurrentStreamItem];
    }
    return;
  }

  [_player play];
  [self updateNowPlaying];
  [self activateNowPlayingSessionIfPossible];
}

- (void)pause:(id)unused
{
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self pause:unused];
    });
    return;
  }

  NSLog(@"[ti.audiostream] pause requested playRequested=%@ pending=%@ preparing=%@ rate=%.2f timeControl=%@",
    _playRequested ? @"YES" : @"NO",
    _pendingPlay ? @"YES" : @"NO",
    _prepareInProgress ? @"YES" : @"NO",
    _player ? _player.rate : 0.0,
    [self timeControlStatusName:_player ? _player.timeControlStatus : AVPlayerTimeControlStatusPaused]);
  NSLog(@"[ti.audiostream] pause call stack:\n%@", [[NSThread callStackSymbols] componentsJoinedByString:@"\n"]);
  if (_player) {
    _playRequested = NO;
    [_player pause];
    [self updateNowPlaying];
  }
}

- (void)stop:(id)args
{
  if (![NSThread isMainThread]) {
    id copiedArgs = [args isKindOfClass:[NSDictionary class]] ? [NSDictionary dictionaryWithDictionary:args] : args;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self stop:copiedArgs];
    });
    return;
  }

  NSLog(@"[ti.audiostream] stop requested hard=%@ playRequested=%@ pending=%@ preparing=%@ rate=%.2f",
    ([args isKindOfClass:[NSDictionary class]] && [TiUtils boolValue:@"hard" properties:args def:NO]) ? @"YES" : @"NO",
    _playRequested ? @"YES" : @"NO",
    _pendingPlay ? @"YES" : @"NO",
    _prepareInProgress ? @"YES" : @"NO",
    _player ? _player.rate : 0.0);
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
  _prepareInProgress = NO;
  _preparingURL = nil;
  _streamGeneration++;
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
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self hardStop:unused];
    });
    return;
  }

  NSLog(@"[ti.audiostream] hardStop requested playRequested=%@ pending=%@ preparing=%@ rate=%.2f",
    _playRequested ? @"YES" : @"NO",
    _pendingPlay ? @"YES" : @"NO",
    _prepareInProgress ? @"YES" : @"NO",
    _player ? _player.rate : 0.0);
  [self resetRetryLogic];
  _artworkGeneration++;
  _lastEmittedMetadataTitle = nil;
  _lastEmittedMetadataArtist = nil;
  _lastEmittedMetadataArtwork = nil;
  _playRequested = NO;
  _pendingPlay = NO;
  _prepareInProgress = NO;
  _preparingURL = nil;
  _streamGeneration++;
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
  if (![NSThread isMainThread]) {
    id copiedArgs = [args isKindOfClass:[NSDictionary class]] ? [NSDictionary dictionaryWithDictionary:args] : args;
    dispatch_async(dispatch_get_main_queue(), ^{
      [self setMetadata:copiedArgs];
    });
    return;
  }

  ENSURE_SINGLE_ARG(args, NSDictionary);
  _artworkGeneration++;
  NSUInteger expectedGeneration = _artworkGeneration;

  BOOL hasTitleKey = [args objectForKey:@"title"] != nil;
  BOOL hasArtistKey = [args objectForKey:@"artist"] != nil;
  BOOL hasArtworkKey = [args objectForKey:@"artwork"] != nil;

  if (hasTitleKey) {
    _currentTitle = [TiUtils stringValue:@"title" properties:args def:@""];
  }
  if (hasArtistKey) {
    _currentArtist = [TiUtils stringValue:@"artist" properties:args def:@""];
  }

  // Check if artwork key exists in args
  id artworkValue = [args objectForKey:@"artwork"];

  if (hasArtworkKey && artworkValue != [NSNull null]) {
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
  } else if (hasArtworkKey) {
    // Caller explicitly passed null/empty artwork -> clear it
    _currentArtwork = nil;
    [self updateNowPlaying];
  } else {
    // Preserve existing artwork/title/artist when the caller only updates a subset.
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
#if TARGET_OS_IOS
    [self refreshPlayableContentManagerForReason:@"stations-cleared"];
#endif
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
#if TARGET_OS_IOS
  [self refreshPlayableContentManagerForReason:@"stations-updated"];
#endif
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
#if TARGET_OS_IOS
    [self refreshPlayableContentManagerForReason:@"current-station-cleared"];
#endif
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
#if TARGET_OS_IOS
  [self refreshPlayableContentManagerForReason:@"current-station-updated"];
#endif
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
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self prepareCurrentStreamItem];
    });
    return;
  }

  if (_currentURL.length == 0) {
    NSLog(@"[ti.audiostream] prepare ignored: missing current URL");
    return;
  }

  NSUInteger generation = ++_streamGeneration;
  NSString *urlString = [_currentURL copy];
  _prepareInProgress = YES;
  _preparingURL = urlString;
  _terminalErrorReportedForCurrentItem = NO;
  BOOL shouldResumeAfterReplace = _playRequested || _pendingPlay;

  [self ensurePlayerInitialized];

  if (_player) {
    NSLog(@"[ti.audiostream] prepare replacing item: pausing player generation=%lu playRequested=%@ pending=%@ rate=%.2f timeControl=%@",
      (unsigned long)generation,
      _playRequested ? @"YES" : @"NO",
      _pendingPlay ? @"YES" : @"NO",
      _player.rate,
      [self timeControlStatusName:_player.timeControlStatus]);
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

  AVPlayerItem *newItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:urlString]];
  if (generation != _streamGeneration || ![urlString isEqualToString:_currentURL]) {
    return;
  }

  _prepareInProgress = NO;
  _preparingURL = nil;
  _currentItem = newItem;
  [_currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];

  _metadataOutput = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:nil];
  [_metadataOutput setDelegate:self queue:dispatch_get_main_queue()];
  [_currentItem addOutput:_metadataOutput];

  [_player replaceCurrentItemWithPlayerItem:_currentItem];

  if (shouldResumeAfterReplace) {
    _pendingPlay = NO;
    NSLog(@"[ti.audiostream] prepare resuming playback generation=%lu", (unsigned long)generation);
    [_player play];
  }

  if ([self hasNowPlayingPublishIntent]) {
    [self updateNowPlaying];
    [self activateNowPlayingSessionIfPossible];
  } else {
    NSLog(@"[ti.audiostream] Prepared stream item without publishing Now Playing");
  }
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
  BOOL hasPlayableItem = _player != nil && _currentItem != nil && _player.currentItem != nil &&
    _currentItem.status != AVPlayerItemStatusFailed;
  BOOL hasActivePlayback = hasPlayableItem && _playRequested && (
    _player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate ||
    _player.timeControlStatus == AVPlayerTimeControlStatusPlaying ||
    _player.rate > 0);
  BOOL sessionReady = YES;
  if (@available(iOS 16.0, *)) {
    sessionReady = _nowPlayingSession == nil || _nowPlayingSession.isActive;
  }
  return hasMetadata && hasActivePlayback && sessionReady;
#else
  return NO;
#endif
}

- (NSString *)carPlayCurrentStreamURL
{
  return _currentURL ?: @"";
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
#if TARGET_OS_IOS
  [self refreshPlayableContentManagerForReason:@"station-playback-started"];
#endif

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

  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:0
                 error:nil];
  [session setActive:YES error:nil];

  _player = [AVPlayer playerWithPlayerItem:nil];
  _player.automaticallyWaitsToMinimizeStalling = YES;

  if (@available(iOS 16.0, *)) {
    _nowPlayingSession = [[MPNowPlayingSession alloc] initWithPlayers:@[ _player ]];
    _nowPlayingSession.delegate = self;
    _nowPlayingSession.automaticallyPublishesNowPlayingInfo = NO;
  }

  [self configureRemoteCommandHandlingIfNeeded];
}

- (void)primeSystemAudioOwnershipForPlaybackStart
{
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:0
                 error:nil];
  [session setActive:YES error:nil];

  [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  [self ensurePlayerInitialized];
  [self configureRemoteCommandHandlingIfNeeded];
  [self configurePlayableContentManagerIfNeeded];

  NSLog(@"[ti.audiostream] ownership(start-prime) refreshed");
}

- (void)refreshSystemAudioOwnershipForReason:(NSString *)reason requireActivePlayback:(BOOL)requireActivePlayback
{
  AVAudioSession *session = [AVAudioSession sharedInstance];

  if (requireActivePlayback && (!_playRequested || !_player)) {
    NSLog(@"[ti.audiostream] ownership(%@) skipped - playback not requested", reason);
    return;
  }

  [session setCategory:AVAudioSessionCategoryPlayback
                  mode:AVAudioSessionModeDefault
               options:0
                 error:nil];
  [session setActive:YES error:nil];

  if (!_player && !_playRequested && _currentURL.length == 0) {
    NSLog(@"[ti.audiostream] ownership(%@) primed without player", reason);
    return;
  }

  [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
  [self ensurePlayerInitialized];
  [self configureRemoteCommandHandlingIfNeeded];
  [self configurePlayableContentManagerIfNeeded];

  if (_player && _player.currentItem && [self hasNowPlayingPublishIntent]) {
    [self updateNowPlaying];
    [self activateNowPlayingSessionIfPossible];
  }

  NSLog(@"[ti.audiostream] ownership(%@) refreshed", reason);
}

- (void)logNowPlayingSnapshot:(NSString *)reason
{
  MPNowPlayingInfoCenter *center = [[self activeNowPlayingInfoCenters] firstObject] ?: [MPNowPlayingInfoCenter defaultCenter];
  NSDictionary *info = center.nowPlayingInfo ?: @{};
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
	      (long)center.playbackState);
	  } else {
    NSLog(@"[ti.audiostream] Snapshot(%@) playerRate=%.2f title='%@' artist='%@' infoRate=%@ live=%@ artwork=%@ playbackState=%ld",
      reason,
      _player.rate,
      title,
      artist,
	      rate ?: @(-1),
	      isLive ?: @(NO),
	      hasArtwork ? @"YES" : @"NO",
	      (long)center.playbackState);
	  }
}

- (NSArray<MPNowPlayingInfoCenter *> *)activeNowPlayingInfoCenters
{
  NSMutableArray<MPNowPlayingInfoCenter *> *centers = [NSMutableArray array];
  if (@available(iOS 16.0, *)) {
    if (_nowPlayingSession) {
      [centers addObject:_nowPlayingSession.nowPlayingInfoCenter];
    }
  }
  MPNowPlayingInfoCenter *defaultCenter = [MPNowPlayingInfoCenter defaultCenter];
  if (![centers containsObject:defaultCenter]) {
    [centers addObject:defaultCenter];
  }
  return centers;
}

- (NSString *)stableNowPlayingContentIdentifier
{
  NSString *automotiveIdentifier = [self currentAutomotiveContentIdentifier];
  if (automotiveIdentifier.length > 0) {
    return automotiveIdentifier;
  }

  if (_currentURL.length > 0) {
    return [@"ti.audiostream.url." stringByAppendingString:_currentURL];
  }

  NSBundle *bundle = [NSBundle mainBundle];
  NSString *bundleIdentifier = bundle.bundleIdentifier;
  if (bundleIdentifier.length > 0) {
    return [@"ti.audiostream.app." stringByAppendingString:bundleIdentifier];
  }

  return @"ti.audiostream.current";
}

- (NSString *)automotiveContentIdentifierForStation:(NSDictionary *)station fallbackIndex:(NSUInteger)fallbackIndex
{
  if (![station isKindOfClass:[NSDictionary class]]) {
    return [NSString stringWithFormat:@"ti.audiostream.station.%lu", (unsigned long)fallbackIndex];
  }

  NSArray *keys = @[ @"id", @"identifier", @"stationId", @"streamUrl", @"url", @"title" ];
  for (NSString *key in keys) {
    NSString *value = [TiUtils stringValue:key properties:station];
    if (value.length > 0) {
      return [NSString stringWithFormat:@"ti.audiostream.station.%@", value];
    }
  }

  return [NSString stringWithFormat:@"ti.audiostream.station.%lu", (unsigned long)fallbackIndex];
}

- (NSString *)currentAutomotiveContentIdentifier
{
  NSDictionary *currentStation = [TiAudiostreamModule persistedCurrentAutomotiveStation];
  if (![currentStation isKindOfClass:[NSDictionary class]]) {
    return nil;
  }

  NSArray *stations = [TiAudiostreamModule persistedAutomotiveStations];
  NSUInteger index = [stations indexOfObjectPassingTest:^BOOL(id stationObject, NSUInteger idx, BOOL *stop) {
    NSDictionary *station = [stationObject isKindOfClass:[NSDictionary class]] ? stationObject : nil;
    if (![station isKindOfClass:[NSDictionary class]]) {
      return NO;
    }

    NSString *stationURL = [TiUtils stringValue:@"streamUrl" properties:station];
    NSString *currentURL = [TiUtils stringValue:@"streamUrl" properties:currentStation];
    if (stationURL.length > 0 && currentURL.length > 0 && [stationURL isEqualToString:currentURL]) {
      return YES;
    }

    NSString *stationID = [TiUtils stringValue:@"id" properties:station];
    NSString *currentID = [TiUtils stringValue:@"id" properties:currentStation];
    return stationID.length > 0 && currentID.length > 0 && [stationID isEqualToString:currentID];
  }];

  return [self automotiveContentIdentifierForStation:currentStation
                                      fallbackIndex:index == NSNotFound ? 0 : index];
}

- (void)configurePlayableContentManagerIfNeeded
{
  if (_playableContentManagerConfigured) {
    return;
  }

  MPPlayableContentManager *manager = [MPPlayableContentManager sharedContentManager];
  manager.dataSource = self;
  manager.delegate = self;
  _playableContentManagerConfigured = YES;
  [self refreshPlayableContentManagerForReason:@"configure"];
  NSLog(@"[ti.audiostream] playable-content manager configured");
}

- (void)refreshPlayableContentManagerForReason:(NSString *)reason
{
  MPPlayableContentManager *manager = [MPPlayableContentManager sharedContentManager];
  if (!_playableContentManagerConfigured) {
    return;
  }

  NSString *identifier = [self currentAutomotiveContentIdentifier];
  if (identifier.length > 0) {
    manager.nowPlayingIdentifiers = @[ identifier ];
  } else {
    manager.nowPlayingIdentifiers = @[];
  }

  [manager reloadData];
  NSLog(@"[ti.audiostream] playable-content refreshed (%@) nowPlayingIdentifiers=%@ stations=%lu",
    reason ?: @"unknown",
    manager.nowPlayingIdentifiers ?: @[],
    (unsigned long)[TiAudiostreamModule persistedAutomotiveStations].count);
}

- (NSInteger)numberOfChildItemsAtIndexPath:(NSIndexPath *)indexPath
{
  if (indexPath.length == 0) {
    return [TiAudiostreamModule persistedAutomotiveStations].count;
  }
  return 0;
}

- (MPContentItem *)contentItemAtIndexPath:(NSIndexPath *)indexPath
{
  NSArray *stations = [TiAudiostreamModule persistedAutomotiveStations];
  if (indexPath.length != 1) {
    return nil;
  }

  NSUInteger index = [indexPath indexAtPosition:0];
  if (index >= stations.count) {
    return nil;
  }

  NSDictionary *station = stations[index];
  NSString *identifier = [self automotiveContentIdentifierForStation:station fallbackIndex:index];
  MPContentItem *item = [[MPContentItem alloc] initWithIdentifier:identifier];
  item.title = [TiUtils stringValue:@"title" properties:station def:[TiUtils stringValue:@"programName" properties:station def:@"Live Stream"]];
  item.subtitle = [TiUtils stringValue:@"artist" properties:station def:[TiUtils stringValue:@"stationName" properties:station def:[TiUtils stringValue:@"subtitle" properties:station def:@""]]];
  item.playable = YES;
  item.container = NO;
  item.streamingContent = YES;

  UIImage *artworkImage = _currentArtwork ?: [self appIconImage];
  if (artworkImage) {
    item.artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:artworkImage.size
                                                   requestHandler:^UIImage *(CGSize size) {
                                                     return artworkImage;
                                                   }];
  }

  return item;
}

- (void)contentItemForIdentifier:(NSString *)identifier completionHandler:(void (^)(MPContentItem *contentItem, NSError *error))completionHandler
{
  NSArray *stations = [TiAudiostreamModule persistedAutomotiveStations];
  for (NSUInteger index = 0; index < stations.count; index++) {
    NSDictionary *station = stations[index];
    if ([[self automotiveContentIdentifierForStation:station fallbackIndex:index] isEqualToString:identifier]) {
      completionHandler([self contentItemAtIndexPath:[NSIndexPath indexPathWithIndex:index]], nil);
      return;
    }
  }

  completionHandler(nil, nil);
}

- (void)playableContentManager:(MPPlayableContentManager *)contentManager
 initiatePlaybackOfContentItemAtIndexPath:(NSIndexPath *)indexPath
             completionHandler:(void (^)(NSError *error))completionHandler
{
  NSArray *stations = [TiAudiostreamModule persistedAutomotiveStations];
  if (indexPath.length != 1 || [indexPath indexAtPosition:0] >= stations.count) {
    if (completionHandler) {
      completionHandler([NSError errorWithDomain:@"ti.audiostream"
                                            code:404
                                        userInfo:@{ NSLocalizedDescriptionKey : @"Station not found" }]);
    }
    return;
  }

  [self playAutomotiveStation:stations[[indexPath indexAtPosition:0]] emitEvent:YES];
  if (completionHandler) {
    completionHandler(nil);
  }
}

- (void)playableContentManager:(MPPlayableContentManager *)contentManager
 didUpdateContext:(MPPlayableContentManagerContext *)context
{
  NSLog(@"[ti.audiostream] playable-content context updated");
}

// Register on both centers because CarPlay can surface either the session
// command center or the application-wide default player.
- (void)registerRemoteCommandHandlersOnCenter:(MPRemoteCommandCenter *)commandCenter
{
  if (!commandCenter) {
    return;
  }

  // Match the native CarPlay probe's first MediaRemote snapshot: these four
  // commands must already be enabled before the first handler registration
  // causes reevaluation of "can be now playing".
  [commandCenter.playCommand setEnabled:YES];
  [commandCenter.pauseCommand setEnabled:YES];
  [commandCenter.nextTrackCommand setEnabled:YES];
  [commandCenter.previousTrackCommand setEnabled:YES];

  [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    NSLog(@"[ti.audiostream] remote command received: play");
    dispatch_async(dispatch_get_main_queue(), ^{
      [self start:nil];
      [self fireRemoteControl:100];
    });
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    NSLog(@"[ti.audiostream] remote command received: pause");
    dispatch_async(dispatch_get_main_queue(), ^{
      [self pause:nil];
      [self fireRemoteControl:101];
    });
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    NSLog(@"[ti.audiostream] remote command received: togglePlayPause rate=%.2f timeControl=%@",
      self->_player ? self->_player.rate : 0.0,
      [self timeControlStatusName:self->_player ? self->_player.timeControlStatus : AVPlayerTimeControlStatusPaused]);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (self->_player && self->_player.rate > 0) {
        [self pause:nil];
        [self fireRemoteControl:101];
      } else {
        [self start:nil];
        [self fireRemoteControl:100];
      }
    });
    return MPRemoteCommandHandlerStatusSuccess;
  }];
  [commandCenter.togglePlayPauseCommand setEnabled:YES];

  [commandCenter.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    NSLog(@"[ti.audiostream] remote command received: stop");
    dispatch_async(dispatch_get_main_queue(), ^{
      [self stop:nil];
      [self fireRemoteControl:102];
    });
    return MPRemoteCommandHandlerStatusSuccess;
  }];
  [commandCenter.stopCommand setEnabled:YES];

  [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    NSLog(@"[ti.audiostream] remote command received: nextTrack");
    dispatch_async(dispatch_get_main_queue(), ^{
      [self fireRemoteControl:104];
    });
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    NSLog(@"[ti.audiostream] remote command received: previousTrack");
    dispatch_async(dispatch_get_main_queue(), ^{
      [self fireRemoteControl:105];
    });
    return MPRemoteCommandHandlerStatusSuccess;
  }];
}

- (void)configureRemoteCommandHandlingIfNeeded
{
  if (!_player) {
    return;
  }

  if (@available(iOS 16.0, *)) {
    MPRemoteCommandCenter *sessionCommandCenter = _nowPlayingSession ? _nowPlayingSession.remoteCommandCenter : nil;
    if (sessionCommandCenter && _registeredSessionRemoteCommandCenter != sessionCommandCenter) {
      _registeredSessionRemoteCommandCenter = sessionCommandCenter;
      [self registerRemoteCommandHandlersOnCenter:sessionCommandCenter];
      NSLog(@"[ti.audiostream] Registered remote commands on session command center");
    }
  }

  MPRemoteCommandCenter *sharedCommandCenter = [MPRemoteCommandCenter sharedCommandCenter];
  if (sharedCommandCenter && _registeredSharedRemoteCommandCenter != sharedCommandCenter) {
    _registeredSharedRemoteCommandCenter = sharedCommandCenter;
    [self registerRemoteCommandHandlersOnCenter:sharedCommandCenter];
    NSLog(@"[ti.audiostream] Registered remote commands on shared command center");
  }
}

- (void)activateNowPlayingSessionIfPossible
{
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self activateNowPlayingSessionIfPossible];
    });
    return;
  }

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

- (void)refreshCarPlayNowPlayingItemForReason:(NSString *)reason
{
#if TARGET_OS_IOS
  if (!_player || !_playRequested) {
    NSLog(@"[ti.audiostream] carplay-refresh(%@) skipped - no requested playback", reason);
    return;
  }

  _carPlayRefreshGeneration += 1;
  NSLog(@"[ti.audiostream] carplay-refresh(%@) generation=%lu", reason, (unsigned long)_carPlayRefreshGeneration);
  [self updateNowPlaying];
  [self activateNowPlayingSessionIfPossible];
#endif
}

- (void)setPlaybackState:(MPNowPlayingPlaybackState)playbackState
{
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self setPlaybackState:playbackState];
    });
    return;
  }

  for (MPNowPlayingInfoCenter *center in [self activeNowPlayingInfoCenters]) {
    center.playbackState = playbackState;
  }
}

- (void)handleCarPlaySceneDidConnect:(NSNotification *)notification
{
  NSLog(@"[ti.audiostream] Received CarPlay scene connect notification");

#if TARGET_OS_IOS
  if (!_playRequested || !_player) {
    NSLog(@"[ti.audiostream] CarPlay connected but no active playback - skipping reassertion");
    return;
  }

  NSLog(@"[ti.audiostream] CarPlay connected with active playback - reasserting Now Playing");
  [self refreshSystemAudioOwnershipForReason:@"carplay-connect" requireActivePlayback:YES];
  __weak __typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf refreshCarPlayNowPlayingItemForReason:@"carplay-connect-delayed-1"];
  });
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf refreshCarPlayNowPlayingItemForReason:@"carplay-connect-delayed-2"];
  });
#endif
}

- (void)handleCarPlayNowPlayingDidPresent:(NSNotification *)notification
{
  NSLog(@"[ti.audiostream] Received CarPlay Now Playing presentation notification");
  __weak __typeof(self) weakSelf = self;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [weakSelf refreshCarPlayNowPlayingItemForReason:@"carplay-now-playing-presented"];
  });
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
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self updateNowPlaying];
    });
    return;
  }

  if (!_player)
    return;

#if TARGET_OS_IOS
  [self configureRemoteCommandHandlingIfNeeded];

  if (_playRequested &&
      _player.rate == 0 &&
      _player.timeControlStatus == AVPlayerTimeControlStatusPaused) {
    NSLog(@"[ti.audiostream] NowPlaying publish suppressed during transient paused playback intent title='%@' artist='%@'",
      _currentTitle ?: @"",
      _currentArtist ?: @"");
    return;
  }

  BOOL shouldAdvertisePlaying = _playRequested && (_isLive || _pendingPlay ||
    _player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate ||
    _player.timeControlStatus == AVPlayerTimeControlStatusPlaying || _player.rate > 0);
  float effectiveRate = shouldAdvertisePlaying ? 1.0f : _player.rate;
  MPNowPlayingPlaybackState playbackState = shouldAdvertisePlaying ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
  NSUInteger publishSequence = ++_nowPlayingPublishSequence;

  NSLog(@"[ti.audiostream] NowPlaying publish #%lu intent=%@ playRequested=%@ pending=%@ preparing=%@ live=%@ playerRate=%.2f timeControl=%@ infoRate=%.2f playbackState=%ld title='%@' artist='%@'",
    (unsigned long)publishSequence,
    shouldAdvertisePlaying ? @"YES" : @"NO",
    _playRequested ? @"YES" : @"NO",
    _pendingPlay ? @"YES" : @"NO",
    _prepareInProgress ? @"YES" : @"NO",
    _isLive ? @"YES" : @"NO",
    _player.rate,
    [self timeControlStatusName:_player.timeControlStatus],
    effectiveRate,
    (long)playbackState,
    _currentTitle ?: @"",
    _currentArtist ?: @"");

  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  info[MPMediaItemPropertyTitle] = _currentTitle ?: @"";
  info[MPMediaItemPropertyArtist] = _currentArtist ?: @"";
  info[MPNowPlayingInfoPropertyMediaType] = @(MPNowPlayingInfoMediaTypeAudio);
  info[MPNowPlayingInfoPropertyPlaybackRate] = @(effectiveRate);
  info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = @0;
  info[MPNowPlayingInfoPropertyPlaybackQueueCount] = @1;

  NSString *contentIdentifier = [self stableNowPlayingContentIdentifier];
  if (contentIdentifier.length > 0) {
    info[MPNowPlayingInfoPropertyExternalContentIdentifier] = contentIdentifier;
    info[MPNowPlayingInfoCollectionIdentifier] = contentIdentifier;
  }

  NSString *serviceIdentifier = [NSBundle mainBundle].bundleIdentifier ?: @"ti.audiostream";
  if (serviceIdentifier.length > 0) {
    info[MPNowPlayingInfoPropertyServiceIdentifier] = serviceIdentifier;
  }

  if (_currentURL.length > 0) {
    NSURL *assetURL = [NSURL URLWithString:_currentURL];
    if (assetURL) {
      info[MPNowPlayingInfoPropertyAssetURL] = assetURL;
    }
  }

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
    NSString *centerLabel = @"default";
    if (@available(iOS 16.0, *)) {
      if (_nowPlayingSession && center == _nowPlayingSession.nowPlayingInfoCenter) {
        centerLabel = @"session";
      }
    }
    NSLog(@"[ti.audiostream] NowPlaying publish #%lu applied center=%@ playbackState=%ld",
      (unsigned long)publishSequence,
      centerLabel,
      (long)playbackState);
  }
  [self activateNowPlayingSessionIfPossible];
  [self logNowPlayingSnapshot:@"update-now-playing"];
#endif
}

- (BOOL)hasNowPlayingPublishIntent
{
  if (!_player) {
    return NO;
  }

  return _playRequested || _pendingPlay ||
    _player.rate > 0 ||
    _player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate ||
    _player.timeControlStatus == AVPlayerTimeControlStatusPlaying;
}

- (NSString *)timeControlStatusName:(AVPlayerTimeControlStatus)status
{
  switch (status) {
    case AVPlayerTimeControlStatusPaused:
      return @"paused";
    case AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate:
      return @"waiting";
    case AVPlayerTimeControlStatusPlaying:
      return @"playing";
  }
  return @"unknown";
}

- (void)reassertNowPlayingContextForReason:(NSString *)reason attemptsRemaining:(NSUInteger)attemptsRemaining
{
#if TARGET_OS_IOS
  BOOL hasPlaybackIntent = _player != nil && (_playRequested || _pendingPlay ||
    _prepareInProgress ||
    _player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate ||
    _player.timeControlStatus == AVPlayerTimeControlStatusPlaying ||
    _player.rate > 0);
  if (!hasPlaybackIntent) {
    NSLog(@"[ti.audiostream] reassert(%@) skipped - no playback intent", reason);
    return;
  }

  NSLog(@"[ti.audiostream] reassert(%@) attempts=%lu", reason, (unsigned long)attemptsRemaining);
  [self refreshSystemAudioOwnershipForReason:reason requireActivePlayback:YES];
  [self logNowPlayingSnapshot:reason];

  // Retry if needed - the system may not pick up the first attempt
  if (attemptsRemaining > 0) {
    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [weakSelf reassertNowPlayingContextForReason:reason attemptsRemaining:attemptsRemaining - 1];
    });
  }
#endif
}

- (void)handleAppDidBecomeActive:(NSNotification *)notification
{
#if TARGET_OS_IOS
  [self refreshSystemAudioOwnershipForReason:@"app-did-become-active" requireActivePlayback:NO];
#endif
}

- (void)handleAppWillEnterForeground:(NSNotification *)notification
{
#if TARGET_OS_IOS
  [self refreshSystemAudioOwnershipForReason:@"app-will-enter-foreground" requireActivePlayback:NO];
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
  if (output != _metadataOutput) {
    return;
  }

  for (AVTimedMetadataGroup *group in groups) {
    NSArray<AVMetadataItem *> *items = group.items;
    if (items.count > 0) {
      [self parseMetadataItems:items];
    }
  }
}

#pragma mark - KVO

- (BOOL)isRetryablePlaybackError:(NSError *)error
{
  if (!error) {
    return NO;
  }

  if ([error.domain isEqualToString:NSURLErrorDomain]) {
    switch (error.code) {
      case NSURLErrorNetworkConnectionLost:
      case NSURLErrorNotConnectedToInternet:
      case NSURLErrorTimedOut:
      case NSURLErrorDataNotAllowed:
      case NSURLErrorInternationalRoamingOff:
      case NSURLErrorCallIsActive:
        return YES;

      case NSURLErrorBadURL:
      case NSURLErrorUnsupportedURL:
      case NSURLErrorCannotFindHost:
      case NSURLErrorCannotConnectToHost:
      case NSURLErrorDNSLookupFailed:
      case NSURLErrorBadServerResponse:
      case NSURLErrorResourceUnavailable:
      case NSURLErrorFileDoesNotExist:
      case NSURLErrorSecureConnectionFailed:
      case NSURLErrorServerCertificateHasBadDate:
      case NSURLErrorServerCertificateUntrusted:
      case NSURLErrorServerCertificateHasUnknownRoot:
      case NSURLErrorServerCertificateNotYetValid:
      case NSURLErrorClientCertificateRejected:
      case NSURLErrorCannotDecodeRawData:
      case NSURLErrorCannotDecodeContentData:
        return NO;

      default:
        return NO;
    }
  }

  return NO;
}

- (void)reportTerminalPlaybackErrorOnce:(NSString *)message
{
  if (_terminalErrorReportedForCurrentItem) {
    return;
  }

  _terminalErrorReportedForCurrentItem = YES;
  [self fireState:@"error"];
  [self fireError:message ?: @"Playback error"];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
  if (object == _player && [keyPath isEqualToString:@"timeControlStatus"]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      AVPlayerTimeControlStatus status = self->_player.timeControlStatus;
      NSLog(@"[ti.audiostream] timeControlStatus changed status=%@ playRequested=%@ pending=%@ preparing=%@ rate=%.2f",
        [self timeControlStatusName:status],
        self->_playRequested ? @"YES" : @"NO",
        self->_pendingPlay ? @"YES" : @"NO",
        self->_prepareInProgress ? @"YES" : @"NO",
        self->_player.rate);

      if (status == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
        [self fireState:@"buffering"];
        [self setPlaybackState:MPNowPlayingPlaybackStatePlaying];
      } else if (status == AVPlayerTimeControlStatusPlaying) {
        self->_retryCount = 0;
        [self fireState:@"playing"];
        [self setPlaybackState:MPNowPlayingPlaybackStatePlaying];
        [self updateNowPlaying];
      } else if (status == AVPlayerTimeControlStatusPaused) {
        if (self->_playRequested || self->_pendingPlay || self->_prepareInProgress) {
          NSLog(@"[ti.audiostream] Preserving Now Playing ownership during transient pause");
          [self fireState:@"buffering"];
          [self setPlaybackState:MPNowPlayingPlaybackStatePlaying];
          [self updateNowPlaying];
          return;
        }
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

      BOOL isRetryable = [self isRetryablePlaybackError:error];

      if (isRetryable && _retryCount < _maxRetries) {
        [self fireState:@"error"];
        [self fireError:error.localizedDescription];
        [self attemptReconnect];
      } else {
        if (!isRetryable) {
          NSLog(@"[ti.audiostream] Permanent error -- no retry");
        } else {
          NSLog(@"[ti.audiostream] Max retries (%d) exhausted", _maxRetries);
        }
        [self reportTerminalPlaybackErrorOnce:error.localizedDescription];
        [self stop:nil];
      }
    }
  }
}

- (void)handleErrorLogEntry:(NSNotification *)notification
{
  AVPlayerItem *item = (AVPlayerItem *)notification.object;
  if (item != _currentItem) {
    return;
  }

  AVPlayerItemErrorLogEvent *lastEvent = item.errorLog.events.lastObject;
  if (lastEvent && lastEvent.errorStatusCode >= 400) {
    NSLog(@"[ti.audiostream] HTTP Error Detected: %ld on domain %@", (long)lastEvent.errorStatusCode, lastEvent.errorDomain);

    [self reportTerminalPlaybackErrorOnce:[NSString stringWithFormat:@"HTTP Error: %ld", (long)lastEvent.errorStatusCode]];

    [self stop:nil];
  }
}

#if TARGET_OS_IOS
- (void)handleInterruption:(NSNotification *)n
{
  int type = [n.userInfo[AVAudioSessionInterruptionTypeKey] intValue];
  NSLog(@"[ti.audiostream] audio interruption type=%d playRequested=%@ rate=%.2f timeControl=%@",
    type,
    _playRequested ? @"YES" : @"NO",
    _player ? _player.rate : 0.0,
    [self timeControlStatusName:_player ? _player.timeControlStatus : AVPlayerTimeControlStatusPaused]);
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
    _pendingPlay = YES;
    [self prepareCurrentStreamItem];
    [self updateNowPlaying];
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
