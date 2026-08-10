import Foundation

public struct SubtitleFile: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        case original
        case korean
        case unknown
    }

    public let id = UUID()
    public let url: URL
    public let kind: Kind

    public var displayName: String {
        url.lastPathComponent
    }

    public static func manual(url: URL) -> SubtitleFile {
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
