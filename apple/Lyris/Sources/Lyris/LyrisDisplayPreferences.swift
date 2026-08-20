import Foundation
import SwiftUI

struct SensitiveFieldVisibility: Equatable {
    private(set) var isRevealed = false

    mutating func toggle() {
        isRevealed.toggle()
    }

    mutating func conceal() {
        isRevealed = false
    }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: Self { self }
    var locale: Locale { Locale(identifier: rawValue) }

    func pick(zh: String, en: String) -> String {
        self == .simplifiedChinese ? zh : en
    }

    var displayName: String {
        pick(zh: "简体中文", en: "English")
    }
}

enum TranslationTargetLanguage: String, Codable, CaseIterable, Identifiable {
    case simplifiedChinese
    case english
    case japanese
    case korean
    case spanish
    case french
    case german

    var id: Self { self }

    var apiName: String {
        switch self {
        case .simplifiedChinese: "Simplified Chinese"
        case .english: "English"
        case .japanese: "Japanese"
        case .korean: "Korean"
        case .spanish: "Spanish"
        case .french: "French"
        case .german: "German"
        }
    }

    var deepLCode: String {
        switch self {
        case .simplifiedChinese: "ZH"
        case .english: "EN"
        case .japanese: "JA"
        case .korean: "KO"
        case .spanish: "ES"
        case .french: "FR"
        case .german: "DE"
        }
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .simplifiedChinese: language.pick(zh: "简体中文", en: "Simplified Chinese")
        case .english: language.pick(zh: "英语", en: "English")
        case .japanese: language.pick(zh: "日语", en: "Japanese")
        case .korean: language.pick(zh: "韩语", en: "Korean")
        case .spanish: language.pick(zh: "西班牙语", en: "Spanish")
        case .french: language.pick(zh: "法语", en: "French")
        case .german: language.pick(zh: "德语", en: "German")
        }
    }
}

enum TranslationFontChoice: String, Codable, CaseIterable, Identifiable {
    case rounded
    case system
    case pingFang
    case songti
    case kaiti
    case monospaced
    case custom

    var id: Self { self }

    var postScriptName: String? {
        switch self {
        case .rounded, .system, .monospaced, .custom: nil
        case .pingFang: "PingFang SC"
        case .songti: "Songti SC"
        case .kaiti: "Kaiti SC"
        }
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .rounded: language.pick(zh: "圆体（默认）", en: "Rounded (Default)")
        case .system: language.pick(zh: "系统字体", en: "System")
        case .pingFang: language.pick(zh: "苹方", en: "PingFang SC")
        case .songti: language.pick(zh: "宋体", en: "Songti SC")
        case .kaiti: language.pick(zh: "楷体", en: "Kaiti SC")
        case .monospaced: language.pick(zh: "等宽字体", en: "Monospaced")
        case .custom: language.pick(zh: "已安装字体", en: "Installed Font")
        }
    }

    func font(
        size: CGFloat,
        weight: Font.Weight,
        customFamily: String? = nil
    ) -> Font {
        if self == .custom,
           let customFamily = customFamily?.trimmingCharacters(in: .whitespacesAndNewlines),
           !customFamily.isEmpty {
            return .custom(customFamily, size: size).weight(weight)
        }
        if let postScriptName {
            return .custom(postScriptName, size: size).weight(weight)
        }
        let design: Font.Design = switch self {
        case .rounded: .rounded
        case .monospaced: .monospaced
        default: .default
        }
        return .system(size: size, weight: weight, design: design)
    }
}

enum LyrisFontSearch {
    static func filteredFamilies(_ families: [String], query: String) -> [String] {
        let normalizedQuery = LyrisInstalledFontCatalog.normalizedSearchKey(query)
        guard !normalizedQuery.isEmpty else { return families }
        return families.filter {
            LyrisInstalledFontCatalog.normalizedSearchKey($0).contains(normalizedQuery)
        }
    }
}

struct LyrisFontRecommendation: Equatable, Sendable {
    let choice: TranslationFontChoice
    let customFamily: String?
    let displayName: String

