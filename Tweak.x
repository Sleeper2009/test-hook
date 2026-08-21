#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

@interface SBIconView : UIView
@end

@interface SBDeviceApplicationSceneView : UIView
@end

static CGRect gSourceIconFrame = (CGRect){{0,0},{0,0}};
// Vị trí icon quy đổi về UIScreen.fixedCoordinateSpace — hệ toạ độ "vật lý" của màn hình,
// KHÔNG đổi theo interface orientation. gSourceIconFrame ở trên được ghi trong hệ toạ độ của
// window SpringBoard (luôn PORTRAIT), còn app đích có thể mở LANDSCAPE -> nếu dùng thẳng
// gSourceIconFrame để tính toán trên window landscape thì lệch hệ toạ độ, icon "nhảy" sang vị
// trí sai. gSourceIconFrameFixed dùng để tính đúng bất kể 2 bên khác orientation.
static CGRect gSourceIconFrameFixed = (CGRect){{0,0},{0,0}};
static BOOL gHasSourceFrame = NO;

// Tham chiếu YẾU tới đúng icon view vừa được nhấn — dùng để cho icon THẬT xoay nhẹ sang phải
// trước khi nội dung app (HyperOS4) bắt đầu xoay. Dùng __weak để nếu icon view bị giải phóng/
// tái sử dụng bất thường thì biến này tự về nil, không giữ crash reference.
static __weak SBIconView *gPressedIconView = nil;

// ===== State cho animation ĐÓNG app (Liquid Morph ngược) =====
// gCloseGestureActive: đang trong lúc gesture vuốt-lên-đóng chạy, TA đang tự vẽ thay hệ thống.
// gCloseT: cùng ý nghĩa với t trong LMTransformAt — 1.0 = app full màn hình (lúc vừa bắt đầu
// vuốt), 0.0 = đã thu về đúng kích thước/vị trí icon. Giảm dần theo khoảng cách kéo tay lên.
static BOOL gCloseGestureActive = NO;
static CGFloat gCloseT = 1.0;
static CGRect gCloseScreen = (CGRect){{0,0},{0,0}};
// Icon đích để thu app về — chụp lại NGAY lúc gesture bắt đầu, dùng gSourceIconFrameFixed hiện
// có (do %hook SBIconView setHighlighted: ghi lại từ lần mở app gần nhất).
static CGRect gCloseIconFixed = (CGRect){{0,0},{0,0}};
static BOOL gCloseHasIcon = NO;

// Khoảng cách kéo tay (point) để coi là "kéo hết cỡ" (t đi từ 1 xuống 0). Chỉnh số này nếu
// thấy phải kéo quá xa hoặc quá gần mới hết animation.
static CGFloat const kLMCloseDragRange = 500.0;
// Ngưỡng % quãng đường (0..1) — vượt qua thì coi là ĐÓNG THẬT, dưới thì coi là HUỶ (bật lại mở).
static CGFloat const kLMCloseThreshold = 0.5;
// Vận tốc hất tay (point/s theo trục Y) — âm nhiều nghĩa là hất lên rất nhanh -> đóng luôn dù
// chưa kéo đủ xa (giống hành vi vuốt-hất của iOS thật).
static CGFloat const kLMCloseFlingVelocity = -800.0;

// Góc xoay nhẹ của ICON THẬT (không phải nội dung app) ngay khi vừa xác nhận HyperOS4 + landscape,
// xoay sang PHẢI một xíu rồi mới bắt đầu animation xoay của nội dung app.
static CGFloat const kLMIconPreRotateAngle = 0.12; // radian, ~7 độ
static NSTimeInterval const kLMIconPreRotateDuration = 0.10; // giây

static BOOL enabled = YES;
static CGFloat lgBounceAmount = 100.0;
static CGFloat lgPeakRadius = 160.0;
static CGFloat lgEndRadius = 20.0;

// 0 = Liquid Morph (mặc định cũ), 1 = HyperOS 4 (chỉ xoay khi app mở ở chế độ ngang)
static NSInteger lmEffectMode = 0;

// Tốc độ chuyển cảnh — chỉnh được bằng thanh trượt trong Settings (áp dụng cho CẢ 2 chế độ:
// Liquid Morph và HyperOS4, vì cùng dùng chung LMRunTransition). Mặc định 0.4 giây.
static CGFloat lmDuration = 0.4;

#define PREFS_DOMAIN @"com.fujb2009.appanimationprefs"
#define NOTIFY_CHANGE "com.fujb2009.appanimationprefs/reload"

// ===== Debug log ra file — xem bằng Filza, không cần PC =====
// Bật/tắt bằng LM_DEBUG. Log ghi vào /var/mobile/Documents/LiquidMorph.log
// (path này là thật trên disk, không cần prefix /var/jb/ dù bạn dùng rootless).
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

