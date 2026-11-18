import XCTest
import CheckmateCore
import CheckmateTestSupport

final class ChineseReviewNarrationTests:XCTestCase {
    private func checkLanguage(_ text:String,file:StaticString=#filePath,line:UInt=#line) {
        XCTAssertFalse(text.isEmpty,file:file,line:line)
        if Bundle.checkmate.preferredLocalizations.first?.hasPrefix("zh")==true {
            XCTAssertNotNil(text.range(of:"[\\p{Han}]",options:.regularExpression),text,file:file,line:line)
        }
    }
    func testChessReviewUsesExactLocalizedFactsAndRejectsInventedText() throws {
        let document=try PGNImporter.parse(Data("1. e4 d5 2. exd5 *".utf8))[0]
        let explanation=try ReviewExplanation.make(document:document,node:document.mainline.last!)
        let segments=try SpeechSegment.decode(ReviewVoiceScript.segments(explanation))
        XCTAssertFalse(segments.isEmpty)
        for segment in segments {checkLanguage(segment.text);XCTAssertTrue(explanation.facts.contains{$0.text==segment.text})}
        XCTAssertNoThrow(try ReviewVoiceScript.validate(segments,explanation:explanation))
        let invented=try SpeechSegment.decode([["text":"未经验证的说明","squares":[],"kind":"focus"]])
        XCTAssertThrowsError(try ReviewVoiceScript.validate(invented,explanation:explanation))
    }
    func testMiniGameReviewKeepsLocalizedProofText() throws {
        var game=MiniGameState(kind:.rookSweep)
        game.snapshot.board=["a1":"wr","h2":"wp","e5":"br","a7":"bp"]
        XCTAssertTrue(game.play(MiniGameMove(from:"a1",to:"a7")))
        let review=MiniGameReview.run(game,cpuSeconds:{0},stop:{false})
        XCTAssertTrue(review.consistent)
        XCTAssertFalse(review.facts.isEmpty)
        let segments=try SpeechSegment.decode(MiniGameReviewVoiceScript.segments(review))
        for segment in segments {checkLanguage(segment.text)}
        XCTAssertNoThrow(try MiniGameReviewVoiceScript.validate(segments,review:review))
    }
    func testChineseCoordinateNumbersAreStrictlyChecked() throws {
        let script="兵从 G 四走到 G 五。"
        let pcm=plausibleLessonPCM(script,seconds:3)
        XCTAssertNoThrow(try LessonRecording.validate(pcm:pcm,transcript:script,script:script,language:"zh-Hans"))
        XCTAssertThrowsError(try LessonRecording.validate(pcm:pcm,transcript:"兵从 G 四走到 G 六。",script:script,language:"zh-Hans"))
    }
}
