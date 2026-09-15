import Foundation
import GlazeCore

/// The folder people drop files into, and the note that makes it findable.
///
/// `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` are both set, which
/// is what lets Finder, iMazing and the Files app reach this folder at all. But the
/// Files app hides an app's folder under "On My iPhone" while it is **empty**, so a
/// freshly installed Glaze looks like an app that does not accept files — the exact
/// thing the empty state tells people to do.
///
/// One small note written on first launch fixes that, and doubles as the instructions
/// at the moment someone is looking for where to put things.
@MainActor
enum IOSDeviceFolder {
    private static let guideName = "Glaze — 여기에 넣으세요.txt"

    /// Where things are meant to go. Created once, as an invitation — **not** as a
    /// rule. What a file is, is settled by what it is: `.mkv` is a film wherever it
    /// sits, `.epub` is a book. Sorting by folder instead would write the same fact
    /// twice, and the day the two disagree — a PDF dropped in the film folder, a
    /// trailer inside a comic scan — the file simply vanishes from the app.
    ///
    /// So these make the tidy path obvious and give shared files somewhere sensible
    /// to land, and nothing breaks for anyone who ignores them.
    enum Shelf {
        case films
        case books

        /// The first name that already exists wins, so switching the app's language
        /// does not leave someone with two folders for the same thing.
        var names: [String] {
            switch self {
            case .films: ["영상", "Video"]
            case .books: ["서재", "Books"]
            }
        }

        /// Named apart from the tabs on purpose: renaming a tab must never orphan a
        /// folder that already has someone's files in it.
        var preferredName: String {
            L10n.string(self == .films ? "ios.device.folder.films" : "ios.device.folder.books")
        }
    }

    static func folder(for shelf: Shelf, creating: Bool = false) -> URL? {
        let root = IOSLibraryModel.deviceLibraryURL
        let fileManager = FileManager.default

        for name in shelf.names {
            let candidate = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return candidate
            }
        }
        guard creating else { return nil }

        let made = root.appendingPathComponent(shelf.preferredName, isDirectory: true)
        try? fileManager.createDirectory(at: made, withIntermediateDirectories: true)
        return made
    }

    private static let offeredKey = "ios.device.shelvesOffered"

    static func prepareIfNeeded() {
        let root = IOSLibraryModel.deviceLibraryURL
        let fileManager = FileManager.default
        let defaults = UserDefaults.standard

        // Offered once, ever. Someone who already has films here gets the two
        // destinations too — nothing of theirs is moved, only two empty folders
        // appear — and someone who then deletes them does not find them back
        // next launch.
        if !defaults.bool(forKey: offeredKey) {
            defaults.set(true, forKey: offeredKey)
            _ = folder(for: .films, creating: true)
            _ = folder(for: .books, creating: true)
        }

        // The note explains an empty folder. Dropping it into one that already has
        // someone's films in it would just be litter.
        let existing = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        let content = existing.filter { name in
            !name.hasPrefix(".") && name != guideName && !Shelf.films.names.contains(name)
                && !Shelf.books.names.contains(name)
        }
        guard content.isEmpty else { return }
        try? Data(guide.utf8).write(to: root.appendingPathComponent(guideName), options: .atomic)
    }

    private static var guide: String {
        L10n.string("ios.device.guide")
    }
}
