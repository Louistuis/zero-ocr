#!/bin/bash
# Builds "Zero OCR.app" (ad-hoc signed) for Apple silicon or, with --intel, the lighter Intel edition,
# and with --dmg a drag-to-install DMG.
#   ./build.sh                  build/Zero OCR.app (Apple silicon)
#   ./build.sh --install        also copy to ~/Applications and launch
#   ./build.sh --dmg            also package build/Zero-OCR.dmg
#   ./build.sh --intel [--dmg]  build/intel/Zero OCR.app (x86_64) and build/Zero-OCR-Intel.dmg
# Needs only the Command Line Tools. llama.cpp comes from its official releases, pinned below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
INTEL=0; ACTION=""
for a in "$@"; do
    case "$a" in
    --intel) INTEL=1 ;;
    --install|--dmg) ACTION="$a" ;;
    *) echo "usage: ./build.sh [--intel] [--install|--dmg]"; exit 1 ;;
    esac
done
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
LLAMA="b11753"
if [ $INTEL = 1 ]; then
    # CPU only, no AVX-512, macOS 13.3 or later: runs on every 2018 and later Intel Mac.
    ARCH="x86_64"; ASSET="macos-x64"; SHAFILE="$ROOT/app/llama-x64.sha256"; VENDOR="$ROOT/app/vendor/llama-$LLAMA-x64"
    BUILD="$ROOT/build/intel"; DMGNAME="Zero-OCR-Intel.dmg"; VOLNAME="Zero OCR for Intel"
    HELPERS="libggml-cpu.0.dylib libggml-blas.0.dylib"
else
    ARCH="arm64"; ASSET="macos-arm64"; SHAFILE="$ROOT/app/llama.sha256"; VENDOR="$ROOT/app/vendor/llama-$LLAMA"
    BUILD="$ROOT/build"; DMGNAME="Zero-OCR.dmg"; VOLNAME="Zero OCR"
    HELPERS="libggml-cpu.0.dylib libggml-blas.0.dylib libggml-metal.0.dylib"
fi
APP="$BUILD/Zero OCR.app"
LLAMA_SHA="$(tr -d '[:space:]' < "$SHAFILE")"
if [ $INTEL = 1 ] && [ "$ACTION" = "--install" ] && [ "$(uname -m)" = "arm64" ]; then
    echo "✗ Not installing the Intel edition on an Apple silicon Mac. Test it from build/intel."; exit 1
fi

echo "▸ llama.cpp $LLAMA ($ASSET)"
if [ ! -x "$VENDOR/llama-server" ]; then
    mkdir -p "$ROOT/app/vendor"
    TGZ="$ROOT/app/vendor/llama-$LLAMA-$ASSET.tar.gz"
    curl -fsSL -o "$TGZ" "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA/llama-$LLAMA-bin-$ASSET.tar.gz"
    echo "$LLAMA_SHA  $TGZ" | shasum -a 256 -c - >/dev/null || { echo "✗ llama.cpp checksum mismatch"; exit 1; }
    # Both archives unpack to llama-$LLAMA, so unpack aside and move into place.
    TMP="$(mktemp -d "$ROOT/app/vendor/.unpack.XXXX")"
    tar -xzf "$TGZ" -C "$TMP"
    rm -rf "$VENDOR"; mv "$TMP/llama-$LLAMA" "$VENDOR"
    rm -rf "$TMP" "$TGZ"
fi

echo "▸ Compiling ($ARCH)"
cd "$ROOT/app"
swift build -c release --arch "$ARCH" 2>&1 | grep -E "error:" && exit 1 || true
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"

echo "▸ Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp "$BIN/ZeroOCR" "$APP/Contents/MacOS/ZeroOCR"
strip -rSTx "$APP/Contents/MacOS/ZeroOCR"
# llama-server and the libraries it loads from @loader_path; the other llama.cpp tools are left out.
for f in llama-server libllama-server-impl.dylib libllama-common.0.dylib libmtmd.0.dylib libllama.0.dylib \
         libggml.0.dylib libggml-rpc.0.dylib libggml-base.0.dylib $HELPERS; do
    cp -L "$VENDOR/$f" "$APP/Contents/Helpers/$f"
