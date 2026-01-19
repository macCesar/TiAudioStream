/**
 * ti.audiostream - Audio streaming module for Titanium
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import <Foundation/Foundation.h>

// Forward declarations
@class UIImage;

NS_ASSUME_NONNULL_BEGIN

// State constants protected for C++ contexts
typedef NS_ENUM(NSInteger, AudioPlayerState) {
    AudioPlayerStateIdle,
    AudioPlayerStateBuffering,
    AudioPlayerStatePlaying,
    AudioPlayerStatePaused,
    AudioPlayerStateStopped,
    AudioPlayerStateError
};

// Delegate protocol
@protocol AudioPlayerManagerDelegate <NSObject>
- (void)audioPlayerStateChanged:(NSString *)state;
- (void)audioPlayerError:(NSString *)message;
- (void)audioPlayerRemoteControl:(NSInteger)command;
@end

@interface AudioPlayerManager : NSObject

@property (nonatomic, weak, nullable) id<AudioPlayerManagerDelegate> delegate;
@property (nonatomic, readonly) BOOL isPlaying;
@property (nonatomic, readonly) AudioPlayerState currentState;

// Singleton
+ (instancetype)sharedInstance;

// Playback control
- (void)setStreamWithURL:(NSString *)url isLive:(BOOL)isLive;
- (void)play;
- (void)pause;
- (void)stop;

// Metadata
- (void)setMetadataWithTitle:(NSString *)title
                      artist:(NSString *)artist
                     artwork:(nullable NSString *)artworkURL;

// Cleanup
- (void)cleanup;

@end

NS_ASSUME_NONNULL_END
