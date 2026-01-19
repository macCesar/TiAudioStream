/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "AudioPlayerManager.h"
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

static NSString *const kStatusKeyPath = @"status";
static NSString *const kPlaybackBufferEmpty = @"playbackBufferEmpty";
static NSString *const kPlaybackLikelyToKeepUp = @"playbackLikelyToKeepUp";

// Remote control constants (must match Android)
static const NSInteger REMOTE_CONTROL_PLAY = 100;
static const NSInteger REMOTE_CONTROL_PAUSE = 101;
static const NSInteger REMOTE_CONTROL_STOP = 102;
static const NSInteger REMOTE_CONTROL_PLAY_PAUSE = 103;
static const NSInteger REMOTE_CONTROL_NEXT = 104;
static const NSInteger REMOTE_CONTROL_PREV = 105;

@interface AudioPlayerManager ()

@property (nonatomic, strong, nullable) AVPlayer *player;
@property (nonatomic, strong, nullable) AVPlayerItem *currentItem;
@property (nonatomic, strong, nullable) NSString *currentURL;
@property (nonatomic, assign) BOOL isLive;
@property (nonatomic, assign) AudioPlayerState currentState;

// Metadata
@property (nonatomic, strong) NSString *currentTitle;
@property (nonatomic, strong) NSString *currentArtist;
@property (nonatomic, strong, nullable) UIImage *currentArtwork;

// Reconnection
@property (nonatomic, assign) NSInteger retryCount;
@property (nonatomic, assign) BOOL isReconnecting;

@end

@implementation AudioPlayerManager

static const NSInteger MAX_RETRIES = 5;
static const NSTimeInterval RETRY_DELAY = 3.0;

#pragma mark - Singleton

+ (instancetype)sharedInstance
{
    static AudioPlayerManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AudioPlayerManager alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    if (self = [super init]) {
        _currentState = AudioPlayerStateIdle;
        _retryCount = 0;
        _isReconnecting = NO;
        _currentTitle = @"";
        _currentArtist = @"";

        [self setupAudioSession];
        [self setupRemoteCommandCenter];
        [self setupNotifications];
    }
    return self;
}

#pragma mark - Audio Session Setup

- (void)setupAudioSession
{
    NSError *error = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];

    [session setCategory:AVAudioSessionCategoryPlayback
                    mode:AVAudioSessionModeDefault
                 options:0
                   error:&error];

    if (error) {
        NSLog(@"[AudioPlayerManager] Error setting audio session category: %@", error.localizedDescription);
        return;
    }

    [session setActive:YES error:&error];
}

#pragma mark - Remote Command Center

- (void)setupRemoteCommandCenter
{
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];

    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self play];
        [self notifyRemoteControl:REMOTE_CONTROL_PLAY];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self pause];
        [self notifyRemoteControl:REMOTE_CONTROL_PAUSE];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.togglePlayPauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        if (self.isPlaying) {
            [self pause];
        } else {
            [self play];
        }
        [self notifyRemoteControl:REMOTE_CONTROL_PLAY_PAUSE];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.stopCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self stop];
        [self notifyRemoteControl:REMOTE_CONTROL_STOP];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self notifyRemoteControl:REMOTE_CONTROL_NEXT];
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        [self notifyRemoteControl:REMOTE_CONTROL_PREV];
        return MPRemoteCommandHandlerStatusSuccess;
    }];
}

#pragma mark - Notifications

- (void)setupNotifications
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleRouteChange:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidFinish:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemFailed:)
                                                 name:AVPlayerItemFailedToPlayToEndTimeNotification
                                               object:nil];
}

#pragma mark - Playback Control

