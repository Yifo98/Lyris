import Foundation

/// Migration adapter that presents Local Companion playback with optional
/// Spotify-account enrichment through the existing `PlaybackAdapting` seam.
///
/// Local owns playback whenever it has an active item. The Web adapter can
/// only add account state to the same canonical Spotify track; it never
/// replaces Local metadata, position, or transport state.
@MainActor
final class HybridPlaybackAdapter: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)? {
        didSet {
            if let lastPublishedSnapshot {
                onSnapshot?(lastPublishedSnapshot)
            }
        }
    }
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?

    private enum PlaybackRoute {
        case local
        case web
    }

    private struct WebSnapshotReceipt {
        let snapshot: PlaybackSnapshot
        let sourceEpoch: UInt64
    }

    private struct LocalWebAssociation {
        let localGeneration: UInt64
        let webSourceEpoch: UInt64
    }

    private let local: PlaybackAdapting
    private let web: PlaybackAdapting

    private var localSnapshot: PlaybackSnapshot?
    private var webReceipt: WebSnapshotReceipt?
    private var lastPublishedSnapshot: PlaybackSnapshot?
    private var localIdentity: String?
    private var localGeneration: UInt64 = 0
    private var observedLocalIdentities: Set<String> = []
    private var currentLocalIdentityIsRepeated = false
    private var webSourceIdentity: String?
    private var webSourceEpoch: UInt64 = 0
    private var webEpochAtLastLocalGeneration: UInt64 = 0
    private var localWebAssociation: LocalWebAssociation?

    init(local: PlaybackAdapting, web: PlaybackAdapting) {
        self.local = local
        self.web = web

        local.onSnapshot = { [weak self] snapshot in
            self?.receiveLocal(snapshot)
        }
        web.onSnapshot = { [weak self] snapshot in
            self?.receiveWeb(snapshot)
        }
        web.onAuthorizationState = { [weak self] state in
            self?.receiveWebAuthorizationState(state)
        }
    }

    func start() {
        local.start()
        web.start()
    }

    func send(_ command: PlaybackCommand) {
        if case .toggleLiked = command {
            guard canRouteLikedToWeb else {
                publishLikedRouteFailure()
                return
            }
            web.send(command)
            return
        }

        guard let route = playbackRoute,
              routeSupports(command, route: route) else { return }
        switch route {
        case .local:
            local.send(command)
        case .web:
            web.send(command)
        }
    }

    private func publishLikedRouteFailure() {
        guard var snapshot = lastPublishedSnapshot else { return }
        snapshot.likedState = .failed(
            lastKnown: snapshot.likedState.displayedValue
        )
        lastPublishedSnapshot = snapshot
        onSnapshot?(snapshot)
    }

    private func receiveLocal(_ snapshot: PlaybackSnapshot) {
        let hadLocalSnapshot = localSnapshot != nil
        let identity = generationIdentity(for: snapshot)
        if localSnapshot == nil || identity != localIdentity {
            let previousLocalWebEpoch = webEpochAtLastLocalGeneration
            let isRepeatedLocalIdentity = observedLocalIdentities.contains(identity)
            localGeneration &+= 1
            localIdentity = identity
            currentLocalIdentityIsRepeated = isRepeatedLocalIdentity
            localWebAssociation = nil

            if let webReceipt,
               canAssociate(
                   webReceipt,
                   with: snapshot,
                   isFirstLocalReceipt: !hadLocalSnapshot,
                   isRepeatedLocalIdentity: isRepeatedLocalIdentity,
                   webEpochAtPreviousLocalGeneration: previousLocalWebEpoch
               ) {
                localWebAssociation = LocalWebAssociation(
                    localGeneration: localGeneration,
                    webSourceEpoch: webReceipt.sourceEpoch
                )
            }
            observedLocalIdentities.insert(identity)
            webEpochAtLastLocalGeneration = webSourceEpoch
        }
        localSnapshot = snapshot
        publishReducedSnapshot()
    }

    private func receiveWeb(_ snapshot: PlaybackSnapshot) {
        let hadPreviousWebReceipt = webReceipt != nil
        let identity = generationIdentity(for: snapshot)
        let sourceAdvanced = webReceipt == nil || identity != webSourceIdentity
        if sourceAdvanced {
            webSourceEpoch &+= 1
            webSourceIdentity = identity
        }

        webReceipt = WebSnapshotReceipt(
            snapshot: snapshot,
            sourceEpoch: webSourceEpoch
        )
        associateCurrentLocalIfSafe(
            snapshot,
            sourceAdvanced: sourceAdvanced,
            hadPreviousWebReceipt: hadPreviousWebReceipt
        )
        publishReducedSnapshot()
    }

    private func receiveWebAuthorizationState(_ state: SpotifyAuthorizationState) {
        switch state {
        case .disconnected, .reauthorizationRequired:
            webReceipt = nil
            webSourceIdentity = nil
            localWebAssociation = nil
            publishReducedSnapshot()
        case .authorizing, .connected, .expiringSoon, .permissionRequired, .failed:
            break
        }
        onAuthorizationState?(state)
    }

    private func publishReducedSnapshot() {
        guard let reduced = reducedSnapshot() else { return }
        guard reduced != lastPublishedSnapshot else { return }
        lastPublishedSnapshot = reduced
        onSnapshot?(reduced)
    }

    private func reducedSnapshot() -> PlaybackSnapshot? {
        if let remotePlaybackSnapshot {
            return remotePlaybackSnapshot
        }

        if let localSnapshot, isActive(localSnapshot) {
            return enrichedLocalSnapshot(localSnapshot)
        }

        if let webSnapshot = currentWebSnapshot, isActive(webSnapshot) {
            return webSnapshot
        }

        if let localSnapshot {
            return localOnlySnapshot(localSnapshot)
        }

        return webReceipt?.snapshot
    }

    /// Spotify's AppleScript dictionary keeps the last local item after the
    /// listener moves playback to another device. In that state Local reports
    /// a paused, stale track while the account API reports the actively playing
    /// device. The playing Web receipt is therefore authoritative until Local
    /// starts playing again.
    private var remotePlaybackSnapshot: PlaybackSnapshot? {
        guard let localSnapshot,
              isActive(localSnapshot),
              !localSnapshot.isPlaying,
              let webSnapshot = webReceipt?.snapshot,
              isActive(webSnapshot),
              webSnapshot.isPlaying else { return nil }
        return webSnapshot
    }

    private func enrichedLocalSnapshot(_ localSnapshot: PlaybackSnapshot) -> PlaybackSnapshot {
        var result = localOnlySnapshot(localSnapshot)
        guard let webSnapshot = currentWebSnapshot,
              isActive(webSnapshot),
              tracksMatch(localSnapshot.track, webSnapshot.track) else {
            return result
        }

        let accountCapabilities = webSnapshot.capabilities.intersection(.hybridAccountEnhancements)
        result.capabilities.formUnion(accountCapabilities)
        result.source = accountCapabilities.isEmpty ? .local : .hybrid
        if accountCapabilities.contains(.likedSongsRead) {
            result.likedState = webSnapshot.likedState
        }
        return result
    }

    private func localOnlySnapshot(_ snapshot: PlaybackSnapshot) -> PlaybackSnapshot {
        var result = snapshot
        result.likedState = .unavailable
        result.capabilities.subtract(.hybridAccountEnhancements)
        result.source = isActive(snapshot) ? .local : .unavailable
        return result
    }

    /// Web identity changes form a monotonically increasing source epoch. A
    /// Local generation can consume a receipt only when it is explicitly
    /// associated with that epoch. This matters for A -> B -> A: an old A
    /// callback has the original Web epoch, so matching the new Local A's track
    /// ID is not enough to re-associate it. The Web source must first advance
    /// from an observed prior identity; even a first Web A receipt is held back
    /// for a repeated Local A. SpotifyPlaybackAdapter publishes accepted polls
    /// in order, making a later B -> A source transition the causal fence.
    private var currentWebSnapshot: PlaybackSnapshot? {
        guard let webReceipt else { return nil }
        guard localSnapshot != nil else { return webReceipt.snapshot }
        guard localWebAssociation?.localGeneration == localGeneration,
              localWebAssociation?.webSourceEpoch == webReceipt.sourceEpoch else { return nil }
        return webReceipt.snapshot
    }

    private func associateCurrentLocalIfSafe(
        _ webSnapshot: PlaybackSnapshot,
        sourceAdvanced: Bool,
        hadPreviousWebReceipt: Bool
    ) {
        guard let localSnapshot else {
            localWebAssociation = nil
            return
        }

        if !isActive(localSnapshot) {
            localWebAssociation = LocalWebAssociation(
                localGeneration: localGeneration,
                webSourceEpoch: webSourceEpoch
            )
            return
        }

        if sourceAdvanced,
           tracksMatch(localSnapshot.track, webSnapshot.track),
           !currentLocalIdentityIsRepeated || hadPreviousWebReceipt {
            localWebAssociation = LocalWebAssociation(
                localGeneration: localGeneration,
                webSourceEpoch: webSourceEpoch
            )
            return
        }

        guard localWebAssociation?.localGeneration == localGeneration,
              localWebAssociation?.webSourceEpoch == webSourceEpoch else {
            localWebAssociation = nil
            return
        }
    }

    private func canAssociate(
        _ webReceipt: WebSnapshotReceipt,
        with localSnapshot: PlaybackSnapshot,
        isFirstLocalReceipt: Bool,
        isRepeatedLocalIdentity: Bool,
        webEpochAtPreviousLocalGeneration: UInt64
    ) -> Bool {
        if !isActive(localSnapshot) { return true }
        guard tracksMatch(localSnapshot.track, webReceipt.snapshot.track) else { return false }
        guard !isRepeatedLocalIdentity else { return false }
        return isFirstLocalReceipt || webReceipt.sourceEpoch > webEpochAtPreviousLocalGeneration
    }

    private var playbackRoute: PlaybackRoute? {
        if remotePlaybackSnapshot != nil {
            return .web
        }
        if let localSnapshot, isActive(localSnapshot) {
            return .local
        }
        if let webSnapshot = currentWebSnapshot, isActive(webSnapshot) {
            return .web
        }
        return nil
    }

    private var canRouteLikedToWeb: Bool {
        guard let published = lastPublishedSnapshot,
              published.capabilities.contains(.likedSongsWrite) else { return false }

        if let remotePlaybackSnapshot {
            return published.track.id == remotePlaybackSnapshot.track.id
        }

        guard let webSnapshot = currentWebSnapshot,
              isActive(webSnapshot) else { return false }

        if let localSnapshot, isActive(localSnapshot) {
            return tracksMatch(localSnapshot.track, webSnapshot.track)
        }
        return published.track.id == webSnapshot.track.id
    }

    private func routeSupports(_ command: PlaybackCommand, route: PlaybackRoute) -> Bool {
        let capabilities: PlaybackCapabilities?
        switch route {
        case .local:
            capabilities = localSnapshot?.capabilities
        case .web:
            capabilities = remotePlaybackSnapshot?.capabilities
                ?? currentWebSnapshot?.capabilities
        }
        guard let capabilities else { return false }

        switch command {
        case .togglePlayback, .previous, .next:
            return capabilities.contains(.transport)
        case .seek:
            return capabilities.contains(.seek)
        case .toggleShuffle:
            return capabilities.contains(.shuffle)
        case .cycleRepeat:
            return capabilities.contains(.repeatMode)
        case .setVolume:
            return capabilities.contains(.volume)
        case .toggleLiked:
            return false
        }
    }

    private func isActive(_ snapshot: PlaybackSnapshot) -> Bool {
        snapshot.track.id != "spotify:idle"
    }

    private func generationIdentity(for snapshot: PlaybackSnapshot) -> String {
        if !isActive(snapshot) { return "spotify:idle" }
        return SpotifyTrackURI.canonical(snapshot.track.id) ?? snapshot.track.id
    }

    private func tracksMatch(_ lhs: Track, _ rhs: Track) -> Bool {
        guard let left = SpotifyTrackURI.canonical(lhs.id),
              let right = SpotifyTrackURI.canonical(rhs.id) else { return false }
        return left == right
    }
}

private extension PlaybackCapabilities {
    static let hybridAccountEnhancements: Self = [
        .likedSongsRead,
        .likedSongsWrite,
    ]
}

enum SpotifyTrackURI {
    static func canonical(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if components.count == 3,
           components[0].lowercased() == "spotify",
           components[1].lowercased() == "track",
           isValidTrackID(components[2]) {
            return "spotify:track:\(components[2])"
        }

        guard let url = URL(string: trimmed),
              url.host?.lowercased() == "open.spotify.com" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        guard let trackIndex = path.firstIndex(where: { $0.lowercased() == "track" }),
              path.indices.contains(trackIndex + 1),
              isValidTrackID(Substring(path[trackIndex + 1])) else { return nil }
        return "spotify:track:\(path[trackIndex + 1])"
    }

    private static func isValidTrackID(_ value: Substring) -> Bool {
        !value.isEmpty && value.allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_")
        }
    }
}
