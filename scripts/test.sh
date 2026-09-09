#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_dir"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$repo_dir/.build/clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$repo_dir/.build/swift-cache}"
# Command Line Tools ships Swift Testing outside SwiftPM's default search path.
developer_dir="$(xcode-select -p)"
framework_dir="$developer_dir/Library/Developer/Frameworks"
extra_flags=()
if [[ -d "$framework_dir/Testing.framework" ]]; then
    extra_flags=(-Xswiftc -F -Xswiftc "$framework_dir" -Xlinker -rpath -Xlinker "$framework_dir"
        -Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib")
fi
swift test --disable-xctest --enable-swift-testing --disable-sandbox \
    --cache-path "$repo_dir/.build/spm-cache" "${extra_flags[@]}" "$@"
