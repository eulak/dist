#!/bin/bash
set -e

APP="/var/containers/Bundle/Application/4EF3D4DC-D6BA-4B40-BCD7-4CB04B59CD1E/Carmow.app"
BIN="$APP/Carmow"
FW="$APP/Frameworks/CarmowRootful.framework"
SDK="/private/preboot/E3A871C2F562B8CFD2E6F24FDA37C69163D9C1A89B9030C2B158192AEB0271130BF79CF61CB98A93D9EB9B8260F01E3E/dopamine-UT95FH/procursus/usr/share/SDKs/iPhoneOS.sdk"

echo "[1/6] Removing any LC_LOAD_DYLIB for CarmowRootful..."
python3 -c "
import struct
path='$BIN'
with open(path,'rb') as f: d=bytearray(f.read())
ncmds=struct.unpack_from('<I',d,16)[0]
soc=struct.unpack_from('<I',d,20)[0]
off=32
removed=0
for i in range(ncmds):
    cmd,size=struct.unpack_from('<II',d,off)
    if cmd==0xc:
        stroff=struct.unpack_from('<I',d,off+8)[0]
        nm=d[off+stroff:off+size].split(b'\x00')[0].decode()
        if 'CarmowRootful' in nm:
            d[off:off+size]=b'\x00'*size
            ncmds-=1
            soc-=size
            removed+=1
    off+=size
if removed>0:
    struct.pack_into('<I',d,16,ncmds)
    struct.pack_into('<I',d,20,soc)
    with open(path,'wb') as f: f.write(d)
print(f'Removed {removed} LC_LOAD_DYLIB entries, ncmds now {ncmds}')
"

echo "[2/6] Listing frameworks and their Info.plists..."
ls "$APP/Frameworks/"
echo "---"
for fw in "$APP"/Frameworks/*/Info.plist; do
    echo "== $fw =="
    cat "$fw" 2>/dev/null | grep -A1 "DPExploit\|CFBundle\|ExploitType" || echo "(no match)"
    echo ""
done

echo "[3/6] Building minimal test dylib..."
cat > /tmp/test_carmow.m << 'SRCEOF'
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

__attribute__((constructor))
static void carmow_init(void) {
    NSLog(@"[Carmow] === CONSTRUCTOR RUNNING ===");
}

void exploit_init(void) {
    NSLog(@"[Carmow] === EXPLOIT_INIT CALLED ===");
}

void exploit_deinit(void) {
    NSLog(@"[Carmow] === EXPLOIT_DEINIT CALLED ===");
}
SRCEOF

clang -target arm64-apple-ios15.0 -isysroot "$SDK" -fobjc-arc -shared \
    -o /tmp/CarmowRootful_test /tmp/test_carmow.m \
    -framework Foundation -Wno-unused-command-line-argument
echo "Compiled OK, size: $(wc -c < /tmp/CarmowRootful_test) bytes"

echo "[4/6] Replacing framework binary..."
cp /tmp/CarmowRootful_test "$FW/CarmowRootful"
ldid -s "$FW/CarmowRootful"

echo "[5/6] Re-signing main binary..."
ldid -s "$BIN"

echo "[6/6] Verifying..."
python3 -c "
with open('$BIN','rb') as f: d=f.read()
print('CarmowRootful LC in binary:', b'CarmowRootful' in d)
import struct
ncmds=struct.unpack_from('<I',d,16)[0]
print(f'ncmds={ncmds}')
"
python3 -c "
import os
fw='$FW/CarmowRootful'
print(f'Framework size: {os.path.getsize(fw)}')
with open(fw,'rb') as f: m=f.read(4)
print(f'Magic: {m.hex()} (cffaedfe=arm64 OK)')
"

echo ""
echo "========================================="
echo "  ALL DONE - Open Carmow now"
echo "  No LC_LOAD_DYLIB - using bundle loader"
echo "  Check logs: sudo log stream | grep Carmow"
echo "========================================="
