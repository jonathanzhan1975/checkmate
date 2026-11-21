import Foundation
import CheckmateCore

/// Explicit silent acceptance fixtures, selected only by NativeModel's automation
/// guard. No HTTP client, audio device, recognizer or synthesizer is created here.
struct DeepSeekFixturePlan:Codable,Sendable {
    var text="这是针对当前显示局面的受控中文回答。"
    var delayMilliseconds=0
    var failure:String?
}

@MainActor final class DeepSeekFixtureRecorder {
    let directory:URL
    private(set) var requests:[[String:Any]]=[],responses:[[String:Any]]=[]
    private(set) var speechTexts:[String]=[]
    private(set) var microphoneStarts=0,speechStops=0,stopCalls=0
    private(set) var listening=false,speaking=false
    init(directory:URL)throws {
        self.directory=directory.appendingPathComponent("DeepSeekFixture")
        try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)
        persist()
    }
    var snapshot:[String:Any] {["requests":requests,"responses":responses,"speechTexts":speechTexts,"microphoneStarts":microphoneStarts,"speechStops":speechStops,"stopCalls":stopCalls,"listening":listening,"speaking":speaking]}
    func writeSnapshot(to url:URL)throws {try JSONSerialization.data(withJSONObject:snapshot,options:[.prettyPrinted,.sortedKeys]).write(to:url,options:.atomic)}
    private func persist(){try? writeSnapshot(to:directory.appendingPathComponent("receipt.json"))}
    func setPlan(text:String,delayMilliseconds:Int=0,failure:String?=nil)throws {
        try JSONEncoder().encode(DeepSeekFixturePlan(text:text,delayMilliseconds:delayMilliseconds,failure:failure)).write(to:directory.appendingPathComponent("plan.json"),options:.atomic)
    }
    func beginRequest(_ id:Int,messages:Data,tools:Data)throws -> DeepSeekFixturePlan {
        requests.append(["id":id,"messages":try JSONSerialization.jsonObject(with:messages),"tools":try JSONSerialization.jsonObject(with:tools)])
        persist()
        let path=directory.appendingPathComponent("plan.json")
        return FileManager.default.fileExists(atPath:path.path) ? try JSONDecoder().decode(DeepSeekFixturePlan.self,from:Data(contentsOf:path)):DeepSeekFixturePlan()
    }
    func response(_ id:Int,status:String){responses.append(["id":id,"status":status]);persist()}
    func state(listening:Bool,speaking:Bool){self.listening=listening;self.speaking=speaking;persist()}
    func microphoneStarted(){microphoneStarts+=1;persist()}
    func spoke(_ text:String){speechTexts.append(text);persist()}
    func stoppedSpeech(){speechStops+=1;persist()}
    func stopped(){stopCalls+=1;persist()}
}

private actor DeepSeekFixtureClient:DeepSeekChatProviding {
    let recorder:DeepSeekFixtureRecorder
    private var serial=0
    init(recorder:DeepSeekFixtureRecorder){self.recorder=recorder}
    func reply(messages:Data,tools:Data)async throws -> DeepSeekChatReply {
        serial+=1;let id=serial
        let plan=try await recorder.beginRequest(id,messages:messages,tools:tools)
        do {
            if plan.delayMilliseconds>0{try await Task.sleep(for:.milliseconds(min(10_000,plan.delayMilliseconds)))}
            try Task.checkCancellation()
            if let failure=plan.failure{throw CheckmateError.unavailable(failure)}
            await recorder.response(id,status:"completed")
            return DeepSeekChatReply(id:"deepseek-fixture-\(id)",model:"deepseek-fixture",text:plan.text)
        } catch {
            await recorder.response(id,status:error is CancellationError ? "cancelled":"failed")
            throw error
        }
    }
}

@MainActor final class DeepSeekFixtureSpeech:ChineseCoachSpeechDriving {
    private(set) var listening=false,speaking=false
    var onTranscript:((String)->Void)?,onFailure:((String)->Void)?,onStateChange:(()->Void)?
    var transcript="请解释当前棋盘。"
    let recorder:DeepSeekFixtureRecorder
    init(recorder:DeepSeekFixtureRecorder){self.recorder=recorder}
    private func changed(){recorder.state(listening:listening,speaking:speaking);onStateChange?()}
    func startListening(device:String)async throws {stop();recorder.microphoneStarted();listening=true;changed()}
    func finishListening(){guard listening else{return};listening=false;changed();onTranscript?(transcript)}
    func speak(_ text:String,volume:Float){stop();recorder.spoke(text);speaking=true;changed()}
    func stopSpeaking(){if speaking{recorder.stoppedSpeech()};speaking=false;changed()}
    func stop(){recorder.stopped();listening=false;stopSpeaking()}
}

@MainActor final class DeepSeekAutomationFixture {
    let recorder:DeepSeekFixtureRecorder,speech:DeepSeekFixtureSpeech
    let client:any DeepSeekChatProviding
    init(directory:URL)throws {
        let recorder=try DeepSeekFixtureRecorder(directory:directory)
        self.recorder=recorder;speech=DeepSeekFixtureSpeech(recorder:recorder);client=DeepSeekFixtureClient(recorder:recorder)
    }
}
