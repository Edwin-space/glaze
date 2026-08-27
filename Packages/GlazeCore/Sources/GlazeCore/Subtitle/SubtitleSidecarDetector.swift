import Foundation

/// Finds the subtitle files that belong to a video.
///
/// This used to try a fixed list of names — `film.srt`, `film.ko.srt`, `film.en.srt`,
/// `film.original.srt` and a few more. Anything outside the list was invisible, and one
/// of the names outside it was the app's own legacy output: translations used to be
/// saved as `film.original.ko.srt`, which no candidate matched. So the viewer waited
/// for a translation, closed the film, reopened it, and the translation was gone.
///
/// Reading the folder instead of guessing at names covers the app's own output, the
/// current `film.ko.srt` convention, old Glaze output, and whatever a person names a
/// file by hand.
public enum SubtitleSidecarDetector {
    private static let supportedExtensions: Set<String> = ["srt", "vtt", "smi"]

    public static func detect(for videoURL: URL) -> [SubtitleFile] {
        let directory = videoURL.deletingLastPathComponent()
        let baseName = videoURL.deletingPathExtension().lastPathComponent

        let entries = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries
            .filter { belongsToVideo(named: baseName, $0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(SubtitleFile.manual(url:))
    }

    /// `film.srt` and `film.<anything>.srt` belong to `film.mkv`. `film2.en.srt` does
    /// not — matching on the prefix alone would sweep in the neighbouring film.
    private static func belongsToVideo(named baseName: String, _ candidate: URL) -> Bool {
        guard supportedExtensions.contains(candidate.pathExtension.lowercased()) else {
            return false
        }

        let stem = candidate.deletingPathExtension().lastPathComponent
        return stem == baseName || stem.hasPrefix(baseName + ".")
    }
}
