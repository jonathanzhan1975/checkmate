import Foundation
public enum ApplicationDataPaths {
    public static func dataDirectoryIdentifier(bundleIdentifier:String?)->String {
        // The phase-two preview must never migrate or save over the learner's
        // accepted 0.20 development installation.
        if bundleIdentifier == "ai.xiaolai.checkmate.deepseek-development"{return "ai.xiaolai.checkmate.deepseek-development"}
        return bundleIdentifier == "ai.xiaolai.checkmate" ? "ai.xiaolai.checkmate" : "ai.xiaolai.checkmate.native-development"
    }
    public static func defaultDirectory()->URL {
        if let path=ProcessInfo.processInfo.environment["CHECKMATE_DATA_DIR"] {return URL(fileURLWithPath:path)}
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent(dataDirectoryIdentifier(bundleIdentifier:Bundle.main.bundleIdentifier))
    }
}
