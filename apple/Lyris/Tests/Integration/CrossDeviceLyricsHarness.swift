import Foundation

@MainActor
private final class PlaybackFixture: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?

    func start() {}
    func send(_ command: PlaybackCommand) {}

    func publish(_ snapshot: PlaybackSnapshot) {
        onSnapshot?(snapshot)
    }
}

@main
private enum CrossDeviceLyricsHarness {
    @MainActor
    static func main() {
        let track = Track(
            id: "spotify:track:cross-device",
            title: "Cross Device Song",
            artist: "Fixture Artist",
            album: "Fixture Album",
            duration: 201,
            kind: .track
        )
        let idle = PlaybackSnapshot(
            track: Track(
                id: "spotify:idle",
                title: "Spotify is not playing",
                artist: "Local Companion",
                album: "",
                duration: 1,
                kind: .unknown
            ),
            position: 0,
            isPlaying: false,
            likedState: .unavailable,
            isShuffled: false,
            repeatMode: .off,
            capabilities: [],
            source: .unavailable
        )
        let local = PlaybackSnapshot(
            track: track,
            position: 28,
            isPlaying: true,
            likedState: .unavailable,
            isShuffled: false,
            repeatMode: .off,
            capabilities: .localCompanion,
            source: .local
        )
        var remote = local
        remote.position = 31
        remote.source = .web
        remote.capabilities = .accountPlayback
        remote.likedState = .value(true)

        let localFixture = PlaybackFixture()
        let webFixture = PlaybackFixture()
        let hybrid = HybridPlaybackAdapter(local: localFixture, web: webFixture)
        var received: [PlaybackSnapshot] = []
        hybrid.onSnapshot = { received.append($0) }
        hybrid.start()

        localFixture.publish(idle)
        webFixture.publish(remote)
        precondition(received.last?.track.id == track.id)
        precondition(received.last?.source == .web)
        precondition(received.last?.track.title == track.title)

        precondition(
            LyrisLyricsReloadPolicy.shouldReload(
                previous: local,
                next: remote,
                currentlyHasLyrics: false
            )
        )
        precondition(
            !LyrisLyricsReloadPolicy.shouldReload(
                previous: local,
                next: remote,
                currentlyHasLyrics: true
            )
        )
        var remoteProgressUpdate = remote
        remoteProgressUpdate.position = 32
        precondition(
            !LyrisLyricsReloadPolicy.shouldReload(
                previous: remote,
                next: remoteProgressUpdate,
                currentlyHasLyrics: false
            )
        )

        print("cross_device_snapshot=PASS same_track_lyrics_retry=PASS")
    }
}
