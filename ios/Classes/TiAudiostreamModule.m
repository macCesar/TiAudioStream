/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiAudiostreamModule.h"
#import "AudioPlayerManager.h"
#import "TiBase.h"
#import "TiHost.h"
#import "TiUtils.h"

@interface TiAudiostreamModule () <AudioPlayerManagerDelegate>
@end

@implementation TiAudiostreamModule

#pragma mark - Internal

- (id)moduleGUID
{
    return @"04e2decf-6370-43f1-bf1d-457c4b417325";
}

- (NSString *)moduleId
{
    return @"ti.audiostream";
}

#pragma mark - Lifecycle

- (void)startup
{
    [super startup];
    [AudioPlayerManager sharedInstance].delegate = self;
    DebugLog(@"[ti.audiostream] Module loaded");
}

- (void)shutdown:(id)sender
{
    [[AudioPlayerManager sharedInstance] cleanup];
    [super shutdown:sender];
}

#pragma mark - Constants

MAKE_SYSTEM_PROP(REMOTE_CONTROL_PLAY, 100);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_PAUSE, 101);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_STOP, 102);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_PLAY_PAUSE, 103);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_NEXT, 104);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_PREV, 105);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_START_SEEK_BACK, 106);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_END_SEEK_BACK, 107);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_START_SEEK_FORWARD, 108);
MAKE_SYSTEM_PROP(REMOTE_CONTROL_END_SEEK_FORWARD, 109);

MAKE_SYSTEM_PROP(AUDIOFOCUS_GAIN, 1);
MAKE_SYSTEM_PROP(AUDIOFOCUS_LOSS, -1);
MAKE_SYSTEM_PROP(AUDIOFOCUS_LOSS_TRANSIENT, -2);
MAKE_SYSTEM_PROP(AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK, -3);

#pragma mark - Properties

- (NSNumber *)playing
{
    return @([AudioPlayerManager sharedInstance].isPlaying);
}

#pragma mark - Public API Methods

- (void)setStream:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    NSString *url = [TiUtils stringValue:@"url" properties:args];
    BOOL isLive = [TiUtils boolValue:@"isLive" properties:args def:YES];
    
    [[AudioPlayerManager sharedInstance] setStreamWithURL:url isLive:isLive];
}

- (void)play:(id)unused
{
    [[AudioPlayerManager sharedInstance] play];
}

- (void)start:(id)unused
{
    // Compatibility with start()
    [[AudioPlayerManager sharedInstance] play];
}

- (void)pause:(id)unused
{
    [[AudioPlayerManager sharedInstance] pause];
}

- (void)stop:(id)unused
{
    [[AudioPlayerManager sharedInstance] stop];
}

- (void)setMetadata:(id)args
{
    ENSURE_SINGLE_ARG(args, NSDictionary);
    NSString *title = [TiUtils stringValue:@"title" properties:args def:@""];
    NSString *artist = [TiUtils stringValue:@"artist" properties:args def:@""];
    NSString *artwork = [TiUtils stringValue:@"artwork" properties:args def:nil];
    
    [[AudioPlayerManager sharedInstance] setMetadataWithTitle:title
                                                       artist:artist
                                                      artwork:artwork];
}

#pragma mark - AudioPlayerManagerDelegate

- (void)audioPlayerStateChanged:(NSString *)state
{
    if ([self _hasListeners:@"state"]) {
        [self fireEvent:@"state" withObject:@{@"state": state}];
    }
}

- (void)audioPlayerError:(NSString *)message
{
    if ([self _hasListeners:@"error"]) {
        [self fireEvent:@"error" withObject:@{@"message": message}];
    }
}

- (void)audioPlayerRemoteControl:(NSInteger)command
{
    if ([self _hasListeners:@"remotecontrol"]) {
        [self fireEvent:@"remotecontrol" withObject:@{@"subtype": @(command)}];
    }
}

@end
