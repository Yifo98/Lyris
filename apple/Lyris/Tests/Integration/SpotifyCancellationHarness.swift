import Foundation

@main
struct SpotifyCancellationHarness {
    static func main() async throws {
        let port: UInt16 = 48_123
        let firstServer = try SpotifyLoopbackServer(port: port)
        try await firstServer.start()

        let waitTask = Task {
            try await withTaskCancellationHandler {
                try await firstServer.waitForCallback(timeout: 30)
            } onCancel: {
                firstServer.cancel()
            }
        }
        waitTask.cancel()
        do {
            _ = try await waitTask.value
            fatalError("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation must resume the callback continuation.
        }
        try await Task.sleep(nanoseconds: 250_000_000)

        // Proves the listener was torn down instead of holding the port for 180 s.
        let reboundServer = try SpotifyLoopbackServer(port: port)
        try await reboundServer.start()
        reboundServer.cancel()

        let callbackPort: UInt16 = 48_124
        let callbackServer = try SpotifyLoopbackServer(
            port: callbackPort,
            expectedPath: "/oauth/spotify-return"
        )
        try await callbackServer.start()
        let callbackTask = Task {
            try await callbackServer.waitForCallback(timeout: 5)
        }
        let (_, wrongResponse) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(callbackPort)/oauth/callback?code=wrong")!
        )
        precondition((wrongResponse as? HTTPURLResponse)?.statusCode == 404)
        let (_, successResponse) = try await URLSession.shared.data(
            from: URL(string: "http://127.0.0.1:\(callbackPort)/oauth/spotify-return?code=fixture&state=expected")!
        )
        precondition((successResponse as? HTTPURLResponse)?.statusCode == 200)
        let callbackURL = try await callbackTask.value
        precondition(callbackURL.port == Int(callbackPort))
        precondition(callbackURL.path == "/oauth/spotify-return")
        precondition(callbackURL.query == "code=fixture&state=expected")

        print("spotify_cancellation=PASS port_rebound=PASS callback_port=PASS expected_path=PASS")
    }
}
