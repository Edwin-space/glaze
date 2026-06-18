import Foundation

enum SubtitleSidecarDetector {
    private static let supportedExtensions = ["srt", "vtt", "smi"]
    private static let languageSuffixes = ["ko", "kor", "kr", "en", "eng", "original"]

    static func detect(for videoURL: URL) -> [SubtitleFile] {
        let directory = videoURL.deletingLastPathComponent()
        let baseName = videoURL.deletingPathExtension().lastPathComponent
        var candidates: [URL] = []

        for subtitleExtension in supportedExtensions {
            candidates.append(directory.appendingPathComponent(baseName).appendingPathExtension(subtitleExtension))

            for suffix in languageSuffixes {
                candidates.append(directory.appendingPathComponent("\(baseName).\(suffix)").appendingPathExtension(subtitleExtension))
            }
        }

        return candidates
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { SubtitleFile(url: $0, kind: kind(for: $0)) }
            .uniquedByPath()
    }

    private static func kind(for url: URL) -> SubtitleFile.Kind {
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

private extension Array where Element == SubtitleFile {
    func uniquedByPath() -> [SubtitleFile] {
        var seen = Set<String>()

        return filter { file in
            let path = file.url.path
            guard !seen.contains(path) else {
                return false
            }

            seen.insert(path)
            return true
        }
    }
}
