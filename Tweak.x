// RecordUnhide - chạy trong SpringBoard.
// Mục đích: gỡ cờ "secure" khỏi các layer/context của SpringBoard (gồm bàn phím
// nhập mật mã) để quay màn hình hiện ra bàn phím số thay vì bị che.
//
// Chưa được biên dịch hay thử trên máy thật. Các tên hàm private và giá trị
// mask 0x12 dưới đây là theo hiểu biết của mình về iOS, hãy kiểm tra bằng log.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface CAContext : NSObject
- (void)setSecure:(BOOL)secure;
@end

#define RU_DOMAIN CFSTR("com.recordunhide")
#define RULog(fmt, ...) NSLog(@"[RecordUnhide] " fmt, ##__VA_ARGS__)

// Các bit thường gặp ở disableUpdateMask của layer "secure" (như ô mật khẩu).
static const unsigned int kSecureBits = 0x12;

// Bật mặc định. Tắt bằng: defaults write com.recordunhide enabled -bool false
static BOOL RUEnabled(void) {
    Boolean exists = false;
    Boolean value = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), RU_DOMAIN, &exists);
    return exists ? (value != 0) : YES;
}

%group LayerMask
%hook CALayer
- (void)setDisableUpdateMask:(unsigned int)mask {
    if ((mask & kSecureBits) && RUEnabled()) {
        RULog(@"layer %@ mask 0x%x -> 0x%x", NSStringFromClass([self class]), mask, mask & ~kSecureBits);
        mask &= ~kSecureBits;
    }
    %orig(mask);
}
%end
%end

%group SecureContext
%hook CAContext
- (void)setSecure:(BOOL)secure {
    if (secure && RUEnabled()) {
        RULog(@"CAContext setSecure:YES -> NO");
        secure = NO;
    }
    %orig(secure);
}
%end
%end

%ctor {
    // Chỉ chạy trong SpringBoard (plist filter đã giới hạn, đây là lớp bảo hiểm).
    if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;

    // Chỉ hook khi selector thật sự tồn tại trên bản iOS này.
    if (class_getInstanceMethod(objc_getClass("CALayer"), NSSelectorFromString(@"setDisableUpdateMask:"))) {
        %init(LayerMask);
    } else {
        RULog(@"CALayer setDisableUpdateMask: not found");
    }
    if (class_getInstanceMethod(objc_getClass("CAContext"), NSSelectorFromString(@"setSecure:"))) {
        %init(SecureContext);
    } else {
        RULog(@"CAContext setSecure: not found");
    }
}
