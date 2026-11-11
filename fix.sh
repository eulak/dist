#!/bin/bash
set -e

APP="/var/containers/Bundle/Application/292D2586-54F1-4075-9C71-11BDF09265F3/Carmow.app"
FW="$APP/Frameworks/CarmowRootful.framework"
SDK="/private/preboot/E3A871C2F562B8CFD2E6F24FDA37C69163D9C1A89B9030C2B158192AEB0271130BF79CF61CB98A93D9EB9B8260F01E3E/dopamine-UT95FH/procursus/usr/share/SDKs/iPhoneOS.sdk"

echo "[1/3] Building minimal test dylib..."
cat > /tmp/test_carmow.m << 'SRCEOF'
#import <Foundation/Foundation.h>

__attribute__((constructor))
static void carmow_init(void) {
    NSLog(@"[Carmow] === CONSTRUCTOR RUNNING ===");
}
SRCEOF

clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -shared \
    -o /tmp/CarmowRootful_test /tmp/test_carmow.m \
    -framework Foundation -Wno-unused-command-line-argument || { echo "COMPILE FAILED"; exit 1; }
echo "Compiled OK: $(wc -c < /tmp/CarmowRootful_test) bytes"

echo "[2/3] Replacing framework binary + signing..."
cp /tmp/CarmowRootful_test "$FW/CarmowRootful"
ldid -s "$FW/CarmowRootful"
echo "Framework replaced and signed"

echo "[3/3] Done - open Carmow now"
echo "If it opens without crash, constructor works."
echo "Check log: sudo log stream --level debug | grep Carmow"
