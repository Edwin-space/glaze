import GlazeCore
import SwiftUI

/// How a folder's contents are laid out.
///
/// The three the Files app offers, because they are the three people already know and
/// each answers a different question: *what is in here* (icons), *which one is it*
/// (list, where the size and subtitle count fit), and *which film is that* (gallery,
/// where the artwork is big enough to recognise).
enum IOSBrowseLayout: String, CaseIterable, Identifiable {
    case icons
    case list
    case gallery

    var id: String { rawValue }

    var labelKey: String {
        switch self {
        case .icons: "ios.browse.layout.icons"
        case .list: "ios.browse.layout.list"
        case .gallery: "ios.browse.layout.gallery"
        }
    }

    var symbol: String {
        switch self {
        case .icons: "square.grid.2x2"
        case .list: "list.bullet"
        case .gallery: "square.grid.3x2.fill"
        }
    }

    /// How wide one tile wants to be. `nil` for the list, which has no tiles.
    var tileWidth: CGFloat? {
        switch self {
        case .icons: 104
        case .list: nil
        case .gallery: 150
        }
    }
}

/// The picker, in the place every file browser puts it.
struct IOSBrowseLayoutMenu: View {
    @Binding var layout: IOSBrowseLayout

    var body: some View {
        Menu {
            Picker(L10n.string("ios.browse.layout"), selection: $layout) {
                ForEach(IOSBrowseLayout.allCases) { option in
                    Label(L10n.string(option.labelKey), systemImage: option.symbol).tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label(L10n.string("ios.browse.layout"), systemImage: layout.symbol)
        }
    }
}
