// FridaGadget hook script for MarginNote 4 Max unlock
// Runs inside FridaGadget injected into the app

// Hook NSUserDefaults
var NSUserDefaults = ObjC.classes.NSUserDefaults;
var origObjectForKey = NSUserDefaults['- objectForKey:'];
NSUserDefaults['- objectForKey:'] = function(key) {
    var strKey = ObjC.unwrap(key);
    if (strKey === 'hasMaxLifetime' || strKey === 'hasProLifetime') {
        send('[MNMaxUnlock] NSUserDefaults objectForKey: ' + strKey + ' → YES');
        return ObjC.wrap(ObjC.classes.NSNumber.numberWithBool_(1));
    }
    if (strKey === 'activeSubscriptionSKU') {
        return ObjC.wrap(ObjC.classes.NSString.stringWithString_('QReader.MarginStudy.easy.MaxYearly'));
    }
    return origObjectForKey.call(this, key);
};

var origBoolForKey = NSUserDefaults['- boolForKey:'];
NSUserDefaults['- boolForKey:'] = function(key) {
    var strKey = ObjC.unwrap(key);
    if (strKey.indexOf('hasMax') === 0 || strKey.indexOf('hasPro') === 0 ||
        strKey.indexOf('isMax') === 0 || strKey.indexOf('isPro') === 0) {
        send('[MNMaxUnlock] boolForKey: ' + strKey + ' → YES');
        return 1;
    }
    return origBoolForKey.call(this, key);
};

// Hook MNEntitlementSnapshot
var MNEntitlementSnapshot = ObjC.classes.MNEntitlementSnapshot;
if (MNEntitlementSnapshot) {
    send('[MNMaxUnlock] Found MNEntitlementSnapshot, hooking...');
    
    // Replace hasMaxLifetime
    MNEntitlementSnapshot['- hasMaxLifetime'].implementation = ObjC.implement(
        MNEntitlementSnapshot['- hasMaxLifetime'],
        function(handle, sel) {
            send('[MNMaxUnlock] hasMaxLifetime → YES');
            return 1;
        }
    );
    
    // Replace hasProLifetime
    MNEntitlementSnapshot['- hasProLifetime'].implementation = ObjC.implement(
        MNEntitlementSnapshot['- hasProLifetime'],
        function(handle, sel) {
            send('[MNMaxUnlock] hasProLifetime → YES');
            return 1;
        }
    );
    
    // Replace setHasMaxLifetime:
    MNEntitlementSnapshot['- setHasMaxLifetime:'].implementation = ObjC.implement(
        MNEntitlementSnapshot['- setHasMaxLifetime:'],
        function(handle, sel, value) {
            send('[MNMaxUnlock] setHasMaxLifetime: called with ' + value + ' → forcing YES');
            var orig = ObjC.classes.MNEntitlementSnapshot.$ivars['_hasMaxLifetime'];
            if (orig) {
                // Call original with YES
                ObjC.classes.MNEntitlementSnapshot['- setHasMaxLifetime:'].call(this, 1);
            }
        }
    );
    
    // Replace setHasProLifetime:
    MNEntitlementSnapshot['- setHasProLifetime:'].implementation = ObjC.implement(
        MNEntitlementSnapshot['- setHasProLifetime:'],
        function(handle, sel, value) {
            send('[MNMaxUnlock] setHasProLifetime: called with ' + value + ' → forcing YES');
            var orig = ObjC.classes.MNEntitlementSnapshot.$ivars['_hasProLifetime'];
            if (orig) {
                ObjC.classes.MNEntitlementSnapshot['- setHasProLifetime:'].call(this, 1);
            }
        }
    );
} else {
    send('[MNMaxUnlock] WARNING: MNEntitlementSnapshot not found!');
}

// Hook RMStore receipt verification
var RMStore = ObjC.classes.RMStore;
if (RMStore) {
    send('[MNMaxUnlock] Found RMStore, hooking verifyTransaction...');
    
    // verifyTransaction:success:failure:
    RMStore['- verifyTransaction:success:failure:'].implementation = ObjC.implement(
        RMStore['- verifyTransaction:success:failure:'],
        function(handle, sel, transaction, successBlock, failureBlock) {
            send('[MNMaxUnlock] RMStore verifyTransaction → FAKE SUCCESS');
            var block = new ObjC.Block(successBlock);
            block.implementation()();
        }
    );
    
    // verifyTransaction:inReceipt:success:failure:
    RMStore['- verifyTransaction:inReceipt:success:failure:'].implementation = ObjC.implement(
        RMStore['- verifyTransaction:inReceipt:success:failure:'],
        function(handle, sel, transaction, receipt, successBlock, failureBlock) {
            send('[MNMaxUnlock] RMStore verifyTransaction:inReceipt → FAKE SUCCESS');
            var block = new ObjC.Block(successBlock);
            block.implementation()();
        }
    );
} else {
    send('[MNMaxUnlock] WARNING: RMStore not found!');
}

// Hook SKPaymentQueue
var SKPaymentQueue = ObjC.classes.SKPaymentQueue;
var origAddPayment = SKPaymentQueue['- addPayment:'];
SKPaymentQueue['- addPayment:'].implementation = ObjC.implement(
    SKPaymentQueue['- addPayment:'],
    function(handle, sel, payment) {
        var productID = ObjC.unwrap(payment.productIdentifier());
        send('[MNMaxUnlock] SKPaymentQueue addPayment: ' + productID + ' → intercepted (no-op)');
        // Don't call original - just swallow the purchase request
    }
);

// Force UserDefaults values at startup
var ud = NSUserDefaults.standardUserDefaults();
ud.setBool_forKey_(1, 'hasMaxLifetime');
ud.setBool_forKey_(1, 'hasProLifetime');
ud.setObject_forKey_(ObjC.classes.NSString.stringWithString_('QReader.MarginStudy.easy.MaxYearly'), 'activeSubscriptionSKU');
ud.synchronize();

send('[MNMaxUnlock] ✅ All hooks installed! Max features unlocked.');
