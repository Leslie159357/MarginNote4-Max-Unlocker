//
//  MNMaxUnlock.mm
//  MarginNote 4 Pro → Max Unlocker (fixed)
//
//  Hooks NSUserDefaults and MNEntitlementSnapshot to unlock Max features.
//  Removed risky StoreKit hooks that caused crashes on iOS 18+.
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <UIKit/UIKit.h>

// ========== Product IDs ==========
static NSString *const kMaxYearlyID = @"QReader.MarginStudy.easy.MaxYearly";

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
        [key isEqualToString:@"hasProLifetime"]) {
        Log(@"NSUserDefaults objectForKey:%@ → @YES", key);
        return @YES;
    }
    if ([key isEqualToString:@"activeSubscriptionSKU"]) {
        return kMaxYearlyID;
    }
    return orig_UD_objectForKey(self, _cmd, key);
}

static BOOL (*orig_UD_boolForKey)(id, SEL, NSString *);
static BOOL hook_UD_boolForKey(id self, SEL _cmd, NSString *key) {
    if ([key hasPrefix:@"hasMax"] || [key hasPrefix:@"hasPro"] ||
        [key hasPrefix:@"isMax"] || [key hasPrefix:@"isPro"] ||
        [key hasPrefix:@"hasActive"]) {
        Log(@"NSUserDefaults boolForKey:%@ → YES", key);
        return YES;
    }
    return orig_UD_boolForKey(self, _cmd, key);
}

// ========== MNEntitlementSnapshot Hook ==========
static BOOL hook_entsnap_hasMax(id self, SEL _cmd) {
    Log(@"MNEntitlementSnapshot.hasMaxLifetime → YES");
    return YES;
}

static BOOL hook_entsnap_hasPro(id self, SEL _cmd) {
    Log(@"MNEntitlementSnapshot.hasProLifetime → YES");
    return YES;
}

static BOOL hook_entsnap_hasActiveMax(id self, SEL _cmd) {
    Log(@"MNEntitlementSnapshot.hasActiveMax → YES");
    return YES;
}

static BOOL hook_entsnap_hasAnyActiveMax(id self, SEL _cmd) {
    Log(@"MNEntitlementSnapshot.hasAnyActiveMax → YES");
    return YES;
}

static BOOL hook_entsnap_hasActiveFullMaxSubscription(id self, SEL _cmd) {
    Log(@"MNEntitlementSnapshot.hasActiveFullMaxSubscription → YES");
    return YES;
}

// ========== Hook Utility ==========
static IMP hookMethod(Class cls, SEL sel, IMP newImpl) {
    if (!cls) { Log(@"Class nil for %@", NSStringFromSelector(sel)); return nil; }
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        // Try class method
        m = class_getClassMethod(cls, sel);
        if (!m) { Log(@"Method [%@ %@] not found", NSStringFromClass(cls), NSStringFromSelector(sel)); return nil; }
    }
    IMP orig = method_setImplementation(m, newImpl);
    Log(@"✓ Hooked [%@ %@]", NSStringFromClass(cls), NSStringFromSelector(sel));
    return orig;
}

// ========== ShowAlert (safe version) ==========
static void showAlert(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @try {
            UIViewController *rootVC = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                    if (scene.activationState == UISceneActivationStateForegroundActive) {
                        UIWindowScene *ws = (UIWindowScene *)scene;
                        for (UIWindow *w in ws.windows) {
                            if (w.isKeyWindow) { rootVC = w.rootViewController; break; }
                        }
                        if (rootVC) break;
                    }
                }
            }
            if (!rootVC) {
                rootVC = UIApplication.sharedApplication.keyWindow.rootViewController;
            }
            if (rootVC) {
                UIAlertController *alert = [UIAlertController
                    alertControllerWithTitle:@"✅ Max Unlocked!"
                    message:@"MarginNote 4 Max features are now active."
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [rootVC presentViewController:alert animated:YES completion:nil];
            }
        } @catch (NSException *e) {
            Log(@"Alert error: %@", e.reason);
        }
    });
}

// ========== Constructor ==========
__attribute__((constructor)) static void init() {
    @autoreleasepool {
        Log(@"=== MarginNote 4 Max Unlocker v2.0 (fixed) ===");
        
        // 1. Hook NSUserDefaults
        hookMethod([NSUserDefaults class], @selector(objectForKey:),
                   (IMP)hook_UD_objectForKey);
        hookMethod([NSUserDefaults class], @selector(boolForKey:),
                   (IMP)hook_UD_boolForKey);
        
        // 2. Hook MNEntitlementSnapshot
        Class entSnap = NSClassFromString(@"MNEntitlementSnapshot");
        if (entSnap) {
            hookMethod(entSnap, @selector(hasMaxLifetime),
                       (IMP)hook_entsnap_hasMax);
            hookMethod(entSnap, @selector(hasProLifetime),
                       (IMP)hook_entsnap_hasPro);
            
            // Also hook additional entitlement check methods
            // These may or may not exist; hookMethod safely handles missing methods
            hookMethod(entSnap, @selector(hasActiveMax),
                       (IMP)hook_entsnap_hasActiveMax);
            hookMethod(entSnap, @selector(hasAnyActiveMax),
                       (IMP)hook_entsnap_hasAnyActiveMax);
            hookMethod(entSnap, @selector(hasActiveFullMaxSubscription),
                       (IMP)hook_entsnap_hasActiveFullMaxSubscription);
            
            Log(@"✓ MNEntitlementSnapshot hooks installed");
        } else {
            Log(@"⚠ MNEntitlementSnapshot class not found — will rely on NSUserDefaults hooks");
        }
        
        // 3. Force write UserDefaults (belt-and-suspenders)
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setBool:YES forKey:@"hasMaxLifetime"];
        [ud setBool:YES forKey:@"hasProLifetime"];
        [ud setBool:YES forKey:@"hasActiveMax"];
        [ud setBool:YES forKey:@"hasAnyActiveMax"];
        [ud setBool:YES forKey:@"hasActiveFullMaxSubscription"];
        [ud setObject:kMaxYearlyID forKey:@"activeSubscriptionSKU"];
        [ud synchronize];
        
        Log(@"All hooks installed ✅ Max features unlocked!");
        showAlert();
    }
}
