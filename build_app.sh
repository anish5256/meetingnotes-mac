#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/mcache"
# Relative source paths in the binary (no build-machine paths in the shipped app).
swift build -c release --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -file-prefix-map -Xswiftc "$PWD=."
bin_dir="$(swift build -c release --cache-path .build/cache --config-path .build/config --security-path .build/security -Xswiftc -file-prefix-map -Xswiftc "$PWD=." --show-bin-path)"
app="$PWD/build/MeetingNotes.app"
# A stable signing identity keeps macOS permissions (mic, calendar, system audio) across updates;
# ad-hoc signing ("-") gives every build a new identity, so macOS would ask again after each update.
SIGN_ID="${CODESIGN_IDENTITY:-}"
if [ -z "$SIGN_ID" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q '"MeetingNotes Local Signing"'; then
    SIGN_ID="MeetingNotes Local Signing"
fi
SIGN_ID="${SIGN_ID:--}"
mkdir -p "$app/Contents/MacOS"
cp "$bin_dir/MeetingNotes" "$app/Contents/MacOS/MeetingNotes"
# Drop debug symbols: they record this machine's build paths and aren't needed to run.
strip -S -x "$app/Contents/MacOS/MeetingNotes"
cp Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Resources"
cp Resources/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
if [ -d build/engine ]; then
    rsync -a --delete build/engine/ "$app/Contents/Resources/engine/"
    # Sign leaves before the enclosing app. Symlinks retain their targets' signatures.
    while IFS= read -r -d '' binary; do
        case "$binary" in
            *.so|*.dylib) codesign --force --sign "$SIGN_ID" --timestamp=none "$binary" ;;
            *) if file -b "$binary" | grep -q 'Mach-O'; then
                   codesign --force --sign "$SIGN_ID" --timestamp=none "$binary"
               fi ;;
        esac
    done < <(find "$app/Contents/Resources/engine" -depth -type f -print0)
else
    rm -rf "$app/Contents/Resources/engine"
fi
codesign --force --sign "$SIGN_ID" --timestamp=none "$app"
printf '%s (signed: %s)\n' "$app" "$SIGN_ID"