- (void)setStreamWithURL:(NSString *)url isLive:(BOOL)isLive
{
    if (!url || url.length == 0) return;

    self.currentURL = url;
    self.isLive = isLive;
    self.retryCount = 0;

    [self removeItemObservers];

    NSURL *streamURL = [NSURL URLWithString:url];
    self.currentItem = [AVPlayerItem playerItemWithURL:streamURL];

    [self addItemObservers];

    if (self.player) {
        [self.player replaceCurrentItemWithPlayerItem:self.currentItem];
    } else {
        self.player = [AVPlayer playerWithPlayerItem:self.currentItem];
        self.player.automaticallyWaitsToMinimizeStalling = YES;
    }
}

- (void)play
{
    if (!self.player) return;
    [[AVAudioSession sharedInstance] setActive:YES error:nil];
    [self.player play];
    [self updateState:AudioPlayerStatePlaying];
    [self updateNowPlayingInfo];
}

- (void)pause
{
    if (!self.player) return;
    [self.player pause];
    [self updateState:AudioPlayerStatePaused];
    [self updateNowPlayingInfo];
}

- (void)stop
{
    if (self.player) {
        [self.player pause];
        [self removeItemObservers];
        self.currentItem = nil;
        self.player = nil;
    }

    [self updateState:AudioPlayerStateStopped];
    [self clearNowPlayingInfo];
    [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}

#pragma mark - Metadata

- (void)setMetadataWithTitle:(NSString *)title
                      artist:(NSString *)artist
                     artwork:(NSString *)artworkURL
{
    self.currentTitle = title ?: @"";
    self.currentArtist = artist ?: @"";
    [self updateNowPlayingInfo];

    if (artworkURL && artworkURL.length > 0) {
        [self loadArtworkAsync:artworkURL];
    }
}

- (void)loadArtworkAsync:(NSString *)artworkPath
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        UIImage *image = nil;
        BOOL isRemoteURL = [artworkPath hasPrefix:@"http://"] || [artworkPath hasPrefix:@"https://"];

        if (isRemoteURL) {
            NSURL *url = [NSURL URLWithString:artworkPath];
            NSData *data = [NSData dataWithContentsOfURL:url];
            if (data) image = [UIImage imageWithData:data];
        } else {
            NSString *resourcePath = [[NSBundle mainBundle] pathForResource:artworkPath ofType:nil];
            if (resourcePath) image = [UIImage imageWithContentsOfFile:resourcePath];
            if (!image) image = [UIImage imageNamed:artworkPath];
        }

        if (image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.currentArtwork = image;
                [self updateNowPlayingInfo];
            });
        }
    });
}

#pragma mark - Now Playing Info

- (void)updateNowPlayingInfo
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = self.currentTitle;
    info[MPMediaItemPropertyArtist] = self.currentArtist;
    if (self.isLive) info[MPNowPlayingInfoPropertyIsLiveStream] = @YES;
    info[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? @1.0 : @0.0;

    if (self.currentArtwork) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc]
            initWithBoundsSize:self.currentArtwork.size
            requestHandler:^UIImage * _Nonnull(CGSize size) {
                return self.currentArtwork;
            }];
        info[MPMediaItemPropertyArtwork] = artwork;
    }

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
}

- (void)clearNowPlayingInfo
{
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nil;
}

#pragma mark - KVO Observers

- (void)addItemObservers
{
    if (!self.currentItem) return;
    [self.currentItem addObserver:self forKeyPath:kStatusKeyPath options:NSKeyValueObservingOptionNew context:nil];
    [self.currentItem addObserver:self forKeyPath:kPlaybackBufferEmpty options:NSKeyValueObservingOptionNew context:nil];
    [self.currentItem addObserver:self forKeyPath:kPlaybackLikelyToKeepUp options:NSKeyValueObservingOptionNew context:nil];
}

