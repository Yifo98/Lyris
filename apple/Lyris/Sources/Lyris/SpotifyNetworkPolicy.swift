import Foundation

enum SpotifyNetworkFailure: Error, Equatable, Sendable {
    case invalidGrant
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: TimeInterval?)
    case server(statusCode: Int)
    case offline
    case cancelled
    case client(statusCode: Int)
    case transport
}

extension SpotifyNetworkFailure: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidGrant:
            "Spotify 授权已过期，需要重新授权。"
        case .unauthorized:
            "Spotify 拒绝了当前访问令牌。"
        case .forbidden:
            "Spotify 账户或授权范围不允许此操作。"
        case .rateLimited(let retryAfter):
            retryAfter.map { "Spotify 请求过于频繁，请在 \(Int(ceil($0))) 秒后重试。" }
                ?? "Spotify 请求过于频繁，请稍后重试。"
        case .server(let statusCode):
            "Spotify 服务暂时不可用（HTTP \(statusCode)）。"
        case .offline:
            "网络当前不可用；本地播放与歌词仍可继续。"
        case .cancelled:
            "操作已取消。"
        case .client(let statusCode):
            "Spotify 请求失败（HTTP \(statusCode)）。"
        case .transport:
            "无法连接 Spotify 服务。"
        }
    }
}

enum SpotifyRequestOperation: Equatable, Sendable {
    case read
    case absoluteMutation
    case navigation

    func permitsAutomaticRetry(for failure: SpotifyNetworkFailure) -> Bool {
        switch self {
        case .read, .absoluteMutation:
            switch failure {
            case .rateLimited, .server, .offline, .transport:
                true
            case .invalidGrant, .unauthorized, .forbidden, .cancelled, .client:
                false
            }
        case .navigation:
            false
        }
    }
}

enum SpotifyNetworkFailureClassifier {
    static func classify(
        statusCode: Int? = nil,
        headers: [String: String] = [:],
        responseBody: Data? = nil,
        underlyingError: Error? = nil,
        now: Date = Date()
    ) -> SpotifyNetworkFailure {
        if isInvalidGrant(responseBody) {
            return .invalidGrant
        }

        guard let statusCode else {
            if isCancelled(underlyingError) {
                return .cancelled
            }
            return isOffline(underlyingError) ? .offline : .transport
        }

        switch statusCode {
        case 401:
            return .unauthorized
        case 403:
            return .forbidden
        case 429:
            let rawRetryAfter = headers.first {
                $0.key.caseInsensitiveCompare("Retry-After") == .orderedSame
            }?.value
            return .rateLimited(
                retryAfter: rawRetryAfter.flatMap { SpotifyRetryAfter.parse($0, now: now) }
            )
        case 500 ... 599:
            return .server(statusCode: statusCode)
        default:
            return .client(statusCode: statusCode)
        }
    }

    private static func isInvalidGrant(_ data: Data?) -> Bool {
        guard
            let data,
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let code = object["error"] as? String
        else {
            return false
        }
        return code.caseInsensitiveCompare("invalid_grant") == .orderedSame
    }

    private static func isOffline(_ error: Error?) -> Bool {
        guard let error else { return false }
        let urlError: URLError
        if let typed = error as? URLError {
            urlError = typed
        } else {
            let bridged = error as NSError
            guard bridged.domain == NSURLErrorDomain else { return false }
            urlError = URLError(URLError.Code(rawValue: bridged.code))
        }

        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private static func isCancelled(_ error: Error?) -> Bool {
        guard let error else { return false }
        if error is CancellationError { return true }
        if let urlError = error as? URLError { return urlError.code == .cancelled }
        let bridged = error as NSError
        return bridged.domain == NSURLErrorDomain
            && bridged.code == URLError.Code.cancelled.rawValue
    }
}

enum SpotifyRetryAfter {
    static func parse(_ rawValue: String, now: Date = Date()) -> TimeInterval? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let seconds = TimeInterval(value), seconds.isFinite {
            return max(0, seconds)
        }

        for format in httpDateFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return max(0, date.timeIntervalSince(now))
            }
        }
        return nil
    }

    private static let httpDateFormats = [
        "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
        "EEEE',' dd-MMM-yy HH':'mm':'ss zzz",
        "EEE MMM d HH':'mm':'ss yyyy",
    ]
}

struct SpotifyRetryPolicy {
    struct Configuration: Equatable, Sendable {
        var maximumRetryCount: Int = 4
        var baseDelay: TimeInterval = 0.5
        var maximumDelay: TimeInterval = 30
        var jitterFraction: Double = 0.2
    }

    typealias Jitter = (_ retryNumber: Int) -> Double

    private let configuration: Configuration
    private let jitter: Jitter

    init(
        configuration: Configuration = .init(),
        jitter: @escaping Jitter = { _ in Double.random(in: -1 ... 1) }
    ) {
        self.configuration = configuration
        self.jitter = jitter
    }

