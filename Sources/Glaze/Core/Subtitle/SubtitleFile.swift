import Foundation

struct SubtitleFile: Identifiable, Equatable {
    enum Kind {
        case original
        case korean
        case unknown
    }

    let id = UUID()
    let url: URL
    let kind: Kind

    var displayName: String {
        url.lastPathComponent
    }
}