static void loadPrefs() {
    CFPreferencesAppSynchronize((__bridge CFStringRef)PREFS_DOMAIN);

    Boolean keyExists;
    Boolean enabledValue = CFPreferencesGetAppBooleanValue(CFSTR("enabled"), (__bridge CFStringRef)PREFS_DOMAIN, &keyExists);
    enabled = keyExists ? (BOOL)enabledValue : YES;

    // LƯU Ý QUAN TRỌNG: nút "Đặt lại về mặc định" của PreferenceLoader XOÁ hẳn key khỏi
    // prefs (không ghi lại giá trị mặc định) -> nếu key không tồn tại, CFPreferencesCopyAppValue
    // trả về NULL. Trước đây chỉ update biến khi có giá trị -> reset không có tác dụng.
    // Giờ LUÔN set về default trước, rồi mới ghi đè nếu key có tồn tại.
    lgBounceAmount = 100.0;
    CFPropertyListRef bv = CFPreferencesCopyAppValue(CFSTR("lgBounceAmount"), (__bridge CFStringRef)PREFS_DOMAIN);
    if (bv) { if (CFGetTypeID(bv)==CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)bv, kCFNumberDoubleType, &lgBounceAmount); CFRelease(bv); }

    lgPeakRadius = 160.0;
    CFPropertyListRef pv = CFPreferencesCopyAppValue(CFSTR("lgPeakRadius"), (__bridge CFStringRef)PREFS_DOMAIN);
    if (pv) { if (CFGetTypeID(pv)==CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)pv, kCFNumberDoubleType, &lgPeakRadius); CFRelease(pv); }

    lgEndRadius = 20.0;
    CFPropertyListRef ev = CFPreferencesCopyAppValue(CFSTR("lgEndRadius"), (__bridge CFStringRef)PREFS_DOMAIN);
    if (ev) { if (CFGetTypeID(ev)==CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)ev, kCFNumberDoubleType, &lgEndRadius); CFRelease(ev); }

    lmEffectMode = 0;
    CFPropertyListRef mv = CFPreferencesCopyAppValue(CFSTR("lmEffectMode"), (__bridge CFStringRef)PREFS_DOMAIN);
    if (mv) { if (CFGetTypeID(mv)==CFNumberGetTypeID()) { int m=0; CFNumberGetValue((CFNumberRef)mv, kCFNumberIntType, &m); lmEffectMode = m; } CFRelease(mv); }

    lmDuration = 0.4;
    CFPropertyListRef dv = CFPreferencesCopyAppValue(CFSTR("lmDuration"), (__bridge CFStringRef)PREFS_DOMAIN);
    if (dv) { if (CFGetTypeID(dv)==CFNumberGetTypeID()) CFNumberGetValue((CFNumberRef)dv, kCFNumberDoubleType, &lmDuration); CFRelease(dv); }
}

static NSTimeInterval getDuration() {
    return lmDuration;
}

// ===== Chế độ "Liquid Morph": icon phóng to + nghiêng nhẹ theo vị trí, bo góc chạy mượt =====
static CATransform3D LMTransformAt(CGFloat t, CGRect icon, CGRect screen) {
    CGFloat sw = screen.size.width, sh = screen.size.height;
    CGFloat cx = CGRectGetMidX(icon), cy = CGRectGetMidY(icon);
    CGFloat nx = (cx - sw/2)/( sw/2), ny = (cy - sh/2)/(sh/2);
    nx = MAX(-1,MIN(1,nx)); ny = MAX(-1,MIN(1,ny));
    CGFloat sx = MAX(0.05, icon.size.width/sw), sy = MAX(0.05, icon.size.height/sh);
    CGFloat e = 1.0 - powf(1.0-t, 3.0);
    CGFloat tilt = powf(1.0-t, 1.6) * 0.85;
    CGFloat bounce = sinf(MIN(t,1.0)*M_PI) * (lgBounceAmount/100.0) * 38.0 * (cy > sh/2 ? -1:1);

    CATransform3D tr = CATransform3DIdentity;
    tr.m34 = -1.0/500.0;
    tr = CATransform3DTranslate(tr, (cx-sw/2)*(1-e), (cy-sh/2)*(1-e)+bounce*(1-e), 0);

    CGFloat halfH = sh/2.0;
    CGFloat pivotY = (ny > 0) ? -halfH : halfH;
    tr = CATransform3DTranslate(tr, 0, pivotY, 0);
    tr = CATransform3DRotate(tr, -ny*tilt, 1,0,0);
    tr = CATransform3DTranslate(tr, 0, -pivotY, 0);

    tr = CATransform3DRotate(tr, nx*tilt, 0,1,0);

    tr = CATransform3DScale(tr, sx+(1-sx)*e, sy+(1-sy)*e, 1);
    return tr;
}

// ===== Chế độ "HyperOS 4": icon QUAY (xoay quanh trục Z) từ dọc -> full màn hình ngang =====
// LUÔN xoay THEO CHIỀU KIM ĐỒNG HỒ, bất kể icon nằm bên trái hay bên phải màn hình
// (đã bỏ cơ chế đổi chiều theo vị trí icon trước đây).
// LƯU Ý: quy ước "dấu dương = xoay theo chiều kim đồng hồ" dựa theo hệ toạ độ layer chuẩn của
// UIKit/CoreAnimation. Nếu build lên thấy bị NGƯỢC (ra ngược chiều kim đồng hồ),
// đổi dấu hằng số kLMRotateBaseSign bên dưới (1.0 <-> -1.0) là đảo lại đúng.
static CGFloat const kLMRotateBaseSign = -1.0; // ĐÃ ĐẢO DẤU: trước xoay lệch sang trái, giờ xoay sang phải theo đúng yêu cầu

