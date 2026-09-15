import Foundation
import Testing
@testable import GlazeBooks
@testable import GlazeCore

@Suite("One archive can hold a whole run")
struct ComicArchiveVolumesTests {
    private func page(_ shade: UInt8) -> Data { Data(repeating: shade, count: 256) }

    /// A download is routinely one archive named `1~24권` with a folder per volume.
    /// Read flat it is one book of thousands of pages with no breaks between them.
    @Test("Folders inside an archive are volumes")
    func findsVolumes() throws {
        let url = try ZipFixture.write([
            ZipFixture.Member("01권/001.png", page(1)),
            ZipFixture.Member("01권/002.png", page(2)),
            ZipFixture.Member("02권/001.png", page(3)),
            ZipFixture.Member("10권/001.png", page(4))
        ], named: "run.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        // Numbered the way a person reads them, not the way strings sort.
        #expect(ComicArchive.volumes(in: url) == ["01권", "02권", "10권"])
    }

    @Test("Opening one volume shows only its pages")
    func opensOneVolume() throws {
        let url = try ZipFixture.write([
            ZipFixture.Member("01권/001.png", page(1)),
            ZipFixture.Member("01권/002.png", page(2)),
            ZipFixture.Member("02권/001.png", page(3))
        ], named: "run2.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = try ComicArchive.open(url, section: "01권")
        #expect(first.pageCount == 2)
        #expect(first.section == "01권")

        let second = try ComicArchive.open(url, section: "02권")
        #expect(second.pageCount == 1)
    }

    /// One folder is simply how someone zipped a single volume, not a run.
    @Test("A single folder is one book, not a run of one")
    func singleFolderIsOneBook() throws {
        let url = try ZipFixture.write([
            ZipFixture.Member("images/001.png", page(1)),
            ZipFixture.Member("images/002.png", page(2))
        ], named: "single.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(ComicArchive.volumes(in: url).isEmpty)
        #expect(try ComicArchive.open(url).pageCount == 2)
    }

    /// A `.zip` is a container for anything. Its name cannot say whether it is a
    /// comic, so the archive is asked.
    @Test("A zip is only a comic when it holds pages")
    func recognisesComicZips() throws {
        let comic = try ZipFixture.write([ZipFixture.Member("001.png", page(1))], named: "comic.zip")
        let other = try ZipFixture.write([ZipFixture.Member("notes.txt", "hello")], named: "other.zip")
        defer {
            try? FileManager.default.removeItem(at: comic)
            try? FileManager.default.removeItem(at: other)
        }

        #expect(BookFileTypes.needsInspection(comic))
        #expect(ComicArchive.holdsPages(comic))
        #expect(!ComicArchive.holdsPages(other))
    }

    /// The shelf problem: a download whose folders are `제1화`, `제2화` parses no
    /// volume numbers at all. Grouped only by number they would land in the shelf one
    /// by one, and a library of downloads becomes hundreds of covers to scroll past.
    @Test("Everything out of one archive is one run, numbered or not")
    func groupsByArchive() throws {
        let url = try ZipFixture.write([
            ZipFixture.Member("제1화/001.png", page(1)),
            ZipFixture.Member("제2화/001.png", page(2)),
            ZipFixture.Member("제10화/001.png", page(3))
        ], named: "unnumbered.zip")
        defer { try? FileManager.default.removeItem(at: url) }

        let sections = ComicArchive.volumes(in: url)
        #expect(sections.count == 3)

        let items = sections.map { section in
            BookItem(
                id: "run.zip#\(section)",
                kind: .comic,
                fileName: "run.zip",
                url: url,
                archiveSection: section,
                collectionKey: "run.zip",
                title: "테스트만화"
            )
        }
        let library = BookLibraryIndex.build(from: items)

        #expect(library.collections.count == 1)
        #expect(library.books.isEmpty)
        // Ordered the way a person reads them: 1, 2, 10 — not 1, 10, 2.
        #expect(library.collections[0].volumes.map(\.archiveSection) == ["제1화", "제2화", "제10화"])
    }
}

/// The shape almost every Korean manga scan actually arrives in: one `.zip` holding
/// one `.zip` per volume, often with a cover image sitting beside them.
///
/// Sixteen of the seventeen archives on the phone this was written for were built this
/// way and **every one of them was invisible** — the shelf asked "does this hold any
/// images?", the outer listing said no, and the book was dropped without a word.
@Suite(.serialized)
struct NestedComicArchiveTests {
    @Test("A zip of zips is a run of volumes, not an empty archive")
    func findsVolumesInsideInnerArchives() throws {
        let outer = try Fixture.nestedComic(volumes: 3, cover: false)
        defer { Fixture.remove(outer) }

        #expect(ComicArchive.holdsPages(outer))
        let volumes = ComicArchive.volumes(in: outer)
        #expect(volumes.count == 3)

        let comic = try ComicArchive.open(outer, section: try #require(volumes.first))
        #expect(comic.pageCount == 4)
        #expect(try comic.imageData(at: 0).count > 0)
    }

    /// A `[Cover].jpg` next to the volumes used to be taken as the archive's only page,
    /// turning a twenty-volume run into a one-page book.
    @Test("A cover beside the volumes does not become the whole book")
    func aCoverDoesNotHideTheVolumes() throws {
        let outer = try Fixture.nestedComic(volumes: 4, cover: true)
        defer { Fixture.remove(outer) }

        #expect(ComicArchive.volumes(in: outer).count == 4)
    }

    /// The shelf draws a cover for every volume of a run. Taking each one by
    /// extracting its whole inner archive wrote hundreds of megabytes to the caches
    /// folder before a single thumbnail appeared, which is what made opening a large
    /// comic a wait.
    @Test("A cover is taken without unpacking the volume")
    func coversDoNotUnpackTheVolume() throws {
        let outer = try Fixture.nestedComic(volumes: 3, cover: false)
        defer { Fixture.remove(outer) }
        let volumes = ComicArchive.volumes(in: outer)

        let before = Fixture.cacheBytes()
        for volume in volumes {
            #expect(ComicArchive.coverData(of: outer, section: volume) != nil)
        }
        #expect(Fixture.cacheBytes() == before)

        // Reading a volume for real still unpacks it, which is the only way to page
        // through one.
        _ = try ComicArchive.open(outer, section: try #require(volumes.first))
        #expect(Fixture.cacheBytes() > before)
    }

    private enum Fixture {
        static func cacheBytes() -> Int64 {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
                  let walker = FileManager.default.enumerator(
                      at: caches.appendingPathComponent("glaze-archives"),
                      includingPropertiesForKeys: [.fileSizeKey]
                  )
            else { return 0 }
            var total: Int64 = 0
            for case let url as URL in walker {
                total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            return total
        }

        /// Builds `outer.zip` containing `NN.zip` volumes of four pages each.
        static func nestedComic(volumes: Int, cover: Bool) throws -> URL {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("nested-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            if cover {
                try png().write(to: work.appendingPathComponent("[Cover].jpg"))
            }
            for volume in 1...volumes {
                let pages = work.appendingPathComponent("v\(volume)", isDirectory: true)
                try FileManager.default.createDirectory(at: pages, withIntermediateDirectories: true)
                for page in 1...4 {
                    try png().write(to: pages.appendingPathComponent(String(format: "%03d.png", page)))
                }
                zip(directory: pages, to: work.appendingPathComponent(String(format: "%02d.zip", volume)))
                try FileManager.default.removeItem(at: pages)
            }

            let outer = work.appendingPathComponent("outer.zip")
            zip(directory: work, to: outer, excluding: "outer.zip")
            return outer
        }

        static func remove(_ outer: URL) {
            try? FileManager.default.removeItem(at: outer.deletingLastPathComponent())
        }

        private static func zip(directory: URL, to destination: URL, excluding: String? = nil) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            var arguments = ["-q", "-r", "-0", destination.path, "."]
            if let excluding { arguments += ["-x", "./\(excluding)"] }
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }

        /// A tiny valid PNG, so the page reader has something real to open.
        private static func png() -> Data {
            var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
            func chunk(_ type: [UInt8], _ payload: [UInt8]) {
                var length = UInt32(payload.count).bigEndian
                withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
                let body = type + payload
                data.append(contentsOf: body)
                var crc = UInt32(crc32(body)).bigEndian
                withUnsafeBytes(of: &crc) { data.append(contentsOf: $0) }
            }
            chunk(Array("IHDR".utf8), [0, 0, 0, 1, 0, 0, 0, 1, 8, 2, 0, 0, 0])
            chunk(Array("IDAT".utf8), [0x78, 0x9C, 0x62, 0x60, 0x60, 0x60, 0x00, 0x00, 0x00, 0x04, 0x00, 0x01])
            chunk(Array("IEND".utf8), [])
            return data
        }

        private static func crc32(_ bytes: [UInt8]) -> UInt32 {
            var table: [UInt32] = (0..<256).map { index in
                var value = UInt32(index)
                for _ in 0..<8 { value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
                return value
            }
            var crc: UInt32 = 0xFFFF_FFFF
            for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
            return crc ^ 0xFFFF_FFFF
        }
    }
}
