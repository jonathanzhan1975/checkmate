#!/usr/bin/env python3
"""Chinese regression extension: pinned English mechanics and Chinese resource contracts."""
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess

if not __debug__:
    raise SystemExit('Assertions must be enabled for acceptance.')

ROOT = Path(__file__).resolve().parents[1]
BASELINE = 'b266339003c6897d3c9e5d7d8ca758c6065c5362'
PATHS = ['Sources/CheckmateRules', 'Sources/CheckmateEngine',
         'Sources/CheckmateCore/Resources/course.json', 'Sources/CheckmateCore/Resources/training',
         'Sources/CheckmateCore/Resources/chess.js', 'Sources/CheckmateCore/Resources/relationships.js',
         'Sources/CheckmateCore/Resources/stockfish', 'Sources/CheckmateCore/Resources/stockfish-build.json']


def main():
    names = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, '--', *PATHS], cwd=ROOT, text=True).splitlines()
    assert names, 'Pinned English baseline is unavailable; do not substitute another revision.'
    changed = []
    for name in names:
        expected = subprocess.check_output(['git', 'show', BASELINE + ':' + name], cwd=ROOT)
        actual = ROOT / name
        if not actual.is_file() or hashlib.sha256(expected).digest() != hashlib.sha256(actual.read_bytes()).digest():
            changed.append(name)
    current = subprocess.check_output(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '--', *PATHS], cwd=ROOT, text=True).splitlines()
    added = sorted(set(current) - set(names))
    assert not changed and not added, f'English mechanics differ: changed={changed}, added={added}; review explicitly, never bless silently.'
    checks = runpy.run_path(str(ROOT / 'scripts/test-chinese-localization.py'))
    catalog = checks['check_catalog']()
    lessons, segments = checks['check_course']()
    content = checks['check_content']()
    result = {'passed': True, 'englishBaseline': BASELINE, 'mechanicalFilesCompared': len(names),
              'mechanicsUnchanged': True, 'chineseCatalogEntries': catalog,
              'courseItems': lessons, 'courseSegments': segments, 'teachingStrings': content,
              'scope': 'mechanical-source equivalence and Chinese resource structure; human translation quality is separate'}
    output = os.environ.get('CHECKMATE_EVIDENCE_DIR')
    if output:
        Path(output).mkdir(parents=True, exist_ok=True)
        (Path(output) / 'chinese-results.json').write_text(json.dumps(result, ensure_ascii=False, indent=2))
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