    static func recommendation(
        for target: TranslationTargetLanguage,
        availableFamilies: [String]
    ) -> Self {
        func installed(_ candidates: [String]) -> String? {
            candidates.first { candidate in
                availableFamilies.contains {
                    $0.compare(candidate, options: [.caseInsensitive, .diacriticInsensitive])
                        == .orderedSame
                }
            }
        }

        switch target {
        case .simplifiedChinese:
            return Self(choice: .pingFang, customFamily: nil, displayName: "苹方")
        case .japanese:
            if let family = installed(["Hiragino Sans", "Hiragino Kaku Gothic ProN"]) {
                return Self(choice: .custom, customFamily: family, displayName: family)
            }
            return Self(choice: .system, customFamily: nil, displayName: "系统字体")
        case .korean:
            if let family = installed(["Apple SD Gothic Neo", "AppleGothic"]) {
                return Self(choice: .custom, customFamily: family, displayName: family)
            }
            return Self(choice: .system, customFamily: nil, displayName: "系统字体")
        case .english, .spanish, .french, .german:
            return Self(choice: .rounded, customFamily: nil, displayName: "系统圆体")
        }
    }
}

enum LyrisInterfaceSkin: String, Codable, CaseIterable, Identifiable {
    case spotifyBlack
    case midnightAurora
    case graphite

    var id: Self { self }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .spotifyBlack: language.pick(zh: "Spotify 深邃黑", en: "Spotify Deep Black")
        case .midnightAurora: language.pick(zh: "午夜极光", en: "Midnight Aurora")
        case .graphite: language.pick(zh: "石墨灰", en: "Graphite")
        }
    }

    var backgroundColor: Color {
        switch self {
        case .spotifyBlack: Color(red: 0.008, green: 0.014, blue: 0.012)
        case .midnightAurora: Color(red: 0.012, green: 0.032, blue: 0.024)
        case .graphite: Color(red: 0.035, green: 0.038, blue: 0.042)
        }
    }

    var raisedBackgroundColor: Color {
        switch self {
        case .spotifyBlack: Color(red: 0.018, green: 0.030, blue: 0.024)
        case .midnightAurora: Color(red: 0.018, green: 0.072, blue: 0.052)
        case .graphite: Color(red: 0.090, green: 0.096, blue: 0.104)
        }
    }

    var secondaryAccentColor: Color {
        switch self {
        case .spotifyBlack: Color(red: 0.12, green: 0.84, blue: 0.38)
        case .midnightAurora: Color(red: 0.10, green: 0.64, blue: 0.46)
        case .graphite: Color(red: 0.46, green: 0.56, blue: 0.53)
        }
    }

    var visualSignature: String {
        switch self {
        case .spotifyBlack: "spotify-black-lime"
        case .midnightAurora: "midnight-aurora-emerald"
        case .graphite: "graphite-neutral"
        }
    }

    var accentColor: Color {
        switch self {
        case .spotifyBlack: LyrisTheme.accent
        case .midnightAurora: Color(red: 0.30, green: 1.00, blue: 0.62)
        case .graphite: Color(red: 0.78, green: 0.84, blue: 0.80)
        }
    }
}

enum LyrisArtworkPresentationMode: String, Codable, CaseIterable, Identifiable {
    case staticArtwork
    case ambientMotion

    var id: Self { self }

    var next: Self {
        switch self {
        case .staticArtwork: .ambientMotion
        case .ambientMotion: .staticArtwork
        }
    }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .staticArtwork: language.pick(zh: "静态封面", en: "Static Artwork")
        case .ambientMotion: language.pick(zh: "封面微动", en: "Artwork Motion")
        }
    }
}

enum MenuBarLyricMode: String, Codable, CaseIterable, Identifiable {
    case original
    case translated
    case bilingual

    var id: Self { self }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .original:
            language.pick(zh: "只显示原文", en: "Original only")
        case .translated:
            language.pick(zh: "只显示译文", en: "Translation only")
        case .bilingual:
            language.pick(zh: "显示双语", en: "Bilingual")
        }
    }
}