static CGFloat LMRotateSignForIcon(CGRect icon, CGRect screen) {
    (void)icon; (void)screen; // không còn phụ thuộc vị trí icon nữa, giữ tham số để khỏi phải sửa nơi gọi
    return kLMRotateBaseSign; // luôn xoay theo chiều kim đồng hồ
}

// Chia làm 2 giai đoạn đúng như yêu cầu:
// - Giai đoạn 1 (0 -> kLMPreRotatePhase): app CHƯA phóng to hẳn, chỉ xoay MỘT ÍT
//   và phình to xíu tại chỗ (cảm giác vừa chạm là xoay+phồng nhẹ trước).
// - Giai đoạn 2 (kLMPreRotatePhase -> 1): nội dung thật của app (đã hiển thị, cùng
//   kích thước icon từ cuối giai đoạn 1) vừa xoay nốt phần còn lại vừa phóng to dần
//   cho tới khi lấp đầy màn hình.
// Chỉnh các hằng số dưới đây nếu muốn pha đầu dài/ngắn, xoay nhiều/ít, phình to nhiều/ít hơn.
static CGFloat const kLMPreRotatePhase  = 0.55; // % thời lượng animation dành cho pha xoay nhẹ ban đầu (đã kéo dài, trước là 0.30)
static CGFloat const kLMPreRotateAmount = 0.45; // pha 1 xoay hết bao nhiêu % trong tổng góc 90°
static CGFloat const kLMPreScaleAmount  = 0.18; // pha 1 phóng to trước bao nhiêu % (0..1) trên tổng quãng phóng to

static CATransform3D LMTransformHyperOS4At(CGFloat t, CGRect icon, CGRect screen) {
    CGFloat sw = screen.size.width, sh = screen.size.height;
    CGFloat cx = CGRectGetMidX(icon), cy = CGRectGetMidY(icon);

    // Vì sẽ xoay 90°, kích thước "nhìn thấy" của icon bị hoán đổi w/h so với màn hình đích
    CGFloat sx = MAX(0.05, icon.size.height / sw);
    CGFloat sy = MAX(0.05, icon.size.width  / sh);

    // t=0: xoay 90° (đúng bằng góc icon dọc lệch so với màn hình ngang), kích thước = icon
    // t=1: xoay về 0° -> app hiển thị đúng chiều ngang, full màn hình
    CGFloat rotateSign = LMRotateSignForIcon(icon, screen); // luôn xoay theo chiều kim đồng hồ
    CGFloat fullAngle = rotateSign * (CGFloat)M_PI_2;
    CGFloat preRotatedAngle = fullAngle * (1.0 - kLMPreRotateAmount); // góc còn lại sau pha 1

    CGFloat e, rotateZ;
    if (t <= kLMPreRotatePhase) {
        // ----- Giai đoạn 1: xoay nhẹ + phình to xíu tại chỗ (chưa phóng to hẳn) -----
        CGFloat lt = t / kLMPreRotatePhase;
        CGFloat le = 1.0 - powf(1.0 - lt, 2.0); // ease-out: xoay dứt khoát rồi khựng lại nhẹ
        e = kLMPreScaleAmount * le;             // phóng to một chút thay vì đứng im hẳn
        rotateZ = fullAngle + (preRotatedAngle - fullAngle) * le;
    } else {
        // ----- Giai đoạn 2: nội dung app vừa xoay nốt vừa phóng to phần lớn còn lại tới full màn hình -----
        CGFloat lt = (t - kLMPreRotatePhase) / (1.0 - kLMPreRotatePhase);
        // Dùng smoothstep (3lt²-2lt³) thay vì ease-out bậc 3: vận tốc = 0 ở CẢ 2 đầu (lt=0 và lt=1).
        // Pha 1 kết thúc với vận tốc ~0 -> pha 2 phải BẮT ĐẦU cũng bằng vận tốc ~0 thì mới liền mạch,
        // không bị khựng. Trước đây ease-out bậc 3 bắt đầu với vận tốc cực đại ngay lt=0 -> giật cục.
        CGFloat le2 = lt*lt*(3.0 - 2.0*lt);
        e = kLMPreScaleAmount + (1.0 - kLMPreScaleAmount) * le2; // tiếp nối từ mốc cuối pha 1 lên 1.0
        rotateZ = preRotatedAngle * (1.0 - le2); // xoay nốt về 0° trong lúc phóng to
    }

    CATransform3D tr = CATransform3DIdentity;
    tr.m34 = -1.0/900.0; // perspective nhẹ cho có chiều sâu

    // BUG ĐÃ SỬA (trục xoay lệch): trước đây thứ tự gọi là Translate -> Rotate -> Scale.
    // Theo ngữ nghĩa CATransform3DTranslate/Rotate/Scale, thao tác gọi TRƯỚC được áp dụng
    // TRƯỚC lên điểm cục bộ (gần layer nhất), thao tác gọi SAU CÙNG là thao tác NGOÀI CÙNG
    // (áp dụng sau, trong hệ toạ độ đã bị các thao tác trước biến đổi).
    // -> Gọi Translate trước khiến nó vô tình bị Rotate ở bước sau "cuốn" theo, làm khối nội
    // dung vừa xoay vừa lượn quanh một tâm lệch hẳn ra xa (tâm màn hình full-size), chứ không
    // phải quay quanh tâm của chính nó -> xoay ra hình thoi/góc chéo, bay theo đường cong.
    //
    // Thứ tự ĐÚNG: Scale -> Rotate -> Translate (gọi hàm đúng theo thứ tự này).
    // -> Scale và Rotate gọi TRƯỚC nên luôn co giãn/xoay quanh gốc toạ độ local, tức đúng bằng
    // tâm của chính layer (anchorPoint mặc định 0.5,0.5) -> tại t=0, sau khi scale (đã hoán đổi
    // sẵn w/h để bù cho việc xoay 90°) rồi rotate đúng 90°, khối nội dung trở về đúng kích
    // thước icon THẬT, 4 cạnh song song 4 lề màn hình — không còn bị chéo góc.
    // -> Translate gọi SAU CÙNG chỉ "khiêng" khối đã xoay/scale xong tới đúng vị trí trên màn
    // hình, không còn ảnh hưởng gì tới trục xoay/scale nữa. Vì (cx-sw/2)*(1-e) và (cy-sh/2)*(1-e)
    // giảm dần về 0 cùng lúc với rotateZ giảm dần về 0 (cùng dùng chung mốc le2/e ở trên), nên
    // tâm xoay sẽ tự động "trôi" dần từ đúng vị trí icon (kể cả icon nằm sát mép trên/dưới màn
    // hình) về đúng tâm màn hình, và khi xoay đủ 90° thì cũng vừa lúc áp thẳng vào đúng layout
    // màn hình ngang — không cần thêm cơ chế tính toán riêng nào khác.
    tr = CATransform3DScale(tr, sx+(1-sx)*e, sy+(1-sy)*e, 1);
    tr = CATransform3DRotate(tr, rotateZ, 0, 0, 1);
    tr = CATransform3DTranslate(tr, (cx-sw/2)*(1-e), (cy-sh/2)*(1-e), 0);
    return tr;
}

