import AppKit
import Foundation

enum LocalSpotifySourceError: Error, Equatable, LocalizedError, Sendable {
    case notInstalled
    case notRunning
    case notPlaying
    case automationDenied
    case malformedResponse
    case unsupportedCommand
    case appleScriptFailed

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "尚未安装 Spotify。"
        case .notRunning:
            "Spotify 尚未运行。"
        case .notPlaying:
            "Spotify 当前没有正在播放的内容。"
        case .automationDenied:
            "Lyris 没有控制 Spotify 的自动化权限。"
        case .malformedResponse:
            "Spotify 返回了无法识别的播放信息。"
        case .unsupportedCommand:
            "此操作需要连接 Spotify 账户。"
        case .appleScriptFailed:
            "无法通过 macOS 自动化读取或控制 Spotify。"
        }
    }
}

enum LocalSpotifyPlayerState: String, Equatable, Sendable {
    case playing
    case paused
    case stopped
}

struct LocalSpotifyScriptSnapshot: Equatable, Sendable {
    let state: LocalSpotifyPlayerState
    let position: TimeInterval
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let spotifyURI: String
    let artworkURL: String
    let isShuffled: Bool
    let isRepeating: Bool
    let volumePercent: Double?

    init(
        state: LocalSpotifyPlayerState,
        position: TimeInterval,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        spotifyURI: String,
        artworkURL: String,
        isShuffled: Bool,
        isRepeating: Bool,
        volumePercent: Double? = nil
    ) {
        self.state = state
        self.position = position
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.spotifyURI = spotifyURI
        self.artworkURL = artworkURL
        self.isShuffled = isShuffled
        self.isRepeating = isRepeating
        self.volumePercent = volumePercent
    }
}

enum LocalSpotifyScriptCommand: Equatable, Sendable {
    case setPlaying(Bool)
    case previous
    case next
    case seek(TimeInterval)
    case setShuffle(Bool)
    case setRepeat(Bool)
    case setVolume(Double)
}

protocol LocalSpotifyScripting: Sendable {
    func readPlayback() async throws -> LocalSpotifyScriptSnapshot
    func perform(_ command: LocalSpotifyScriptCommand) async throws
}

enum LocalSpotifyDurationNormalizer {
    /// Spotify's scripting dictionary documents seconds, while current desktop builds
    /// have also returned milliseconds. The position and item kind disambiguate the
    /// practical cases without corrupting multi-hour podcasts that are genuinely seconds.
    static func seconds(
        from rawValue: TimeInterval,
        position: TimeInterval = 0,
        itemKind: PlaybackItemKind = .unknown
    ) -> TimeInterval {
        guard rawValue.isFinite, rawValue > 0 else { return 0 }
        let finitePosition = position.isFinite ? max(0, position) : 0
        let millisecondsCandidate = rawValue / 1_000
        let positionProvesSeconds = finitePosition > millisecondsCandidate + 5
        let stronglyLooksLikeMilliseconds = rawValue >= 86_400
            || (itemKind == .track && rawValue > 10_000)
        let normalized = stronglyLooksLikeMilliseconds && !positionProvesSeconds
            ? millisecondsCandidate
            : rawValue
        return min(normalized, 7 * 24 * 60 * 60)
    }
}

protocol LocalSpotifyAppleScriptExecuting: Sendable {
    func execute(source: String, arguments: [String]) async throws -> String
}

struct LocalSpotifyAppleScriptExecutionFailure: Error, Equatable, Sendable {
    let exitStatus: Int32
    let standardError: String
}

struct LocalSpotifyOSAScriptExecutor: LocalSpotifyAppleScriptExecuting {
    func execute(source: String, arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let output = Pipe()
            let errorOutput = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source, "--"] + arguments
            process.standardOutput = output
            process.standardError = errorOutput
            process.terminationHandler = { process in
                let stdout = output.fileHandleForReading.readDataToEndOfFile()
                let stderr = errorOutput.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus == 0 {
                    var rendered = String(decoding: stdout, as: UTF8.self)
                    if rendered.hasSuffix("\n") { rendered.removeLast() }
                    if rendered.hasSuffix("\r") { rendered.removeLast() }
                    continuation.resume(returning: rendered)
                } else {
                    continuation.resume(
                        throwing: LocalSpotifyAppleScriptExecutionFailure(
                            exitStatus: process.terminationStatus,
                            standardError: String(decoding: stderr, as: UTF8.self)
                        )
                    )
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

protocol LocalSpotifyApplicationInspecting: Sendable {
    func isSpotifyInstalled() -> Bool
    func isSpotifyRunning() -> Bool
}

struct SystemLocalSpotifyApplicationInspector: LocalSpotifyApplicationInspecting, @unchecked Sendable {
    private static let bundleIdentifier = "com.spotify.client"

    func isSpotifyInstalled() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) != nil
    }

    func isSpotifyRunning() -> Bool {
        !NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.bundleIdentifier
        ).isEmpty
    }
}

