import Foundation

struct Track {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
}

@main
private enum LyricsMatcherScriptVariantHarness {
    static func main() {
        let track = Track(
            id: "spotify:track:reported-actor",
            title: "演员",
            artist: "薛之謙",
            album: "绅士",
            duration: 261
        )
        let candidates = [
            LyricsMatchCandidate(
                title: "演员",
                artist: "薛之谦",
                album: "绅士",
                duration: 261
            ),
        ]

        precondition(
            LyricsMatcher().bestMatch(for: track, among: candidates) != nil,
            "Traditional/simplified metadata variants must refer to the same song"
        )
        print("lyrics_matcher_script_variant=PASS")
    }
}