static CGFloat LMRadius(CGFloat t) {
    CGFloat peak = lgPeakRadius, end = lgEndRadius, icon = 13.0;
    if (t < 0.45) return icon + (peak-icon)*(t/0.45);
    CGFloat l = (t-0.45)/0.55; if(l>1)l=1;
    return peak + (end-peak)*l;
}

// ===== Phát hiện icon ở 4 góc và "dịch giả lập" vào vị trí cột/hàng thứ 2 =====
// Chỉnh các số này theo layout máy bạn khi test
static CGFloat const kLMCornerMarginX  = 100.0; // cách mép trái/phải bao nhiêu pt thì tính là "góc"
static CGFloat const kLMCornerMarginYTop = 160.0; // cách mép trên bao nhiêu pt thì tính là "góc trên"
static CGFloat const kLMDockHeight = 130.0; // chiều cao vùng dock, loại khỏi "góc dưới"
static CGFloat const kLMCornerMarginYBottom = 160.0; // từ đỉnh dock tính ngược lên bao nhiêu pt
static CGFloat const kLMGridStepX = 85.0;  // khoảng cách 1 cột icon theo chiều ngang — chỉnh theo layout máy bạn
static CGFloat const kLMGridStepY = 95.0;  // khoảng cách 1 hàng icon theo chiều dọc — chỉnh theo layout máy bạn

static CGRect LMAdjustedIconFrame(CGRect icon, CGRect screen) {
    CGFloat sw = screen.size.width, sh = screen.size.height;
    CGFloat cx = CGRectGetMidX(icon), cy = CGRectGetMidY(icon);
    BOOL isLeft  = cx < kLMCornerMarginX;
    BOOL isRight = cx > (sw - kLMCornerMarginX);
    BOOL isTop   = cy < kLMCornerMarginYTop;
    CGFloat dockTop = sh - kLMDockHeight;
    BOOL isBottom = (cy < dockTop) && (cy > dockTop - kLMCornerMarginYBottom);

    BOOL isCorner = (isTop || isBottom) && (isLeft || isRight);
    if (!isCorner) return icon; // không phải góc -> giữ nguyên, dùng animation như cũ

    CGRect adjusted = icon;
    if (isLeft)  adjusted.origin.x += kLMGridStepX;  // dịch vào trong 1 cột
    if (isRight) adjusted.origin.x -= kLMGridStepX;  // dịch vào trong 1 cột
    if (isTop)   adjusted.origin.y += kLMGridStepY;  // dịch vào trong 1 hàng
    if (isBottom) adjusted.origin.y -= kLMGridStepY;
    return adjusted;
}