actor LocalSpotifyAppleScriptAdapter: LocalSpotifyScripting {
    static let fieldSeparator = String(UnicodeScalar(31))

    private let executor: any LocalSpotifyAppleScriptExecuting
    private let applicationInspector: any LocalSpotifyApplicationInspecting
    private var operationTail: Task<Void, Never>?

    init(
        executor: any LocalSpotifyAppleScriptExecuting = LocalSpotifyOSAScriptExecutor(),
        applicationInspector: any LocalSpotifyApplicationInspecting = SystemLocalSpotifyApplicationInspector()
    ) {
        self.executor = executor
        self.applicationInspector = applicationInspector
    }

    func readPlayback() async throws -> LocalSpotifyScriptSnapshot {
        try ensureSpotifyIsAvailable()
        let output: String
        do {
            output = try await executeSerialized(source: Self.readPlaybackScript, arguments: [])
        } catch {
            throw mapExecutionError(error)
        }
        return try Self.parsePlayback(output)
    }

    func perform(_ command: LocalSpotifyScriptCommand) async throws {
        try ensureSpotifyIsAvailable()
        let request = Self.request(for: command)
        do {
            _ = try await executeSerialized(source: request.source, arguments: request.arguments)
        } catch {
            throw mapExecutionError(error)
        }
    }

    private func executeSerialized(source: String, arguments: [String]) async throws -> String {
        let precedingOperation = operationTail
        let executor = self.executor
        let operation = Task<String, Error> {
            _ = await precedingOperation?.result
            try Task.checkCancellation()
            return try await executor.execute(source: source, arguments: arguments)
        }
        operationTail = Task { _ = await operation.result }
        return try await operation.value
    }

    private func ensureSpotifyIsAvailable() throws {
        guard applicationInspector.isSpotifyInstalled() else {
            throw LocalSpotifySourceError.notInstalled
        }
        guard applicationInspector.isSpotifyRunning() else {
            throw LocalSpotifySourceError.notRunning
        }
    }

    private func mapExecutionError(_ error: Error) -> LocalSpotifySourceError {
        if let sourceError = error as? LocalSpotifySourceError { return sourceError }
        guard let failure = error as? LocalSpotifyAppleScriptExecutionFailure else {
            return .appleScriptFailed
        }
        let diagnostic = failure.standardError
        if diagnostic.contains("(-1743)") { return .automationDenied }
        if diagnostic.contains("(-600)") { return .notRunning }
        if diagnostic.contains("(-1728)") { return .notPlaying }
        return .appleScriptFailed
    }

    private static func parsePlayback(_ output: String) throws -> LocalSpotifyScriptSnapshot {
        let fields = output.components(separatedBy: fieldSeparator)
        guard let stateField = fields.first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let state = LocalSpotifyPlayerState(rawValue: stateField) else {
            throw LocalSpotifySourceError.malformedResponse
        }
        guard state != .stopped else { throw LocalSpotifySourceError.notPlaying }
        guard fields.count == 11,
              let position = parseNumber(fields[1]),
              let duration = parseNumber(fields[5]),
              let isShuffled = parseBoolean(fields[8]),
              let isRepeating = parseBoolean(fields[9]),
              let volumePercent = parseNumber(fields[10]) else {
            throw LocalSpotifySourceError.malformedResponse
        }
        return LocalSpotifyScriptSnapshot(
            state: state,
            position: position,
            title: fields[2],
            artist: fields[3],
            album: fields[4],
            duration: duration,
            spotifyURI: fields[6],
            artworkURL: fields[7],
            isShuffled: isShuffled,
            isRepeating: isRepeating,
            volumePercent: volumePercent
        )
    }

    private static func parseNumber(_ value: String) -> Double? {
        if let number = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return number
        }
        let localizedDecimal = value.replacingOccurrences(of: ",", with: ".")
        return Double(localizedDecimal.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func parseBoolean(_ value: String) -> Bool? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1": true
        case "false", "no", "0": false
        default: nil
        }
    }

    private static func request(
        for command: LocalSpotifyScriptCommand
    ) -> (source: String, arguments: [String]) {
        switch command {
        case .setPlaying(true):
            return (playScript, [])
        case .setPlaying(false):
            return (pauseScript, [])
        case .previous:
            return (previousScript, [])
        case .next:
            return (nextScript, [])
        case .seek(let position):
            return (seekScript, [String(max(0, position.isFinite ? position : 0))])
        case .setShuffle(let enabled):
            return (shuffleScript, [String(enabled)])
        case .setRepeat(let enabled):
            return (repeatScript, [String(enabled)])
        case .setVolume(let level):
            let percent = Int((min(max(level, 0), 1) * 100).rounded())
            return (volumeScript, [String(percent)])
        }
    }

    private static let readPlaybackScript = #"""
    on safeText(candidate)
        try
            if candidate is missing value then return ""
            return candidate as text
        on error
            return ""
        end try
    end safeText

    on run argv
        tell application id "com.spotify.client"
            set playbackState to player state as text
            if playbackState is "stopped" then return playbackState
            set playbackItem to current track
            set separatorCharacter to ASCII character 31
            set itemTitle to my safeText(name of playbackItem)
            set itemArtist to my safeText(artist of playbackItem)
            set itemAlbum to my safeText(album of playbackItem)
            set itemDuration to my safeText(duration of playbackItem)
            set itemURI to my safeText(spotify url of playbackItem)
            set itemArtwork to my safeText(artwork url of playbackItem)
            return playbackState & separatorCharacter & (player position as text) & separatorCharacter & itemTitle & separatorCharacter & itemArtist & separatorCharacter & itemAlbum & separatorCharacter & itemDuration & separatorCharacter & itemURI & separatorCharacter & itemArtwork & separatorCharacter & (shuffling as text) & separatorCharacter & (repeating as text) & separatorCharacter & (sound volume as text)
        end tell
    end run
    """#

    private static let playScript = #"""
    on run argv
        tell application id "com.spotify.client" to play
    end run
    """#

    private static let pauseScript = #"""
    on run argv
        tell application id "com.spotify.client" to pause
    end run
    """#

    private static let previousScript = #"""
    on run argv
        tell application id "com.spotify.client" to previous track
    end run
    """#

    private static let nextScript = #"""
    on run argv
        tell application id "com.spotify.client" to next track
    end run
    """#

    private static let seekScript = #"""
    on run argv
        if (count of argv) is not 1 then error number -50
        set requestedPosition to (item 1 of argv) as real
        tell application id "com.spotify.client" to set player position to requestedPosition
    end run
    """#

    private static let shuffleScript = #"""
    on run argv
        if (count of argv) is not 1 then error number -50
        set requestedState to ((item 1 of argv) as text) is "true"
        tell application id "com.spotify.client" to set shuffling to requestedState
    end run
    """#

    private static let repeatScript = #"""
    on run argv
        if (count of argv) is not 1 then error number -50
        set requestedState to ((item 1 of argv) as text) is "true"
        tell application id "com.spotify.client" to set repeating to requestedState
    end run
    """#

    private static let volumeScript = #"""
    on run argv
        if (count of argv) is not 1 then error number -50
        set requestedVolume to (item 1 of argv) as integer
        if requestedVolume < 0 then set requestedVolume to 0
        if requestedVolume > 100 then set requestedVolume to 100
        tell application id "com.spotify.client" to set sound volume to requestedVolume
    end run
    """#
}

@MainActor
protocol LocalSpotifyScheduledTask: AnyObject {
    func cancel()
}

@MainActor
protocol LocalSpotifySourceScheduling: AnyObject {
    func schedule(
        every interval: TimeInterval,
        operation: @escaping () async -> Void
    ) -> any LocalSpotifyScheduledTask
}

@MainActor
final class LocalSpotifyTaskScheduler: LocalSpotifySourceScheduling {
    private final class TaskToken: LocalSpotifyScheduledTask {
        private var task: Task<Void, Never>?

        init(task: Task<Void, Never>) {
            self.task = task
        }

        func cancel() {
            task?.cancel()
            task = nil
        }

        deinit {
            task?.cancel()
        }
    }

    func schedule(
        every interval: TimeInterval,
        operation: @escaping () async -> Void
    ) -> any LocalSpotifyScheduledTask {
        let nanoseconds = UInt64(max(0.01, interval) * 1_000_000_000)
        let task = Task { @MainActor in
            while !Task.isCancelled {
                await operation()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
        return TaskToken(task: task)
    }
}

@MainActor
final class LocalSpotifyPlaybackSource: PlaybackAdapting {
    var onSnapshot: ((PlaybackSnapshot) -> Void)?
    var onAuthorizationState: ((SpotifyAuthorizationState) -> Void)?
    var onIssue: ((LocalSpotifySourceError) -> Void)?

    private enum MutationLane: Hashable {
        case playback
        case navigation
        case seek
        case shuffle
        case repeatMode
        case volume
    }

    private let scripting: any LocalSpotifyScripting
    private let scheduler: any LocalSpotifySourceScheduling
    private let monotonicNow: () -> TimeInterval
    private let pollInterval: TimeInterval
    private let projectionInterval: TimeInterval
    private var scheduledTasks: [any LocalSpotifyScheduledTask] = []
    private var sourceSnapshot: PlaybackSnapshot?
    private var latestSnapshot: PlaybackSnapshot?
    private var playbackClock = PlaybackClock()
    private var pollGeneration: UInt64 = 0
    private var lifecycleGeneration: UInt64 = 0
    private var mutationEpoch: UInt64 = 0
    private var mutationGenerations: [MutationLane: UInt64] = [:]
    private var mutationTasks: [MutationLane: Task<Void, Never>] = [:]

    init(
        scripting: any LocalSpotifyScripting = LocalSpotifyAppleScriptAdapter(),
        scheduler: (any LocalSpotifySourceScheduling)? = nil,
        pollInterval: TimeInterval = 0.75,
        projectionInterval: TimeInterval = 1.0 / 12.0,
        monotonicNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.scripting = scripting
        self.scheduler = scheduler ?? LocalSpotifyTaskScheduler()
        self.pollInterval = pollInterval
        self.projectionInterval = projectionInterval
        self.monotonicNow = monotonicNow
    }

    func start() {
        stop()
        lifecycleGeneration &+= 1
        scheduledTasks = [
            scheduler.schedule(every: pollInterval) { [weak self] in
                await self?.pollOnce()
            },
            scheduler.schedule(every: projectionInterval) { [weak self] in
                self?.publishProjection()
            },
        ]
    }

    func stop() {
        lifecycleGeneration &+= 1
        pollGeneration &+= 1
        mutationEpoch &+= 1
        scheduledTasks.forEach { $0.cancel() }
        scheduledTasks.removeAll()
        mutationTasks.values.forEach { $0.cancel() }
        mutationTasks.removeAll()
    }

    func send(_ command: PlaybackCommand) {
        if case .toggleLiked = command {
            onIssue?(.unsupportedCommand)
            return
        }
        guard let previousSnapshot = latestSnapshot else {
            onIssue?(.notPlaying)
            return
        }

        let lane = mutationLane(for: command)
        let generation = nextMutationGeneration(for: lane)
        mutationEpoch &+= 1
        let trackID = previousSnapshot.track.id
        let scriptCommand = optimisticCommand(command, from: previousSnapshot)

        mutationTasks[lane]?.cancel()
        let scripting = self.scripting
        let task = Task { [weak self] in
            do {
                try await scripting.perform(scriptCommand)
                self?.finishMutation(lane: lane, generation: generation, trackID: trackID)
            } catch is CancellationError {
                self?.finishMutation(lane: lane, generation: generation, trackID: trackID)
            } catch {
                self?.failMutation(
                    error,
                    command: command,
                    previousSnapshot: previousSnapshot,
                    lane: lane,
                    generation: generation,
                    trackID: trackID
                )
            }
        }
        mutationTasks[lane] = task
    }

    private func pollOnce() async {
        pollGeneration &+= 1
        let generation = pollGeneration
        let lifecycle = lifecycleGeneration
        let epoch = mutationEpoch
        do {
            let rawSnapshot = try await scripting.readPlayback()
            guard generation == pollGeneration,
                  lifecycle == lifecycleGeneration,
                  epoch == mutationEpoch,
                  mutationTasks.isEmpty else { return }
            let snapshot = try makeSnapshot(from: rawSnapshot)
            sourceSnapshot = snapshot
            playbackClock.apply(
                .source(
                    PlaybackClockSourceSample(
                        trackID: snapshot.track.id,
                        position: snapshot.position,
                        duration: snapshot.track.duration,
                        isPlaying: snapshot.isPlaying
                    )
                ),
                at: monotonicNow()
            )
            publishProjection()
        } catch is CancellationError {
            return
        } catch {
            guard generation == pollGeneration,
                  lifecycle == lifecycleGeneration,
                  epoch == mutationEpoch else { return }
            let issue = (error as? LocalSpotifySourceError) ?? .appleScriptFailed
            if issue == .notPlaying
                || issue == .notRunning
                || issue == .notInstalled
                || issue == .automationDenied {
                publishUnavailable(issue)
            }
            onIssue?(issue)
        }
    }

    private func makeSnapshot(from raw: LocalSpotifyScriptSnapshot) throws -> PlaybackSnapshot {
        guard raw.state != .stopped else { throw LocalSpotifySourceError.notPlaying }
        let itemKind = playbackItemKind(for: raw.spotifyURI)
        let duration = LocalSpotifyDurationNormalizer.seconds(
            from: raw.duration,
            position: raw.position,
            itemKind: itemKind
        )
        let position = normalizedPosition(raw.position, duration: duration)
        let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = raw.artist.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !raw.spotifyURI.isEmpty else {
            throw LocalSpotifySourceError.malformedResponse
        }
        let trackID = canonicalTrackID(
            spotifyURI: raw.spotifyURI,
            title: title,
            artist: artist,
            album: raw.album,
            duration: duration
        )
        return PlaybackSnapshot(
            track: Track(
                id: trackID,
                title: title,
                artist: artist,
                album: raw.album,
                duration: duration,
                artworkURL: artworkURL(from: raw.artworkURL),
                kind: itemKind
            ),
            position: position,
            isPlaying: raw.state == .playing,
            likedState: .unavailable,
            isShuffled: raw.isShuffled,
            repeatMode: raw.isRepeating ? .all : .off,
            volume: raw.volumePercent.map { min(max($0 / 100, 0), 1) },
            capabilities: .localCompanion,
            source: .local
        )
    }

    private func optimisticCommand(
        _ command: PlaybackCommand,
        from previousSnapshot: PlaybackSnapshot
    ) -> LocalSpotifyScriptCommand {
        switch command {
        case .togglePlayback:
            let desired = !previousSnapshot.isPlaying
            sourceSnapshot?.isPlaying = desired
            playbackClock.apply(.setPlaying(desired), at: monotonicNow())
            publishProjection()
            return .setPlaying(desired)
        case .previous:
            return .previous
        case .next:
            return .next
        case .seek(let requestedPosition):
            let position = normalizedPosition(
                requestedPosition,
                duration: previousSnapshot.track.duration
            )
            playbackClock.apply(.seek(to: position), at: monotonicNow())
            publishProjection()
            return .seek(position)
        case .toggleShuffle:
            let desired = !previousSnapshot.isShuffled
            sourceSnapshot?.isShuffled = desired
            publishProjection()
            return .setShuffle(desired)
        case .cycleRepeat:
            let desired = previousSnapshot.repeatMode == .off
            sourceSnapshot?.repeatMode = desired ? .all : .off
            publishProjection()
            return .setRepeat(desired)
        case .setVolume(let requestedLevel):
            let level = min(max(requestedLevel, 0), 1)
            sourceSnapshot?.volume = level
            publishProjection()
            return .setVolume(level)
        case .toggleLiked:
            preconditionFailure("Liked Songs is unavailable in Local Companion mode")
        }
    }

    private func finishMutation(
        lane: MutationLane,
        generation: UInt64,
        trackID: String
    ) {
        guard isCurrentMutation(lane: lane, generation: generation, trackID: trackID) else {
            return
        }
        mutationTasks[lane] = nil
        mutationEpoch &+= 1
    }

    private func failMutation(
        _ error: Error,
        command: PlaybackCommand,
        previousSnapshot: PlaybackSnapshot,
        lane: MutationLane,
        generation: UInt64,
        trackID: String
    ) {
        guard isCurrentMutation(lane: lane, generation: generation, trackID: trackID) else {
            return
        }
        mutationTasks[lane] = nil
        mutationEpoch &+= 1
        rollback(command, to: previousSnapshot)
        onIssue?((error as? LocalSpotifySourceError) ?? .appleScriptFailed)
    }

    private func rollback(_ command: PlaybackCommand, to snapshot: PlaybackSnapshot) {
        guard sourceSnapshot?.track.id == snapshot.track.id else { return }
        switch command {
        case .togglePlayback, .seek:
            playbackClock.apply(.clear, at: monotonicNow())
            playbackClock.apply(
                .source(
                    PlaybackClockSourceSample(
                        trackID: snapshot.track.id,
                        position: snapshot.position,
                        duration: snapshot.track.duration,
                        isPlaying: snapshot.isPlaying
                    )
                ),
                at: monotonicNow()
            )
            sourceSnapshot?.isPlaying = snapshot.isPlaying
        case .toggleShuffle:
            sourceSnapshot?.isShuffled = snapshot.isShuffled
        case .cycleRepeat:
            sourceSnapshot?.repeatMode = snapshot.repeatMode
        case .setVolume:
            sourceSnapshot?.volume = snapshot.volume
        case .previous, .next, .toggleLiked:
            break
        }
        publishProjection()
    }

    private func publishProjection() {
        guard var snapshot = sourceSnapshot else { return }
        snapshot.position = playbackClock.position(at: monotonicNow())
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
    }

    private func publishUnavailable(_ issue: LocalSpotifySourceError) {
        playbackClock.apply(.clear, at: monotonicNow())
        let snapshot = PlaybackSnapshot(
            track: Track(
                id: "spotify:idle",
                title: issue.errorDescription ?? "Spotify 当前不可用",
                artist: "Local Companion",
                album: "",
                duration: 1,
                kind: .unknown
            ),
            position: 0,
            isPlaying: false,
            likedState: .unavailable,
            isShuffled: false,
            repeatMode: .off,
            capabilities: [],
            source: .unavailable
        )
        sourceSnapshot = snapshot
        latestSnapshot = snapshot
        onSnapshot?(snapshot)
    }

    private func mutationLane(for command: PlaybackCommand) -> MutationLane {
        switch command {
        case .togglePlayback: .playback
        case .previous, .next: .navigation
        case .seek: .seek
        case .toggleShuffle: .shuffle
        case .cycleRepeat: .repeatMode
        case .setVolume: .volume
        case .toggleLiked: preconditionFailure("Liked Songs has no local mutation lane")
        }
    }

    private func nextMutationGeneration(for lane: MutationLane) -> UInt64 {
        let generation = (mutationGenerations[lane] ?? 0) &+ 1
        mutationGenerations[lane] = generation
        return generation
    }

    private func isCurrentMutation(
        lane: MutationLane,
        generation: UInt64,
        trackID: String
    ) -> Bool {
        mutationGenerations[lane] == generation && sourceSnapshot?.track.id == trackID
    }

    private func normalizedPosition(
        _ position: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        let finitePosition = position.isFinite ? max(0, position) : 0
        guard duration > 0 else { return finitePosition }
        return min(finitePosition, duration)
    }

    private func artworkURL(from rawValue: String) -> URL? {
        guard let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    private func playbackItemKind(for spotifyURI: String) -> PlaybackItemKind {
        let canonical = spotifyURI.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if canonical.hasPrefix("spotify:track:") { return .track }
        if canonical.hasPrefix("spotify:episode:") { return .episode }
        if canonical.hasPrefix("spotify:ad:") { return .advertisement }
        return .unknown
    }

    private func canonicalTrackID(
        spotifyURI: String,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval
    ) -> String {
        let uri = spotifyURI.trimmingCharacters(in: .whitespacesAndNewlines)
        if uri.hasPrefix("spotify:") { return uri }
        let fingerprint = [title, artist, album, String(Int(duration.rounded()))]
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
            .joined(separator: "\u{1f}")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in fingerprint.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return "spotify:local:\(String(hash, radix: 16))"
    }
}
