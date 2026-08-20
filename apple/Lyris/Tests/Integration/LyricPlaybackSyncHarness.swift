import Foundation

@main
private enum LyricPlaybackSyncHarness {
    static func main() {
        let lyrics = [
            TimedLyric(
                startTime: 77.34,
                original: "就算你有一道墙",
                translation: "就算你有一道墙"
            ),
            TimedLyric(
                startTime: 81.24,
                original: "我的爱会攀上窗台盛放",
                translation: "我的爱会攀上窗台盛放"
            ),
            TimedLyric(
                startTime: 85.29,
                original: "打开窗你会看到悲伤融化",
                translation: "打开窗你会看到悲伤融化"
            ),
        ]
        let spotifyPosition = 81.85
        let activeIndex = LyrisLyricLineProgress.activeIndex(
            position: spotifyPosition,
            timingDelay: 0,
            lyrics: lyrics
        )

        precondition(activeIndex == 1)
        precondition(lyrics[activeIndex!].original == "我的爱会攀上窗台盛放")
        precondition(
            !LyrisCompactLyricContextPolicy.shouldShowNextLine(
                showsAdjacentLyrics: false
            ),
            "A compact same-language card must not present the next lyric before Spotify reaches it"
        )
        precondition(
            LyrisCompactLyricContextPolicy.shouldShowNextLine(
                showsAdjacentLyrics: true
            ),
            "A taller card should retain its clearly separated next-line context"
        )

        print("line_selection=PASS compact_same_language_sync=PASS")
    }
}