// ===== Nhận biết app đang mở có phải đang ở chế độ màn hình ngang không =====
static BOOL LMIsLandscapeScene(UIWindow *window) {
    if (!window) return NO;
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = window.windowScene;
        if (scene) {
            return UIInterfaceOrientationIsLandscape(scene.interfaceOrientation);
        }
    }
    CGRect b = window.bounds;
    return b.size.width > b.size.height;
}

// forward declaration vì LMPollForLandscape gọi LMRunTransition (định nghĩa ở dưới)
static void LMRunTransition(SBDeviceApplicationSceneView *view, BOOL useHyperOS4Spin);

// ===== Kiểm tra lặp lại xem app sắp mở có phải landscape không =====
// self.window ở đây là window của SpringBoard, không phải window thật của app đang mở
// -> chỉ check windowScene.interfaceOrientation thôi sẽ không phát hiện được landscape.
// Nên check thêm cả self.bounds và thử lại nhiều lần.
static void LMPollForLandscape(SBDeviceApplicationSceneView *view, CGRect capturedIconFrameFixed, BOOL hadSourceFrame, NSInteger attempt) {
    if (!view.window) { lmLog(@"poll#%ld: view mất window, dừng", (long)attempt); return; }

    CGRect b = view.bounds;
    BOOL landscapeBounds = b.size.width > b.size.height;
    BOOL landscapeScene = LMIsLandscapeScene(view.window);
    lmLog(@"poll#%ld bounds=%@ landscapeBounds=%d landscapeScene(window)=%d",
          (long)attempt, NSStringFromCGRect(b), landscapeBounds, landscapeScene);

    if (landscapeBounds || landscapeScene) {
        lmLog(@"poll#%ld -> phát hiện NGANG, chạy hiệu ứng HyperOS4", (long)attempt);
        // Truyền frame theo fixedCoordinateSpace — LMRunTransition sẽ tự quy đổi sang đúng
        // hệ toạ độ (landscape) của view.window ngay trước khi build animation.
        gSourceIconFrameFixed = capturedIconFrameFixed;
        gHasSourceFrame = hadSourceFrame;

        // Cho ICON THẬT xoay nhẹ sang phải một xíu TRƯỚC, rồi mới bắt đầu animation xoay của
        // nội dung app. Chỉ làm việc này ở ĐÂY (sau khi đã xác nhận chắc chắn là HyperOS4 +
        // landscape) — KHÔNG làm ngay lúc setHighlighted, vì lúc đó chưa biết app sắp mở
        // dọc hay ngang (xem giải thích trong %hook SBIconView).
        SBIconView *iconV = gPressedIconView;
        if (iconV) {
            [CATransaction begin];
            [CATransaction setAnimationDuration:kLMIconPreRotateDuration];
            [CATransaction setAnimationTimingFunction:
                [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            iconV.transform = CGAffineTransformMakeRotation(kLMIconPreRotateAngle);
            [CATransaction commit];

            // LUÔN ép icon về lại identity sau đúng kLMIconPreRotateDuration, bất kể app đã mở
            // xong hay chưa. Đây là bài học từ bug cũ (icon view được SpringBoard TÁI SỬ DỤNG,
            // không tạo mới mỗi lần) — nếu animation bị cắt giữa chừng mà không ép về identity,
            // icon sẽ "kẹt" lại transform dở dang, lần sau hiện ra bị lệch/nghiêng.
            __weak SBIconView *weakIcon = iconV;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kLMIconPreRotateDuration*NSEC_PER_SEC)),
                dispatch_get_main_queue(), ^{
                    SBIconView *strongIcon = weakIcon;
                    if (strongIcon) strongIcon.transform = CGAffineTransformIdentity;
                    LMRunTransition(view, YES);
                });
            return;
        }

        LMRunTransition(view, YES);
        return;
    }
    if (attempt >= 6) {
        lmLog(@"poll#%ld -> hết lượt thử (~0.5s), coi là app dọc, KHÔNG can thiệp gì (giữ hành vi mặc định)", (long)attempt);
        // Không pin, không animate gì hết -> app dọc giữ nguyên animation mặc định của hệ thống.
        return;
    }
    __weak SBDeviceApplicationSceneView *weakView = view;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SBDeviceApplicationSceneView *strongView = weakView;
        if (strongView) LMPollForLandscape(strongView, capturedIconFrameFixed, hadSourceFrame, attempt + 1);
    });
}

