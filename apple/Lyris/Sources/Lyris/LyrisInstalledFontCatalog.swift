import AppKit
import Foundation

struct LyrisInstalledFontOption: Identifiable, Equatable, Hashable, Sendable {
    let familyName: String
    let displayName: String
    let aliases: [String]

    var id: String { familyName }

    fileprivate var searchableNames: [String] {
        [familyName, displayName] + aliases
    }
}

enum LyrisInstalledFontCatalog {
    @MainActor private static var cachedSharedOptions: [LyrisInstalledFontOption]?

    @MainActor
    static func systemOptions(
        fontManager: NSFontManager = .shared
    ) -> [LyrisInstalledFontOption] {
        let usesSharedManager = fontManager === NSFontManager.shared
        if usesSharedManager, let cachedSharedOptions {
            return cachedSharedOptions
        }
        let options: [LyrisInstalledFontOption] = fontManager.availableFontFamilies
            .compactMap { family -> LyrisInstalledFontOption? in
                let normalizedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalizedFamily.isEmpty else { return nil }

                var aliases: [String] = []
                var displayName = normalizedFamily
                for member in fontManager.availableMembers(ofFontFamily: normalizedFamily) ?? [] {
                    guard let postScriptName = member.first as? String else { continue }
                    aliases.append(postScriptName)
                    if member.count > 1, let styleName = member[1] as? String {
                        aliases.append(styleName)
                    }
                    if let font = NSFont(name: postScriptName, size: 13) {
                        aliases.append(font.fontName)
                        aliases.append(font.familyName ?? "")
                        aliases.append(font.displayName ?? "")
                        if displayName == normalizedFamily,
                           let visibleName = font.displayName,
                           !visibleName.isEmpty {
                            displayName = visibleName
                        }
                    }
                }

                return LyrisInstalledFontOption(
                    familyName: normalizedFamily,
                    displayName: displayName,
                    aliases: aliases
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                )
            }
            .sorted {
                $0.familyName.localizedCaseInsensitiveCompare($1.familyName) == .orderedAscending
            }
        if usesSharedManager {
            cachedSharedOptions = options
        }
        return options
    }

    @MainActor
    static func invalidateSystemOptionsCache() {
        cachedSharedOptions = nil
    }

    static func filteredOptions(
        _ options: [LyrisInstalledFontOption],
        query: String
    ) -> [LyrisInstalledFontOption] {
        let normalizedQuery = normalizedSearchKey(query)
        guard !normalizedQuery.isEmpty else { return options }
        return options.filter { option in
            option.searchableNames.contains {
                normalizedSearchKey($0).contains(normalizedQuery)
            }
        }
    }

    static func normalizedSearchKey(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        let scalars = folded.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }
}
