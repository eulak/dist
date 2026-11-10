# Carmow — Teknik Notlar

## Genel Bakış

Carmow, Dopamine 3.0.13 tabanlı bir jailbreak uygulaması. Orijinal Dopamine IPA'sı üzerine dylib enjeksiyonu ile rootful desteği, Carmow branding'i ve ek paket yöneticileri eklendi.

**Hedef cihaz:** iPad 7,3 (A10X, arm64) — iOS 15.5 (19F77, xnu-8020.122.1)
**Bundle ID:** `com.carmow.what`
**Dağıtım:** `eulak/dist` GitHub repo → GitHub Pages → TrollStore

---

## Mimari

### Katmanlar

```
Carmow.ipa
├── Payload/Carmow.app/
│   ├── Carmow              ← Dopamine 3.0.13 binary (renamed, LC_LOAD_DYLIB injected)
│   ├── Info.plist           ← com.carmow.what, v3.2.0
│   ├── PkgManagers.plist    ← Sileo + Zebra + Cydia
│   ├── Credits.plist        ← "by eulak"
│   ├── Themes.plist         ← Carmow temalı
│   ├── *.lproj/             ← 26 dil, "Dopamine" → "Carmow"
│   ├── Assets.car           ← Orijinal Dopamine asset'leri
│   ├── carmow-rootful       ← Standalone rootful helper binary (arm64)
│   ├── Frameworks/
│   │   ├── kfd.framework/           ← opa334'ün kfd fork'u (physpuppet/landa/smith)
│   │   ├── ClearSword.framework/    ← PPL bypass
│   │   ├── DarkSword.framework/     ← SPTM bypass
│   │   ├── Titan.framework/         ← Kernel exploit helper
│   │   ├── weightBufs.framework/    ← Alternatif exploit
│   │   ├── multicast_bytecopy.framework/
│   │   ├── badRecovery.framework/
│   │   ├── dmaFail.framework/
│   │   ├── momentarius.framework/
│   │   └── CarmowRootful.framework/ ← YENİ: Rootful switch + settings hook
│   ├── basebin/             ← Dopamine BaseBin (jbserver, systemhook, etc.)
│   └── basebin.tc           ← Trust cache
```

### Exploit Zinciri (Dopamine'den aynen)

1. **XPF** (eXtensible Patchfinder) — kernelcache'den offset'leri dinamik bulur
2. **kfd** — physpuppet (iOS 15.0-15.7.3, öncelik 1000) veya landa (iOS 15.0-15.8.6, öncelik 900)
3. **IOSurface R/W** — kread_IOSurface + kwrite_IOSurface (sem_open DEĞİL)
4. **Physical R/W primitive** oluşturulur
5. Exploit temizlenir
6. **Yetki yükseltme:** uid 0, unsandbox, CS_PLATFORM_BINARY
7. **BaseBin** yüklenir: trustcache, jbserver, systemhook, launchdhook
8. **Bootstrap** kurulur (/var/jb → Procursus)
9. **Paket yöneticisi** kurulur (Sileo/Zebra/Cydia)

### CarmowRootful.dylib

`CarmowRootful.framework/CarmowRootful` — runtime hook dylib'i.