// ===== Chạy animation chuyển cảnh (dùng chung cho cả 2 chế độ) =====
static void LMRunTransition(SBDeviceApplicationSceneView *view, BOOL useHyperOS4Spin) {
    if (!view.window) { gHasSourceFrame = NO; return; }

    NSTimeInterval dur = getDuration();
    // QUAN TRỌNG: không dùng [UIScreen mainScreen].bounds ở đây — trên iOS, UIScreen.bounds
    // KHÔNG tự xoay theo hướng hiện tại của máy (vẫn giữ hệ toạ độ "gốc" dù màn hình đang ngang),
    // trong khi icon frame lại được ghi theo hệ toạ độ cửa sổ lúc bấm (đã đúng hướng thật).
    // Nếu 2 bên lệch hệ toạ độ -> tỉ lệ scale/translate bị sai -> nhìn như app "tự dưng full màn
    // hình" thay vì phóng to dần đúng từ vị trí icon. Dùng view.window.bounds (đã đúng hướng
    // thật tại thời điểm chạy animation) để chắc chắn khớp.
    CGRect screen = view.window ? view.window.bounds : [UIScreen mainScreen].bounds;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    [view.layer removeAllAnimations];
    view.layer.mask = nil;
    view.layer.filters = nil;
    [CATransaction commit];
    view.frame = screen;
    view.alpha = 1.0;
    view.layer.masksToBounds = YES;
    view.layer.cornerCurve = kCACornerCurveContinuous;

    // BUG ĐÃ SỬA: gSourceIconFrame (cũ) được ghi theo hệ toạ độ window SpringBoard — LUÔN PORTRAIT.
    // Khi app đích mở LANDSCAPE, "screen" ở trên là window landscape (vd 736x414) trong khi icon cũ
    // vẫn mang toạ độ portrait (vd trong khung 414x736) -> cx/cy tính sai hoàn toàn -> icon "xoay từ
    // một vị trí khác". Sửa bằng cách quy đổi gSourceIconFrameFixed (đã lưu theo
    // UIScreen.fixedCoordinateSpace, bất biến theo orientation) VỀ ĐÚNG hệ toạ độ của view.window
    // TẠI THỜI ĐIỂM chạy animation — dùng đúng API convertRect:fromCoordinateSpace: nên luôn đúng
    // dù app mở portrait hay landscape, xoay trái hay phải.
    CGRect rawIcon;
    if (gHasSourceFrame) {
        UIScreen *scr = view.window.screen ?: [UIScreen mainScreen];
        rawIcon = [view.window convertRect:gSourceIconFrameFixed fromCoordinateSpace:scr.fixedCoordinateSpace];
        lmLog(@"LMRunTransition: frameFixed=%@ -> rawIcon(trong window hiện tại)=%@ screen=%@",
              NSStringFromCGRect(gSourceIconFrameFixed), NSStringFromCGRect(rawIcon), NSStringFromCGRect(screen));
    } else {
        rawIcon = CGRectMake(screen.size.width/2-30, screen.size.height/2-30, 60, 60);
    }
    CGRect icon = LMAdjustedIconFrame(rawIcon, screen); // <- dùng vị trí đã "giả lập cột/hàng thứ 2" nếu là góc

    NSInteger steps = useHyperOS4Spin ? 48 : 30; // HyperOS4 cần nhiều mốc hơn để pha 1 (chỉ ~30% thời lượng) không bị răng cưa
    NSMutableArray *trs = [NSMutableArray array];
    NSMutableArray *rads = [NSMutableArray array];
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat t = (CGFloat)i/steps;
        CATransform3D tr = useHyperOS4Spin ? LMTransformHyperOS4At(t, icon, screen) : LMTransformAt(t, icon, screen);
        [trs addObject:[NSValue valueWithCATransform3D:tr]];
        [rads addObject:@(LMRadius(t))];
    }
    CAKeyframeAnimation *ta = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    ta.values = trs; ta.duration = dur;
    ta.timingFunction = [CAMediaTimingFunction functionWithName:
        useHyperOS4Spin ? kCAMediaTimingFunctionLinear : kCAMediaTimingFunctionEaseInEaseOut];
    ta.fillMode = kCAFillModeForwards; ta.removedOnCompletion = NO;
    [view.layer addAnimation:ta forKey:@"lm_t"];
    view.layer.transform = [trs.lastObject CATransform3DValue];

    CAKeyframeAnimation *ra = [CAKeyframeAnimation animationWithKeyPath:@"cornerRadius"];
    ra.values = rads; ra.duration = dur;
    ra.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    ra.fillMode = kCAFillModeForwards; ra.removedOnCompletion = NO;
    [view.layer addAnimation:ra forKey:@"lm_r"];
    view.layer.cornerRadius = [rads.lastObject floatValue];

    CABasicAnimation *fa = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fa.fromValue = @0.0; fa.toValue = @1.0;
    fa.duration = dur*0.18; fa.removedOnCompletion = YES;
    [view.layer addAnimation:fa forKey:@"lm_f"];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)((dur+0.05)*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        view.layer.masksToBounds = NO;
        view.layer.cornerRadius = 0;
        view.layer.transform = CATransform3DIdentity;
        gHasSourceFrame = NO;
    });
}

