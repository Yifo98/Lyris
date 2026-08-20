import Foundation

enum TranslationEndpointPolicy {
    static func allows(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        guard scheme == "http", let host = components.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
