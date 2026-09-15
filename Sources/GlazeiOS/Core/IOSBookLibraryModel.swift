import Foundation
import GlazeBooks
import GlazeCore
import Observation

/// The books and comics on the device.
///
/// Deliberately not tied to whichever media source is selected. A film can come from
/// a NAS, but a book is read on a train — it has to be on the phone. Keeping the
/// bookshelf on the device folder means switching from the NAS to local films does
/// not empty it, which is what a shared model would have done.
@Observable
@MainActor
final class IOSBookLibraryModel {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
    }

    private(set) var library = BookLibrary()
    private(set) var phase: Phase = .idle

    private var task: Task<Void, Never>?

    var isLoading: Bool { phase == .loading }

    /// Every library on the device is one source as far as favourites go — a book
    /// pinned on the phone is pinned on the phone.
    static let sourceKey = "device.books"

    func reload() {
        task?.cancel()
        phase = .loading

        let root = IOSLibraryModel.deviceLibraryURL
        task = Task { [weak self] in
            let found = await LocalBookLoader().load(root: root)
            guard let self, !Task.isCancelled else { return }
            library = found
            phase = .ready
        }
    }

    func book(withID id: String) -> BookItem? {
        library.allBooks.first { $0.id == id }
    }

    func collection(withID id: String) -> BookCollection? {
        library.collections.first { $0.id == id }
    }
}

/// What a tap on the shelf opens.
enum IOSBookSelection: Identifiable, Hashable {
    case collection(String)

    var id: String {
        switch self {
        case .collection(let id): "collection:\(id)"
        }
    }
}