%hook SBIconView
- (void)setHighlighted:(BOOL)h {
    %orig;
    if (!enabled || !h) return;
    UIWindow *w = self.window;
    if (w && CGRectGetWidth(self.bounds)>0) {
        CGRect frameInWindow = [self convertRect:self.bounds toView:w];
        gSourceIconFrame = frameInWindow; // giữ lại (không dùng cho HyperOS4 nữa, tránh phá code cũ)

        // Quy đổi sang fixedCoordinateSpace của màn hình NGAY LÚC CHẠM — bất kể app sắp mở
        // là portrait hay landscape, giá trị này luôn đúng vị trí vật lý của icon trên màn hình.
        UIScreen *scr = w.screen ?: [UIScreen mainScreen];
        gSourceIconFrameFixed = [w convertRect:frameInWindow toCoordinateSpace:scr.fixedCoordinateSpace];
        gHasSourceFrame = YES;
        gPressedIconView = self; // lưu lại đúng icon view này để có thể cho nó xoay nhẹ (nếu HyperOS4 + landscape)
        lmLog(@"icon highlighted: frameInWindow=%@ frameFixed=%@", NSStringFromCGRect(frameInWindow), NSStringFromCGRect(gSourceIconFrameFixed));
    }
}
%end

%hook SBDeviceApplicationSceneView
- (void)didMoveToWindow {
    %orig;
    if (!enabled || !self.window) return;

    if (lmEffectMode == 1) {
        lmLog(@"didMoveToWindow: bắt đầu poll landscape (không pin trước), bounds ban đầu=%@", NSStringFromCGRect(self.bounds));
        LMPollForLandscape(self, gSourceIconFrameFixed, gHasSourceFrame, 0);
        return;
    }

    LMRunTransition(self, NO);
}
%end

// ============================================================================
// ===== ANIMATION ĐÓNG APP (Liquid Morph ngược) =====
// ============================================================================
// Tìm được qua FLEX Runtime Browser + hook log thực tế trên máy:
// - SBFluidSwitcherGestureManager: _handleSwitcherPanGesture{Began,Changed,Ended}:
//   nhận UIPanGestureRecognizer, cho translation/velocity theo point kéo tay.
// - SBFluidSwitcherItemContainerLayer: layer thật bị hệ thống tự scale khi vuốt
//   (setTransform:, chỉ scale quanh tâm, không dịch chuyển). Đây là layer mình cần
//   "cướp quyền vẽ" để thay bằng animation Liquid Morph ngược.

@interface SBFluidSwitcherGestureManager : NSObject
@end

@interface SBFluidSwitcherItemContainerLayer : CALayer
@end

// Chạy nốt animation ĐÓNG THẬT — từ gCloseT hiện tại giảm dần về 0 (icon).
static void LMRunCloseFinish(CALayer *layer) {
    if (!layer) { gCloseGestureActive = NO; return; }
    CGRect icon = gCloseHasIcon ? LMAdjustedIconFrame(gCloseIconFixed, gCloseScreen)
                                 : CGRectMake(gCloseScreen.size.width/2-30, gCloseScreen.size.height/2-30, 60, 60);
    CGRect screen = gCloseScreen;
    CGFloat fromT = gCloseT;
    NSTimeInterval dur = getDuration() * MAX(0.15, fromT);

    NSInteger steps = 30;
    NSMutableArray *trs = [NSMutableArray array];
    NSMutableArray *rads = [NSMutableArray array];
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat lt = (CGFloat)i/steps;
        CGFloat t = fromT * (1.0 - lt); // fromT -> 0
        [trs addObject:[NSValue valueWithCATransform3D:LMTransformAt(t, icon, screen)]];
        [rads addObject:@(LMRadius(t))];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CAKeyframeAnimation *ta = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    ta.values = trs; ta.duration = dur;
    ta.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    ta.fillMode = kCAFillModeForwards; ta.removedOnCompletion = NO;
    [layer addAnimation:ta forKey:@"lm_close_t"];
    layer.transform = [trs.lastObject CATransform3DValue];

    CAKeyframeAnimation *ra = [CAKeyframeAnimation animationWithKeyPath:@"cornerRadius"];
    ra.values = rads; ra.duration = dur;
    ra.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseIn];
    ra.fillMode = kCAFillModeForwards; ra.removedOnCompletion = NO;
    [layer addAnimation:ra forKey:@"lm_close_r"];
    layer.cornerRadius = [rads.lastObject floatValue];
    [CATransaction commit];

    lmLog(@"LMRunCloseFinish: fromT=%.3f dur=%.2f icon=%@", fromT, dur, NSStringFromCGRect(icon));

    __weak CALayer *weakLayer = layer;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((dur+0.05)*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CALayer *strongLayer = weakLayer;
        if (strongLayer) {
            strongLayer.cornerRadius = 0;
            strongLayer.transform = CATransform3DIdentity;
        }
        gCloseGestureActive = NO;
    });
}

