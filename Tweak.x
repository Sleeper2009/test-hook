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

%hook SBFluidSwitcherItemContainerLayer
- (void)setTransform:(CATransform3D)t {
    if (gProbeActive) {
        probeLog(@"[SBFluidSwitcherItemContainerLayer setTransform:] tx=%.1f ty=%.1f sx=%.2f sy=%.2f",
                 t.m41, t.m42,
                 sqrt(t.m11*t.m11+t.m12*t.m12), sqrt(t.m21*t.m21+t.m22*t.m22));
    }
    %orig;
}
%end

%hook SBFluidSwitcherPageView
- (void)setTransform:(CGAffineTransform)t {
    if (gProbeActive) {
        probeLog(@"[SBFluidSwitcherPageView setTransform(affine):] a=%.2f b=%.2f c=%.2f d=%.2f tx=%.1f ty=%.1f",
                 t.a, t.b, t.c, t.d, t.tx, t.ty);
    }
    %orig;
}
- (void)setFrame:(CGRect)f {
    if (gProbeActive) {
        probeLog(@"[SBFluidSwitcherPageView setFrame:] %@", NSStringFromCGRect(f));
    }
    %orig;
}
%end

%hook SBFluidSwitcherContentView
- (void)setTransform:(CGAffineTransform)t {
    if (gProbeActive) {
        probeLog(@"[SBFluidSwitcherContentView setTransform(affine):] a=%.2f b=%.2f c=%.2f d=%.2f tx=%.1f ty=%.1f",
                 t.a, t.b, t.c, t.d, t.tx, t.ty);
    }
    %orig;
}
- (void)setFrame:(CGRect)f {
    if (gProbeActive) {
        probeLog(@"[SBFluidSwitcherContentView setFrame:] %@", NSStringFromCGRect(f));
    }
    %orig;
}
%end

%hook SBAppSwitcherReusableSnapshotView
- (void)setTransform:(CGAffineTransform)t {
    if (gProbeActive) {
        probeLog(@"[SBAppSwitcherReusableSnapshotView setTransform(affine):] a=%.2f b=%.2f c=%.2f d=%.2f tx=%.1f ty=%.1f",
                 t.a, t.b, t.c, t.d, t.tx, t.ty);
    }
    %orig;
}
- (void)setFrame:(CGRect)f {
    if (gProbeActive) {
        probeLog(@"[SBAppSwitcherReusableSnapshotView setFrame:] %@", NSStringFromCGRect(f));
    }
    %orig;
}
%end

%hook SBDeviceApplicationSceneView
- (void)setTransform:(CGAffineTransform)t {
    if (gProbeActive) {
        probeLog(@"[SBDeviceApplicationSceneView setTransform(affine):] a=%.2f b=%.2f c=%.2f d=%.2f tx=%.1f ty=%.1f",
                 t.a, t.b, t.c, t.d, t.tx, t.ty);
    }
    %orig;
}
- (void)setFrame:(CGRect)f {
    if (gProbeActive) {
        probeLog(@"[SBDeviceApplicationSceneView setFrame:] %@", NSStringFromCGRect(f));
    }
    %orig;
}
%end

%ctor {
    probeLog(@"=== CloseGestureProbe2 loaded ===");
}
