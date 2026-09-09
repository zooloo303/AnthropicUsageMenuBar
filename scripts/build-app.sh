#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$repo_dir/.build/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$repo_dir/.build/swift-cache}"
swift build -c release --product AnthropicUsageMenuBar --disable-sandbox --cache-path "$repo_dir/.build/spm-cache"
bin_dir="$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$repo_dir/.build/spm-cache")"
app_dir="$repo_dir/dist/Usage Menu Bar.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/AnthropicUsageMenuBar" "$app_dir/Contents/MacOS/UsageMenuBar"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>com.zooloo303.UsageMenuBar</string>
    <key>CFBundleName</key><string>Usage Menu Bar</string>
    <key>CFBundleDisplayName</key><string>Usage Menu Bar</string>
    <key>CFBundleExecutable</key><string>UsageMenuBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$app_dir"
codesign --verify --strict "$app_dir"
printf 'Built %s\n' "$app_dir"
