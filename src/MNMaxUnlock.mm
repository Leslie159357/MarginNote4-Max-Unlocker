//
//  MNMaxUnlock.mm
//  MarginNote 4 Pro → Max Unlocker
//
//  Hooks StoreKit receipt verification and entitlement resolution
//  to unlock Max features without purchasing.
//
//  Compile:
//    clang -shared -framework Foundation -framework StoreKit -framework UIKit \
//          -o MNMaxUnlock.dylib src/MNMaxUnlock.mm \
//          -arch arm64 -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//          -miphoneos-version-min=15.0 -fobjc-arc
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <StoreKit/StoreKit.h>
#import <UIKit/UIKit.h>

// ========== Product IDs ==========
static NSString *const kMaxYearlyID    = @"QReader.MarginStudy.easy.MaxYearly";
static NSString *const kFreeTrialMaxID = @"QReader.MarginStudy.easy.FreeTrialMAX";
static NSString *const kProUnlockID    = @"QReader.MarginStudy.easy.ProUnlock";

// ========== Logging ==========
static void Log(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSLog(@"[MNMaxUnlock] %@", [[NSString alloc] initWithFormat:fmt arguments:args]);
    va_end(args);
}

// ========== NSUserDefaults Hook ==========
static id (*orig_UD_objectForKey)(id, SEL, NSString *);
static id hook_UD_objectForKey(id self, SEL _cmd, NSString *key) {
    if ([key isEqualToString:@"hasMaxLifetime"] ||
        [key isEqualToString:@"hasProLifetime"]) return @YES;
    if ([key isEqualToString:@"activeSubscriptionSKU"]) return kMaxYearlyID;
    return orig_UD_objectForKey(self, _cmd, key);
}

static BOOL (*orig_UD_boolForKey)(id, SEL, NSString *);
static BOOL hook_UD_boolForKey(id self, SEL _cmd, NSString *key) {
    if ([key hasPrefix:@"hasMax"] || [key hasPrefix:@"hasPro"] ||
        [key hasPrefix:@"isMax"] || [key hasPrefix:@"isPro"]) return YES;
    return orig_UD_boolForKey(self, _cmd, key);
}

// ========== MNEntitlementSnapshot Hook ==========
// Force hasMaxLifetime / hasProLifetime to YES

static BOOL (*orig_entsnap_hasMax)(id, SEL);
static BOOL hook_entsnap_hasMax(id self, SEL _cmd) {
    Log(@"MNEntitlementSnapshot.hasMaxLifetime → YES");
    return YES;
}

static BOOL (*orig_entsnap_hasPro)(id, SEL);
static BOOL hook_entsnap_hasPro(id self, SEL _cmd) {
    Log(@"MNEntitlementSnapshot.hasProLifetime → YES");
    return YES;
}

static void (*orig_entsnap_setMax)(id, SEL, BOOL);
static void hook_entsnap_setMax(id self, SEL _cmd, BOOL v) {
    Log(@"setHasMaxLifetime:%d → forcing YES", v);
    orig_entsnap_setMax(self, _cmd, YES);
}

static void (*orig_entsnap_setPro)(id, SEL, BOOL);
static void hook_entsnap_setPro(id self, SEL _cmd, BOOL v) {
    Log(@"setHasProLifetime:%d → forcing YES", v);
    orig_entsnap_setPro(self, _cmd, YES);
}

// ========== RMStore Receipt Verification Hook ==========
static void (*orig_verify_sf)(id, SEL, id, id, id);
static void hook_verify_sf(id self, SEL _cmd, id tx, id success, id failure) {
    Log(@"RMStore verifyTransaction:success:failure: → FAKE SUCCESS");
    void (^s)(void) = success; if (s) s();
}

static void (*orig_verify_inreceipt)(id, SEL, id, id, id, id);
static void hook_verify_inreceipt(id self, SEL _cmd, id tx, id receipt, id success, id failure) {
    Log(@"RMStore verifyTransaction:inReceipt: → FAKE SUCCESS");
    void (^s)(void) = success; if (s) s();
}

// ========== SKPaymentQueue Hook ==========
static void (*orig_addPayment)(id, SEL, SKPayment *);
static void hook_addPayment(id self, SEL _cmd, SKPayment *payment) {
    Log(@"SKPaymentQueue addPayment:%@ → intercepted (no-op, fake success)", payment.productIdentifier);
    // Don't call original — simulate success
}

