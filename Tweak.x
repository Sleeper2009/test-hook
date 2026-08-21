#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

static void probeLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *path = @"/var/mobile/Documents/CloseGestureProbe2.log";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
}

// Chỉ log trong lúc gesture đang chạy (Began -> Ended), tránh log rác lúc bình
// thường (SpringBoard tự set transform liên tục cho rất nhiều việc khác).
static BOOL gProbeActive = NO;

@interface SBFluidSwitcherGestureManager : NSObject
@end

%hook SBFluidSwitcherGestureManager
- (void)_handleSwitcherPanGestureBegan:(id)gesture {
    %orig;
    gProbeActive = YES;
    probeLog(@"=== GESTURE BEGAN — bat dau theo doi transform ===");
}
- (void)_handleSwitcherPanGestureEnded:(id)gesture {
    %orig;
    probeLog(@"=== GESTURE ENDED — ngung theo doi transform ===");
    gProbeActive = NO;
}
%end

// ===== Hook setTransform: (CALayer, dùng cho cả UIView.layer lẫn CALayer con
// riêng như SBFluidSwitcherItemContainerLayer) trên các class nghi vấn =====
#define HOOK_LAYER_TRANSFORM(CLASS_NAME) \
%hook CLASS_NAME \
- (void)setTransform:(CATransform3D)t { \
    if (gProbeActive) { \
        probeLog(@"[%s setTransform:] tx=%.1f ty=%.1f sx=%.2f sy=%.2f", \
                 #CLASS_NAME, t.m41, t.m42, \
                 sqrt(t.m11*t.m11+t.m12*t.m12), sqrt(t.m21*t.m21+t.m22*t.m22)); \
    } \
    %orig; \
} \
%end

HOOK_LAYER_TRANSFORM(SBFluidSwitcherItemContainerLayer)

// ===== Hook setTransform: (UIView, CGAffineTransform) + setFrame: trên các
// view class nghi vấn — dùng để bắt trường hợp hệ thống dùng affine transform
// hoặc đổi frame trực tiếp thay vì CATransform3D =====
#define HOOK_VIEW_TRANSFORM_FRAME(CLASS_NAME) \
%hook CLASS_NAME \
- (void)setTransform:(CGAffineTransform)t { \
    if (gProbeActive) { \
        probeLog(@"[%s setTransform(affine):] a=%.2f b=%.2f c=%.2f d=%.2f tx=%.1f ty=%.1f", \
                 #CLASS_NAME, t.a, t.b, t.c, t.d, t.tx, t.ty); \
    } \
    %orig; \
} \
- (void)setFrame:(CGRect)f { \
    if (gProbeActive) { \
        probeLog(@"[%s setFrame:] %@", #CLASS_NAME, NSStringFromCGRect(f)); \
    } \
    %orig; \
} \
%end

HOOK_VIEW_TRANSFORM_FRAME(SBFluidSwitcherPageView)
HOOK_VIEW_TRANSFORM_FRAME(SBFluidSwitcherContentView)
HOOK_VIEW_TRANSFORM_FRAME(SBAppSwitcherReusableSnapshotView)
HOOK_VIEW_TRANSFORM_FRAME(SBDeviceApplicationSceneView)

%ctor {
    probeLog(@"=== CloseGestureProbe2 loaded ===");
}
