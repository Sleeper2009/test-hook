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

    // TẠM BỎ điều kiện lọc "banner" để test animation có chạy được không.
    // Nếu thấy hiệu ứng chạy đúng, mình sẽ thêm lại điều kiện lọc sau.

    UIView *targetView = [self view];
    CALayer *layer = targetView.layer;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [layer removeAllAnimations];
    targetView.alpha = 0.85;
    targetView.transform = CGAffineTransformMakeScale(0.3, 0.3);
    [CATransaction commit];

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