// Chạy animation HUỶ đóng — bật ngược lại từ gCloseT hiện tại lên 1.0 (full màn hình).
static void LMRunCloseCancel(CALayer *layer) {
    if (!layer) { gCloseGestureActive = NO; return; }
    CGRect icon = gCloseHasIcon ? LMAdjustedIconFrame(gCloseIconFixed, gCloseScreen)
                                 : CGRectMake(gCloseScreen.size.width/2-30, gCloseScreen.size.height/2-30, 60, 60);
    CGRect screen = gCloseScreen;
    CGFloat fromT = gCloseT;
    NSTimeInterval dur = 0.28;

    NSInteger steps = 24;
    NSMutableArray *trs = [NSMutableArray array];
    NSMutableArray *rads = [NSMutableArray array];
    for (NSInteger i = 0; i <= steps; i++) {
        CGFloat lt = (CGFloat)i/steps;
        CGFloat t = fromT + (1.0 - fromT) * lt; // fromT -> 1
        [trs addObject:[NSValue valueWithCATransform3D:LMTransformAt(t, icon, screen)]];
        [rads addObject:@(LMRadius(t))];
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CAKeyframeAnimation *ta = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    ta.values = trs; ta.duration = dur;
    ta.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    ta.fillMode = kCAFillModeForwards; ta.removedOnCompletion = NO;
    [layer addAnimation:ta forKey:@"lm_close_t"];
    layer.transform = [trs.lastObject CATransform3DValue];

    CAKeyframeAnimation *ra = [CAKeyframeAnimation animationWithKeyPath:@"cornerRadius"];
    ra.values = rads; ra.duration = dur;
    ra.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    ra.fillMode = kCAFillModeForwards; ra.removedOnCompletion = NO;
    [layer addAnimation:ra forKey:@"lm_close_r"];
    layer.cornerRadius = [rads.lastObject floatValue];
    [CATransaction commit];

    lmLog(@"LMRunCloseCancel: fromT=%.3f dur=%.2f", fromT, dur);

    __weak CALayer *weakLayer = layer;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((dur+0.05)*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CALayer *strongLayer = weakLayer;
        if (strongLayer) {
            strongLayer.cornerRadius = 0;
            strongLayer.transform = CATransform3DIdentity;
        }
        gCloseGestureActive = NO;
    });
}

// Layer gần nhất mà hệ thống vừa cố set transform trong lúc đang đóng — dùng để
// LMRunCloseFinish/Cancel biết chính xác layer nào cần animate tiếp ở bước Ended.
static __weak CALayer *gLastCloseLayer = nil;

%hook SBFluidSwitcherGestureManager

- (void)_handleSwitcherPanGestureBegan:(id)gesture {
    %orig;
    if (!enabled || lmEffectMode != 0) return; // v1: chỉ áp dụng cho mode Liquid Morph cổ điển
    UIPanGestureRecognizer *pan = gesture;
    if (![pan isKindOfClass:[UIPanGestureRecognizer class]] || !pan.view) return;

    gCloseGestureActive = YES;
    gCloseT = 1.0;
    gCloseScreen = pan.view.window ? pan.view.window.bounds : pan.view.bounds;
    gCloseHasIcon = gHasSourceFrame;
    gCloseIconFixed = gSourceIconFrameFixed;
    lmLog(@"CLOSE began: screen=%@ hasIcon=%d icon=%@", NSStringFromCGRect(gCloseScreen), gCloseHasIcon, NSStringFromCGRect(gCloseIconFixed));
}

- (void)_handleSwitcherPanGestureChanged:(id)gesture {
    %orig;
    if (!gCloseGestureActive) return;
    UIPanGestureRecognizer *pan = gesture;
    if (![pan isKindOfClass:[UIPanGestureRecognizer class]]) return;
    CGPoint t = [pan translationInView:pan.view];
    CGFloat progress = MAX(0.0, MIN(1.0, (-t.y) / kLMCloseDragRange));
    gCloseT = 1.0 - progress;
}

- (void)_handleSwitcherPanGestureEnded:(id)gesture {
    %orig;
    if (!gCloseGestureActive) return;
    UIPanGestureRecognizer *pan = gesture;
    CGFloat velY = 0;
    if ([pan isKindOfClass:[UIPanGestureRecognizer class]]) {
        velY = [pan velocityInView:pan.view].y;
    }
    BOOL shouldClose = (gCloseT <= (1.0 - kLMCloseThreshold)) || (velY <= kLMCloseFlingVelocity);
    lmLog(@"CLOSE ended: gCloseT=%.3f velY=%.1f -> %@", gCloseT, velY, shouldClose ? @"DONG" : @"HUY");

    if (shouldClose) {
        LMRunCloseFinish(gLastCloseLayer);
    } else {
        LMRunCloseCancel(gLastCloseLayer);
    }
}

%end

%hook SBFluidSwitcherItemContainerLayer
- (void)setTransform:(CATransform3D)t {
    if (!gCloseGestureActive) { %orig; return; }
    gLastCloseLayer = self;
    CGRect icon = gCloseHasIcon ? LMAdjustedIconFrame(gCloseIconFixed, gCloseScreen)
                                 : CGRectMake(gCloseScreen.size.width/2-30, gCloseScreen.size.height/2-30, 60, 60);
    CATransform3D custom = LMTransformAt(gCloseT, icon, gCloseScreen);
    self.cornerRadius = LMRadius(gCloseT);
    %orig(custom);
}
%end

%ctor {
    loadPrefs();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
        (CFNotificationCallback)loadPrefs, CFSTR(NOTIFY_CHANGE), NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}
