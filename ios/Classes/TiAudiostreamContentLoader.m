#import "TiAudiostreamContentLoader.h"

@interface TiAudiostreamContentLoader () <NSURLSessionDataDelegate>
@property(nonatomic) NSURLSession *session;
@property(nonatomic) NSMutableData *data;
@property(nonatomic) NSURLResponse *response;
@property(nonatomic) NSUInteger maxBytes;
@property(nonatomic) BOOL probeStream;
@property(nonatomic) BOOL stationList;
@property(nonatomic) BOOL finished;
@property(nonatomic, copy) void (^completion)(NSData *, NSURLResponse *, NSError *);
@end

@implementation TiAudiostreamContentLoader

+ (NSError *)errorWithCode:(NSInteger)code
{
  return [NSError errorWithDomain:@"ti.audiostream.HTTP" code:code userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Stream request failed (%ld)", (long)code]}];
}

+ (void)requestURL:(NSURL *)url maxBytes:(NSUInteger)maxBytes probeStream:(BOOL)probe completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion
{
  if (!url || !([url.scheme.lowercaseString isEqualToString:@"http"] || [url.scheme.lowercaseString isEqualToString:@"https"])) {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, nil, [self errorWithCode:NSURLErrorBadURL]); });
    return;
  }
  TiAudiostreamContentLoader *loader = [self new];
  loader.maxBytes = maxBytes;
  loader.probeStream = probe;
  NSString *extension = url.path.pathExtension.lowercaseString;
  loader.stationList = [extension isEqualToString:@"m3u"] || [extension isEqualToString:@"pls"];
  loader.data = [NSMutableData data];
  loader.completion = completion;
  NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  config.timeoutIntervalForRequest = 10;
  config.timeoutIntervalForResource = 15;
  loader.session = [NSURLSession sessionWithConfiguration:config delegate:loader delegateQueue:nil];
  [[loader.session dataTaskWithURL:url] resume];
}

+ (void)fetchURL:(NSURL *)url maxBytes:(NSUInteger)maxBytes completion:(void (^)(NSData *, NSURLResponse *, NSError *))completion
{
  [self requestURL:url maxBytes:maxBytes probeStream:NO completion:completion];
}

- (void)finishWithData:(NSData *)data error:(NSError *)error
{
  if (self.finished) return;
  self.finished = YES;
  void (^completion)(NSData *, NSURLResponse *, NSError *) = self.completion;
  self.completion = nil;
  NSURLResponse *response = self.response;
  [self.session invalidateAndCancel];
  self.session = nil;
  dispatch_async(dispatch_get_main_queue(), ^{ completion(data, response, error); });
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler
{
  self.response = response;
  NSInteger code = [(NSHTTPURLResponse *)response statusCode];
  if (code < 200 || code >= 300) {
    completionHandler(NSURLSessionResponseCancel);
    [self finishWithData:nil error:[[self class] errorWithCode:code]];
    return;
  }
  NSString *mime = response.MIMEType.lowercaseString ?: @"";
  BOOL playlistMime = [mime containsString:@"mpegurl"] || [mime containsString:@"scpls"];
  self.stationList = self.stationList || playlistMime;
  if (self.probeStream && !self.stationList && ([mime hasPrefix:@"audio/"] || [mime hasPrefix:@"video/"])) {
    completionHandler(NSURLSessionResponseCancel);
    [self finishWithData:nil error:nil]; // Native player owns direct audio/HLS.
    return;
  }
  if (response.expectedContentLength > (int64_t)self.maxBytes) {
    completionHandler(NSURLSessionResponseCancel);
    [self finishWithData:nil error:(self.probeStream && !self.stationList) ? nil : [[self class] errorWithCode:NSURLErrorDataLengthExceedsMaximum]];
    return;
  }
  completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data
{
  if (self.finished) return;
  if (self.data.length + data.length > self.maxBytes) {
    [self finishWithData:nil error:[[self class] errorWithCode:NSURLErrorDataLengthExceedsMaximum]];
    return;
  }
  [self.data appendData:data];
  if (self.probeStream) {
    NSString *prefix = [[NSString alloc] initWithData:self.data encoding:NSUTF8StringEncoding];
    NSString *trimmed = [prefix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([prefix containsString:@"#EXT-X-"]) {
      // HLS may use .m3u or no suffix. Keep its URL for AVPlayer.
      [self finishWithData:nil error:nil];
    } else if (!self.stationList && (!prefix || (trimmed.length >= 16 && ![trimmed hasPrefix:@"#"] && ![trimmed.lowercaseString hasPrefix:@"[playlist]"]))) {
      [self finishWithData:nil error:nil];
    }
  }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
  [self finishWithData:error ? nil : self.data error:error];
}

+ (void)resolveStreamURL:(NSURL *)url completion:(void (^)(NSURL *, NSError *))completion
{
  if ([@[@"mp3", @"aac", @"aacp", @"m4a", @"mp4", @"ogg", @"oga", @"opus", @"wav", @"flac", @"m3u8"] containsObject:url.path.pathExtension.lowercaseString ?: @""]) {
    dispatch_async(dispatch_get_main_queue(), ^{ completion(url, nil); });
    return;
  }
  [self requestURL:url maxBytes:256 * 1024 probeStream:YES completion:^(NSData *data, NSURLResponse *response, NSError *error) {
    if (error) { completion(nil, error); return; }
    NSURL *base = response.URL ?: url;
    if (!data) { completion(base, nil); return; }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    NSString *extension = base.path.pathExtension.lowercaseString;
    NSString *mime = response.MIMEType.lowercaseString;
    BOOL isList = [extension isEqualToString:@"pls"] || [extension isEqualToString:@"m3u"] ||
      [mime containsString:@"mpegurl"] || [mime containsString:@"scpls"] ||
      [text containsString:@"#EXTM3U"] || [text.lowercaseString containsString:@"[playlist]"];
    if (!isList || [text containsString:@"#EXT-X-"]) { completion(base, nil); return; }
    BOOL isPLS = [extension isEqualToString:@"pls"] || [mime containsString:@"scpls"] || [text.lowercaseString containsString:@"[playlist]"];
    for (NSString *rawLine in [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]) {
      NSString *line = [rawLine stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if (!line.length || [line hasPrefix:@"#"] || [line hasPrefix:@"["]) continue;
      NSRange equal = [line rangeOfString:@"="];
      if (isPLS && equal.location != NSNotFound && [line.lowercaseString hasPrefix:@"file"]) {
        line = [[line substringFromIndex:equal.location + 1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
      } else if (isPLS) continue;
      NSURL *target = [NSURL URLWithString:line relativeToURL:base].absoluteURL.standardizedURL;
      if ([target.scheme.lowercaseString isEqualToString:@"http"] || [target.scheme.lowercaseString isEqualToString:@"https"]) {
        completion(target, nil); return;
      }
    }
    completion(nil, [self errorWithCode:NSURLErrorCannotParseResponse]);
  }];
}
@end
