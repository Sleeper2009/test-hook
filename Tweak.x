#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface SBDeviceApplicationSceneView : UIView
@end

// ===================================================================================
// PROBE #6 — nối tiếp probe #5. Thêm câu hỏi cuối cùng:
//   (c) Trong lúc đang kéo tay (BEGAN -> ENDED), view thật (SBDeviceApplicationSceneView)
//       có đang HIỂN THỊ (alpha/hidden/opacity) song song với lớp snapshot không, hay đã
//       bị ẩn đi để nhường chỗ cho snapshot?
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
        lmLog(@"[probe6] POLL kết thúc sau ~1.5s, dừng theo dõi.");
        gProbeTrackedLayers = nil;
        return;
    }
    for (CALayer *layer in gProbeTrackedLayers) {
        CALayer *pres = layer.presentationLayer;
        if (!pres) continue;
        CATransform3D t = pres.transform;
        lmLog(@"[probe6] POLL#%ld layer=%p tick=%.0fms tx=%.2f ty=%.2f sx=%.3f sy=%.3f m34=%.5f",
              (long)tick, layer, tick*16.0, t.m41, t.m42, t.m11, t.m22, t.m34);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.016 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        ProbePollPresentationLayers(tick + 1);
    });
}

// ----- Log trạng thái hiển thị (alpha/hidden/opacity) của view thật -----
static void ProbeLogActiveViewVisibility(NSString *tag) {
    SBDeviceApplicationSceneView *v = gProbeActiveSceneView;
    if (!v) {
        lmLog(@"[probe6] %@ activeSceneView=nil (không có view để log)", tag);
        return;
    }
    CALayer *pres = v.layer.presentationLayer;
    lmLog(@"[probe6] %@ activeSceneView=%p alpha=%.3f hidden=%d layer.opacity=%.3f presentation.opacity=%.3f window=%p frame=%@",
          tag, v, v.alpha, v.hidden, v.layer.opacity,
          pres ? pres.opacity : -1.0f, v.window, NSStringFromCGRect(v.frame));
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
        lmLog(@"[probe6] snapshot setTransform layer=%p frame=%@ (đang co dần về icon nếu w/h -> ~60)",
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
        lmLog(@"[probe6] scene view %p GẮN vào window (bounds=%@) alpha=%.3f hidden=%d",
              self, NSStringFromCGRect(self.bounds), self.alpha, self.hidden);
    } else {
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        CFAbsoluteTime deltaFromBegan = gProbeGestureBeganAt > 0 ? (now - gProbeGestureBeganAt) : -1;
        lmLog(@"[probe6] scene view %p BỊ GỠ khỏi window. deltaFromGestureBegan=%.3fs (âm nghĩa là gesture chưa bắt đầu)",
              self, deltaFromBegan);
    }
}

// Bắt luôn nếu có ai đó chỉnh alpha/hidden trực tiếp trên view thật trong lúc gesture chạy —
// đây chính là bằng chứng rõ nhất cho câu hỏi (c).
- (void)setAlpha:(CGFloat)a {
    %orig;
    if (self == gProbeActiveSceneView) {
        lmLog(@"[probe6] activeSceneView setAlpha:%.3f", a);
    }
}

- (void)setHidden:(BOOL)h {
    %orig;
    if (self == gProbeActiveSceneView) {
        lmLog(@"[probe6] activeSceneView setHidden:%d", h);
    }
}
%end

// ----- Hook vào đúng các callback grabberTongue bạn đã dò ra trước đó -----
// LƯU Ý: nếu tên method/class trong bản probe cũ của bạn khác chữ ký dưới đây,
// sửa lại cho khớp — quan trọng nhất là giữ đúng các dòng lmLog(...) bên trong.
%hook SBFluidSwitcherGestureManager
- (void)grabberTongueBeganPulling:(id)tongue withDistance:(CGFloat)distance andVelocity:(CGFloat)velocity andGesture:(id)gesture {
    gProbeGestureBeganAt = CFAbsoluteTimeGetCurrent();
    lmLog(@"[probe6] BEGAN. activeSceneView=%p window=%p", gProbeActiveSceneView, gProbeActiveSceneView.window);
    ProbeLogActiveViewVisibility(@"BEGAN");
    %orig;
}

- (void)grabberTongueUpdatedPulling:(id)tongue withDistance:(CGFloat)distance andVelocity:(CGFloat)velocity andGesture:(id)gesture {
    // Chỉ log alpha/hidden ở đây, KHÔNG log transform (đã có ở %hook CALayer rồi, tránh log trùng/lụt).
    ProbeLogActiveViewVisibility([NSString stringWithFormat:@"UPDATED distance=%.2f velocity=%.2f", distance, velocity]);
    %orig;
}

- (void)grabberTongueEndedPulling:(id)tongue withDistance:(CGFloat)distance andVelocity:(CGFloat)velocity andGesture:(id)gesture {
    lmLog(@"[probe6] ENDED (trước %%orig). activeSceneView window=%p", gProbeActiveSceneView.window);
    ProbeLogActiveViewVisibility(@"ENDED (trước %orig)");
    %orig;
    lmLog(@"[probe6] ENDED (sau %%orig). activeSceneView window=%p -> bắt đầu poll 1.5s", gProbeActiveSceneView.window);
    ProbeLogActiveViewVisibility(@"ENDED (sau %orig)");
    ProbePollPresentationLayers(0);
}

- (void)grabberTongueCanceledPulling:(id)tongue withDistance:(CGFloat)distance andVelocity:(CGFloat)velocity andGesture:(id)gesture {
    lmLog(@"[probe6] CANCELED (trước %%orig). activeSceneView window=%p", gProbeActiveSceneView.window);
    ProbeLogActiveViewVisibility(@"CANCELED (trước %orig)");
    %orig;
    lmLog(@"[probe6] CANCELED (sau %%orig). activeSceneView window=%p -> bắt đầu poll 1.5s", gProbeActiveSceneView.window);
    ProbeLogActiveViewVisibility(@"CANCELED (sau %orig)");
    ProbePollPresentationLayers(0);
}
%end

%ctor {
    lmLog(@"[probe6] tweak nạp xong, bắt đầu theo dõi.");
}
