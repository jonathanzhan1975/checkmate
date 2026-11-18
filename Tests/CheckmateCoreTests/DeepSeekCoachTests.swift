import XCTest
import CheckmateCore
import CheckmateTestSupport

private actor ScriptedDeepSeek:DeepSeekChatProviding {
    let delay:Duration
    var replies:[DeepSeekChatReply],requests:[[String:Any]]=[]
    init(_ replies:[DeepSeekChatReply],delay:Duration = .zero){self.replies=replies;self.delay=delay}
    func reply(messages:Data,tools:Data)async throws->DeepSeekChatReply {
        requests.append(["messages":try JSONSerialization.jsonObject(with:messages),"tools":try JSONSerialization.jsonObject(with:tools)])
        try await Task.sleep(for:delay);try Task.checkCancellation()
        guard !replies.isEmpty else{throw CheckmateError.invalid("No scripted reply")};return replies.removeFirst()
    }
    var count:Int{requests.count}
    func captured()->[[String:Any]]{requests}
}
@MainActor final class DeepSeekCoachTests:XCTestCase {
    private func session(consent:Bool=true)throws->GameSession{let s=try GameSession(engine:nil);var settings=s.state.settings;settings.deepSeekConsent=consent;settings.deepSeekSpeak=false;s.updateSettings(settings);return s}
    private func wait(_ coach:DeepSeekCoach)async throws{for _ in 0..<200{if !coach.thinking{return};try await Task.sleep(for:.milliseconds(5))};XCTFail("Coach did not finish")}
    func testConsentRequiredBeforeAnyNetworkRequest()async throws {
        let client=ScriptedDeepSeek([]),coach=try DeepSeekCoach(session:session(consent:false),client:client)
        coach.ask("为什么这步不能走？");let count=await client.count;XCTAssertEqual(count,0);XCTAssertTrue(coach.history.isEmpty);XCTAssertFalse(coach.thinking)
    }
    func testAnswerUsesLiveBoardAndReleasesOwnedLease()async throws {
        let s=try session(),client=ScriptedDeepSeek([.init(id:"r",model:"deepseek-fixture",text:"先发展马和象，再考虑王车易位。")]),coach=try DeepSeekCoach(session:s,client:client)
        let fen=s.rules.fen;coach.ask("我该先考虑什么？");try await wait(coach)
        XCTAssertEqual(coach.history.map(\.role),["learner","coach"]);XCTAssertNil(s.voiceLease);XCTAssertEqual(s.rules.fen,fen)
        let requests=await client.captured(),messages=requests[0]["messages"] as! [[String:Any]],input=messages.last!["content"] as! String
        let json=try XCTUnwrap(input.components(separatedBy:"本轮已验证棋局数据：\n").last)
        let normalized=String(decoding:try JSONSerialization.data(withJSONObject:JSONSerialization.jsonObject(with:Data(json.utf8)),options:.withoutEscapingSlashes),as:UTF8.self)
        XCTAssertTrue(normalized.contains(fen))
        XCTAssertTrue(input.contains("legalMoves"))
        XCTAssertTrue((messages[0]["content"] as! String).contains("DeepSeek"))
    }
    func testToolContinuationUsesValidatedReadOnlyToolsWithoutMoving()async throws {
        let s=try session(),fen=s.rules.fen,client=ScriptedDeepSeek([.init(id:"one",model:"deepseek-fixture",text:"",calls:[.init(id:"inspect",name:"inspect_piece",arguments:"{\"square\":\"b1\"}")]),.init(id:"two",model:"deepseek-fixture",text:"b1 的马先走日字形，检查 c3 和 a3。")]),coach=try DeepSeekCoach(session:s,client:client)
        coach.ask("b1 的马怎么走？");try await wait(coach)
        let requests=await client.captured();XCTAssertEqual(requests.count,2)
        let messages=requests[1]["messages"] as! [[String:Any]];XCTAssertEqual(messages.last?["role"] as? String,"tool");XCTAssertEqual(messages.last?["tool_call_id"] as? String,"inspect")
        XCTAssertEqual(s.rules.fen,fen);XCTAssertEqual(coach.history.last?.role,"coach")
    }
    func testChangedPositionDiscardsOldAnswer()async throws {
        let s=try session(),client=ScriptedDeepSeek([.init(id:"late",model:"deepseek-fixture",text:"旧局面回答不应出现")],delay:.milliseconds(80)),coach=try DeepSeekCoach(session:s,client:client)
        coach.ask("这步棋为什么？");try await Task.sleep(for:.milliseconds(10));s.newGame(side:"b")
        try await Task.sleep(for:.milliseconds(120));XCTAssertFalse(coach.thinking);XCTAssertFalse(coach.history.contains{$0.role=="coach"});XCTAssertNil(s.voiceLease)
    }
    func testStopAndTimeoutCancelWithoutFallback()async throws {
        for stopManually in [false,true] {
            let s=try session(),client=ScriptedDeepSeek([.init(id:"late",model:"deepseek-fixture",text:"迟到的回答")],delay:.seconds(2)),coach=try DeepSeekCoach(session:s,client:client,timeout:0.04)
            coach.ask("请分析这里");if stopManually{try await Task.sleep(for:.milliseconds(10));coach.stop()}
            try await Task.sleep(for:.milliseconds(90));XCTAssertFalse(coach.thinking);XCTAssertNil(s.voiceLease);XCTAssertFalse(coach.history.contains{$0.role=="coach"});let count=await client.count;XCTAssertLessThanOrEqual(count,1)
        }
    }
    func testToolRoundsAreBounded()async throws {
        let s=try session(),reply=DeepSeekChatReply(id:"loop",model:"deepseek-fixture",text:"",calls:[.init(id:"inspect",name:"inspect_piece",arguments:"{\"square\":\"b1\"}")]),client=ScriptedDeepSeek(Array(repeating:reply,count:8)),coach=try DeepSeekCoach(session:s,client:client)
        coach.ask("请检查");try await wait(coach);let count=await client.count;XCTAssertEqual(count,DeepSeekCoach.maximumRounds);XCTAssertFalse(coach.history.contains{$0.role=="coach"});XCTAssertNil(s.voiceLease)
    }
    func testUnknownToolsCannotMutateGame()async throws {
        let s=try session(),fen=s.rules.fen,client=ScriptedDeepSeek([.init(id:"bad",model:"deepseek-fixture",text:"",calls:[.init(id:"move",name:"play_move",arguments:"{\"from\":\"e2\",\"to\":\"e4\"}")]),.init(id:"end",model:"deepseek-fixture",text:"此教练只提供建议，不替你走棋。")]),coach=try DeepSeekCoach(session:s,client:client)
        coach.ask("替我走棋");try await wait(coach);XCTAssertEqual(s.rules.fen,fen)
        let messages=(await client.captured())[1]["messages"] as! [[String:Any]];XCTAssertTrue((messages.last?["content"] as? String)?.contains("INVALID_ARGUMENT")==true)
    }
    func testCompanionOwnershipPreventsRequestsAndCancelsPendingAnswer()async throws {
        let s=try session(),client=ScriptedDeepSeek([.init(id:"late",model:"deepseek-fixture",text:"旧回答")],delay:.milliseconds(80)),coach=try DeepSeekCoach(session:s,client:client)
        coach.ask("分析局面");try await Task.sleep(for:.milliseconds(10))
        s.setConnection(enabled:true,role:"coach")
        try await Task.sleep(for:.milliseconds(120))
        XCTAssertFalse(coach.available);XCTAssertFalse(coach.thinking)
        XCTAssertFalse(coach.history.contains{$0.role=="coach"})
        let before=await client.count;coach.ask("再问一次");let after=await client.count
        XCTAssertEqual(before,after)
    }
    func testAnotherVoiceLeaseIsNeverClosedByDeepSeek()async throws {
        let s=try session(),other=try s.openVoice(),client=ScriptedDeepSeek([]),coach=try DeepSeekCoach(session:s,client:client)
        coach.ask("分析局面");try await wait(coach);coach.stop()
        let count=await client.count;XCTAssertEqual(count,0);XCTAssertEqual(s.voiceLease,other)
        s.closeVoice()
    }
    func testReviewWorkspaceWithoutVisibleBoardRejectsQuestions()async throws {
        let s=try session(),client=ScriptedDeepSeek([]),coach=try DeepSeekCoach(session:s,client:client)
        s.suspendForReview();XCTAssertFalse(coach.available);coach.ask("现在应该怎么走？")
        let count=await client.count;XCTAssertEqual(count,0);XCTAssertTrue(coach.history.isEmpty)
    }
    func testSpokenCoordinatesDoNotChangeDisplayedNotation(){let text="把马从 b1 走到 c3，先看 e4。";let speech=ChineseCoachSpeech.spokenCoordinates(text);XCTAssertEqual(text,"把马从 b1 走到 c3，先看 e4。");XCTAssertTrue(speech.contains("B 一"));XCTAssertTrue(speech.contains("C 三"));XCTAssertFalse(speech.contains("e4"))}
}
