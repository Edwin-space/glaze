import Foundation
import Testing
@testable import GlazeBooks
@testable import GlazeCore

/// 7-Zip is what a lot of comic downloads actually come in. Unlike a zip it is solid-
/// compressed, so these tests are about the path that unpacks it once rather than
/// reading pages where they lie.
@Suite("A 7z holding a comic")
struct SevenZipArchiveTests {
    /// Built by the same tool people use, not hand-assembled: the point is that a
    /// real 7z opens, and a hand-made one would only prove our own assumptions.
    private func makeArchive() throws -> URL? {
        guard let python = ["/usr/bin/python3", "/usr/local/bin/python3"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-7z-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let archive = directory.appendingPathComponent("테스트 1~3권.7z")

        let script = """
        import struct, zlib, io, sys
        try:
            import py7zr
        except ImportError:
            sys.exit(3)

        def png(w, h, base):
            def chunk(t, d):
                c = t + d
                return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
            raw = b''
            for y in range(h):
                raw += b'\\x00' + bytes([base, 40, 90]) * w
            return (b'\\x89PNG\\r\\n\\x1a\\n'
                    + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
                    + chunk(b'IDAT', zlib.compress(raw, 6))
                    + chunk(b'IEND', b''))

        # LZMA2 is what 7-Zip itself writes by default, so that is what to test
        # against. py7zr's own default adds a filter this decoder does not read.
        filters = [{'id': py7zr.FILTER_LZMA2, 'preset': 6}]
        with py7zr.SevenZipFile(r'\(archive.path)', 'w', filters=filters) as z:
            for vol in (1, 2, 3):
                for page in range(1, 4):
                    z.writef(io.BytesIO(png(120, 180, 40 + vol * 40)), '%02d권/%03d.png' % (vol, page))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        // py7zr is not installed; nothing to test against.
        guard process.terminationStatus == 0 else { return nil }
        return archive
    }

    @Test("Its contents are listed without unpacking it")
    func listsWithoutUnpacking() throws {
        guard let archive = try makeArchive() else { return }
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

        #expect(SevenZipArchive.holdsPages(at: archive))
        #expect(SevenZipArchive.volumes(at: archive) == ["01권", "02권", "03권"])
    }

    @Test("Unpacking gives a folder that reads as a comic")
    func unpacksAndReads() throws {
        guard let archive = try makeArchive() else { return }
        let parent = archive.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: parent) }

        let unpacked = parent.appendingPathComponent("unpacked", isDirectory: true)
        var seen: (Int, Int) = (0, 0)
        try SevenZipArchive.extract(at: archive, to: unpacked) { seen = ($0, $1) }

        #expect(seen == (9, 9))
        #expect(ComicFolder.volumes(in: unpacked) == ["01권", "02권", "03권"])

        // One volume, read as a comic, with its pages measurable without decoding.
        let volume = try ComicFolder(root: unpacked.appendingPathComponent("02권"))
        #expect(volume.pageCount == 3)
        #expect(volume.pageSize(at: 0) == CGSize(width: 120, height: 180))
        #expect(try !volume.imageData(at: 0).isEmpty)
    }

    @Test("A 7z with nothing readable in it is not a comic")
    func rejectsNonComics() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-7z-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let notAnArchive = directory.appendingPathComponent("broken.7z")
        try Data(repeating: 0, count: 4_096).write(to: notAnArchive)
        #expect(!SevenZipArchive.holdsPages(at: notAnArchive))
    }
}
