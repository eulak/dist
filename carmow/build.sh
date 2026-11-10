#!/bin/bash
# Carmow Builder — WSL2 build script
# Dopamine 3.x → Carmow rebrand + rootful + derleme
set -euo pipefail

log() { echo -e "\033[1;32m[CARMOW]\033[0m $1"; }
err() { echo -e "\033[1;31m[HATA]\033[0m $1"; }

WORK="$HOME/carmow-build"
mkdir -p "$WORK"
cd "$WORK"

# ── 1. Dependencies ──
log "Bagimliliklar kuruluyor..."
sudo apt-get update -qq 2>&1 | tail -1
sudo apt-get install -y -qq \
    git make clang lld curl unzip g++ \
    libarchive-dev liblzma-dev libssl-dev zlib1g-dev \
    libplist-dev \
    python3 coreutils 2>&1 | tail -3

# ── 2. ldid ──
if ! command -v ldid &>/dev/null; then
    log "ldid kuruluyor..."
    rm -rf /tmp/ldid-src
    git clone --depth 1 https://github.com/ProcursusTeam/ldid.git /tmp/ldid-src 2>&1 | tail -1
    cd /tmp/ldid-src && make -j"$(nproc)" 2>&1 | tail -3
    sudo cp ldid /usr/local/bin/
    cd "$WORK"
fi
log "ldid hazir"

# ── 3. iOS SDK ──
SDK_DIR="$WORK/sdks/iPhoneOS16.5.sdk"
if [ ! -d "$SDK_DIR" ]; then
    log "iOS SDK indiriliyor (~500MB)..."
    mkdir -p "$WORK/sdks"
    curl -sL "https://github.com/theos/sdks/archive/master.tar.gz" -o /tmp/sdks.tar.gz
    tar xzf /tmp/sdks.tar.gz -C "$WORK/sdks" --strip-components=1 2>/dev/null
    rm -f /tmp/sdks.tar.gz
fi
if [ -d "$SDK_DIR" ]; then log "SDK OK"; else err "SDK bulunamadi!"; exit 1; fi

# ── 4. Clone Dopamine ──
DOPAMINE="$WORK/Dopamine"
if [ ! -d "$DOPAMINE/.git" ]; then
    log "Dopamine klonlaniyor (submodule dahil)..."
    git clone --recurse-submodules --depth 1 https://github.com/opa334/Dopamine.git "$DOPAMINE" 2>&1 | tail -5
else
    log "Dopamine zaten mevcut"
fi

# ── 5. Rebrand → Carmow ──
log "Carmow olarak rebrand ediliyor..."
python3 << 'PYEOF'
import plistlib, glob, os

# Info.plist
plist = os.path.expanduser("~/carmow-build/Dopamine/Application/Dopamine/Info.plist")
if os.path.exists(plist):
    with open(plist, "rb") as f:
        pl = plistlib.load(f)
    pl["CFBundleIdentifier"] = "com.carmow.what"
    pl["CFBundleName"] = "Carmow"
    pl["CFBundleDisplayName"] = "Carmow"
    with open(plist, "wb") as f:
        plistlib.dump(pl, f)
    print("  Info.plist OK")

# Localizable.strings
count = 0
for lp in glob.glob(os.path.expanduser("~/carmow-build/Dopamine/Application/Dopamine/Dopamine/*.lproj")):
    sf = os.path.join(lp, "Localizable.strings")
    if not os.path.exists(sf):
        continue
    try:
        with open(sf, "rb") as f:
            d = plistlib.load(f)
        changed = False
        for k in d:
            if isinstance(d[k], str) and "Dopamine" in d[k]:
                d[k] = d[k].replace("Dopamine", "Carmow")
                changed = True
            if isinstance(d[k], str) and "opa334" in d[k]:
                d[k] = d[k].replace("by opa334, ElleKit by évelyne", "by eulak")
                changed = True
        if changed:
            with open(sf, "wb") as f:
                plistlib.dump(d, f, fmt=plistlib.FMT_BINARY)
            count += 1
    except:
        pass
print(f"  Lokalizasyonlar OK ({count} dosya)")
PYEOF

# ── 6. Patch Makefiles for WSL (no xcrun, no brew) ──
log "Makefile'lar WSL icin yamalanıyor..."
cd "$DOPAMINE"
find BaseBin -name "Makefile" -exec sed -i \
    "s|\$(shell xcrun --sdk iphoneos --show-sdk-path)|$SDK_DIR|g" {} \;
find BaseBin -name "Makefile" -exec sed -i \
    "s|-I\$(shell brew --prefix)/opt/libarchive/include|-I/usr/include|g" {} \;

# ── 7. Build BaseBin ──
log "BaseBin derleniyor..."
make -C BaseBin 2>&1 | tail -30

if [ -f BaseBin/basebin.tar ]; then
    log "BaseBin OK: $(ls -lh BaseBin/basebin.tar | awk '{print $5}')"
