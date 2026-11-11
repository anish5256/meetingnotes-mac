#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TRANSCRIBER_DIR="${TRANSCRIBER_DIR:-$HOME/voice-memo-transcriber}"
fail() { echo "ERROR: $*" >&2; exit 1; }
[ -f "$TRANSCRIBER_DIR/requirements-engine.txt" ] || fail "Missing $TRANSCRIBER_DIR/requirements-engine.txt. Set TRANSCRIBER_DIR to the transcription pipeline checkout."
TRANSCRIBER_DIR="$(cd "$TRANSCRIBER_DIR" && pwd)"
mkdir -p build/cache
archive="$PWD/build/cache/cpython-3.12.16+20261110-aarch64-apple-darwin-install_only.tar.gz"
if [ ! -f "$archive" ]; then
    curl --fail --location --retry 3 'https://github.com/astral-sh/python-build-standalone/releases/download/20261110/cpython-3.12.16%2B20261110-aarch64-apple-darwin-install_only.tar.gz' -o "$archive.part"
    mv "$archive.part" "$archive"
fi
# Recreate the payload so previous builds cannot leave stale packages or scripts.
rm -rf build/engine
mkdir -p build/engine/app/models build/engine/bin
tar -xzf "$archive" -C build/engine
engine="$PWD/build/engine"
python="$engine/python/bin/python3"
"$python" --version
export PIP_NO_CACHE_DIR=1
# Prevent optional dependency resolution from pulling in torch.
"$python" -m pip install --no-deps mlx-whisper
constraints="$PWD/build/cache/engine-constraints.txt"
printf 'torch===meetingnotes-does-not-bundle-torch\n' > "$constraints"
"$python" -m pip install -c "$constraints" -r "$TRANSCRIBER_DIR/requirements-engine.txt"
"$python" -c 'import importlib.util; assert importlib.util.find_spec("torch") is None, "torch must not be bundled"'
for source in "$TRANSCRIBER_DIR"/*.py; do
    [ -f "$source" ] || continue
    case "$(basename "$source")" in test_*.py|*_test.py) continue ;; esac
    cp "$source" "$engine/app/"
done
[ -d "$TRANSCRIBER_DIR/scripts" ] || fail "Missing pipeline scripts directory."
rsync -a --exclude tests --exclude venv --exclude models --exclude docs "$TRANSCRIBER_DIR/scripts/" "$engine/app/scripts/"
models=(nemo_en_titanet_small.onnx sherpa-onnx-pyannote-segmentation-3-0/model.onnx 3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx)
missing=0
for model in "${models[@]}"; do
    if [ -s "$TRANSCRIBER_DIR/models/$model" ]; then
        mkdir -p "$engine/app/models/$(dirname "$model")"
        cp "$TRANSCRIBER_DIR/models/$model" "$engine/app/models/$model"
    else
        missing=1
    fi
done
if [ "$missing" = 1 ]; then
    (cd "$engine/app" && bash scripts/download_models.sh "$engine/app/models")
fi
for model in "${models[@]}"; do
    [ -s "$engine/app/models/$model" ] || fail "Speaker model missing: $model"
done
version="$(git -C "$TRANSCRIBER_DIR" describe --always --dirty 2>/dev/null || true)"
printf '%s\n' "${version:-unknown}" > "$engine/app/ENGINE_VERSION"
ffmpeg="$("$python" -c 'import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())')"
cp "$ffmpeg" "$engine/bin/ffmpeg"
chmod +x "$engine/bin/ffmpeg"
"$python" -m pip cache purge 2>/dev/null || true
find "$engine/python" -type d -name site-packages -print0 | while IFS= read -r -d '' site; do
    find "$site" -type d -name tests -prune -exec rm -rf {} +
done
"$python" -I -c "import mlx_whisper, sherpa_onnx, scipy, soundfile, anthropic, imageio_ffmpeg"
du -sh "$engine"/*
