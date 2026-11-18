import Foundation
import AVFoundation
import Speech
import CheckmateAssets
import CheckmateDomain
import CheckmateSupport
import PCM16

/// Speech input and output are independent of the reasoning provider. No Codex
/// credentials, model or service are used. Capture and playback take turns to
/// prevent the synthesized answer from being recognized as another question.
@MainActor public final class ChineseCoachSpeech:NSObject,AVSpeechSynthesizerDelegate {
    public private(set) var listening=false,speaking=false
    public var onTranscript:((String)->Void)?,onFailure:((String)->Void)?,onStateChange:(()->Void)?
    private let input=VoiceAudio(),synthesizer=AVSpeechSynthesizer()
    private var request:SFSpeechAudioBufferRecognitionRequest?,recognition:SFSpeechRecognitionTask?
    private var recognizer:SFSpeechRecognizer?
    private var inputFrames=0,signalPeak:Float=0
    private var epoch=UUID(),limit:Task<Void,Never>?
    private var utterance:AVSpeechUtterance?
    public override init(){super.init();synthesizer.delegate=self
        input.onInput={[weak self] data in self?.append(data)}
        input.onInputChanged={[weak self] in guard let self else{return};stopRecognition();onFailure?(String(localized:"The microphone device changed. Select a device and start speaking again.",bundle:.checkmate))}
    }
    public func startListening(device:String)async throws {
        guard !NativePolicy.silent else{throw CheckmateError.unavailable(String(localized:"Microphone capture is disabled during automation.",bundle:.checkmate))}
        stop();let generation=epoch
        let authorization=await withCheckedContinuation{continuation in SFSpeechRecognizer.requestAuthorization{continuation.resume(returning:$0)}}
        guard epoch==generation,!Task.isCancelled else{throw CancellationError()}
        guard authorization == .authorized else{throw CheckmateError.unavailable(String(localized:"Allow Speech Recognition in macOS Privacy & Security, or type your question.",bundle:.checkmate))}
        guard let recognizer=SFSpeechRecognizer(locale:Locale(identifier:"zh-CN")),recognizer.isAvailable else{throw CheckmateError.unavailable(String(localized:"Chinese speech recognition is unavailable. You can type your question.",bundle:.checkmate))}
        let request=SFSpeechAudioBufferRecognitionRequest();request.shouldReportPartialResults=false
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition{request.requiresOnDeviceRecognition=true}
        self.request=request;self.recognizer=recognizer;inputFrames=0;signalPeak=0
        recognition=recognizer.recognitionTask(with:request){[weak self] result,error in
            let final=result?.isFinal==true,text=result?.bestTranscription.formattedString
            Task{@MainActor in
                guard let self,self.epoch==generation else{return}
                if final,let text,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                    self.stopRecognition();self.onTranscript?(text)
                } else if error != nil {
                    if let diagnostic=error as NSError?{NativeLog.voice.error("Chinese speech recognition failed: \(diagnostic.domain,privacy:.public) code \(diagnostic.code), frames \(self.inputFrames), peak \(self.signalPeak)")}
                    self.stopRecognition();self.onFailure?(String(localized:"Speech could not be recognized. Try again or type your question.",bundle:.checkmate))
                }
            }
        }
        // Capture and synthesis take turns, so no voice-processing output graph
        // is needed. Its microphone/speaker format negotiation can fail on Macs.
        do{try await input.startCapture(device:device,voiceProcessing:false);guard epoch==generation,!Task.isCancelled else{throw CancellationError()};input.listening=true;listening=true;onStateChange?()}
        catch{stopRecognition();throw error}
        limit=Task{[weak self] in do{try await Task.sleep(for:.seconds(55));guard let self,epoch==generation else{return};finishListening()}catch{}}
    }
    private func append(_ data:Data){
        guard listening,let request,let format=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:24000,channels:1,interleaved:false) else{return}
        let samples=PCM.decode(data)
        inputFrames+=samples.count;signalPeak=max(signalPeak,samples.reduce(Float(0)){max($0,abs($1))})
        guard !samples.isEmpty,let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:AVAudioFrameCount(samples.count)),let channel=buffer.floatChannelData?[0] else{return}
        buffer.frameLength=AVAudioFrameCount(samples.count);samples.withUnsafeBufferPointer{channel.update(from:$0.baseAddress!,count:samples.count)};request.append(buffer)
    }
    public func finishListening(){
        guard listening else{return};input.stopCapture();listening=false;request?.endAudio();limit?.cancel();onStateChange?()
        let generation=epoch
        limit=Task{[weak self] in do{try await Task.sleep(for:.seconds(8));guard let self,epoch==generation,request != nil else{return};stopRecognition();onFailure?(String(localized:"Speech recognition timed out. Try again or type your question.",bundle:.checkmate))}catch{}}
    }
    private func stopRecognition(){epoch=UUID();limit?.cancel();limit=nil;input.stopCapture();request?.endAudio();recognition?.cancel();recognition=nil;request=nil;recognizer=nil;listening=false;onStateChange?()}
    public func speak(_ text:String,volume:Float){
        stopRecognition();stopSpeaking()
        guard !NativePolicy.silent else{return}
        guard let voice=AVSpeechSynthesisVoice(language:"zh-CN") else{onFailure?(String(localized:"A Mandarin system voice is unavailable. The answer remains available as text.",bundle:.checkmate));return}
        // Keep display notation intact, expanding coordinates only for pronunciation.
        let spoken=Self.spokenCoordinates(text),line=AVSpeechUtterance(string:spoken)
        line.voice=voice;line.rate=AVSpeechUtteranceDefaultSpeechRate;line.volume=max(0,min(1,volume));utterance=line;speaking=true;onStateChange?();synthesizer.speak(line)
    }
    public static func spokenCoordinates(_ text:String)->String {
        let digits=["1":"一","2":"二","3":"三","4":"四","5":"五","6":"六","7":"七","8":"八"]
        guard let regex=try? NSRegularExpression(pattern:"(?<![A-Za-z0-9])([a-hA-H])([1-8])(?![A-Za-z0-9])") else{return text}
        var result=text
        for match in regex.matches(in:text,range:NSRange(text.startIndex...,in:text)).reversed(){
            guard let all=Range(match.range,in:result),let letter=Range(match.range(at:1),in:result),let number=Range(match.range(at:2),in:result) else{continue}
            result.replaceSubrange(all,with:String(result[letter]).uppercased()+" "+(digits[String(result[number])] ?? ""))
        }
        return result
    }
    public func stopSpeaking(){utterance=nil;synthesizer.stopSpeaking(at:.immediate);speaking=false;onStateChange?()}
    public func stop(){stopRecognition();stopSpeaking()}
    nonisolated public func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didFinish utterance:AVSpeechUtterance){Task{@MainActor [weak self] in guard let self,self.utterance===utterance else{return};self.utterance=nil;speaking=false;onStateChange?()}}
    nonisolated public func speechSynthesizer(_ synthesizer:AVSpeechSynthesizer,didCancel utterance:AVSpeechUtterance){Task{@MainActor [weak self] in guard let self,self.utterance===utterance else{return};self.utterance=nil;speaking=false;onStateChange?()}}
}
