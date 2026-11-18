import XCTest
import CheckmateCore
import CheckmateTestSupport
@testable import CheckmateNative

@MainActor final class DeepSeekConsentTests:XCTestCase {
    override func setUpWithError()throws{try isolateDataDirectory()}
    func testDefaultCannotStartOrResumeLegacyProvider()throws {
        let model=try NativeModel();defer{model.shutdown()}
        XCTAssertTrue(model.usesDeepSeekCoach)
        var legacy=0
        model.askVoiceConsent={_,_ in legacy+=1}
        model.reconnectVoice={legacy+=1}
        _ = try model.session.openVoice();model.voice.receive(["type":"session.updated"])
        model.setAway(true);XCTAssertTrue(model.voiceResumeIntent)
        model.setAway(false)
        model.connectVoiceWithConsent{legacy+=1}
        model.startConnections()
        XCTAssertEqual(legacy,0);XCTAssertFalse(model.voiceResumeIntent)
        XCTAssertFalse(model.voice.connected);XCTAssertFalse(model.voice.connecting)
        XCTAssertFalse(model.session.companionEnabled)
    }
    func testDecliningPreservesQuestionAndSendsNothing()throws {
        let model=try NativeModel();defer{model.shutdown()}
        var prompts=0;model.askDeepSeekConsent={reply in prompts+=1;reply(false)}
        model.voiceHelp.draft="为什么这步不能走？"
        model.askDeepSeek(model.voiceHelp.draft)
        XCTAssertEqual(prompts,1);XCTAssertEqual(model.voiceHelp.draft,"为什么这步不能走？")
        XCTAssertFalse(model.session.state.settings.deepSeekConsent)
        XCTAssertTrue(model.deepSeekCoach.history.isEmpty);XCTAssertFalse(model.deepSeekCoach.thinking)
    }
    func testConsentSavedOnceWithoutOpeningNetworkOrMicrophone()throws {
        let model=try NativeModel();defer{model.shutdown()}
        var prompts=0,actions=0;model.askDeepSeekConsent={reply in prompts+=1;reply(true)}
        model.withDeepSeekConsent{actions+=1};model.withDeepSeekConsent{actions+=1}
        XCTAssertEqual(prompts,1);XCTAssertEqual(actions,2)
        try model.store.save(model.session.state)
        XCTAssertTrue(try model.store.load().settings.deepSeekConsent)
        XCTAssertFalse(model.deepSeekCoach.listening);XCTAssertFalse(model.deepSeekCoach.thinking)
    }
    func testDelayedConsentDoesNotSubmitQuestionForOldBoard()throws {
        let model=try NativeModel();defer{model.shutdown()}
        var pending:((Bool)->Void)?,prompts=0,actions=0
        model.askDeepSeekConsent={reply in prompts+=1;pending=reply}
        model.withDeepSeekConsent{actions+=1};model.withDeepSeekConsent{actions+=1}
        XCTAssertEqual(prompts,1)
        model.session.newGame(side:"b");pending?(true)
        XCTAssertEqual(actions,0);XCTAssertTrue(model.deepSeekCoach.history.isEmpty)
        XCTAssertFalse(model.deepSeekConsentPending)
    }
}
