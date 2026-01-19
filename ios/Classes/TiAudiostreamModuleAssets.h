#import "TiModule.h"

@interface TiAudiostreamModuleAssets : NSObject
- (NSData *)moduleAsset:(NSString *)path;
- (NSData *)resolveModuleAsset:(NSString *)path;
@end