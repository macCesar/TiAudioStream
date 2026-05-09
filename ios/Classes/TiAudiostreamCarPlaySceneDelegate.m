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
- (NSString *)carPlayCurrentStreamURL;
- (void)refreshCarPlayNowPlayingItemForReason:(NSString *)reason;
@end

typedef void (^TiAudiostreamCarPlayCompletion)(void);

@implementation TiAudiostreamCarPlaySceneDelegate {
  CPInterfaceController *_interfaceController;
  CPListTemplate *_rootTemplate;
  NSUInteger _pendingNowPlayingRequestID;
  NSMutableArray<CPListItem *> *_stationItems;
  NSArray<NSString *> *_stationItemIdentifiers;
}

- (NSString *)stationIdentifier:(NSDictionary *)station
{
  if (![station isKindOfClass:[NSDictionary class]]) {
    return @"";
  }

  NSString *streamURL = [station objectForKey:@"streamUrl"] ?: [station objectForKey:@"url"];
  if (streamURL.length > 0) {
    return [@"url:" stringByAppendingString:streamURL];
  }

  NSString *title = [station objectForKey:@"stationName"] ?: [station objectForKey:@"title"] ?: @"";
  NSString *subtitle = [station objectForKey:@"subtitle"] ?: [station objectForKey:@"artist"] ?: @"";
  return [NSString stringWithFormat:@"meta:%@|%@", title, subtitle];
}

- (NSArray<NSString *> *)stationIdentifiersFromStations:(NSArray<NSDictionary *> *)stations
{
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
  for (NSDictionary *station in stations) {
    if (![station isKindOfClass:[NSDictionary class]]) {
      continue;
    }
    [identifiers addObject:[self stationIdentifier:station]];
  }
  return identifiers;
}

- (NSString *)displaySubtitleForStation:(NSDictionary *)station currentStation:(NSDictionary *)currentStation
{
  NSString *subtitle = [station objectForKey:@"subtitle"] ?: [station objectForKey:@"stationName"] ?: [station objectForKey:@"artist"] ?: @"";
  if ([self station:station matchesCurrentStation:currentStation]) {
    if (subtitle.length > 0) {
      return [NSString stringWithFormat:@"On Air • %@", subtitle];
    }
    return @"On Air";
  }
  return subtitle;
}

- (BOOL)station:(NSDictionary *)station matchesCurrentStation:(NSDictionary *)currentStation
{
  if (![station isKindOfClass:[NSDictionary class]] || ![currentStation isKindOfClass:[NSDictionary class]]) {
    return NO;
  }

  NSString *stationStreamURL = [station objectForKey:@"streamUrl"] ?: [station objectForKey:@"url"];
  NSString *currentStreamURL = [currentStation objectForKey:@"streamUrl"] ?: [currentStation objectForKey:@"url"];
  if (stationStreamURL.length > 0 && currentStreamURL.length > 0 && [stationStreamURL isEqualToString:currentStreamURL]) {
    return YES;
  }

  NSString *moduleStreamURL = [[TiAudiostreamModule activeModule] carPlayCurrentStreamURL];
  if (stationStreamURL.length > 0 && moduleStreamURL.length > 0 && [stationStreamURL isEqualToString:moduleStreamURL]) {
    return YES;
  }

  NSString *stationTitle = [station objectForKey:@"stationName"] ?: [station objectForKey:@"title"];
  NSString *currentTitle = [currentStation objectForKey:@"stationName"] ?: [currentStation objectForKey:@"title"];
  NSString *stationSubtitle = [station objectForKey:@"subtitle"] ?: [station objectForKey:@"artist"];
  NSString *currentSubtitle = [currentStation objectForKey:@"subtitle"] ?: [currentStation objectForKey:@"artist"];

  return stationTitle.length > 0 &&
         currentTitle.length > 0 &&
         [stationTitle isEqualToString:currentTitle] &&
         ((stationSubtitle.length == 0 && currentSubtitle.length == 0) ||
          [stationSubtitle isEqualToString:currentSubtitle]);
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
  listTemplate.leadingNavigationBarButtons = @[];
  listTemplate.trailingNavigationBarButtons = @[];
  listTemplate.backButton = nil;
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
  NSMutableArray<NSString *> *identifiers = [NSMutableArray array];

  for (NSDictionary *station in stations) {
    if (![station isKindOfClass:[NSDictionary class]]) {
      continue;
    }

    NSString *title = [station objectForKey:@"title"] ?: [station objectForKey:@"programName"] ?: [station objectForKey:@"stationName"] ?: @"Station";
    NSString *subtitle = [self displaySubtitleForStation:station currentStation:currentStation];
    CPListItem *stationItem = [[CPListItem alloc] initWithText:title detailText:subtitle];
    stationItem.playing = [self station:station matchesCurrentStation:currentStation] && [self isPlaybackActive];
    stationItem.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
    stationItem.userInfo = station;
    stationItem.handler = ^(id<CPSelectableListItem> item, dispatch_block_t completionBlock) {
      NSDictionary *selectedStation = nil;
      if ([item isKindOfClass:[CPListItem class]]) {
        id userInfo = ((CPListItem *)item).userInfo;
        if ([userInfo isKindOfClass:[NSDictionary class]]) {
          selectedStation = (NSDictionary *)userInfo;
        }
      }
      TiAudiostreamCarPlaySceneDelegate *strongSelf = weakSelf;
      if (!strongSelf) {
        if (completionBlock) {
          completionBlock();
        }
        return;
      }

      [strongSelf handleStationSelection:selectedStation ?: station
                                  reason:@"station-selection"
                              completion:completionBlock];
    };
    [items addObject:stationItem];
    [identifiers addObject:[self stationIdentifier:station]];
  }

  _stationItems = [items mutableCopy];
  _stationItemIdentifiers = [identifiers copy];

  return @[ [[CPListSection alloc] initWithItems:items] ];
}

