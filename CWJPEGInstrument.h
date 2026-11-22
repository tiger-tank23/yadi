#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN
// All methods are synchronous. Use one dedicated serial worker, never the UI thread.
// Give the worker the latest decoded pixel buffer; discard stale frames upstream.
@interface CWJPEGInstrument : NSObject
- (BOOL)startWithIPv4:(NSString *)address error:(NSError * _Nullable * _Nullable)error;
- (CGSize)canvasSize;
- (int)frameRate;
- (BOOL)sendJPEG:(NSData *)jpeg error:(NSError **)error;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
