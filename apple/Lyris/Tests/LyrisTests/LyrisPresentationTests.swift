import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Lyris

final class LyrisPresentationTests: XCTestCase {
    @MainActor
    func testCompactIslandHostingViewCapturesClicksAboveTheLyricTray() {
        let hostingView = LyrisIslandHostingView(
            rootView: HStack {
                Text("Artwork and title")
                Spacer()
                Text("Waveform")
            }
            .frame(width: 480, height: 56),
            onPointerEntered: {},
            onPointerExited: {},
            onPointerClicked: {},
            capturesAllClicks: { true }
        )
        hostingView.frame = CGRect(x: 0, y: 0, width: 480, height: 56)
        hostingView.layoutSubtreeIfNeeded()

        let leftWingHit = hostingView.hitTest(CGPoint(x: 72, y: 42))
        let rightWingHit = hostingView.hitTest(CGPoint(x: 408, y: 42))
        XCTAssertTrue(leftWingHit === hostingView)
        XCTAssertTrue(rightWingHit === hostingView)
        XCTAssertTrue(hostingView.acceptsFirstMouse(for: nil))
    }

    func testArtworkPresentationControlCyclesBetweenStaticAndAmbientModes() {
        XCTAssertEqual(LyrisArtworkPresentationMode.staticArtwork.next, .ambientMotion)
        XCTAssertEqual(LyrisArtworkPresentationMode.ambientMotion.next, .staticArtwork)
    }

    func testFloatingPresentationModeDrivesWindowBehaviorInsteadOfSkinSelection() {
        XCTAssertEqual(
            LyrisFloatingSurfacePolicy(mode: .topIsland).windowBehavior,
            .notchAttached
        )
        XCTAssertEqual(
            LyrisFloatingSurfacePolicy(mode: .floatingCard).windowBehavior,
            .movableBar
        )
        XCTAssertEqual(
            LyrisFloatingSurfacePolicy(mode: .desktopLyrics).windowBehavior,
            .desktopLyrics
        )
        XCTAssertTrue(LyrisFloatingSurfacePolicy(mode: .topIsland).autoCollapses)
        XCTAssertFalse(LyrisFloatingSurfacePolicy(mode: .floatingCard).autoCollapses)
        XCTAssertFalse(LyrisFloatingSurfacePolicy(mode: .desktopLyrics).autoCollapses)
    }

    func testPresentationTransitionPlanAppliesEachModeAsOneCoherentWindowState() {
        let island = LyrisFloatingSurfaceTransitionPlan(mode: .topIsland)
        XCTAssertTrue(island.showsTopPanel)
        XCTAssertFalse(island.showsMainWindow)
        XCTAssertFalse(island.topPanelIsMovable)
        XCTAssertEqual(island.targetIslandState, .compact)

        let floating = LyrisFloatingSurfaceTransitionPlan(mode: .floatingCard)
        XCTAssertTrue(floating.showsTopPanel)
        XCTAssertFalse(floating.showsMainWindow)
        XCTAssertTrue(floating.topPanelIsMovable)
        XCTAssertEqual(floating.targetIslandState, .expanded)

        let desktop = LyrisFloatingSurfaceTransitionPlan(mode: .desktopLyrics)
        XCTAssertFalse(desktop.showsTopPanel)
        XCTAssertTrue(desktop.showsMainWindow)
        XCTAssertFalse(desktop.topPanelIsMovable)
        XCTAssertNil(desktop.targetIslandState)
    }

    func testPublishedPresentationModeBecomesTheActiveWindowModeImmediately() {
        var state = LyrisFloatingSurfaceModeState(initialMode: .topIsland)

        let floating = state.apply(publishedMode: .floatingCard)
        XCTAssertEqual(state.activeMode, .floatingCard)
        XCTAssertEqual(floating.mode, .floatingCard)
        XCTAssertTrue(floating.topPanelIsMovable)

        let island = state.apply(publishedMode: .topIsland)
        XCTAssertEqual(state.activeMode, .topIsland)
        XCTAssertEqual(island.targetIslandState, .compact)
        XCTAssertFalse(island.topPanelIsMovable)
    }

    func testDisplayPreferencesPersistSkinArtworkModeAndCustomTranslationFont() throws {
        let suiteName = "LyrisPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = LyrisDisplayPreferences(
            interfaceLanguage: .simplifiedChinese,
            translationTarget: .simplifiedChinese,
            translationFont: .custom,
            customTranslationFontFamily: "Fixture Font",
            interfaceSkin: .midnightAurora,
            artworkPresentationMode: .ambientMotion,
            floatingPresentationMode: .floatingCard,
            macIslandExpandedHoldDuration: .balanced,
            macIslandExpansionTrigger: .hoverAndClick,
            macIslandHoverExpandDelay: 3,
            menuBarLyricMode: .translated,
            convertsTraditionalChineseToSimplified: true
        )
        preferences.save(to: defaults)

