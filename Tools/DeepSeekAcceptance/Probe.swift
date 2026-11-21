import Foundation
import CheckmateCore

actor ObservedDeepSeek:DeepSeekChatProviding {
    let client:DeepSeekChatClient
    var models:[String]=[],tools:[String]=[],contexts:[Data]=[],toolMessages:[Data]=[]
    var calls:[DeepSeekToolCall]=[]
    init(key:String){client=DeepSeekChatClient(key:{key})}
    func reply(messages:Data,tools:Data)async throws->DeepSeekChatReply{
        if let values=try JSONSerialization.jsonObject(with:messages) as? [[String:Any]],
           let question=values.last?["content"] as? String,question.contains("本轮已验证棋局数据：\n"),
           let context=question.components(separatedBy:"本轮已验证棋局数据：\n").last {contexts.append(Data(context.utf8))}
        if let values=try JSONSerialization.jsonObject(with:messages) as? [[String:Any]] {for value in values where value["role"] as? String=="tool"{toolMessages.append(try JSONSerialization.data(withJSONObject:value))}}
        let answer=try await client.reply(messages:messages,tools:tools);models.append(answer.model);self.tools+=answer.calls.map(\.name);calls+=answer.calls;return answer}
}
@main struct DeepSeekAcceptance {
    @MainActor static func main()async {
        do {
            guard CommandLine.arguments.contains("--live-deepseek"),let index=CommandLine.arguments.firstIndex(of:"--output"),CommandLine.arguments.indices.contains(index+1) else{throw CheckmateError.invalid("Use --live-deepseek --output PATH; this explicitly makes paid DeepSeek requests, without microphone or speaker.")}
            let key=ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
            guard !key.isEmpty else{throw CheckmateError.invalid("DEEPSEEK_API_KEY is missing")}
            let scopeIndex=CommandLine.arguments.firstIndex(of:"--scope")
            let scope=scopeIndex.flatMap{CommandLine.arguments.indices.contains($0+1) ? CommandLine.arguments[$0+1]:nil} ?? "practice"
            guard ["practice","review","training"].contains(scope) else{throw CheckmateError.invalid("Unknown DeepSeek probe scope")}
            let output=URL(fileURLWithPath:CommandLine.arguments[index+1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            let provider=ObservedDeepSeek(key:key),session=try GameSession(engine:NativeEngine())
            var settings=session.state.settings;settings.deepSeekConsent=true;settings.deepSeekSpeak=false;session.updateSettings(settings)
            let review=ReviewController();session.reviewController=review
            var player:LearningPlayer?,training:TrainingController?,adapter:TrainingVoiceAdapter?
            defer{player?.shutdown()}
            var expectedFEN=session.rules.fen,expectedTool="analyze_position",question="请先调用 analyze_position 检查当前局面，再用简体中文给初学者一个简短建议。不要替我走棋。"
            var expectedSquare:String?
            if scope != "practice" {_ = try session.rules.move(uci:"e2e4")}
            let practiceFEN=session.rules.fen
            if scope=="review" {
                let document=try PGNImporter.parse(Data("1. d4 d5 *".utf8))[0];review.open(document,practice:session);try review.select(1)
                guard let shown=review.displayFEN else{throw CheckmateError.invalid("Review board missing")};expectedFEN=shown
                expectedTool="inspect_piece";expectedSquare="d4";question="请先调用 inspect_piece 检查当前复盘中的 d4，再用简体中文简短解释这里的兵。不要替我走棋。"
            } else if scope=="training" {
                setenv("CHECKMATE_TRAINING_ENABLED","1",1);setenv("CHECKMATE_TRAINING_B","1",1);setenv("CHECKMATE_TRAINING_VOICE","1",1)
                let learning=try LearningPlayer(session:session),controller=TrainingController(session:session,learning:learning)
                player=learning;training=controller;controller.games.engine=NativeEngine()
                controller.begin(try controller.prepare(entry:"finish-the-game",variant:"kqk"))
                guard let exercise=controller.exercise,let start=exercise.scenario.fen,let square=exercise.board.keys.sorted().first else{throw CheckmateError.invalid("Missing training fixture")}
                let rules=try ChessRules(fen:start);for move in exercise.scenario.prelude ?? []{_ = try rules.move(uci:move)};expectedFEN=rules.fen
                adapter=TrainingVoiceAdapter(session:session,controller:controller)
                expectedTool="inspect_piece";expectedSquare=square;question="请先调用 inspect_piece 检查当前训练中的 \(square)，再用简体中文给初学者一个简短提示。不要替我走棋，也不要读取其他棋盘。"
            }
            let ledger=UsageLedger(directory:output.appendingPathComponent("Usage")),coach=try DeepSeekCoach(session:session,client:provider)
            coach.attach(review:review,training:adapter);coach.usageLedger=ledger
            let trainingBefore=training?.exercise?.snapshot.actions
            coach.ask(question)
            for _ in 0..<2000{if !coach.thinking{break};try await Task.sleep(for:.milliseconds(50))}
            let answer=coach.history.last(where:{$0.role=="coach"})?.text ?? "",tools=await provider.tools,models=await provider.models
            let contexts=await provider.contexts
            let context: [String:Any]
            if let data=contexts.first,let parsed=try JSONSerialization.jsonObject(with:data) as? [String:Any]{context=parsed}else{context=[:]}
            let state=context["state"] as? [String:Any] ?? [:],trainingContext=context["training"] as? [String:Any] ?? [:]
            let display=state["display"] as? [String:Any] ?? [:]
            let actualFEN=context["fen"] as? String ?? trainingContext["fen"] as? String ?? display["fen"] as? String ?? ""
            let actualScope=context["scope"] as? String ?? state["mode"] as? String ?? ""
            let scopeCorrect:Bool
            if scope=="review" {scopeCorrect=actualScope=="read-only-review" && actualFEN==expectedFEN && context["nodeId"] as? Int==1 && coach.history.last?.source == .review}
            else if scope=="training" {scopeCorrect=actualScope=="training" && actualFEN==expectedFEN && coach.history.last?.source == .training && training?.exercise?.snapshot.recordedHelp==true}
            else {scopeCorrect=actualScope=="practice" && actualFEN==expectedFEN && coach.history.last?.source == .practice}
            let calls=await provider.calls,toolMessages=try await provider.toolMessages.compactMap{try JSONSerialization.jsonObject(with:$0) as? [String:Any]}
            let expectedRules=try ChessRules(fen:expectedFEN)
            var toolChecks:[[String:Any]]=[]
            for call in calls where call.name==expectedTool {
                let args=try JSONSerialization.jsonObject(with:Data(call.arguments.utf8)) as? [String:Any] ?? [:]
                let message=toolMessages.last{$0["tool_call_id"] as? String==call.id}
                let content=message?["content"] as? String ?? "null"
                let result=(try? JSONSerialization.jsonObject(with:Data(content.utf8))) as? [String:Any] ?? [:]
                var valid=false
                if result["error"]==nil,result["ok"] as? Bool != false {
                    if expectedTool=="inspect_piece",let square=expectedSquare,args["square"] as? String==square {
                        let inspection=result["inspection"] as? [String:Any] ?? result
                        if let actual=try? JSONDecoder().decode(PieceInspection.self,from:JSONSerialization.data(withJSONObject:inspection)){
                            valid=actual == (try expectedRules.inspect(square))
                        }
                    } else if let analysis=result["analysis"] as? [String:Any],let best=analysis["bestMove"] as? String,let lines=analysis["lines"] as? [Any] {
                        valid = !lines.isEmpty && expectedRules.moves().contains{$0.uci==best}
                    }
                }
                toolChecks.append(["id":call.id,"name":call.name,"arguments":args,"result":result,"successful":valid])
            }
            let toolSucceeded=toolChecks.contains{$0["successful"] as? Bool==true}
            let boardUnchanged=session.rules.fen==practiceFEN && (scope != "review" || review.displayFEN==expectedFEN) && (scope != "training" || training?.exercise?.snapshot.actions==trainingBefore)
            let passed = !coach.thinking && !answer.isEmpty && answer.range(of:"[\\p{Han}]",options:.regularExpression) != nil && toolSucceeded && boardUnchanged && scopeCorrect && !models.isEmpty && models.allSatisfy{$0.lowercased().contains("deepseek")}
            let report:[String:Any]=["passed":passed,"scope":scope,"actualScope":actualScope,"expectedFEN":expectedFEN,"actualFEN":actualFEN,"scopeCorrect":scopeCorrect,"context":context,"provider":"deepseek","models":models,"tools":tools,"toolChecks":toolChecks,"toolSucceeded":toolSucceeded,"answer":answer,"boardUnchanged":boardUnchanged,"microphoneUsed":false,"speakerUsed":false,"status":coach.status,"usage":ledger.records.map{["model":$0.model ?? "unknown","tokens":$0.tokens?.total as Any? ?? NSNull()]}]
            try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:output.appendingPathComponent("result.json"),options:.atomic)
            coach.stop();session.prepareShutdown();ledger.flushForShutdown()
            guard passed else{throw CheckmateError.invalid("Live DeepSeek acceptance failed; inspect result.json")}
            print("DeepSeek live scoped guidance passed; requested local tool succeeded; board unchanged; no microphone or speaker.")
        }catch{FileHandle.standardError.write(Data((String(describing:error)+"\n").utf8));exit(1)}
    }
}
