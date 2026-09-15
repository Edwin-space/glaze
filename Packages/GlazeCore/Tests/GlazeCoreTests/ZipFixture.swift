import Compression
import Foundation

/// Writes a real zip file for tests.
///
/// Deliberately not shelling out to `zip`: the point of the tests that use this is to
/// prove the reader handles the bytes the format specifies, including deflated
/// members, so the fixture has to produce them.
enum ZipFixture {
    struct Member {
        let name: String
        let data: Data
        var compressed = true

        init(_ name: String, _ text: String, compressed: Bool = true) {
            self.name = name
            self.data = Data(text.utf8)
            self.compressed = compressed
        }

        init(_ name: String, _ data: Data, compressed: Bool = true) {
            self.name = name
            self.data = data
            self.compressed = compressed
        }
    }

    static func write(_ members: [Member], named: String) throws -> URL {
        var file = Data()
        var directory = Data()

        for member in members {
            let name = Data(member.name.utf8)
            let stored = member.compressed ? deflate(member.data) : member.data
            let method: UInt16 = member.compressed ? 8 : 0
            let offset = UInt32(file.count)

            file.append(u32(0x0403_4b50))
            file.append(u16(20)); file.append(u16(0)); file.append(u16(method))
            file.append(u16(0)); file.append(u16(0))
            file.append(u32(0))
            file.append(u32(UInt32(stored.count)))
            file.append(u32(UInt32(member.data.count)))
            file.append(u16(UInt16(name.count))); file.append(u16(0))
            file.append(name)
            file.append(stored)

            directory.append(u32(0x0201_4b50))
            directory.append(u16(20)); directory.append(u16(20)); directory.append(u16(0))
            directory.append(u16(method))
            directory.append(u16(0)); directory.append(u16(0))
            directory.append(u32(0))
            directory.append(u32(UInt32(stored.count)))
            directory.append(u32(UInt32(member.data.count)))
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
        file.append(u16(UInt16(members.count))); file.append(u16(UInt16(members.count)))
        file.append(u32(UInt32(directory.count)))
        file.append(u32(directoryOffset))
        file.append(u16(0))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("glaze-\(UUID().uuidString)-\(named)")
        try file.write(to: url)
        return url
    }

    private static func deflate(_ data: Data) -> Data {
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

    private static func u16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private static func u32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
}
