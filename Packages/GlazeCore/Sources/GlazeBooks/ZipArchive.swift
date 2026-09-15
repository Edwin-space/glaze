import Compression
import Foundation
import GlazeCore

/// Reading a zip file's table of contents, and one member at a time.
///
/// Written by hand rather than pulled in as a dependency, because the whole of what
/// this app needs from zip is small — a list of what is inside, and raw deflate for
/// one member. Two very different things ask for it: a `.cbz` comic, which is images
/// in reading order, and an `.epub` book, which is XHTML with a manifest.
public struct ZipArchive: Sendable {
    public struct Entry: Equatable, Sendable {
        /// The full path inside the archive, e.g. `OEBPS/chapter1.xhtml`.
        public let name: String
        fileprivate let headerOffset: UInt64
        fileprivate let compressedSize: Int
        fileprivate let uncompressedSize: Int
        fileprivate let method: UInt16
    }

    public enum Failure: Error, Equatable {
        case unreadable
        case notAZip
        case missing(String)
        case damaged(String)
    }

    public let url: URL
    public let entries: [Entry]

    private let indexByName: [String: Int]

    // MARK: - Opening

    /// Reads the archive's table of contents. Does not read any member.
    public static func open(_ url: URL) throws -> ZipArchive {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.unreadable }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        guard fileSize > UInt64(endOfDirectoryLength) else { throw Failure.notAZip }

