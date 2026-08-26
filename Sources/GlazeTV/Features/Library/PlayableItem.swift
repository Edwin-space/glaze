import Foundation
import GlazeCore

/// A film the viewer can start, with its name already made readable.
///
/// The title is carried alongside the resource because DLNA playback URLs are opaque
/// ids — `80.mkv` — and the parsed form is carried because every screen shows it and
/// none of them should be re-parsing a release name to draw a row.
struct PlayableItem: Identifiable, Equatable {
    let resource: NetworkMediaResource
    /// What the server called it, kept for the detail screen.
    let title: String
    let parsed: ParsedMediaTitle

    var id: String { "\(resource.serverID)#\(resource.objectID)" }

    init(resource: NetworkMediaResource, title: String) {
        self.resource = resource
        self.title = title
        self.parsed = MediaTitleParser.parse(title)
    }
}
