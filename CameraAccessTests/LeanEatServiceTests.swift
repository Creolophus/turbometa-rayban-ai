import XCTest
@testable import CameraAccess

private final class LeanEatHTTPStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor
final class LeanEatServiceTests: XCTestCase {
    private func service() -> LeanEatService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LeanEatHTTPStub.self]
        return LeanEatService(configuration: LeanEatConfiguration(baseURL: "https://example.invalid/v1",
            model: "test-vision", headers: ["Authorization": "Bearer test-only", "Content-Type": "application/json"],
            language: "English"), session: URLSession(configuration: configuration))
    }

    override func tearDown() { LeanEatHTTPStub.handler = nil }

    func testUsesConfigurationSnapshotAndDecodesResponse() async throws {
        let fixture = LeanEatTests.response
        LeanEatHTTPStub.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://example.invalid/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.timeoutInterval, 60)
            return (200, try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": fixture]]]]))
        }
        let result = try await service().analyzeFood(Data([1]))
        XCTAssertEqual(result.foods.first?.name, "鸡胸肉")
    }

    func testErrorDoesNotExposeProviderPayload() async throws {
        LeanEatHTTPStub.handler = { _ in (401, Data("private provider payload".utf8)) }
        do { _ = try await service().analyzeFood(Data([1])); XCTFail("Expected HTTP failure") }
        catch {
            XCTAssertFalse(error.localizedDescription.contains("private provider payload"))
            guard case LeanEatError.http(401) = error else { return XCTFail("Wrong error") }
        }
    }

    func testTransportTimeoutPropagates() async throws {
        LeanEatHTTPStub.handler = { _ in throw URLError(.timedOut) }
        do { _ = try await service().analyzeFood(Data([1])); XCTFail("Expected timeout") }
        catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
    }

    func testCancelledRequestDoesNotStartTransport() async throws {
        LeanEatHTTPStub.handler = { _ in XCTFail("Cancelled request reached transport"); throw URLError(.cancelled) }
        let service = service()
        let task = Task { try await service.analyzeFood(Data([1])) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError || (error as? URLError)?.code == .cancelled) }
    }
}
