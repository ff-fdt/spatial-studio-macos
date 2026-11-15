#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-release}"
swift build -c "$mode" --product SpatialDesk
bin="$(swift build -c "$mode" --show-bin-path)"
app="${SPATIAL_DESK_OUTPUT_DIR:-dist}/Spatial Studio.app"
bundle_id="${SPATIAL_DESK_BUNDLE_ID:-local.spatialdesk.asmr}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin/SpatialDesk" "$app/Contents/MacOS/SpatialDesk"
ditto "$bin/SpatialDesk_SpatialDesk.bundle" "$app/Contents/Resources/SpatialDesk_SpatialDesk.bundle"
cp "Sources/SpatialEngine/LICENSE-atmos-control.txt" "$app/Contents/Resources/"
cp "Sources/NearFieldDVF/LICENSE.txt" "$app/Contents/Resources/LICENSE-SAF-DVF.txt"
icon_root="$(mktemp -d "${TMPDIR:-/tmp}/spatial-studio-icon.XXXXXX")"
trap 'rm -rf "$icon_root"' EXIT
swift scripts/make-app-icon.swift "$icon_root/SpatialStudio.iconset"
iconutil -c icns "$icon_root/SpatialStudio.iconset" -o "$app/Contents/Resources/SpatialStudio.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Spatial Studio</string>
<key>CFBundleDisplayName</key><string>Spatial Studio</string>
<key>CFBundleIdentifier</key><string>local.spatialdesk.asmr</string>
<key>CFBundleExecutable</key><string>SpatialDesk</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleIconFile</key><string>SpatialStudio.icns</string>
<key>CFBundleShortVersionString</key><string>0.27</string>
<key>CFBundleVersion</key><string>27</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>NSAudioCaptureUsageDescription</key><string>Spatial Studio processes your Mac’s audio in real time and plays it back through your headphones.</string>
</dict></plist>
PLIST
plutil -replace CFBundleIdentifier -string "$bundle_id" "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources/en.lproj" "$app/Contents/Resources/zh-Hans.lproj"
printf '%s\n' '"NSAudioCaptureUsageDescription" = "Spatial Studio processes your Mac’s audio in real time and plays it back through your headphones.";' > "$app/Contents/Resources/en.lproj/InfoPlist.strings"
printf '%s\n' '"NSAudioCaptureUsageDescription" = "Spatial Studio 实时调整 Mac 播放的系统声音，并将结果送回耳机。";' > "$app/Contents/Resources/zh-Hans.lproj/InfoPlist.strings"
python3 scripts/sign-local-app.py "$app"
(cd "$(dirname "$app")" && printf '%s/%s\n' "$PWD" "$(basename "$app")")
