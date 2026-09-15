import Foundation
import Testing
@testable import GlazeBooks
@testable import GlazeCore

@Suite("An epub says what it is and what order to read it in")
struct EPUBPackageTests {
    private let container = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private let opf = """
    <?xml version="1.0" encoding="utf-8"?>
    <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="id">
      <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
        <dc:title>이기적 유전자</dc:title>
        <dc:creator>리처드 도킨스</dc:creator>
        <dc:language>ko</dc:language>
      </metadata>
      <manifest>
        <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
        <item id="cover" href="../images/cover.png" media-type="image/png" properties="cover-image"/>
        <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
        <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
        <item id="ad" href="text/ad.xhtml" media-type="application/xhtml+xml"/>
      </manifest>
      <spine>
        <itemref idref="c1"/>
        <itemref idref="c2"/>
        <itemref idref="ad" linear="no"/>
      </spine>
    </package>
    """

    private let nav = """
    <?xml version="1.0" encoding="utf-8"?>
    <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
      <body>
        <nav epub:type="landmarks"><ol><li><a href="text/ch1.xhtml">본문 시작</a></li></ol></nav>
        <nav epub:type="toc">
          <ol>
            <li><a href="text/ch1.xhtml">1장 이기적 유전자</a>
              <ol><li><a href="text/ch1.xhtml#s2">1.1 복제자</a></li></ol>
            </li>
            <li><a href="text/ch2.xhtml#part2">2장 불멸의 코일</a></li>
          </ol>
        </nav>
      </body>
    </html>
    """

    private func book() throws -> URL {
        try ZipFixture.write(
            [
                ZipFixture.Member("mimetype", "application/epub+zip", compressed: false),
                ZipFixture.Member("META-INF/container.xml", container),
                ZipFixture.Member("OEBPS/content.opf", opf),
                ZipFixture.Member("OEBPS/nav.xhtml", nav),
                ZipFixture.Member("OEBPS/text/ch1.xhtml", "<html><body><p>가</p></body></html>"),
                ZipFixture.Member("OEBPS/text/ch2.xhtml", "<html><body><p>나</p></body></html>"),
                ZipFixture.Member("images/cover.png", "not really a png")
            ],
            named: "book.epub"
        )
    }

    @Test("The book's own title beats the file name")
    func metadata() throws {
        let url = try book()
        defer { try? FileManager.default.removeItem(at: url) }

        let package = try EPUBBook.readPackage(at: url)
        #expect(package.title == "이기적 유전자")
        #expect(package.author == "리처드 도킨스")
        #expect(package.language == "ko")
    }

    /// The failure this guards against: hrefs are relative to the package document
    /// and routinely climb out of their folder. Unresolved, they name nothing in the
    /// zip and every chapter comes up blank.
    @Test("Reading order is resolved to real paths inside the archive")
    func spine() throws {
        let url = try book()
        defer { try? FileManager.default.removeItem(at: url) }

        let package = try EPUBBook.readPackage(at: url)
        #expect(package.spine == ["OEBPS/text/ch1.xhtml", "OEBPS/text/ch2.xhtml"])
        #expect(package.coverPath == "images/cover.png")
    }

    @Test("Pages marked as outside the reading order stay out of it")
    func skipsNonLinear() throws {
        let url = try book()
        defer { try? FileManager.default.removeItem(at: url) }

        let package = try EPUBBook.readPackage(at: url)
        #expect(!package.spine.contains { $0.hasSuffix("ad.xhtml") })
    }

    /// A navigation document also carries a landmarks list and sometimes a page list.
    /// Only the one typed `toc` is the contents.
    @Test("The contents list is read, and only the contents list")
    func chapters() throws {
        let url = try book()
        defer { try? FileManager.default.removeItem(at: url) }

        let package = try EPUBBook.readPackage(at: url)
        #expect(package.chapters.map(\.title) == ["1장 이기적 유전자", "1.1 복제자", "2장 불멸의 코일"])
        #expect(package.chapters.map(\.depth) == [0, 1, 0])
        #expect(package.chapters.last?.fragment == "part2")
        #expect(package.chapters.first?.path == "OEBPS/text/ch1.xhtml")
    }

    @Test("A zip that is not a book is turned away")
    func rejectsNonEPUB() throws {
        let url = try ZipFixture.write([ZipFixture.Member("readme.txt", "hello")], named: "plain.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: EPUBBook.Failure.notAnEPUB) { try EPUBBook.readPackage(at: url) }
    }
}
