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
#import <CoreMedia/CoreMedia.h>

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
    
    // Setup Audio Session
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeDefault options:0 error:nil];
    [session setActive:YES error:nil];
    
    // Setup Remote Commands
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    [cc.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self play:nil]; return MPRemoteCommandHandlerStatusSuccess; }];
    [cc.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self pause:nil]; return MPRemoteCommandHandlerStatusSuccess; }];
    [cc.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *e) { [self stop:nil]; return MPRemoteCommandHandlerStatusSuccess; }];
    
    // Notifications
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleRouteChange:) name:AVAudioSessionRouteChangeNotification object:nil];
}

#pragma mark - JS API

- (void)setStream:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    _currentURL = [TiUtils stringValue:@"url" properties:args];
    _isLive = [TiUtils boolValue:@"isLive" properties:args def:YES];
    
    if (_currentItem) {
        @try {
            [_currentItem removeObserver:self forKeyPath:@"status"];
            [_currentItem removeObserver:self forKeyPath:@"playbackBufferEmpty"];
            [_currentItem removeObserver:self forKeyPath:@"playbackLikelyToKeepUp"];
        } @catch (id e) {}
    }
    
    _currentItem = [AVPlayerItem playerItemWithURL:[NSURL URLWithString:_currentURL]];
    [_currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [_currentItem addObserver:self forKeyPath:@"playbackBufferEmpty" options:NSKeyValueObservingOptionNew context:nil];
    [_currentItem addObserver:self forKeyPath:@"playbackLikelyToKeepUp" options:NSKeyValueObservingOptionNew context:nil];
    
    if (_player) {
        [_player replaceCurrentItemWithPlayerItem:_currentItem];
    } else {
        _player = [AVPlayer playerWithPlayerItem:_currentItem];
        _player.automaticallyWaitsToMinimizeStalling = YES;
    }
}

- (void)play:(id)unused { if (_player) { [[AVAudioSession sharedInstance] setActive:YES error:nil]; [_player play]; [self fireState:@"playing"]; [self updateNowPlaying]; } }
- (void)start:(id)unused { [self play:nil]; }
- (void)pause:(id)unused { if (_player) { [_player pause]; [self fireState:@"paused"]; [self updateNowPlaying]; } }
- (void)stop:(id)unused { 
    if (_player) { [_player pause]; _player = nil; _currentItem = nil; }
    [self fireState:@"stopped"];
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

- (void)setMetadata:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    _currentTitle = [TiUtils stringValue:@"title" properties:args def:@""];
    _currentArtist = [TiUtils stringValue:@"artist" properties:args def:@""];
    NSString *artworkURL = [TiUtils stringValue:@"artwork" properties:args];
    [self updateNowPlaying];
    
    if (artworkURL) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:artworkURL]];
            UIImage *img = [UIImage imageWithData:data];
            if (img) { dispatch_async(dispatch_get_main_queue(), ^{ self->_currentArtwork = img; [self updateNowPlaying]; }); }
        });
    }
}

#pragma mark - Internal

- (void)updateNowPlaying
{
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
    if (object == _currentItem) {
        if ([keyPath isEqualToString:@"status"]) {
            if (_currentItem.status == AVPlayerItemStatusReadyToPlay) { _retryCount = 0; if (_player.rate > 0) [self fireState:@"playing"]; }
            else if (_currentItem.status == AVPlayerItemStatusFailed) { [self fireState:@"error"]; [self attemptReconnect]; }
        }
        if ([keyPath isEqualToString:@"playbackBufferEmpty"] && _currentItem.playbackBufferEmpty) [self fireState:@"buffering"];
        if ([keyPath isEqualToString:@"playbackLikelyToKeepUp"] && _currentItem.playbackLikelyToKeepUp && _player.rate > 0) [self fireState:@"playing"];
    }
}

- (void)handleInterruption:(NSNotification *)n { if ([n.userInfo[AVAudioSessionInterruptionTypeKey] intValue] == AVAudioSessionInterruptionTypeBegan) [self pause:nil]; }
- (void)handleRouteChange:(NSNotification *)n { if ([n.userInfo[AVAudioSessionRouteChangeReasonKey] intValue] == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) [self pause:nil]; }

- (void)attemptReconnect {
    if (_isReconnecting || _retryCount >= 5) return;
    _retryCount++; _isReconnecting = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self->_isReconnecting = NO; if (self->_currentURL) { [self setStream:@{@"url":self->_currentURL}]; [self play:nil]; }
    });
}

- (void)fireState:(NSString *)state { if ([self _hasListeners:@"state"]) [self fireEvent:@"state" withObject:@{@"state":state}]; }

@end
