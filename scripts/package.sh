#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${SKIP_ENGINE:-0}" != 1 ]; then
    bash scripts/build_engine.sh
fi
bash build_app.sh
mkdir -p dist
rm -f dist/MeetingNotes.zip
ditto -c -k --sequesterRsrc --keepParent build/MeetingNotes.app dist/MeetingNotes.zip
du -sh dist/MeetingNotes.zip
