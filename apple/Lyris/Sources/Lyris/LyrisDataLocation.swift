import Foundation

enum LyrisDataLocation {
    static func rootURL(
        startingAt bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> URL {
        var candidate = bundleURL.standardizedFileURL
        while candidate.pathComponents.count > 1 {
            let macPackage = candidate.appendingPathComponent("apple/Lyris/Package.swift")
            if fileManager.fileExists(atPath: macPackage.path) {
                return candidate.appendingPathComponent("LyrisData", isDirectory: true)
            }
            candidate.deleteLastPathComponent()
        }
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return migrateLegacyApplicationSupportIfNeeded(
            applicationSupportURL: applicationSupport,
            fileManager: fileManager
        )
    }

    static func migrateLegacyApplicationSupportIfNeeded(
        applicationSupportURL: URL,
        fileManager: FileManager = .default
    ) -> URL {
        let current = applicationSupportURL.appendingPathComponent("Lyris", isDirectory: true)
        let legacy = applicationSupportURL.appendingPathComponent("MeloFloat", isDirectory: true)
        guard !fileManager.fileExists(atPath: current.path),
              fileManager.fileExists(atPath: legacy.path) else {
            return current
        }
        do {
            try fileManager.createDirectory(
                at: applicationSupportURL,
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: legacy, to: current)
            return current
        } catch {
            // Never strand user-authored lyrics or configuration if the one-time
            // rename cannot be completed. A later launch can retry the move.
            return legacy
        }
    }

    static func prepareSharedURLCache() {
        let directory = cacheURL().appendingPathComponent("Network", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        URLCache.shared = URLCache(
            memoryCapacity: 24 * 1_024 * 1_024,
            diskCapacity: 160 * 1_024 * 1_024,
            directory: directory
        )
    }

    static func lyricsURL(
        startingAt bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> URL {
        rootURL(startingAt: bundleURL, fileManager: fileManager)
            .appendingPathComponent("Lyrics", isDirectory: true)
    }

    static func cacheURL(
        startingAt bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> URL {
        rootURL(startingAt: bundleURL, fileManager: fileManager)
            .appendingPathComponent("Cache", isDirectory: true)
    }

    static func fontsURL(
        startingAt bundleURL: URL = Bundle.main.bundleURL,
        fileManager: FileManager = .default
    ) -> URL {
        rootURL(startingAt: bundleURL, fileManager: fileManager)
            .appendingPathComponent("Fonts", isDirectory: true)
    }

    static func writeConfiguration(_ configuration: NonSecretConfigurationSnapshot) {
        let directory = rootURL().appendingPathComponent("Config", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration)
            try data.write(to: directory.appendingPathComponent("settings.json"), options: .atomic)
        } catch {
            // UserDefaults remains the runtime source of truth if the readable mirror cannot be written.
        }
    }
}

struct NonSecretConfigurationSnapshot: Codable {
    let hasSpotifyClientID: Bool
    let interfaceLanguage: String
    let translationProvider: String
    let translationBaseURL: String
    let translationModel: String
    let translationThinkingEnabled: Bool
    let translationStyle: String
    let translationTargetLanguage: String
    let translationFont: String
    let customTranslationFontFamily: String
    let interfaceSkin: String
    let artworkPresentationMode: String
    let menuBarLyricMode: String
    let floatingPresentationMode: String
    let macIslandExpandedHoldDuration: String
    let macIslandExpansionTrigger: String
    let macIslandHoverExpandDelay: Double
    let convertsTraditionalChineseToSimplified: Bool
    let linkedEffectStyle: String
    let costCurrency: String
    let costCurrencyUnitsPerUSD: Double
    let lyricTimingDelay: Double
    let sensitiveValuesLocation: String
}
