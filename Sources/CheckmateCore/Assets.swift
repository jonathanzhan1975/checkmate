import Foundation
import CryptoKit
public enum NativeResources {
    public static var root: URL { {
        let bundle = Bundle.main.resourceURL.flatMap {
            Bundle(url: $0.appendingPathComponent("Checkmate_CheckmateAssets.bundle"))
        } ?? Bundle.module
        let resources = bundle.resourceURL!
        let nested = resources.appendingPathComponent("Resources")
        return FileManager.default.fileExists(atPath: nested.appendingPathComponent("chess.js").path) ? nested : resources
    }() }
    public static func url(_ path:String) -> URL {root.appendingPathComponent(path)}
}
/// Presentation-only overlays. Source content, answer IDs, mechanics and saved progress stay unchanged.
public enum ChineseContent {
    private struct Catalog: Decodable { let version:Int,locale:String,sourceHashes:[String:String],translations:[String:String] }
    private static let translations:[String:String] = {
        guard let data=try? Data(contentsOf:NativeResources.url("content.zh-Hans.json")),
              let catalog=try? JSONDecoder().decode(Catalog.self,from:data),
              catalog.version==1,catalog.locale=="zh-Hans" else{return [:]}
        for path in ["course.json","training/catalog.json","training/scenarios.json"] {
            guard let source=try? Data(contentsOf:NativeResources.url(path)),
                  catalog.sourceHashes[path]==SHA256.hash(data:source).map({String(format:"%02x",$0)}).joined() else{return [:]}
        }
        return catalog.translations
    }()
    private static let phrases = translations.keys.filter{$0.count>=25}.sorted{$0.count==$1.count ? $0<$1:$0.count>$1.count}
    public static func text(_ source:String,locale:String?=nil)->String {
        let language=locale ?? Bundle.checkmate.preferredLocalizations.first ?? "en"
        guard language.hasPrefix("zh") else{return source}
        if let translated=translations[source]{return translated}
        // Feedback can combine a localized status with an authored explanation or hint.
        var result=source
        for phrase in phrases where result.contains(phrase){result=result.replacingOccurrences(of:phrase,with:translations[phrase]!)}
        return result
    }
}
public extension Bundle {
    /// The one String Catalog (Localizable.xcstrings) the whole app localizes through: `String(localized:…,bundle:.checkmate)`.
    /// The packaged copy inside the app when there is one, else SwiftPM's (tests and command-line tools). build.sh also
    /// copies its localizations into the app itself, where SwiftUI's `Text("…")` and AppKit look by default.
    static let checkmate:Bundle = {Bundle.main.resourceURL.flatMap{Bundle(url:$0.appendingPathComponent("Checkmate_CheckmateAssets.bundle"))} ?? .module}()
}
/// Localized interpolation formats a number with `%lf`, so 1.5 shows as "1.500000". Shown numbers are formatted into
/// text first, so their digits are chosen on purpose; with warnings as errors these overloads stop the build.
public extension String.LocalizationValue.StringInterpolation {
    @available(*,deprecated,message:"Format the number into text first: localized interpolation shows 1.5 as 1.500000")
    mutating func appendInterpolation(_ value:Double) {appendInterpolation(String(describing:value))}
    @available(*,deprecated,message:"Format the number into text first: localized interpolation shows 1.5 as 1.500000")
    mutating func appendInterpolation(_ value:Float) {appendInterpolation(String(describing:value))}
}
