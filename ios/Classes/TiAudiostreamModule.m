/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiAudiostreamModule.h"
#import "TiBase.h"
#import "TiHost.h"
#import "TiUtils.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

@interface TiAudiostreamModule () <AVPlayerItemMetadataOutputPushDelegate> {
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
  NSArray *_titleRules;
  NSArray *_artistRules;
  NSString *_lastEmittedState;
  BOOL _pendingPlay;
  NSUInteger _artworkGeneration;
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

  // Default: auto-update metadata from stream
  _autoUpdateMetadata = YES;

#if TARGET_OS_IOS
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
  [session setActive:YES error:nil];

  MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
  [cc.playCommand setEnabled:YES];
  [cc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self start:nil];
    [self fireRemoteControl:100];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [cc.pauseCommand setEnabled:YES];
  [cc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self pause:nil];
    [self fireRemoteControl:101];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [cc.stopCommand setEnabled:YES];
  [cc.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self stop:nil];
    [self fireRemoteControl:102];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [cc.nextTrackCommand setEnabled:YES];
  [cc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self fireRemoteControl:104];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [cc.previousTrackCommand setEnabled:YES];
  [cc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) {
    [self fireRemoteControl:105];
    return MPRemoteCommandHandlerStatusSuccess;
  }];

  [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
#endif

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleErrorLogEntry:)
                                               name:AVPlayerItemNewErrorLogEntryNotification
                                             object:nil];
}

#pragma mark - JS API

- (void)setStream:(id)args
{
  ENSURE_SINGLE_ARG(args, NSDictionary);
  _artworkGeneration++;
  _currentURL = [TiUtils stringValue:@"url" properties:args];
  _isLive = [TiUtils boolValue:@"isLive" properties:args def:YES];
  _autoUpdateMetadata = [TiUtils boolValue:@"autoUpdateMetadata" properties:args def:YES];

  // Check if title, artist, artwork are provided
  NSString *title = [TiUtils stringValue:@"title" properties:args];
  NSString *artist = [TiUtils stringValue:@"artist" properties:args];
  id artworkValue = [args objectForKey:@"artwork"]; // Check if key exists (can be null)

  // Always set metadata when changing streams (clears previous)
  NSMutableDictionary *metaDict = [NSMutableDictionary dictionary];
  if (title)
    [metaDict setObject:title forKey:@"title"];
  if (artist)
    [metaDict setObject:artist forKey:@"artist"];

  // Handle artwork: null/"" → clear, string → load, not provided → clear (new stream behavior)
  if (artworkValue != nil && artworkValue != [NSNull null]) {
    NSString *artwork = [TiUtils stringValue:@"artwork" properties:args];
    // null or empty string → clear, valid url → load
    [metaDict setObject:(artwork ?: @"") forKey:@"artwork"];
  } else {
    // Key not provided → clear artwork for new stream
    [metaDict setObject:@"" forKey:@"artwork"];
  }

  [self setMetadata:metaDict];

  // Handle metadataRules: present + dict → set, present + null → clear, absent → preserve
  if ([args objectForKey:@"metadataRules"] != nil) {
    id rulesValue = [args objectForKey:@"metadataRules"];
    if ([rulesValue isKindOfClass:[NSDictionary class]]) {
      [self setMetadataRules:rulesValue];
    } else {
      // NSNull or any non-dict → clear rules
      [self setMetadataRules:nil];
    }
  }

  [self prepareCurrentStreamItem];
}

- (void)start:(id)unused
{
  if (!_player)
    return;

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

  // Si el item aún no está conectado (async en progreso), diferir el play
  if (!_currentItem || !_player.currentItem) {
    _pendingPlay = YES;
    return;
  }

  [_player play];
  [self updateNowPlaying];
}

- (void)pause:(id)unused
{
  if (_player && _player.rate > 0) {
    [_player pause];
    [self updateNowPlaying];
  }
}

- (void)stop:(id)unused
{
  _artworkGeneration++;
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
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
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

    // If null, empty string, or just whitespace → clear artwork
    if (artworkURL == nil || [artworkURL length] == 0 || [[artworkURL stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length] == 0) {
      _currentArtwork = nil;
      [self updateNowPlaying];
    } else {
      // Valid URL → load it
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
            // Failed to load → clear artwork
            self->_currentArtwork = nil;
          }
          [self updateNowPlaying];
        });
      });
    }
  } else {
    // Key not provided → clear artwork (new stream behavior)
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

  if (!_player) {
    _player = [AVPlayer playerWithPlayerItem:nil];
    _player.automaticallyWaitsToMinimizeStalling = YES;
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
      }
    });
  });
}

#pragma mark - Internal

