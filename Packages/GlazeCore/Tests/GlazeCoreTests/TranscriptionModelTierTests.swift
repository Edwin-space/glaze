import Testing
@testable import GlazeCore

struct TranscriptionModelTierTests {
    /// A typo here does not fail to compile — it fails at runtime as a model download
    /// error, after the user has already waited. Pin the exact repository names.
    @Test func mapsToWhisperKitRepositoryNames() {
        #expect(TranscriptionModelTier.fast.whisperModelName == "openai_whisper-base")
        #expect(TranscriptionModelTier.balanced.whisperModelName == "openai_whisper-small")
        #expect(TranscriptionModelTier.accurate.whisperModelName == "openai_whisper-large-v3-v20240930_turbo")
        #expect(TranscriptionModelTier.maximum.whisperModelName == "openai_whisper-large-v3")
    }

    @Test func everyTierIsDistinctAndLabelled() {
        let names = Set(TranscriptionModelTier.allCases.map(\.whisperModelName))
        #expect(names.count == TranscriptionModelTier.allCases.count)

        let labels = Set(TranscriptionModelTier.allCases.map(\.labelKey))
        #expect(labels.count == TranscriptionModelTier.allCases.count)
    }

    /// Tiers are presented as a speed/accuracy ladder, so download size must climb
    /// with the tier — otherwise the ordering shown to the user is a lie.
    @Test func downloadSizeIncreasesWithTier() {
        let sizes = TranscriptionModelTier.allCases.map(\.approximateDownloadMegabytes)
        #expect(sizes == sizes.sorted())
    }

    @Test func choicesSurviveAsRawValues() {
        for tier in TranscriptionModelTier.allCases {
            #expect(TranscriptionModelTier(rawValue: tier.rawValue) == tier)
        }
        for quality in SubtitleTranslationQuality.allCases {
            #expect(SubtitleTranslationQuality(rawValue: quality.rawValue) == quality)
        }
    }
}
