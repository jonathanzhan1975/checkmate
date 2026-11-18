import Foundation
import XCTest
@testable import CheckmateContent
import CheckmateDomain

private final class DeepSeekResponseStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class DeepSeekTranslationTests: XCTestCase {
    private func translator(key: String? = "fixture-key") -> DeepSeekLessonTranslator {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DeepSeekResponseStub.self]
        return DeepSeekLessonTranslator(session: URLSession(configuration: configuration), key: { key })
    }
    override func tearDown() { DeepSeekResponseStub.handler = nil; super.tearDown() }
    private func payload(_ text: LessonTranslation) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": "fixture-response", "model": "deepseek-flash",
            "usage": ["prompt_tokens": 11, "completion_tokens": 22, "total_tokens": 33],
            "choices": [["finish_reason": "stop", "message": ["content": String(decoding: try JSONEncoder().encode(text), as: UTF8.self)]]]
        ])
    }
    func testMissingCredentialDoesNotContactService() async throws {
        DeepSeekResponseStub.handler = { _ in XCTFail("Missing key must not send a request"); return (200, Data()) }
        do { _ = try await translator(key: nil).accountStatus(); XCTFail("Missing key accepted") } catch {}
    }
    func testValidatedTranslationAndActualUsage() async throws {
        let source = LessonTranslation.source(library: try CourseLibrary(), index: 0)
        var text = source; text.title = "中文课程"
        let data = try payload(text)
        DeepSeekResponseStub.handler = { request in
            XCTAssertEqual(request.url?.host, "api.deepseek.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            return (200, data)
        }
        let provider = translator()
        let result = try await provider.translate(source: source, locale: "zh-Hans", onUsage: { _, _, _ in })
        XCTAssertEqual(provider.providerID, "deepseek")
        XCTAssertEqual(result.text, text)
        XCTAssertEqual(result.tokens?.total, 33)
        XCTAssertEqual(result.model, "deepseek-flash")
    }
    func testAuthAndBalanceFailuresNeverRetryOrRevealServerBody() async throws {
        let source = LessonTranslation.source(library: try CourseLibrary(), index: 0)
        for status in [401, 402] {
            var calls = 0
            DeepSeekResponseStub.handler = { _ in calls += 1; return (status, Data("fixture-secret".utf8)) }
            do { _ = try await translator().translate(source: source, locale: "zh-Hans", onUsage: { _, _, _ in }); XCTFail("Refusal accepted") }
            catch { XCTAssertFalse(String(describing: error).contains("fixture-secret")) }
            XCTAssertEqual(calls, 1)
        }
    }
    func testChangedCoordinatesAreRejectedBeforeSaving() async throws {
        var source = LessonTranslation.source(library: try CourseLibrary(), index: 0)
        source.beats[0].say += " e4"
        var changed = source
        changed.beats[0].say = changed.beats[0].say.replacingOccurrences(of: "e4", with: "d4")
        let data = try payload(changed)
        DeepSeekResponseStub.handler = { _ in (200, data) }
        do { _ = try await translator().translate(source: source, locale: "zh-Hans", onUsage: { _, _, _ in }); XCTFail("Changed coordinate accepted") } catch {}
    }
}
