import SwiftUI

private struct LyrisAttachedBarShape: Shape {
    let cameraInset: CGFloat
    let cameraWidth: CGFloat
    let state: LyrisIslandState
    let presentationMode: FloatingPresentationMode

    func path(in rect: CGRect) -> Path {
        if presentationMode == .floatingCard {
            return RoundedRectangle(
                cornerRadius: rect.height / 2,
                style: .continuous
            ).path(in: rect)
        }
        let hasCameraHousing = cameraInset > 0 && cameraWidth > 0
        if !hasCameraHousing {
            return RoundedRectangle(
                cornerRadius: state == .compact ? rect.height / 2 : 24,
                style: .continuous
            ).path(in: rect)
        }
        if state == .compact {
            let bounds = rect.insetBy(
                dx: LyrisTopPlayerGeometry.compactEndCapInset,
                dy: 0
            )
            let shelfDepth = min(
                LyrisTopPlayerGeometry.compactShelfDepth,
                max(0, bounds.height - 1)
            )
            let topBandBottom = bounds.maxY - shelfDepth
            let shelfWidth = min(
                LyrisTopPlayerGeometry.compactLyricShelfWidth,
                max(0, bounds.width - 48)
            )
            let cameraCenterX = bounds.midX
            let shelfLeft = cameraCenterX - shelfWidth / 2
            let shelfRight = cameraCenterX + shelfWidth / 2
            let shelfBottomInset = min(
                LyrisTopPlayerGeometry.compactShelfShoulderInset,
                shelfWidth / 4
            )
            let shelfBottomLeft = shelfLeft + shelfBottomInset
            let shelfBottomRight = shelfRight - shelfBottomInset
            let shelfShoulderControl = LyrisTopPlayerGeometry
                .compactShoulderControlDistance(for: shelfBottomInset)
            let outerClosure = LyrisTopPlayerGeometry
                .compactOuterClosureGeometry(
                    in: bounds,
                    topBandBottom: topBandBottom
                )
            var path = Path()

            // The outer closures and the lower lyric tray share the exact same
            // horizontal/vertical shoulder ratio and control distance. This
            // keeps the compact island as one continuous material instead of
            // combining circular end caps with an unrelated V-shaped shelf.
            path.move(to: CGPoint(x: bounds.minX, y: bounds.minY))
            path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.minY))
            path.addCurve(
                to: outerClosure.rightBottom,
                control1: outerClosure.rightTopControl,
                control2: outerClosure.rightBottomControl
            )
            path.addLine(to: CGPoint(x: shelfRight, y: topBandBottom))
            path.addCurve(
                to: CGPoint(x: shelfBottomRight, y: bounds.maxY),
                control1: CGPoint(
                    x: shelfRight - shelfShoulderControl,
                    y: topBandBottom
                ),
                control2: CGPoint(
                    x: shelfBottomRight + shelfShoulderControl,
                    y: bounds.maxY
                )
            )
            path.addLine(to: CGPoint(x: shelfBottomLeft, y: bounds.maxY))
            path.addCurve(
                to: CGPoint(x: shelfLeft, y: topBandBottom),
                control1: CGPoint(
                    x: shelfBottomLeft - shelfShoulderControl,
                    y: bounds.maxY
                ),
                control2: CGPoint(
                    x: shelfLeft + shelfShoulderControl,
                    y: topBandBottom
                )
            )
            path.addLine(to: outerClosure.leftBottom)
            path.addCurve(
                to: CGPoint(x: bounds.minX, y: bounds.minY),
                control1: outerClosure.leftBottomControl,
                control2: outerClosure.leftTopControl
            )
            path.closeSubpath()
            return path
        }
        let topRadius = min(14, rect.height / 4)
        let bottomRadius = min(28, rect.height / 2)
        let k: CGFloat = 0.552_284_75
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + topRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRadius, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + topRadius),
            control1: CGPoint(x: rect.maxX - topRadius * (1 - k), y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + topRadius * (1 - k))
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius))
        path.addCurve(
            to: CGPoint(x: rect.maxX - bottomRadius, y: rect.maxY),
            control1: CGPoint(x: rect.maxX, y: rect.maxY - bottomRadius * (1 - k)),
            control2: CGPoint(x: rect.maxX - bottomRadius * (1 - k), y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + bottomRadius, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius),
            control1: CGPoint(x: rect.minX + bottomRadius * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.minX, y: rect.maxY - bottomRadius * (1 - k))
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topRadius))
        path.addCurve(
            to: CGPoint(x: rect.minX + topRadius, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + topRadius * (1 - k)),
            control2: CGPoint(x: rect.minX + topRadius * (1 - k), y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct LyrisTopPlayerBackdrop: View {
    let state: LyrisIslandState
    let style: LinkedEffectStyle
    let skin: LyrisInterfaceSkin
    let isPlaying: Bool
    let effectSeed: String
    let progress: Double

    var body: some View {
        let profile = LyrisTopPlayerMaterialProfile.resolve(for: state)

        ZStack {
            Color.black

            if state == .expanded {
                skin.backgroundColor.opacity(profile.skinTintOpacity)
                LyrisLinkedEffectOverlay(
                    style: style,
                    skin: skin,
                    isPlaying: isPlaying,
                    seed: effectSeed,
                    progress: progress
                )
                .opacity(profile.linkedEffectOpacity)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.22),
                        .clear,
                        Color.black.opacity(0.20),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.034),
                        .clear,
                        Color.black.opacity(0.20),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
    }
}

struct LyrisTopPlayerView: View {
    @ObservedObject var store: LyrisStore
    @ObservedObject var islandModel: LyrisIslandModel
    let presentationMode: FloatingPresentationMode
    let showMainWindow: () -> Void

    var body: some View {
        let configuration = islandModel.configuration
        let displayedState = presentationMode == .topIsland
            ? islandModel.state
            : LyrisIslandState.expanded
        let shape = LyrisAttachedBarShape(
            cameraInset: configuration.cameraInset,
            cameraWidth: configuration.cameraWidth,
            state: displayedState,
            presentationMode: presentationMode
        )
        ZStack(alignment: .top) {
            if displayedState == .compact {
                let compactSize = LyrisTopPlayerGeometry.visualSize(
                    configuration: configuration,
                    state: .compact
                )
                Color.clear
                compactContent
                    .frame(
                        width: compactSize.width,
                        height: compactSize.height
                    )
                    .clipShape(shape)
                    .overlay {
                        if !configuration.hasCameraHousing {
                            shape.stroke(
                                Color.white.opacity(0.075),
                                lineWidth: 0.65
                            )
                        }
                    }
                    .shadow(
                        color: configuration.hasCameraHousing
                            ? .clear
                            : Color.black.opacity(0.32),
                        radius: 10,
                        y: 4
                    )
            } else {
                ZStack {
                    LyrisTopPlayerBackdrop(
                        state: .expanded,
                        style: store.linkedEffectStyle,
                        skin: store.interfaceSkin,
                        isPlaying: store.playback.isPlaying,
                        effectSeed: store.playback.track.id,
                        progress: store.progress
                    )
                    LyrisGlobalFlowThreadOverlay(
                        style: store.linkedEffectStyle,
                        skin: store.interfaceSkin,
                        isPlaying: store.playback.isPlaying,
                        seed: store.playback.track.id,
                        composition: LyrisExpandedIslandEffectPolicy.composition,
                        progress: store.progress
                    )
                    .opacity(LyrisExpandedIslandEffectPolicy.opacity)
                    expandedContent
                }
                .clipShape(shape)
                .overlay {
                    let profile = LyrisTopPlayerMaterialProfile.resolve(for: .expanded)
                    shape.stroke(
                        LinearGradient(
                            colors: [
                                store.interfaceSkin.accentColor.opacity(profile.edgeLightOpacity),
                                Color.white.opacity(0.035),
                                store.interfaceSkin.secondaryAccentColor.opacity(
                                    profile.edgeLightOpacity * 0.78
                                ),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.7
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .accessibilityElement(children: .contain)
    }

    private var compactContent: some View {
        let configuration = islandModel.configuration

        return ZStack {
            LyrisTopPlayerBackdrop(
                state: .compact,
                style: store.linkedEffectStyle,
                skin: store.interfaceSkin,
                isPlaying: store.playback.isPlaying,
                effectSeed: store.playback.track.id,
                progress: store.progress
            )
            compactInformationLayout(configuration: configuration)
        }
        .accessibilityLabel("\(store.playback.track.title)，\(compactLyric)")
    }

    @ViewBuilder
    private func compactInformationLayout(
        configuration: LyrisTopPlayerConfiguration
    ) -> some View {
        if configuration.hasCameraHousing {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    compactMetadataWing
                        .frame(width: LyrisTopPlayerGeometry.compactWingWidth)
                        .offset(
                            x: LyrisTopPlayerGeometry.compactWingContentSafeOffset
                        )
                    Color.clear.frame(width: configuration.cameraWidth)
                    compactLyricWing
                        .frame(width: LyrisTopPlayerGeometry.compactWingWidth)
                        .offset(
                            x: -LyrisTopPlayerGeometry.compactWingContentSafeOffset
                        )
                }
                .frame(height: configuration.cameraInset)

                compactLyricDisplay
                    .frame(
                        width: LyrisTopPlayerGeometry.compactLyricShelfWidth,
                        height: LyrisTopPlayerGeometry.compactShelfDepth
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } else {
            HStack(spacing: 9) {
                compactArtwork
                compactMetadata
                    .frame(width: 164, alignment: .leading)
                LyrisSoftDivider().frame(height: 24)
                compactLyricDisplay
                    .frame(maxWidth: .infinity)
                compactEffectMark
            }
            .padding(.horizontal, 10)
        }
    }

    private var compactMetadataWing: some View {
        HStack(spacing: 6) {
            compactArtwork
            Text(compactTitle)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 78, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var compactLyricWing: some View {
        HStack {
            Spacer(minLength: 8)
            compactEffectMark
            Spacer(minLength: 8)
        }
    }

    private var compactArtwork: some View {
        LyrisArtworkView(url: store.playback.track.artworkURL)
            .frame(width: 24, height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
            }
    }

    private var compactMetadata: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(compactTitle)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.90))
                .lineLimit(1)
            Text(store.playback.track.artist)
                .font(.system(size: 8.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.50))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var compactLyricDisplay: some View {
        LyrisSynchronizedMarqueeText(
            text: compactLyric,
            progress: store.activeLyricProgress,
            font: store.translationDisplayFont(
                size: LyrisTopPlayerGeometry.compactLyricFontSize,
                weight: .semibold
            ),
            baseColor: Color.white.opacity(0.52),
            progressColor: store.interfaceSkin.accentColor.opacity(0.96)
        )
        .frame(
            width: LyrisTopPlayerGeometry.compactLyricShelfWidth - 18,
            height: LyrisTopPlayerGeometry.compactShelfDepth,
            alignment: .center
        )
    }

    private var compactEffectMark: some View {
        LyrisWaveformView(
            trackID: "compact-effect:\(store.playback.track.id)",
            progress: store.progress,
            isPlaying: store.playback.isPlaying,
            accentColor: store.interfaceSkin.accentColor
        )
        .frame(width: 66, height: 10)
        .opacity(store.linkedEffectStyle == .off ? 0.24 : 0.72)
    }

    private var expandedContent: some View {
        GeometryReader { proxy in
            HStack(spacing: 14) {
                expandedIdentity
                    .frame(width: 240)

                LyrisSoftDivider()
                    .frame(height: 118)

                expandedLyricStage
                    .frame(maxWidth: .infinity)

                LyrisSoftDivider()
                    .frame(height: 118)

                expandedControls
                    .frame(width: 190, alignment: .trailing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private var expandedIdentity: some View {
        HStack(spacing: 12) {
            VStack(spacing: 3) {
                LyrisPlayerArtworkVisual(
                    store: store,
                    mode: store.artworkPresentationMode
                )
                .frame(width: 78, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                HStack(spacing: 4) {
                    Button(action: store.handleLikedControlTap) {
                        Image(
                            systemName: (store.playback.likedState.displayedValue ?? false)
                                ? "heart.fill"
                                : "heart"
                        )
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(
                            (store.playback.likedState.displayedValue ?? false)
                                ? store.interfaceSkin.accentColor
                                : LyrisTheme.secondaryText
                        )
                        .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)

                    LyrisIconButton(
                        symbol: store.artworkPresentationMode == .ambientMotion
                            ? "sparkles"
                            : "photo",
                        active: store.artworkPresentationMode == .ambientMotion,
                        size: 24,
                        activeColor: store.interfaceSkin.accentColor,
                        help: "切换封面表现"
                    ) {
                        store.updateArtworkPresentationMode(
                            store.artworkPresentationMode.next
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(store.playback.track.title.uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(LyrisTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(store.playback.track.artist)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(LyrisTheme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                LyrisWaveformView(
                    trackID: store.playback.track.id,
                    progress: store.progress,
                    isPlaying: store.playback.isPlaying,
                    accentColor: store.interfaceSkin.accentColor
                )
                .frame(height: 18)
                .opacity(store.linkedEffectStyle == .off ? 0.34 : 0.72)
            }
            .frame(maxWidth: .infinity, maxHeight: 108, alignment: .leading)
        }
    }

    private var expandedLyricStage: some View {
        VStack(spacing: 3) {
            Button(action: showMainWindow) {
                VStack(spacing: 3) {
                    Text(previousLyric ?? " ")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(LyrisTheme.tertiaryText.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(height: 14)
                        .frame(maxWidth: .infinity)

                    LyrisSynchronizedMarqueeText(
                        text: primaryLyric,
                        progress: store.activeLyricProgress,
                        font: .system(size: 24, weight: .semibold),
                        baseColor: LyrisTheme.secondaryText,
                        progressColor: store.interfaceSkin.accentColor
                    )
                    .frame(height: 31)
                    .frame(maxWidth: .infinity)

                    if let translation = translationLyric {
                        LyrisSynchronizedMarqueeText(
                            text: translation,
                            progress: store.activeLyricProgress,
                            font: store.translationDisplayFont(size: 17, weight: .medium),
                            baseColor: LyrisTheme.secondaryText.opacity(0.74),
                            progressColor: LyrisTheme.primaryText.opacity(0.92)
                        )
                        .frame(height: 22)
                        .frame(maxWidth: .infinity)
                    } else {
                        Text(" ")
                            .font(.system(size: 17))
                            .frame(height: 22)
                    }

                    Text(nextLyric ?? " ")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(LyrisTheme.tertiaryText.opacity(0.82))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(height: 14)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .focusable(false)

            LyrisProgressBar(store: store, showsTime: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var expandedControls: some View {
        VStack(alignment: .trailing, spacing: 8) {
            LyrisTransportControls(store: store, compact: true)
            HStack(spacing: 3) {
                if presentationMode == .topIsland {
                    LyrisIconButton(
                        symbol: "chevron.compact.up",
                        size: 30,
                        help: "立即收回灵动岛"
                    ) {
                        islandModel.collapseByUserRequest()
                    }
                    .accessibilityLabel("立即收回灵动岛")
                }
                LyrisIconButton(
                    symbol: islandModel.isLockedOpen ? "lock.fill" : "lock.open",
                    active: islandModel.isLockedOpen,
                    size: 30,
                    activeColor: store.interfaceSkin.accentColor,
                    help: islandModel.isLockedOpen ? "解除锁定" : "锁定展开"
                ) {
                    islandModel.toggleLockedOpen()
                }
                .accessibilityLabel(islandModel.isLockedOpen ? "解除锁定" : "锁定展开")
                LyrisPresentationModeMenu(store: store, size: 30)
                LyrisIconButton(symbol: "gearshape", size: 30, help: "设置") {
                    store.showSettings(.appearance)
                }
            }
        }
    }

    private var activeLyricIndex: Int? {
        guard let activeID = store.activeLyric?.id else { return nil }
        return store.lyrics.firstIndex(where: { $0.id == activeID })
    }

    private var previousLyric: String? {
        guard let index = activeLyricIndex, index > store.lyrics.startIndex else { return nil }
        return store.displayedOriginal(for: store.lyrics[index - 1])
    }

    private var nextLyric: String? {
        guard let index = activeLyricIndex,
              store.lyrics.indices.contains(index + 1) else { return nil }
        return store.displayedOriginal(for: store.lyrics[index + 1])
    }

    private var primaryLyric: String {
        store.activeLyric.map(store.displayedOriginal(for:))
            ?? store.lyricsPipelineState.presentation(language: store.interfaceLanguage)?.title
            ?? store.playback.track.title
    }

    private var translationLyric: String? {
        guard let line = store.activeLyric else { return nil }
        return store.secondaryIslandLyric(for: line)
    }

    private var compactLyric: String {
        LyrisCompactLyricProjection.text(
            mode: store.menuBarLyricMode,
            original: primaryLyric,
            translated: store.activeLyric.flatMap {
                store.secondaryIslandLyric(for: $0, showsAdjacentLyrics: false)
            }
        )
    }

    private var compactTitle: String {
        switch store.playback.track.id {
        case "loading", "spotify:idle":
            return "LYRIS"
        default:
            return store.playback.track.title.uppercased()
        }
    }
}

struct LyrisMainWindowView: View {
    @ObservedObject var store: LyrisStore

    var body: some View {
        LyrisGlassSurface(
            cornerRadius: 20,
            shadeOpacity: 0.62,
            skin: store.interfaceSkin
        ) {
            ZStack {
                LyrisLinkedEffectOverlay(
                    style: store.linkedEffectStyle,
                    skin: store.interfaceSkin,
                    isPlaying: store.playback.isPlaying,
                    seed: store.playback.track.id,
                    progress: store.progress
                )
                .opacity(0.70)
                LyrisGlobalFlowThreadOverlay(
                    style: store.linkedEffectStyle,
                    skin: store.interfaceSkin,
                    isPlaying: store.playback.isPlaying,
                    seed: store.playback.track.id
                )
                .opacity(0.24)

                VStack(spacing: 0) {
                    mainToolbar
                    Divider().overlay(LyrisTheme.hairline)
                    GeometryReader { proxy in
                        HStack(spacing: 0) {
                            nowPlayingColumn
                                .frame(width: min(350, proxy.size.width * 0.35))
                            Divider().overlay(LyrisTheme.hairline)
                            lyricsColumn
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(1)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private var mainToolbar: some View {
        ZStack {
            HStack(spacing: 0) {
                LyrisWindowDragRegion()
                    .frame(width: 420, height: 58)
                Spacer()
                Color.clear.frame(width: 178, height: 58)
            }
            Text("Lyris")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LyrisTheme.secondaryText)
                HStack {
                    Spacer()
                    LyrisPresentationModeMenu(store: store, size: 32)
                    LyrisIconButton(symbol: "record.circle", size: 32, help: "歌词与来源") {
                        store.showSettings(.storage)
                }
                Menu {
                    ForEach(LyrisInterfaceSkin.allCases) { skin in
                        Button {
                            store.updateInterfaceSkin(skin)
                        } label: {
                            Label(
                                skin.displayName(in: store.interfaceLanguage),
                                systemImage: store.interfaceSkin == skin
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                        }
                    }
                    Divider()
                    Button("更多外观设置…") {
                        store.showSettings(.appearance)
                    }
                } label: {
                    Image(systemName: "tshirt")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(LyrisTheme.primaryText)
                        .frame(width: 32, height: 32)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .focusable(false)
                .fixedSize()
                .help("切换界面皮肤")
                Divider().frame(height: 26).overlay(LyrisTheme.hairline)
                LyrisIconButton(symbol: "ellipsis", size: 32, help: "设置") {
                    store.showSettings(.language)
                }
            }
        }
        .padding(.horizontal, 22)
        .frame(height: 58)
    }

    private var nowPlayingColumn: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 6)
            LyrisArtworkView(url: store.playback.track.artworkURL)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 278)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(LyrisTheme.hairline, lineWidth: 1)
                }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.playback.track.title.uppercased())
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(LyrisTheme.primaryText)
                        .lineLimit(1)
                    Text(store.playback.track.artist)
                        .font(.system(size: 14))
                        .foregroundStyle(LyrisTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: store.handleLikedControlTap) {
                    Image(systemName: (store.playback.likedState.displayedValue ?? false) ? "checkmark.circle.fill" : "heart")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(
                            (store.playback.likedState.displayedValue ?? false)
                                ? store.interfaceSkin.accentColor
                                : LyrisTheme.secondaryText
                        )
                }
                .buttonStyle(.plain)
                .focusable(false)
            }

            LyrisProgressBar(store: store, showsTime: true)
            LyrisWaveformView(
                trackID: store.playback.track.id,
                progress: store.progress,
                isPlaying: store.playback.isPlaying,
                accentColor: store.interfaceSkin.accentColor
            )
            .frame(height: 30)
            .opacity(store.linkedEffectStyle == .off ? 0.42 : 0.88)
            LyrisTransportControls(store: store, compact: false)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 18) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(LyrisTheme.primaryText)
                Slider(
                    value: Binding(
                        get: { store.playback.volume ?? 0.5 },
                        set: { store.send(.setVolume($0)) }
                    ),
                    in: 0...1
                )
                .tint(store.interfaceSkin.accentColor)
                .disabled(!store.playback.capabilities.contains(.volume))
            }
            Spacer(minLength: 10)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 28)
    }

    private var lyricsColumn: some View {
        LyrisLyricsListView(store: store, presentation: .main)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
    }
}

enum LyrisPresentationModeMenuPolicy {
    static let acceptsKeyboardFocus = false
}

struct LyrisPresentationModeMenu: View {
    @ObservedObject var store: LyrisStore
    let size: CGFloat

    var body: some View {
        Menu {
            ForEach(FloatingPresentationMode.allCases) { mode in
                Button {
                    store.updateFloatingPresentationMode(mode)
                } label: {
                    Label(
                        "\(mode.displayName(in: store.interfaceLanguage))（\(mode.guidance(in: store.interfaceLanguage))）",
                        systemImage: store.floatingPresentationMode == mode
                            ? "checkmark.circle.fill"
                            : mode.symbolName
                    )
                }
            }
        } label: {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LyrisTheme.primaryText)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .focusable(LyrisPresentationModeMenuPolicy.acceptsKeyboardFocus)
        .fixedSize()
        .help("切换呈现模式")
        .accessibilityLabel("切换呈现模式")
    }
}

struct LyrisMenuPopoverView: View {
    @ObservedObject var store: LyrisStore
    let showMainWindow: () -> Void

    var body: some View {
        LyrisGlassSurface(
            cornerRadius: 26,
            shadeOpacity: 0.74,
            skin: store.interfaceSkin
        ) {
            VStack(spacing: 18) {
                HStack(spacing: 16) {
                    LyrisArtworkView(url: store.playback.track.artworkURL)
                        .frame(width: 74, height: 74)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.playback.track.title.uppercased())
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(LyrisTheme.primaryText)
                            .lineLimit(1)
                        Text(store.playback.track.artist)
                            .font(.system(size: 13))
                            .foregroundStyle(LyrisTheme.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer()
                    LyrisWaveformView(
                        trackID: store.playback.track.id,
                        progress: store.progress,
                        isPlaying: store.playback.isPlaying,
                        accentColor: store.interfaceSkin.accentColor
                    )
                    .frame(width: 42, height: 28)
                }

                LyrisProgressBar(store: store, showsTime: true)
                Divider().overlay(LyrisTheme.hairline)

                LyrisLyricsListView(store: store, presentation: .popover)
                    .frame(maxHeight: .infinity)

                HStack(spacing: 18) {
                    Color.clear
                        .frame(width: 34, height: 34)
                    Spacer()
                    LyrisTransportControls(store: store, compact: false)
                    Spacer()
                    LyrisIconButton(symbol: "arrow.up.forward.app", size: 34, help: "打开主窗口") {
                        showMainWindow()
                    }
                }
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
    }
}

enum LyrisLyricsPresentation {
    case main
    case popover
}

enum LyrisLyricsProjection {
    static func lines(
        for presentation: LyrisLyricsPresentation,
        lyrics: [TimedLyric]
    ) -> [TimedLyric] {
        // Both surfaces render the complete document. Visual emphasis and
        // ScrollViewReader keep the active context focused without deleting
        // earlier or later lines from the user's lyric reader.
        lyrics
    }
}

private struct LyrisLyricsListView: View {
    @ObservedObject var store: LyrisStore
    let presentation: LyrisLyricsPresentation

    var body: some View {
        Group {
            if store.lyrics.isEmpty {
                emptyState
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: presentation == .main ? 24 : 18) {
                            ForEach(displayedLines) { line in
                                lyricLine(line)
                                    .id(line.id)
                            }
                        }
                        .padding(.vertical, 14)
                    }
                    .scrollIndicators(.hidden)
                    .onAppear { scrollToActive(reader, animated: false) }
                    .onChange(of: store.activeLyric?.id) { _ in
                        scrollToActive(reader, animated: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func lyricLine(_ line: TimedLyric) -> some View {
        let active = line.id == store.activeLyric?.id
        HStack(alignment: .top, spacing: 18) {
            Circle()
                .fill(active ? store.interfaceSkin.accentColor : Color.white.opacity(0.12))
                .frame(width: active ? 10 : 7, height: active ? 10 : 7)
                .shadow(color: active ? store.interfaceSkin.accentColor.opacity(0.65) : .clear, radius: 8)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 7) {
                if active {
                    LyrisProgressiveText(
                        text: store.displayedOriginal(for: line),
                        progress: store.activeLyricProgress,
                        font: .system(
                            size: presentation == .main ? 24 : 20,
                            weight: .semibold
                        ),
                        baseColor: LyrisTheme.secondaryText,
                        progressColor: store.interfaceSkin.accentColor
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(store.displayedOriginal(for: line))
                        .font(.system(
                            size: presentation == .main ? 18 : 16,
                            weight: .regular
                        ))
                        .foregroundStyle(LyrisTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let translation = distinctTranslation(for: line) {
                    Text(translation)
                        .font(store.translationDisplayFont(
                            size: presentation == .main ? (active ? 17 : 14) : (active ? 16 : 13),
                            weight: active ? .semibold : .regular
                        ))
                        .foregroundStyle(active ? store.interfaceSkin.accentColor.opacity(0.90) : LyrisTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .opacity(active ? 1 : 0.72)
        .animation(.easeOut(duration: 0.24), value: active)
    }

    private var emptyState: some View {
        let state = store.lyricsPipelineState.presentation(language: store.interfaceLanguage)
        return VStack(spacing: 12) {
            Image(systemName: state?.systemImage ?? "text.quote")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(store.interfaceSkin.accentColor.opacity(0.8))
            Text(state?.title ?? "等待歌词")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(LyrisTheme.primaryText)
            if let detail = state?.detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(LyrisTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
            if state?.canRetry == true {
                Button("重试") { store.retryLyrics() }
                    .buttonStyle(.borderedProminent)
                    .tint(store.interfaceSkin.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var displayedLines: [TimedLyric] {
        LyrisLyricsProjection.lines(
            for: presentation,
            lyrics: store.lyrics
        )
    }

    private func distinctTranslation(for line: TimedLyric) -> String? {
        let translated = store.displayedTranslation(for: line)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let original = store.displayedOriginal(for: line)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !translated.isEmpty, translated != original else { return nil }
        return translated
    }

    private func scrollToActive(_ reader: ScrollViewProxy, animated: Bool) {
        guard let id = store.activeLyric?.id else { return }
        let action = { reader.scrollTo(id, anchor: .center) }
        if animated {
            withAnimation(.easeInOut(duration: 0.32), action)
        } else {
            action()
        }
    }
}

private struct LyrisTransportControls: View {
    @ObservedObject var store: LyrisStore
    let compact: Bool

    var body: some View {
        let size: CGFloat = compact ? 30 : 38
        HStack(spacing: compact ? 4 : 9) {
            LyrisIconButton(
                symbol: "shuffle",
                active: store.playback.isShuffled,
                size: size,
                activeColor: store.interfaceSkin.accentColor,
                help: "随机播放"
            ) { store.send(.toggleShuffle) }
                .disabled(!store.playback.capabilities.contains(.shuffle))

            LyrisIconButton(symbol: "backward.end.fill", size: size, help: "上一首") {
                store.send(.previous)
            }
            .disabled(!store.playback.capabilities.contains(.transport))

            LyrisIconButton(
                symbol: store.playback.isPlaying ? "pause.fill" : "play.fill",
                active: true,
                size: compact ? 44 : 56,
                foreground: .black,
                activeColor: store.interfaceSkin.accentColor,
                help: store.playback.isPlaying ? "暂停" : "播放"
            ) { store.send(.togglePlayback) }
                .background(Color.white.opacity(0.94), in: Circle())
                .disabled(!store.playback.capabilities.contains(.transport))

            LyrisIconButton(symbol: "forward.end.fill", size: size, help: "下一首") {
                store.send(.next)
            }
            .disabled(!store.playback.capabilities.contains(.transport))

            if !compact {
                LyrisIconButton(
                    symbol: store.playback.repeatMode == .one ? "repeat.1" : "repeat",
                    active: store.playback.repeatMode != .off,
                    size: size,
                    activeColor: store.interfaceSkin.accentColor,
                    help: "循环模式"
                ) { store.send(.cycleRepeat) }
                    .disabled(!store.playback.capabilities.contains(.repeatMode))
            }
        }
    }
}

private struct LyrisProgressBar: View {
    @ObservedObject var store: LyrisStore
    let showsTime: Bool
    @State private var scrubProgress: Double?

    var body: some View {
        let progress = min(max(scrubProgress ?? store.progress, 0), 1)
        VStack(spacing: 6) {
            ZStack {
                GeometryReader { proxy in
                    let thumbDiameter = 12.0
                    let availableWidth = max(0, proxy.size.width - thumbDiameter)
                    let filledWidth = thumbDiameter / 2 + availableWidth * progress

                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.14))
                            .frame(height: 4)

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        store.interfaceSkin.accentColor,
                                        store.interfaceSkin.secondaryAccentColor,
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(2, filledWidth), height: 4)

                        Circle()
                            .fill(Color.white.opacity(0.96))
                            .frame(width: thumbDiameter, height: thumbDiameter)
                            .overlay {
                                Circle()
                                    .stroke(store.interfaceSkin.accentColor.opacity(0.55), lineWidth: 1)
                            }
                            .shadow(color: store.interfaceSkin.accentColor.opacity(0.28), radius: 3)
                            .offset(x: availableWidth * progress)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }

                Slider(
                    value: Binding(
                        get: { progress },
                        set: { scrubProgress = min(max($0, 0), 1) }
                    ),
                    in: 0...1,
                    onEditingChanged: { isEditing in
                        guard !isEditing else { return }
                        let finalProgress = min(max(scrubProgress ?? store.progress, 0), 1)
                        scrubProgress = nil
                        store.seek(to: finalProgress * store.playback.track.duration)
                    }
                )
                .controlSize(.small)
                .opacity(0.015)
                .accessibilityLabel("歌曲进度")
            }
            .frame(height: 16)

            if showsTime {
                HStack {
                    Text(lyrisTime(progress * store.playback.track.duration))
                    Spacer()
                    Text(lyrisTime(store.playback.track.duration))
                }
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(LyrisTheme.secondaryText)
            }
        }
    }
}
