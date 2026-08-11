import GlazeCore
import XCTest

final class SubtitlePreparationPlannerTests: XCTestCase {
    func testUsesEmbeddedTrackMatchingPreferredLanguage() {
        let english = EmbeddedSubtitleTrack(streamIndex: 2, codec: "ass", languageCode: "eng")
        let korean = EmbeddedSubtitleTrack(streamIndex: 3, codec: "subrip", languageCode: "kor")

        let plan = SubtitlePreparationPlanner.plan(
            embeddedTracks: [english, korean],
            preferredLanguageCodes: ["ko-KR", "en-US"]
        )

        XCTAssertEqual(plan, .useEmbedded(track: korean))
    }

    func testUsesTimedEmbeddedTrackAsTranslationSourceWhenPreferredLanguageIsMissing() {
        let english = EmbeddedSubtitleTrack(
            streamIndex: 4,
            codec: "ass",
            languageCode: "eng",
            isDefault: true
        )

        let plan = SubtitlePreparationPlanner.plan(
            embeddedTracks: [english],
            preferredLanguageCodes: ["ko"]
        )

        XCTAssertEqual(
            plan,
            .translateEmbedded(sourceTrack: english, targetLanguageCode: "ko")
        )
    }

    func testFallsBackToAudioTranscriptionForBitmapOnlyTracks() {
        let pgs = EmbeddedSubtitleTrack(
            streamIndex: 5,
            codec: "hdmv_pgs_subtitle",
            languageCode: "eng"
        )

        let plan = SubtitlePreparationPlanner.plan(
            embeddedTracks: [pgs],
            preferredLanguageCodes: ["ko"]
        )

        XCTAssertEqual(plan, .transcribeAudio(targetLanguageCode: "ko"))
    }
}
