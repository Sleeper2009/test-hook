// Tweak.x — RECONSTRUCTED from com.phuc.notification26 compiled dylib
// Project: 26Anim_notification
// Recovered via Mach-O + Objective-C runtime metadata analysis (symbol table,
// __objc_methname, __objc_selrefs, __cstring, __TEXT const).
//
// ⚠️ Đây là bản dựng lại gần đúng, KHÔNG PHẢI source gốc 100%:
//  - Comment gốc: mất hoàn toàn (không tồn tại trong binary sau compile)
//  - Tên biến local trong function: mất, mình đặt lại tên hợp lý
//  - Logic điều kiện chính xác (if/else order, so sánh "banner"): suy luận
//    từ thứ tự selector gọi trong __objc_methname, có thể sai thứ tự
//  - Giá trị hằng số animation (damping/velocity) ngoài 0.05 giây: KHÔNG
//    tìm thấy trong __TEXT __const → có thể là literal ARM64 immediate
//    trong instruction, cần disassembler thật (Hopper/IDA/Ghidra) để lấy
//    chính xác. Mình để placeholder TODO.

#import <UIKit/UIKit.h>

// Xác nhận từ __DATA __data: giá trị khởi tạo = 1 (YES)
static BOOL kEnabled = YES;

// Xác nhận từ symbol "_loadPrefs" + selectors:
// initWithContentsOfFile:, objectForKeyedSubscript:, boolValue
static void loadPrefs() {
    NSDictionary *prefs = [[NSDictionary alloc]
        initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.phuc.notification26.plist"];
    if (prefs) {
        id val = prefs[@"kEnabled"];
        if (val) {
            kEnabled = [val boolValue];
        }
    }
}

// Xác nhận từ __cstring: "com.phuc.notification26/reload"
static void reloadPrefsCallback(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object,
                                 CFDictionaryRef userInfo) {
    loadPrefs();
}

%hook NCNotificationShortLookViewController

// Symbol: __logos_method$_ungrouped$NCNotificationShortLookViewController$viewWillAppear$
// Có 3 block con (_block_invoke, _block_invoke_2, _block_invoke_3)
// Selectors dùng: delegate, respondsToSelector:, class, lowercaseString,
// containsString:, parentViewController, view, superview, setAlpha:,
// setTransform:, performWithoutAnimation:, layer, removeAllAnimations,
// animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:
// options:animations:completion:
- (void)viewWillAppear:(BOOL)animated {
    %orig;

    if (!kEnabled) return;

    // TODO: chưa chắc chắn 100% mục đích check này — có thể để lọc
    // notification style "banner" trước khi áp animation
    id delegateObj = [self delegate];
    if ([delegateObj respondsToSelector:@selector(class)]) {
        NSString *className = NSStringFromClass([delegateObj class]);
        if ([[className lowercaseString] containsString:@"banner"]) {

            UIView *targetView = [self view];
            UIViewController *parentVC = [self parentViewController];
            UIView *containerView = [targetView superview];

            // Block 1: reset transform/alpha trước khi chạy animation
            void (^resetBlock)(void) = ^{
                [targetView.layer removeAllAnimations];
                [targetView performWithoutAnimation:^{
                    [targetView setAlpha:0.0];
                    [targetView setTransform:CGAffineTransformMakeScale(0.85, 0.85)];
                }];
            };

            // Block 2: animation chính — spring scale + fade in
            // TODO: damping / initialSpringVelocity thật lấy từ __TEXT __const
            // chỉ tìm được 1 double = 0.05 (nhiều khả năng là "duration")
            void (^animBlock)(void) = ^{
                [UIView animateWithDuration:0.05
                                      delay:0.0
                     usingSpringWithDamping:0.8   // TODO: giá trị đoán, cần verify
                      initialSpringVelocity:0.5   // TODO: giá trị đoán, cần verify
                                    options:0
                                 animations:^{
                    [targetView setAlpha:1.0];
                    [targetView setTransform:CGAffineTransformIdentity];
                }
                                 completion:^(BOOL finished) {
                    // Block 3: completion callback
                }];
            };

            resetBlock();
            dispatch_async(dispatch_get_main_queue(), animBlock);
        }
    }
}

// Symbol: __logos_method$_ungrouped$NCNotificationShortLookViewController$viewDidAppear$
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!kEnabled) return;
    // TODO: thân hàm không để lại nhiều dấu vết symbol riêng —
    // có thể chỉ gọi lại logic tương tự viewWillAppear hoặc rỗng thêm log
}

%end

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)reloadPrefsCallback,
        CFSTR("com.phuc.notification26/reload"),
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );
}
