import AppKit
import SwiftUI
import CheckmateCore

@MainActor enum DeepSeekConsent {
    static func ask(_ reply:@escaping (Bool)->Void){
        let alert=NSAlert();alert.messageText=String(localized:"Ask the chess coach using DeepSeek?",bundle:.checkmate)
        alert.informativeText=String(localized:"Your question and the current board are sent to DeepSeek and charged to your API account. Chinese microphone input uses macOS speech recognition, which may use Apple servers when on-device recognition is unavailable. Replies use the system Mandarin voice. The microphone starts only when you press Speak.",bundle:.checkmate)
        alert.addButton(withTitle:String(localized:"Agree",bundle:.checkmate)).setAccessibilityIdentifier("deepseek-consent-agree")
        alert.addButton(withTitle:String(localized:"Cancel",bundle:.checkmate)).setAccessibilityIdentifier("deepseek-consent-cancel")
        alert.present(on:NSApp.keyWindow ?? NSApp.mainWindow){reply($0 == .alertFirstButtonReturn)}
    }
}
extension NativeModel {
    var usesDeepSeekCoach:Bool{session.state.settings.coachProvider=="deepseek"}
    func withDeepSeekConsent(_ action:@escaping ()->Void){
        guard usesDeepSeekCoach else{return}
        if session.state.settings.deepSeekConsent{action();return}
        guard !deepSeekConsentPending else{return};deepSeekConsentPending=true
        let identity=session.displayIdentity
        askDeepSeekConsent{[weak self] agreed in
            guard let self else{return};deepSeekConsentPending=false
            guard agreed else{return}
            var settings=session.state.settings;settings.deepSeekConsent=true;session.updateSettings(settings)
            guard identity==session.displayIdentity,deepSeekCoach.available else{return}
            action()
        }
    }
    func askDeepSeek(_ text:String){
        let question=text.trimmingCharacters(in:.whitespacesAndNewlines);guard !question.isEmpty else{return}
        if voice.connected || voice.connecting{voice.disconnect()}
        withDeepSeekConsent{[weak self] in guard let self else{return};deepSeekCoach.ask(question);if voiceHelp.draft.trimmingCharacters(in:.whitespacesAndNewlines)==question{voiceHelp.draft=""}}
    }
    func listenWithDeepSeek(){
        if voice.connected || voice.connecting{voice.disconnect()}
        withDeepSeekConsent{[weak self] in self?.learning.pauseNarration();self?.audio.stopAll();self?.deepSeekCoach.startListening()}
    }
}

struct DeepSeekCoachCard:View {
    @ObservedObject var coach:DeepSeekCoach
    @ObservedObject var help:VoiceHelp
    let model:NativeModel
    private func submit(){let question=help.draft;model.askDeepSeek(question);if model.session.state.settings.deepSeekConsent{help.draft=""}}
    var body:some View {
        Divider();Text("DeepSeek Chess Coach").sectionHeading()
        Text("Ask about the current position in Chinese. DeepSeek uses the board and local chess tools to guide you.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        Text(coach.status).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("deepseek-coach-status")
        if coach.thinking{ProgressView().controlSize(.small)}
        TextField("Ask DeepSeek…",text:$help.draft).onSubmit{submit()}.accessibilityIdentifier("deepseek-ask")
        HStack {
            Button("Send"){submit()}.disabled(help.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || !coach.available).accessibilityIdentifier("deepseek-send")
            Button(coach.listening ? String(localized:"Finish Speaking",bundle:.checkmate):String(localized:"Speak Chinese",bundle:.checkmate)){
                if coach.listening{coach.finishListening()}else{model.listenWithDeepSeek()}
            }.disabled(!coach.available).accessibilityIdentifier("deepseek-microphone")
            Button("Stop"){coach.stop()}.disabled(!coach.thinking && !coach.listening && !coach.speaking).accessibilityIdentifier("deepseek-stop")
        }
        if !coach.lastQuestion.isEmpty,!coach.thinking{Button("Ask That Again"){model.askDeepSeek(coach.lastQuestion)}.disabled(!coach.available).accessibilityIdentifier("deepseek-retry")}
        Text("DeepSeek API charges apply when you ask a question. Press Speak to interrupt playback and start a new question.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
        ForEach(Array(coach.history.reversed())){entry in VStack(alignment:.leading,spacing:Metrics.tightGap){Text(entry.role=="learner" ? String(localized:"You",bundle:.checkmate):"DeepSeek").font(.caption).foregroundStyle(.secondary);Text(entry.text).textSelection(.enabled)}.accessibilityIdentifier("deepseek-message-"+entry.id)}
        if !coach.history.isEmpty{Button("Clear Conversation"){coach.clearHistory()}.accessibilityIdentifier("deepseek-clear")}
    }
}

struct DeepSeekSettingsContent:View {
    @ObservedObject var session:GameSession
    @ObservedObject var coach:DeepSeekCoach
    @State private var devices:[VoiceInputDevice]=[]
    var body:some View {
        Section("Answer model"){
            Text("DeepSeek · deepseek-flash")
            Text("DeepSeek is the default chess reasoning service. Questions are sent only when you ask; there is no automatic provider fallback.").font(.caption).foregroundStyle(.secondary)
            Button("Check Configuration"){coach.checkAvailability()}.accessibilityIdentifier("deepseek-check")
            Text(coach.status).textSelection(.enabled)
        }
        Section("Speech"){
            Toggle("Read DeepSeek Answers Aloud",isOn:session.binding(\.deepSeekSpeak)).accessibilityIdentifier("deepseek-speak-answers")
            Text("Mandarin speech uses the macOS system voice. Microphone recognition uses macOS Speech; on-device recognition is preferred when available.").font(.caption).foregroundStyle(.secondary)
            Slider(value:session.binding(\.voiceVolume),in:0...1){Text("Coach volume")}
            Button("Preview Mandarin Voice"){coach.readFacts(String(localized:"Hello. Let us look at this chess position together.",bundle:.checkmate))}.accessibilityIdentifier("deepseek-voice-preview")
            Picker("Input device",selection:session.binding(\.voiceInputDevice)){Text("System default").tag("");ForEach(devices){Text($0.name).tag($0.id)}}.onAppear{devices=VoiceAudio.devices()}
            Text("Recording and playback take turns to prevent echoes. Press Speak Chinese to interrupt the answer; press Finish Speaking to submit it.").font(.caption).foregroundStyle(.secondary)
        }
        Section("API access"){
            Text("Configure DEEPSEEK_API_KEY on this Mac. The key stays outside saved games, conversations and exported language packs.").font(.caption).foregroundStyle(.secondary)
            Text("Text tokens, speech-recognition time and speech-playback time are recorded separately in Usage.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
