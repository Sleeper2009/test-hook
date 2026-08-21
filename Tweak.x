#import <UIKit/UIKit.h>

// ===== Debug log ra file — xem bằng Filza, không cần PC =====
// Log ghi vào /var/mobile/Documents/CloseGestureProbe.log
static void probeLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *path = @"/var/mobile/Documents/CloseGestureProbe.log";
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

// forward-declare để khỏi cần header thật của SpringBoard — chỉ khai đúng những
// gì mình cần gọi/đọc, không cần biết toàn bộ interface thật của class.
@interface SBFluidSwitcherGestureManager : NSObject
- (id)_deckInSwitcherPanGestureRecognizer;
@end

// ===== Hook 3 hàm built-in handler tìm được qua FLEX Runtime Browser =====
%hook SBFluidSwitcherGestureManager

- (void)_handleSwitcherPanGestureBegan:(id)gesture {
    %orig;
    UIPanGestureRecognizer *pan = gesture;
    CGPoint t = CGPointZero;
    CGPoint v = CGPointZero;
    if ([pan isKindOfClass:[UIPanGestureRecognizer class]]) {
        t = [pan translationInView:pan.view];
        v = [pan velocityInView:pan.view];
    }
    probeLog(@"BEGAN  gesture=%@ class=%@ translation=%@ velocity=%@",
             gesture, [gesture class], NSStringFromCGPoint(t), NSStringFromCGPoint(v));
}

- (void)_handleSwitcherPanGestureChanged:(id)gesture {
    %orig;
    UIPanGestureRecognizer *pan = gesture;
    CGPoint t = CGPointZero;
    CGPoint v = CGPointZero;
    if ([pan isKindOfClass:[UIPanGestureRecognizer class]]) {
        t = [pan translationInView:pan.view];
        v = [pan velocityInView:pan.view];
    }
    probeLog(@"CHANGED translation=%@ velocity=%@", NSStringFromCGPoint(t), NSStringFromCGPoint(v));
}

- (void)_handleSwitcherPanGestureEnded:(id)gesture {
    %orig;
    UIPanGestureRecognizer *pan = gesture;
    CGPoint t = CGPointZero;
    CGPoint v = CGPointZero;
    if ([pan isKindOfClass:[UIPanGestureRecognizer class]]) {
        t = [pan translationInView:pan.view];
        v = [pan velocityInView:pan.view];
    }
    probeLog(@"ENDED  translation=%@ velocity=%@", NSStringFromCGPoint(t), NSStringFromCGPoint(v));
}

// ===== 3 hàm delegate — cùng nằm trên class này (thấy trong list method FLEX),
// hook thêm để xác nhận thứ tự gọi thật so với 3 hàm built-in ở trên. Tham số
// đầu là transaction (SBFluidSwitcherGestureWorkspaceTransaction*), tham số sau
// là gesture recognizer — không cần biết type chính xác, dùng id là đủ. =====
- (void)fluidSwitcherGestureTransaction:(id)transaction didBeginGesture:(id)gesture {
    %orig;
    probeLog(@"[delegate] didBeginGesture transaction=%@ gesture=%@", [transaction class], [gesture class]);
}

- (void)fluidSwitcherGestureTransaction:(id)transaction didUpdateGesture:(id)gesture {
    %orig;
    probeLog(@"[delegate] didUpdateGesture");
}

- (void)fluidSwitcherGestureTransaction:(id)transaction didEndGesture:(id)gesture {
    %orig;
    probeLog(@"[delegate] didEndGesture");
}

%end

%ctor {
    probeLog(@"=== CloseGestureProbe loaded ===");
}
