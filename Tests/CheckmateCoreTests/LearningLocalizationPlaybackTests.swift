import CheckmateTestSupport
import XCTest
import CheckmateCore
@testable import CheckmateDomain
@testable import CheckmateSupport
@testable import CheckmateRules
@testable import CheckmateEngine
@testable import CheckmateContent
@testable import CheckmateApplication
@testable import CheckmateMacPlatform

@MainActor final class LearningLocalizationPlaybackTests:XCTestCase {
 func testPackSelectionNeverChangesPracticeOrMiniGame()async throws {let dir=try scratchDirectory();let session=try GameSession(engine:nil),player=try LearningPlayer(session:session),store=try LessonPackStore(directory:dir);let mode=session.mode,fen=session.rules.fen;player.packs=store;XCTAssertEqual(session.mode,mode);XCTAssertEqual(session.rules.fen,fen);session.state.settings.lessonLanguage="fr";player.settingsChanged();try await Task.sleep(for:.milliseconds(100));XCTAssertEqual(session.mode,mode);XCTAssertEqual(session.rules.fen,fen);player.startMini(.pawnDuel);let mini=player.miniGame;player.reloadLocalizedPacks();try await Task.sleep(for:.milliseconds(100));XCTAssertEqual(player.miniGame,mini);XCTAssertTrue(player.mini);player.shutdown()}
 func testShortAndLongClipsKeepAllAuthoredActions()async throws {
  let dir=try scratchDirectory()
  let library=try CourseLibrary(),source=LessonTranslation.source(library:library,index:19),store=try LessonPackStore(directory:dir);try store.saveTranslation(source,source:source,locale:"fr")
  for (index,beat) in source.beats.enumerated(){_ = try store.saveClip(pcm:plausibleLessonPCM(beat.speak,seconds:index==0 ? 30:0),transcript:beat.speak,beatID:beat.id,source:source,locale:"fr",voice:"cedar",model:"gpt-realtime")}
  let session=try GameSession(engine:nil),player=try LearningPlayer(session:session);session.state.settings.lessonLanguage="fr";session.state.settings.autoAdvance=false;player.openLesson(index:19);player.packs=store
  for _ in 0..<100 {if player.fallbackMessage==nil{break};try await Task.sleep(for:.milliseconds(10))};XCTAssertNil(player.fallbackMessage)
  player.openLesson(index:19);XCTAssertGreaterThanOrEqual(player.duration,30+library.lessonTiming.postNarrationGap)
  for index in source.beats.indices {player.seek(step:index);player.play();player.advance(by:player.duration);XCTAssertEqual(player.frame.board,library.referenceFrames[19][index].end.board);XCTAssertEqual(player.frame.counts,library.lessons[19].beats[index].count);XCTAssertFalse(player.playing)};player.shutdown()
 }
}

@MainActor final class ChineseLessonTextTests: XCTestCase {
    func testBundledChineseTextMatchesEveryAuthoredLesson() throws {
        let library = try CourseLibrary()
        XCTAssertEqual(library.lessons.filter { !$0.isPractice }.count, 34)
        XCTAssertEqual(library.lessons.filter(\.isPractice).count, 5)
        for index in library.lessons.indices {
            let source = LessonTranslation.source(library: library, index: index)
            let translated = try XCTUnwrap(BundledLessonText.translation(source: source, locale: "zh-Hans"))
            try translated.validate(against: source)
            XCTAssertNotEqual(translated.title, source.title)
        }
        let source = LessonTranslation.source(library: library, index: 0)
        XCTAssertNil(BundledLessonText.translation(source: source, locale: "fr"))
    }

    func testTextOnlyTranslationIsVisibleWithoutPlayingEnglishAudio() async throws {
        let directory = try scratchDirectory()
        let library = try CourseLibrary()
        let source = LessonTranslation.source(library: library, index: 0)
        var translated = source
        translated.title = "译文：" + source.title
        translated.beats[0].say = "译文：" + source.beats[0].say
        let store = try LessonPackStore(directory: directory)
        try store.saveTranslation(translated, source: source, locale: "fr")
        let session = try GameSession(engine: nil)
        session.state.settings.lessonLanguage = "fr"
        session.state.settings.autoAdvance = false
        let player = try LearningPlayer(session: session)
        let narration = TextOnlyNarrationProbe()
        player.audio = narration
        player.packs = store
        player.openLesson(index: 0)
        for _ in 0..<500 {
            if !player.localizationLoading { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(player.localizationLoading)
        XCTAssertEqual(player.localizedTitle(index: 0), translated.title)
        XCTAssertEqual(player.subtitle, translated.beats[0].say)
        XCTAssertNotNil(player.fallbackMessage)
        player.play()
        XCTAssertEqual(narration.englishPlayCount, 0)
        XCTAssertGreaterThan(narration.stopCount, 0)
        player.shutdown()
    }
}

@MainActor private final class TextOnlyNarrationProbe: NarrationService {
    private(set) var englishPlayCount = 0
    private(set) var stopCount = 0
    var playbackTime: Double? { nil }
    var narrationFailure: String? { nil }
    func play(file: String, seconds: Double, settings: AppSettings) { englishPlayCount += 1 }
    func play(localURL: URL, seconds: Double, settings: AppSettings) {}
    func pause() {}
    func stop() { stopCount += 1 }
    func setNarrationVolume(_ volume: Double) {}
}
