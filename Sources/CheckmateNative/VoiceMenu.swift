import AppKit
import CheckmateCore

/// V-20: Game ▸ Connect Voice Coach and Stop Speaking (⌘.). Both hide in a network game, which has its own coach.
extension GameWindow {
    /// Connects through the consent question (`NativeModel.connectPracticeVoice`), or disconnects a coach already on.
    @objc func toggleVoiceCoach(){if model.usesDeepSeekCoach{showDetails();model.deepSeekCoach.checkAvailability();return};let voice=model.voice;if voice.connected || voice.connecting{voice.disconnect()}else{model.connectPracticeVoice()}}
    @objc func stopSpeaking(){if model.usesDeepSeekCoach{model.deepSeekCoach.stop();return};guard model.voice.canStopTurn else{return};model.voice.stopTurn()}
    /// Whether a voice item is enabled, with Connect's title following the connection; nil for other items.
    /// `offered`: the control bar offers Connect here now.
    static func voiceMenuItemEnabled(_ item:NSMenuItem,model:NativeModel,offered:Bool)->Bool? {
        if model.usesDeepSeekCoach {
            switch item.action {
            case #selector(toggleVoiceCoach)?:item.title=String(localized:"Ask DeepSeek",bundle:.checkmate);return offered || model.deepSeekCoach.available
            case #selector(stopSpeaking)?:return model.deepSeekCoach.thinking || model.deepSeekCoach.listening || model.deepSeekCoach.speaking
            default:return nil
            }
        }
        let voice=model.voice
        switch item.action {
        case #selector(toggleVoiceCoach)?:
            item.title=voice.connected ? String(localized:"Disconnect Voice Coach",bundle:.checkmate):voice.connecting ? String(localized:"Cancel Voice Coach",bundle:.checkmate):String(localized:"Connect Voice Coach",bundle:.checkmate)
            return voice.connected || voice.connecting || offered
        case #selector(stopSpeaking)?:return voice.connected && voice.canStopTurn
        default:return nil
        }
    }
}
