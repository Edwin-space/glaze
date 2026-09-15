import Compression
import Foundation
import Testing
@testable import GlazeBooks
@testable import GlazeCore

@Suite("A cbz gives up its pages")
struct ComicArchiveTests {
    @Test("Pages come back in order, whether stored or deflated")
    func readsPages() throws {
        let pages: [(String, Data)] = [
            ("002.png", Data(repeating: 0xAB, count: 4_096)),
            ("010.png", Data("the tenth page".utf8)),
            ("001.png", Data(repeating: 0x11, count: 64))
        ]
        let url = try write(
            entries: pages.map { ($0.0, $0.1, true) } + [("__MACOSX/._001.png", Data("junk".utf8), false)],
            named: "ordered.cbz"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try ComicArchive.open(url)

        // 10 after 2 is what a person means; a plain string sort puts it after 1.
        #expect(archive.pages.map(\.name) == ["001.png", "002.png", "010.png"])
        #expect(try archive.imageData(at: 0) == pages[2].1)
        #expect(try archive.imageData(at: 1) == pages[0].1)
        #expect(try archive.imageData(at: 2) == pages[1].1)
    }

    @Test("An archive holding no images is not a comic")
    func rejectsEmpty() throws {
        let url = try write(entries: [("readme.txt", Data("nothing here".utf8), false)], named: "empty.cbz")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ComicArchive.Failure.noPages) { try ComicArchive.open(url) }
    }

