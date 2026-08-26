// Tweak.x
#import <UIKit/UIKit.h>

@interface NCNotificationShortLookViewController : UIViewController
- (id)delegate;
@end

// ===== CÁC GIÁ TRỊ MẶC ĐỊNH (dùng khi chưa có plist hoặc thiếu key) =====
static BOOL   kEnabled          = YES;   // Bật/tắt tweak
static double kAnimDuration     = 0.35;  // Thời gian animation (giây). Càng nhỏ càng nhanh/giật, càng lớn càng chậm/mượt
static double kSpringDamping    = 0.75;  // Độ "cứng" lò xo (0.0 - 1.0). Thấp = nảy nhiều lần, cao = không nảy (mượt thẳng)
static double kSpringVelocity   = 0.4;   // Tốc độ ban đầu lúc bắt đầu animate. Cao = vọt nhanh lúc đầu rồi mới chậm lại
static double kInitialScaleX    = 0.3;   // Tỉ lệ scale ban đầu theo chiều ngang (0.0 - 1.0). Càng nhỏ, banner "nở ra" từ chấm càng nhỏ càng rõ
static double kInitialScaleY    = 0.3;   // Tỉ lệ scale ban đầu theo chiều dọc
static double kInitialAlpha     = 0.85;  // Độ mờ lúc bắt đầu (0.0 = trong suốt hẳn, 1.0 = hiện rõ luôn, không fade)
static double kAnchorPointY     = 0.0;   // Điểm neo theo chiều dọc (0.0 = mép trên, 0.5 = giữa view, 1.0 = mép dưới)
                                          // 0.0 sẽ làm banner "phồng ra" từ đỉnh, giống hiệu ứng bạn mô tả
static NSString *kFilterKeyword = @"banner"; // Từ khóa lọc tên class delegate, chỉ áp animation nếu tên class chứa từ này (không phân biệt hoa thường)

static void loadPrefs() {
    NSDictionary *prefs = [[NSDictionary alloc]
        initWithContentsOfFile:@"/var/mobile/Library/Preferences/com.phuc.notification26.plist"];
    if (!prefs) return;

    id v;
    if ((v = prefs[@"kEnabled"]))        kEnabled        = [v boolValue];
    if ((v = prefs[@"kAnimDuration"]))   kAnimDuration   = [v doubleValue];
    if ((v = prefs[@"kSpringDamping"]))  kSpringDamping  = [v doubleValue];
    if ((v = prefs[@"kSpringVelocity"])) kSpringVelocity = [v doubleValue];
    if ((v = prefs[@"kInitialScaleX"]))  kInitialScaleX  = [v doubleValue];
    if ((v = prefs[@"kInitialScaleY"]))  kInitialScaleY  = [v doubleValue];
    if ((v = prefs[@"kInitialAlpha"]))   kInitialAlpha   = [v doubleValue];
    if ((v = prefs[@"kAnchorPointY"]))   kAnchorPointY   = [v doubleValue];
    if ((v = prefs[@"kFilterKeyword"])) {
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            kFilterKeyword = v;
        }
    }
}

static void reloadPrefsCallback(CFNotificationCenterRef center, void *observer,
                                 CFStringRef name, const void *object,
                                 CFDictionaryRef userInfo) {
    loadPrefs();
}

%hook NCNotificationShortLookViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;

    if (!kEnabled) return;

    id delegateObj = [self delegate];
    if ([delegateObj respondsToSelector:@selector(class)]) {
        NSString *className = NSStringFromClass([delegateObj class]);
        if ([[className lowercaseString] containsString:[kFilterKeyword lowercaseString]]) {

            UIView *targetView = [self view];
            CALayer *layer = targetView.layer;

            // Đổi anchorPoint theo kAnchorPointY để đổi hướng "phồng ra"
            CGPoint oldAnchor = layer.anchorPoint;
            CGRect bounds = targetView.bounds;
            CGPoint newAnchor = CGPointMake(0.5, kAnchorPointY);

            CGPoint oldPos = layer.position;
            CGPoint newPos = CGPointMake(
                oldPos.x + (newAnchor.x - oldAnchor.x) * bounds.size.width,
                oldPos.y + (newAnchor.y - oldAnchor.y) * bounds.size.height
            );

            // Tắt animation ngầm để trạng thái "nhỏ sẵn" áp dụng NGAY LẬP TỨC,
            // không có frame nào hiện to trước khi animation chạy
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            layer.anchorPoint = newAnchor;
            layer.position = newPos;
            [layer removeAllAnimations];
            targetView.alpha = kInitialAlpha;
            targetView.transform = CGAffineTransformMakeScale(kInitialScaleX, kInitialScaleY);
            [CATransaction commit];

            // Chạy animation phóng to ngay trong cùng lượt runloop (không dispatch_async)
            [UIView animateWithDuration:kAnimDuration
                                  delay:0.0
                 usingSpringWithDamping:kSpringDamping
                  initialSpringVelocity:kSpringVelocity
                                options:UIViewAnimationOptionCurveEaseOut
                             animations:^{
                targetView.alpha = 1.0;
                targetView.transform = CGAffineTransformIdentity;
            }
                             completion:nil];
        }
    }
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!kEnabled) return;
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
