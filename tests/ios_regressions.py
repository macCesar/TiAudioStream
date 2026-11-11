import pathlib, subprocess, re, tempfile
# Compile selected production methods against deterministic system substitutes.
# These regressions do not certify AVPlayer, CarPlay or real device behavior.
repo=pathlib.Path(__file__).resolve().parents[1]
workspace=tempfile.TemporaryDirectory(prefix='tiaudiostream-ios-tests-')
root=pathlib.Path(workspace.name)
src=(repo/'ios/Classes/TiAudiostreamModule.m').read_text()
cp=(repo/'ios/Classes/TiAudiostreamCarPlaySceneDelegate.m').read_text()
def method(text,sig):
 start=text.index(sig);end=text.find('\n}\n',start)+2
 assert end>start
 return text[start:end]
methods='\n'.join(method(src,s) for s in ['- (void)handlePlaybackEnded:', '- (void)metadataOutput:', '- (void)setStream:', '- (void)start:', '- (void)setMetadata:', '- (void)pause:', '- (void)handleInterruption:', '- (void)attemptReconnect','- (void)reconnect','- (void)resetRetryLogic','- (BOOL)isRetryablePlaybackError:', '- (NSString *)applyRules:', '- (void)parseMetadataItems:', '- (void)stop:', '- (void)observeValueForKeyPath:'])
preamble=r"""
#import <Foundation/Foundation.h>
#define TiAudiostreamDebugLog(...) ((void)0)
#define ENSURE_SINGLE_ARG(args, type) NSCAssert([args isKindOfClass:[type class]], @"argument type")
#import <AVFoundation/AVFoundation.h>
#import <dispatch/dispatch.h>
#undef TARGET_OS_IOS
#define TARGET_OS_IOS 1
typedef NSInteger MPNowPlayingPlaybackState;
enum {MPNowPlayingPlaybackStateStopped=0,MPNowPlayingPlaybackStatePlaying=1,MPNowPlayingPlaybackStatePaused=2};
static NSString *TiAudiostreamAutomotiveStationsDidChangeNotification=@"changed";
@interface FakeAudioSession:NSObject
+(id)sharedInstance;-(BOOL)setActive:(BOOL)b withOptions:(NSUInteger)o error:(NSError**)e;
@end
@implementation FakeAudioSession
+(id)sharedInstance{return [self new];}-(BOOL)setActive:(BOOL)b withOptions:(NSUInteger)o error:(NSError**)e{return YES;}
@end
#define AVAudioSession FakeAudioSession
@interface TiUtils:NSObject
+(BOOL)boolValue:(NSString*)k properties:(NSDictionary*)p def:(BOOL)d;
+(NSString*)stringValue:(NSString*)k properties:(NSDictionary*)p;
+(NSString*)stringValue:(NSString*)k properties:(NSDictionary*)p def:(NSString*)d;
@end
@implementation TiUtils
+(NSString*)stringValue:(NSString*)k properties:(NSDictionary*)p def:(NSString*)d{return [self stringValue:k properties:p]?:d;}
+(NSString*)stringValue:(NSString*)k properties:(NSDictionary*)p{return [p[k] isKindOfClass:[NSString class]]?p[k]:nil;}
+(BOOL)boolValue:(NSString*)k properties:(NSDictionary*)p def:(BOOL)d{return p[k]?[p[k] boolValue]:d;}
@end
@interface FakeInfoCenter:NSObject
@property NSDictionary *nowPlayingInfo;
@end
@implementation FakeInfoCenter
@end
#define MPNowPlayingInfoCenter FakeInfoCenter

#define AVAudioSessionInterruptionTypeKey @"type"
#define AVAudioSessionInterruptionOptionKey @"options"
@interface UIImage:NSObject
+(id)imageWithData:(NSData*)data;
@end
@implementation UIImage
+(id)imageWithData:(NSData*)data{return nil;}
@end
@interface FakePlayer:NSObject
@property AVPlayerItem *currentItem;
-(void)play;
@property float rate;@property AVPlayerTimeControlStatus timeControlStatus;
-(void)pause;
@end
@implementation FakePlayer
-(void)play{self.rate=1;}
-(void)pause{self.rate=0;self.timeControlStatus=AVPlayerTimeControlStatusPaused;}
@end
static NSMutableArray *pendingArtwork;
@interface TiAudiostreamContentLoader:NSObject
+(void)fetchURL:(NSURL*)url maxBytes:(NSUInteger)limit completion:(void(^)(NSData*,NSURLResponse*,NSError*))completion;
@end
@implementation TiAudiostreamContentLoader
+(void)fetchURL:(NSURL*)url maxBytes:(NSUInteger)limit completion:(void(^)(NSData*,NSURLResponse*,NSError*))completion{if(!pendingArtwork)pendingArtwork=[NSMutableArray new];[pendingArtwork addObject:[completion copy]];}
@end
static UIImage *TiAudiostreamDecodeArtwork(NSData *data){return [UIImage imageWithData:data];}
@interface Probe:NSObject {
@public
 FakePlayer *_player;
 BOOL _isLive, _stopped, _playRequested,_pendingPlay,_prepareInProgress,_carPlayOwnershipSessionRefreshed,_resumeOnInterruption,_autoUpdateMetadata;
 AVPlayerItemMetadataOutput *_metadataOutput; NSString *_lastEmittedState; NSString *_currentURL,*_currentTitle,*_currentArtist,*_preparingURL,*_preparedURL,*lastState,*_lastEmittedMetadataTitle,*_lastEmittedMetadataArtist,*_lastEmittedMetadataArtwork;AVPlayerItem *_currentItem;NSUInteger _streamGeneration;UIImage *_currentArtwork;
 NSArray *_titleRules,*_artistRules;NSUInteger _artworkGeneration, _automaticMetadataGeneration;
 int _retryCount,_maxRetries;double _retryDelay;NSTimer *_retryTimer;
 int starts,prepares,publishes,events;
 NSString *capturedTitle,*capturedArtist;
}
-(void)handlePlaybackEnded:(NSNotification*)n;-(void)metadataOutput:(AVPlayerItemMetadataOutput*)output didOutputTimedMetadataGroups:(NSArray*)groups fromPlayerItemTrack:(AVPlayerItemTrack*)track;
-(void)setMetadata:(id)args;-(void)setMetadataRules:(id)args;-(BOOL)hasNowPlayingPublishIntent;
-(void)primeSystemAudioOwnershipForPlaybackStart;-(void)ensureCarPlayOwnershipSessionForReason:(NSString*)r;-(void)activateNowPlayingSessionIfPossible;
-(void)hardStop:(id)x;-(BOOL)isRetryablePlaybackError:(NSError*)error;-(void)start:(id)x;-(void)updateNowPlaying;-(NSString*)timeControlStatusName:(AVPlayerTimeControlStatus)s;
-(void)prepareCurrentStreamItem;-(void)fireState:(NSString*)s;
-(void)setPlaybackState:(NSInteger)s;-(NSArray*)activeNowPlayingInfoCenters;-(void)reportTerminalPlaybackErrorOnce:(NSString*)s;-(void)fireError:(NSString*)s;
-(NSString*)applyRules:(NSArray*)rules toString:(NSString*)input;
-(void)emitMetadataIfChangedWithTitle:(NSString*)t artist:(NSString*)a artwork:(NSString*)art raw:(NSDictionary*)r;
@end
@implementation Probe
-(instancetype)init{if((self=[super init])){_player=[FakePlayer new];_currentURL=@"https://radio.test/live";_retryDelay=0.01;_maxRetries=5;_autoUpdateMetadata=YES;}return self;}
-(void)hardStop:(id)x{}
-(void)primeSystemAudioOwnershipForPlaybackStart{starts++;}
-(void)ensureCarPlayOwnershipSessionForReason:(NSString*)r{}
-(void)activateNowPlayingSessionIfPossible{}
-(BOOL)hasNowPlayingPublishIntent{return _playRequested;}
-(void)setMetadataRules:(id)args{}
-(void)updateNowPlaying{publishes++;}
-(NSString*)timeControlStatusName:(AVPlayerTimeControlStatus)s{return @"fake";}
-(void)prepareCurrentStreamItem{prepares++;_prepareInProgress=YES;_preparingURL=_currentURL;_streamGeneration++;}
-(void)fireState:(NSString*)s{lastState=s;}
-(void)setPlaybackState:(NSInteger)s{}
-(NSArray*)activeNowPlayingInfoCenters{return @[[FakeInfoCenter new]];}
-(void)reportTerminalPlaybackErrorOnce:(NSString*)s{}
-(void)fireError:(NSString*)s{}
-(void)emitMetadataIfChangedWithTitle:(NSString*)t artist:(NSString*)a artwork:(NSString*)art raw:(NSDictionary*)r{events++;capturedTitle=t;capturedArtist=a;}
"""
preamble += '\n'
cp_method=method(cp,'- (NSUInteger)indexOfCurrentStationInStations:')
preamble=preamble.replace('@interface Probe:NSObject', method(cp,'static NSString *TiAudiostreamStationString(')+'\n'+'''static NSString *auditLiveURL;
@interface TiAudiostreamModule:NSObject
+(id)activeModule;-(NSString*)carPlayCurrentStreamURL;
@end
@implementation TiAudiostreamModule
+(id)activeModule{static id m; if(!m)m=[self new];return m;}
-(NSString*)carPlayCurrentStreamURL{return auditLiveURL;}
@end
@interface IndexProbe:NSObject
@end
@implementation IndexProbe
'''+cp_method+'''
@end
@interface Probe:NSObject''')
main=r"""
@end
static void out(NSString *s,id x){printf("%s=%s\n",s.UTF8String,[[x description] UTF8String]);}
static AVMutableMetadataItem *tag(NSString *key,id value){
 AVMutableMetadataItem *m=[AVMutableMetadataItem metadataItem];m.keySpace=AVMetadataKeySpaceIcy;m.key=key;m.value=value;return m;
}
int main(){@autoreleasepool{
 Probe *switcher=[Probe new];
 [switcher setStream:@{@"url":@"https://a/list.pls"}];[switcher start:nil];[switcher pause:nil];
 [switcher setStream:@{@"url":@"https://b/list.pls"}];[switcher start:nil];
 out(@"SWITCH_DURING_PREPARATION_STARTS_NEW_URL", @(switcher->prepares));
 IndexProbe *idx=[IndexProbe new];auditLiveURL=@"https://a";
 NSArray *stations=@[@{@"id":@"a",@"streamUrl":@"https://a"},@{@"id":@"b",@"streamUrl":@"https://b"}];
 out(@"CARPLAY_PERSISTED_SELECTION_BEATS_OLD_LIVE_URL",@([idx indexOfCurrentStationInStations:stations currentStation:stations[1]]));
 out(@"CARPLAY_LIVE_URL_FALLBACK",@([idx indexOfCurrentStationInStations:stations currentStation:nil]));
 out(@"CARPLAY_STABLE_ID_FALLBACK",@([idx indexOfCurrentStationInStations:stations currentStation:@{@"id":@"b"}]));

 out(@"CARPLAY_NULL_URL_SAFE",@([idx indexOfCurrentStationInStations:@[@{@"streamUrl":[NSNull null],@"id":@"b"}] currentStation:@{@"streamUrl":[NSNull null],@"id":@"b"}]==0));
 auditLiveURL=@"https://b";
 out(@"CARPLAY_NULL_IDS_USE_LIVE_URL",@([idx indexOfCurrentStationInStations:@[@{@"streamUrl":[NSNull null],@"id":[NSNull null]},@{@"streamUrl":@"https://b",@"id":[NSNull null]}] currentStation:@{@"id":[NSNull null]}]==1));
 out(@"CARPLAY_NUMERIC_ID_RETAINED",@([idx indexOfCurrentStationInStations:@[@{@"id":@1},@{@"id":@2}] currentStation:@{@"id":@2}]==1));
 Probe *stale=[Probe new];stale->_preparedURL=@"https://a";stale->_currentURL=@"https://a";stale->_metadataOutput=[AVPlayerItemMetadataOutput new];AVPlayerItemMetadataOutput *oldOutput=stale->_metadataOutput;
 [stale setStream:@{@"url":@"https://b"}];
 [stale metadataOutput:oldOutput didOutputTimedMetadataGroups:@[[AVTimedMetadataGroup new]] fromPlayerItemTrack:nil];
 out(@"PAUSED_SELECTION_DETACHES_METADATA",@(stale->_metadataOutput==nil&&stale->events==0));
 Probe *ended=[Probe new];ended->_playRequested=YES;ended->_preparedURL=ended->_currentURL;ended->_currentItem=[AVPlayerItem playerItemWithURL:[NSURL URLWithString:@"https://fixture/finite.mp3"]];
 [ended handlePlaybackEnded:[NSNotification notificationWithName:AVPlayerItemDidPlayToEndTimeNotification object:ended->_currentItem]];
 out(@"FINITE_END_STOPS_INTENT",@(!ended->_playRequested&&ended->_stopped&&[ended->lastState isEqualToString:@"stopped"]));
 Probe *manual=[Probe new];manual->_currentArtwork=[UIImage new];
 [manual setMetadata:@{@"title":@"New Manual Title",@"artwork":@"https://images.test/new.png"}];
 out(@"MANUAL_TITLE_PUBLISHED_BEFORE_IMAGE", @(manual->publishes));
 [manual setMetadata:@{@"artwork":[NSNull null]}];
 void(^oldImage)(NSData*,NSURLResponse*,NSError*)=pendingArtwork.lastObject;
 oldImage([NSData data],nil,nil);
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
 out(@"CLEAR_IGNORES_OLD_IMAGE_RESULT", @(manual->_currentArtwork==nil));
 manual->_currentArtwork=[UIImage new];
 [manual setMetadata:@{@"artist":@"Retained Artist"}];
 out(@"OMITTED_MANUAL_ARTWORK_PRESERVED", @(manual->_currentArtwork!=nil));
 Probe *p=[Probe new];p->_playRequested=YES;
 [p attemptReconnect];[p pause:nil];[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
 out(@"RETRY_AFTER_PAUSE_PLAY_REQUESTED",@(p->_playRequested));out(@"RETRY_AFTER_PAUSE_PREPARES",@(p->prepares));
 p=[Probe new];p->_player.rate=1;p->_player.timeControlStatus=AVPlayerTimeControlStatusPlaying;p->_playRequested=YES;
 [p handleInterruption:[NSNotification notificationWithName:@"test" object:nil userInfo:@{@"type":@1}]];
 [p pause:nil];
 [p handleInterruption:[NSNotification notificationWithName:@"test" object:nil userInfo:@{@"type":@0,@"options":@1}]];
 out(@"MANUAL_PAUSE_DURING_INTERRUPTION_STARTS",@(p->starts));
 p=[Probe new];p->_currentTitle=@"Old";p->_currentArtist=@"Old Artist";
 [p parseMetadataItems:@[tag(@"StreamTitle",@"Singer - New Song"),tag(@"StreamUrl",@"http://127.0.0.1:1/unavailable.jpg")]];
 out(@"TITLE_WITH_BROKEN_ARTWORK_INTERNAL",p->_currentTitle);out(@"TITLE_WITH_BROKEN_ARTWORK_PUBLISHES",@(p->publishes));out(@"TITLE_WITH_BROKEN_ARTWORK_EVENTS",@(p->events));
 p=[Probe new];p->_autoUpdateMetadata=NO;p->_currentTitle=@"Manual";
 [p parseMetadataItems:@[tag(@"StreamTitle",@"Singer - Track")]];
 out(@"AUTO_FALSE_PRESERVES_TITLE",p->_currentTitle);out(@"AUTO_FALSE_EVENT_TITLE",p->capturedTitle);
 out(@"RETRY_URL_TIMEOUT",@([p isRetryablePlaybackError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]]));
 out(@"RETRY_WRAPPED_TIMEOUT",@([p isRetryablePlaybackError:[NSError errorWithDomain:AVFoundationErrorDomain code:AVErrorUnknown userInfo:@{NSUnderlyingErrorKey:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]}]]));
 p=[Probe new];p->_player.rate=1;p->_player.timeControlStatus=AVPlayerTimeControlStatusPlaying;p->_playRequested=YES;
 [p->_player addObserver:p forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew context:nil];
 [p stop:nil];int before=p->publishes;
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.04]];
 out(@"SOFT_STOP_FINAL_STATE",p->lastState);out(@"SOFT_STOP_LATE_PUBLISHES",@(p->publishes-before));
 [p->_player removeObserver:p forKeyPath:@"timeControlStatus"];
 p=[Probe new];
 out(@"BAD_REPLACEMENT_PRESERVES_INPUT", [p applyRules:@[@{@"match":@"(Song)",@"replace":@"$2"}] toString:@"Song"]);
 out(@"VALID_REPLACEMENT", [p applyRules:@[@{@"match":@"(Song)",@"replace":@"New $1"}] toString:@"Song"]);
 out(@"RETRY_HTTP_503", @([p isRetryablePlaybackError:[NSError errorWithDomain:@"ti.audiostream.HTTP" code:503 userInfo:nil]]));
 out(@"RETRY_HTTP_404", @([p isRetryablePlaybackError:[NSError errorWithDomain:@"ti.audiostream.HTTP" code:404 userInfo:nil]]));
 [p parseMetadataItems:@[tag(@"StreamTitle",@"Singer - Song - Part II")]];out(@"MULTI_SEPARATOR_TITLE",p->capturedTitle);
 }}
"""
(root/'ObjcProbe.m').write_text(preamble+methods+main)
subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','AVFoundation','-framework','CoreMedia',str(root/'ObjcProbe.m'),'-o',str(root/'ObjcProbe')],check=True)
result = subprocess.run([str(root/'ObjcProbe')], check=True, capture_output=True, text=True)
observed = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
expected = {
 'CARPLAY_NULL_IDS_USE_LIVE_URL':'1', 'CARPLAY_NUMERIC_ID_RETAINED':'1', 'CARPLAY_NULL_URL_SAFE':'1', 'PAUSED_SELECTION_DETACHES_METADATA':'1', 'FINITE_END_STOPS_INTENT':'1',
 'MANUAL_TITLE_PUBLISHED_BEFORE_IMAGE': '1',
 'CLEAR_IGNORES_OLD_IMAGE_RESULT': '1',
 'OMITTED_MANUAL_ARTWORK_PRESERVED': '1',
 'SWITCH_DURING_PREPARATION_STARTS_NEW_URL': '2',
 'CARPLAY_PERSISTED_SELECTION_BEATS_OLD_LIVE_URL': '1',
 'CARPLAY_LIVE_URL_FALLBACK': '0',
 'CARPLAY_STABLE_ID_FALLBACK': '1',
 'RETRY_AFTER_PAUSE_PLAY_REQUESTED': '0',
 'RETRY_AFTER_PAUSE_PREPARES': '0',
 'MANUAL_PAUSE_DURING_INTERRUPTION_STARTS': '0',
 'TITLE_WITH_BROKEN_ARTWORK_INTERNAL': 'New Song',
 'TITLE_WITH_BROKEN_ARTWORK_PUBLISHES': '1',
 'TITLE_WITH_BROKEN_ARTWORK_EVENTS': '1',
 'AUTO_FALSE_PRESERVES_TITLE': 'Manual',
 'AUTO_FALSE_EVENT_TITLE': 'Track',
 'RETRY_URL_TIMEOUT': '1',
 'RETRY_WRAPPED_TIMEOUT': '1',
 'SOFT_STOP_FINAL_STATE': 'stopped',
 'SOFT_STOP_LATE_PUBLISHES': '0',
 'BAD_REPLACEMENT_PRESERVES_INPUT': 'Song',
 'VALID_REPLACEMENT': 'New Song',
 'RETRY_HTTP_503': '1',
 'RETRY_HTTP_404': '0',
 'MULTI_SEPARATOR_TITLE': 'Song - Part II',
}
failures = []
for key, value in expected.items():
    actual = observed.get(key)
    print(('PASS' if actual == value else 'FAIL') + f' {key}: {actual!r} (expected {value!r})')
    if actual != value:
        failures.append(key)
assert not failures, f'{len(failures)} regressions failed: {failures}'
print(f'{len(expected)} iOS regressions passed')
