/**
 * ti.audiostream - Window Scene Delegate for Titanium compatibility
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiAudiostreamWindowSceneDelegate.h"

@implementation TiAudiostreamWindowSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
  if (![scene isKindOfClass:[UIWindowScene class]]) return;

  UIWindowScene *windowScene = (UIWindowScene *)scene;
  UIWindow *titaniumWindow = [UIApplication sharedApplication].delegate.window;

  if (titaniumWindow) {
    titaniumWindow.windowScene = windowScene;
    titaniumWindow.hidden = NO;
    self.window = titaniumWindow;
    [titaniumWindow makeKeyAndVisible];

    UIViewController *rootViewController = titaniumWindow.rootViewController;
    if (rootViewController) {
      [rootViewController setNeedsStatusBarAppearanceUpdate];
      [rootViewController.view setNeedsLayout];
      [rootViewController.view layoutIfNeeded];
    }

    NSLog(@"[ti.audiostream] Window scene attached to Titanium window");
  }
}

@end