        let restored = LyrisDisplayPreferences.load(from: defaults)
        XCTAssertEqual(restored.interfaceSkin, .midnightAurora)
        XCTAssertEqual(restored.artworkPresentationMode, .ambientMotion)
        XCTAssertEqual(restored.customTranslationFontFamily, "Fixture Font")
        XCTAssertTrue(restored.convertsTraditionalChineseToSimplified)
        XCTAssertEqual(restored.floatingPresentationMode, .floatingCard)
        XCTAssertEqual(restored.macIslandExpansionTrigger, .hoverAndClick)
        XCTAssertEqual(restored.macIslandHoverExpandDelay, 3)
    }

    func testIslandExpansionTriggerSeparatesHoverAndClickBehavior() {
        XCTAssertTrue(MacIslandExpansionTrigger.hover.allowsHover)
        XCTAssertFalse(MacIslandExpansionTrigger.hover.allowsClick)
        XCTAssertFalse(MacIslandExpansionTrigger.click.allowsHover)
        XCTAssertTrue(MacIslandExpansionTrigger.click.allowsClick)
        XCTAssertTrue(MacIslandExpansionTrigger.hoverAndClick.allowsHover)
        XCTAssertTrue(MacIslandExpansionTrigger.hoverAndClick.allowsClick)
    }

    func testCompactIslandStatusItemRoutesClickToExpansion() {
        XCTAssertEqual(
            LyrisStatusItemActionPolicy.primaryAction(
                mode: .topIsland,
                islandState: .compact,
                trigger: .hoverAndClick
            ),
            .expandIsland
        )
        XCTAssertEqual(
            LyrisStatusItemActionPolicy.primaryAction(
                mode: .topIsland,
                islandState: .compact,
                trigger: .hover
            ),
            .togglePopover
        )
        XCTAssertEqual(
            LyrisStatusItemActionPolicy.primaryAction(
                mode: .topIsland,
                islandState: .expanded,
                trigger: .hoverAndClick
            ),
            .togglePopover
        )
    }

    func testFetchedTranslationModelCatalogPersistsOnlyForMatchingEndpoint() throws {
        let suiteName = "LyrisPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        LyrisTranslationModelCatalogPersistence.save(
            models: ["model-b", "model-a", "model-b"],
            provider: .deepSeek,
            baseURL: "https://api.deepseek.com/",
            to: defaults
        )

        XCTAssertEqual(
            LyrisTranslationModelCatalogPersistence.load(
                provider: .deepSeek,
                baseURL: "https://api.deepseek.com",
                from: defaults
            ),
            ["model-a", "model-b"]
        )
        XCTAssertEqual(
            LyrisTranslationModelCatalogPersistence.load(
                provider: .openAI,
                baseURL: "https://api.deepseek.com",
                from: defaults
            ),
            []
        )
        XCTAssertEqual(
            LyrisTranslationModelCatalogPersistence.load(
                provider: .deepSeek,
                baseURL: "https://example.com/v1",
                from: defaults
            ),
            []
        )
    }

    func testPresentationMenuDoesNotKeepTheNativeFocusRing() {
        XCTAssertFalse(LyrisPresentationModeMenuPolicy.acceptsKeyboardFocus)
    }

    func testPresentationChoicesStayAvailableAndPersist() throws {
        let suiteName = "LyrisPresentationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(FloatingPresentationMode.floatingCard.rawValue, forKey: "floatingPresentationMode")

        XCTAssertEqual(
            LyrisDisplayPreferences.load(from: defaults).floatingPresentationMode,
            .floatingCard
        )
        XCTAssertEqual(
            FloatingPresentationMode.allCases,
            [.topIsland, .floatingCard, .desktopLyrics]
        )
        XCTAssertEqual(FloatingPresentationMode.topIsland.next, .floatingCard)
        XCTAssertEqual(FloatingPresentationMode.floatingCard.next, .desktopLyrics)
        XCTAssertEqual(FloatingPresentationMode.desktopLyrics.next, .topIsland)
    }

    func testFontSearchMatchesFamilyNamesCaseInsensitively() {
        let families = ["PingFang SC", "Songti SC", "SF Pro", "Arial"]

        XCTAssertEqual(
            LyrisFontSearch.filteredFamilies(families, query: "song"),
            ["Songti SC"]
        )
        XCTAssertEqual(
            LyrisFontSearch.filteredFamilies(families, query: "  sf  "),
            ["SF Pro"]
        )
        XCTAssertEqual(
            LyrisFontSearch.filteredFamilies(families, query: ""),
            families
        )
    }

    func testFontSearchIgnoresSpacingAndPunctuationUsedByInstalledFontNames() {
        let families = ["Alibaba PuHuiTi 3.0", "PingFang SC", "SF Pro Display"]

        XCTAssertEqual(
            LyrisFontSearch.filteredFamilies(families, query: "AlibabaPuHuiTi3"),
            ["Alibaba PuHuiTi 3.0"]
        )
        XCTAssertEqual(
            LyrisFontSearch.filteredFamilies(families, query: "sf-pro"),
            ["SF Pro Display"]
        )
    }

    func testFontRecommendationUsesLanguageAppropriateMacFamilies() {
        XCTAssertEqual(
            LyrisFontRecommendation.recommendation(
                for: .simplifiedChinese,
                availableFamilies: ["Arial", "PingFang SC"]
            ),
            .init(choice: .pingFang, customFamily: nil, displayName: "苹方")
        )
        XCTAssertEqual(
            LyrisFontRecommendation.recommendation(
                for: .japanese,
                availableFamilies: ["Arial", "Hiragino Sans"]
            ),
            .init(choice: .custom, customFamily: "Hiragino Sans", displayName: "Hiragino Sans")
        )
        XCTAssertEqual(
            LyrisFontRecommendation.recommendation(
                for: .korean,
                availableFamilies: ["Arial", "Apple SD Gothic Neo"]
            ),
            .init(choice: .custom, customFamily: "Apple SD Gothic Neo", displayName: "Apple SD Gothic Neo")
        )
    }

    func testLinkedEffectProfilesAreVisiblyDistinctAndOffDisablesRendering() {
        let enabled = [
            LinkedEffectStyle.aurora.profile,
            LinkedEffectStyle.pulse.profile,
        ]

        XCTAssertEqual(Set(enabled).count, enabled.count)
        XCTAssertTrue(enabled.allSatisfy(\.isEnabled))
        XCTAssertFalse(LinkedEffectStyle.off.profile.isEnabled)
        XCTAssertEqual(LinkedEffectStyle.spectrum.normalized, .aurora)
        XCTAssertEqual(LinkedEffectStyle.spectrum.profile, LinkedEffectStyle.aurora.profile)
        XCTAssertGreaterThan(
            LinkedEffectStyle.pulse.profile.borderIntensity,
            LinkedEffectStyle.aurora.profile.borderIntensity
        )
    }

    func testLinkedEffectPickerRemovesSpectrumAndCyclesWithinLightFlowStyles() {
        XCTAssertEqual(LinkedEffectStyle.allCases, [.aurora, .pulse, .off])
        XCTAssertEqual(LinkedEffectStyle.aurora.next, .pulse)
        XCTAssertEqual(LinkedEffectStyle.pulse.next, .off)
        XCTAssertEqual(LinkedEffectStyle.spectrum.next, .aurora)
    }

    func testSettingsMaterialReflectsTheSelectedLinkedEffect() {
        let aurora = LyrisSettingsMaterialProfile.resolve(style: .aurora)
        let pulse = LyrisSettingsMaterialProfile.resolve(style: .pulse)
        let off = LyrisSettingsMaterialProfile.resolve(style: .off)

        XCTAssertGreaterThan(aurora.effectOpacity, 0)
        XCTAssertGreaterThan(pulse.effectOpacity, aurora.effectOpacity)
        XCTAssertEqual(off.effectOpacity, 0)
        XCTAssertTrue(aurora.animates)
        XCTAssertTrue(pulse.animates)
        XCTAssertFalse(off.animates)
    }

    func testLinkedEffectKeepsAmbientMotionWhilePlaybackIsPaused() {
        XCTAssertFalse(
            LyrisLinkedEffectMotionPolicy.timelineIsPaused(style: .aurora)
        )
        XCTAssertFalse(
            LyrisLinkedEffectMotionPolicy.timelineIsPaused(style: .pulse)
        )
        XCTAssertTrue(
            LyrisLinkedEffectMotionPolicy.timelineIsPaused(style: .off)
        )
        XCTAssertEqual(
            LyrisLinkedEffectMotionPolicy.phaseScale(isPlaying: true),
            1
        )
        XCTAssertEqual(
            LyrisLinkedEffectMotionPolicy.phaseScale(isPlaying: false),
            0.28
        )
    }

    func testFetchedTranslationModelsBecomeStablePickerOptions() {
        XCTAssertEqual(
            LyrisTranslationModelSelection.options(
                available: ["model-b", "model-a", "model-b", "  "],
                current: "model-b"
            ),
            ["model-a", "model-b"]
        )
        XCTAssertEqual(
            LyrisTranslationModelSelection.options(
                available: [],
                current: "manual-model"
            ),
            ["manual-model"]
        )
        XCTAssertTrue(
            LyrisTranslationModelSelection.usesFetchedPicker(
                available: ["model-a"]
            )
        )
        XCTAssertFalse(
            LyrisTranslationModelSelection.usesFetchedPicker(
                available: []
            )
        )
    }

    func testCompactTopPlayerMaterialRemainsHardwareBlackAcrossSkins() {
        let profile = LyrisTopPlayerMaterialProfile.resolve(for: .compact)

        XCTAssertTrue(profile.usesHardwareBlack)
        XCTAssertEqual(profile.skinTintOpacity, 0)
        XCTAssertEqual(profile.linkedEffectOpacity, 0)
        XCTAssertEqual(profile.edgeLightOpacity, 0)
    }

    func testSynchronizedMarqueeKeepsEndsStillAndTravelsWithLyricProgress() {
        XCTAssertEqual(LyrisSynchronizedMarqueeText.travelProgress(for: 0), 0)
        XCTAssertEqual(LyrisSynchronizedMarqueeText.travelProgress(for: 0.12), 0)
        XCTAssertGreaterThan(LyrisSynchronizedMarqueeText.travelProgress(for: 0.5), 0)
        XCTAssertLessThan(LyrisSynchronizedMarqueeText.travelProgress(for: 0.5), 1)
        XCTAssertEqual(LyrisSynchronizedMarqueeText.travelProgress(for: 0.88), 1)
        XCTAssertEqual(LyrisSynchronizedMarqueeText.travelProgress(for: 1), 1)
    }

    func testSynchronizedMarqueeCentersShortLyricsAndScrollsOnlyOverflow() {
        XCTAssertEqual(
            LyrisSynchronizedMarqueeText.horizontalOffset(
                contentWidth: 120,
                containerWidth: 340,
                progress: 0.5
            ),
            110
        )
        XCTAssertEqual(
            LyrisSynchronizedMarqueeText.horizontalOffset(
                contentWidth: 440,
                containerWidth: 340,
                progress: 0
            ),
            0
        )
        XCTAssertEqual(
            LyrisSynchronizedMarqueeText.horizontalOffset(
                contentWidth: 440,
                containerWidth: 340,
                progress: 1
            ),
            -100
        )
    }

    func testExpandedTopPlayerMaterialKeepsThemeAsLocalizedLightFlow() {
        let profile = LyrisTopPlayerMaterialProfile.resolve(for: .expanded)

        XCTAssertFalse(profile.usesHardwareBlack)
        XCTAssertGreaterThan(profile.linkedEffectOpacity, 0)
        XCTAssertLessThanOrEqual(profile.skinTintOpacity, 0.08)
        XCTAssertGreaterThan(profile.edgeLightOpacity, 0)
    }

    func testTraditionalChineseCanRenderAsSimplifiedAndUseNextLineAsSecondary() {
        let current = TimedLyric(startTime: 0, original: "抬頭閉眼讓淚流進心裡面", translation: "")
        let next = TimedLyric(startTime: 4, original: "下一句歌詞", translation: "")

        XCTAssertEqual(
            LyrisLyricDisplayPolicy.originalText(
                current.original,
                convertsTraditionalChineseToSimplified: true
            ),
            "抬头闭眼让泪流进心里面"
        )
        XCTAssertEqual(
            LyrisLyricDisplayPolicy.secondaryText(
                for: current,
                in: [current, next],
                translatedText: nil,
                convertsTraditionalChineseToSimplified: true
            ),
            "下一句歌词"
        )
    }

    func testDistinctTranslationWinsOverNextLineFallback() {
        let current = TimedLyric(startTime: 0, original: "Hello", translation: "")
        let next = TimedLyric(startTime: 4, original: "Next", translation: "")

        XCTAssertEqual(
            LyrisLyricDisplayPolicy.secondaryText(
                for: current,
                in: [current, next],
                translatedText: "你好",
                convertsTraditionalChineseToSimplified: true
            ),
            "你好"
        )
    }

    func testSeekInteractionClampsPointerLocationAndCalculatesPosition() {
        XCTAssertEqual(LyrisSeekInteraction.normalizedProgress(x: -20, width: 200), 0)
        XCTAssertEqual(LyrisSeekInteraction.normalizedProgress(x: 80, width: 200), 0.4)
        XCTAssertEqual(LyrisSeekInteraction.normalizedProgress(x: 260, width: 200), 1)
        XCTAssertEqual(
            LyrisSeekInteraction.position(x: 80, width: 200, duration: 300),
            120,
            accuracy: 0.001
        )
    }

    func testPricingCatalogIncludesProviderSourceAndCurrentModelRates() {
        let deepSeek = TranslationPricingCatalog.reference(
            provider: .deepSeek,
            model: "deepseek-v4-flash"
        )
        XCTAssertEqual(deepSeek.rates.inputUSDPerMillion, 0.44)
        XCTAssertEqual(deepSeek.rates.outputUSDPerMillion, 1.32)
        XCTAssertEqual(deepSeek.verifiedDate, "2026-08-18")
        XCTAssertNotNil(deepSeek.sourceURL)

        let openAI = TranslationPricingCatalog.reference(
            provider: .openAI,
            model: "gpt-5.6-terra"
        )
        XCTAssertEqual(openAI.rates.inputUSDPerMillion, 2.5)
        XCTAssertEqual(openAI.rates.outputUSDPerMillion, 15)
        XCTAssertNotNil(openAI.sourceURL)
    }

    func testDeepSeekOfficialPricingParserSelectsCurrentPeriodAndModelColumn() throws {
        let officialFixture = """
        1M INPUT TOKENS (CACHE MISS) OFF-PEAK $0.22 $0.66 PEAK $0.44 $1.32
        1M OUTPUT TOKENS OFF-PEAK $0.66 $1.98 PEAK $1.32 $3.96
        Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC
        """
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let peakDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 2))
        )
        let offPeakDate = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))
        )

        let flashPeak = try DeepSeekOfficialPricingParser.parse(
            pageText: officialFixture,
            model: "deepseek-v4-flash",
            now: peakDate
        )
        XCTAssertEqual(flashPeak.rates.inputUSDPerMillion, 0.44)
        XCTAssertEqual(flashPeak.rates.outputUSDPerMillion, 1.32)
        XCTAssertEqual(flashPeak.period, .peak)

        let proOffPeak = try DeepSeekOfficialPricingParser.parse(
            pageText: officialFixture,
            model: "deepseek-v4-pro",
            now: offPeakDate
        )
        XCTAssertEqual(proOffPeak.rates.inputUSDPerMillion, 0.66)
        XCTAssertEqual(proOffPeak.rates.outputUSDPerMillion, 1.98)
        XCTAssertEqual(proOffPeak.period, .offPeak)
    }

    func testNotchedScreenProducesAConnectedTopPlayerAtThePhysicalTopEdge() {
        let metrics = LyrisScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 63, width: 1_512, height: 886),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 665, height: 32),
            auxiliaryTopRightArea: CGRect(x: 850, y: 950, width: 662, height: 32)
        )

        let configuration = LyrisTopPlayerGeometry.configuration(for: metrics)
        let frame = LyrisTopPlayerGeometry.frame(
            configuration: configuration,
            metrics: metrics
        )

        XCTAssertTrue(configuration.hasCameraHousing)
        XCTAssertEqual(configuration.cameraInset, 32)
        XCTAssertEqual(configuration.cameraWidth, 185)
        XCTAssertEqual(configuration.hostSize, CGSize(width: 1_080, height: 164))
        XCTAssertEqual(frame.maxY, metrics.frame.maxY)
        XCTAssertEqual(frame.midX, metrics.frame.midX)
    }

    func testNonNotchedScreenUsesVisibleTopAndNoCameraAttachment() {
        let metrics = LyrisScreenMetrics(
            frame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: 1_512, y: 0, width: 1_920, height: 1_055),
            safeAreaTop: 0,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let configuration = LyrisTopPlayerGeometry.configuration(for: metrics)
        let frame = LyrisTopPlayerGeometry.frame(
            configuration: configuration,
            metrics: metrics
        )

        XCTAssertFalse(configuration.hasCameraHousing)
        XCTAssertEqual(configuration.cameraInset, 0)
        XCTAssertEqual(configuration.cameraWidth, 0)
        XCTAssertEqual(
            LyrisTopPlayerGeometry.visualSize(
                configuration: configuration,
                state: .compact
            ),
            CGSize(width: 480, height: 36)
        )
        XCTAssertEqual(
            LyrisTopPlayerGeometry.compactContentWidth(configuration: configuration),
            LyrisTopPlayerGeometry.compactExternalWidth
        )
        XCTAssertEqual(
            frame.maxY,
            metrics.visibleFrame.maxY - LyrisTopPlayerGeometry.externalTopInset
        )
    }

    func testWaveformIsTrackSeededAndDeterministic() {
        let first = LyrisWaveformModel.heights(count: 48, seed: "demo:track:a")
        XCTAssertEqual(first, LyrisWaveformModel.heights(count: 48, seed: "demo:track:a"))
        XCTAssertNotEqual(first, LyrisWaveformModel.heights(count: 48, seed: "demo:track:b"))
        XCTAssertTrue(first.allSatisfy { (0.12...1).contains($0) })
    }

    func testFlowThreadsAreDenseDeterministicAndInterwoven() {
        let first = LyrisFlowThreadModel.threads(
            count: 14,
            seed: "demo:track:northbound"
        )
        XCTAssertEqual(
            first,
            LyrisFlowThreadModel.threads(
                count: 14,
                seed: "demo:track:northbound"
            )
        )
        XCTAssertNotEqual(
            first,
            LyrisFlowThreadModel.threads(count: 14, seed: "another-track")
        )
        XCTAssertEqual(first.count, 14)
        XCTAssertTrue(first.allSatisfy { (0.50...0.86).contains($0.lineWidth) })
        XCTAssertTrue(first.allSatisfy { (0.28...0.62).contains($0.opacity) })

        let sampleXs = stride(from: 0.0, through: 1.0, by: 0.05).map {
            CGFloat($0)
        }
        for phase in [0.0, 1.5, 60.0] {
            XCTAssertTrue(first.allSatisfy { thread in
                sampleXs.allSatisfy { x in
                    (0...1).contains(
                        LyrisFlowThreadModel.normalizedY(
                            for: thread,
                            normalizedX: x,
                            phase: phase
                        )
                    )
                }
            })
        }

        let crossingPairs = first.indices.dropLast().reduce(into: 0) { count, lhs in
            for rhs in first.indices where rhs > lhs {
                let leftDelta = LyrisFlowThreadModel.normalizedY(
                    for: first[lhs],
                    normalizedX: 0.18,
                    phase: 0
                ) - LyrisFlowThreadModel.normalizedY(
                    for: first[rhs],
                    normalizedX: 0.18,
                    phase: 0
                )
                let rightDelta = LyrisFlowThreadModel.normalizedY(
                    for: first[lhs],
                    normalizedX: 0.82,
                    phase: 0
                ) - LyrisFlowThreadModel.normalizedY(
                    for: first[rhs],
                    normalizedX: 0.82,
                    phase: 0
                )
                if leftDelta * rightDelta < 0 {
                    count += 1
                }
            }
        }
        XCTAssertGreaterThan(crossingPairs, 3)
    }

    func testFlowThreadsKeepVisibleMotion() {
        let threads = LyrisFlowThreadModel.threads(
            count: 14,
            seed: "visible-flow-motion"
        )
        let sampleXs: [CGFloat] = [0.16, 0.34, 0.52, 0.70, 0.88]
        let displacements = threads.flatMap { thread in
            sampleXs.map { x in
                abs(
                    LyrisFlowThreadModel.normalizedY(
                        for: thread,
                        normalizedX: x,
                        phase: LinkedEffectStyle.aurora.profile.animationRate
                    ) - LyrisFlowThreadModel.normalizedY(
                        for: thread,
                        normalizedX: x,
                        phase: 0
                    )
                )
            }
        }
        let meanDisplacement = displacements.reduce(0, +)
            / CGFloat(max(displacements.count, 1))

        XCTAssertGreaterThan(meanDisplacement, 0.003)
    }

    func testFlowThreadRenderingStaysInsideTheInteractiveFrameBudget() {
        XCTAssertEqual(LyrisFlowThreadRenderPolicy.renderSurfaceCount, 1)
        XCTAssertEqual(LyrisFlowThreadRenderPolicy.framesPerSecond, 24)
        XCTAssertEqual(
            LyrisFlowThreadRenderPolicy.maximumPointCountPerFrame,
            12 * 48
        )
        XCTAssertEqual(LyrisLinkedEffectMotionPolicy.framesPerSecond, 24)
        XCTAssertEqual(LyrisAmbientParticleRenderPolicy.maximumCount, 90)
    }

    func testOrbitalBreathingUsesTwoPrimaryAndFourEchoRings() {
        let rings = LyrisOrbitalRingModel.rings(seed: "drop-top")
        XCTAssertEqual(rings.count, 6)
        XCTAssertEqual(rings.filter(\.isPrimary).count, 2)
        XCTAssertEqual(rings.filter { !$0.isPrimary }.count, 4)

        let first = rings.map {
            LyrisOrbitalRingModel.normalizedRect(for: $0, phase: 0)
        }
        let later = rings.map {
            LyrisOrbitalRingModel.normalizedRect(for: $0, phase: 1.5)
        }
        XCTAssertTrue(first.allSatisfy { rect in
            rect.minX >= 0 && rect.maxX <= 1
                && rect.minY >= 0.42 && rect.maxY <= 0.94
        })
        XCTAssertNotEqual(first, later)
    }

    func testCounterpointUsesTwoPrimarySixEchoesAndMultipleInterweaves() {
        let voices = LyrisCounterpointModel.voices(seed: "drop-top")
        XCTAssertEqual(voices.count, 8)
        XCTAssertEqual(voices.filter(\.isPrimary).count, 2)
        XCTAssertEqual(voices.filter { !$0.isPrimary }.count, 6)
        XCTAssertGreaterThan(
            LyrisCounterpointModel.travelPhase(for: voices[0], phase: 1),
            0
        )
        XCTAssertLessThan(
            LyrisCounterpointModel.travelPhase(for: voices[1], phase: 1),
            0
        )

        let crossing: CGFloat = 0.58
        let firstPrimary = voices[0]
        let secondPrimary = voices[1]
        let deltas = stride(from: 0.0, through: 1.0, by: 0.01).map { sample in
            let x = CGFloat(sample)
            return LyrisCounterpointModel.normalizedY(
                for: firstPrimary,
                normalizedX: x,
                crossingX: crossing,
                phase: 0
            ) - LyrisCounterpointModel.normalizedY(
                for: secondPrimary,
                normalizedX: x,
                crossingX: crossing,
                phase: 0
            )
        }
        let interweaves = zip(deltas, deltas.dropFirst()).filter { lhs, rhs in
            lhs * rhs < 0
        }.count
        XCTAssertGreaterThanOrEqual(interweaves, 2)

        let initial = LyrisCounterpointModel.normalizedY(
            for: firstPrimary,
            normalizedX: 0.28,
            crossingX: crossing,
            phase: 0
        )
        let animated = LyrisCounterpointModel.normalizedY(
            for: firstPrimary,
            normalizedX: 0.28,
            crossingX: crossing,
            phase: 0.45
        )
        XCTAssertNotEqual(initial, animated)
        XCTAssertEqual(LyrisExpandedIslandEffectPolicy.composition, .counterpoint)
        XCTAssertEqual(LyrisExpandedIslandEffectPolicy.motionMultiplier, 2.8)
        XCTAssertEqual(LyrisExpandedIslandEffectPolicy.opacity, 0.50)
        XCTAssertEqual(LyrisExpandedIslandEffectPolicy.framesPerSecond, 30)
    }

    func testCounterpointCurvesAreIrregularAndEdgeDissolveIsSymmetric() {
        XCTAssertEqual(LyrisCounterpointDissolvePolicy.leadingBoundary, 0.25)
        XCTAssertEqual(LyrisCounterpointDissolvePolicy.trailingBoundary, 0.78)
        XCTAssertEqual(
            LyrisCounterpointDissolvePolicy.region(at: 0.10),
            .particlesOnly
        )
        XCTAssertEqual(
            LyrisCounterpointDissolvePolicy.region(at: 0.20),
            .fragmentedLine
        )
        XCTAssertEqual(
            LyrisCounterpointDissolvePolicy.region(at: 0.50),
            .continuousLine
        )
        XCTAssertEqual(
            LyrisCounterpointDissolvePolicy.region(at: 0.84),
            .fragmentedLine
        )
        XCTAssertEqual(
            LyrisCounterpointDissolvePolicy.region(at: 0.96),
            .particlesOnly
        )
        let fineBlend = LyrisCounterpointDissolvePolicy.fragmentOpacity(
            for: .fine,
            progress: 0.22
        )
        let mediumBlend = LyrisCounterpointDissolvePolicy.fragmentOpacity(
            for: .medium,
            progress: 0.52
        )
        let coarseBlend = LyrisCounterpointDissolvePolicy.fragmentOpacity(
            for: .coarse,
            progress: 0.84
        )
        XCTAssertGreaterThan(fineBlend, mediumBlend * 0.55)
        XCTAssertGreaterThan(mediumBlend, coarseBlend * 0.55)
        XCTAssertGreaterThan(coarseBlend, 0.55)

        let transitionSamples = stride(
            from: CGFloat(0.08),
            through: CGFloat(0.92),
            by: CGFloat(0.04)
        ).map { progress in
            LyrisCounterpointFragmentTexture.allCases.reduce(0.0) { total, texture in
                total + LyrisCounterpointDissolvePolicy.fragmentOpacity(
                    for: texture,
                    progress: progress
                )
            }
        }
        XCTAssertTrue(transitionSamples.allSatisfy { $0 > 0.18 })
        let adjacentBlendChanges = zip(
            transitionSamples.dropFirst(),
            transitionSamples
        ).map { next, previous in
            abs(next - previous)
        }
        XCTAssertLessThan(adjacentBlendChanges.max() ?? 1, 0.36)

        let voices = LyrisCounterpointModel.voices(seed: "irregular-curve")
        let lead = voices[0]
        let crossing: CGFloat = 0.56
        let samples: [CGFloat] = [0.14, 0.28, 0.42, 0.70, 0.84]
        let values = samples.map { x in
            LyrisCounterpointModel.normalizedY(
                for: lead,
                normalizedX: x,
                crossingX: crossing,
                phase: 0.6
            )
        }
        let firstDifferences = zip(values.dropFirst(), values).map { next, previous in
            next - previous
        }
        let curvature = zip(
            firstDifferences.dropFirst(),
            firstDifferences
        ).map { next, previous in
            next - previous
        }
        XCTAssertGreaterThan(curvature.map(abs).max() ?? 0, 0.015)

        let particles = LyrisAmbientParticleModel.particles(
            count: LyrisCounterpointDissolveModel.particleCount,
            seed: "counterpoint-dissolve"
        )
        let positions = particles.indices.map { index in
            LyrisCounterpointDissolveModel.normalizedPosition(
                for: particles[index],
                index: index,
                voices: voices,
                crossingX: crossing,
                phase: 0.6
            )
        }
        XCTAssertEqual(positions.filter { $0.x < 0.5 }.count, positions.count / 2)
        XCTAssertEqual(positions.filter { $0.x > 0.5 }.count, positions.count / 2)
        XCTAssertTrue(positions.allSatisfy { position in
            position.x <= 0.24 || position.x >= 0.76
        })
    }

    func testAmbientParticlesAreDeterministicTrackSeededAndRemainInBounds() {
        let first = LyrisAmbientParticleModel.particles(
            count: 96,
            seed: "demo:track:northbound"
        )
        XCTAssertEqual(
            first,
            LyrisAmbientParticleModel.particles(
                count: 96,
                seed: "demo:track:northbound"
            )
        )
        XCTAssertNotEqual(
            first,
            LyrisAmbientParticleModel.particles(count: 96, seed: "another-track")
        )
        XCTAssertEqual(first.count, 96)
        XCTAssertTrue(first.allSatisfy { (0...1).contains($0.baseX) })
        XCTAssertTrue(first.allSatisfy { (0...1).contains($0.baseY) })
        XCTAssertTrue(first.allSatisfy { (0.45...1.8).contains($0.radius) })
        XCTAssertTrue(first.allSatisfy { (0.055...0.30).contains($0.opacity) })

        for phase in [0.0, 1.5, 60.0, 3_600.0] {
            XCTAssertTrue(first.allSatisfy { particle in
                let position = LyrisAmbientParticleModel.normalizedPosition(
                    for: particle,
                    phase: phase
                )
                return (0...1).contains(position.x) && (0...1).contains(position.y)
            })
        }
    }

    func testAuroraParticlesTravelAVisibleDistanceWithinOneSecond() {
        let particles = LyrisAmbientParticleModel.particles(
            count: 96,
            seed: "visible-motion-fixture"
        )
        let displacements = particles.map { particle -> Double in
            let start = LyrisAmbientParticleModel.normalizedPosition(
                for: particle,
                phase: 0
            )
            let end = LyrisAmbientParticleModel.normalizedPosition(
                for: particle,
                phase: LinkedEffectStyle.aurora.profile.animationRate
            )
            return hypot(Double(end.x - start.x), Double(end.y - start.y))
        }
        let meanDisplacement = displacements.reduce(0, +)
            / Double(max(displacements.count, 1))

        // Roughly 3px per second on a 1000pt surface. Anything below this is
        // technically animated but visually indistinguishable from static.
        XCTAssertGreaterThan(meanDisplacement, 0.003)
    }

    func testMainWindowPlacementDoesNotOverlapPersistentTopPlayer() {
        let visibleFrame = CGRect(x: 0, y: 63, width: 1_512, height: 886)
        let topPlayerFrame = CGRect(x: 316, y: 858, width: 880, height: 124)

        let mainFrame = LyrisWindowPlacementPolicy.mainWindowFrame(
            windowSize: CGSize(width: 1_020, height: 720),
            visibleFrame: visibleFrame,
            topPlayerFrame: topPlayerFrame
        )

        XCTAssertFalse(mainFrame.intersects(topPlayerFrame))
        XCTAssertEqual(
            topPlayerFrame.minY - mainFrame.maxY,
            LyrisWindowPlacementPolicy.topPlayerGap
        )
        XCTAssertTrue(visibleFrame.contains(mainFrame))
    }

    func testIslandStatesStayCompactUntilInteractionRequiresExpansion() {
        let configuration = LyrisTopPlayerConfiguration(
            hostSize: CGSize(width: 880, height: 124),
            cameraInset: 32,
            cameraWidth: 185,
            hasCameraHousing: true
        )

        XCTAssertEqual(
            LyrisTopPlayerGeometry.visualSize(
                configuration: configuration,
                state: .compact
            ),
            CGSize(width: 465, height: 56)
        )
        XCTAssertEqual(LyrisTopPlayerGeometry.compactWingWidth, 140)
        XCTAssertEqual(LyrisTopPlayerGeometry.compactShelfDepth, 24)
        XCTAssertEqual(LyrisTopPlayerGeometry.compactLyricShelfWidth, 250)
        XCTAssertEqual(LyrisTopPlayerGeometry.compactLyricFontSize, 11.5)
        XCTAssertEqual(LyrisTopPlayerGeometry.compactEndCapInset, 1)
        XCTAssertEqual(LyrisTopPlayerGeometry.compactShelfShoulderInset, 22)
        XCTAssertEqual(
            LyrisTopPlayerGeometry.compactShoulderSlope,
            22.0 / 24.0,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            LyrisTopPlayerGeometry.compactOuterClosureInset(topBandHeight: 32),
            29.333_333,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyrisTopPlayerGeometry.compactShoulderControlDistance(for: 22),
            10
        )
        XCTAssertEqual(
            LyrisTopPlayerGeometry.compactShoulderControlDistance(for: 29.333_333),
            10
        )
        XCTAssertEqual(
            LyrisTopPlayerGeometry.visualSize(
                configuration: configuration,
                state: .expanded
            ),
            CGSize(width: 880, height: 124)
        )

        let metrics = LyrisScreenMetrics(
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 63, width: 1_512, height: 886),
            safeAreaTop: 32,
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 665, height: 32),
            auxiliaryTopRightArea: CGRect(x: 850, y: 950, width: 662, height: 32)
        )
        let panelFrame = LyrisTopPlayerGeometry.panelFrame(
            configuration: configuration,
            metrics: metrics,
            state: .compact
        )
        let visualFrame = LyrisTopPlayerGeometry.frame(
            configuration: configuration,
            metrics: metrics,
            state: .compact
        )
        let expandedFrame = LyrisTopPlayerGeometry.panelFrame(
            configuration: configuration,
            metrics: metrics,
            state: .expanded
        )
        XCTAssertEqual(panelFrame.maxY, metrics.frame.maxY)
        XCTAssertEqual(visualFrame.midX, metrics.frame.midX, accuracy: 0.5)
        XCTAssertEqual(panelFrame.size, CGSize(width: 490, height: 66))
        XCTAssertEqual(expandedFrame.maxY, panelFrame.maxY)
        XCTAssertLessThan(expandedFrame.minY, panelFrame.minY)
        XCTAssertGreaterThan(expandedFrame.width, panelFrame.width)
    }

    func testLockedIslandStaysExpandedUntilExplicitlyUnlocked() async {
        await MainActor.run {
            let model = LyrisIslandModel()

            model.expand()
            model.toggleLockedOpen()
            model.collapseImmediately()

            XCTAssertTrue(model.isLockedOpen)
            XCTAssertEqual(model.state, .expanded)

            model.toggleLockedOpen()
            model.collapseImmediately()

            XCTAssertFalse(model.isLockedOpen)
            XCTAssertEqual(model.state, .compact)
        }
    }

    func testExplicitCollapseAlsoClearsTheIslandLock() async {
        await MainActor.run {
            let model = LyrisIslandModel()

            model.expand()
            model.setLockedOpen(true)
            model.collapseByUserRequest()

            XCTAssertFalse(model.isLockedOpen)
            XCTAssertEqual(model.state, .compact)
        }
    }

    func testIslandOnlyExpandsAfterHoverDelayCompletes() async throws {
        let model = await MainActor.run { LyrisIslandModel() }
        await MainActor.run {
            model.expand(after: 0.08)
            XCTAssertEqual(model.state, .compact)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        await MainActor.run {
            XCTAssertEqual(model.state, .compact)
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        await MainActor.run {
            XCTAssertEqual(model.state, .expanded)
        }
    }

    func testAuthoritativePointerDwellExpandsAfterContinuousThreeSecondHover() {
        var tracker = LyrisHoverDwellTracker()

        XCTAssertFalse(tracker.shouldExpand(isInside: true, uptime: 10, delay: 3))
        XCTAssertFalse(tracker.shouldExpand(isInside: true, uptime: 12.99, delay: 3))
        XCTAssertTrue(tracker.shouldExpand(isInside: true, uptime: 13.01, delay: 3))

        tracker.reset()
        XCTAssertFalse(tracker.shouldExpand(isInside: true, uptime: 20, delay: 3))
        XCTAssertFalse(tracker.shouldExpand(isInside: false, uptime: 21, delay: 3))
        XCTAssertFalse(tracker.shouldExpand(isInside: true, uptime: 23.9, delay: 3))
        XCTAssertFalse(tracker.shouldExpand(isInside: true, uptime: 26.8, delay: 3))
        XCTAssertTrue(tracker.shouldExpand(isInside: true, uptime: 26.91, delay: 3))
    }

    func testLeavingBeforeHoverDelayCancelsExpansion() async throws {
        let model = await MainActor.run { LyrisIslandModel() }
        await MainActor.run {
            model.expand(after: 0.05)
            model.cancelPendingExpansion()
        }
        try await Task.sleep(nanoseconds: 80_000_000)
        await MainActor.run {
            XCTAssertEqual(model.state, .compact)
        }
    }

    func testCompactLyricProjectionUsesTheSelectedModeAndFallsBackSafely() {
        XCTAssertEqual(
            LyrisCompactLyricProjection.text(
                mode: .original,
                original: "Original",
                translated: "译文"
            ),
            "Original"
        )
        XCTAssertEqual(
            LyrisCompactLyricProjection.text(
                mode: .translated,
                original: "Original",
                translated: "译文"
            ),
            "译文"
        )
        XCTAssertEqual(
            LyrisCompactLyricProjection.text(
                mode: .bilingual,
                original: "Original",
                translated: "译文"
            ),
            "Original · 译文"
        )
        XCTAssertEqual(
            LyrisCompactLyricProjection.text(
                mode: .translated,
                original: "中文原文",
                translated: nil
            ),
            "中文原文"
        )
    }

    func testCompactOuterClosureMatchesTheLyricTrayCurveAndProtectsArtwork() {
        let bounds = CGRect(x: 0, y: 0, width: 465, height: 56)
        let geometry = LyrisTopPlayerGeometry.compactOuterClosureGeometry(
            in: bounds,
            topBandBottom: 32
        )

        XCTAssertEqual(geometry.rightTopControl.y, bounds.minY)
        XCTAssertLessThan(geometry.rightTopControl.x, bounds.maxX)
        XCTAssertEqual(geometry.rightBottomControl.y, 32)
        XCTAssertEqual(geometry.leftBottomControl.y, 32)
        XCTAssertEqual(geometry.leftTopControl.y, bounds.minY)
        XCTAssertGreaterThan(geometry.leftTopControl.x, bounds.minX)

        let metadataWidth: CGFloat = 24 + 6 + 78
        let centeredMargin = (LyrisTopPlayerGeometry.compactWingWidth - metadataWidth) / 2
        XCTAssertGreaterThanOrEqual(
            centeredMargin + LyrisTopPlayerGeometry.compactWingContentSafeOffset,
            geometry.leftBottom.x - bounds.minX
        )
    }

    func testFlowThreadEdgesDissolveIntoMovingParticles() {
        let particles = LyrisAmbientParticleModel.particles(
            count: LyrisFlowEdgeDissolveModel.particleCount,
            seed: "flow-edge-dissolve"
        )
        let first = particles.indices.map { index in
            LyrisFlowEdgeDissolveModel.normalizedPosition(
                for: particles[index],
                index: index,
                phase: 0
            )
        }
        let later = particles.indices.map { index in
            LyrisFlowEdgeDissolveModel.normalizedPosition(
                for: particles[index],
                index: index,
                phase: 1.5
            )
        }

        XCTAssertEqual(first.count, LyrisFlowEdgeDissolveModel.particleCount)
        XCTAssertLessThanOrEqual(LyrisFlowEdgeDissolveModel.particleCount, 32)
        XCTAssertTrue(first.allSatisfy { position in
            (position.x <= 0.24 || position.x >= 0.76)
                && (0.52...0.92).contains(position.y)
        })
        XCTAssertNotEqual(first, later)
    }

    func testLyricTextProgressUsesWordTimingAndFallsBackToLineTiming() {
        let lineID = UUID()
        let wordSyncedLine = LyricLine(
            id: lineID,
            startTime: 10,
            endTime: 14,
            original: "Hello world",
            words: [
                LyricWord(text: "Hello", startTime: 10, endTime: 11),
                LyricWord(text: "world", startTime: 12, endTime: 14),
            ]
        )

        XCTAssertEqual(
            LyrisLyricTextProgress.value(
                position: 10.5,
                timingDelay: 0,
                line: wordSyncedLine,
                fallback: 0
            ),
            0.25,
            accuracy: 0.001
        )
        XCTAssertEqual(
            LyrisLyricTextProgress.value(
                position: 13,
                timingDelay: 0,
                line: wordSyncedLine,
                fallback: 0
            ),
            0.75,
            accuracy: 0.001
        )

        let lineSyncedLine = LyricLine(
            id: lineID,
            startTime: 10,
            endTime: 14,
            original: "Fallback"
        )
        XCTAssertEqual(
            LyrisLyricTextProgress.value(
                position: 12,
                timingDelay: 0,
                line: lineSyncedLine,
                fallback: 0.5
            ),
            0.5,
            accuracy: 0.001
        )
    }

    func testMainLyricsProjectionPreservesTheEntireDocument() {
        let lines = (0..<9).map { index in
            TimedLyric(
                startTime: TimeInterval(index * 4),
                original: "Line \(index)",
                translation: "译文 \(index)"
            )
        }

        XCTAssertEqual(
            LyrisLyricsProjection.lines(for: .main, lyrics: lines),
            lines
        )
    }
}
