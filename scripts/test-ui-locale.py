"""The UI adapter must require Chinese output, never normalize English fallback into a pass."""
import os
import json
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
import ui_locale


class LocaleAdapterTests(unittest.TestCase):
    def scope(self, folder, run_id='a'*32, gate='fixture'):
        (Path(folder) / 'language-run.json').write_text(json.dumps({'runID':run_id}))
        return patch.dict(os.environ, CHECKMATE_EVIDENCE_DIR=folder, CHECKMATE_LANGUAGE_RUN_ID=run_id, CHECKMATE_LANGUAGE_GATE=gate)
    def setUp(self):
        self.environment = patch.dict(os.environ, CHECKMATE_TEST_LANGUAGE='zh-Hans')
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def testEnglishFallbackCannotPassChineseExpectation(self):
        self.assertIn('Settings…', ui_locale.UIText('AXMenuItem: 设置… | showSettings'))
        self.assertNotIn('Settings…', ui_locale.UIText('AXMenuItem: Settings… | showSettings'))
        self.assertEqual(str(ui_locale.UIText('设置…')), '设置…')

    def testIdentifiersAndTypedDataAreUnmodified(self):
        self.assertEqual(ui_locale.arguments(('click', 'bar-voiceConnect')), ('click', 'bar-voiceConnect'))
        self.assertEqual(ui_locale.arguments(('close-window', 'Settings')), ('close-window', 'Settings'))
        self.assertEqual(ui_locale.arguments(('type', '[White "Jane"]\n1. e4 *')), ('type', '[White "Jane"]\n1. e4 *'))
        self.assertEqual(ui_locale.arguments(('key', '35')), ('key', '35'))
        self.assertEqual(ui_locale.arguments(('menu', 'Checkmate', 'Settings…')), ('menu', 'Checkmate', '设置…'))

    def testPieceLabelsUseTheWholeChinesePhrase(self):
        self.assertTrue(ui_locale.UIText('e2, 白方，兵, 已选中').startswith('e2, White, pawn'))
        self.assertIn('selected', ui_locale.UIText('e2, 白方，兵, 已选中'))
        self.assertNotIn('selected', ui_locale.UIText('e2, White, pawn, selected'))

    def testEnglishControlRemainsExplicitSupplement(self):
        with patch.dict(os.environ, CHECKMATE_TEST_LANGUAGE='en'):
            self.assertEqual(ui_locale.text('Settings…'), 'Settings…')
            self.assertIn('White', ui_locale.UIText('White pawn'))
            self.assertEqual(ui_locale.arguments(('select-popup','lesson-language','French')),('select-popup','lesson-language','French'))
        self.assertEqual(ui_locale.arguments(('select-popup','lesson-language',ui_locale.raw('French'))),('select-popup','lesson-language','French'))

    def testNumberedControlUsesTranslatedTemplate(self):
        self.assertEqual(ui_locale.arguments(('menu-open', 'Level 1')), ('menu-open', '第 1 级'))
        self.assertNotIn('Level 1', ui_locale.UIText('Level 1'))
        self.assertIn('Level 1', ui_locale.UIText('第 1 级'))
        self.assertEqual(ui_locale.text(ui_locale.ui('Play Pawn Duel')), '玩兵的对决')
        self.assertEqual(ui_locale.text(ui_locale.course('Play Pawn Duel')), '来玩兵的对决')

    def testUnknownEnglishAndAmbiguousContextsFailClosed(self):
        with self.assertRaises(AssertionError):
            'A new untranslated application control' in ui_locale.UIText('A new untranslated application control')
        with self.assertRaises(AssertionError):
            ui_locale.text('Neither')
        self.assertNotEqual(ui_locale.text(ui_locale.ui('Neither')), ui_locale.text(ui_locale.content('Neither')))
        self.assertEqual(ui_locale.text(ui_locale.raw('The Pawn')), 'The Pawn')

    def testUIReadsCannotBeHashKeysWithContextualEquality(self):
        with self.assertRaises(TypeError):
            hash(ui_locale.UIText('设置…'))

    def testActivityKeepsEveryLocalizedPhase(self):
        expected = 'Current activity | The Fork · Play on · Your turn'
        localized = ui_locale.text(ui_locale.ui('Current activity')) + ' | ' + ui_locale.text(ui_locale.course('The Fork')) + ' · ' + ui_locale.text(ui_locale.ui('Play on · Your turn'))
        self.assertIn(expected, ui_locale.UIText(localized))
        self.assertNotIn(expected, ui_locale.UIText(expected))

    def testMissingLanguageEvidenceCannotProducePassingProof(self):
        with tempfile.TemporaryDirectory() as folder, self.scope(folder):
            ui_locale.expect_instance(folder,42)
            with self.assertRaises(ui_locale.LanguageEvidenceMissing):
                ui_locale.record(42, 'AXApplication: Checkmate')
            self.assertFalse((ui_locale.proof_scope(folder)[0] / 'locale-42.json').exists())
            with self.assertRaises(AssertionError):
                ui_locale.verify_evidence(folder)

    def testGateProofRequiresActualMatchingRawChinese(self):
        with tempfile.TemporaryDirectory() as folder, self.scope(folder):
            ui_locale.expect_instance(folder,42)
            ui_locale.record(42, 'AXMenuItem: 设置… | showSettings')
            self.assertEqual(ui_locale.verify_evidence(folder)['observedInstances'], 1)
            (ui_locale.proof_scope(folder)[0] / 'locale-42-initial-ax.txt').write_text('AXMenuItem: Settings… | showSettings')
            with self.assertRaises(AssertionError):
                ui_locale.verify_evidence(folder)

    def testAnotherGateOrRunCannotLendItsLanguageEvidence(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.scope(folder):
                ui_locale.expect_instance(folder,42)
                ui_locale.record(42,'AXMenuItem: 设置… | showSettings')
                self.assertEqual(ui_locale.verify_evidence(folder)['observedInstances'],1)
                ui_locale.expect_instance(folder,43)
                with self.assertRaises(AssertionError):ui_locale.verify_evidence(folder)
            for run_id,gate in [('a'*32,'other'),('b'*32,'fixture')]:
                with self.scope(folder,run_id,gate):
                    ui_locale.expect_instance(folder,42)
                    with self.assertRaises(AssertionError):ui_locale.verify_evidence(folder)

    def testReusedPIDNeedsFreshInstanceEvidence(self):
        with tempfile.TemporaryDirectory() as folder, self.scope(folder):
            ui_locale.expect_instance(folder,42)
            ui_locale.record(42,'AXMenuItem: 设置… | showSettings')
            self.assertEqual(ui_locale.verify_evidence(folder)['observedInstances'],1)
            ui_locale.expect_instance(folder,42)
            with self.assertRaises(AssertionError):ui_locale.verify_evidence(folder)
            ui_locale.record(42,'AXMenuItem: 设置… | showSettings')
            self.assertEqual(ui_locale.verify_evidence(folder)['observedInstances'],1)

    def testAllInteractiveRestartsHaveIndependentChineseProof(self):
        with tempfile.TemporaryDirectory() as folder, self.scope(folder):
            for pid in [42,43,44]:
                ui_locale.expect_instance(folder,pid)
                ui_locale.record(pid,'AXMenuItem: 设置… | showSettings')
            self.assertEqual(ui_locale.verify_evidence(folder)['observedInstances'],3)


if __name__ == '__main__':
    unittest.main()
