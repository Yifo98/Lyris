import Foundation

enum OfficialPricingPeriod: String, Equatable, Sendable {
    case peak
    case offPeak
    case standard
}

struct OfficialTranslationPricingSnapshot: Equatable, Sendable {
    let rates: TranslationPricingRates
    let period: OfficialPricingPeriod
    let checkedAt: Date
    let sourceURL: URL
    let note: String
}

enum OfficialTranslationPricingError: LocalizedError, Equatable {
    case unsupportedProvider
    case invalidResponse
    case unparseablePage

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider:
            "当前服务暂不支持自动读取官方价格，请打开官方价格页或手动填写。"
        case .invalidResponse:
            "官方价格页暂时无法访问。"
        case .unparseablePage:
            "官方价格页已更新，Lyris 暂时无法可靠解析，请打开页面核对。"
        }
    }
}

enum DeepSeekOfficialPricingParser {
    static func parse(
        pageText: String,
        model: String,
        now: Date
    ) throws -> OfficialTranslationPricingSnapshot {
        let normalized = normalizedText(pageText)
        let input = try values(
            in: normalized,
            pattern: #"1M INPUT TOKENS \(CACHE MISS\)\s+OFF-PEAK\s+\$([0-9.]+)\s+\$([0-9.]+)\s+PEAK\s+\$([0-9.]+)\s+\$([0-9.]+)"#
        )
        let output = try values(
            in: normalized,
            pattern: #"1M OUTPUT TOKENS\s+OFF-PEAK\s+\$([0-9.]+)\s+\$([0-9.]+)\s+PEAK\s+\$([0-9.]+)\s+\$([0-9.]+)"#
        )
        let modelColumn = model.lowercased().contains("pro") ? 1 : 0
        let period = pricingPeriod(at: now)
        let periodOffset = period == .peak ? 2 : 0
        let index = periodOffset + modelColumn
        guard input.indices.contains(index), output.indices.contains(index) else {
            throw OfficialTranslationPricingError.unparseablePage
        }
        guard let sourceURL = URL(
            string: "https://api-docs.deepseek.com/quick_start/pricing/"
        ) else {
            throw OfficialTranslationPricingError.invalidResponse
        }
        return OfficialTranslationPricingSnapshot(
            rates: TranslationPricingRates(
                inputUSDPerMillion: input[index],
                outputUSDPerMillion: output[index]
            ),
            period: period,
            checkedAt: now,
            sourceURL: sourceURL,
            note: period == .peak
                ? "DeepSeek 高峰时段、缓存未命中参考价"
                : "DeepSeek 非高峰时段、缓存未命中参考价"
        )
    }

    private static func pricingPeriod(at date: Date) -> OfficialPricingPeriod {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let hour = calendar.component(.hour, from: date)
        return (1..<4).contains(hour) || (6..<10).contains(hour)
            ? .peak
            : .offPeak
    }

    private static func values(in text: String, pattern: String) throws -> [Double] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            throw OfficialTranslationPricingError.unparseablePage
        }
        let values = (1..<match.numberOfRanges).compactMap { index -> Double? in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Double(text[range])
        }
        guard values.count == 4 else {
            throw OfficialTranslationPricingError.unparseablePage
        }
        return values
    }

    private static func normalizedText(_ value: String) -> String {
        var text = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let entities = [
            "&#x24;": "$",
            "&#36;": "$",
            "&dollar;": "$",
            "&nbsp;": " ",
            "&amp;": "&",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        return text.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
    }
}

struct OfficialTranslationPricingClient: Sendable {
    func fetch(
        provider: TranslationProvider,
        model: String,
        now: Date = Date()
    ) async throws -> OfficialTranslationPricingSnapshot {
        guard provider == .deepSeek,
              let url = TranslationPricingCatalog.reference(
                provider: provider,
                model: model
              ).sourceURL else {
            throw OfficialTranslationPricingError.unsupportedProvider
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let pageText = String(data: data, encoding: .utf8) else {
            throw OfficialTranslationPricingError.invalidResponse
        }
        return try DeepSeekOfficialPricingParser.parse(
            pageText: pageText,
            model: model,
            now: now
        )
    }
}
