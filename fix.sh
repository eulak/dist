#!/bin/bash
set -e

SDK="/private/preboot/E3A871C2F562B8CFD2E6F24FDA37C69163D9C1A89B9030C2B158192AEB0271130BF79CF61CB98A93D9EB9B8260F01E3E/dopamine-UT95FH/procursus/usr/share/SDKs/iPhoneOS.sdk"
WORK="/tmp/carmow-build"
rm -rf "$WORK"
mkdir -p "$WORK"

echo "[1/7] Finding Carmow app..."
APP=$(find /var/containers/Bundle/Application -name "Carmow.app" 2>/dev/null | head -1)
if [ -z "$APP" ]; then echo "Carmow.app not found!"; exit 1; fi
echo "Found: $APP"

echo "[2/7] Writing hook source..."
cat > "$WORK/hook.m" << 'SRCEOF'
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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
    for (UIView *s in ((UIView *)r).subviews) {
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
        st = @"Jailbreak active (rootless)";
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
        SEL o = @selector(initWithImage:subtitles:); SEL r = @selector(carmow_initWithImage:subtitles:);
        class_addMethod(hdr, r, class_getMethodImplementation([CarmowHeaderHook class], r),
            method_getTypeEncoding(class_getInstanceMethod([CarmowHeaderHook class], r)));
        swizzle(hdr, o, r);
    }
    Class cred = NSClassFromString(@"DOCreditsViewController");
    if (cred) {
        SEL o = @selector(specifiers); SEL r = @selector(carmow_specifiers);
        class_addMethod(cred, r, class_getMethodImplementation([CarmowCreditsHook class], r),
            method_getTypeEncoding(class_getInstanceMethod([CarmowCreditsHook class], r)));
        swizzle(cred, o, r);
    }
    Class set = NSClassFromString(@"DOSettingsController");
    if (set) {
        SEL o = @selector(specifiers); SEL r = @selector(carmow_specifiers);
        class_addMethod(set, r, class_getMethodImplementation([CarmowSettingsHook class], r),
            method_getTypeEncoding(class_getInstanceMethod([CarmowSettingsHook class], r)));
        swizzle(set, o, r);
    }
    NSLog(@"[Carmow] Hooks installed");
}

__attribute__((constructor))
static void carmow_init(void) {
    NSLog(@"[Carmow] Constructor");
    dispatch_async(dispatch_get_main_queue(), ^{ install_hooks(); });
}
void exploit_init(void) {}
void exploit_deinit(void) {}
SRCEOF

echo "[3/7] Compiling dylib..."
clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -shared -Os \
    -o "$WORK/CarmowRootful" "$WORK/hook.m" \
    -framework Foundation -framework UIKit \
    -Wno-unused-command-line-argument -Wno-objc-method-access || { echo "COMPILE FAILED"; exit 1; }
echo "Compiled: $(wc -c < "$WORK/CarmowRootful") bytes"

echo "[4/7] Copying app to build dir..."
mkdir -p "$WORK/ipa/Payload"
cp -a "$APP" "$WORK/ipa/Payload/Carmow.app"

echo "[5/7] Adding framework..."
mkdir -p "$WORK/ipa/Payload/Carmow.app/Frameworks/CarmowRootful.framework"
cp "$WORK/CarmowRootful" "$WORK/ipa/Payload/Carmow.app/Frameworks/CarmowRootful.framework/CarmowRootful"
cat > "$WORK/ipa/Payload/Carmow.app/Frameworks/CarmowRootful.framework/Info.plist" << 'PEOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CarmowRootful</string>
    <key>CFBundleIdentifier</key>
    <string>com.carmow.rootful</string>
    <key>CFBundleName</key>
    <string>CarmowRootful</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
</dict>
</plist>
PEOF

echo "[6/7] Injecting LC_LOAD_DYLIB..."
python3 -c "
import struct
path='$WORK/ipa/Payload/Carmow.app/Carmow'
with open(path,'rb') as f: d=bytearray(f.read())
dylib=b'@rpath/CarmowRootful.framework/CarmowRootful\x00'
pad=(8-len(dylib)%8)%8
dylib=dylib.ljust(len(dylib)+pad,b'\x00')
ncmds=struct.unpack_from('<I',d,16)[0]
soc=struct.unpack_from('<I',d,20)[0]
ins=32+soc
cmd=struct.pack('<IIIIII',0xC,24+len(dylib),24,2,0x10000,0x10000)+dylib
avail=sum(1 for i in range(len(cmd)) if ins+i<len(d) and d[ins+i]==0)
if avail<len(cmd): print(f'NO SPACE:{avail}<{len(cmd)}'); exit(1)
d[ins:ins+len(cmd)]=cmd
struct.pack_into('<I',d,16,ncmds+1)
struct.pack_into('<I',d,20,soc+len(cmd))
with open(path,'wb') as f: f.write(d)
print(f'Injected: ncmds {ncmds}->{ncmds+1}')
"

echo "[7/7] Packaging IPA..."
cd "$WORK/ipa" && zip -qr "$WORK/Carmow.ipa" Payload/
echo ""
echo "========================================="
echo "  IPA ready: $WORK/Carmow.ipa"
echo "  Size: $(du -h "$WORK/Carmow.ipa" | cut -f1)"
echo ""
echo "  Install steps:"
echo "  1. Delete Carmow from TrollStore"
echo "  2. Open Files app"
echo "  3. Go to: On My iPad > /tmp/carmow-build/"
echo "     Or run: trollstorehelper install $WORK/Carmow.ipa"
echo "========================================="