else
    err "BaseBin derlenemedi! Yukardaki hatalara bak."
    exit 1
fi

# ── 8. Build Application (clang, no xcodebuild) ──
log "Application derleniyor..."
APP_SRC="$DOPAMINE/Application/Dopamine"
APP_BUILD="$WORK/app-build"
rm -rf "$APP_BUILD"
mkdir -p "$APP_BUILD/obj" "$APP_BUILD/Carmow.app/Frameworks"

# Collect sources
SRCS=$(find "$APP_SRC/Dopamine" "$APP_SRC/Jailbreak" "$APP_SRC/UI" \
    -name "*.m" -o -name "*.c" 2>/dev/null | sort)

CFLAGS="-target arm64-apple-ios15.0 -isysroot $SDK_DIR \
    -fobjc-arc -Os -DNDEBUG \
    -I$DOPAMINE/BaseBin/.include \
    -I$APP_SRC/Dopamine -I$APP_SRC"

FAIL=0
TOTAL=0
for src in $SRCS; do
    name=$(basename "$src")
    obj="$APP_BUILD/obj/${name%.*}.o"
    if clang $CFLAGS -c -o "$obj" "$src" 2>/dev/null; then
        TOTAL=$((TOTAL + 1))
    else
        FAIL=$((FAIL + 1))
    fi
done
log "Derleme: $TOTAL basarili, $FAIL basarisiz"

# Link
OBJS=$(find "$APP_BUILD/obj" -name "*.o" | tr '\n' ' ')
if [ -n "$OBJS" ]; then
    lld -flavor darwin -arch arm64 \
        -platform_version ios 15.0.0 16.5.0 \
        -syslibroot "$SDK_DIR" \
        -framework Foundation -framework UIKit -framework CoreGraphics \
        -framework Security -framework IOKit -framework IOSurface \
        -lSystem -lobjc -adhoc_codesign \
        -o "$APP_BUILD/Carmow.app/Carmow" \
        $OBJS 2>&1 || err "Link basarisiz"
fi

# Copy resources
cp "$APP_SRC/Dopamine/Info.plist" "$APP_BUILD/Carmow.app/" 2>/dev/null || true
cp -r "$APP_SRC/Dopamine/Dopamine/"*.lproj "$APP_BUILD/Carmow.app/" 2>/dev/null || true
cp "$APP_SRC/Dopamine/Dopamine/Assets.car" "$APP_BUILD/Carmow.app/" 2>/dev/null || true
cp "$APP_SRC/Dopamine/Dopamine/Themes.plist" "$APP_BUILD/Carmow.app/" 2>/dev/null || true
cp "$APP_SRC/Dopamine/Dopamine/PkgManagers.plist" "$APP_BUILD/Carmow.app/" 2>/dev/null || true
cp "$APP_SRC/Dopamine/Dopamine/Credits.plist" "$APP_BUILD/Carmow.app/" 2>/dev/null || true
cp "$DOPAMINE/BaseBin/basebin.tar" "$APP_BUILD/Carmow.app/" 2>/dev/null || true
cp "$DOPAMINE/BaseBin/basebin.tc" "$APP_BUILD/Carmow.app/" 2>/dev/null || true

# Sign
ENTS="$APP_SRC/Dopamine/Dopamine.entitlements"
if [ -f "$APP_BUILD/Carmow.app/Carmow" ]; then
    ldid -S"$ENTS" "$APP_BUILD/Carmow.app/Carmow" 2>/dev/null || \
        ldid -Cadhoc -s "$APP_BUILD/Carmow.app/Carmow" 2>/dev/null || true
fi

# Package IPA
cd "$APP_BUILD"
rm -rf Payload Carmow.ipa
mkdir Payload
cp -r Carmow.app Payload/
zip -r Carmow.ipa Payload >/dev/null 2>&1
rm -rf Payload

if [ -f Carmow.ipa ]; then
    IPA_SIZE=$(ls -lh Carmow.ipa | awk '{print $5}')
    log "════════════════════════════════════════"
    log "  CARMOW.IPA HAZIRLANDI!"
    log "  Boyut: $IPA_SIZE"
    log "  Konum: $APP_BUILD/Carmow.ipa"
    log "════════════════════════════════════════"

    # Copy to Windows Desktop
    WIN_USER=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')
    if [ -n "$WIN_USER" ]; then
        cp Carmow.ipa "/mnt/c/Users/$WIN_USER/Desktop/Carmow.ipa" 2>/dev/null && \
            log "Masaustune kopyalandi!" || \
            log "Masaustune kopyalanamadi, IPA: $APP_BUILD/Carmow.ipa"
    fi
else
    err "IPA olusturulamadi."
    log "BaseBin derlendiyse, Application icin macOS + Xcode gerekebilir."
    log "Alternatif: BaseBin ciktisi $DOPAMINE/BaseBin/basebin.tar"
fi

log "Tamamlandi."
