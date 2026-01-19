/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiModule.h"
#import <Foundation/Foundation.h>

@class UIImage;

NS_ASSUME_NONNULL_BEGIN

// Definición de estados
typedef NS_ENUM(NSInteger, AudioPlayerState) {
    AudioPlayerStateIdle,
    AudioPlayerStateBuffering,
    AudioPlayerStatePlaying,
    AudioPlayerStatePaused,
    AudioPlayerStateStopped,
    AudioPlayerStateError
};

// Protocolo del Delegate
@protocol AudioPlayerManagerDelegate <NSObject>
- (void)audioPlayerStateChanged:(NSString *)state;
- (void)audioPlayerError:(NSString *)message;
- (void)audioPlayerRemoteControl:(NSInteger)command;
@end

// Interfaz del Manager
@interface AudioPlayerManager : NSObject
@property (nonatomic, weak, nullable) id<AudioPlayerManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) AudioPlayerState currentState;
+ (instancetype)sharedInstance;
- (void)setStreamWithURL:(NSString *)url isLive:(BOOL)isLive;
- (void)play;
- (void)pause;
- (void)stop;
- (void)setMetadataWithTitle:(NSString *)title artist:(NSString *)artist artwork:(nullable NSString *)artworkURL;
- (void)cleanup;
@end

// Interfaz del Módulo
@interface TiAudiostreamModule : TiModule <AudioPlayerManagerDelegate>
@end

NS_ASSUME_NONNULL_END