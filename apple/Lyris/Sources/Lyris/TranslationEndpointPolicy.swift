import CryptoKit
import Foundation

enum TranslationEndpointPolicy {
    // Persist only a digest: custom endpoint URLs may contain private query data.
    static func cacheIdentity(for baseURL: String) -> String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var identity = trimmed
        if var components = URLComponents(string: trimmed) {
            components.scheme = components.scheme?.lowercased()
            components.host = components.host?.lowercased()
            if (components.scheme == "https" && components.port == 443)
                || (components.scheme == "http" && components.port == 80) {
                components.port = nil
            }
            let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            components.path = path.isEmpty ? "" : "/" + path
            components.fragment = nil
            identity = components.string ?? trimmed
        }
        return SHA256.hash(data: Data(identity.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func allows(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        guard scheme == "http", let host = components.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
