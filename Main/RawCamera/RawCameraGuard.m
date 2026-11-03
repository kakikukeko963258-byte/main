#import "RawCameraGuard.h"

@implementation RawPhotoSettingsAttempt
@end

RawPhotoSettingsAttempt *RawMakePhotoSettings(OSType rawPixelFormat, NSString *codec) {
    RawPhotoSettingsAttempt *result = [RawPhotoSettingsAttempt new];
    @try {
        if (rawPixelFormat != 0) {
            result.settings = [AVCapturePhotoSettings photoSettingsWithRawPixelFormatType:rawPixelFormat
                rawFileType:AVFileTypeDNG processedFormat:nil processedFileType:nil];
        } else {
            result.settings = [AVCapturePhotoSettings photoSettingsWithFormat:@{AVVideoCodecKey: codec ?: AVVideoCodecTypeJPEG}];
        }
    } @catch (NSException *exception) {
        result.errorMessage = [NSString stringWithFormat:@"撮影形式を設定できません: %@", exception.reason ?: exception.name];
    }
    return result;
}

NSString *RawPerformCapture(AVCapturePhotoOutput *output, AVCapturePhotoSettings *settings,
                           CMVideoDimensions dimensions, BOOL flash, BOOL mirrored,
                           id<AVCapturePhotoCaptureDelegate> delegate) {
    @try {
        if (dimensions.width > 0 && dimensions.height > 0) settings.maxPhotoDimensions = dimensions;
        if (settings.rawPhotoPixelFormatType == 0) {
            settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationQuality;
        }
        settings.flashMode = flash && [output.supportedFlashModes containsObject:@(AVCaptureFlashModeOn)] ? AVCaptureFlashModeOn : AVCaptureFlashModeOff;
        AVCaptureConnection *connection = [output connectionWithMediaType:AVMediaTypeVideo];
        if ([connection isVideoRotationAngleSupported:90]) connection.videoRotationAngle = 90;
        if (connection.isVideoMirroringSupported) {
            connection.automaticallyAdjustsVideoMirroring = NO;
            connection.videoMirrored = mirrored;
        }
        [output capturePhotoWithSettings:settings delegate:delegate];
    } @catch (NSException *exception) {
        return [NSString stringWithFormat:@"このレンズ・形式・画素数で撮影できません: %@", exception.reason ?: exception.name];
    }
    return nil;
}
