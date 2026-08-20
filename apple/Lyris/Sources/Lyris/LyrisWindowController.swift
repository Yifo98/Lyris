import AppKit
import Combine
import QuartzCore
import SwiftUI

private final class LyrisTopPanel: NSPanel {
    override func constrainFrameRect(
        _ frameRect: NSRect,
        to screen: NSScreen?
    ) -> NSRect {
        // NSWindow normally pushes borderless windows below the menu bar and
        // camera housing. This panel is intentionally anchored to the physical
        // display edge so its compact state occupies the existing black notch
        // instead of creating a second capsule underneath it.
        frameRect
    }
}

final class LyrisIslandHostingView<Content: View>: NSHostingView<Content> {
    private let onPointerEntered: () -> Void
    private let onPointerExited: () -> Void
    private let onPointerClicked: () -> Void
    private let capturesAllClicks: () -> Bool
    private var islandTrackingArea: NSTrackingArea?

    init(
        rootView: Content,
        onPointerEntered: @escaping () -> Void,
        onPointerExited: @escaping () -> Void,
        onPointerClicked: @escaping () -> Void,
        capturesAllClicks: @escaping () -> Bool
    ) {
        self.onPointerEntered = onPointerEntered
        self.onPointerExited = onPointerExited
        self.onPointerClicked = onPointerClicked
        self.capturesAllClicks = capturesAllClicks
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init(rootView: Content) {
        fatalError("Use init(rootView:onPointerEntered:onPointerExited:)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let islandTrackingArea {
            removeTrackingArea(islandTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [
                .mouseEnteredAndExited,
                .mouseMoved,
                .activeAlways,
                .inVisibleRect,
            ],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        islandTrackingArea = area
        super.updateTrackingAreas()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        if capturesAllClicks() {
            return self
        }
        return super.hitTest(point) ?? self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseEntered(with event: NSEvent) {
        onPointerEntered()
    }

    override func mouseExited(with event: NSEvent) {
        onPointerExited()
    }

    override func mouseDown(with event: NSEvent) {
        onPointerClicked()
        super.mouseDown(with: event)
    }
}

struct LyrisScreenMetrics: Equatable {
    let frame: CGRect
    let visibleFrame: CGRect
    let safeAreaTop: CGFloat
    let auxiliaryTopLeftArea: CGRect?
    let auxiliaryTopRightArea: CGRect?
}

struct LyrisTopPlayerConfiguration: Equatable {
    let hostSize: CGSize
    let cameraInset: CGFloat
    let cameraWidth: CGFloat
    let hasCameraHousing: Bool
}

enum LyrisIslandState: Equatable {
    case compact
    case expanded
}

enum LyrisStatusItemPrimaryAction: Equatable {
    case expandIsland
    case togglePopover
}

enum LyrisStatusItemActionPolicy {
    static func primaryAction(
        mode: FloatingPresentationMode,
        islandState: LyrisIslandState,
        trigger: MacIslandExpansionTrigger
    ) -> LyrisStatusItemPrimaryAction {
        if mode == .topIsland,
           islandState == .compact,
           trigger.allowsClick {
            return .expandIsland
        }
        return .togglePopover
    }
}

struct LyrisFloatingSurfacePolicy: Equatable {
    enum WindowBehavior: Equatable {
        case notchAttached
        case movableBar
        case desktopLyrics
    }

    let mode: FloatingPresentationMode

    var windowBehavior: WindowBehavior {
        switch mode {
        case .topIsland: .notchAttached
        case .floatingCard: .movableBar
        case .desktopLyrics: .desktopLyrics
        }
    }

    var autoCollapses: Bool { mode == .topIsland }

    var displayedState: LyrisIslandState {
        mode == .topIsland ? .compact : .expanded
    }
}

struct LyrisFloatingSurfaceTransitionPlan: Equatable {
    let mode: FloatingPresentationMode

    var showsTopPanel: Bool { mode != .desktopLyrics }
    var showsMainWindow: Bool { mode == .desktopLyrics }
    var topPanelIsMovable: Bool { mode == .floatingCard }

    var targetIslandState: LyrisIslandState? {
        switch mode {
        case .topIsland: .compact
        case .floatingCard: .expanded
        case .desktopLyrics: nil
        }
    }
}

struct LyrisFloatingSurfaceModeState: Equatable {
    private(set) var activeMode: FloatingPresentationMode

    init(initialMode: FloatingPresentationMode) {
        activeMode = initialMode
    }

    mutating func apply(publishedMode: FloatingPresentationMode) -> LyrisFloatingSurfaceTransitionPlan {
        activeMode = publishedMode
        return LyrisFloatingSurfaceTransitionPlan(mode: publishedMode)
    }
}

struct LyrisHoverDwellTracker: Equatable {
    private var enteredUptime: TimeInterval?

    mutating func shouldExpand(
        isInside: Bool,
        uptime: TimeInterval,
        delay: TimeInterval
    ) -> Bool {
        guard isInside else {
            reset()
            return false
        }
        let normalizedDelay = delay.isFinite ? max(0, delay) : 0
        guard normalizedDelay > 0 else {
            enteredUptime = uptime
            return true
        }
        guard let enteredUptime else {
            self.enteredUptime = uptime
            return false
        }
        return uptime - enteredUptime >= normalizedDelay
    }

    mutating func reset() {
        enteredUptime = nil
    }
}

enum LyrisCompactLyricProjection {
    static func text(
        mode: MenuBarLyricMode,
        original: String,
        translated: String?
    ) -> String {
        let normalizedTranslation = translated?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .original:
            return original
        case .translated:
            return normalizedTranslation.flatMap { $0.isEmpty ? nil : $0 } ?? original
        case .bilingual:
            guard let normalizedTranslation,
                  !normalizedTranslation.isEmpty,
                  normalizedTranslation != original else { return original }
            return "\(original) · \(normalizedTranslation)"
        }
    }
}

@MainActor
final class LyrisIslandModel: ObservableObject {
    @Published private(set) var state: LyrisIslandState = .compact
    @Published private(set) var isLockedOpen = false
    @Published private(set) var configuration = LyrisTopPlayerConfiguration(
        hostSize: CGSize(width: 820, height: 92),
        cameraInset: 0,
        cameraWidth: 0,
        hasCameraHousing: false
    )

    private var expansionTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    func update(configuration: LyrisTopPlayerConfiguration) {
        self.configuration = configuration
    }

    func expand() {
        expansionTask?.cancel()
        expansionTask = nil
        collapseTask?.cancel()
        state = .expanded
    }

    func expand(after delay: TimeInterval) {
        collapseTask?.cancel()
        guard state == .compact else { return }
        guard delay > 0 else {
            expand()
            return
        }
        guard expansionTask == nil else { return }
        expansionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(max(0, delay) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.expansionTask = nil
            self?.state = .expanded
        }
    }

    func cancelPendingExpansion() {
        expansionTask?.cancel()
        expansionTask = nil
    }

    func toggleLockedOpen() {
        setLockedOpen(!isLockedOpen)
    }

    func setLockedOpen(_ locked: Bool) {
        cancelPendingExpansion()
        collapseTask?.cancel()
        isLockedOpen = locked
        if locked {
            state = .expanded
        }
    }

    func collapse(after delay: TimeInterval = 0.65) {
        guard !isLockedOpen else { return }
        cancelPendingExpansion()
        collapseTask?.cancel()
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64(max(0, delay) * 1_000_000_000)
            )
            guard !Task.isCancelled else { return }
            self?.state = .compact
        }
    }

    func collapseImmediately(force: Bool = false) {
        guard force || !isLockedOpen else { return }
        cancelPendingExpansion()
        collapseTask?.cancel()
        state = .compact
    }

    func collapseByUserRequest() {
        cancelPendingExpansion()
        collapseTask?.cancel()
        isLockedOpen = false
        state = .compact
    }
}

struct LyrisCompactOuterClosureGeometry: Equatable {
    let leftBottom: CGPoint
    let rightBottom: CGPoint
    let rightTopControl: CGPoint
    let rightBottomControl: CGPoint
    let leftBottomControl: CGPoint
    let leftTopControl: CGPoint
}

enum LyrisTopPlayerGeometry {
    static let preferredWidth: CGFloat = 1_080
    static let minimumWidth: CGFloat = 900
    static let bodyHeight: CGFloat = 132
    // The compact state stays visually attached to the hardware camera
    // housing. The larger information hierarchy belongs to the downward
    // expansion, not to a menu-bar-wide strip.
    // The compact island is a single centered composition. Both information
    // wings use the same width so the artwork/title group, camera housing,
    // waveform, and lower lyric shelf all share one physical center axis.
    // 140pt keeps the complete shell close to the approved reference's
    // screen-width ratio without letting either wing drift into unrelated
    // menu-bar items.
    static let compactWingWidth: CGFloat = 140
    // The lyric shelf is deliberately deeper than the 32pt camera band. It
    // remains a compact glance surface, but gives the active lyric enough
    // vertical breathing room to be read at real menu-bar scale.
    static let compactShelfDepth: CGFloat = 24
    static let compactLyricShelfWidth: CGFloat = 250
    static let compactLyricFontSize: CGFloat = 11.5
    // Keep the antialiased end caps one point inside the SwiftUI clip bounds,
    // so neither side is visually sliced by the host view edge.
    static let compactEndCapInset: CGFloat = 1
    // The approved compact reference keeps the lower lyric shelf close to
    // half of the complete silhouette width. A short inset creates the soft
    // V-shaped shoulder without pinching the shelf into a narrow tab.
    static let compactShelfShoulderInset: CGFloat = 22
    // The outer closure narrows by roughly 29pt across the 32pt camera band.
    // Shift both wing contents half that distance toward the camera so cover
    // art and the effect mark remain inside the curved silhouette.
    static let compactWingContentSafeOffset: CGFloat = 15
    static let compactExternalWidth: CGFloat = 480
    static let externalTopInset: CGFloat = 8
    static let horizontalScreenInset: CGFloat = 32
    static let compactHoverSideInset: CGFloat = 12
    static let compactHoverDepth: CGFloat = 10

