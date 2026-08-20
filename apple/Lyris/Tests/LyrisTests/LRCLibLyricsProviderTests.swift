import Foundation
import XCTest
@testable import Lyris

final class LRCLibLyricsProviderTests: XCTestCase {
    override func tearDown() {
        LRCLibFixtureURLProtocol.response = nil
        super.tearDown()
    }

    func testSearchKeepsValidLyricsWhenAnotherCandidateHasNoDuration() async throws {
        LRCLibFixtureURLProtocol.response = { request in
            let path = try XCTUnwrap(request.url?.path)
            if path == "/api/get-cached" {
                return (404, Data(), [:])
            }
            XCTAssertEqual(path, "/api/search")
            let body = """
            [
              {
                "id": 101,
                "trackName": "Strategy (from the Netflix film KPop Demon Hunters)",
                "artistName": "TWICE",
                "albumName": "STRATEGY",
                "duration": 166.0,
                "plainLyrics": "Line one\\nLine two",
                "syncedLyrics": "[00:01.00] Line one\\n[00:03.00] Line two"
              },
              {
                "id": 102,
                "trackName": "Strategy (from the Netflix film KPop Demon Hunters)",
                "artistName": "TWICE",
                "albumName": "STRATEGY",
                "duration": null,
                "plainLyrics": "Other line",
                "syncedLyrics": "[00:01.00] Other line"
              }
            ]
            """
            return (200, Data(body.utf8), [:])
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LRCLibFixtureURLProtocol.self]
        let provider = LRCLibLyricsProvider(session: URLSession(configuration: configuration))
        let track = Track(
            id: "spotify:track:fixture",
            title: "Strategy (from the Netflix film KPop Demon Hunters)",
            artist: "TWICE",
            album: "STRATEGY",
            duration: 166.773
        )

        let result = try await provider.lyrics(for: track)

        XCTAssertEqual(result.sourceID, "lrclib:101")
        XCTAssertEqual(result.lyrics.map(\.original), ["Line one", "Line two"])
    }

    func testRateLimitPreservesRetryAfterForThePipeline() async throws {
        LRCLibFixtureURLProtocol.response = { _ in
            (429, Data(), ["Retry-After": "7"])
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LRCLibFixtureURLProtocol.self]
        let provider = LRCLibLyricsProvider(session: URLSession(configuration: configuration))

        do {
            _ = try await provider.lyrics(
                for: Track(
                    id: "spotify:track:fixture",
                    title: "Fixture",
                    artist: "Artist",
                    album: "Album",
                    duration: 180
                )
            )
            XCTFail("Expected LRCLIB to surface the rate limit")
        } catch {
            XCTAssertEqual(error as? LRCLibError, .rateLimited(retryAfter: 7))
        }
    }

    func testSearchRetriesTraditionalChineseMetadataWhenSimplifiedQueryIsEmpty() async throws {
        LRCLibFixtureURLProtocol.response = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/api/get-cached" {
                return (404, Data(), [:])
            }

            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let artist = components.queryItems?.first(where: { $0.name == "artist_name" })?.value
            guard artist == "孫燕姿" else {
                return (200, Data("[]".utf8), [:])
            }

            let body = """
            [
              {
                "id": 34003428,
                "trackName": "雨天",
                "artistName": "孫燕姿",
                "albumName": "My Story, Your Song 經典全記錄",
                "duration": 241.0,
                "plainLyrics": "第一行\\n第二行",
                "syncedLyrics": "[00:01.00] 第一行\\n[00:03.00] 第二行"
              }
            ]
            """
            return (200, Data(body.utf8), [:])
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LRCLibFixtureURLProtocol.self]
        let provider = LRCLibLyricsProvider(session: URLSession(configuration: configuration))
        let track = Track(
            id: "spotify:track:rainy-day",
            title: "雨天",
            artist: "孙燕姿",
            album: "My Story, Your Song 经典全记录",
            duration: 242
        )

        let result = try await provider.lyrics(for: track)

        XCTAssertEqual(result.sourceID, "lrclib:34003428")
        XCTAssertEqual(result.lyrics.map(\.original), ["第一行", "第二行"])
    }

    func testSearchFallsBackToTitleOnlyWhenProviderArtistMetadataDiffers() async throws {
        var titleOnlyRequestCount = 0
        LRCLibFixtureURLProtocol.response = { request in
            let url = try XCTUnwrap(request.url)
            if url.path == "/api/get-cached" {
                return (404, Data(), [:])
            }

            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let artist = components.queryItems?.first(where: { $0.name == "artist_name" })?.value
            guard artist == nil else {
                return (200, Data("[]".utf8), [:])
            }
            titleOnlyRequestCount += 1
            let body = """
            [
              {
                "id": 510,
                "trackName": "Rain Love",
                "artistName": "R.L.",
                "albumName": "Rain Love",
                "duration": 238.0,
                "plainLyrics": "First line\\nSecond line",
                "syncedLyrics": "[00:01.00] First line\\n[00:03.00] Second line"
              }
            ]
            """
            return (200, Data(body.utf8), [:])
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LRCLibFixtureURLProtocol.self]
        let provider = LRCLibLyricsProvider(
            session: URLSession(configuration: configuration),
            matcher: LyricsMatcher(minimumConfidence: 0.70)
        )
        let track = Track(
            id: "spotify:track:rain-love",
            title: "Rain Love",
            artist: "R.L.",
            album: "Rain Love",
            duration: 238
        )

        let result = try await provider.lyrics(for: track)

        XCTAssertEqual(titleOnlyRequestCount, 1)
        XCTAssertEqual(result.sourceID, "lrclib:510")
    }
}

private final class LRCLibFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    static var response: ((URLRequest) throws -> (
        status: Int,
        body: Data,
        headers: [String: String]
    ))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let responseBuilder = try XCTUnwrap(Self.response)
            let fixture = try responseBuilder(request)
            let response = try XCTUnwrap(
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: fixture.status,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                        .merging(fixture.headers) { _, new in new }
                )
            )
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: fixture.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
