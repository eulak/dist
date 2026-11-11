#!/bin/bash
set -e

APP="/var/containers/Bundle/Application/292D2586-54F1-4075-9C71-11BDF09265F3/Carmow.app"
FW="$APP/Frameworks/CarmowRootful.framework"
SDK="/private/preboot/E3A871C2F562B8CFD2E6F24FDA37C69163D9C1A89B9030C2B158192AEB0271130BF79CF61CB98A93D9EB9B8260F01E3E/dopamine-UT95FH/procursus/usr/share/SDKs/iPhoneOS.sdk"

echo "[1/4] Writing full hook source..."
cat > /tmp/carmow_full.m << 'SRCEOF'
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

static void swizzle(Class cls, SEL orig, SEL repl) {
    Method o = class_getInstanceMethod(cls, orig);
    Method r = class_getInstanceMethod(cls, repl);
    if (!o || !r) return;
    if (class_addMethod(cls, orig, method_getImplementation(r), method_getTypeEncoding(r)))
        class_replaceMethod(cls, repl, method_getImplementation(o), method_getTypeEncoding(o));
    else
        method_exchangeImplementations(o, r);
}

@interface CarmowHeaderHook : NSObject @end
@implementation CarmowHeaderHook
- (id)carmow_initWithImage:(UIImage *)img subtitles:(NSArray *)subs {
    id r = [self carmow_initWithImage:img subtitles:subs];
    if (!r) return r;
    UIView *v = (UIView *)r;
    for (UIView *s in v.subviews) {
        if ([s isKindOfClass:[UIStackView class]]) {
            UIStackView *st = (UIStackView *)s;
            for (UIView *a in st.arrangedSubviews) {
                if ([a isKindOfClass:[UIImageView class]]) {
                    a.hidden = YES;
                    UILabel *l = [[UILabel alloc] init];
                    l.text = @"Carmow";
                    l.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
                    l.textColor = [UIColor whiteColor];
                    l.translatesAutoresizingMaskIntoConstraints = NO;
                    [st insertArrangedSubview:l atIndex:0];
                    break;
                }
            }
            break;
        }
    }
    return r;
}
@end

@interface CarmowCreditsHook : NSObject @end
@implementation CarmowCreditsHook
- (id)carmow_specifiers { return @[]; }
@end

@interface CarmowSettingsHook : NSObject @end
@implementation CarmowSettingsHook
- (id)carmow_specifiers {
    NSArray *orig = [self carmow_specifiers];
    NSMutableArray *specs = [orig mutableCopy];
    Class PSS = NSClassFromString(@"PSSpecifier");
    if (!PSS) return orig;
    id grp = [PSS performSelector:@selector(emptyGroupSpecifier)];
    [grp performSelector:@selector(setName:) withObject:@"Rootful"];
    NSString *st;
    if ([[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"])
        st = @"Jailbreak active (rootless at /var/jb)";
    else if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/rootful"])
        st = @"Rootful overlay present";
    else
        st = @"Rootful not configured";
    [grp performSelector:@selector(setProperty:forKey:) withObject:st withObject:@"footerText"];
    [specs addObject:grp];
    return specs;
}
@end

static void install_hooks(void) {
    NSLog(@"[Carmow] Installing hooks...");
    Class hdr = NSClassFromString(@"DOHeaderView");
    if (hdr) {
        SEL o = @selector(initWithImage:subtitles:);
        SEL r = @selector(carmow_initWithImage:subtitles:);
        class_addMethod(hdr, r, class_getMethodImplementation([CarmowHeaderHook class], r),
            method_getTypeEncoding(class_getInstanceMethod([CarmowHeaderHook class], r)));
        swizzle(hdr, o, r);
        NSLog(@"[Carmow] Header hooked");
    }
    Class cred = NSClassFromString(@"DOCreditsViewController");
    if (cred) {
        SEL o = @selector(specifiers); SEL r = @selector(carmow_specifiers);
        class_addMethod(cred, r, class_getMethodImplementation([CarmowCreditsHook class], r),
            method_getTypeEncoding(class_getInstanceMethod([CarmowCreditsHook class], r)));
        swizzle(cred, o, r);
        NSLog(@"[Carmow] Credits hooked");
    }
    Class set = NSClassFromString(@"DOSettingsController");
    if (set) {
        SEL o = @selector(specifiers); SEL r = @selector(carmow_specifiers);
        class_addMethod(set, r, class_getMethodImplementation([CarmowSettingsHook class], r),
            method_getTypeEncoding(class_getInstanceMethod([CarmowSettingsHook class], r)));
        swizzle(set, o, r);
        NSLog(@"[Carmow] Settings hooked");
    }
    NSLog(@"[Carmow] All hooks installed");
}

__attribute__((constructor))
static void carmow_init(void) {
    NSLog(@"[Carmow] Constructor fired");
    dispatch_async(dispatch_get_main_queue(), ^{ install_hooks(); });
}
void exploit_init(void) { NSLog(@"[Carmow] exploit_init"); }
void exploit_deinit(void) { NSLog(@"[Carmow] exploit_deinit"); }
SRCEOF

echo "[2/4] Compiling..."
clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -shared \
    -o /tmp/CarmowRootful_full /tmp/carmow_full.m \
    -framework Foundation -framework UIKit \
    -Wno-unused-command-line-argument -Wno-objc-method-access || { echo "COMPILE FAILED"; exit 1; }
echo "Compiled: $(wc -c < /tmp/CarmowRootful_full) bytes"

echo "[3/4] Replacing framework + signing..."
cp /tmp/CarmowRootful_full "$FW/CarmowRootful"
ldid -s "$FW/CarmowRootful"
ldid -s "$APP/Carmow"

echo "[4/4] Verifying..."
echo "Framework: $(wc -c < "$FW/CarmowRootful") bytes"

echo ""
echo "========================================="
echo "  DONE - Kill Carmow and reopen"
echo "  Logo = Carmow, Credits = empty"
echo "  Settings = Rootful section at bottom"
echo "  Log: sudo log stream | grep Carmow"
echo "========================================="