**Nasıl çalışıyor:**
- `__attribute__((constructor))` ile otomatik yüklenir
- `DOSettingsController.viewDidLoad` methodunu swizzle eder
- Ayarlar sayfasının sonuna "Carmow Rootful" bölümü ekler:
  - UISwitch toggle (NSUserDefaults'a kayıt)
  - "Rootful Overlay Oluştur" butonu
  - Durum etiketi (bindfs mount sayısı)
- `CarmowRootfulHandler` sınıfı buton aksiyonlarını yönetir

**FakeFS Overlay mekanizması:**
- `/private/var/rootful/` altında overlay dizinleri oluşturur
- Sistem dizinlerini (/Applications, /usr/bin, /usr/lib, vb.) symlink ile kopyalar
- Yeni dosyalar overlay'a yazılabilir
- Dopamine'in mevcut bindfs mount'ları (/System, /usr, /usr/lib) zaten yazılabilir

**Kısıtlama:** iOS 15.5'in SSV (Sealed System Volume) koruması nedeniyle gerçek rootfs remount mümkün değil. Bu overlay yaklaşımı "fake rootful" — yazılabilir bir katman sağlar ama boot snapshot'ını değiştirmez.

### LC_LOAD_DYLIB Enjeksiyonu

Ana Carmow binary'sine `@rpath/CarmowRootful.framework/CarmowRootful` load command'ı Python ile enjekte edildi:
- Mach-O header'daki `ncmds` ve `sizeofcmds` güncellendi
- Mevcut load command'lardan sonraki padding alanına yazıldı
- FAT binary desteği var (arm64 slice offset'i otomatik bulunur)

---

## Geçmiş Sürümler ve Denenmiş Yaklaşımlar

### v1.0 – v1.3.x (Trigon tabanlı, başarısız)

**Trigon exploit (CVE-2023-32434):**
- IOSurface + mach_make_memory_entry_64 integer overflow
- PurpleGfxMem GPU carveout üzerinden fiziksel bellek okuma
- **SONUÇ:** GPU carveout sadece GPU belleği içeriyor. Kernel struct'ları alt DRAM'da, geriye doğru tarama vm_read_overwrite SEA (Synchronous External Abort) ile crash.

**Trigon step'leri (0-11):** Her biri ayrı ayrı test edildi
- Step 0-5: IOSurface + overflow entry oluşturma ✓
- Step 6-7: Proc struct tarama (32MB forward) — hiçbir şey bulunamadı
- Step 9: Beyond-alloc read crash → devre dışı bırakıldı
- Step 10: Fresh scan — sadece 31 data page (GPU firmware)
- Step 11: PA-wrap probes — crash, devre dışı bırakıldı

**kfd entegrasyonu (felix-pb/kfd):**
- Step 12 olarak eklendi
- Tahmini offset'ler (proc__p_pid=0x68, proc__p_fd__fd_ofiles=0x100)
- `kread_sem_open` + `kwrite_sem_open` kullanıldı — YANLIŞ (iOS 15'te IOSurface R/W lazım)
- longjmp + signal handler eklendi (crash koruması)
- kern.version 21.5.0 eşlemesi düzeltildi
- **SONUÇ:** Hardcoded offset'ler yanlış, kfd arm64'te bilinen sorunlar var

### v2.0 – v3.0 (Dopamine rebranding)

- Dopamine 3.0.13 IPA indirildi
- Bundle ID, isim, lokalizasyonlar, credits değiştirildi
- carmow-rootful standalone binary eklendi
- **SONUÇ:** Jailbreak çalıştı ama rootful mekanizması eksik

### v3.1.x (carmow-rootful helper)

- `/var/jb/rootful/` → "Operation not permitted" (Dopamine korumalı alan)
- `/private/var/rootful/` → çalışıyor ama standalone binary trust cache'de değil → SIGKILL
- `ldid -s` sonrası çalıştı, overlay oluşturuldu
- bindfs mount'lar zaten Dopamine tarafından kurulmuş

### v3.2.0 (dylib enjeksiyonu — mevcut)

- CarmowRootful.dylib derlenip framework olarak eklendi
- LC_LOAD_DYLIB inject ile ana binary'ye bağlandı
- Ayarlar sayfasına rootful toggle eklendi
- PkgManagers'a Cydia eklendi

---

## Build Süreci

### Bu Sandbox'ta (Linux)

```bash
# Dylib derleme
SDK=/opt/toolchain/sdks/iPhoneOS16.5.sdk
clang -target arm64-apple-ios15.0 -isysroot "$SDK" \
    -fobjc-arc -Os -c -o CarmowRootful.o CarmowRootful.m
lld -flavor darwin -arch arm64 \
    -platform_version ios 15.0.0 16.5.0 \
    -syslibroot "$SDK" -dylib \
    -install_name @rpath/CarmowRootful.framework/CarmowRootful \
    -framework Foundation -framework UIKit -framework CoreGraphics \
    -lSystem -lobjc -adhoc_codesign \
    -o CarmowRootful
pyldid -S CarmowRootful
```

### IPA Oluşturma

1. Dopamine 3.0.13 IPA indir (`/releases/latest/download/Dopamine.ipa`)
2. Aç, `Dopamine.app` → `Carmow.app` rename
3. Info.plist rebrand
4. Lokalizasyonlar rebrand (26 dil)
5. CarmowRootful.framework ekle
6. LC_LOAD_DYLIB inject (Python Mach-O patcher)
7. PkgManagers.plist güncelle
8. `pyldid --entitlements` ile re-sign
9. zip → Carmow.ipa

### Derleme Yapılamayan Şeyler (Xcode gerekli)

- Dopamine ana binary'si (xcodeproj + SwiftUI views + ObjC + 6 submodule)
- BaseBin bütünü (arm64 + arm64e fat binary, macOS libtool, xcrun bağımlı Makefile'lar)
- Exploit framework'leri (kfd, ClearSword, DarkSword, Titan, vb.)

**Windows build denemesi:** `build-carmow.bat` + WSL2 + build.sh denendi. ChOma .o dosyaları derlendi ama libtool → llvm-ar ve lld patching'i yetersiz kaldı. Tam derleme macOS + Xcode gerektiriyor.

---

## Dağıtım

### GitHub Pages

- Repo: `eulak/dist` (public)
- URL: `https://eulak.github.io/dist/carmow/`
- Dosyalar: `Carmow.ipa`, `version.json`, `config.json`, `build.sh`

### version.json formatı

```json
{
  "version": "3.2.0",
  "build": 16,
  "url": "https://eulak.github.io/dist/carmow/Carmow.ipa",
  "notes": "...",
  "min_ios": "15.0"
}
```

### CDN Cache Sorunu

GitHub Pages CDN 5-10 dakika cache'liyor. `raw.githubusercontent.com` da aynı. Çözüm: GitHub API kullan (`api.github.com/repos/eulak/dist/contents/carmow/version.json`) — her zaman taze.

---

## Bilinen Sorunlar ve Yapılacaklar

1. **Rootful overlay gerçek rootfs değil** — SSV nedeniyle boot snapshot değiştirilemiyor. Gerçek rootful için palera1n (checkm8, bilgisayar gerekli) veya NekoJB'nin fakefs kodu lazım
2. **Cydia .deb dosyası IPA'da yok** — PkgManagers'a eklendi ama bootstrap'ta cydia.deb olmayabilir
3. **CarmowRootful.dylib UI'ı basit** — scroll view'a eklenen static view, Dopamine'in native tablo yapısına tam entegre değil
4. **Lokalizasyonlar "0 dosya" diyor** — Binary plist okuma sorunu olabilir, kontrol edilmeli
5. **build-carmow.bat** Windows'tan tam derleme yapamıyor — macOS gerekli

---

## Dosya Konumları (Sandbox)

- Dopamine kaynak kodu: `/home/claude/opa334/dopamine/`
- Mevcut Carmow IPA (extracted): `/tmp/dopamine-dl/extracted/`
- CarmowRootful dylib kaynağı: `/tmp/carmow-dylib/CarmowRootful.m`
- Son IPA: `/tmp/dopamine-dl/Carmow-rootful.ipa`
- dist repo (clone): `/tmp/dist-fresh/`
- Eski Trigon tabanlı Carmow: `/home/claude/work/project/DopamineJB/`

---

## Sonraki Sohbet İçin Hızlı Başlangıç

1. Bu dosyayı oku
2. `eulak/dist` repo'sundan son `carmow/version.json`'ı kontrol et
3. Değişiklik gerekiyorsa:
   - Dylib değişikliği → `/tmp/carmow-dylib/CarmowRootful.m` düzenle, derle, IPA'ya ekle
   - Branding değişikliği → `/tmp/dopamine-dl/extracted/` içinde plist'leri düzenle
   - Yeni sürüm → IPA'yı paketle, `dist` repo'ya push et
4. `build-carmow.bat` Windows build scripti — WSL2 + GitHub API ile build.sh indirir
