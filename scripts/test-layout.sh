#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# The verification below reads the scenario's evidence, so the folder is chosen here rather than in test-scenario.sh.
export CHECKMATE_EVIDENCE_DIR=${CHECKMATE_EVIDENCE_DIR:-$(mktemp -d /tmp/checkmate-ui.XXXXXX)}
# Chinese font layout and ScreenCaptureKit captures can exceed 45 seconds on macOS 26.
# This bounds scenario liveness only; every geometry and overlap assertion still runs below.
bash scripts/test-scenario.sh --stale layout-verification.json --exited 'Layout app exited before writing its results' --show passed --show '#samples' --show failures --layout-scenario layout-results.json 120

python3 scripts/verify-native-layout.py "$CHECKMATE_EVIDENCE_DIR/layout-results.json" > "$CHECKMATE_EVIDENCE_DIR/layout-verification.json"
