#!/usr/bin/env python3
"""Install or archive a fully verified Chinese language pack. Dry-run unless --install/--archive is given."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
from datetime import datetime, timezone
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_directory(path):
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            raise ValueError('Symbolic-link directories are not accepted: ' + str(ancestor))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--destination', type=Path, default=Path.home() / 'Library/Application Support/ai.xiaolai.checkmate.native-development')
    parser.add_argument('--install', action='store_true')
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    source = args.source.absolute()
    safe_directory(source)
    proof = json.loads((source / 'verification.json').read_text())
    resources = ROOT / 'Sources/CheckmateCore/Resources'
    if (proof.get('version'), proof.get('locale'), proof.get('voice'), proof.get('lessons'), proof.get('clips')) != (1, 'zh-Hans', 'cedar', 39, 710):
        raise ValueError('A complete, supported 39-lesson/710-clip verification is required.')
    if proof['sourceHash'] != digest(resources / 'course.json') or proof['translationHash'] != digest(resources / 'course.zh-Hans.json'):
        raise ValueError('The language pack does not match the current course and translation.')
    files = []
    for name, expected in proof['files'].items():
        if not re.fullmatch('[a-f0-9]{64}', name):
            raise ValueError('Unsafe filename in verification.')
        path = source / 'LessonLanguages' / name
        if path.is_symlink() or not path.is_file() or digest(path) != expected:
            raise ValueError('A verified file is missing or changed: ' + name)
        files.append(path)
    if args.archive:
        args.archive.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=args.archive.parent, delete=False) as scratch:
            temporary = Path(scratch.name)
        try:
            with zipfile.ZipFile(temporary, 'w', zipfile.ZIP_DEFLATED) as archive:
                archive.write(source / 'verification.json', 'verification.json')
                for path in files:
                    archive.write(path, 'LessonLanguages/' + path.name)
            os.replace(temporary, args.archive)
        finally:
            temporary.unlink(missing_ok=True)
        print('Archive:', args.archive)
    if args.install:
        destination = args.destination.absolute() / 'LessonLanguages'
        safe_directory(destination)
        destination.mkdir(parents=True, exist_ok=True, mode=0o700)
        backup = ROOT / 'recordings/backups' / datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')
        changed = 0
        for path in files:
            target = destination / path.name
            if target.is_symlink():
                raise ValueError('Refusing to replace a symbolic link.')
            if target.exists():
                if digest(target) == digest(path):
                    continue
                backup.mkdir(parents=True, exist_ok=True, mode=0o700)
                shutil.copy2(target, backup / target.name)
            with tempfile.NamedTemporaryFile(dir=destination, delete=False) as scratch:
                temporary = Path(scratch.name)
                scratch.write(path.read_bytes())
                scratch.flush()
                os.fsync(scratch.fileno())
            os.chmod(temporary, 0o600)
            os.replace(temporary, target)
            changed += 1
        print('Installed', changed, 'files to', destination)
        if backup.exists():
            print('Previous files backed up to', backup)
    print('Verified pack:', len(files), 'files;', proof['clips'], 'clips;', round(proof['seconds'] / 60, 1), 'minutes')
    if not args.install and not args.archive:
        print('Dry run: pass --install or --archive PATH to write files.')


if __name__ == '__main__':
    main()
