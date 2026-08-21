import Foundation
import Testing
@testable import GlazeCore

struct SubtitleFileLanguageTests {
    private func language(_ name: String) -> String? {
        SubtitleFile.manual(url: URL(fileURLWithPath: "/tmp/\(name)")).languageCode
    }

    @Test func readsATwoLetterTag() {
        #expect(language("Movie.en.srt") == "en")
    }

    @Test func normalizesAThreeLetterTag() {
        #expect(language("Movie.kor.srt") == "ko")
    }

    @Test func ignoresRegion() {
        #expect(language("Movie.pt-BR.srt") == "pt")
    }

    /// A trailing word is not a language. Without this check `Movie.final.srt` would
    /// claim to be in the language "final" and the translator would be told to trust it.
    @Test func rejectsATrailingWordThatIsNotALanguage() {
        #expect(language("Movie.final.srt") == nil)
    }

    @Test func hasNoLanguageWhenTheNameCarriesNoTag() {
        #expect(language("Movie.srt") == nil)
    }

    /// "und" is how containers say "undetermined"; it must not be taken at face value.
    @Test func rejectsUndetermined() {
        #expect(language("Movie.und.srt") == nil)
    }
}