    static var compactShoulderSlope: CGFloat {
        compactShelfShoulderInset / compactShelfDepth
    }

    static func compactOuterClosureInset(topBandHeight: CGFloat) -> CGFloat {
        max(0, topBandHeight) * compactShoulderSlope
    }

    static func compactShoulderControlDistance(for inset: CGFloat) -> CGFloat {
        min(10, max(4, max(0, inset) * 0.65))
    }

    static func compactOuterClosureGeometry(
        in bounds: CGRect,
        topBandBottom: CGFloat
    ) -> LyrisCompactOuterClosureGeometry {
        let topBandHeight = max(0, topBandBottom - bounds.minY)
        let inset = min(
            compactOuterClosureInset(topBandHeight: topBandHeight),
            bounds.width / 4
        )
        let control = compactShoulderControlDistance(for: inset)
        let leftBottom = CGPoint(x: bounds.minX + inset, y: topBandBottom)
        let rightBottom = CGPoint(x: bounds.maxX - inset, y: topBandBottom)
        return LyrisCompactOuterClosureGeometry(
            leftBottom: leftBottom,
            rightBottom: rightBottom,
            rightTopControl: CGPoint(
                x: bounds.maxX - control,
                y: bounds.minY
            ),
            rightBottomControl: CGPoint(
                x: rightBottom.x + control,
                y: topBandBottom
            ),
            leftBottomControl: CGPoint(
                x: leftBottom.x - control,
                y: topBandBottom
            ),
            leftTopControl: CGPoint(
                x: bounds.minX + control,
                y: bounds.minY
            )
        )
    }

