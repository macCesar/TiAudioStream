#import <Foundation/Foundation.h>

// All completions run on the main queue. Every request has byte and time limits.
@interface TiAudiostreamContentLoader : NSObject
+ (void)fetchURL:(NSURL *)url maxBytes:(NSUInteger)maxBytes completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion;
+ (void)resolveStreamURL:(NSURL *)url completion:(void (^)(NSURL *, NSError *))completion;
@end
