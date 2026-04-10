/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiModule.h"

@interface TiAudiostreamModule : TiModule

// Public API
- (void)setStream:(id)args;
- (void)start:(id)unused;
- (void)pause:(id)unused;
- (void)stop:(id)unused;
- (void)setMetadata:(id)args;
- (void)setMetadataRules:(id)args;
- (void)setAutomotiveStations:(id)args;
- (void)setCurrentAutomotiveStation:(id)args;

// Properties
@property (nonatomic, readonly) NSNumber *playing;

// Constants
@property (nonatomic, readonly) NSNumber *REMOTE_CONTROL_PLAY;
@property (nonatomic, readonly) NSNumber *REMOTE_CONTROL_PAUSE;
@property (nonatomic, readonly) NSNumber *REMOTE_CONTROL_STOP;
@property (nonatomic, readonly) NSNumber *REMOTE_CONTROL_PLAY_PAUSE;
@property (nonatomic, readonly) NSNumber *REMOTE_CONTROL_NEXT;
@property (nonatomic, readonly) NSNumber *REMOTE_CONTROL_PREV;

@end
