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

@interface TiAudiostreamModule () {
    AVPlayer *_player;
    AVPlayerItem *_currentItem;
    BOOL _isLive;
    NSString *_currentURL;
    NSString *_currentTitle;
    NSString *_currentArtist;
    UIImage *_currentArtwork;
    NSInteger _retryCount;
    BOOL _isReconnecting;
}
@end

@implementation TiAudiostreamModule

#pragma mark - Lifecycle

- (id)moduleGUID { return @"04e2decf-6370-43f1-bf1d-457c4b417325"; }
- (NSString *)moduleId { return @"ti.audiostream"; }

- (void)startup
{
    [super startup];
    _retryCount = 0;
    _isReconnecting = NO;
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
    [session setActive:YES error:nil];
    
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    [cc.playCommand setEnabled:YES];
    [cc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self start:nil]; return MPRemoteCommandHandlerStatusSuccess; }];
    
    [cc.pauseCommand setEnabled:YES];
    [cc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self pause:nil]; return MPRemoteCommandHandlerStatusSuccess; }];
    
    [cc.stopCommand setEnabled:YES];
    [cc.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self stop:nil]; return MPRemoteCommandHandlerStatusSuccess; }];
    
    [cc.nextTrackCommand setEnabled:YES];
    [cc.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self fireRemoteControl:104]; return MPRemoteCommandHandlerStatusSuccess; }];
    
    [cc.previousTrackCommand setEnabled:YES];
    [cc.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self fireRemoteControl:105]; return MPRemoteCommandHandlerStatusSuccess; }];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
}

#pragma mark - JS API

- (void)setStream:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    _currentURL = [TiUtils stringValue:@"url" properties:args];
    _isLive = [TiUtils boolValue:@"isLive" properties:args def:YES];
    _retryCount = 0;
    _isReconnecting = NO;
    
    // 1. Parar y limpiar TODO inmediatamente para evitar que se escuche la frecuencia anterior
    if (_player) {
        [_player pause];
        @try { [_player removeObserver:self forKeyPath:@"timeControlStatus"]; } @catch (id e) {}
    }
    
    if (_currentItem) {
        @try { [_currentItem removeObserver:self forKeyPath:@"status"]; } @catch (id e) {}
        _currentItem = nil;
    }
    
    // 2. Notificar buffering de inmediato al JS
    [self fireState:@"buffering"];
    
    // 3. Configurar nuevo item
    _currentItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:_currentURL]];
    [_currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
    if (_player) {
        [_player replaceCurrentItemWithPlayerItem:_currentItem];
    } else {
        _player = [AVPlayer playerWithPlayerItem:_currentItem];
        _player.automaticallyWaitsToMinimizeStalling = YES;
    }
    
    [_player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)start:(id)unused { 
    if (_player) { 
        [[AVAudioSession sharedInstance] setActive:YES error:nil]; 
        [_player play]; 
        [self updateNowPlaying]; 
    } 
}

- (void)pause:(id)unused { 
    if (_player) { 
        [_player pause]; 
        [self updateNowPlaying]; 
    } 
}

- (void)stop:(id)unused { 
    _isReconnecting = NO;
    if (_player) { 
        [_player pause]; 
        [_player replaceCurrentItemWithPlayerItem:nil]; 
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
        if (_currentItem.status == AVPlayerItemStatusFailed) { 
            [self fireState:@"error"]; 
            [self fireError:_currentItem.error.localizedDescription];
            BOOL isTerminal = NO;
            if ([_currentItem.error.domain isEqualToString:NSURLErrorDomain]) {
                if (_currentItem.error.code == NSURLErrorFileDoesNotExist || _currentItem.error.code == NSURLErrorNoPermissionsToReadFile) isTerminal = YES;
            }
            if (isTerminal) { _isReconnecting = NO; [_player pause]; [self updateNowPlaying]; } else { [self attemptReconnect]; }
        }
    }
}

- (void)handleInterruption:(NSNotification *)n { 
    if ([n.userInfo[AVAudioSessionInterruptionTypeKey] intValue] == AVAudioSessionInterruptionTypeBegan) [self pause:nil]; 
}

- (void)attemptReconnect {
    if (_isReconnecting || _retryCount >= 5) return;
    _retryCount++; _isReconnecting = YES;
    NSString *urlToRetry = [_currentURL copy];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_isReconnecting && [self->_currentURL isEqualToString:urlToRetry]) {
            self->_isReconnecting = NO;
            [self setStream:@{@"url":self->_currentURL, @"isLive":@(self->_isLive)}];
            [self start:nil];
        }
    });
}

- (void)fireState:(NSString *)state { if ([self _hasListeners:@"state"]) [self fireEvent:@"state" withObject:@{@"state":state}]; }
- (void)fireError:(NSString *)msg { if ([self _hasListeners:@"error"]) [self fireEvent:@"error" withObject:@{@"message":msg}]; }
- (void)fireRemoteControl:(NSInteger)subtype { if ([self _hasListeners:@"remotecontrol"]) [self fireEvent:@"remotecontrol" withObject:@{@"subtype": @(subtype)}]; }

@end