        let directory = try readCentralDirectory(handle: handle, fileSize: fileSize)
        let entries = parse(centralDirectory: directory)
        guard !entries.isEmpty else { throw Failure.notAZip }
        return ZipArchive(url: url, entries: entries)
    }

    private init(url: URL, entries: [Entry]) {
        self.url = url
        self.entries = entries
        var index: [String: Int] = [:]
        for (position, entry) in entries.enumerated() where index[entry.name] == nil {
            index[entry.name] = position
        }
        indexByName = index
    }

    public func index(of name: String) -> Int? { indexByName[name] }

    public func contains(_ name: String) -> Bool { indexByName[name] != nil }

    // MARK: - Reading from the front

    /// One member read by walking local headers from the beginning of a zip, without
    /// its central directory.
    ///
    /// A zip's index lives at the end, so reading a member normally means having the
    /// whole file. That is the wrong bargain for a cover: drawing the shelf would mean
    /// inflating every volume of every run, hundreds of megabytes, to show one picture
    /// each. The first members' *local* headers sit at the very front, and the front
    /// is all a cover needs.
    ///
    /// - Parameter prefix: the beginning of a zip file. Members that run past its end
    ///   are not returned rather than returned truncated.
    public static func firstMember(inPrefix prefix: Data, where matches: (String) -> Bool) -> Data? {
        var cursor = 0
        while cursor + localHeaderLength <= prefix.count {
            guard prefix.u32(at: cursor) == localHeaderSignature else { return nil }

            let flags = prefix.u16(at: cursor + 6)
            // Bit 3 puts the sizes *after* the data, so there is no way to know where
            // this member ends — and so no way to step to the next one.
            guard flags & 0x08 == 0 else { return nil }

            let method = prefix.u16(at: cursor + 8)
            let compressed = Int(prefix.u32(at: cursor + 18))
            let uncompressed = Int(prefix.u32(at: cursor + 22))
            let nameLength = Int(prefix.u16(at: cursor + 26))
            let extraLength = Int(prefix.u16(at: cursor + 28))

            let nameStart = cursor + localHeaderLength
            guard nameStart + nameLength <= prefix.count else { return nil }
            let name = String(
                decoding: prefix[prefix.startIndex + nameStart ..< prefix.startIndex + nameStart + nameLength],
                as: UTF8.self
            )

            let dataStart = nameStart + nameLength + extraLength
            let dataEnd = dataStart + compressed
            if matches(name) {
                guard dataEnd <= prefix.count, uncompressed > 0 else { return nil }
                let stored = Data(prefix[prefix.startIndex + dataStart ..< prefix.startIndex + dataEnd])
                switch method {
                case 0: return stored
                case 8: return try? inflate(stored, to: uncompressed, name: name)
                default: return nil
                }
            }
            cursor = dataEnd
        }
        return nil
    }

    // MARK: - Reading a member

    public func data(named name: String) throws -> Data {
        guard let index = indexByName[name] else { throw Failure.missing(name) }
        return try data(at: index, byteLimit: nil)
    }

    public func data(at index: Int) throws -> Data {
        try data(at: index, byteLimit: nil)
    }

    /// - Parameter byteLimit: stop after this many decompressed bytes. Used to read
    ///   only an image's header — laying out a vertical strip needs every page's
    ///   shape, and inflating four hundred whole pages to learn it would take longer
    ///   than reading the volume.
    public func data(at index: Int, byteLimit: Int?) throws -> Data {
        guard entries.indices.contains(index) else { throw Failure.missing("#\(index)") }
        let entry = entries[index]

        guard let handle = try? FileHandle(forReadingFrom: url) else { throw Failure.unreadable }
        defer { try? handle.close() }

        // The local header repeats the name and may carry a different extra field to
        // the central directory's, so where the bytes start has to be read here
        // rather than assumed.
        try handle.seek(toOffset: entry.headerOffset)
        guard let header = try handle.read(upToCount: localHeaderLength), header.count == localHeaderLength,
              header.u32(at: 0) == localHeaderSignature
        else { throw Failure.damaged(entry.name) }

        let start = entry.headerOffset
            + UInt64(localHeaderLength)
            + UInt64(header.u16(at: 26))
            + UInt64(header.u16(at: 28))
        try handle.seek(toOffset: start)

        // A bounded read wants only the front of the member. Deflate has to be fed
        // from the beginning either way, so this is a prefix rather than a seek.
        // Deflate on already-compressed content — a zip inside a zip, a JPEG — barely
        // shrinks, so the source has to be at least as long as the output wanted.
        let wanted = byteLimit.map {
            min(entry.compressedSize, max(Self.sourcePrefix, $0 + 64 * 1_024))
        } ?? entry.compressedSize
        guard let stored = try handle.read(upToCount: wanted), stored.count == wanted
        else { throw Failure.damaged(entry.name) }

        switch entry.method {
        case 0:
            guard let byteLimit else { return stored }
            return Data(stored.prefix(byteLimit))
        case 8:
            guard let byteLimit else {
                return try Self.inflate(stored, to: entry.uncompressedSize, name: entry.name)
            }
            guard let partial = Self.inflate(stored, upTo: min(byteLimit, entry.uncompressedSize)) else {
                throw Failure.damaged(entry.name)
            }
            return partial
        default:
            throw Failure.damaged(entry.name)
        }
    }

    /// Zip stores raw deflate, which is what Apple's `COMPRESSION_ZLIB` decodes
    /// despite the name — the zlib wrapper is not present in a zip member.
    private static func inflate(_ data: Data, to size: Int, name: String) throws -> Data {
        guard size > 0 else { throw Failure.damaged(name) }

        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination -> Int in
            guard let destinationBase = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let sourceBase = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBase, size,
                    sourceBase, source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure.damaged(name) }
        return output
    }

    /// Inflates only as far as asked. The buffer form cannot do this — it needs the
    /// whole output size up front — so this is the streaming one.
    private static func inflate(_ data: Data, upTo limit: Int) -> Data? {
        guard limit > 0 else { return Data() }

        // Allocated rather than declared: `compression_stream_init` fills the struct
        // in, and a `var` of it would have to be read before it is initialised.
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK
        else { return nil }
        defer { compression_stream_destroy(stream) }

        let bufferSize = 64 * 1_024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var output = Data()
        return data.withUnsafeBytes { source -> Data? in
            guard let base = source.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.pointee.src_ptr = base
            stream.pointee.src_size = source.count

            while output.count < limit {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = bufferSize
                // Not FINALIZE: the source is a prefix of the member, and telling the
                // decoder this is the end of it would make a truncated stream an error.
                let status = compression_stream_process(stream, 0)
                output.append(buffer, count: bufferSize - stream.pointee.dst_size)

                switch status {
                case COMPRESSION_STATUS_END:
                    return output
                case COMPRESSION_STATUS_OK:
                    // Ran out of input before the limit: a prefix is all there is.
                    if stream.pointee.src_size == 0, bufferSize == stream.pointee.dst_size { return output }
                default:
                    return output.isEmpty ? nil : output
                }
            }
            return output
        }
    }

    // MARK: - The central directory

    private static func readCentralDirectory(handle: FileHandle, fileSize: UInt64) throws -> Data {
        // The end record sits at the very end unless there is an archive comment,
        // which can be 64KB long; that is the whole reason for scanning a tail.
        let tailLength = Int(min(fileSize, UInt64(maximumCommentLength + endOfDirectoryLength)))
        try handle.seek(toOffset: fileSize - UInt64(tailLength))
        guard let tail = try handle.read(upToCount: tailLength) else { throw Failure.notAZip }
        guard let endIndex = tail.lastIndex(ofSignature: endOfDirectorySignature) else { throw Failure.notAZip }

        var size = UInt64(tail.u32(at: endIndex + 12))
        var offset = UInt64(tail.u32(at: endIndex + 16))

        // An archive large enough to need zip64 is unusual but a scanned art book can
        // manage it, and the fields it overflows are exactly the two used here.
        if offset == UInt32.max || size == UInt32.max,
           let locator = tail.lastIndex(ofSignature: zip64LocatorSignature) {
            let recordOffset = tail.u64(at: locator + 8)
            try handle.seek(toOffset: recordOffset)
            if let record = try handle.read(upToCount: 56), record.count == 56,
               record.u32(at: 0) == zip64EndSignature {
                size = record.u64(at: 40)
                offset = record.u64(at: 48)
            }
        }

        guard size > 0, offset < fileSize else { throw Failure.notAZip }
        try handle.seek(toOffset: offset)
        guard let directory = try handle.read(upToCount: Int(size)) else { throw Failure.notAZip }
        return directory
    }

    private static func parse(centralDirectory directory: Data) -> [Entry] {
        var entries: [Entry] = []
        var cursor = 0

        while cursor + centralEntryLength <= directory.count {
            guard directory.u32(at: cursor) == centralEntrySignature else { break }

            let method = directory.u16(at: cursor + 10)
            var compressed = UInt64(directory.u32(at: cursor + 20))
            var uncompressed = UInt64(directory.u32(at: cursor + 24))
            let nameLength = Int(directory.u16(at: cursor + 28))
            let extraLength = Int(directory.u16(at: cursor + 30))
            let commentLength = Int(directory.u16(at: cursor + 32))
            var headerOffset = UInt64(directory.u32(at: cursor + 42))

            let nameStart = cursor + centralEntryLength
            guard nameStart + nameLength + extraLength + commentLength <= directory.count else { break }
            let name = String(
                decoding: directory[directory.startIndex + nameStart ..< directory.startIndex + nameStart + nameLength],
                as: UTF8.self
            )

            if uncompressed == UInt64(UInt32.max) || compressed == UInt64(UInt32.max)
                || headerOffset == UInt64(UInt32.max) {
                readZip64Extra(
                    directory,
                    start: nameStart + nameLength,
                    length: extraLength,
                    uncompressed: &uncompressed,
                    compressed: &compressed,
                    headerOffset: &headerOffset
                )
            }

            entries.append(
                Entry(
                    name: name,
                    headerOffset: headerOffset,
                    compressedSize: Int(compressed),
                    uncompressedSize: Int(uncompressed),
                    method: method
                )
            )
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    /// The zip64 extra field lists only the values that overflowed, in a fixed order.
    private static func readZip64Extra(
        _ directory: Data,
        start: Int,
        length: Int,
        uncompressed: inout UInt64,
        compressed: inout UInt64,
        headerOffset: inout UInt64
    ) {
        var cursor = start
        let end = start + length
        while cursor + 4 <= end {
            let identifier = directory.u16(at: cursor)
            let size = Int(directory.u16(at: cursor + 2))
            guard cursor + 4 + size <= end else { return }
            guard identifier == 0x0001 else {
                cursor += 4 + size
                continue
            }

            var field = cursor + 4
            if uncompressed == UInt64(UInt32.max), field + 8 <= end {
                uncompressed = directory.u64(at: field)
                field += 8
            }
            if compressed == UInt64(UInt32.max), field + 8 <= end {
                compressed = directory.u64(at: field)
                field += 8
            }
            if headerOffset == UInt64(UInt32.max), field + 8 <= end {
                headerOffset = directory.u64(at: field)
            }
            return
        }
    }

    // MARK: - Constants

    private static let endOfDirectorySignature: UInt32 = 0x0605_4b50
    private static let zip64LocatorSignature: UInt32 = 0x0706_4b50
    private static let zip64EndSignature: UInt32 = 0x0606_4b50
    private static let centralEntrySignature: UInt32 = 0x0201_4b50
    private static let endOfDirectoryLength = 22
    private static let centralEntryLength = 46
    private static let maximumCommentLength = 65_535
    /// How much compressed data a bounded read pulls off disk.
    private static let sourcePrefix = 512 * 1_024
}

private let localHeaderSignature: UInt32 = 0x0403_4b50
private let localHeaderLength = 30

// MARK: - Little-endian reads

/// Zip is little-endian throughout, and every field here is read out of a `Data`
/// slice whose indices do not start at zero — hence the offset from `startIndex`
/// rather than plain subscripting, which is the mistake this hides.
private extension Data {
    func byte(at offset: Int) -> UInt8 {
        let index = startIndex + offset
        return indices.contains(index) ? self[index] : 0
    }

    func u16(at offset: Int) -> UInt16 {
        UInt16(byte(at: offset)) | UInt16(byte(at: offset + 1)) << 8
    }

    func u32(at offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(byte(at: offset + $1)) << (8 * UInt32($1)) }
    }

    func u64(at offset: Int) -> UInt64 {
        (0..<8).reduce(UInt64(0)) { $0 | UInt64(byte(at: offset + $1)) << (8 * UInt64($1)) }
    }

    func lastIndex(ofSignature signature: UInt32) -> Int? {
        guard count >= 4 else { return nil }
        for offset in stride(from: count - 4, through: 0, by: -1) where u32(at: offset) == signature {
            return offset
        }
        return nil
    }
}
