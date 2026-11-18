import Foundation
import CheckmateAssets
import CheckmateDomain
import CheckmateSupport

public struct DeepSeekToolCall:Sendable {
    public let id:String,name:String,arguments:String
    public init(id:String,name:String,arguments:String){self.id=id;self.name=name;self.arguments=arguments}
}
public struct DeepSeekChatReply:Sendable {
    public let id:String,model:String,text:String,calls:[DeepSeekToolCall],tokens:UsageTokens?
    public init(id:String,model:String,text:String,calls:[DeepSeekToolCall]=[],tokens:UsageTokens?=nil){self.id=id;self.model=model;self.text=text;self.calls=calls;self.tokens=tokens}
}
public protocol DeepSeekChatProviding:Sendable {
    func reply(messages:Data,tools:Data) async throws -> DeepSeekChatReply
}
/// HTTPS-only reasoning provider. There is deliberately no model/provider fallback.
public struct DeepSeekChatClient:DeepSeekChatProviding {
    public static let model="deepseek-flash",maximumResponseBytes=256*1024,maximumArgumentBytes=8192
    private let session:URLSession,key:@Sendable ()->String?,fixture:Bool
    public init(session:URLSession?=nil,key:@escaping @Sendable ()->String?={ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? ProcessInfo.processInfo.environment["Deep_Seek_API_Key"]}){
        let configuration=URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest=40;configuration.timeoutIntervalForResource=50
        self.session=session ?? URLSession(configuration:configuration);self.key=key;fixture=session != nil
    }
    private func credential()throws->String {
        guard let key=key()?.trimmingCharacters(in:.whitespacesAndNewlines),!key.isEmpty else{throw CheckmateError.unavailable(String(localized:"Configure DEEPSEEK_API_KEY before asking the coach.",bundle:.checkmate))}
        return key
    }
    public func checkCredential()throws{_ = try credential()}
    public func reply(messages:Data,tools:Data)async throws->DeepSeekChatReply {
        try Task.checkCancellation();let token=try credential()
        guard !NativePolicy.silent || fixture else{throw CheckmateError.unavailable(String(localized:"Live DeepSeek coaching is disabled during automation.",bundle:.checkmate))}
        guard messages.count<=160*1024,tools.count<=32*1024,
              let conversation=try JSONSerialization.jsonObject(with:messages) as? [[String:Any]],!conversation.isEmpty,conversation.count<=32,
              let functions=try JSONSerialization.jsonObject(with:tools) as? [[String:Any]] else{throw CheckmateError.invalid(String(localized:"DeepSeek returned an incomplete answer. Ask again.",bundle:.checkmate))}
        var request=URLRequest(url:URL(string:"https://api.deepseek.com/chat/completions")!)
        request.httpMethod="POST";request.setValue("Bearer "+token,forHTTPHeaderField:"Authorization") // not localized: HTTP authorization scheme, never shown in the interface
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var payload:[String:Any]=["model":Self.model,"messages":conversation,"stream":false,"thinking":["type":"disabled"],"max_tokens":2048]
        if !functions.isEmpty{payload["tools"]=functions;payload["tool_choice"]="auto"}
        request.httpBody=try JSONSerialization.data(withJSONObject:payload)
        let data:Data,response:URLResponse
        do{(data,response)=try await session.data(for:request)}catch{
            if Task.isCancelled || error is CancellationError{throw CancellationError()}
            throw CheckmateError.unavailable(String(localized:"DeepSeek could not be reached. Check the connection and try again.",bundle:.checkmate))
        }
        try Task.checkCancellation()
        guard let http=response as? HTTPURLResponse else{throw CheckmateError.invalid(String(localized:"DeepSeek returned an incomplete answer. Ask again.",bundle:.checkmate))}
        // No automatic retry: a timed-out generation might already have been billed.
        switch http.statusCode {
        case 200:break
        case 401:throw CheckmateError.unavailable(String(localized:"The DeepSeek key is invalid. Check its configuration.",bundle:.checkmate))
        case 402:throw CheckmateError.unavailable(String(localized:"The DeepSeek balance is insufficient. Top up before asking again.",bundle:.checkmate))
        case 429:throw CheckmateError.unavailable(String(localized:"DeepSeek is busy. Wait a moment, then ask again.",bundle:.checkmate))
        default:throw CheckmateError.unavailable(String(localized:"DeepSeek could not answer this time. Try again later.",bundle:.checkmate))
        }
        guard data.count<=Self.maximumResponseBytes,
              let object=try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let id=object["id"] as? String,!id.isEmpty,id.utf8.count<=256,
              let model=object["model"] as? String,!model.isEmpty,model.utf8.count<=128,
              let choices=object["choices"] as? [[String:Any]],choices.count==1,
              let message=choices[0]["message"] as? [String:Any],message["role"] as? String=="assistant",
              let finish=choices[0]["finish_reason"] as? String,["stop","tool_calls"].contains(finish)
        else{throw CheckmateError.invalid(String(localized:"DeepSeek returned an incomplete answer. Ask again.",bundle:.checkmate))}
        let text=message["content"] as? String ?? ""
        guard text.count<=8000 else{throw CheckmateError.invalid(String(localized:"DeepSeek returned an incomplete answer. Ask again.",bundle:.checkmate))}
        let raw=message["tool_calls"] as? [[String:Any]] ?? []
        guard raw.count<=3 else{throw CheckmateError.invalid(String(localized:"DeepSeek returned an incomplete answer. Ask again.",bundle:.checkmate))}
        var ids=Set<String>();let allowed=Set(functions.compactMap{($0["function"] as? [String:Any])?["name"] as? String})
        let calls=try raw.map{call -> DeepSeekToolCall in
            guard call["type"] as? String=="function",let cid=call["id"] as? String,!cid.isEmpty,cid.utf8.count<=256,ids.insert(cid).inserted,
                  let function=call["function"] as? [String:Any],let name=function["name"] as? String,allowed.contains(name),
                  let arguments=function["arguments"] as? String,arguments.utf8.count<=Self.maximumArgumentBytes,
                  (try? JSONSerialization.jsonObject(with:Data(arguments.utf8))) is [String:Any]
            else{throw CheckmateError.invalid(String(localized:"DeepSeek requested an invalid chess tool.",bundle:.checkmate))}
            return DeepSeekToolCall(id:cid,name:name,arguments:arguments)
        }
        guard (!calls.isEmpty && finish=="tool_calls") || (calls.isEmpty && finish=="stop" && !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) else{throw CheckmateError.invalid(String(localized:"DeepSeek returned an incomplete answer. Ask again.",bundle:.checkmate))}
        let usage=object["usage"] as? [String:Any]
        let tokens=usage.map{UsageTokens.parseCodex(["inputTokens":$0["prompt_tokens"] as Any,"outputTokens":$0["completion_tokens"] as Any,"totalTokens":$0["total_tokens"] as Any,"cachedInputTokens":$0["prompt_cache_hit_tokens"] as Any])} ?? nil
        return DeepSeekChatReply(id:id,model:model,text:text,calls:calls,tokens:tokens)
    }
}
