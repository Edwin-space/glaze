import Foundation

/// ffprobe reports demuxer aliases, not a single authoritative container name.
public enum MediaContainerName {
    public static func displayName(formatNames: String?, pathExtension: String) -> String {
        let names = (formatNames ?? "").lowercased().split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let suffix = pathExtension.lowercased()
        if names.contains("matroska") && names.contains("webm") {
            // A suffix can disambiguate a known family, never override another family.
            switch suffix {
            case "mkv", "mka", "mks": return "Matroska"
            case "webm", "weba": return "WebM"
            default: return "Matroska / WebM"
            }
        }
        let name = names.first ?? suffix
        return name.isEmpty ? "–" : name.uppercased()
    }
}
