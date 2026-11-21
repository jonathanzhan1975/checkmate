#!/bin/bash
# The unit gate: the legacy-store export round trip, both XCTest bundles and the Python self-tests.
# SwiftPM builds with the user's temp folder, where its lock files coordinate concurrent builds of this checkout
# (it also leaves empty TemporaryDirectory.* folders there). The test bundles then run directly under the gate's
# private TMPDIR, so anything a test leaves behind fails the gate (scripts/run-gates.py).
set -euo pipefail
cd "$(dirname "$0")/.."
evidence=${CHECKMATE_EVIDENCE_DIR:?Set CHECKMATE_EVIDENCE_DIR}
swiftpm_tmp=$(getconf DARWIN_USER_TEMP_DIR)
xcrun swiftc Tools/legacy-store-test.swift -o "$evidence/legacy-store-test"
"$evidence/legacy-store-test" Tools/legacy-export.js "$evidence/legacy-export.json"
TMPDIR="$swiftpm_tmp" python3 scripts/fresh-sources.py .build -- swift build --build-tests > "$evidence/swift-build-tests.log" 2>&1
bin=$(TMPDIR="$swiftpm_tmp" swift build --show-bin-path)
# Native SwiftPM copies xcstrings without compiling them. Compile the same shipped catalog for tests,
# including English plurals; otherwise tests silently exercise fallback keys instead of localized text.
catalog_resources="$bin/Checkmate_CheckmateAssets.bundle/Resources"
[[ -d "$bin/Checkmate_CheckmateAssets.bundle/Contents/Resources" ]] && catalog_resources="$bin/Checkmate_CheckmateAssets.bundle/Contents/Resources"
xcrun xcstringstool compile Sources/CheckmateCore/Localizable.xcstrings --output-directory "$catalog_resources"
runner=$(xcrun --find xctest)
: > "$evidence/swift-tests.log"
if [[ -d "$bin/CheckmatePackageTests.xctest" ]]; then
  CHECKMATE_LEGACY_EXPORT="$evidence/legacy-export.json" CHECKMATE_AUTOMATION=1 "$runner" -XCTest All -AppleLanguages '(en)' -AppleLocale en_US "$bin/CheckmatePackageTests.xctest" >> "$evidence/swift-tests.log" 2>&1
else
for suite in CheckmateDomainTests CheckmateCoreTests CheckmateNativeTests CheckmateMCPTests; do
  CHECKMATE_LEGACY_EXPORT="$evidence/legacy-export.json" CHECKMATE_AUTOMATION=1 "$runner" -XCTest All -AppleLanguages '(en)' -AppleLocale en_US "$bin/$suite.xctest" >> "$evidence/swift-tests.log" 2>&1
done
fi
python3 -I Tools/test-lesson-action-alignment.py
python3 -I Tools/test-import-cedar.py
python3 -I Tools/test-narration-coverage.py
# Lesson sources: baseline parity, reviewed illustrations, practice relations and current exports.
python3 -I Tools/prepare-lesson-scripts.py --check > /dev/null
python3 -I Tools/test-lesson-rules.py
python3 -I Tools/test-provenance.py
python3 -I Tools/build-game-library.py --check
python3 -I Tools/build-openings.py --check
python3 -I Tools/test-record-lessons.py
python3 -I Tools/prepare-training-content.py --check
python3 -I Tools/test-prepare-training-content.py
# KPK oracle (mini-game plan WI-019): both implementations compared on every legal position.
python3 -I Tools/test-kpk-oracle.py
python3 scripts/test-run-gates.py
python3 scripts/test-ui-locale.py
python3 -I scripts/test-fresh-sources.py
# Every engine and voice entry is classified for network-game fairness (LAN-play plan D8).
python3 -I scripts/test-fairness-inventory.py > /dev/null

# Chinese catalog and bundled course structural validation.
python3 -I scripts/test-chinese-localization.py
