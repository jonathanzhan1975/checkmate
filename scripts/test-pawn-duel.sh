#!/bin/bash
set -euo pipefail
# Silent test-host acceptance: every lesson mini-game takes a clicked move and the computer replies, and a game won by
# a clicked move opens its post-game review sheet (WI-018), whose Read Aloud uses a silent local speech driver,
# reads the exact proved text with zero model/microphone calls, and stops on Stop, close and restart.
checkmate_pawn_evidence=${CHECKMATE_EVIDENCE_DIR:-$(mktemp -d /tmp/checkmate-pawn-duel.XXXXXX)}
export CHECKMATE_EVIDENCE_DIR="$checkmate_pawn_evidence"
mkdir -p "$checkmate_pawn_evidence"
cd "$(dirname "$0")/.."
python3 - "$checkmate_pawn_evidence" <<'PYHELPER'
import pathlib,sys
sys.path.insert(0,'scripts')
import app_driver
app_driver.compile_helpers(pathlib.Path(sys.argv[1]),{'pointer-helper':'mini-review-pointer-helper'})
PYHELPER
export CHECKMATE_POINTER_HELPER="$checkmate_pawn_evidence/mini-review-pointer-helper"
export CHECKMATE_DEEPSEEK_FIXTURE=1
export DEEPSEEK_API_KEY=sk-checkmate-fixture-only
exec bash scripts/test-scenario.sh --log pawn-duel-app.log --show passed --show games --show 'review?' --exited 'Mini-game scenario exited before writing results' --pawn-duel-scenario pawn-duel-results.json 120
