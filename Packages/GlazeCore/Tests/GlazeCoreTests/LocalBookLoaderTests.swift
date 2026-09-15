import Foundation
import Testing
@testable import GlazeBooks
@testable import GlazeCore

@Suite("A folder on the device becomes a bookshelf")
struct LocalBookLoaderTests {
    private func makeTree(_ files: [(path: String, data: Data)]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-books-\(UUID().uuidString)", isDirectory: true)
        for file in files {
            let url = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: url)
        }
        return root
    }

    @Test("Volumes group, standalone books do not, and films are left alone")
    func reads() async throws {
        let root = try makeTree([
            ("Parasite.2019.1080p.mkv", Data("film".utf8)),
            ("만화/원피스 01권.cbz", Data("comic".utf8)),
            ("만화/원피스 02권.cbz", Data("comic".utf8)),
            ("이기적 유전자.pdf", Data("book".utf8))
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let library = await LocalBookLoader().load(root: root)

        #expect(library.collections.first?.title == "원피스")
        #expect(library.books.map(\.title) == ["이기적 유전자"])
        // The film is not a book, and nothing about it should appear here.
        #expect(!library.allBooks.contains { $0.fileName.hasSuffix(".mkv") })
    }

    @Test("A book is named by where it sits, so a reinstall does not lose it")
    func relativeIdentifiers() async throws {
        let root = try makeTree([("만화/원피스 01권.cbz", Data("comic".utf8))])
        defer { try? FileManager.default.removeItem(at: root) }

        let library = await LocalBookLoader().load(root: root)
        #expect(library.allBooks.map(\.id) == ["만화/원피스 01권.cbz"])
    }
}
