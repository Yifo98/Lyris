import Foundation
import XCTest
@testable import Lyris

final class FirstUseFlowStateTests: XCTestCase {
    func testFirstLaunchStartsWithLocalLyricsAndNeverAutomaticallyRequestsOAuth() {
        let state = FirstUseFlowState()

        XCTAssertEqual(state.currentStep, .localLyrics)
        XCTAssertEqual(state.localStatus, .notRunning)
        XCTAssertFalse(state.isCompleted)
        XCTAssertEqual(state.nextEffect, .observeLocalSpotify)
        XCTAssertFalse(state.shouldAutomaticallyStartOAuth)
        XCTAssertEqual(
            state.currentStep.title(in: .simplifiedChinese),
            "打开 Spotify，Lyris 会自动显示歌词"
        )
        XCTAssertEqual(
            state.currentStep.title(in: .english),
            "Open Spotify and Lyris will show lyrics automatically"
        )
    }

    func testLocalDetectionReportsEveryRequiredStatusWithBilingualCopy() {
        var state = FirstUseFlowState()
        XCTAssertEqual(state.transition(.continueFromLocalLyrics), .observeLocalSpotify)
        XCTAssertEqual(state.currentStep, .statusDetection)

        let statuses: [LocalLyricsReadiness] = [
            .notInstalled,
            .notRunning,
            .notPlaying,
            .recognized,
            .searchingLyrics,
            .displayed,
        ]

        for status in statuses {
            XCTAssertEqual(state.transition(.localStatusChanged(status)), .none)
            XCTAssertEqual(state.localStatus, status)
            XCTAssertFalse(status.title(in: .simplifiedChinese).isEmpty)
            XCTAssertFalse(status.title(in: .english).isEmpty)
            XCTAssertFalse(status.description(in: .simplifiedChinese).isEmpty)
            XCTAssertFalse(status.description(in: .english).isEmpty)
        }

        XCTAssertEqual(LocalLyricsReadiness.recognized.title(in: .simplifiedChinese), "已识别")
        XCTAssertEqual(LocalLyricsReadiness.searchingLyrics.title(in: .english), "Searching for lyrics")
        XCTAssertEqual(LocalLyricsReadiness.displayed.description(in: .english), "Synchronized lyrics are ready on the card.")
    }

    func testAccountAndTranslationCanBothBeSkipped() {
        var state = FirstUseFlowState()

        _ = state.transition(.continueFromLocalLyrics)
        XCTAssertEqual(state.transition(.continueFromStatusDetection), .none)
        XCTAssertEqual(state.currentStep, .accountEnhancement)
        XCTAssertEqual(state.accountDecision, .undecided)

        XCTAssertEqual(state.transition(.skipAccountEnhancement), .none)
        XCTAssertEqual(state.accountDecision, .skipped)
        XCTAssertEqual(state.currentStep, .translation)

        XCTAssertEqual(state.transition(.skipTranslation), .finished)
        XCTAssertEqual(state.translationDecision, .skipped)
        XCTAssertTrue(state.isCompleted)
        XCTAssertFalse(state.isFirstUse)
        XCTAssertEqual(state.currentStep, .translation)
        XCTAssertEqual(state.nextEffect, .none)
    }

    func testOptionalSetupIsUserInitiatedAndOnlyPresentsConfiguration() {
        var state = FirstUseFlowState()
        _ = state.transition(.continueFromLocalLyrics)
        _ = state.transition(.continueFromStatusDetection)

        XCTAssertEqual(state.transition(.requestAccountEnhancement), .presentAccountSetup)
        XCTAssertEqual(state.currentStep, .accountEnhancement)
        XCTAssertEqual(state.accountDecision, .undecided)
        XCTAssertFalse(state.shouldAutomaticallyStartOAuth)

        XCTAssertEqual(state.transition(.accountEnhancementFinished), .none)
        XCTAssertEqual(state.accountDecision, .configured)
        XCTAssertEqual(state.currentStep, .translation)

        XCTAssertEqual(state.transition(.requestTranslation), .presentTranslationSetup)
        XCTAssertEqual(state.currentStep, .translation)
        XCTAssertEqual(state.translationDecision, .undecided)

        XCTAssertEqual(state.transition(.translationFinished), .finished)
        XCTAssertEqual(state.translationDecision, .configured)
        XCTAssertTrue(state.isCompleted)
    }

    func testCompletedProgressCanBePersistedAndRestored() throws {
        var completed = FirstUseFlowState()
        _ = completed.transition(.continueFromLocalLyrics)
        _ = completed.transition(.continueFromStatusDetection)
        _ = completed.transition(.skipAccountEnhancement)
        _ = completed.transition(.skipTranslation)

        let encoded = try JSONEncoder().encode(completed)
        let restored = try JSONDecoder().decode(FirstUseFlowState.self, from: encoded)

        XCTAssertEqual(restored, completed)
        XCTAssertTrue(restored.isCompleted)
        XCTAssertFalse(restored.isFirstUse)
    }

    func testStepDescriptionsAreBilingualAndExplainOptionalEnhancements() {
        XCTAssertEqual(
            FirstUseStep.statusDetection.description(in: .simplifiedChinese),
            "从 Spotify 是否安装、运行到歌词显示，逐步反馈当前状态。"
        )
        XCTAssertEqual(
            FirstUseStep.accountEnhancement.description(in: .english),
            "Optionally connect with Client ID + PKCE for library and account playback controls."
        )
        XCTAssertEqual(
            FirstUseStep.translation.title(in: .simplifiedChinese),
            "设置歌词翻译（可选）"
        )
    }

    func testFinishLaterNeverStartsOAuthAndMarksOptionalStepsSkipped() {
        var state = FirstUseFlowState()

        XCTAssertEqual(state.transition(.finishLater), .finished)
        XCTAssertTrue(state.isCompleted)
        XCTAssertEqual(state.accountDecision, .skipped)
        XCTAssertEqual(state.translationDecision, .skipped)
        XCTAssertFalse(state.shouldAutomaticallyStartOAuth)
    }
}
