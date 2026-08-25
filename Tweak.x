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

            [targetView.layer removeAllAnimations];
            targetView.alpha = 0.0;
            targetView.transform = CGAffineTransformMakeScale(0.85, 0.85);

            dispatch_async(dispatch_get_main_queue(), ^{
                [UIView animateWithDuration:0.05
                                      delay:0.0
                     usingSpringWithDamping:0.8
                      initialSpringVelocity:0.5
                                    options:0
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