done
cp "$VENDOR/LICENSE" "$APP/Contents/Resources/LICENSE-llama.cpp.txt"
# marked + KaTeX for formatted results; the Intel edition draws them natively instead.
[ $INTEL = 1 ] || cp -R "$ROOT/app/Resources/web" "$APP/Contents/Resources/web"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

ICONS="$ROOT/build"
mkdir -p "$ICONS"
if [ ! -f "$ICONS/AppIcon.icns" ] || [ "$ROOT/app/Tools/makeicon.swift" -nt "$ICONS/AppIcon.icns" ]; then
    swift "$ROOT/app/Tools/makeicon.swift" "$ICONS/icon1024.png"
    ICONSET="$ICONS/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" \
                "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" "$ICONS/icon1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$ICONS/AppIcon.icns"
fi
cp "$ICONS/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Services: NSSendFileTypes puts them in Finder's right-click Quick Actions for images and PDFs,
# NSSendTypes in any app where an image is selected.
service() {
    cat <<SVC
        <dict>
            <key>NSMessage</key>         <string>$1</string>
            <key>NSPortName</key>        <string>Zero OCR</string>
            <key>NSMenuItem</key>        <dict><key>default</key><string>$2</string></dict>
            <key>NSSendFileTypes</key>   <array><string>public.image</string><string>com.adobe.pdf</string></array>
            <key>NSSendTypes</key>       <array><string>public.png</string><string>public.tiff</string><string>NSFilenamesPboardType</string></array>
            <key>NSRequiredContext</key> <dict/>
        </dict>
SVC
}

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>Zero OCR</string>
    <key>CFBundleDisplayName</key>        <string>Zero OCR</string>
    <key>CFBundleIdentifier</key>         <string>com.lou15.zeroocr</string>
    <key>CFBundleExecutable</key>         <string>ZeroOCR</string>
    <key>CFBundleIconFile</key>           <string>AppIcon</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$VERSION</string>
    <key>NSHumanReadableCopyright</key>   <string>© 2026 Louis Nordbø. MIT licensed.</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>LSArchitecturePriority</key>     <array><string>$ARCH</string></array>
    <key>NSSupportsAutomaticGraphicsSwitching</key> <true/>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Zero OCR reads the text in the area you select.</string>
    <key>CFBundleURLTypes</key>
    <array><dict>
        <key>CFBundleURLName</key>    <string>Zero OCR</string>
        <key>CFBundleURLSchemes</key> <array><string>zeroocr</string></array>
    </dict></array>
    <key>CFBundleDocumentTypes</key>
    <array><dict>
        <key>CFBundleTypeName</key>   <string>Image or PDF</string>
        <key>CFBundleTypeRole</key>   <string>Viewer</string>
        <key>LSHandlerRank</key>      <string>Alternate</string>
        <key>LSItemContentTypes</key> <array><string>public.image</string><string>com.adobe.pdf</string></array>
    </dict></array>
    <key>NSServices</key>
    <array>
$(service readText "Copy Text with Zero OCR")
$(service readTable "Copy Table with Zero OCR")
$(service readDocument "Copy as Markdown with Zero OCR")
    </array>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing"
# An ad-hoc signature's default requirement is its own hash, so macOS would forget the Screen
# Recording permission on every update. Requiring only the bundle identifier keeps it.
for f in "$APP/Contents/Helpers/"*; do codesign --force --sign - "$f" 2>/dev/null; done
codesign --force --sign - --identifier com.lou15.zeroocr -r='designated => identifier "com.lou15.zeroocr"' "$APP" 2>/dev/null
codesign --verify --deep "$APP"

case "$ACTION" in
--install)
    osascript -e 'tell application id "com.lou15.zeroocr" to quit' 2>/dev/null || true
    pkill -x ZeroOCR 2>/dev/null || true
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Zero OCR.app"
    cp -R "$APP" "$HOME/Applications/"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/Zero OCR.app"
    /System/Library/CoreServices/pbs -update 2>/dev/null || true
    open -g "$HOME/Applications/Zero OCR.app"
    echo "✓ installed to ~/Applications"
    ;;
--dmg)
    DMG="$ROOT/build/$DMGNAME"   # one name per edition for every version, so releases/latest/download/ always works
    STAGE="$BUILD/dmg"
    rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format ULFO "$DMG"
    rm -rf "$STAGE"
    shasum -a 256 "$DMG"
    echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
    ;;
*) echo "✓ $APP" ;;
esac
