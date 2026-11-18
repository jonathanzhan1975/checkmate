import XCTest
import Foundation
import CheckmateDomain
import CheckmateContent

private final class CoachHTTPStub:URLProtocol {
    static var handle:((URLRequest)throws->(Int,Data))?
    override class func canInit(with request:URLRequest)->Bool{true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest{request}
    override func startLoading(){do{let (code,data)=try Self.handle!(request);client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:code,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed);client?.urlProtocol(self,didLoad:data);client?.urlProtocolDidFinishLoading(self)}catch{client?.urlProtocol(self,didFailWithError:error)}}
    override func stopLoading(){}
}
final class DeepSeekChatTests:XCTestCase {
    private func client(key:String?="fixture-deepseek-key")->DeepSeekChatClient{let c=URLSessionConfiguration.ephemeral;c.protocolClasses=[CoachHTTPStub.self];return DeepSeekChatClient(session:URLSession(configuration:c),key:{key})}
    private let messages=Data("[{\"role\":\"user\",\"content\":\"马为什么不能走到 e4？\"}]".utf8)
    private let tools=Data("[{\"type\":\"function\",\"function\":{\"name\":\"inspect_piece\",\"parameters\":{\"type\":\"object\"}}}]".utf8)
    private func response(_ text:String="先检查马的合法走法。",calls:[[String:Any]]=[] ,finish:String?=nil)throws->Data {
        try JSONSerialization.data(withJSONObject:["id":"coach-fixture","model":"deepseek-served-model","usage":["prompt_tokens":100,"completion_tokens":25,"total_tokens":125,"prompt_cache_hit_tokens":20],"choices":[["finish_reason":finish ?? (calls.isEmpty ? "stop":"tool_calls"),"message":["role":"assistant","content":text,"tool_calls":calls]]]])
    }
    override func tearDown(){CoachHTTPStub.handle=nil;super.tearDown()}
    private func body(_ request:URLRequest)throws->Data {
        if let data=request.httpBody{return data}
        let stream=try XCTUnwrap(request.httpBodyStream);stream.open();defer{stream.close()}
        var data=Data(),buffer=[UInt8](repeating:0,count:4096)
        while true{let count=stream.read(&buffer,maxLength:buffer.count);if count==0{break};guard count>0 else{throw CocoaError(.fileReadUnknown)};data.append(contentsOf:buffer.prefix(count));guard data.count<200*1024 else{throw CocoaError(.fileReadTooLarge)}}
        return data
    }
    func testDefaultAndMigratedSettingsUseDeepSeek()throws {
        XCTAssertEqual(AppSettings().coachProvider,"deepseek");XCTAssertEqual(AppSettings(raw:[:]).coachProvider,"deepseek");XCTAssertEqual(AppSettings(raw:["coachProvider":"codex"]).coachProvider,"deepseek")
        let data=try JSONEncoder().encode(AppSettings());XCTAssertEqual(try JSONDecoder().decode(AppSettings.self,from:data).coachProvider,"deepseek");XCTAssertFalse(AppSettings().deepSeekConsent)
    }
    func testHTTPSRequestUsesDeepSeekAndReportsActualUsage()async throws {
        CoachHTTPStub.handle={request in
            XCTAssertEqual(request.url?.absoluteString,"https://api.deepseek.com/chat/completions");XCTAssertEqual(request.httpMethod,"POST");XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer fixture-deepseek-key")
            let requestBody=try self.body(request),body=try JSONSerialization.jsonObject(with:requestBody) as! [String:Any]
            XCTAssertEqual(body["model"] as? String,"deepseek-flash");XCTAssertEqual((body["thinking"] as? [String:String])?["type"],"disabled");XCTAssertEqual(body["stream"] as? Bool,false)
            XCTAssertFalse(String(decoding:requestBody,as:UTF8.self).lowercased().contains("codex"))
            return (200,try self.response())
        }
        let value=try await client().reply(messages:messages,tools:tools);XCTAssertEqual(value.model,"deepseek-served-model");XCTAssertEqual(value.tokens?.total,125);XCTAssertEqual(value.tokens?.cachedInput,20)
    }
    func testMissingKeyNeverContactsProvider()async {
        CoachHTTPStub.handle={_ in XCTFail("No request is allowed without credentials");return(200,Data())}
        do{_ = try await client(key:nil).reply(messages:messages,tools:tools);XCTFail()}catch{}
    }
    func testAuthenticationBalanceAndTemporaryErrorsDoNotRetryOrLeakBody()async {
        for code in [401,402,429,500,503] {
            var requests=0;CoachHTTPStub.handle={_ in requests+=1;return(code,Data("fixture-deepseek-key secret server body".utf8))}
            do{_ = try await client().reply(messages:messages,tools:tools);XCTFail()}catch{XCTAssertFalse(String(describing:error).contains("fixture-deepseek-key"))}
            XCTAssertEqual(requests,1)
        }
    }
    func testInvalidOrUnauthorizedToolsAreRejected()async throws {
        let cases:[[[String:Any]]]=[
            [["id":"x","type":"function","function":["name":"play_move","arguments":"{}"]]],
            [["id":"x","type":"function","function":["name":"inspect_piece","arguments":"[]"]]],
            [["id":"x","type":"function","function":["name":"inspect_piece","arguments":"{\"padding\":\""+String(repeating:"x",count:9000)+"\"}"]]],
            (0..<4).map{["id":"c\($0)","type":"function","function":["name":"inspect_piece","arguments":"{}"]]}
        ]
        for calls in cases{CoachHTTPStub.handle={_ in (200,try self.response(calls:calls))};do{_ = try await client().reply(messages:messages,tools:tools);XCTFail("Invalid tools accepted")}catch{}}
    }
    func testPartialAnswerIsNotPresentedAsCompleted()async {
        CoachHTTPStub.handle={_ in (200,try self.response(finish:"length"))}
        do{_ = try await client().reply(messages:messages,tools:tools);XCTFail()}catch{}
    }
}
