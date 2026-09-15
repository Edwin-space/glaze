import Foundation
import Testing
@testable import GlazeBooks
@testable import GlazeCore

@Suite("A file name says which volume it is")
struct BookTitleParserTests {
    @Test("The Korean volume marker is found")
    func koreanVolume() {
        let parsed = BookTitleParser.parse(fileName: "원피스 01권.cbz", kind: .comic)
        #expect(parsed.title == "원피스")
        #expect(parsed.volume == 1)
    }

    @Test("Vol., v and # all mean the same thing")
    func westernMarkers() {
        #expect(BookTitleParser.parse(fileName: "One Piece Vol. 3.cbz", kind: .comic).volume == 3)
        #expect(BookTitleParser.parse(fileName: "One Piece v03.cbz", kind: .comic).volume == 3)
        #expect(BookTitleParser.parse(fileName: "Berserk #14.cbz", kind: .comic).volume == 14)
        #expect(BookTitleParser.parse(fileName: "One Piece Volume 12.cbz", kind: .comic).title == "One Piece")
    }

    @Test("Scan tags and edition notes are not part of the title")
    func brackets() {
        let parsed = BookTitleParser.parse(fileName: "[스캔] 슬램덩크 07 (완전판).cbz", kind: .comic)
        #expect(parsed.title == "슬램덩크")
        #expect(parsed.volume == 7)
    }

    @Test("The last marker wins, so a re-run is not mistaken for a volume")
    func lastMarkerWins() {
        let parsed = BookTitleParser.parse(fileName: "배트맨 v2 03권.cbz", kind: .comic)
        #expect(parsed.volume == 3)
    }

    /// The failure this guards against: `Blade Runner 2049.pdf` filed as volume 2049
    /// of a book called `Blade Runner`.
    @Test("A number in a book's title is not a volume number")
    func documentsKeepTheirNumbers() {
        let parsed = BookTitleParser.parse(fileName: "Blade Runner 2049.pdf", kind: .document)
        #expect(parsed.title == "Blade Runner 2049")
        #expect(parsed.volume == nil)
    }

    @Test("A comic trusts a bare trailing number")
    func comicsTrustBareNumbers() {
        let parsed = BookTitleParser.parse(fileName: "나루토 12.cbz", kind: .comic)
        #expect(parsed.title == "나루토")
        #expect(parsed.volume == 12)
    }

    /// One archive routinely holds a whole run and is named for it. Left as it is,
    /// `원피스 1~24권` reads as volume 24 of a book called `원피스 1~`, and every
    /// volume inside the archive inherits that name.
    @Test("A range of volumes is the run's name, not a volume number")
    func stripsRanges() {
        #expect(BookTitleParser.parse(fileName: "원피스 1~24권 완결.zip", kind: .comic).title == "원피스")
        #expect(BookTitleParser.parse(fileName: "원피스 1~24권 완결.zip", kind: .comic).volume == nil)
        #expect(BookTitleParser.parse(fileName: "나루토 01-21화.zip", kind: .comic).title == "나루토")
    }

    @Test("A book with no number keeps its whole name")
    func standalone() {
        let parsed = BookTitleParser.parse(fileName: "이기적 유전자.pdf", kind: .document)
        #expect(parsed.title == "이기적 유전자")
        #expect(parsed.volume == nil)
    }
}

@Suite("Volumes become one row on the shelf")
struct BookLibraryIndexTests {
    private func book(_ name: String, kind: BookItem.Kind = .comic) -> BookItem {
        let parsed = BookTitleParser.parse(fileName: name, kind: kind)
        return BookItem(
            id: name,
            kind: kind,
            fileName: name,
            url: URL(fileURLWithPath: "/books/\(name)"),
            title: parsed.title,
            volume: parsed.volume
        )
    }

    @Test("A run of volumes is one collection")
    func collects() {
        let library = BookLibraryIndex.build(from: [
            book("원피스 01권.cbz"), book("원피스 02권.cbz"), book("원피스 03권.cbz")
        ])
        #expect(library.collections.count == 1)
        #expect(library.collections[0].title == "원피스")
        #expect(library.collections[0].volumes.map(\.volume) == [1, 2, 3])
        #expect(library.books.isEmpty)
    }

    /// One volume on its own is not a collection: it would add a screen to tap
    /// through that holds exactly one thing.
    @Test("A lone volume stays on the shelf as itself")
    func singleVolumeStandsAlone() {
        let library = BookLibraryIndex.build(from: [book("원피스 01권.cbz"), book("이기적 유전자.pdf", kind: .document)])
        #expect(library.collections.isEmpty)
        #expect(library.books.count == 2)
        #expect(library.books.contains { $0.displayTitle == "원피스 1권" })
    }
}
