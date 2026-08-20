import CryptoKit
import Foundation
import Security

protocol SpotifyAuthorizationFlowing {
    var mode: SpotifyAuthorizationMode { get }
    func makeAttempt(
        for profile: SpotifyAuthorizationProfile,
        scopes: Set<String>
    ) throws -> SpotifyAuthorizationAttempt
    func exchange(
        callbackURL: URL,
        attempt: SpotifyAuthorizationAttempt
    ) async throws -> SpotifyAuthorizationTokenGrant
    func withValidAuthorizationFence(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> Void
    ) throws
}

final class SpotifyPKCEAuthorizationFlow: SpotifyAuthorizationFlowing {
    typealias ProofGenerator = () throws -> SpotifyPKCEProof
    typealias StateGenerator = () throws -> String

    private let exchanger: any SpotifyAuthorizationTokenExchanging
    private let proofGenerator: ProofGenerator
    private let stateGenerator: StateGenerator

    let mode = SpotifyAuthorizationMode.pkce

    init(
        exchanger: any SpotifyAuthorizationTokenExchanging,
        proofGenerator: @escaping ProofGenerator = { try SpotifyAuthorizationEntropy.makePKCEProof() },
        stateGenerator: @escaping StateGenerator = { try SpotifyAuthorizationEntropy.randomURLSafeString(byteCount: 24) }
    ) {
        self.exchanger = exchanger
        self.proofGenerator = proofGenerator
        self.stateGenerator = stateGenerator
    }

    func makeAttempt(
        for profile: SpotifyAuthorizationProfile,
        scopes: Set<String>
    ) throws -> SpotifyAuthorizationAttempt {
        guard profile.authorizationMode == .pkce else {
            throw SpotifyAuthorizationCoreError.profileModeMismatch
        }
        let proof = try proofGenerator()
        guard (43...128).contains(proof.verifier.count), !proof.challenge.isEmpty else {
            throw SpotifyAuthorizationCoreError.invalidProof
        }
        let state = try stateGenerator()
        guard !state.isEmpty else { throw SpotifyAuthorizationCoreError.invalidProof }
        let authorizationURL = try SpotifyAuthorizationRequestBuilder.authorizationURL(
            profile: profile,
            scopes: scopes,
            state: state,
            pkceChallenge: proof.challenge
        )
        return SpotifyAuthorizationAttempt(
            profileID: profile.id,
            clientID: profile.clientID,
            mode: .pkce,
            redirectURI: profile.redirectURI,
            requestedScopes: scopes,
            authorizationURL: authorizationURL,
            state: state,
            sessionProof: .pkce(codeVerifier: proof.verifier),
            authorizationFence: exchanger.authorizationFence(for: profile.id)
        )
    }

    func exchange(
        callbackURL: URL,
        attempt: SpotifyAuthorizationAttempt
    ) async throws -> SpotifyAuthorizationTokenGrant {
        guard attempt.mode == .pkce,
              case .pkce(let verifier) = attempt.sessionProof else {
            throw SpotifyAuthorizationCoreError.profileModeMismatch
        }
        let code = try SpotifyAuthorizationCallbackParser.authorizationCode(
            from: callbackURL,
            attempt: attempt
        )
        return try await exchanger.exchange(
            SpotifyAuthorizationTokenRequest(
                profileID: attempt.profileID,
                clientID: attempt.clientID,
                redirectURI: attempt.redirectURI,
                authorizationCode: code,
                authentication: .pkce(codeVerifier: verifier),
                authorizationFence: attempt.authorizationFence
            )
        )
    }

    func withValidAuthorizationFence(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> Void
    ) throws {
        try exchanger.withValidAuthorizationFence(fence, perform: operation)
    }
}

final class SpotifySecretAuthorizationFlow: SpotifyAuthorizationFlowing {
    typealias StateGenerator = () throws -> String

    private let exchanger: any SpotifyAuthorizationTokenExchanging
    private let tokenStore: SpotifyTokenStore
    private let stateGenerator: StateGenerator

    let mode = SpotifyAuthorizationMode.authorizationCodeWithSecret

    init(
        exchanger: any SpotifyAuthorizationTokenExchanging,
        tokenStore: SpotifyTokenStore,
        stateGenerator: @escaping StateGenerator = {
            try SpotifyAuthorizationEntropy.randomURLSafeString(byteCount: 24)
        }
    ) {
        self.exchanger = exchanger
        self.tokenStore = tokenStore
        self.stateGenerator = stateGenerator
    }