- (void)refreshStationItemsInPlace API_AVAILABLE(ios(14.0))
{
  NSArray<NSDictionary *> *stations = [TiAudiostreamModule persistedAutomotiveStations];
  NSDictionary *currentStation = [TiAudiostreamModule persistedCurrentAutomotiveStation];
  NSArray<NSString *> *identifiers = [self stationIdentifiersFromStations:stations];

  if (_stationItems.count == 0 || ![_stationItemIdentifiers isEqualToArray:identifiers] || _stationItems.count != stations.count) {
    if (_rootTemplate) {
      [_rootTemplate updateSections:[self buildRootSections]];
    }
    return;
  }

  [_stationItems enumerateObjectsUsingBlock:^(CPListItem *item, NSUInteger idx, BOOL *stop) {
    NSDictionary *station = idx < stations.count ? stations[idx] : nil;
    if (![station isKindOfClass:[NSDictionary class]]) {
      return;
    }

    NSString *title = [station objectForKey:@"title"] ?: [station objectForKey:@"programName"] ?: [station objectForKey:@"stationName"] ?: @"Station";
    NSString *subtitle = [self displaySubtitleForStation:station currentStation:currentStation];
    [item setText:title];
    [item setDetailText:subtitle];
    item.userInfo = station;
    item.playing = [self station:station matchesCurrentStation:currentStation] && [self isPlaybackActive];
    item.playingIndicatorLocation = CPListItemPlayingIndicatorLocationTrailing;
  }];
}

- (void)handleStationSelection:(NSDictionary *)station
                        reason:(NSString *)reason
                    completion:(TiAudiostreamCarPlayCompletion)completion API_AVAILABLE(ios(14.0))
{
  TiAudiostreamModule *module = [TiAudiostreamModule activeModule];
  if (!module) {
    NSLog(@"[ti.audiostream] No active module available for station selection (%@)", reason);
    if (completion) {
      completion();
    }
    return;
  }

  [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamAutomotiveStationSelectedNotification
                                                      object:station];
  if (completion) {
    completion();
  }

  NSArray<NSNumber *> *refreshDelays = @[ @0.15, @0.60, @1.20 ];
  for (NSNumber *delay in refreshDelays) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      [self refreshStationItemsInPlace];
    });
  }
  _pendingNowPlayingRequestID += 1;
  [self presentNowPlayingWhenPlaybackIsReadyAnimated:NO
                                              reason:reason
                                             attempt:0
                                           requestID:_pendingNowPlayingRequestID
                                          completion:nil];
}