- (void)updateNowPlaying
{
  if (!_player)
    return;

#if TARGET_OS_IOS
  NSMutableDictionary *info = [NSMutableDictionary dictionary];
  info[MPMediaItemPropertyTitle] = _currentTitle ?: @"";
  info[MPMediaItemPropertyArtist] = _currentArtist ?: @"";
  info[MPNowPlayingInfoPropertyPlaybackRate] = @(_player.rate);
  if (_isLive)
    info[MPNowPlayingInfoPropertyIsLiveStream] = @YES;
  if (_currentArtwork) {
    info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:_currentArtwork.size
                                                                       requestHandler:^UIImage *(CGSize size) {
                                                                         return self->_currentArtwork;
                                                                       }];
  }
  [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
#endif

  // Note: Mac Catalyst does not support MPNowPlayingInfoCenter
  // The metadata is still available via the 'metadata' event and module properties
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

    NSLog(@"[ti.audiostream] Metadata Item Found: key=%@, commonKey=%@, valueType=%@", keyString, commonKey, NSStringFromClass([value class]));

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
      // Check if it's an image URL
      if ([stringValue hasSuffix:@".jpg"] || [stringValue hasSuffix:@".jpeg"] ||
          [stringValue hasSuffix:@".png"] || [stringValue hasSuffix:@".gif"] ||
          [stringValue containsString:@".jpg?"] || [stringValue containsString:@".png?"]) {
        artworkURL = stringValue;
        NSLog(@"[ti.audiostream] Found artwork URL: %@", artworkURL);
      }
    }

    // Deep Inspection for Embedded Metadata (Global Player / ID3 COMM frames)
    if (stringValue && !title) {
      if ([stringValue containsString:@"StreamTitle='"]) {
        NSLog(@"[ti.audiostream] Found embedded StreamTitle in: %@", keyString);
        // Extract content between StreamTitle=' and ';
        NSRange startRange = [stringValue rangeOfString:@"StreamTitle='"];
        if (startRange.location != NSNotFound) {
          NSUInteger startPos = startRange.location + startRange.length;
          NSRange endRange = [stringValue rangeOfString:@"';" options:0 range:NSMakeRange(startPos, stringValue.length - startPos)];
          if (endRange.location != NSNotFound) {
            title = [stringValue substringWithRange:NSMakeRange(startPos, endRange.location - startPos)];
            NSLog(@"[ti.audiostream] Extracted Title: %@", title);
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

    NSLog(@"[ti.audiostream] Parsed Metadata: Title='%@', Artist='%@', Artwork=%@, ArtworkURL=%@", title, artist, artwork ? @"YES" : @"NO", artworkURL ?: @"none");

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

    // Fetch artwork from URL if found
    if (artworkURL) {
      __block NSString *capturedArtworkURL = [artworkURL copy]; // Capture for block
      __block NSString *capturedEventTitle = [eventTitle copy];
      __block NSString *capturedEventArtist = [eventArtist copy];
      NSUInteger expectedGeneration = _artworkGeneration;
      NSString *expectedURL = [_currentURL copy];
      dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:capturedArtworkURL]];
        UIImage *img = [UIImage imageWithData:data];
        if (img) {
          dispatch_async(dispatch_get_main_queue(), ^{
            if (expectedGeneration != self->_artworkGeneration) {
              return;
            }
            if (expectedURL && self->_currentURL && ![expectedURL isEqualToString:self->_currentURL]) {
              return;
            }
            // Only update remote controls if auto-update is enabled
            if (self->_autoUpdateMetadata) {
              self->_currentArtwork = img;
              [self updateNowPlaying];
            }
            // Fire metadata event again with artwork URL (always fire for app UI)
            if ([self _hasListeners:@"metadata"]) {
              [self fireEvent:@"metadata"
                   withObject:@{
                     @"title" : capturedEventTitle ?: @"",
                     @"artist" : capturedEventArtist ?: @"",
                     @"artwork" : capturedArtworkURL,
                     @"raw" : rawSource
                   }];
            }
          });
        }
      });
      // Update immediately without artwork, it'll come shortly
      changed = YES;
    }

    if (changed && !artworkURL && self->_autoUpdateMetadata) {
      [self updateNowPlaying];
    }

    if ([self _hasListeners:@"metadata"]) {
      [self fireEvent:@"metadata"
           withObject:@{
             @"title" : eventTitle,
             @"artist" : eventArtist,
             @"artwork" : artworkURL ?: @"",
             @"raw" : rawSource
           }];
    }
  }
}

#pragma mark - AVPlayerItemMetadataOutputPushDelegate

- (void)metadataOutput:(AVPlayerItemMetadataOutput *)output didOutputTimedMetadataGroups:(NSArray<AVTimedMetadataGroup *> *)groups fromPlayerItemTrack:(AVPlayerItemTrack *)track
{
  NSLog(@"[ti.audiostream] Metadata output received %lu groups", (unsigned long)groups.count);

  for (AVTimedMetadataGroup *group in groups) {
    NSArray<AVMetadataItem *> *items = group.items;
    if (items.count > 0) {
      NSLog(@"[ti.audiostream] Processing metadata group with %lu items", (unsigned long)items.count);
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
      } else if (self->_player.timeControlStatus == AVPlayerTimeControlStatusPlaying) {
        [self fireState:@"playing"];
        [self updateNowPlaying];
      } else if (self->_player.timeControlStatus == AVPlayerTimeControlStatusPaused) {
        [self fireState:@"paused"];
        [self updateNowPlaying];
      }
    });
  }
  if (object == _currentItem && [keyPath isEqualToString:@"status"]) {
    AVPlayerItem *item = (AVPlayerItem *)object;
    if (item.status == AVPlayerItemStatusReadyToPlay) {
      NSLog(@"[ti.audiostream] PlayerItem ReadyToPlay. Checking commonMetadata...");
      [self parseMetadataItems:item.asset.commonMetadata];
    } else if (item.status == AVPlayerItemStatusFailed) {
      NSError *error = item.error;
      NSLog(@"[ti.audiostream] Playback Failed: %@", error.localizedDescription);

      [self fireState:@"error"];
      [self fireError:error.localizedDescription];

      [self stop:nil];
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

    // Error HTTP (404, 500, etc) = Detener inmediatamente
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
#endif

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
