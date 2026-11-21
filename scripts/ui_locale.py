"""Forward-localize the original UI expectations; actual accessibility output stays Chinese.

Only display text uses this adapter. Saved state, protocol fields, imported PGN,
keyboard text and stable accessibility identifiers are never translated.
"""
import functools
import json
import os
from pathlib import Path
import re


class ExpectedUI(str):
    pass


class ExpectedContent(str):
    pass


class ExpectedCourse(str):
    pass


class Raw(str):
    pass


def ui(value):
    return ExpectedUI(value)


def content(value):
    return ExpectedContent(value)


def course(value):
    return ExpectedCourse(value)


def raw(value):
    return Raw(value)


class LanguageEvidenceMissing(AssertionError):
    pass

ROOT = Path(__file__).resolve().parents[1]


def language():
    return os.environ.get('CHECKMATE_TEST_LANGUAGE', 'zh-Hans')


@functools.lru_cache(maxsize=1)
def translations():
    entries = json.loads((ROOT / 'Sources/CheckmateCore/Localizable.xcstrings').read_text())['strings']
    result = {}
    for key, entry in entries.items():
        value = entry.get('localizations', {}).get('zh-Hans', {}).get('stringUnit', {}).get('value')
        if key and value and '%' not in key:
            result[key] = value
    return result


@functools.lru_cache(maxsize=1)
def content_translations():
    resources = ROOT / 'Sources/CheckmateCore/Resources'
    return json.loads((resources / 'content.zh-Hans.json').read_text())['translations']


@functools.lru_cache(maxsize=1)
def course_translations():
    resources = ROOT / 'Sources/CheckmateCore/Resources'
    english = json.loads((resources / 'course.json').read_text())
    chinese = json.loads((resources / 'course.zh-Hans.json').read_text())
    result = dict(chinese.get('labels', {}))
    for source, target in zip(english['lessons'], chinese['lessons']):
        assert source['id'] == target['lessonID']
        result[source['title']] = target['title']
    return result


@functools.lru_cache(maxsize=1)
def lesson_step_translations():
    resources = ROOT / 'Sources/CheckmateCore/Resources'
    english = json.loads((resources / 'course.json').read_text())
    chinese = json.loads((resources / 'course.zh-Hans.json').read_text())
    result = {}
    for i, lesson in enumerate(chinese['lessons']):
        for j, beat in enumerate(lesson['beats']):
            key = f'{j+1}. {english["stepTitles"][i][j]}'
            result.setdefault(key, set()).add(f'{j+1}. {beat["stepTitle"]}')
    return result


@functools.lru_cache(maxsize=1)
def declared_identifiers():
    found = set()
    for path in (ROOT / 'Sources/CheckmateNative').glob('*.swift'):
        code = path.read_text()
        found.update(re.findall(r'(?:accessibilityIdentifier|setAccessibilityIdentifier|NSUserInterfaceItemIdentifier)\("([^"\n]+)"', code))
    return found


def is_identifier(value):
    if value in {'Settings', 'main'}:
        return True
    for identifier in declared_identifiers():
        prefix = identifier.split('\\(')[0]
        if prefix and prefix[0].islower() and ('-' in prefix or '_' in prefix):
            if value == prefix or (prefix.endswith(('-', '_')) and value.startswith(prefix)):
                return True
    return False


@functools.lru_cache(maxsize=1)
def numeric_templates():
    entries = json.loads((ROOT / 'Sources/CheckmateCore/Localizable.xcstrings').read_text())['strings']
    forms = []
    token = re.compile(r'%(?:\d+\$)?(?:lld|ld|lu|d|u|f)')
    for source, entry in entries.items():
        target = entry.get('localizations', {}).get('zh-Hans', {}).get('stringUnit', {}).get('value')
        if not target or not token.search(source) or '%@' in source:
            continue
        parts = token.split(source)
        pattern = re.compile('^' + r'([-+]?\d+(?:[.,]\d+)?)'.join(re.escape(p) for p in parts) + '$')
        forms.append((pattern, target, token))
    return forms


