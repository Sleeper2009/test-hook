#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface SBDeviceApplicationSceneView : UIView
@end

// ===================================================================================
// PROBE #5 — chỉ để ĐO, trả lời 2 câu hỏi:
//   (a) SBDeviceApplicationSceneView (view thật của app) có bị hệ thống gỡ khỏi window
//       trong lúc kéo tay vuốt-lên-đóng-app không, hay vẫn còn sống?
//   (b) Sau khi buông tay xác nhận đóng, hệ thống còn animate transform NGẦM (không
//       qua -setTransform: tường minh) hay dừng hẳn tại điểm buông tay?
// ===================================================================================

#define LM_DEBUG 1
static void lmLog(NSString *fmt, ...) {
#if LM_DEBUG
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *path = @"/var/mobile/Documents/LiquidMorph.log";
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [NSDate date], msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!fh) {
        [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
        fh = [NSFileHandle fileHandleForWritingAtPath:path];
    }
    [fh seekToEndOfFile];
    [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    [fh closeFile];
#endif
}

// ----- Theo dõi view thật (SBDeviceApplicationSceneView) của app đang mở -----
static __weak SBDeviceApplicationSceneView *gProbeActiveSceneView = nil;
static CFAbsoluteTime gProbeGestureBeganAt = 0;

// ----- Theo dõi các CALayer dạng snapshot (ItemContainerLayer) -----
static NSMutableArray *gProbeTrackedLayers = nil;

static void ProbePollPresentationLayers(NSInteger tick) {
    if (tick == 0) {
        gProbeTrackedLayers = [NSMutableArray array];
    }
    if (tick >= 90) { // ~90 * 16ms ≈ 1.5s sau khi buông tay
        lmLog(@"[probe5] POLL kết thúc sau ~1.5s, dừng theo dõi.");
        gProbeTrackedLayers = nil;
        return;
    }
    for (CALayer *layer in gProbeTrackedLayers) {
        CALayer *pres = layer.presentationLayer;
        if (!pres) continue;
        CATransform3D t = pres.transform;
        lmLog(@"[probe5] POLL#%ld layer=%p tick=%.0fms tx=%.2f ty=%.2f sx=%.3f sy=%.3f m34=%.5f",
              (long)tick, layer, tick*16.0, t.m41, t.m42, t.m11, t.m22, t.m34);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ProbePollPresentationLayers(tick + 1);
    });
}

%hook CALayer
- (void)setTransform:(CATransform3D)t {
    %orig;
    id del = self.delegate;
    if (del && [NSStringFromClass([del class]) isEqualToString:@"SBReusableSnapshotItemContainer"]) {
        if (gProbeTrackedLayers && ![gProbeTrackedLayers containsObject:self]) {
            [gProbeTrackedLayers addObject:self];
        }
        CGRect f = self.frame;
        lmLog(@"[probe5] setTransform layer=%p frame=%@ (đang co dần về icon nếu w/h -> ~60)",
              self, NSStringFromCGRect(f));
    }
}
%end

// ----- Log việc view thật bị gỡ/gắn khỏi window -----
%hook SBDeviceApplicationSceneView
- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        gProbeActiveSceneView = self;
        lmLog(@"[probe5] scene view %p GẮN vào window (bounds=%@)", self, NSStringFromCGRect(self.bounds));
    } else {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        CFAbsoluteTime deltaFromBegan = gProbeGestureBeganAt > 0 ? (now - gProbeGestureBeganAt) : -1;
        lmLog(@"[probe5] scene view %p BỊ GỠ khỏi window. deltaFromGestureBegan=%.3fs (âm nghĩa là gesture chưa bắt đầu)",
              self, deltaFromBegan);
    }
}
%end

// ----- Hook vào đúng các callback grabberTongue bạn đã dò ra trước đó -----
// LƯU Ý: nếu tên method/class trong bản probe cũ của bạn (đã ra log CloseGestureProbe*.log,
// LiquidMorph.log, ClosingProbe3.log) khác chữ ký dưới đây, hãy sửa lại cho khớp — quan
// trọng nhất là giữ đúng các dòng lmLog(...) bên trong.
%hook SBFluidSwitcherGestureManager
- (void)grabberTongueBeganPulling:(id)tongue withDistance:(CGFloat)distance andVelocity:(CGFloat)velocity andGesture:(id)gesture {
    gProbeGestureBeganAt = CFAbsoluteTimeGetCurrent();
    lmLog(@"[probe5] BEGAN. activeSceneView=%p window=%p (nil nghĩa là ĐÃ bị gỡ TRƯỚC khi gesture bắt đầu)",
          gProbeActiveSceneView, gProbeActiveSceneView.window);
    %orig;
}

- (void)grabberTongueEndedPulling:(id)tongue withDistance:(CGFloat)distance andVelocity:(CGFloat)velocity andGesture:(id)gesture {
    lmLog(@"[probe5] ENDED (trước %%orig). activeSceneView window=%p", gProbeActiveSceneView.window);
    %orig;
    lmLog(@"[probe5] ENDED (sau %%orig). activeSceneView window=%p -> bắt đầu poll 1.5s xem còn animate ngầm không",
          gProbeActiveSceneView.window);
    ProbePollPresentationLayers(0);
}

- (void)grabberTongueCanceledPulling:(id)tongue withDistance:(CGFloat)distance andVelocity:(CGFloat)velocity andGesture:(id)gesture {
    lmLog(@"[probe5] CANCELED (trước %%orig). activeSceneView window=%p", gProbeActiveSceneView.window);
    %orig;
    lmLog(@"[probe5] CANCELED (sau %%orig). activeSceneView window=%p -> bắt đầu poll 1.5s",
          gProbeActiveSceneView.window);
    ProbePollPresentationLayers(0);
}
%end

%ctor {
    lmLog(@"[probe5] tweak nạp xong, bắt đầu theo dõi.");
}
