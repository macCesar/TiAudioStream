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
}
@end

@implementation TiAudiostreamModule

#pragma mark - Lifecycle

- (id)moduleGUID { return @"04e2decf-6370-43f1-bf1d-457c4b417325"; }
- (NSString *)moduleId { return @"ti.audiostream"; }

- (void)startup
{
    [super startup];
    
#if TARGET_OS_IOS
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
    [session setActive:YES error:nil];
#endif
    
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
    [cc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self fireRemoteControl:104]; return MPRemoteCommandHandlerStatusSuccess; }];
    
    [cc.previousTrackCommand setEnabled:YES];
    [cc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self fireRemoteControl:105]; return MPRemoteCommandHandlerStatusSuccess; }];
    
#if TARGET_OS_IOS
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
#endif
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleErrorLogEntry:) name:AVPlayerItemNewErrorLogEntryNotification object:nil];
}

#pragma mark - JS API

- (void)setStream:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    _currentURL = [TiUtils stringValue:@"url" properties:args];
    _isLive = [TiUtils boolValue:@"isLive" properties:args def:YES];

    // 1. Parar y limpiar TODO inmediatamente
    if (_player) {
        [_player pause];
        @try { [_player removeObserver:self forKeyPath:@"timeControlStatus"]; } @catch (id e) {}
    }

    if (_currentItem) {
        @try { [_currentItem removeObserver:self forKeyPath:@"status"]; } @catch (id e) {}
        if (_metadataOutput) {
            [_currentItem removeOutput:_metadataOutput];
            _metadataOutput = nil;
        }
        _currentItem = nil;
    }

    // 2. Notificar buffering de inmediato al JS
    [self fireState:@"buffering"];

    // 3. Configurar nuevo item
    _currentItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:_currentURL]];
    [_currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];

    // 4. Configurar AVPlayerItemMetadataOutput (reemplazo moderno de timedMetadata)
    // Pasamos nil para recibir TODOS los metadata disponibles
    _metadataOutput = [[AVPlayerItemMetadataOutput alloc] initWithIdentifiers:nil];
    [_metadataOutput setDelegate:self queue:dispatch_get_main_queue()];
    [_currentItem addOutput:_metadataOutput];

    if (_player) {
        [_player replaceCurrentItemWithPlayerItem:_currentItem];
    } else {
        _player = [AVPlayer playerWithPlayerItem:_currentItem];
    }

    _player.automaticallyWaitsToMinimizeStalling = YES;

    [_player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)start:(id)unused { 
    if (!_player) return;

    // Guard clause: If already playing, don't re-prepare
    if (_player.rate > 0 && _currentItem.status == AVPlayerItemStatusReadyToPlay) {
        return;
    }

#if TARGET_OS_IOS
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
#endif
    
    // Intelligence: If it's a live stream, we ALWAYS re-prepare on Play to ensure we jump to the live edge
    if (_isLive && _currentURL) {
        NSLog(@"[ti.audiostream] Live stream: Re-preparing source to jump to live edge.");
        [self setStream:@{@"url": _currentURL, @"isLive": @(_isLive)}];
    } 
    // For non-live, only resurrect if it's in a failed/null state
    else if (_currentURL && (!_currentItem || _currentItem.status == AVPlayerItemStatusFailed)) {
        NSLog(@"[ti.audiostream] VOD stream item invalid, resurrecting: %@", _currentURL);
        [self setStream:@{@"url": _currentURL, @"isLive": @(_isLive)}];
    }
    
    [_player play]; 
    [self updateNowPlaying]; 
}

- (void)pause:(id)unused { 
    if (_player && _player.rate > 0) { 
        [_player pause]; 
        [self updateNowPlaying]; 
    } 
}

- (void)stop:(id)unused { 
    if (_player) { 
        [_player pause]; 
        @try { [_player replaceCurrentItemWithPlayerItem:nil]; } @catch (id e) {}
    }
    [self fireState:@"stopped"];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

- (void)setMetadata:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    _currentTitle = [TiUtils stringValue:@"title" properties:args def:@""];
    _currentArtist = [TiUtils stringValue:@"artist" properties:args def:@""];
    NSString *artworkURL = [TiUtils stringValue:@"artwork" properties:args];
    
    if (artworkURL) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:artworkURL]];
            UIImage *img = [UIImage imageWithData:data];
            if (img) { 
                dispatch_async(dispatch_get_main_queue(), ^{ 
                    self->_currentArtwork = img; 
                    [self updateNowPlaying]; 
                }); 
            }
        });
    } else {
        _currentArtwork = nil;
        [self updateNowPlaying];
    }
}

