#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>

// Decode a bounded thumbnail instead of allocating a full resolution source bitmap.
NS_INLINE UIImage *TiAudiostreamDecodeArtwork(NSData *data)
{
  if (!data.length || data.length > 8 * 1024 * 1024) return nil;
  CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
  if (!source) return nil;
  NSDictionary *options = @{
    (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
    (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
    (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @1024,
    (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
  };
  CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
  CFRelease(source);
  if (!thumbnail) return nil;
  UIImage *image = [UIImage imageWithCGImage:thumbnail];
  CGImageRelease(thumbnail);
  return image;
}
