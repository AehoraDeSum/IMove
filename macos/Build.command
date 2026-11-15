#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${IMOVE_BUILD_DIR:-$project_dir/work}"
mkdir -p "$build_dir/cache" "$build_dir/config" "$build_dir/security" "$build_dir/modules"
export CLANG_MODULE_CACHE_PATH="$build_dir/modules"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/modules"
swift_args=(--package-path "$project_dir" --scratch-path "$build_dir/build" --cache-path "$build_dir/cache" --config-path "$build_dir/config" --security-path "$build_dir/security" --disable-sandbox -c release -debug-info-format none)
swift build "${swift_args[@]}" --product IMove
binary_dir="$(swift build "${swift_args[@]}" --show-bin-path)"
app_dir="$project_dir/IMove.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
bundled_usb="$project_dir/.usb-dist/pymobiledevice3/pymobiledevice3"
if [[ ! -x "$bundled_usb" ]]; then
  echo "Bundled USB tool not found. Run ./BuildUSB.command first." >&2
  exit 1
fi
rm -rf "$app_dir/Contents/Resources/USB"
mkdir -p "$app_dir/Contents/Resources/USB"
ditto "$project_dir/.usb-dist/pymobiledevice3" "$app_dir/Contents/Resources/USB/pymobiledevice3"
cp "$binary_dir/IMove" "$app_dir/Contents/MacOS/IMove"
cp "$project_dir/Guide.html" "$app_dir/Contents/Resources/Guide.html"
cp "$project_dir/Web/Controller.html" "$app_dir/Contents/Resources/Controller.html"
cp "$project_dir/Web/controller.js" "$app_dir/Contents/Resources/controller.js"
cp "$project_dir/Web/iPhoneProbe.html" "$app_dir/Contents/Resources/iPhoneProbe.html"
cp "$project_dir/Web/iphone-probe.js" "$app_dir/Contents/Resources/iphone-probe.js"
cp "$project_dir/Web/Map.html" "$app_dir/Contents/Resources/Map.html"
cp "$project_dir/Web/map.js" "$app_dir/Contents/Resources/map.js"
cp "$project_dir/Web/istanbul-rail.json" "$app_dir/Contents/Resources/istanbul-rail.json"
cp "$project_dir/Web/leaflet.js" "$app_dir/Contents/Resources/leaflet.js"
cp "$project_dir/Web/leaflet.css" "$app_dir/Contents/Resources/leaflet.css"
cp "$project_dir/Web/LEAFLET-LICENSE.txt" "$app_dir/Contents/Resources/LEAFLET-LICENSE.txt"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>IMove</string>
<key>CFBundleIdentifier</key><string>local.imove.prototype</string>
<key>CFBundleName</key><string>IMove</string>
<key>CFBundleDisplayName</key><string>IMove</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>16</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
swift "$project_dir/scripts/DrawIcon.swift" "$build_dir/AppIcon.iconset" "$app_dir/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app_dir"
printf '\nReady: %s\n' "$app_dir"
