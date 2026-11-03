#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface RawPhotoSettingsAttempt : NSObject
@property(nonatomic, strong, nullable) AVCapturePhotoSettings *settings;
@property(nonatomic, copy, nullable) NSString *errorMessage;
@end

FOUNDATION_EXPORT RawPhotoSettingsAttempt *RawMakePhotoSettings(OSType rawPixelFormat, NSString * _Nullable codec);
FOUNDATION_EXPORT NSString * _Nullable RawPerformCapture(AVCapturePhotoOutput *output,
    AVCapturePhotoSettings *settings, CMVideoDimensions dimensions, BOOL flash, BOOL mirrored,
    id<AVCapturePhotoCaptureDelegate> delegate);
NS_ASSUME_NONNULL_END
