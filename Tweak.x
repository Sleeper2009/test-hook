// Tweak.x
#import <UIKit/UIKit.h>

@interface NCNotificationShortLookViewController : UIViewController
- (id)delegate;
@end

static BOOL kEnabled = YES;

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
        if ([[className lowercaseString] containsString:@"banner"]) {

            UIView *targetView = [self view];
            CALayer *layer = targetView.layer;

            // Đổi anchorPoint sang giữa mép trên để banner "phồng ra"
            // từ 1 điểm trên đỉnh thay vì từ tâm view
            CGPoint oldAnchor = layer.anchorPoint;
            CGRect bounds = targetView.bounds;
            CGPoint newAnchor = CGPointMake(0.5, 0.0);

            CGPoint oldPos = layer.position;
            CGPoint newPos = CGPointMake(
                oldPos.x + (newAnchor.x - oldAnchor.x) * bounds.size.width,
                oldPos.y + (newAnchor.y - oldAnchor.y) * bounds.size.height
            );
            layer.anchorPoint = newAnchor;
            layer.position = newPos;

            [layer removeAllAnimations];

            // Gần như hiện rõ ngay, chỉ mờ nhẹ lúc bắt đầu (không fade từ 0)
            targetView.alpha = 0.85;
            targetView.transform = CGAffineTransformMakeScale(0.3, 0.3);

            dispatch_async(dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.35
                                      delay:0.0
                     usingSpringWithDamping:0.75
                      initialSpringVelocity:0.4
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                    targetView.alpha = 1.0;
                    targetView.transform = CGAffineTransformIdentity;
                }
                                 completion:nil];
            });
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
