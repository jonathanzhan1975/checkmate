#!/usr/bin/env python3
"""Check Chinese resources without invoking a model, network, or audio device."""
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
PLACEHOLDERS = re.compile(r'%(?:\d+\$)?(?:#@[^@]+@|[-+ #0]*\d*(?:\.\d+)?(?:hh|ll|[hlLzjt])?[diuoxXfFeEgGaAcCsSp@%])')
NOTATION = re.compile(r'(?<![A-Za-z0-9])(?:[a-h][1-8](?:[a-h][1-8][qrbn]?)?|O-O(?:-O)?|[KQRBN][a-h]?[1-8]?x?[a-h][1-8][+#]?)(?![A-Za-z0-9])')


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


def leaves(node, path=()):
    if not isinstance(node, dict):
        return
    if 'stringUnit' in node:
        yield path, node['stringUnit']['value']
    for key, value in node.items():
        if key != 'stringUnit':
            yield from leaves(value, path + (key,))


def check_catalog():
    catalog = read_json(ROOT / 'Sources/CheckmateCore/Localizable.xcstrings')
    count = 0
    for key, entry in catalog['strings'].items():
        if not key:
            continue
        localizations = entry.get('localizations', {})
        assert 'zh-Hans' in localizations, 'Missing Chinese entry: ' + key
        original = dict(leaves(localizations.get('en', {'stringUnit': {'value': key}})))
        translated = dict(leaves(localizations['zh-Hans']))
        assert original.keys() == translated.keys(), 'Variation mismatch: ' + key
        for path, source in original.items():
            target = translated[path]
            assert target.strip() or not source.strip(), 'Empty translation: ' + key
            assert '\ufffd' not in target, 'Invalid Unicode: ' + key
            expected, actual = PLACEHOLDERS.findall(source), PLACEHOLDERS.findall(target)
            indexed = all(token == '%%' or re.match(r'%\d+\$', token) for token in expected)
            assert (sorted(expected) == sorted(actual) if indexed else expected == actual), 'Placeholder mismatch: ' + key
        count += 1
    return count


def check_course():
    resources = ROOT / 'Sources/CheckmateCore/Resources'
    original_bytes = (resources / 'course.json').read_bytes()
    course = json.loads(original_bytes)
    translated = read_json(resources / 'course.zh-Hans.json')
    assert translated['version'] == 1 and translated['locale'] == 'zh-Hans'
    assert translated['sourceHash'] == hashlib.sha256(original_bytes.replace(b'\r\n', b'\n')).hexdigest(), 'Course source changed'
    assert translated['provider'] == 'codex'
    lessons = translated['lessons']
    assert [lesson['id'] for lesson in course['lessons']] == [lesson['lessonID'] for lesson in lessons]
    segments = 0
    for index, (source, target) in enumerate(zip(course['lessons'], lessons)):
        assert len(source.get('teaches', [])) == len(target['teaches'])
        assert len(source['beats']) == len(target['beats'])
        pairs = [(source['title'], target['title'])] + list(zip(source.get('teaches', []), target['teaches']))
        for step, (beat, text) in enumerate(zip(source['beats'], target['beats'])):
            assert beat.get('id', source['id'] + ':' + str(step)) == text['id']
            pairs.extend([(course['stepTitles'][index][step], text['stepTitle']), (beat['say'], text['say']), (beat.get('speak') or beat['say'], text['speak'])])
            segments += 1
        for english, chinese in pairs:
            assert chinese.strip() or not english.strip(), 'Empty course text'
            assert '\ufffd' not in chinese, 'Invalid course Unicode'
            assert sorted(NOTATION.findall(english)) == sorted(NOTATION.findall(chinese)), 'Changed chess notation: ' + english
    for source, target in translated['labels'].items():
        assert target.strip() and '\ufffd' not in target
        assert sorted(NOTATION.findall(source)) == sorted(NOTATION.findall(target))
    return len(lessons), segments


if __name__ == '__main__':
    entries = check_catalog()
    lessons, segments = check_course()
    print(json.dumps({'passed': True, 'chineseCatalogEntries': entries, 'courseItems': lessons, 'courseSegments': segments}))
