"""Compile the production CarPlay artwork method with deterministic image downloads."""
import argparse
import pathlib
import subprocess
import tempfile

repo = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=pathlib.Path, default=repo/'ios/Classes/TiAudiostreamCarPlaySceneDelegate.m')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('- (void)applyArtworkForStation:')
method = source[start:source.index('\n}\n', start) + 2]
preamble = r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
@interface UIImage:NSObject
@property NSString *tag;
@property CGSize size;
@end
@implementation UIImage
@end
@interface CPListItem:NSObject
@property UIImage *image;
@end
@implementation CPListItem
@end
static NSMutableArray *downloads;
@interface TiAudiostreamContentLoader:NSObject
+(void)fetchURL:(NSURL*)url maxBytes:(NSUInteger)bytes completion:(void(^)(NSData*,NSURLResponse*,NSError*))completion;
@end
@implementation TiAudiostreamContentLoader
+(void)fetchURL:(NSURL*)url maxBytes:(NSUInteger)bytes completion:(void(^)(NSData*,NSURLResponse*,NSError*))completion{
 if(!downloads)downloads=[NSMutableArray new];[downloads addObject:[completion copy]];
}
@end
static UIImage *TiAudiostreamDecodeArtwork(NSData *data){
 if(!data.length)return nil;UIImage *image=[UIImage new];image.tag=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];image.size=CGSizeMake(10,10);return image;
}
#define TiAudiostreamCarPlaySceneDelegate Probe
@interface Probe:NSObject{NSCache<NSString*,UIImage*> *_artworkCache;NSMutableDictionary *_pendingArtwork;}
@end
@implementation Probe
'''
main = r'''
@end
static void complete(NSUInteger index, NSString *value){
 void(^completion)(NSData*,NSURLResponse*,NSError*)=downloads[index];
 completion([value dataUsingEncoding:NSUTF8StringEncoding],nil,nil);
 [[NSRunLoop currentRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
}
static void check(BOOL ok,NSString *name){printf("%s %s\n",ok?"PASS":"FAIL",name.UTF8String);if(!ok)exit(1);}
int main(){@autoreleasepool{
 Probe *probe=[Probe new];CPListItem *item=[CPListItem new];
 [probe applyArtworkForStation:@{@"id":@"a",@"artwork":@"https://image.test/a.png"} toItem:item];
 [probe applyArtworkForStation:@{@"id":@"b",@"artwork":@"https://image.test/b.png"} toItem:item];
 complete(1,@"B");complete(0,@"A");
 check([item.image.tag isEqualToString:@"B"],@"reused row rejects previous station image");
 [probe applyArtworkForStation:@{@"id":@"b",@"artwork":@"https://image.test/c.png"} toItem:item];
 [probe applyArtworkForStation:@{@"id":@"b",@"artwork":@"https://image.test/d.png"} toItem:item];
 complete(3,@"D");complete(2,@"C");
 check([item.image.tag isEqualToString:@"D"],@"same station rejects previous image");
 [probe applyArtworkForStation:@{@"id":@"b",@"artwork":@"https://image.test/e.png"} toItem:item];
 [probe applyArtworkForStation:@{@"id":@"b"} toItem:item];complete(4,@"E");
 check(item.image==nil,@"cleared artwork cannot return from pending download");
 [probe applyArtworkForStation:@{@"id":@"b",@"artwork":@"https://image.test/f.png"} toItem:item];complete(5,nil);
 check(item.image==nil,@"failed newest image retains fallback");
 NSUInteger count=downloads.count;CPListItem *other=[CPListItem new];
 NSDictionary *same=@{@"artwork":@"https://image.test/shared.png"};
 [probe applyArtworkForStation:same toItem:item];[probe applyArtworkForStation:same toItem:item];[probe applyArtworkForStation:same toItem:other];
 check(downloads.count==count+1,@"same pending URL coalesces repeated refreshes and rows");complete(count,@"Shared");
 check([item.image.tag isEqualToString:@"Shared"]&&[other.image.tag isEqualToString:@"Shared"],@"shared download updates both current rows");
 [probe applyArtworkForStation:same toItem:[CPListItem new]];check(downloads.count==count+1,@"valid shared image cached");

}}
'''
with tempfile.TemporaryDirectory(prefix='tiaudiostream-carplay-') as tmp:
    path = pathlib.Path(tmp)
    (path/'probe.m').write_text(preamble + method + main)
    subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', '-framework', 'CoreGraphics', str(path/'probe.m'), '-o', str(path/'probe')], check=True)
    subprocess.run([str(path/'probe')], check=True)