    static func configuration(
        for metrics: LyrisScreenMetrics
    ) -> LyrisTopPlayerConfiguration {
        let hasCameraHousing = usesCameraHousing(metrics)
        let cameraInset = hasCameraHousing ? max(0, metrics.safeAreaTop) : 0
        let cameraWidth: CGFloat
        if hasCameraHousing,
           let left = metrics.auxiliaryTopLeftArea,
           let right = metrics.auxiliaryTopRightArea {
            cameraWidth = max(0, right.minX - left.maxX)
        } else {
            cameraWidth = 0
        }
        let availableWidth = max(0, metrics.frame.width - horizontalScreenInset * 2)
        let width = min(
            max(minimumWidth, availableWidth),
            min(preferredWidth, metrics.frame.width)
        )
        return LyrisTopPlayerConfiguration(
            hostSize: CGSize(width: width, height: bodyHeight + cameraInset),
            cameraInset: cameraInset,
            cameraWidth: cameraWidth,
            hasCameraHousing: hasCameraHousing
        )
    }

    static func frame(
        configuration: LyrisTopPlayerConfiguration,
        metrics: LyrisScreenMetrics,
        state: LyrisIslandState = .expanded
    ) -> CGRect {
        let size = visualSize(configuration: configuration, state: state)
        let reference = configuration.hasCameraHousing
            ? metrics.frame
            : usableFrame(metrics)
        if state == .compact, configuration.hasCameraHousing {
            return CGRect(
                x: reference.midX - size.width / 2,
                y: reference.maxY - size.height,
                width: size.width,
                height: size.height
            ).integral
        }
        let topInset = configuration.hasCameraHousing ? 0 : externalTopInset
        return CGRect(
            x: reference.midX - size.width / 2,
            y: reference.maxY - topInset - size.height,
            width: size.width,
            height: size.height
        ).integral
    }