- (void)presentNowPlayingTemplateAnimated:(BOOL)animated
                                    reason:(NSString *)reason
                                completion:(TiAudiostreamCarPlayCompletion)completion API_AVAILABLE(ios(14.0))
{
  if (!_interfaceController) {
    NSLog(@"[ti.audiostream] Cannot push Now Playing (%@): no CarPlay interface controller", reason);
    if (completion) {
      completion();
    }
    return;
  }

  CPNowPlayingTemplate *template = [CPNowPlayingTemplate sharedTemplate];
  template.upNextButtonEnabled = NO;
  template.albumArtistButtonEnabled = NO;

  if (_interfaceController.topTemplate == template) {
    NSLog(@"[ti.audiostream] Now Playing template already visible (%@)", reason);
    [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamCarPlayDidPresentNowPlayingNotification object:nil];
    if (completion) {
      completion();
    }
    return;
  }

  if ([_interfaceController.templates containsObject:template]) {
    NSLog(@"[ti.audiostream] Returning to existing Now Playing template (%@)", reason);
    [_interfaceController popToTemplate:template
                               animated:animated
                             completion:^(BOOL success, NSError *error) {
                               if (success) {
                                 [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamCarPlayDidPresentNowPlayingNotification object:nil];
                                 if (completion) {
                                   completion();
                                 }
                                 return;
                               }

                               NSLog(@"[ti.audiostream] Failed to return to Now Playing template (%@): %@",
                                 reason,
                                 error.localizedDescription ?: error);
                               if (completion) {
                                 completion();
                               }
                             }];
    return;
  }

  NSLog(@"[ti.audiostream] Pushing Now Playing template (%@)", reason);
  [_interfaceController pushTemplate:template
                             animated:animated
                           completion:^(BOOL success, NSError *error) {
                             if (success) {
                               [[NSNotificationCenter defaultCenter] postNotificationName:TiAudiostreamCarPlayDidPresentNowPlayingNotification object:nil];
                               if (completion) {
                                 completion();
                               }
                               return;
                             }

                             NSLog(@"[ti.audiostream] Failed to push Now Playing template (%@): %@",
                               reason,
                               error.localizedDescription ?: error);
                             if (completion) {
                               completion();
                             }
                           }];
}

- (void)presentNowPlayingWhenPlaybackIsReadyAnimated:(BOOL)animated
                                              reason:(NSString *)reason
                                             attempt:(NSUInteger)attempt
                                           requestID:(NSUInteger)requestID
                                          completion:(TiAudiostreamCarPlayCompletion)completion API_AVAILABLE(ios(14.0))
{
  if (requestID != _pendingNowPlayingRequestID) {
    if (completion) {
      completion();
    }
    return;
  }

  if ([self isNowPlayingReady]) {
    TiAudiostreamModule *module = [TiAudiostreamModule activeModule];
    [module refreshCarPlayNowPlayingItemForReason:[NSString stringWithFormat:@"%@-preflight", reason ?: @"unknown"]];
    NSLog(@"[ti.audiostream] Presenting Now Playing immediately (%@)", reason);
    [self presentNowPlayingTemplateAnimated:animated reason:reason completion:completion];
    return;
  }

  if (attempt >= 24) {
    NSLog(@"[ti.audiostream] Skipping delayed Now Playing push (%@): playback never became ready", reason);
    if (completion) {
      completion();
    }
    return;
  }

  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self presentNowPlayingWhenPlaybackIsReadyAnimated:animated
                                               reason:reason
                                              attempt:attempt + 1
                                            requestID:requestID
                                           completion:completion];
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

                                   if ([strongSelf isNowPlayingReady]) {
                                     strongSelf->_pendingNowPlayingRequestID += 1;
                                     [strongSelf presentNowPlayingTemplateAnimated:NO
                                                                            reason:@"scene-connect-eager"
                                                                        completion:nil];
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
  if (![NSThread isMainThread]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self handleAutomotiveStationsDidChange:notification];
    });
    return;
  }

  if (!_interfaceController) {
    return;
  }

  if (_rootTemplate) {
    [self refreshStationItemsInPlace];
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
