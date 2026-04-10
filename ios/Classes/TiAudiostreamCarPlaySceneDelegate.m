/**
 * ti.audiostream - CarPlay Audio Scene Delegate
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiAudiostreamCarPlaySceneDelegate.h"
#import "TiAudiostreamModule.h"
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>

static NSString *const TiAudiostreamCarPlayDidConnectNotification = @"TiAudiostreamCarPlayDidConnectNotification";
static NSString *const TiAudiostreamCarPlayDidPresentNowPlayingNotification = @"TiAudiostreamCarPlayDidPresentNowPlayingNotification";
static NSString *const TiAudiostreamAutomotiveStationSelectedNotification = @"TiAudiostreamAutomotiveStationSelectedNotification";
static NSString *const TiAudiostreamAutomotiveStationsDidChangeNotification = @"TiAudiostreamAutomotiveStationsDidChangeNotification";

@interface TiAudiostreamModule (AutomotiveInternal)
+ (NSArray<NSDictionary *> *)persistedAutomotiveStations;
+ (NSDictionary *)persistedCurrentAutomotiveStation;
+ (TiAudiostreamModule *)activeModule;
- (BOOL)carPlayNowPlayingReady;
@end

@implementation TiAudiostreamCarPlaySceneDelegate {
  CPInterfaceController *_interfaceController;
  CPListTemplate *_rootTemplate;
  NSUInteger _pendingNowPlayingRequestID;
}

- (BOOL)isPlaybackActive
{
  TiAudiostreamModule *module = [TiAudiostreamModule activeModule];
  return module != nil && [module.playing boolValue];
}

- (BOOL)isNowPlayingReady
{
  TiAudiostreamModule *module = [TiAudiostreamModule activeModule];
  return module != nil && [module carPlayNowPlayingReady];
}

- (NSString *)hostApplicationName
{
  NSBundle *bundle = [NSBundle mainBundle];
  NSString *displayName = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
  if (displayName.length > 0) {
    return displayName;
  }

  NSString *bundleName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
  if (bundleName.length > 0) {
    return bundleName;
  }

  return @"Audio";
}

- (CPListTemplate *)buildRootTemplate API_AVAILABLE(ios(14.0))
{
  CPListTemplate *listTemplate = [[CPListTemplate alloc] initWithTitle:[self hostApplicationName]
                                                              sections:[self buildRootSections]];
  listTemplate.emptyViewTitleVariants = @[ @"No playback options" ];
  listTemplate.emptyViewSubtitleVariants = @[ @"Open the app on iPhone to refresh playback." ];
  return listTemplate;
}

- (NSArray<CPListSection *> *)buildRootSections API_AVAILABLE(ios(14.0))
{
  __weak TiAudiostreamCarPlaySceneDelegate *weakSelf = self;
  NSMutableArray<CPListItem *> *items = [NSMutableArray array];
  NSDictionary *currentStation = [TiAudiostreamModule persistedCurrentAutomotiveStation];
  NSArray<NSDictionary *> *stations = [TiAudiostreamModule persistedAutomotiveStations];

  if ([currentStation isKindOfClass:[NSDictionary class]]) {
    NSString *currentTitle = [currentStation objectForKey:@"title"] ?: [currentStation objectForKey:@"stationName"] ?: @"Last station";
    NSString *currentSubtitle = [currentStation objectForKey:@"subtitle"] ?: [currentStation objectForKey:@"stationName"] ?: @"";
    CPListItem *currentItem = [[CPListItem alloc] initWithText:currentTitle detailText:currentSubtitle];
    currentItem.handler = ^(id<CPSelectableListItem> item, dispatch_block_t completionBlock) {
      [weakSelf handleStationSelection:currentStation reason:@"current-selection"];
      if (completionBlock) {
        completionBlock();
      }
    };
    [items addObject:currentItem];
  }

  for (NSDictionary *station in stations) {
    if (![station isKindOfClass:[NSDictionary class]]) {
      continue;
    }

    NSString *title = [station objectForKey:@"title"] ?: [station objectForKey:@"programName"] ?: [station objectForKey:@"stationName"] ?: @"Station";
    NSString *subtitle = [station objectForKey:@"subtitle"] ?: [station objectForKey:@"stationName"] ?: [station objectForKey:@"artist"] ?: @"";
    CPListItem *stationItem = [[CPListItem alloc] initWithText:title detailText:subtitle];
    stationItem.handler = ^(id<CPSelectableListItem> item, dispatch_block_t completionBlock) {
      [weakSelf handleStationSelection:station reason:@"station-selection"];
      if (completionBlock) {
        completionBlock();
      }
    };
    [items addObject:stationItem];
  }

  return @[ [[CPListSection alloc] initWithItems:items] ];
}

- (void)handleStationSelection:(NSDictionary *)station reason:(NSString *)reason API_AVAILABLE(ios(14.0))
{
  TiAudiostreamModule *module = [TiAudiostreamModule activeModule];
  if (module) {
    [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamAutomotiveStationSelectedNotification
                                                        object:station];
  } else {
    NSLog(@"[ti.audiostream] No active module available for station selection (%@)", reason);
  }
}

- (void)presentNowPlayingTemplateAnimated:(BOOL)animated reason:(NSString *)reason API_AVAILABLE(ios(14.0))
{
  if (!_interfaceController) {
    NSLog(@"[ti.audiostream] Skipping Now Playing push (%@): interface controller missing", reason);
    return;
  }

  CPTemplate *topTemplate = _interfaceController.topTemplate;
  if ([topTemplate isKindOfClass:[CPNowPlayingTemplate class]]) {
    NSLog(@"[ti.audiostream] Now Playing already visible (%@)", reason);
    return;
  }

  CPNowPlayingTemplate *nowPlaying = [CPNowPlayingTemplate sharedTemplate];
  nowPlaying.upNextButtonEnabled = NO;
  nowPlaying.albumArtistButtonEnabled = NO;

  [_interfaceController pushTemplate:nowPlaying
                            animated:animated
                          completion:^(BOOL success, NSError *error) {
                            if (success) {
                              NSLog(@"[ti.audiostream] CarPlay pushed Now Playing template (%@)", reason);
                              [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamCarPlayDidPresentNowPlayingNotification
                                                                                  object:nil];
                            } else {
                              NSLog(@"[ti.audiostream] Failed to push Now Playing template (%@): %@", reason, error.localizedDescription ?: error);
                            }
                          }];
}

- (void)presentNowPlayingWhenPlaybackIsReadyAnimated:(BOOL)animated
                                              reason:(NSString *)reason
                                             attempt:(NSUInteger)attempt
                                           requestID:(NSUInteger)requestID API_AVAILABLE(ios(14.0))
{
  if (requestID != _pendingNowPlayingRequestID) {
    return;
  }

  if ([self isNowPlayingReady]) {
    [self presentNowPlayingTemplateAnimated:animated reason:reason];
    return;
  }

  if (attempt >= 24) {
    NSLog(@"[ti.audiostream] Skipping delayed Now Playing push (%@): playback never became ready", reason);
    return;
  }

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self presentNowPlayingWhenPlaybackIsReadyAnimated:animated
                                               reason:reason
                                              attempt:attempt + 1
                                            requestID:requestID];
  });
}

#pragma mark - UISceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
  NSLog(@"[ti.audiostream] CarPlay scene willConnect");
}

- (void)sceneDidDisconnect:(UIScene *)scene
{
  NSLog(@"[ti.audiostream] CarPlay scene didDisconnect");
  [[NSNotificationCenter defaultCenter] removeObserver:self name:TiAudiostreamAutomotiveStationsDidChangeNotification object:nil];
}

#pragma mark - CPTemplateApplicationSceneDelegate

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
    didConnectInterfaceController:(CPInterfaceController *)interfaceController
{
  _interfaceController = interfaceController;
  NSLog(@"[ti.audiostream] CarPlay didConnectInterfaceController scenes=%lu", (unsigned long)[UIApplication sharedApplication].connectedScenes.count);
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(handleAutomotiveStationsDidChange:)
                                               name:TiAudiostreamAutomotiveStationsDidChangeNotification
                                             object:nil];

  if (@available(iOS 14.0, *)) {
    __weak TiAudiostreamCarPlaySceneDelegate *weakSelf = self;
    _rootTemplate = [self buildRootTemplate];
    [_interfaceController setRootTemplate:_rootTemplate
                                 animated:NO
                               completion:^(BOOL success, NSError *error) {
                                 if (success) {
                                   TiAudiostreamCarPlaySceneDelegate *strongSelf = weakSelf;
                                   if (!strongSelf) {
                                     return;
                                   }
                                   NSLog(@"[ti.audiostream] CarPlay root template set");

                                   // Notify the module so it can reassert the Now Playing session
                                   [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamCarPlayDidConnectNotification object:nil];

                                   // Auto-push Now Playing if audio is already playing
                                   if ([strongSelf isPlaybackActive]) {
                                     strongSelf->_pendingNowPlayingRequestID++;
                                     NSUInteger requestID = strongSelf->_pendingNowPlayingRequestID;
                                     dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                       [weakSelf presentNowPlayingWhenPlaybackIsReadyAnimated:YES
                                                                                       reason:@"scene-connect-auto"
                                                                                      attempt:0
                                                                                    requestID:requestID];
                                     });
                                   }
                                 } else {
                                   NSLog(@"[ti.audiostream] Failed to set CarPlay root template: %@", error.localizedDescription ?: error);
                                 }
                               }];
  }

  NSLog(@"[ti.audiostream] CarPlay connected");
}

- (void)handleAutomotiveStationsDidChange:(NSNotification *)notification API_AVAILABLE(ios(14.0))
{
  if (!_interfaceController) {
    return;
  }

  if (_rootTemplate) {
    [_rootTemplate updateSections:[self buildRootSections]];
    return;
  }

  _rootTemplate = [self buildRootTemplate];
  [_interfaceController setRootTemplate:_rootTemplate
                               animated:NO
                             completion:^(BOOL success, NSError *error) {
                               if (!success) {
                                 NSLog(@"[ti.audiostream] Failed to refresh CarPlay root template: %@", error.localizedDescription ?: error);
                                 return;
                               }
                             }];
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
    didConnectInterfaceController:(CPInterfaceController *)interfaceController
                        toWindow:(CPWindow *)window
{
  NSLog(@"[ti.audiostream] CarPlay connected to window");
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
    didDisconnectInterfaceController:(CPInterfaceController *)interfaceController
{
  _interfaceController = nil;
  NSLog(@"[ti.audiostream] CarPlay disconnected");
}

- (void)templateApplicationScene:(CPTemplateApplicationScene *)templateApplicationScene
    didDisconnectInterfaceController:(CPInterfaceController *)interfaceController
                         fromWindow:(CPWindow *)window
{
  NSLog(@"[ti.audiostream] CarPlay disconnected from window");
}

@end