    static func visualSize(
        configuration: LyrisTopPlayerConfiguration,
        state: LyrisIslandState
    ) -> CGSize {
        switch state {
        case .compact:
            CGSize(
                width: configuration.hasCameraHousing
                    ? configuration.cameraWidth
                        + compactWingWidth * 2
                    : compactExternalWidth,
                height: configuration.hasCameraHousing
                    ? max(configuration.cameraInset + compactShelfDepth, 1)
                    : 36
            )
        case .expanded:
            configuration.hostSize
        }
    }

    static func compactContentWidth(
        configuration: LyrisTopPlayerConfiguration
    ) -> CGFloat {
        configuration.hasCameraHousing
            ? compactWingWidth * 2
            : compactExternalWidth
    }

    static func panelFrame(
        configuration: LyrisTopPlayerConfiguration,
        metrics: LyrisScreenMetrics,
        state: LyrisIslandState
    ) -> CGRect {
        var result = frame(
            configuration: configuration,
            metrics: metrics,
            state: state
        )
        guard state == .compact, configuration.hasCameraHousing else {
            return result
        }
        result.origin.x -= compactHoverSideInset
        result.origin.y -= compactHoverDepth
        result.size.width += compactHoverSideInset * 2
        result.size.height += compactHoverDepth
        return result.integral
    }

    static func floatingCardFrame(
        metrics: LyrisScreenMetrics,
        savedOrigin: CGPoint? = nil
    ) -> CGRect {
        let usable = usableFrame(metrics)
        let width = min(820, max(620, usable.width - horizontalScreenInset * 2))
        let size = CGSize(width: width, height: bodyHeight)
        if let savedOrigin {
            let candidate = CGRect(origin: savedOrigin, size: size)
            if usable.intersection(candidate).width >= min(320, size.width * 0.5),
               usable.intersection(candidate).height >= 44 {
                return candidate.integral
            }
        }
        return CGRect(
            x: usable.midX - size.width / 2,
            y: usable.maxY - size.height - 24,
            width: size.width,
            height: size.height
        ).integral
    }

