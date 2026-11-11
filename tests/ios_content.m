#import <Foundation/Foundation.h>
#import "TiAudiostreamContentLoader.h"

static int remaining, failures;
static void check(BOOL condition, NSString *name) {
  printf("%s %s\n", condition ? "PASS" : "FAIL", name.UTF8String);
  if (!condition) failures++;
}
int main(int argc, char **argv) {
  @autoreleasepool {
    NSURL *base = [NSURL URLWithString:[NSString stringWithUTF8String:argv[1]]];
    NSDictionary *cases = @{
      @"absolute.pls": @"/audio.mp3", @"plain.m3u": @"/audio.mp3", @"named.m3u": @"/file.php", @"relative.pls": @"/audio.mp3",
      @"relative.m3u?token=1#fragment": @"/audio.mp3", @"hls.m3u": @"/hls.m3u",
      @"list": @"/audio.mp3", @"live": @"/live", @"hls.m3u8": @"/hls.m3u8"
    };
    remaining = (int)cases.count + 5;
    void (^done)(void) = ^{ if (--remaining == 0) exit(failures ? 1 : 0); };
    for (NSString *path in cases) {
      [TiAudiostreamContentLoader resolveStreamURL:[NSURL URLWithString:path relativeToURL:base].absoluteURL completion:^(NSURL *url, NSError *error) {
        check(error == nil && [url.path isEqualToString:cases[path]], path);
        done();
      }];
    }
    for (NSString *path in @[@"404.pls", @"429.pls", @"503.pls", @"empty.pls"]) {
      [TiAudiostreamContentLoader resolveStreamURL:[NSURL URLWithString:path relativeToURL:base].absoluteURL completion:^(NSURL *url, NSError *error) {
        check(url == nil && error != nil, path);
        if (![path isEqualToString:@"empty.pls"]) check(error.code == path.integerValue, @"HTTP status preserved");
        done();
      }];
    }
    [TiAudiostreamContentLoader fetchURL:[NSURL URLWithString:@"huge" relativeToURL:base].absoluteURL maxBytes:1024 completion:^(NSData *data, NSURLResponse *response, NSError *error) {
      check(data == nil && error != nil, @"bounded download"); done();
    }];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ fprintf(stderr, "Timed out\n"); exit(2); });
  }
  dispatch_main();
}
