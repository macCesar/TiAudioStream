#import <Foundation/Foundation.h>

// Binary diagnostics are deliberately opt-in. JS events remain available in production.
#ifndef TI_AUDIOSTREAM_DIAGNOSTICS
#define TI_AUDIOSTREAM_DIAGNOSTICS 0
#endif
#if TI_AUDIOSTREAM_DIAGNOSTICS
NS_INLINE void TiAudiostreamDebugLog(NSString *format, ...)
{
  va_list args;
  va_start(args, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
  va_end(args);
  NSRegularExpression *urls = [NSRegularExpression regularExpressionWithPattern:@"https?://[^\\s'\\\"<>]+" options:NSRegularExpressionCaseInsensitive error:nil];
  message = [urls stringByReplacingMatchesInString:message options:0 range:NSMakeRange(0, message.length) withTemplate:@"[URL redacted]"];
  NSLog(@"%@", message);
}
#else
#define TiAudiostreamDebugLog(...) ((void)0)
#endif
