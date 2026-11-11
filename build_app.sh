#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/mcache"
swift build -c release --cache-path .build/cache --config-path .build/config --security-path .build/security
bin_dir="$(swift build -c release --cache-path .build/cache --config-path .build/config --security-path .build/security --show-bin-path)"
app="$PWD/build/MeetingNotes.app"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/MeetingNotes" "$app/Contents/MacOS/MeetingNotes"
cp Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [ -d build/engine ]; then
    rsync -a --delete build/engine/ "$app/Contents/Resources/engine/"
    # Sign leaves before the enclosing app. Symlinks retain their targets' signatures.
    while IFS= read -r -d '' binary; do
        case "$binary" in
            *.so|*.dylib) codesign --force --sign - --timestamp=none "$binary" ;;
            *) if file -b "$binary" | grep -q 'Mach-O'; then
                   codesign --force --sign - --timestamp=none "$binary"
               fi ;;
        esac
    done < <(find "$app/Contents/Resources/engine" -depth -type f -print0)
else
    rm -rf "$app/Contents/Resources/engine"
fi
codesign --force --sign - --timestamp=none "$app"
printf '%s\n' "$app"
