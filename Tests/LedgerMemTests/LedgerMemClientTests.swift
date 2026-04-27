import XCTest
@testable import LedgerMem

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StubTransport: HTTPTransport, @unchecked Sendable {
    var lastRequest: URLRequest?
    var responder: (URLRequest) -> (Data, HTTPURLResponse)

    init(responder: @escaping (URLRequest) -> (Data, HTTPURLResponse)) {
        self.responder = responder
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return responder(request)
    }
}

private func makeResponse(_ url: URL, status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
}

final class LedgerMemClientTests: XCTestCase {

    func testSearchSendsBearerAndWorkspaceHeaders() async throws {
        let payload = #"{"hits":[{"id":"m1","content":"hi","score":0.9,"metadata":null}]}"#
        let stub = StubTransport { req in
            (payload.data(using: .utf8)!, makeResponse(req.url!, status: 200))
        }
        let client = LedgerMemClient(
            apiKey: "test-key",
            workspaceId: "ws_123",
            baseURL: URL(string: "https://api.test")!,
            transport: stub
        )

        let response = try await client.search(query: "hello", limit: 3)

        XCTAssertEqual(response.hits.count, 1)
        XCTAssertEqual(response.hits[0].id, "m1")

        let req = try XCTUnwrap(stub.lastRequest)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-workspace-id"), "ws_123")
        XCTAssertEqual(req.url?.path, "/v1/search")

        let bodyString = String(data: req.httpBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("\"query\":\"hello\""))
        XCTAssertTrue(bodyString.contains("\"limit\":3"))
    }

    func testCreateReturnsMemory() async throws {
        let payload = #"{"id":"m_42","content":"remember","metadata":null,"createdAt":null}"#
        let stub = StubTransport { req in
            (payload.data(using: .utf8)!, makeResponse(req.url!, status: 200))
        }
        let client = LedgerMemClient(
            apiKey: "k", workspaceId: "w",
            baseURL: URL(string: "https://api.test")!,
            transport: stub
        )

        let memory = try await client.create(content: "remember")

        XCTAssertEqual(memory.id, "m_42")
        XCTAssertEqual(stub.lastRequest?.url?.path, "/v1/memories")
        XCTAssertEqual(stub.lastRequest?.httpMethod, "POST")
    }

    func testDeleteThrowsOnNon2xx() async {
        let stub = StubTransport { req in
            ("{\"error\":\"not found\"}".data(using: .utf8)!, makeResponse(req.url!, status: 404))
        }
        let client = LedgerMemClient(
            apiKey: "k", workspaceId: "w",
            baseURL: URL(string: "https://api.test")!,
            transport: stub
        )

        do {
            try await client.delete(id: "missing")
            XCTFail("expected throw")
        } catch let LedgerMemError.http(status, _) {
            XCTAssertEqual(status, 404)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
