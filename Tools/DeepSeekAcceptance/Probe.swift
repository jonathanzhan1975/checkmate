import Foundation
import CheckmateCore

actor ObservedDeepSeek:DeepSeekChatProviding {
    let client:DeepSeekChatClient
    var models:[String]=[],tools:[String]=[]
    init(key:String){client=DeepSeekChatClient(key:{key})}
    func reply(messages:Data,tools:Data)async throws->DeepSeekChatReply{let answer=try await client.reply(messages:messages,tools:tools);models.append(answer.model);self.tools+=answer.calls.map(\.name);return answer}
}
@main struct DeepSeekAcceptance {
    @MainActor static func main()async {
        do {
            guard CommandLine.arguments.contains("--live-deepseek"),let index=CommandLine.arguments.firstIndex(of:"--output"),CommandLine.arguments.indices.contains(index+1) else{throw CheckmateError.invalid("Use --live-deepseek --output PATH; this explicitly makes paid DeepSeek requests, without microphone or speaker.")}
            let key=ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ""
            guard !key.isEmpty else{throw CheckmateError.invalid("DEEPSEEK_API_KEY is missing")}
            let output=URL(fileURLWithPath:CommandLine.arguments[index+1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
            let provider=ObservedDeepSeek(key:key),session=try GameSession(engine:NativeEngine())
            var settings=session.state.settings;settings.deepSeekConsent=true;settings.deepSeekSpeak=false;session.updateSettings(settings)
            let ledger=UsageLedger(directory:output.appendingPathComponent("Usage")),coach=try DeepSeekCoach(session:session,client:provider)
            coach.usageLedger=ledger;let fen=session.rules.fen
            coach.ask("请先调用 analyze_position 检查当前局面，再用简体中文给初学者一个简短建议。不要替我走棋。")
            for _ in 0..<2000{if !coach.thinking{break};try await Task.sleep(for:.milliseconds(50))}
            let answer=coach.history.last(where:{$0.role=="coach"})?.text ?? "",tools=await provider.tools,models=await provider.models
            let passed = !coach.thinking && !answer.isEmpty && answer.range(of:"[\\p{Han}]",options:.regularExpression) != nil && tools.contains("analyze_position") && session.rules.fen==fen && models.allSatisfy{$0.lowercased().contains("deepseek")}
            let report:[String:Any]=["passed":passed,"provider":"deepseek","models":models,"tools":tools,"answer":answer,"boardUnchanged":session.rules.fen==fen,"microphoneUsed":false,"speakerUsed":false,"status":coach.status,"usage":ledger.records.map{["model":$0.model ?? "unknown","tokens":$0.tokens?.total as Any? ?? NSNull()]}]
            try JSONSerialization.data(withJSONObject:report,options:.prettyPrinted).write(to:output.appendingPathComponent("result.json"),options:.atomic)
            coach.stop();session.prepareShutdown();ledger.flushForShutdown()
            guard passed else{throw CheckmateError.invalid("Live DeepSeek acceptance failed; inspect result.json")}
            print("DeepSeek live chess guidance passed; local engine used; board unchanged; no Codex, microphone or speaker.")
        }catch{FileHandle.standardError.write(Data((String(describing:error)+"\n").utf8));exit(1)}
    }
}
