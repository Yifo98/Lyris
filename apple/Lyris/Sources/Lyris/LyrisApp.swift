import AppKit
import SwiftUI

@MainActor
final class LyrisRuntime: ObservableObject {
    static let shared = LyrisRuntime()
    @Published var store: LyrisStore?
    let surfaceVisibility = LyrisSurfaceVisibility()

    private init() {}
}

@main
struct LyrisApp: App {
    @NSApplicationDelegateAdaptor(LyrisAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            LyrisSettingsRootView(runtime: .shared)
        }
    }
}

@MainActor
final class LyrisAppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: LyrisWindowController?
    private var store: LyrisStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        LyrisDataLocation.prepareSharedURLCache()
        if let appIcon = LyrisAssets.appIcon {
            NSApp.applicationIconImage = appIcon
        }

        let arguments = Set(ProcessInfo.processInfo.arguments)
        let isDemo = arguments.contains("--demo")
        let defaults: UserDefaults
        if isDemo, let demoDefaults = UserDefaults(suiteName: "Lyris.VisualQA") {
            demoDefaults.removePersistentDomain(forName: "Lyris.VisualQA")
            defaults = demoDefaults
        } else {
            defaults = .standard
        }

        let vault: CredentialVault = isDemo
            ? LyrisDemoCredentialVault()
            : KeychainCredentialVault(defaults: defaults)
        let broker = SpotifySessionBroker(
            credentialVault: vault,
            persistentSessionDefaults: defaults
        )
        let playbackAdapter: PlaybackAdapting
        let spotifyAuthorizer: SpotifyAuthorizing
        let refreshAccountState: () -> Void

        if isDemo {
            playbackAdapter = DemoPlaybackAdapter()
            spotifyAuthorizer = LyrisDemoSpotifyAuthorizer()
            refreshAccountState = {}
        } else {
            let authorizationRuntime = SpotifyAuthorizationRuntime(
                sessionBroker: broker,
                credentialVault: vault,
                defaults: defaults
            )
            let localPlayback = LocalSpotifyPlaybackSource()
            let accountPlayback = SpotifyPlaybackAdapter(
                sessionBroker: broker,
                accountProvider: authorizationRuntime
            )
            authorizationRuntime.onAuthorizationChanged = { [weak accountPlayback] in
                accountPlayback?.requestImmediateAccountRefresh()
            }
            playbackAdapter = HybridPlaybackAdapter(
                local: localPlayback,
                web: accountPlayback
            )
            spotifyAuthorizer = authorizationRuntime
            refreshAccountState = { [weak accountPlayback] in
                accountPlayback?.requestImmediateAccountRefresh()
            }
        }

        let store = LyrisStore(
            playbackAdapter: playbackAdapter,
            lyricsProvider: isDemo ? DemoLyricsProvider() : LRCLibLyricsProvider(),
            translationAdapter: HTTPTranslationAdapter(),
            spotifyAuthorizer: spotifyAuthorizer,
            credentialVault: vault,
            defaults: defaults
        )
        if isDemo {
            store.finishFirstUseLater()
            #if DEBUG
            if arguments.contains("--qa-translation-models") {
                store.loadTranslationModelsForQA([
                    "deepseek-v4-flash",
                    "deepseek-v4-pro",
                    "deepseek-reasoner",
                ])
            }
            #endif
        }
        store.onSpotifyAccountStateRefreshRequested = refreshAccountState

        let controller = LyrisWindowController(
            store: store,
            refreshAccountState: refreshAccountState,
            surfaceVisibility: LyrisRuntime.shared.surfaceVisibility
        )
        self.store = store
        LyrisRuntime.shared.store = store
        windowController = controller
        controller.show()

        #if DEBUG
        if arguments.contains("--qa-static")
            || arguments.contains("--qa-popover")
            || arguments.contains("--qa-island-expanded") {
            Task { @MainActor [weak store, weak controller] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                if store?.playback.isPlaying == true {
                    store?.send(.togglePlayback)
                }
                if arguments.contains("--qa-popover") {
                    controller?.showMenuPopover()
                }
                if arguments.contains("--qa-island-expanded") {
                    controller?.expandTopPlayerForQA()
                }
            }
        }
        #endif
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        windowController?.showMainWindow()
        return true
    }
}

private final class LyrisDemoCredentialVault: CredentialVault {
    private var values: [String: String] = [:]

    func read(account: String) throws -> String? { values[account] }
    func write(_ secret: String, account: String) throws { values[account] = secret }
    func delete(account: String) throws { values.removeValue(forKey: account) }
}

private struct LyrisDemoSpotifyAuthorizer: SpotifyAuthorizing {
    func configuredProfile() throws -> SpotifyAuthorizationProfile? { nil }

    func saveConfiguration(
        clientID: String,
        redirectURI: String
    ) throws -> SpotifyAuthorizationProfile {
        SpotifyAuthorizationProfile(
            displayName: "Visual QA",
            clientID: clientID,
            redirectURI: redirectURI
        )
    }

    func restoreConnection(
        clientID: String,
        redirectURI: String
    ) async throws -> SpotifyConnectionReport? { nil }

    func authorize(
        clientID: String,
        redirectURI: String
    ) async throws -> SpotifyConnectionReport {
        SpotifyConnectionReport(displayName: "Visual QA")
    }
}