struct LyrisDisplayPreferences: Codable, Equatable {
    var interfaceLanguage: AppLanguage
    var translationTarget: TranslationTargetLanguage
    var translationFont: TranslationFontChoice
    var customTranslationFontFamily: String
    var interfaceSkin: LyrisInterfaceSkin
    var artworkPresentationMode: LyrisArtworkPresentationMode
    var floatingPresentationMode: FloatingPresentationMode
    var macIslandExpandedHoldDuration: MacIslandExpandedHoldDuration
    var macIslandExpansionTrigger: MacIslandExpansionTrigger
    var macIslandHoverExpandDelay: Double
    var menuBarLyricMode: MenuBarLyricMode
    var convertsTraditionalChineseToSimplified: Bool

    static func load(from defaults: UserDefaults) -> Self {
        Self(
            interfaceLanguage: defaults.string(forKey: "interfaceLanguage")
                .flatMap(AppLanguage.init(rawValue:)) ?? .simplifiedChinese,
            translationTarget: defaults.string(forKey: "translationTargetLanguage")
                .flatMap(TranslationTargetLanguage.init(rawValue:)) ?? .simplifiedChinese,
            translationFont: defaults.string(forKey: "translationFontChoice")
                .flatMap(TranslationFontChoice.init(rawValue:)) ?? .rounded,
            customTranslationFontFamily: defaults.string(
                forKey: "customTranslationFontFamily"
            ) ?? "",
            interfaceSkin: defaults.string(forKey: "interfaceSkin")
                .flatMap(LyrisInterfaceSkin.init(rawValue:)) ?? .midnightAurora,
            artworkPresentationMode: defaults.string(forKey: "artworkPresentationMode")
                .flatMap(LyrisArtworkPresentationMode.init(rawValue:)) ?? .staticArtwork,
            floatingPresentationMode: defaults.string(forKey: "floatingPresentationMode")
                .flatMap(FloatingPresentationMode.init(rawValue:)) ?? .topIsland,
            macIslandExpandedHoldDuration: defaults.string(forKey: "macIslandExpandedHoldDuration")
                .flatMap(MacIslandExpandedHoldDuration.init(rawValue:)) ?? .balanced,
            macIslandExpansionTrigger: defaults.string(forKey: "macIslandExpansionTrigger")
                .flatMap(MacIslandExpansionTrigger.init(rawValue:)) ?? .hoverAndClick,
            macIslandHoverExpandDelay: defaults.object(forKey: "macIslandHoverExpandDelay") == nil
                ? 3
                : min(max(defaults.double(forKey: "macIslandHoverExpandDelay"), 0), 5),
            menuBarLyricMode: defaults.string(forKey: "menuBarLyricMode")
                .flatMap(MenuBarLyricMode.init(rawValue:)) ?? .translated,
            convertsTraditionalChineseToSimplified: defaults.object(
                forKey: "convertsTraditionalChineseToSimplified"
            ) as? Bool ?? true
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
        defaults.set(translationTarget.rawValue, forKey: "translationTargetLanguage")
        defaults.set(translationFont.rawValue, forKey: "translationFontChoice")
        defaults.set(customTranslationFontFamily, forKey: "customTranslationFontFamily")
        defaults.set(interfaceSkin.rawValue, forKey: "interfaceSkin")
        defaults.set(artworkPresentationMode.rawValue, forKey: "artworkPresentationMode")
        defaults.set(floatingPresentationMode.rawValue, forKey: "floatingPresentationMode")
        defaults.set(
            macIslandExpandedHoldDuration.rawValue,
            forKey: "macIslandExpandedHoldDuration"
        )
        defaults.set(macIslandExpansionTrigger.rawValue, forKey: "macIslandExpansionTrigger")
        defaults.set(macIslandHoverExpandDelay, forKey: "macIslandHoverExpandDelay")
        defaults.set(menuBarLyricMode.rawValue, forKey: "menuBarLyricMode")
        defaults.set(
            convertsTraditionalChineseToSimplified,
            forKey: "convertsTraditionalChineseToSimplified"
        )
    }
}
