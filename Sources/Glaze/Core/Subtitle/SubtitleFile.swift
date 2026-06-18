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

    static func manual(url: URL) -> SubtitleFile {
        SubtitleFile(url: url, kind: kind(for: url))
    }

    private static func kind(for url: URL) -> Kind {
        let lowercasedName = url.deletingPathExtension().lastPathComponent.lowercased()

        if lowercasedName.hasSuffix(".ko") || lowercasedName.hasSuffix(".kor") || lowercasedName.hasSuffix(".kr") {
            return .korean
        }

        if lowercasedName.hasSuffix(".original") || lowercasedName.hasSuffix(".en") || lowercasedName.hasSuffix(".eng") {
            return .original
        }

        return .unknown
    }
}