    func makeAttempt(
        for profile: SpotifyAuthorizationProfile,
        scopes: Set<String>
    ) throws -> SpotifyAuthorizationAttempt {
        guard profile.authorizationMode == .authorizationCodeWithSecret else {
            throw SpotifyAuthorizationCoreError.profileModeMismatch
        }
        let state = try stateGenerator()
        guard !state.isEmpty else { throw SpotifyAuthorizationCoreError.invalidProof }
        let authorizationURL = try SpotifyAuthorizationRequestBuilder.authorizationURL(
            profile: profile,
            scopes: scopes,
            state: state,
            pkceChallenge: nil
        )
        return SpotifyAuthorizationAttempt(
            profileID: profile.id,
            clientID: profile.clientID,
            mode: .authorizationCodeWithSecret,
            redirectURI: profile.redirectURI,
            requestedScopes: scopes,
            authorizationURL: authorizationURL,
            state: state,
            sessionProof: .clientSecretFromTokenStore,
            authorizationFence: exchanger.authorizationFence(for: profile.id)
        )
    }

    func exchange(
        callbackURL: URL,
        attempt: SpotifyAuthorizationAttempt
    ) async throws -> SpotifyAuthorizationTokenGrant {
        guard attempt.mode == .authorizationCodeWithSecret,
              case .clientSecretFromTokenStore = attempt.sessionProof else {
            throw SpotifyAuthorizationCoreError.profileModeMismatch
        }
        let code = try SpotifyAuthorizationCallbackParser.authorizationCode(
            from: callbackURL,
            attempt: attempt
        )
        guard let clientSecret = try tokenStore.clientSecret(for: attempt.profileID),
              !clientSecret.isEmpty else {
            throw SpotifyAuthorizationCoreError.missingClientSecret
        }
        return try await exchanger.exchange(
            SpotifyAuthorizationTokenRequest(
                profileID: attempt.profileID,
                clientID: attempt.clientID,
                redirectURI: attempt.redirectURI,
                authorizationCode: code,
                authentication: .clientSecret(clientSecret),
                authorizationFence: attempt.authorizationFence
            )
        )
    }

    func withValidAuthorizationFence(
        _ fence: SpotifyAuthorizationFence,
        perform operation: () throws -> Void
    ) throws {
        try exchanger.withValidAuthorizationFence(fence, perform: operation)
    }
}

private enum SpotifyAuthorizationCallbackParser {
    static func authorizationCode(
        from callbackURL: URL,
        attempt: SpotifyAuthorizationAttempt
    ) throws -> String {
        guard callbackMatches(callbackURL, redirectURI: attempt.redirectURI),
              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw SpotifyAuthorizationCoreError.invalidCallback
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard values[item.name] == nil else {
                throw SpotifyAuthorizationCoreError.invalidCallback
            }
            values[item.name] = item.value ?? ""
        }
        guard values["state"] == attempt.state else {
            throw SpotifyAuthorizationCoreError.stateMismatch
        }
        if let denied = values["error"], !denied.isEmpty {
            throw SpotifyAuthorizationCoreError.denied(denied)
        }
        guard let code = values["code"], !code.isEmpty else {
            throw SpotifyAuthorizationCoreError.missingCode
        }
        return code
    }

    private static func callbackMatches(_ callbackURL: URL, redirectURI: String) -> Bool {
        guard let expected = URLComponents(string: redirectURI),
              let actual = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            return false
        }
        return expected.scheme?.lowercased() == actual.scheme?.lowercased()
            && expected.host?.lowercased() == actual.host?.lowercased()
            && expected.port == actual.port
            && expected.path == actual.path
    }
}

private enum SpotifyAuthorizationRequestBuilder {
    static func authorizationURL(
        profile: SpotifyAuthorizationProfile,
        scopes: Set<String>,
        state: String,
        pkceChallenge: String?
    ) throws -> URL {
        guard isValidLoopbackRedirect(profile.redirectURI) else {
            throw SpotifyAuthorizationCoreError.invalidRedirectURI
        }
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        var queryItems = [
            URLQueryItem(name: "client_id", value: profile.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: profile.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.sorted().joined(separator: " ")),
        ]
        if let pkceChallenge {
            queryItems.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
            queryItems.append(URLQueryItem(name: "code_challenge", value: pkceChallenge))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw SpotifyAuthorizationCoreError.invalidAuthorizationURL
        }
        return url
    }

    private static func isValidLoopbackRedirect(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "http",
              let host = components.host?.lowercased(),
              host == "127.0.0.1" || host == "::1",
              components.port != nil,
              !components.path.isEmpty else { return false }
        return true
    }
}

private enum SpotifyAuthorizationEntropy {
    static func makePKCEProof() throws -> SpotifyPKCEProof {
        let verifier = try randomURLSafeString(byteCount: 64)
        let digest = Data(SHA256.hash(data: Data(verifier.utf8)))
        return SpotifyPKCEProof(verifier: verifier, challenge: base64URL(digest))
    }

    static func randomURLSafeString(byteCount: Int) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SpotifyAuthorizationCoreError.invalidProof
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
