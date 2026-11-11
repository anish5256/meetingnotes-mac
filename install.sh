#!/bin/bash
# One-command setup for MeetingNotes:
#   1. checks the Mac, 2. installs ffmpeg + Python via Homebrew if missing,
#   3. sets up the transcription engine (voice-memo-transcriber) with its models,
#   4. builds MeetingNotes.app and puts it in ~/Applications.
# Safe to re-run (it skips what is already done). Usage: bash install.sh
# Options (env vars): TRANSCRIBER_DIR (default ~/voice-memo-transcriber), APP_DEST (default ~/Applications),
#                     NO_OPEN=1 (don't launch at the end), SKIP_SETTINGS=1 (don't write the app's engine path)
set -euo pipefail
TRANSCRIBER_DIR="${TRANSCRIBER_DIR:-$HOME/voice-memo-transcriber}"
TRANSCRIBER_REPO="${TRANSCRIBER_REPO:-https://github.com/anish5256/voice-memo-transcriber.git}"
APP_DEST="${APP_DEST:-$HOME/Applications}"
HERE="$(cd "$(dirname "$0")" && pwd)"
step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\n\033[31mERROR:\033[0m %s\n" "$1" >&2; exit 1; }

step "1/4 Checking your Mac"
[ "$(uname -m)" = "arm64" ] || fail "MeetingNotes needs an Apple Silicon Mac (M1 or newer)."
version="$(sw_vers -productVersion)"
[ "${version%%.*}" -ge 14 ] || fail "macOS 14 (Sonoma) or newer is required. You have $version."
command -v brew >/dev/null || fail "Homebrew is missing. Install it from https://brew.sh, then run: bash install.sh"
xcode-select -p >/dev/null 2>&1 || fail "Apple's developer tools are missing. Run: xcode-select --install   (then run this again)"
command -v swift >/dev/null || fail "The Swift compiler was not found. Run: xcode-select --install"
command -v git >/dev/null || fail "git is missing. Run: xcode-select --install"
echo "OK: $(sw_vers -productName) $version on Apple Silicon"

step "2/4 Installing tools (ffmpeg, Python 3.12)"
brew list ffmpeg >/dev/null 2>&1 || brew install ffmpeg
PY="$(command -v python3.12 || true)"
if [ -z "$PY" ]; then brew install python@3.12; PY="$(brew --prefix python@3.12)/bin/python3.12"; fi
echo "OK: $("$PY" --version), $(ffmpeg -version | head -1 | cut -d' ' -f1-3)"

step "3/4 Setting up the transcription engine in $TRANSCRIBER_DIR"
if [ -d "$TRANSCRIBER_DIR/.git" ]; then
    echo "Found an existing copy, keeping it (update it yourself with: git -C \"$TRANSCRIBER_DIR\" pull)."
else
    git clone "$TRANSCRIBER_REPO" "$TRANSCRIBER_DIR" || fail "Could not download the transcription engine. If the repo is private, run 'gh auth login' first or ask the owner for access."
fi
cd "$TRANSCRIBER_DIR"
[ -x venv/bin/python ] || "$PY" -m venv venv
venv/bin/python -m pip install -q --upgrade pip
venv/bin/python -m pip install -q -r requirements.txt
if [ -s models/nemo_en_titanet_small.onnx ] && [ -s models/sherpa-onnx-pyannote-segmentation-3-0/model.onnx ] \
   && [ -s models/3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx ]; then
    echo "Speaker models already present."
else
    bash scripts/download_models.sh models >/dev/null
fi
venv/bin/python -I -c "import mlx_whisper, sherpa_onnx, scipy, soundfile, anthropic" || fail "Python packages did not install correctly."
echo "OK: engine ready (the speech model, ~3 GB, downloads automatically on the first recording)"

step "4/4 Building MeetingNotes.app"
cd "$HERE"
bash build_app.sh >/dev/null
mkdir -p "$APP_DEST"
rm -rf "$APP_DEST/MeetingNotes.app"
cp -R build/MeetingNotes.app "$APP_DEST/"
if [ "${SKIP_SETTINGS:-0}" != 1 ] && [ "$TRANSCRIBER_DIR" != "$HOME/voice-memo-transcriber" ]; then
    defaults write com.anish.meetingnotes repoPath -string "$TRANSCRIBER_DIR"
fi
echo "OK: installed $APP_DEST/MeetingNotes.app"

printf "\n\033[1mAll set.\033[0m Next: open MeetingNotes and connect ChatGPT or Claude in Settings > Accounts (see README).\n"
[ "${NO_OPEN:-0}" = 1 ] || open "$APP_DEST/MeetingNotes.app"
