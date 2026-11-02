#!/bin/bash
# Builds "Zero OCR.app" (ad-hoc signed, Apple Silicon) and, with --dmg, a drag-to-install DMG.
#   ./build.sh              build into build/
#   ./build.sh --install    build and copy to ~/Applications, then launch
#   ./build.sh --dmg        build and package build/Zero-OCR-<version>.dmg
# Needs only the Command Line Tools. llama.cpp comes from its official release, pinned below.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Zero OCR.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
LLAMA="b11753"
LLAMA_SHA="$(tr -d '[:space:]' < "$ROOT/app/llama.sha256")"
VENDOR="$ROOT/app/vendor/llama-$LLAMA"

echo "▸ llama.cpp $LLAMA"
if [ ! -x "$VENDOR/llama-server" ]; then
    mkdir -p "$ROOT/app/vendor"
    TGZ="$ROOT/app/vendor/llama-$LLAMA.tar.gz"
    curl -fsSL -o "$TGZ" "https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA/llama-$LLAMA-bin-macos-arm64.tar.gz"
    echo "$LLAMA_SHA  $TGZ" | shasum -a 256 -c - >/dev/null || { echo "✗ llama.cpp checksum mismatch"; exit 1; }
    tar -xzf "$TGZ" -C "$ROOT/app/vendor"
    mv "$ROOT/app/vendor/llama-$LLAMA" "$VENDOR.tmp" 2>/dev/null || true
    [ -d "$VENDOR.tmp" ] && mv "$VENDOR.tmp" "$VENDOR"
    rm -f "$TGZ"
fi

echo "▸ Compiling"
cd "$ROOT/app"
swift build -c release 2>&1 | grep -E "error:" && exit 1 || true

echo "▸ Bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Helpers"
cp .build/release/ZeroOCR "$APP/Contents/MacOS/ZeroOCR"
strip -rSTx "$APP/Contents/MacOS/ZeroOCR"
# llama-server and the libraries it loads from @loader_path; the other llama.cpp tools are left out.
for f in llama-server libllama-server-impl.dylib libllama-common.0.dylib libmtmd.0.dylib libllama.0.dylib \
         libggml.0.dylib libggml-cpu.0.dylib libggml-blas.0.dylib libggml-metal.0.dylib libggml-rpc.0.dylib \
         libggml-base.0.dylib; do
    cp -L "$VENDOR/$f" "$APP/Contents/Helpers/$f"
done
cp "$VENDOR/LICENSE" "$APP/Contents/Resources/LICENSE-llama.cpp.txt"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"

if [ ! -f "$BUILD/AppIcon.icns" ] || [ "$ROOT/app/Tools/makeicon.swift" -nt "$BUILD/AppIcon.icns" ]; then
    swift "$ROOT/app/Tools/makeicon.swift" "$BUILD/icon1024.png"
    ICONSET="$BUILD/AppIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for spec in "16 16x16" "32 16x16@2x" "32 32x32" "64 32x32@2x" "128 128x128" "256 128x128@2x" \
                "256 256x256" "512 256x256@2x" "512 512x512" "1024 512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" "$BUILD/icon1024.png" --out "$ICONSET/icon_$2.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$BUILD/AppIcon.icns"
fi
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

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
    <key>LSArchitecturePriority</key>     <array><string>arm64</string></array>
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
for f in "$APP/Contents/Helpers/"*; do codesign --force --sign - "$f" 2>/dev/null; done
codesign --force --sign - "$APP" 2>/dev/null
codesign --verify --deep "$APP"

case "${1:-}" in
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
    DMG="$BUILD/Zero-OCR-$VERSION.dmg"
    STAGE="$BUILD/dmg"
    rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -quiet -volname "Zero OCR" -srcfolder "$STAGE" -fs HFS+ -format ULFO "$DMG"
    rm -rf "$STAGE"
    shasum -a 256 "$DMG"
    echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
    ;;
*) echo "✓ $APP" ;;
esac
