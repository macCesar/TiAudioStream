/**
 * ti.audiostream - Window Scene Delegate for Titanium compatibility
 *
 * Copyright (c) 2026 César Estrada (macCesar)
 * Licensed under the MIT License
 */

#import "TiAudiostreamWindowSceneDelegate.h"

// Adaptive across Titanium SDKs so the SAME tiapp.xml scene manifest boots on
// both. Discriminator is behavioral, not a version string:
//   - SDK >= 13.3.0.GA: TiApp itself adopted UIWindowSceneDelegate and builds
//     the window through the scene lifecycle. We forward every scene callback to
//     TiApp so the app boots exactly like a stock Titanium app.
//   - SDK <= 13.2.x.GA: TiApp still builds its window in didFinishLaunching, so
//     we only attach that already-created window to the connecting scene.
// Without this, an app that declares this delegate (needed to add a CarPlay
// scene) shows a black screen on 13.3.0 because TiApp's scene setup never runs.
@implementation TiAudiostreamWindowSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
  id appDelegate = [UIApplication sharedApplication].delegate;

  if ([appDelegate respondsToSelector:@selector(scene:willConnectToSession:options:)]) {
    // SDK >= 13.3.0: let TiApp set up the window scene natively.
    [appDelegate scene:scene willConnectToSession:session options:connectionOptions];
    return;
  }

  // SDK <= 13.2.x: attach the window TiApp already created in didFinishLaunching.
  if (![scene isKindOfClass:[UIWindowScene class]]) return;

  UIWindowScene *windowScene = (UIWindowScene *)scene;
  UIWindow *titaniumWindow = [(id<UIApplicationDelegate>)appDelegate window];

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

    NSLog(@"[ti.audiostream] Window scene attached to Titanium window (legacy path)");
  }
}

// On 13.3.0+ the rest of the scene lifecycle (didBecomeActive, background,
// openURLContexts, ...) must also reach TiApp. Transparent proxy: advertise and
// forward any selector TiApp handles that we don't. On <= 13.2.x TiApp ignores
// these scene selectors, so the proxy is a no-op there.
- (BOOL)respondsToSelector:(SEL)aSelector
{
  if ([super respondsToSelector:aSelector]) {
    return YES;
  }
  return [[UIApplication sharedApplication].delegate respondsToSelector:aSelector];
}

- (id)forwardingTargetForSelector:(SEL)aSelector
{
  id appDelegate = [UIApplication sharedApplication].delegate;
  if ([appDelegate respondsToSelector:aSelector]) {
    return appDelegate;
  }
  return nil;
}

@end