    func delay(
        for failure: SpotifyNetworkFailure,
        retryNumber: Int
    ) -> TimeInterval? {
        guard retryNumber > 0, retryNumber <= max(0, configuration.maximumRetryCount) else {
            return nil
        }

        let maximumDelay = max(0, configuration.maximumDelay)
        if case .rateLimited(let retryAfter?) = failure {
            // Retry-After is a server minimum, not a client-side backoff hint.
            // Never shorten it; callers may instead schedule a later retry.
            return max(0, retryAfter)
        }

        guard failure.isRetryable else { return nil }

        let baseDelay = max(0, configuration.baseDelay)
        let exponential = baseDelay * pow(2, Double(retryNumber - 1))
        let bounded = min(exponential.isFinite ? exponential : maximumDelay, maximumDelay)
        let jitterFraction = min(max(configuration.jitterFraction, 0), 1)
        let jitterSample = min(max(jitter(retryNumber), -1), 1)
        return min(max(0, bounded * (1 + jitterFraction * jitterSample)), maximumDelay)
    }
}

private extension SpotifyNetworkFailure {
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .server, .offline, .transport:
            return true
        case .invalidGrant, .unauthorized, .forbidden, .cancelled, .client:
            return false
        }
    }
}

enum SpotifyNetworkRecoveryDecision: Equatable, Sendable {
    case clearRefreshTokenAndReauthorize
    case refreshAccessToken
    case retry
    case doNotRetry
}

enum SpotifyNetworkRecovery {
    static func decision(for failure: SpotifyNetworkFailure) -> SpotifyNetworkRecoveryDecision {
        switch failure {
        case .invalidGrant:
            return .clearRefreshTokenAndReauthorize
        case .unauthorized:
            return .refreshAccessToken
        case .rateLimited, .server, .offline, .transport:
            return .retry
        case .forbidden, .cancelled, .client:
            return .doNotRetry
        }
    }
}

enum SpotifyRefreshTokenLifetimeStatus: Equatable, Sendable {
    case valid(expiresAt: Date)
    case reauthorizationReminderDue(expiresAt: Date)
    case expired(at: Date)
}

struct SpotifyRefreshTokenLifetimePolicy {
    private let calendar: Calendar
    private let lifetimeMonths: Int
    private let reminderLeadDays: Int
    private let now: () -> Date

    init(
        calendar: Calendar = .current,
        lifetimeMonths: Int = 6,
        reminderLeadDays: Int = 14,
        now: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.lifetimeMonths = max(0, lifetimeMonths)
        self.reminderLeadDays = max(0, reminderLeadDays)
        self.now = now
    }

    func expirationDate(originalAuthorizationDate: Date) -> Date {
        calendar.date(
            byAdding: .month,
            value: lifetimeMonths,
            to: originalAuthorizationDate
        ) ?? originalAuthorizationDate
    }

    func status(originalAuthorizationDate: Date) -> SpotifyRefreshTokenLifetimeStatus {
        let expiration = expirationDate(originalAuthorizationDate: originalAuthorizationDate)
        let currentDate = now()
        if currentDate >= expiration {
            return .expired(at: expiration)
        }

        let reminderDate = calendar.date(
            byAdding: .day,
            value: -reminderLeadDays,
            to: expiration
        ) ?? expiration
        if currentDate >= reminderDate {
            return .reauthorizationReminderDue(expiresAt: expiration)
        }
        return .valid(expiresAt: expiration)
    }
}

enum SpotifyCredentialRedactor {
    static let placeholder = "<redacted>"

    static func redact(_ message: String) -> String {
        let separator = #"[\s._-]*"#
        let authorizationPattern = #"(?i)(\b(?:(?:proxy)\#(separator))?authorization\b["']?\s*[:=]\s*)(["']?)([^"'\s,;&]+(?:\s+[^"'\s,;&]+)?)(["']?)"#
        let credentialNames = [
            #"x\#(separator)api\#(separator)key"#,
            #"api\#(separator)key"#,
            #"apikey"#,
            #"x\#(separator)client\#(separator)secret"#,
            #"client\#(separator)secret"#,
            #"access\#(separator)token"#,
            #"refresh\#(separator)token"#,
            #"(?:[a-z0-9]+[\s._-]+)+token"#,
            #"authorization\#(separator)code"#,
            #"auth\#(separator)code"#,
            #"code\#(separator)verifier"#,
            #"access"#,
            #"refresh"#,
            #"secret"#,
            #"token"#,
            #"code"#,
        ].joined(separator: "|")
        let credentialPattern = #"(?i)(\b(?:\#(credentialNames))\b["']?\s*[:=]\s*)(["']?)([^"'\s&,;}]+)(["']?)"#

        let authorizationRedacted = replacing(
            authorizationPattern,
            in: message,
            template: "$1$2\(placeholder)$4"
        )
        return replacing(
            credentialPattern,
            in: authorizationRedacted,
            template: "$1$2\(placeholder)$4"
        )
    }

    static func redact(headers: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: headers.map { key, value in
            (key, isSensitiveHeader(key) ? placeholder : redact(value))
        })
    }

    private static func isSensitiveHeader(_ name: String) -> Bool {
        let normalized = name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        let exactNames = [
            "authorization",
            "proxyauthorization",
            "secret",
            "clientsecret",
            "xclientsecret",
            "accesstoken",
            "refreshtoken",
            "authorizationcode",
            "authcode",
            "codeverifier",
            "access",
            "refresh",
            "apikey",
            "xapikey",
            "token",
            "code",
        ]
        if exactNames.contains(normalized) { return true }
        return ["authorization", "apikey", "clientsecret", "token", "codeverifier"]
            .contains { normalized.hasSuffix($0) }
    }

    private static func replacing(
        _ pattern: String,
        in value: String,
        template: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return value
        }
        let range = NSRange(value.startIndex ..< value.endIndex, in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: template
        )
    }
}
