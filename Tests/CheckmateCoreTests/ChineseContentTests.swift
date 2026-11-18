import XCTest
import CheckmateCore

final class ChineseContentTests: XCTestCase {
    func testEveryMiniGameTitleRuleAndDrawReasonDisplaysChinese() {
        let sources=MiniGameKind.allCases.flatMap{[$0.title,$0.rules]}+MiniGameDraw.allCases.map(\.text)
        for source in sources {
            let text=ChineseContent.text(source,locale:"zh-Hans")
            XCTAssertNotEqual(text,source)
            XCTAssertNil(text.range(of:"[A-Za-z]{3,}",options:.regularExpression),text)
            XCTAssertEqual(ChineseContent.text(source,locale:"en"),source)
        }
    }
    func testEveryPuzzleDisplaysChineseAndKeepsOriginalChoiceAnswers() throws {
        let library=try CourseLibrary()
        XCTAssertEqual(library.puzzles.count,82)
        for puzzle in library.puzzles {
            for text in [puzzle.title,puzzle.exercise.prompt,puzzle.explanation] where !text.isEmpty {
                let displayed=ChineseContent.text(text,locale:"zh-Hans")
                XCTAssertNotEqual(displayed,text,puzzle.id+": "+text)
                XCTAssertEqual(ChineseContent.text(text,locale:"en"),text)
            }
            if puzzle.exercise.kind=="choice",let answer=puzzle.exercise.answer {
                XCTAssertTrue(puzzle.exercise.matches([answer]))
                for choice in puzzle.exercise.choices ?? [] {
                    let displayed=ChineseContent.text(choice,locale:"zh-Hans")
                    XCTAssertFalse(displayed.isEmpty)
                    // The UI submits the original value; a translated label is never the answer key.
                    XCTAssertEqual(puzzle.exercise.matches([choice]),choice==answer)
                }
            }
        }
    }
    func testComposedFeedbackTranslatesAuthoredExplanation() throws {
        let puzzle=try CourseLibrary().puzzles[0]
        let source="正确。 "+puzzle.explanation
        let translated=ChineseContent.text(source,locale:"zh-Hans")
        XCTAssertTrue(translated.hasPrefix("正确。 "))
        XCTAssertFalse(translated.contains(puzzle.explanation))
    }
    func testNotationAndUnknownContentAreNotRewritten() {
        XCTAssertEqual(ChineseContent.text("e2e4 Nf3 O-O",locale:"zh-Hans"),"e2e4 Nf3 O-O")
        XCTAssertEqual(ChineseContent.text("Learner supplied text",locale:"zh-Hans"),"Learner supplied text")
    }
}