- (void)removeItemObservers
{
    if (!self.currentItem) return;
    @try {
        [self.currentItem removeObserver:self forKeyPath:kStatusKeyPath];
        [self.currentItem removeObserver:self forKeyPath:kPlaybackBufferEmpty];
        [self.currentItem removeObserver:self forKeyPath:kPlaybackLikelyToKeepUp];
    } @catch (NSException *e) {}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (![object isKindOfClass:[AVPlayerItem class]]) return;
    AVPlayerItem *item = (AVPlayerItem *)object;

    if ([keyPath isEqualToString:kStatusKeyPath]) {
        if (item.status == AVPlayerItemStatusReadyToPlay) {
            self.retryCount = 0;
            if (self.player.rate > 0) [self updateState:AudioPlayerStatePlaying];
        } else if (item.status == AVPlayerItemStatusFailed) {
            [self updateState:AudioPlayerStateError];
            [self notifyError:item.error.localizedDescription ?: @"Playback failed"];
            [self attemptReconnect];
        }
    }

    if ([keyPath isEqualToString:kPlaybackBufferEmpty] && item.playbackBufferEmpty) {
        [self updateState:AudioPlayerStateBuffering];
    }

    if ([keyPath isEqualToString:kPlaybackLikelyToKeepUp] && item.playbackLikelyToKeepUp && self.player.rate > 0) {
        [self updateState:AudioPlayerStatePlaying];
    }
}

#pragma mark - Interruption Handling

- (void)handleInterruption:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    AVAudioSessionInterruptionType type = [info[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    if (type == AVAudioSessionInterruptionTypeBegan) {
        [self pause];
    } else if (type == AVAudioSessionInterruptionTypeEnded) {
        AVAudioSessionInterruptionOptions options = [info[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        if (options & AVAudioSessionInterruptionOptionShouldResume) [self play];
    }
}

- (void)handleRouteChange:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    AVAudioSessionRouteChangeReason reason = [info[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    if (reason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) [self pause];
}

#pragma mark - Player Item Notifications

- (void)playerItemDidFinish:(NSNotification *)notification
{
    [self updateState:AudioPlayerStateStopped];
}

- (void)playerItemFailed:(NSNotification *)notification
{
    [self updateState:AudioPlayerStateError];
    [self notifyError:@"Stream playback failed"];
    [self attemptReconnect];
}

#pragma mark - Reconnection

- (void)attemptReconnect
{
    if (self.isReconnecting || self.retryCount >= MAX_RETRIES) {
        if (self.retryCount >= MAX_RETRIES) [self stop];
        return;
    }

    self.retryCount++;
    self.isReconnecting = YES;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RETRY_DELAY * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isReconnecting = NO;
        if (self.currentURL) {
            [self setStreamWithURL:self.currentURL isLive:self.isLive];
            [self play];
        }
    });
}

#pragma mark - State Management

- (void)updateState:(AudioPlayerState)newState
{
    if (self.currentState == newState) return;
    self.currentState = newState;
    NSString *stateString;
    switch (newState) {
        case AudioPlayerStateBuffering: stateString = @"buffering"; break;
        case AudioPlayerStatePlaying: stateString = @"playing"; break;
        case AudioPlayerStatePaused: stateString = @"paused"; break;
        case AudioPlayerStateStopped: stateString = @"stopped"; break;
        case AudioPlayerStateError: stateString = @"error"; break;
        default: stateString = @"idle"; break;
    }
    [self notifyStateChange:stateString];
}

- (BOOL)isPlaying
{
    return self.player && self.player.rate > 0;
}

#pragma mark - Delegate Notifications

- (void)notifyStateChange:(NSString *)state
{
    if ([self.delegate respondsToSelector:@selector(audioPlayerStateChanged:)]) {
        [self.delegate audioPlayerStateChanged:state];
    }
}

- (void)notifyError:(NSString *)message
{
    if ([self.delegate respondsToSelector:@selector(audioPlayerError:)]) {
        [self.delegate audioPlayerError:message];
    }
}

- (void)notifyRemoteControl:(NSInteger)command
{
    if ([self.delegate respondsToSelector:@selector(audioPlayerRemoteControl:)]) {
        [self.delegate audioPlayerRemoteControl:command];
    }
}

#pragma mark - Cleanup

- (void)cleanup
{
    [self stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)dealloc
{
    [self cleanup];
}

@end