#pragma mark - Properties

- (id)playing { return NUMBOOL(_player != nil && _player.rate > 0); }

#pragma mark - Constants

- (id)REMOTE_CONTROL_PLAY { return @(100); }
- (id)REMOTE_CONTROL_PAUSE { return @(101); }
- (id)REMOTE_CONTROL_STOP { return @(102); }
- (id)REMOTE_CONTROL_PLAY_PAUSE { return @(103); }
- (id)REMOTE_CONTROL_NEXT { return @(104); }
- (id)REMOTE_CONTROL_PREV { return @(105); }

#pragma mark - Internal

- (void)updateNowPlaying
{
    if (!_player) return;
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = _currentTitle ?: @"";
    info[MPMediaItemPropertyArtist] = _currentArtist ?: @"";
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(_player.rate);
    if (_isLive) info[MPNowPlayingInfoPropertyIsLiveStream] = @YES;
    if (_currentArtwork) {
        info[MPMediaItemPropertyArtwork] = [[MPMediaItemArtwork alloc] initWithBoundsSize:_currentArtwork.size requestHandler:^UIImage *(CGSize size) { return self->_currentArtwork; }];
    }
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)parseMetadataItems:(NSArray<AVMetadataItem *> *)items {
    if (!items || items.count == 0) return;

    __block NSString *title = nil;
    __block NSString *artist = nil;
    __block UIImage *artwork = nil;

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
                if (data) artwork = [UIImage imageWithData:data];
            }
        }
        // Direct Key Match
        else if ([keyString isEqualToString:@"title"] || [keyString isEqualToString:@"StreamTitle"]) {
            title = (NSString *)value;
        } else if ([keyString isEqualToString:@"artist"]) {
            artist = (NSString *)value;
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

    if (title || artist || artwork) {
        NSMutableDictionary *rawSource = [NSMutableDictionary dictionary];
        for (AVMetadataItem *item in items) {
            id key = item.key;
            id value = item.value;
            NSString *keyString = [key isKindOfClass:[NSString class]] ? (NSString *)key : [key description];
            if (value) rawSource[keyString] = [value description];
        }

        // Handle "Artist - Title" combined format
        if (title && !artist && [title containsString:@" - "]) {
            NSArray *parts = [title componentsSeparatedByString:@" - "];
            artist = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            title = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }

        NSLog(@"[ti.audiostream] Parsed Metadata: Title='%@', Artist='%@', Artwork=%@", title, artist, artwork ? @"YES" : @"NO");
        
        BOOL changed = NO;
        if (title && ![title isEqualToString:_currentTitle]) { _currentTitle = title; changed = YES; }
        if (artist && ![artist isEqualToString:_currentArtist]) { _currentArtist = artist; changed = YES; }
        if (artwork) { _currentArtwork = artwork; changed = YES; }

        if (changed) {
            [self updateNowPlaying];
            if ([self _hasListeners:@"metadata"]) {
                [self fireEvent:@"metadata" withObject:@{
                    @"title": _currentTitle ?: @"",
                    @"artist": _currentArtist ?: @"",
                    @"artwork": @"",
                    @"raw": rawSource
                }];
            }
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
            if (self->_player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) { [self fireState:@"buffering"]; }
            else if (self->_player.timeControlStatus == AVPlayerTimeControlStatusPlaying) { [self fireState:@"playing"]; [self updateNowPlaying]; }
            else if (self->_player.timeControlStatus == AVPlayerTimeControlStatusPaused) { [self fireState:@"paused"]; [self updateNowPlaying]; }
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
- (void)handleInterruption:(NSNotification *)n {
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

- (void)fireState:(NSString *)state { if ([self _hasListeners:@"state"]) [self fireEvent:@"state" withObject:@{@"state":state}]; }
- (void)fireError:(NSString *)msg { if ([self _hasListeners:@"error"]) [self fireEvent:@"error" withObject:@{@"message":msg}]; }
- (void)fireRemoteControl:(NSInteger)subtype { 
    if ([self _hasListeners:@"remotecontrol"]) {
        NSString *action = @"UNKNOWN";
        switch (subtype) {
            case 100: action = @"PLAY"; break;
            case 101: action = @"PAUSE"; break;
            case 102: action = @"STOP"; break;
            case 103: action = @"PLAY_PAUSE"; break;
            case 104: action = @"NEXT"; break;
            case 105: action = @"PREV"; break;
        }
        [self fireEvent:@"remotecontrol" withObject:@{@"subtype": @(subtype), @"action": action}]; 
    }
}

@end