    private static func usesCameraHousing(_ metrics: LyrisScreenMetrics) -> Bool {
        guard metrics.safeAreaTop > 0,
              let left = metrics.auxiliaryTopLeftArea,
              let right = metrics.auxiliaryTopRightArea else {
            return false
        }
        return right.minX > left.maxX
    }

    private static func usableFrame(_ metrics: LyrisScreenMetrics) -> CGRect {
        let visible = metrics.visibleFrame.intersection(metrics.frame)
        return visible.isNull || visible.isEmpty ? metrics.frame : visible
    }
}

enum LyrisWindowPlacementPolicy {
    static let topPlayerGap: CGFloat = 16

    static func mainWindowFrame(
        windowSize requestedSize: CGSize,
        visibleFrame: CGRect,
        topPlayerFrame: CGRect
    ) -> CGRect {
        let size = CGSize(
            width: min(requestedSize.width, visibleFrame.width),
            height: min(requestedSize.height, visibleFrame.height)
        )
        let centeredX = visibleFrame.midX - size.width / 2
        let unobscuredTop = min(
            visibleFrame.maxY,
            topPlayerFrame.minY - topPlayerGap
        )
        let y = max(visibleFrame.minY, unobscuredTop - size.height)
        return CGRect(
            x: min(max(centeredX, visibleFrame.minX), visibleFrame.maxX - size.width),
            y: y,
            width: size.width,
            height: size.height
        ).integral
    }
}

@MainActor
final class LyrisWindowController: NSObject, NSWindowDelegate {
    private let store: LyrisStore
    private let refreshAccountState: () -> Void
    private let islandModel = LyrisIslandModel()
    private let mainWindow: NSWindow
    private let topPanel: NSPanel
    private var settingsWindow: NSWindow?
    private let popover = NSPopover()
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.squareLength
    )
    private var screenObserver: NSObjectProtocol?
    private var pointerTrackingTimer: Timer?
    private var collapseWasRequested = false
    private var hoverDwellTracker = LyrisHoverDwellTracker()
    private var isApplyingFloatingPresentationMode = false
    private var floatingSurfaceModeState: LyrisFloatingSurfaceModeState
    private var hasEstablishedMainWindowFrame = false
    private var cancellables = Set<AnyCancellable>()
    private var topPlayerMetrics: LyrisScreenMetrics?
    private weak var topPlayerScreen: NSScreen?

    init(
        store: LyrisStore,
        refreshAccountState: @escaping () -> Void
    ) {
        self.store = store
        self.refreshAccountState = refreshAccountState
        floatingSurfaceModeState = LyrisFloatingSurfaceModeState(
            initialMode: store.floatingPresentationMode
        )
        mainWindow = Self.makeMainWindow()
        topPanel = Self.makeTopPanel()
        super.init()

        mainWindow.delegate = self
        topPanel.delegate = self
        mainWindow.contentView = NSHostingView(
            rootView: LyrisMainWindowView(store: store)
        )
        hasEstablishedMainWindowFrame = mainWindow.setFrameUsingName(
            Self.mainWindowFrameAutosaveName
        )
        mainWindow.setFrameAutosaveName(Self.mainWindowFrameAutosaveName)
        configureStatusItem()
        configurePopover()
        store.onSettingsRequested = { [weak self] _ in
            self?.showSettingsWindow()
        }
        store.onMainWindowRequested = { [weak self] in
            self?.showMainWindow()
        }
        applyFloatingPresentationMode(store.floatingPresentationMode)
        configurePointerTrackingFallback()

        islandModel.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self, !self.isApplyingFloatingPresentationMode else { return }
                self.updateTopPlayerFrame(for: state, animated: true)
            }
            .store(in: &cancellables)