    @Test("A file that is not a zip is turned away rather than half-read")
    func rejectsNonZip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-zip.cbz")
        try Data(repeating: 0x00, count: 5_000).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: ComicArchive.Failure.notAZip) { try ComicArchive.open(url) }
    }

    // MARK: - A zip, written by hand

    /// Deliberately not shelling out to `zip`: the point is to prove this code reads
    /// the bytes the format specifies, including a deflated member.
    private func write(entries: [(name: String, data: Data, compress: Bool)], named: String) throws -> URL {
        var file = Data()
        var directory = Data()

        for entry in entries {
            let name = Data(entry.name.utf8)
            let stored = entry.compress ? deflate(entry.data) : entry.data
            let method: UInt16 = entry.compress ? 8 : 0
            let offset = UInt32(file.count)

            file.append(u32(0x0403_4b50))
            file.append(u16(20)); file.append(u16(0)); file.append(u16(method))
            file.append(u16(0)); file.append(u16(0))
            file.append(u32(0))
            file.append(u32(UInt32(stored.count)))
            file.append(u32(UInt32(entry.data.count)))
            file.append(u16(UInt16(name.count))); file.append(u16(0))
            file.append(name)
            file.append(stored)

            directory.append(u32(0x0201_4b50))
            directory.append(u16(20)); directory.append(u16(20)); directory.append(u16(0))
            directory.append(u16(method))
            directory.append(u16(0)); directory.append(u16(0))
            directory.append(u32(0))
            directory.append(u32(UInt32(stored.count)))
            directory.append(u32(UInt32(entry.data.count)))
            directory.append(u16(UInt16(name.count)))
            directory.append(u16(0)); directory.append(u16(0)); directory.append(u16(0))
            directory.append(u16(0)); directory.append(u32(0))
            directory.append(u32(offset))
            directory.append(name)
        }

        let directoryOffset = UInt32(file.count)
        file.append(directory)
        file.append(u32(0x0605_4b50))
        file.append(u16(0)); file.append(u16(0))
        file.append(u16(UInt16(entries.count))); file.append(u16(UInt16(entries.count)))
        file.append(u32(UInt32(directory.count)))
        file.append(u32(directoryOffset))
        file.append(u16(0))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(named)
        try file.write(to: url)
        return url
    }

    private func deflate(_ data: Data) -> Data {
        let capacity = max(64, data.count + data.count / 2 + 64)
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        return output.prefix(written)
    }

    private func u16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private func u32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }

    /// Laying out a vertical strip needs every page's shape before it can place
    /// anything. Reading it from the image header keeps that from meaning "inflate
    /// the whole volume first".
    @Test("A page's size is read from its header, not by decoding it")
    func measuresPagesWithoutDecodingThem() throws {
        let tall = png(width: 800, height: 4_000)
        let wide = png(width: 1_400, height: 900)
        let url = try write(
            entries: [("001.png", tall, true), ("002.png", wide, false)],
            named: "sizes.cbz"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try ComicArchive.open(url)
        #expect(archive.pageSize(at: 0) == CGSize(width: 800, height: 4_000))
        #expect(archive.pageSize(at: 1) == CGSize(width: 1_400, height: 900))
    }

    /// A solid colour would compress to less than one output buffer and never
    /// exercise the bound, so this page is noise.
    @Test("A bounded read stops early instead of inflating the whole page")
    func readsOnlyThePrefix() throws {
        let page = png(width: 500, height: 1_400, noisy: true)
        let url = try write(entries: [("001.png", page, true)], named: "bounded.cbz")
        defer { try? FileManager.default.removeItem(at: url) }

        let archive = try ComicArchive.open(url)
        let head = try archive.imageData(at: 0, byteLimit: 1_024)

        #expect(page.count > 512 * 1_024)
        // The decoder works a buffer at a time, so the bound is "stop after", not
        // "exactly this many bytes".
        #expect(head.count <= 128 * 1_024)
        #expect(head.prefix(8) == page.prefix(8))
    }

    /// A real PNG, so ImageIO has something it actually recognises to measure.
    private func png(width: Int, height: Int, noisy: Bool = false) -> Data {
        func chunk(_ tag: [UInt8], _ body: Data) -> Data {
            var out = Data()
            out.append(u32(UInt32(body.count)).reversed4())
            out.append(contentsOf: tag)
            out.append(body)
            var crcInput = Data(tag)
            crcInput.append(body)
            out.append(u32(UInt32(crc32(crcInput))).reversed4())
            return out
        }

        var header = Data()
        header.append(u32(UInt32(width)).reversed4())
        header.append(u32(UInt32(height)).reversed4())
        header.append(contentsOf: [8, 0, 0, 0, 0])

        var raw = Data()
        var seed: UInt32 = 0x1234_5678
        for _ in 0..<height {
            raw.append(0)
            if noisy {
                var row = Data(capacity: width)
                for _ in 0..<width {
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    row.append(UInt8(truncatingIfNeeded: seed >> 16))
                }
                raw.append(row)
            } else {
                raw.append(Data(repeating: 0x80, count: width))
            }
        }

        var file = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        file.append(chunk(Array("IHDR".utf8), header))
        file.append(chunk(Array("IDAT".utf8), deflate(raw, zlibWrapped: true)))
        file.append(chunk(Array("IEND".utf8), Data()))
        return file
    }

    private func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for index in 0..<256 {
            var value = UInt32(index)
            for _ in 0..<8 { value = (value & 1) == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
            table[index] = value
        }
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    /// PNG's IDAT carries a zlib stream, which is raw deflate inside a two-byte
    /// header and a checksum; zip members carry the raw deflate on its own.
    private func deflate(_ data: Data, zlibWrapped: Bool) -> Data {
        let body = deflate(data)
        guard zlibWrapped else { return body }
        var out = Data([0x78, 0x01])
        out.append(body)
        var adlerA: UInt32 = 1
        var adlerB: UInt32 = 0
        for byte in data {
            adlerA = (adlerA + UInt32(byte)) % 65_521
            adlerB = (adlerB + adlerA) % 65_521
        }
        out.append(u32((adlerB << 16) | adlerA).reversed4())
        return out
    }
}

private extension Data {
    /// PNG is big-endian; the zip writer above is little-endian. This flips one field.
    func reversed4() -> Data { Data(reversed()) }
}
