import Foundation
import XCTest
@testable import Lyris

final class TranslationModelSelectionTests: XCTestCase {
    override func tearDown() {
        TranslationModelFixtureURLProtocol.models = []
        TranslationModelFixtureURLProtocol.probedModels = []
        super.tearDown()
    }

    func testConnectionProbePreservesTheSelectedAvailableModel() async throws {
        let cases: [(TranslationProvider, String, [String])] = [
            (.deepSeek, "deepseek-v4-pro", ["deepseek-flash", "deepseek-v4-pro"]),
            (.deepSeek, "deepseek-v4-flash", ["deepseek-flash", "deepseek-v4-flash", "deepseek-v4-pro"]),
            (.openAI, "gpt-4.1-mini", ["gpt-5-mini", "gpt-4.1-mini"]),
            (.custom, "chosen-model", ["another-model", "chosen-model"]),
        ]
        for (provider, selected, models) in cases {
            let report = try await probe(provider: provider, selected: selected, models: models)
            XCTAssertEqual(report.suggestedModel, selected)
            XCTAssertEqual(TranslationModelFixtureURLProtocol.probedModels, [selected])
        }
    }

    func testDiscoveryPrefersCurrentFlashAndRetainsLegacyFallback() async throws {
        let cases: [(String, [String], String)] = [
            ("unavailable-model", ["deepseek-flash", "deepseek-v4-pro"], "deepseek-flash"),
            ("", ["deepseek-v4-flash", "deepseek-v4-pro"], "deepseek-v4-flash"),
        ]
        for (selected, models, expected) in cases {
            let report = try await probe(provider: .deepSeek, selected: selected, models: models)
            XCTAssertEqual(report.suggestedModel, expected)
            XCTAssertEqual(TranslationModelFixtureURLProtocol.probedModels, [expected])
        }
    }

    private func probe(
        provider: TranslationProvider,
        selected: String,
        models: [String]
    ) async throws -> TranslationConnectionReport {
        TranslationModelFixtureURLProtocol.models = models
        TranslationModelFixtureURLProtocol.probedModels = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TranslationModelFixtureURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        return try await HTTPTranslationAdapter(session: session).testConnection(
            configuration: TranslationConfiguration(
                provider: provider,
                baseURL: "https://translation.example",
                model: selected,
                thinkingEnabled: false
            ),
            apiKey: "fixture-key"
        )
    }
}

private final class TranslationModelFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    static var models: [String] = []
    static var probedModels: [String] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let object: [String: Any]
            if url.path == "/models" {
                object = ["data": Self.models.map { ["id": $0] }]
            } else {
                XCTAssertEqual(url.path, "/chat/completions")
                var data = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 1_024)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        data.append(contentsOf: buffer.prefix(count))
                    }
                }
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                Self.probedModels.append(try XCTUnwrap(body["model"] as? String))
                object = ["choices": [["message": ["content": "OK"]]]]
            }
            let response = try XCTUnwrap(HTTPURLResponse(
                url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: object))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
