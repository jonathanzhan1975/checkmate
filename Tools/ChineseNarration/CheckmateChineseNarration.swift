import Foundation
import CheckmateDomain
import CheckmateContent
import CheckmateSupport
import CheckmateAssets

/// Explicit live recording utility. Uses the production recorder and its PCM/transcript guards without exceptions.
@main struct CheckmateChineseNarration {
    @MainActor static func main() async {
        do{try await run()}
        catch{fputs("Stopped: \(userFacingMessage(error,fallback:"Recording or verification failed.")). Completed recordings are preserved.\n",stderr);exit(1)}
    }
    @MainActor static func run() async throws {
        guard CommandLine.arguments.contains("--generate") || CommandLine.arguments.contains("--verify"),
              let at=CommandLine.arguments.firstIndex(of:"--output"),CommandLine.arguments.indices.contains(at+1) else {
            print("Usage: CheckmateChineseNarration (--generate [--all] | --verify) --output DIRECTORY")
            return
        }
        let library=try CourseLibrary()
        let directory=URL(fileURLWithPath:CommandLine.arguments[at+1],isDirectory:true)
        let store=try LessonPackStore(directory:directory)
        if CommandLine.arguments.contains("--verify") {
            var clips=0,seconds=0.0
            for index in library.lessons.indices {
                let source=LessonTranslation.source(library:library,index:index)
                guard let expected=BundledLessonText.translation(source:source,locale:"zh-Hans"),
                      let pack=try store.completePack(source:source,locale:"zh-Hans",voice:"cedar"),
                      pack.translation==expected else{throw CheckmateError.invalid("Chinese recordings are incomplete or outdated: \(source.lessonID)")}
                clips+=pack.clips.count;seconds+=pack.clips.reduce(0){$0+$1.seconds}
            }
            var files:[String:String]=[:]
            for file in try FileManager.default.contentsOfDirectory(at:store.directory,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey]) {
                guard file.lastPathComponent.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil,
                      try file.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink != true else{throw CheckmateError.invalid("Unexpected language-pack file.")}
                files[file.lastPathComponent]=reviewHash(try Data(contentsOf:file))
            }
            let proof:[String:Any]=["version":1,"locale":"zh-Hans","voice":"cedar","lessons":library.lessons.count,"clips":clips,"seconds":seconds,
                "sourceHash":reviewHash(try Data(contentsOf:NativeResources.url("course.json"))),
                "translationHash":reviewHash(try Data(contentsOf:NativeResources.url("course.zh-Hans.json"))),"files":files]
            try JSONSerialization.data(withJSONObject:proof,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("verification.json"),options:.atomic)
            print("Verified \(library.lessons.count) lessons, \(clips) clips, \(Int(seconds)) seconds. All audio and script hashes passed.")
            return
        }
        let usage=UsageLedger(directory:directory)
        let recorder=RealtimeLessonRecorder(rejectedRecording:{pcm,transcript,script in
            let failed=directory.appendingPathComponent("rejected",isDirectory:true)
            try? FileManager.default.createDirectory(at:failed,withIntermediateDirectories:true)
            let name=UUID().uuidString
            if let wav=try? LessonRecording.wav(pcm){try? wav.write(to:failed.appendingPathComponent(name+".wav"),options:.atomic)}
            if let data=try? JSONSerialization.data(withJSONObject:["script":script,"transcript":transcript,"pcmBytes":pcm.count],options:[.prettyPrinted,.sortedKeys]){try? data.write(to:failed.appendingPathComponent(name+".json"),options:.atomic)}
        })
        let indices=CommandLine.arguments.contains("--all") ? Array(library.lessons.indices):[0]
        var completed=0
        for index in indices {
            try Task.checkCancellation()
            let source=LessonTranslation.source(library:library,index:index)
            guard let translation=BundledLessonText.translation(source:source,locale:"zh-Hans") else{
                throw CheckmateError.invalid("Bundled Chinese translation is missing.")
            }
            try store.saveTranslation(translation,source:source,locale:"zh-Hans")
            let beats=CommandLine.arguments.contains("--all") ? translation.beats:Array(translation.beats.prefix(1))
            for start in stride(from:0,to:beats.count,by:3) {
            try await withThrowingTaskGroup(of:Bool.self) {group in
            for beat in beats[start..<min(start+3,beats.count)] {
                if let pack=try store.partialPack(source:source,locale:"zh-Hans",voice:"cedar"),
                   pack.translation.beats.first(where:{$0.id==beat.id})?.speak==beat.speak,
                   try store.clipURL(pack:pack,beatID:beat.id) != nil {continue}
                group.addTask {
                    let operation=await usage.begin(activity:.lessonRecording,provider:"realtime",sessionID:UUID().uuidString,model:"gpt-realtime",locale:"zh-Hans",voice:"cedar",lessonID:source.lessonID)
                    do {
                        let result=try await recorder.record(script:beat.speak,locale:"zh-Hans",voice:"cedar",onUsage:{_,_ in})
                        _ = try store.saveClip(pcm:result.pcm,transcript:result.transcript,beatID:beat.id,source:source,locale:"zh-Hans",voice:"cedar",model:result.model)
                        await usage.record(operationID:operation,providerID:result.responseID,tokens:result.tokens,status:.completed,cumulative:true,durationSeconds:Double(result.pcm.count)/48000,model:result.model)
                        print("Saved: \(beat.id), \(result.pcm.count / 48000) seconds");fflush(stdout)
                        return true
                    } catch {
                        await usage.finish(operationID:operation,status:Task.isCancelled ? .cancelled:.failed)
                        print("Not saved: \(beat.id); validation or service failed. Resume explicitly.");fflush(stdout)
                        throw error
                    }
                }
            }
            for try await saved in group {if saved{completed+=1}}
            }
            }
        }
        try await usage.flush()
        print("Completed; validated clips are in \(directory.path).")
    }
}
