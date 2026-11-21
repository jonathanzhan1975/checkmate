import XCTest
import Combine
import CheckmateCore
import CheckmateTestSupport
@testable import CheckmateApplication

@MainActor private final class SilentCoachSpeech:ChineseCoachSpeechDriving {
    var listening=false,speaking=false,starts=0
    var onTranscript:((String)->Void)?,onFailure:((String)->Void)?,onStateChange:(()->Void)?
    var texts:[String]=[],transcript="为什么这步不能走？"
    func startListening(device:String)async throws {stop();starts+=1;listening=true;onStateChange?()}
    func finishListening(){guard listening else{return};listening=false;onStateChange?();onTranscript?(transcript)}
    func speak(_ text:String,volume:Float){listening=false;texts.append(text);speaking=true;onStateChange?()}
    func stopSpeaking(){speaking=false;onStateChange?()}
    func stop(){listening=false;stopSpeaking()}
}

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
    func testChineseInputHandsOffToAnswerAndLocalSpeech()async throws {
        let s=try session(),speech=SilentCoachSpeech(),client=ScriptedDeepSeek([.init(id:"spoken",model:"deepseek-fixture",text:"先检查王是否安全。")])
        var settings=s.state.settings;settings.deepSeekSpeak=true;s.updateSettings(settings)
        let coach=try DeepSeekCoach(session:s,client:client,speech:speech),fen=s.rules.fen
        coach.startListening();try await poll("Chinese input ready",tries:200,every:.milliseconds(5)){coach.listening}
        coach.finishListening();try await wait(coach)
        XCTAssertEqual(coach.history.first?.text,speech.transcript);XCTAssertEqual(speech.texts,["先检查王是否安全。"])
        XCTAssertTrue(coach.speaking);XCTAssertFalse(coach.listening);XCTAssertEqual(s.rules.fen,fen)
        coach.stop();XCTAssertFalse(speech.listening || speech.speaking);XCTAssertNil(s.voiceLease)
    }
    func testProvedFactsReadExactlyWithoutModelOrMicrophoneAndStopOnNewGame()async throws {
        let s=try session(consent:false),speech=SilentCoachSpeech(),client=ScriptedDeepSeek([]),coach=try DeepSeekCoach(session:s,client:client,speech:speech)
        let facts="第1步：这里有已证明的将死。\n车在 a1，王在 h8。"
        coach.readFacts(facts);XCTAssertEqual(speech.texts,[facts]);XCTAssertTrue(coach.speaking)
        coach.stopLocalReviewReading();XCTAssertFalse(speech.speaking)
        coach.readFacts(facts);XCTAssertEqual(speech.texts,[facts,facts]);s.newGame(side:"b")
        try await poll("Old local reading stopped",tries:200,every:.milliseconds(5)){!coach.speaking}
        let count=await client.count;XCTAssertEqual(count,0);XCTAssertEqual(speech.starts,0);XCTAssertNil(s.voiceLease)
    }
    func testStoppedInputCannotSubmitALateTranscript()async throws {
        let speech=SilentCoachSpeech(),client=ScriptedDeepSeek([]),coach=try DeepSeekCoach(session:session(),client:client,speech:speech)
        coach.startListening();try await poll("Input ready",tries:200,every:.milliseconds(5)){coach.listening}
        coach.stop();speech.onTranscript?("迟到的旧问题")
        let count=await client.count;XCTAssertEqual(count,0);XCTAssertTrue(coach.history.isEmpty);XCTAssertFalse(coach.listening || coach.speaking)
    }
    func testReviewAnswerAndPieceToolUseTheReviewBoard()async throws {
        let s=try session(),review=ReviewController();s.reviewController=review
        _ = try s.rules.move(uci:"e2e4");let practice=s.rules.fen
        let document=try PGNImporter.parse(Data("1. d4 d5 *".utf8))[0];review.open(document,practice:s);try review.select(1)
        let shown=try XCTUnwrap(review.displayRules?.fen),node=review.nodeID
        let client=ScriptedDeepSeek([.init(id:"piece",model:"deepseek-fixture",text:"",calls:[.init(id:"d4",name:"inspect_piece",arguments:"{\"square\":\"d4\"}")]),.init(id:"answer",model:"deepseek-fixture",text:"这里解释的是复盘中的 d4 兵。")])
        let coach=try DeepSeekCoach(session:s,client:client);coach.attach(review:review,training:nil)
        XCTAssertTrue(coach.available);coach.ask("复盘里这个兵为什么到 d4？");try await wait(coach)
        let requests=await client.captured();XCTAssertEqual(requests.count,2)
        let messages=requests[0]["messages"] as! [[String:Any]],input=messages.last!["content"] as! String
        let context=try JSONSerialization.jsonObject(with:Data(try XCTUnwrap(input.components(separatedBy:"本轮已验证棋局数据：\n").last).utf8))
        let normalized=String(decoding:try JSONSerialization.data(withJSONObject:context,options:.withoutEscapingSlashes),as:UTF8.self)
        XCTAssertTrue(normalized.contains(shown));XCTAssertFalse(normalized.contains(practice))
        let continued=requests[1]["messages"] as! [[String:Any]];XCTAssertTrue((continued.last?["content"] as? String)?.contains("d4")==true)
        XCTAssertEqual(coach.history.last?.source,.review);XCTAssertEqual(review.nodeID,node);XCTAssertEqual(s.rules.fen,practice);XCTAssertNil(s.voiceLease)
    }
    func testTrainingAnswerRecordsHelpBeforeDisclosureAndKeepsPracticeSeparate()async throws {
        setEnvironment(["CHECKMATE_TRAINING_ENABLED":"1","CHECKMATE_TRAINING_B":"1","CHECKMATE_TRAINING_VOICE":"1"])
        let defender=ScriptedDefender(),(s,player,controller)=try TrainingEndgameTests.fixture([TrainingVoiceAdapterTests.scenario()],defender:defender)
        defer{defender.release();player.shutdown()}
        try s.playWhite(from:"e2",to:"e4");_ = try s.commitBlack("e7e5");let practice=s.rules.fen
        controller.begin(try controller.prepare(entry:"finish-the-game"))
        var settings=s.state.settings;settings.deepSeekConsent=true;settings.deepSeekSpeak=false;s.updateSettings(settings)
        let adapter=TrainingVoiceAdapter(session:s,controller:controller),review=ReviewController(),shown=try XCTUnwrap(controller.exercise?.current?.fen)
        let client=ScriptedDeepSeek([.init(id:"piece",model:"deepseek-fixture",text:"",calls:[.init(id:"g1",name:"inspect_piece",arguments:"{\"square\":\"g1\"}")]),.init(id:"answer",model:"deepseek-fixture",text:"训练里的后在 g1，先限制对方王的活动。")])
        let coach=try DeepSeekCoach(session:s,client:client);coach.attach(review:review,training:adapter)
        XCTAssertTrue(coach.available);XCTAssertFalse(controller.exercise!.snapshot.recordedHelp)
        var helpBeforeDisclosure=false
        let observation=coach.$history.sink{entries in if entries.contains(where:{$0.role=="coach"}){helpBeforeDisclosure=controller.exercise?.snapshot.recordedHelp==true}}
        defer{observation.cancel();coach.stop()}
        coach.ask("训练局面中的后该怎么配合王？");try await wait(coach)
        let requests=await client.captured();XCTAssertEqual(requests.count,2);XCTAssertTrue(helpBeforeDisclosure)
        let messages=requests[0]["messages"] as! [[String:Any]],input=messages.last!["content"] as! String
        let context=try JSONSerialization.jsonObject(with:Data(try XCTUnwrap(input.components(separatedBy:"本轮已验证棋局数据：\n").last).utf8))
        let normalized=String(decoding:try JSONSerialization.data(withJSONObject:context,options:.withoutEscapingSlashes),as:UTF8.self)
        XCTAssertTrue(normalized.contains(shown));XCTAssertFalse(normalized.contains(practice))
        for secret in TrainingVoiceAdapterTests.secrets{XCTAssertFalse(normalized.contains(secret))}
        XCTAssertEqual(coach.history.last?.source,.training);XCTAssertEqual(controller.exercise?.current?.fen,shown);XCTAssertEqual(s.rules.fen,practice)
    }
    func testChangingReviewNodeCancelsAnInFlightAnswer()async throws {
        let s=try session(),review=ReviewController();s.reviewController=review
        var settings=s.state.settings;settings.deepSeekSpeak=true;s.updateSettings(settings)
        let document=try PGNImporter.parse(Data("1. d4 d5 *".utf8))[0];review.open(document,practice:s)
        let client=ScriptedDeepSeek([.init(id:"late",model:"deepseek-fixture",text:"旧复盘节点回答")],delay:.milliseconds(150))
        let speech=SilentCoachSpeech(),coach=try DeepSeekCoach(session:s,client:client,speech:speech);coach.attach(review:review,training:nil)
        coach.ask("解释旧复盘节点")
        for _ in 0..<100 {if await client.count==1{break};try await Task.sleep(for:.milliseconds(5))}
        let count=await client.count;XCTAssertEqual(count,1);XCTAssertTrue(coach.thinking)
        try review.select(1);try await Task.sleep(for:.milliseconds(220))
        XCTAssertFalse(coach.thinking);XCTAssertFalse(coach.history.contains{$0.role=="coach"});XCTAssertTrue(speech.texts.isEmpty);XCTAssertNil(s.voiceLease)
    }
    func testReplacingTrainingAttemptCancelsAnInFlightAnswer()async throws {
        setEnvironment(["CHECKMATE_TRAINING_ENABLED":"1","CHECKMATE_TRAINING_B":"1","CHECKMATE_TRAINING_VOICE":"1"])
        let defender=ScriptedDefender(),(s,player,controller)=try TrainingEndgameTests.fixture([TrainingVoiceAdapterTests.scenario()],defender:defender)
        defer{defender.release();player.shutdown()}
        controller.begin(try controller.prepare(entry:"finish-the-game"))
        var settings=s.state.settings;settings.deepSeekConsent=true;settings.deepSeekSpeak=true;s.updateSettings(settings)
        let adapter=TrainingVoiceAdapter(session:s,controller:controller),review=ReviewController(),attempt=controller.exercise!.snapshot.id
        let client=ScriptedDeepSeek([.init(id:"late",model:"deepseek-fixture",text:"旧训练尝试回答")],delay:.milliseconds(150)),speech=SilentCoachSpeech()
        let coach=try DeepSeekCoach(session:s,client:client,speech:speech);coach.attach(review:review,training:adapter)
        coach.ask("解释旧训练尝试")
        for _ in 0..<100 {if await client.count==1{break};try await Task.sleep(for:.milliseconds(5))}
        let count=await client.count;XCTAssertEqual(count,1);XCTAssertTrue(coach.thinking)
        controller.begin(try controller.prepare(entry:"finish-the-game"));XCTAssertNotEqual(controller.exercise!.snapshot.id,attempt)
        try await Task.sleep(for:.milliseconds(220))
        XCTAssertFalse(coach.thinking);XCTAssertFalse(coach.history.contains{$0.role=="coach"});XCTAssertTrue(speech.texts.isEmpty);XCTAssertFalse(controller.exercise!.snapshot.recordedHelp)
    }
    func testSpokenCoordinatesDoNotChangeDisplayedNotation(){let text="把马从 b1 走到 c3，先看 e4。";let speech=ChineseCoachSpeech.spokenCoordinates(text);XCTAssertEqual(text,"把马从 b1 走到 c3，先看 e4。");XCTAssertTrue(speech.contains("B 一"));XCTAssertTrue(speech.contains("C 三"));XCTAssertFalse(speech.contains("e4"))}
}
