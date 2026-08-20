import Foundation
import NaturalLanguage

enum LyricsTranslationDecision {
    static func sourceAlreadyMatchesTarget(
        lines: [String],
        target: TranslationTargetLanguage
    ) -> Bool {
        let text = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard text.unicodeScalars.filter(CharacterSet.letters.contains).count >= 4 else {
            return false
        }

        if target == .simplifiedChinese,
           let simplified = text.applyingTransform(
               StringTransform("Traditional-Simplified"),
               reverse: false
           ),
           simplified != text {
            return false
        }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let expected = target.recognizedLanguage
        let confidence = recognizer
            .languageHypotheses(withMaximum: 8)[expected] ?? 0
        if confidence >= 0.82 {
            return true
        }

        let scripts = ScriptProfile(text)
        switch target {
        case .simplifiedChinese:
            return scripts.han >= 4
                && scripts.hiraganaKatakana == 0
                && scripts.hangul == 0
                && scripts.latin <= max(2, scripts.han / 4)
        case .japanese:
            return scripts.hiraganaKatakana >= 3
                && scripts.hangul == 0
                && scripts.latin <= max(2, (scripts.han + scripts.hiraganaKatakana) / 4)
        case .korean:
            return scripts.hangul >= 4
                && scripts.hiraganaKatakana == 0
                && scripts.latin <= max(2, scripts.hangul / 4)
        case .english, .spanish, .french, .german:
            return false
        }
    }

    static func passthrough(_ lyrics: [TimedLyric]) -> [TimedLyric] {
        lyrics.map { lyric in
            let existingTranslation = lyric.translation
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return TimedLyric(
                id: lyric.id,
                startTime: lyric.startTime,
                original: lyric.original,
                translation: existingTranslation.isEmpty
                    ? lyric.original
                    : lyric.translation,
                isEstimated: lyric.isEstimated
            )
        }
    }

    static func fillingSameLanguageTranslation(
        in lyrics: [TimedLyric],
        target: TranslationTargetLanguage
    ) -> [TimedLyric] {
        guard sourceAlreadyMatchesTarget(
            lines: lyrics.map(\.original),
            target: target
        ) else {
            return lyrics
        }
        return passthrough(lyrics)
    }
}

private extension TranslationTargetLanguage {
    var recognizedLanguage: NLLanguage {
        switch self {
        case .simplifiedChinese: NLLanguage(rawValue: "zh-Hans")
        case .english: NLLanguage(rawValue: "en")
        case .japanese: NLLanguage(rawValue: "ja")
        case .korean: NLLanguage(rawValue: "ko")
        case .spanish: NLLanguage(rawValue: "es")
        case .french: NLLanguage(rawValue: "fr")
        case .german: NLLanguage(rawValue: "de")
        }
    }
}

private struct ScriptProfile {
    var han = 0
    var hiraganaKatakana = 0
    var hangul = 0
    var latin = 0

    init(_ text: String) {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                han += 1
            case 0x3040...0x30FF:
                hiraganaKatakana += 1
            case 0xAC00...0xD7AF:
                hangul += 1
            case 0x0041...0x005A, 0x0061...0x007A:
                latin += 1
            default:
                break
            }
        }
    }
}