static void (*orig_restore)(id, SEL);
static void hook_restore(id self, SEL _cmd) {
    Log(@"SKPaymentQueue restoreCompletedTransactions → intercepted");
    // Create fake restored transactions
    id observer = [self valueForKey:@"_observer"];
    if (observer && [observer respondsToSelector:@selector(paymentQueue:updatedTransactions:)]) {
        [observer paymentQueue:self updatedTransactions:@[]];
    }
    if (observer && [observer respondsToSelector:@selector(paymentQueueRestoreCompletedTransactionsFinished:)]) {
        [observer paymentQueueRestoreCompletedTransactionsFinished:self];
    }
}

// ========== Hook Utility ==========
static void hookMethod(Class cls, SEL sel, IMP newImpl, IMP *oldImpl) {
    if (!cls) { Log(@"Class nil for %@", NSStringFromSelector(sel)); return; }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) { Log(@"Method [%@ %@] not found", NSStringFromClass(cls), NSStringFromSelector(sel)); return; }
    *oldImpl = method_setImplementation(m, newImpl);
    Log(@"✓ Hooked [%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
}

// ========== ShowAlert ==========
static void showAlert(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"✅ Max Unlocked!"
            message:@"MarginNote 4 Max features are now active.\nAI, OCR, Mac access, database channels all unlocked."
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        
        UIWindow *keyWin = nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *w in ((UIWindowScene *)scene).windows) {
                    if (w.isKeyWindow) { keyWin = w; break; }
                }
            }
        }
        if (!keyWin) keyWin = UIApplication.sharedApplication.keyWindow;
        [keyWin.rootViewController presentViewController:alert animated:YES completion:nil];
    });
}

// ========== Constructor ==========
__attribute__((constructor)) static void init() {
    Log(@"=== MarginNote 4 Max Unlocker v1.0 ===");
    
    // 1. Hook NSUserDefaults
    hookMethod([NSUserDefaults class], @selector(objectForKey:),
               (IMP)hook_UD_objectForKey, (IMP *)&orig_UD_objectForKey);
    hookMethod([NSUserDefaults class], @selector(boolForKey:),
               (IMP)hook_UD_boolForKey, (IMP *)&orig_UD_boolForKey);
    
    // 2. Hook MNEntitlementSnapshot
    Class entSnap = NSClassFromString(@"MNEntitlementSnapshot");
    if (entSnap) {
        hookMethod(entSnap, @selector(hasMaxLifetime),
                   (IMP)hook_entsnap_hasMax, (IMP *)&orig_entsnap_hasMax);
        hookMethod(entSnap, @selector(hasProLifetime),
                   (IMP)hook_entsnap_hasPro, (IMP *)&orig_entsnap_hasPro);
        hookMethod(entSnap, @selector(setHasMaxLifetime:),
                   (IMP)hook_entsnap_setMax, (IMP *)&orig_entsnap_setMax);
        hookMethod(entSnap, @selector(setHasProLifetime:),
                   (IMP)hook_entsnap_setPro, (IMP *)&orig_entsnap_setPro);
    } else {
        Log(@"⚠ MNEntitlementSnapshot class not found");
    }
    
    // 3. Hook RMStore
    Class rmStore = NSClassFromString(@"RMStore");
    if (rmStore) {
        hookMethod(rmStore, @selector(verifyTransaction:success:failure:),
                   (IMP)hook_verify_sf, (IMP *)&orig_verify_sf);
        hookMethod(rmStore, @selector(verifyTransaction:inReceipt:success:failure:),
                   (IMP)hook_verify_inreceipt, (IMP *)&orig_verify_inreceipt);
    } else {
        Log(@"⚠ RMStore class not found");
    }
    
    // 4. Hook SKPaymentQueue
    hookMethod([SKPaymentQueue class], @selector(addPayment:),
               (IMP)hook_addPayment, (IMP *)&orig_addPayment);
    hookMethod([SKPaymentQueue class], @selector(restoreCompletedTransactions),
               (IMP)hook_restore, (IMP *)&orig_restore);
    
    // 5. Force write UserDefaults
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:YES forKey:@"hasMaxLifetime"];
    [ud setBool:YES forKey:@"hasProLifetime"];
    [ud setObject:kMaxYearlyID forKey:@"activeSubscriptionSKU"];
    [ud synchronize];
    
    Log(@"All hooks installed ✅ Max features unlocked!");
    showAlert();
}