def text(source):
    if not isinstance(source, str) or not language().startswith('zh'):
        return source
    if isinstance(source, Raw) or is_identifier(source):
        return str(source)
    values = translations()
    content_values = content_translations()
    course_values = course_translations()
    if isinstance(source, ExpectedContent):
        if source not in content_values:
            raise AssertionError('Missing explicit content expectation: ' + source)
        return content_values[source]
    if isinstance(source, ExpectedCourse):
        if source not in course_values:
            raise AssertionError('Missing explicit course expectation: ' + source)
        return course_values[source]
    candidates = {mapping[source] for mapping in (values, content_values, course_values) if source in mapping}
    if len(candidates) > 1 and not isinstance(source, ExpectedUI):
        raise AssertionError('Ambiguous expectation; choose ui(), course() or content(): ' + source)
    if source in values:
        return values[source]
    if source.startswith('Play '):
        entries = json.loads((ROOT / 'Sources/CheckmateCore/Localizable.xcstrings').read_text())['strings']
        template = entries['Play %@']['localizations']['zh-Hans']['stringUnit']['value']
        rendered = re.sub(r'%(?:1\$)?@', lambda _: text(source[5:]), template)
        if source in course_values and course_values[source] != rendered and not isinstance(source, ExpectedUI):
            raise AssertionError('UI template differs from course label; choose ui() or course(): ' + source)
        return rendered
    if source in course_values:
        return course_values[source]
    steps = lesson_step_translations()
    if source in steps:
        assert len(steps[source]) == 1, 'Lesson step needs explicit lesson context: ' + source
        return next(iter(steps[source]))
    if source.startswith('Current activity | '):
        caption = source[len('Current activity | '):]
        if ' · ' in caption:
            title, phase = caption.split(' · ', 1)
            return text(ui('Current activity')) + ' | ' + text(course(title)) + ' · ' + text(ui(phase))
        return text(ui('Current activity')) + ' | ' + text(course(caption))
    if source in {'Next lesson','Previous lesson'}:
        return values[source+':'].rstrip(':：')
    for prefix, key in [('Practice: ', 'Practice: %@'), ('Practice activity for ', 'Practice activity for %@'), ('Next lesson: ', 'Next lesson: %@'), ('Previous lesson: ', 'Previous lesson: %@'), ('Continue to ', 'Continue to %@')]:
        if source.startswith(prefix):
            entries = json.loads((ROOT / 'Sources/CheckmateCore/Localizable.xcstrings').read_text())['strings']
            template = entries[key]['localizations']['zh-Hans']['stringUnit']['value']
            return re.sub(r'%(?:1\$)?@', lambda _: text(course(source[len(prefix):])), template)
    hint = re.fullmatch(r'Hint (\d+):', source)
    if hint:
        entries = json.loads((ROOT / 'Sources/CheckmateCore/Localizable.xcstrings').read_text())['strings']
        template = entries['Hint %lld: %@']['localizations']['zh-Hans']['stringUnit']['value']
        return template.split('%2$@')[0].replace('%1$lld', hint.group(1))
    if ' | ' in source:
        return ' | '.join(text(ui(part)) for part in source.split(' | '))
    board = re.fullmatch(r'(suggested move to|suggested move from|guards|guarded by) ([a-h][1-8])', source)
    if board:
        entries = json.loads((ROOT / 'Sources/CheckmateCore/Localizable.xcstrings').read_text())['strings']
        template = entries[board.group(1) + ' %@']['localizations']['zh-Hans']['stringUnit']['value']
        return re.sub(r'%(?:1\$)?@', board.group(2), template)
    if source == 'suggested move':
        # A board-label fragment shared by both source/destination annotations.
        return '建议'
    role = re.fullmatch(r'(AX[A-Za-z]+: )(.*)', source)
    if role:
        return role.group(1) + text(ui(role.group(2)))
    square = re.fullmatch(r'([a-h][1-8]), (.*)', source)
    if square:
        tail = square.group(2)
        piece = re.match(r'(White|Black), (pawn|knight|bishop|rook|queen|king|piece)(.*)', tail)
        if piece:
            rest = piece.group(3)
            return square.group(1) + ', ' + values[piece.group(1) + ', ' + piece.group(2)] + (', ' + text(rest[2:]) if rest.startswith(', ') else rest)
        return square.group(1) + ', ' + text(tail)
    for pattern, target, token in numeric_templates():
        match = pattern.fullmatch(source)
        if match:
            index = iter(match.groups())
            def replace(value):
                position = re.match(r'%(\d+)\$', value.group())
                return match.group(int(position.group(1))) if position else next(index)
            return token.sub(replace, target)
    def piece(match):
        named = values[match.group(1)]
        return named + '（位于' + match.group(2) + '）'
    named = re.fullmatch(r'((?:White|Black) (?:pawn|knight|bishop|rook|queen|king|piece)) on ([a-h][1-8])', source)
    if named:
        return piece(named)
    if not re.search('[A-Za-z]', source) or re.fullmatch(r'[a-h][1-8](?:[a-h][1-8][qrbn]?)?', source):
        return str(source)
    raise AssertionError('Display expectation needs Chinese adaptation or explicit raw()/content(): ' + source)


class UIText(str):
    """Raw UI text whose assertions translate the expected value forward only.

    For example, 'Settings…' in UIText('设置…') succeeds in Chinese mode;
    'Settings…' in UIText('Settings…') fails. English fallback cannot pass that
    expectation. str(value), saved evidence and regex input remain the raw text.
    """
    def __contains__(self, expected):
        return str.__contains__(self, text(expected))

    def __eq__(self, expected):
        return str.__eq__(self, text(expected)) if isinstance(expected, str) else NotImplemented

    def __ne__(self, expected):
        equal = self.__eq__(expected)
        return NotImplemented if equal is NotImplemented else not equal

    __hash__ = None

    def startswith(self, expected, *args):
        return str.startswith(self, tuple(text(v) for v in expected) if isinstance(expected, tuple) else text(expected), *args)

    def endswith(self, expected, *args):
        return str.endswith(self, tuple(text(v) for v in expected) if isinstance(expected, tuple) else text(expected), *args)

    def strip(self, chars=None):
        return UIText(str.strip(self, chars))

    def splitlines(self, keepends=False):
        return [UIText(v) for v in str.splitlines(self, keepends)]

    def split(self, sep=None, maxsplit=-1):
        return [UIText(v) for v in str.split(self, sep, maxsplit)]

    def index(self, expected, *args):
        return str.index(self, text(expected), *args)


