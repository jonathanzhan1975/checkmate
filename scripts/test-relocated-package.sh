#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
checkmate_evidence=${CHECKMATE_EVIDENCE_DIR:?}
# A previous result must never satisfy the wait for this run.
rm -f "$checkmate_evidence/relocated-results.json"
checkmate_copy=$(mktemp -d "${TMPDIR:-/tmp}/checkmate-relocated.XXXXXX")
trap 'rm -rf "$checkmate_copy"' EXIT
ditto build/CheckmateAutomation.app "$checkmate_copy/Checkmate.app"
(cd "$checkmate_copy"; env -i PATH=/usr/bin:/bin CHECKMATE_AUTOMATION=1 ./Checkmate.app/Contents/MacOS/CheckmateNative --package-check "$checkmate_evidence/relocated-results.json")
python3 - "$checkmate_evidence/relocated-results.json" "$checkmate_copy" <<'PY'
import json,sys,pathlib,plistlib,subprocess
result=json.load(open(sys.argv[1]));resources=pathlib.Path(result['resourceRoot']).resolve()
assert result['passed'] and resources.is_relative_to(pathlib.Path(sys.argv[2]).resolve()),result
for name in ('course.zh-Hans.json','content.zh-Hans.json'):
    assert (resources/name).read_bytes()==(pathlib.Path('Sources/CheckmateCore/Resources')/name).read_bytes(),name
table=resources.parent/'zh-Hans.lproj/Localizable.strings'
strings=plistlib.loads(subprocess.check_output(['plutil','-convert','xml1','-o','-',str(table)]))
assert strings['Settings…']=='设置…', 'Moved bundle must retain its Chinese UI table'
result['chineseResources']=True
pathlib.Path(sys.argv[1]).write_text(json.dumps(result,indent=2))
PY
