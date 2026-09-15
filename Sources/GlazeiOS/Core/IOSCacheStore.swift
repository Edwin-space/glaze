import Foundation
import GlazeBooks
import Observation

/// Everything the app unpacks or draws so it does not have to again.
///
/// Three things end up here and all of them can grow without bound: `.7z` comics
/// unpacked page by page, volumes lifted out of a zip-of-zips, and EPUBs opened out
/// into files a web view can load — plus the thumbnails drawn from them. A run of
/// twenty volumes read to the end leaves a copy of that run on the device.
///
/// None of it is anything the viewer put there and none of it is lost by deleting it,
/// so the honest thing is to show what it weighs and let them throw it away.
@MainActor
@Observable
final class IOSCacheStore {
    /// The folder names, in the one place that knows all three.
    enum Kind: String, CaseIterable {
        /// `.7z` unpacked, and volumes lifted out of a zip inside a zip.
        case archives = "glaze-archives"   // NestedZipCache.cacheFolderName
        /// EPUBs opened out for the web view.
        case books = "glaze-books"
        case covers = "glaze-book-covers"
    }

    private(set) var byteCount: Int64 = 0
    private(set) var isMeasuring = false

    func refresh() {
        isMeasuring = true
        Task.detached(priority: .utility) {
            let total = Self.measure()
            await MainActor.run {
                self.byteCount = total
                self.isMeasuring = false
            }
        }
    }

    /// - Note: the reader keeps whatever it has already opened; only what is on disk
    ///   goes. Reopening that book unpacks it again.
    func clear() {
        for kind in Kind.allCases {
            guard let url = Self.directory(kind) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
        byteCount = 0
        refresh()
    }

    nonisolated static func directory(_ kind: Kind) -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(kind.rawValue, isDirectory: true)
    }

    private nonisolated static func measure() -> Int64 {
        var total: Int64 = 0
        for kind in Kind.allCases {
            guard let root = directory(kind),
                  let walker = FileManager.default.enumerator(
                      at: root,
                      includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
                  )
            else { continue }

            for case let url as URL in walker {
                let values = try? url.resourceValues(
                    forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
                )
                total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            }
        }
        return total
    }
}
