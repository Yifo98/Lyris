import Foundation

@main
private enum LyricsLanguageDetectionHarness {
    static func main() {
        precondition(
            LyricsTranslationDecision.sourceAlreadyMatchesTarget(
                lines: ["你好，打个招呼", "我们就这样向前走"],
                target: .simplifiedChinese
            )
        )
        precondition(
            !LyricsTranslationDecision.sourceAlreadyMatchesTarget(
                lines: ["你好，打个招呼", "我们就这样向前走"],
                target: .english
            )
        )
        precondition(
            LyricsTranslationDecision.sourceAlreadyMatchesTarget(
                lines: ["I know exactly where this road will go", "Say hello again"],
                target: .english
            )
        )
        precondition(
            !LyricsTranslationDecision.sourceAlreadyMatchesTarget(
                lines: ["우린 계속 달려가", "say hello"],
                target: .simplifiedChinese
            )
        )
        precondition(
            !LyricsTranslationDecision.sourceAlreadyMatchesTarget(
                lines: ["你好，say hello", "我们 keep moving"],
                target: .simplifiedChinese
            )
        )
        precondition(
            !LyricsTranslationDecision.sourceAlreadyMatchesTarget(
                lines: ["後來我們終於學會了如何去愛", "回憶裡的你依然溫柔"],
                target: .simplifiedChinese
            )
        )
        let original = [
            TimedLyric(startTime: 1, original: "你好，打个招呼", translation: "")
        ]
        precondition(
            LyricsTranslationDecision.passthrough(original).first?.translation
                == "你好，打个招呼"
        )
        let cachedSameLanguage = [
            TimedLyric(startTime: 1, original: "爱一天，抵过永远", translation: ""),
            TimedLyric(startTime: 5, original: "下一句", translation: "人工校对"),
        ]
        let normalized = LyricsTranslationDecision.fillingSameLanguageTranslation(
            in: cachedSameLanguage,
            target: .simplifiedChinese
        )
        precondition(normalized[0].translation == "爱一天，抵过永远")
        precondition(normalized[1].translation == "人工校对")

        print("same_language_skip=PASS mixed_language_translate=PASS passthrough=PASS cached_same_language_fill=PASS manual_translation_preserved=PASS")
    }
}