        store.$floatingPresentationMode
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] publishedMode in
                // `@Published` emits from `willSet`; consume the emitted mode
                // directly instead of rereading the store's previous value.
                self?.applyFloatingPresentationMode(publishedMode)
            }
            .store(in: &cancellables)


        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateTopPlayer()
            }
        }
    }

    deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        pointerTrackingTimer?.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func show() {
        switch floatingSurfaceModeState.activeMode {
        case .desktopLyrics:
            showMainWindow()
        case .topIsland, .floatingCard:
            updateTopPlayer()
        }
    }

    func showMainWindow() {
        refreshAccountState()
        if !hasEstablishedMainWindowFrame {
            placeMainWindowAvoidingTopPlayer()
            hasEstablishedMainWindowFrame = true
        }
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
    }

    func showMenuPopover() {
        guard let button = statusItem.button else { return }
        refreshAccountState()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    #if DEBUG
    func expandTopPlayerForQA() {
        guard floatingSurfaceModeState.activeMode == .topIsland else { return }
        store.updateMacIslandExpandedHoldDuration(.persistent)
        islandModel.expand()
        updateTopPlayerFrame(for: .expanded, animated: false)
    }
    #endif

    private func showSettingsWindow() {
        popover.performClose(nil)
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            let createdWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            createdWindow.title = "Lyris 设置"
            createdWindow.titleVisibility = .hidden
            createdWindow.titlebarAppearsTransparent = true
            createdWindow.titlebarSeparatorStyle = .none
            createdWindow.isOpaque = false
            createdWindow.backgroundColor = .clear
            createdWindow.isMovableByWindowBackground = true
            createdWindow.minSize = NSSize(width: 760, height: 520)
            createdWindow.isReleasedWhenClosed = false
            createdWindow.hidesOnDeactivate = false
            createdWindow.level = .floating
            createdWindow.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            createdWindow.delegate = self
            createdWindow.appearance = NSAppearance(named: .darkAqua)
            createdWindow.contentView = NSHostingView(
                rootView: LyrisSettingsView(store: store)
            )
            if !createdWindow.setFrameUsingName(Self.settingsWindowFrameAutosaveName) {
                createdWindow.center()
            }
            createdWindow.setFrameAutosaveName(Self.settingsWindowFrameAutosaveName)
            settingsWindow = createdWindow
            window = createdWindow
        }

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidMove(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === mainWindow {
            hasEstablishedMainWindowFrame = true
            if let screen = window.screen,
               screen !== topPlayerScreen {
                updateTopPlayer()
            }
        } else if window === topPanel,
                  floatingSurfaceModeState.activeMode == .floatingCard {
            UserDefaults.standard.set(
                Double(window.frame.minX),
                forKey: Self.floatingCardOriginXKey
            )
            UserDefaults.standard.set(
                Double(window.frame.minY),
                forKey: Self.floatingCardOriginYKey
            )
        }
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        if let source = LyrisAssets.appIcon?.copy() as? NSImage {
            source.size = NSSize(width: 16, height: 16)
            source.isTemplate = false
            button.image = source
        } else {
            button.image = NSImage(
                systemSymbolName: "waveform",
                accessibilityDescription: "Lyris"
            )
        }
        button.toolTip = "Lyris"
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.contentViewController = NSHostingController(
            rootView: LyrisMenuPopoverView(
                store: store,
                showMainWindow: { [weak self] in
                    self?.popover.performClose(nil)
                    self?.showMainWindow()
                }
            )
        )
    }

    private func configurePointerTrackingFallback() {
        let timer = Timer.scheduledTimer(
            timeInterval: 0.08,
            target: self,
            selector: #selector(pollIslandPointerLocation),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        pointerTrackingTimer = timer
    }

    @objc private func pollIslandPointerLocation() {
        guard LyrisFloatingSurfacePolicy(
            mode: floatingSurfaceModeState.activeMode
        ).autoCollapses else {
            hoverDwellTracker.reset()
            return
        }
        if islandModel.isLockedOpen {
            collapseWasRequested = false
            hoverDwellTracker.reset()
            islandModel.expand()
            return
        }
        let location = NSEvent.mouseLocation
        let hitFrame = topPanel.frame.insetBy(dx: -8, dy: -8)
        let isInside = hitFrame.contains(location)
        switch islandModel.state {
        case .compact:
            collapseWasRequested = false
            guard store.macIslandExpansionTrigger.allowsHover else {
                hoverDwellTracker.reset()
                return
            }
            if hoverDwellTracker.shouldExpand(
                isInside: isInside,
                uptime: ProcessInfo.processInfo.systemUptime,
                delay: store.macIslandHoverExpandDelay
            ) {
                hoverDwellTracker.reset()
                islandModel.expand()
            }
        case .expanded:
            hoverDwellTracker.reset()
            if isInside {
                collapseWasRequested = false
                islandModel.expand()
            } else if !collapseWasRequested {
                collapseWasRequested = true
                scheduleIslandCollapse()
            }
        }
    }

    private func handleIslandPointerClick() {
        guard floatingSurfaceModeState.activeMode == .topIsland,
              islandModel.state == .compact,
              store.macIslandExpansionTrigger.allowsClick else { return }
        hoverDwellTracker.reset()
        collapseWasRequested = false
        islandModel.expand()
    }

    private func scheduleIslandCollapse() {
        guard LyrisFloatingSurfacePolicy(
            mode: floatingSurfaceModeState.activeMode
        ).autoCollapses else { return }
        guard !islandModel.isLockedOpen else { return }
        guard let delay = store.macIslandExpandedHoldDuration.seconds else { return }
        islandModel.collapse(after: delay)
    }

    @objc private func togglePopover() {
        guard statusItem.button != nil else { return }
        let action = LyrisStatusItemActionPolicy.primaryAction(
            mode: floatingSurfaceModeState.activeMode,
            islandState: islandModel.state,
            trigger: store.macIslandExpansionTrigger
        )
        if action == .expandIsland {
            handleIslandPointerClick()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showMenuPopover()
        }
    }

    private func updateTopPlayer() {
        let presentationMode = floatingSurfaceModeState.activeMode
        guard presentationMode != .desktopLyrics else {
            topPanel.orderOut(nil)
            return
        }
        guard let screen = preferredScreen() else { return }
        let metrics = metrics(for: screen)
        let configuration = LyrisTopPlayerGeometry.configuration(for: metrics)
        topPlayerScreen = screen
        topPlayerMetrics = metrics
        islandModel.update(configuration: configuration)
        let hostingView = LyrisIslandHostingView(
            rootView: LyrisTopPlayerView(
                store: store,
                islandModel: islandModel,
                presentationMode: presentationMode,
                showMainWindow: { [weak self] in self?.showMainWindow() }
            ),
            onPointerEntered: { [weak self] in
                self?.pollIslandPointerLocation()
            },
            onPointerExited: { [weak self] in
                // Tracking-area exits can fire while AppKit replaces or resizes
                // the hosting view. Re-read the authoritative global pointer
                // location instead of resetting the dwell timer from that
                // transient callback.
                self?.pollIslandPointerLocation()
            },
            onPointerClicked: { [weak self] in
                self?.handleIslandPointerClick()
            },
            capturesAllClicks: { [weak self] in
                guard let self else { return false }
                return self.floatingSurfaceModeState.activeMode == .topIsland
                    && self.islandModel.state == .compact
            }
        )
        topPanel.contentView = hostingView
        updateTopPlayerFrame(animated: false)
        topPanel.orderFrontRegardless()
    }

    private func updateTopPlayerFrame(
        for state: LyrisIslandState? = nil,
        animated: Bool
    ) {
        guard let metrics = topPlayerMetrics else { return }
        if floatingSurfaceModeState.activeMode == .floatingCard {
            let frame = LyrisTopPlayerGeometry.floatingCardFrame(
                metrics: metrics,
                savedOrigin: savedFloatingCardOrigin()
            )
            guard animated, topPanel.isVisible else {
                topPanel.setFrame(frame, display: true)
                return
            }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.24
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.22,
                    1,
                    0.36,
                    1
                )
                topPanel.animator().setFrame(frame, display: true)
            }
            return
        }
        let resolvedState = state ?? islandModel.state
        let frame = LyrisTopPlayerGeometry.panelFrame(
            configuration: islandModel.configuration,
            metrics: metrics,
            state: resolvedState
        )
        guard animated, topPanel.isVisible else {
            topPanel.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.30
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                1,
                0.36,
                1
            )
            topPanel.animator().setFrame(frame, display: true)
        }
    }

    private func placeMainWindowAvoidingTopPlayer() {
        guard let screen = preferredScreen() else {
            mainWindow.center()
            return
        }
        mainWindow.setFrame(
            LyrisWindowPlacementPolicy.mainWindowFrame(
                windowSize: mainWindow.frame.size,
                visibleFrame: screen.visibleFrame,
                topPlayerFrame: expandedTopPlayerFrame(on: screen)
            ),
            display: true
        )
    }

    private func expandedTopPlayerFrame(on screen: NSScreen) -> CGRect {
        let metrics = metrics(for: screen)
        return LyrisTopPlayerGeometry.frame(
            configuration: LyrisTopPlayerGeometry.configuration(for: metrics),
            metrics: metrics,
            state: .expanded
        )
    }

    private func preferredScreen() -> NSScreen? {
        mainWindow.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func metrics(for screen: NSScreen) -> LyrisScreenMetrics {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--qa-external-display") {
            return LyrisScreenMetrics(
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                safeAreaTop: 0,
                auxiliaryTopLeftArea: nil,
                auxiliaryTopRightArea: nil
            )
        }
        #endif
        return LyrisScreenMetrics(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    private static func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_020, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Lyris"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 860, height: 620)
        window.collectionBehavior = [.fullScreenPrimary]
        window.appearance = NSAppearance(named: .darkAqua)
        return window
    }

    private static let mainWindowFrameAutosaveName = "LyrisMainWindowFrame"
    private static let settingsWindowFrameAutosaveName = "LyrisSettingsWindowFrame"
    private static let floatingCardOriginXKey = "LyrisFloatingCardOriginX"
    private static let floatingCardOriginYKey = "LyrisFloatingCardOriginY"

    private func applyFloatingPresentationMode(
        _ publishedMode: FloatingPresentationMode
    ) {
        let plan = floatingSurfaceModeState.apply(
            publishedMode: publishedMode
        )
        hoverDwellTracker.reset()
        collapseWasRequested = false
        isApplyingFloatingPresentationMode = true
        defer { isApplyingFloatingPresentationMode = false }

        topPanel.isMovable = plan.topPanelIsMovable
        topPanel.isMovableByWindowBackground = plan.topPanelIsMovable

        guard plan.showsTopPanel else {
            topPanel.orderOut(nil)
            showMainWindow()
            return
        }

        mainWindow.orderOut(nil)
        switch plan.targetIslandState {
        case .compact:
            islandModel.setLockedOpen(false)
            islandModel.collapseImmediately(force: true)
        case .expanded:
            islandModel.expand()
        case nil:
            break
        }
        updateTopPlayer()
    }

    private func savedFloatingCardOrigin() -> CGPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.floatingCardOriginXKey) != nil,
              defaults.object(forKey: Self.floatingCardOriginYKey) != nil else { return nil }
        return CGPoint(
            x: defaults.double(forKey: Self.floatingCardOriginXKey),
            y: defaults.double(forKey: Self.floatingCardOriginYKey)
        )
    }

    private static func makeTopPanel() -> NSPanel {
        let panel = LyrisTopPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1_200, height: 150),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}