def arguments(args):
    if not args:
        return args
    named = {'press', 'focus', 'select', 'click', 'frame', 'enabled', 'value', 'select-popup',
             'close-window', 'menu', 'menu-open', 'dialog-click', 'choose-menu-item', 'click-left', 'click-at', 'drag-across', 'wheel', 'help'}
    if args[0] not in named:
        return args
    if args[0] == 'menu' and len(args) > 1 and args[1] == 'Checkmate':
        # The application menu is the product name, not the chess result.
        return (args[0], args[1], *(text(v) for v in args[2:]))
    if args[0] == 'select-popup' and len(args) > 2 and args[1] == 'lesson-language' and language().startswith('zh') and not isinstance(args[2], Raw):
        names = {'English': '英语', 'French': '法语', 'Spanish': '西班牙语'}
        choice = names.get(str(args[2]))
        return (args[0], text(args[1]), choice if choice is not None else text(args[2]), *(text(v) for v in args[3:]))
    return (args[0], *(text(v if isinstance(v, (Raw, ExpectedCourse, ExpectedContent)) else ui(v)) for v in args[1:]))


def proof_scope(folder, gate_name=None):
    root = Path(folder)
    metadata = json.loads((root / 'language-run.json').read_text())
    run_id = metadata['runID']
    gate = gate_name or os.environ.get('CHECKMATE_LANGUAGE_GATE', '')
    assert re.fullmatch('[0-9a-f]{32}', run_id) and re.fullmatch('[a-z0-9-]+', gate), 'Invalid UI proof scope'
    current = os.environ.get('CHECKMATE_LANGUAGE_RUN_ID')
    assert gate_name is not None or not current or current == run_id, 'UI proof belongs to another run'
    return root / 'ui-language' / run_id / gate, run_id, gate


def expect_instance(folder, pid):
    scope, _, _ = proof_scope(folder)
    scope.mkdir(parents=True, exist_ok=True)
    path = scope / 'expected-pids.json'
    expected = json.loads(path.read_text()) if path.exists() else {}
    expected[str(int(pid))] = os.urandom(16).hex()
    path.write_text(json.dumps(expected,sort_keys=True))


def record(pid, raw):
    folder = os.environ.get('CHECKMATE_EVIDENCE_DIR')
    if not folder:
        return
    evidence, run_id, gate = proof_scope(folder)
    evidence.mkdir(parents=True, exist_ok=True)
    instance = json.loads((evidence / 'expected-pids.json').read_text())[str(int(pid))]
    path = evidence / f'locale-{pid}-initial-ax.txt'
    marker = next((row for row in str(raw).splitlines() if '| showSettings' in row), None)
    if not marker:
        (evidence / f'locale-{pid}-pending-ax.txt').write_text(str(raw))
        raise LanguageEvidenceMissing('Complete accessibility read has no application language marker; no Chinese pass may be recorded.')
    if marker:
        expected = translations()['Settings…'] if language().startswith('zh') else 'Settings…'
        assert expected in marker, f'Actual app language does not match {language()}: {marker}'
        proof_path = evidence / f'locale-{pid}.json'
        if not proof_path.exists() or json.loads(proof_path.read_text()).get('instance') != instance:
            path.write_text(str(raw))
            proof_path.write_text(json.dumps({'passed': True, 'runID': run_id, 'gate': gate, 'pid': int(pid), 'instance': instance, 'expectedLanguage': language(), 'actualSettingsMenu': marker, 'rawAccessibility': path.name}, ensure_ascii=False, indent=2))


def verify_evidence(folder, gate_name=None):
    """A gate cannot pass as localized UI without an observed language proof."""
    evidence, run_id, gate = proof_scope(folder, gate_name)
    proofs = list(evidence.glob('locale-*.json'))
    assert proofs, 'No actual UI language evidence; this gate cannot count as Chinese UI acceptance.'
    expected_instances = json.loads((evidence / 'expected-pids.json').read_text())
    assert expected_instances and {json.loads(path.read_text())['pid'] for path in proofs} == {int(pid) for pid in expected_instances}, 'Missing language proof for an interactive application instance'
    for path in proofs:
        proof = json.loads(path.read_text())
        assert proof.get('runID') == run_id and proof.get('gate') == gate, path.name
        assert proof.get('instance') == expected_instances[str(proof['pid'])], 'A PID was reused without fresh language proof'
        assert proof.get('passed') is True and proof.get('expectedLanguage') == language(), path.name
        raw_path = evidence / proof['rawAccessibility']
        assert raw_path.is_file() and proof['actualSettingsMenu'] in raw_path.read_text(), path.name
        expected = translations()['Settings…'] if language().startswith('zh') else 'Settings…'
        assert expected in proof['actualSettingsMenu'], path.name
    return {'language': language(), 'observedInstances': len(proofs)}
