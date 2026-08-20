import Foundation

private final class PlaybackURLProtocol: URLProtocol, @unchecked Sendable {
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        let body: Data
        if request.url?.host == "accounts.spotify.com" {
            body = Data(#"{"access_token":"test-token","expires_in":3600}"#.utf8)
        } else if request.httpMethod == "GET" {
            body = Data("[true]".utf8)
        } else {
            body = Data()
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct PlaybackVault: CredentialVault {
    func read(account: String) throws -> String? { "refresh-token" }
    func write(_ secret: String, account: String) throws {}
    func delete(account: String) throws {}
}

@main
private enum SpotifyPlaybackHarness {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackURLProtocol.self]
        let broker = SpotifySessionBroker(
            credentialVault: PlaybackVault(),
            session: URLSession(configuration: configuration)
        )
        let snapshot = PlaybackSnapshot(
            track: Track(id: "spotify:track:abc", title: "Track", artist: "Artist", album: "Album", duration: 180),
            position: 30,
            isPlaying: true,
            isLiked: true,
            isShuffled: false,
            repeatMode: .off
        )
        let account = SpotifyPlaybackAccount(
            profile: SpotifyAuthorizationProfile(
                displayName: "Fixture",
                clientID: "client",
                redirectURI: "http://127.0.0.1:43821/oauth/callback",
                grantedScopes: SpotifyAuthorizationScopes.accountEnhancement
            )
        )

        let saved = try await broker.isTrackSaved(snapshot.track.id, account: account)
        precondition(saved)
        try await broker.send(.seek(42.25), snapshot: snapshot, account: account)
        try await broker.send(.toggleLiked, snapshot: snapshot, account: account)
        try await broker.send(.setVolume(0.42), snapshot: snapshot, account: account)

        let apiRequests = PlaybackURLProtocol.requests.filter { $0.url?.host == "api.spotify.com" }
        precondition(apiRequests.count == 4)
        precondition(apiRequests[0].url?.path == "/v1/me/library/contains")
        precondition(URLComponents(url: apiRequests[0].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "spotify:track:abc")
        precondition(apiRequests[1].url?.path == "/v1/me/player/seek")
        precondition(URLComponents(url: apiRequests[1].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "42250")
        precondition(apiRequests[2].httpMethod == "DELETE")
        precondition(apiRequests[2].url?.path == "/v1/me/library")
        precondition(apiRequests[3].url?.path == "/v1/me/player/volume")
        precondition(URLComponents(url: apiRequests[3].url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "42")
        print("spotify_library=PASS spotify_seek=PASS spotify_volume=PASS")
    }
}
