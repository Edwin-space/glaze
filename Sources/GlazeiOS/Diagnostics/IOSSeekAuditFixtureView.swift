#if DEBUG
import Foundation
import GlazeCore
import SwiftUI

/// Explicit opt-in UI-test fixture, absent from Release. Reads only this named
/// Documents subfolder; it does not accept remote control or open incoming URLs.
struct IOSSeekAuditFixture: Decodable {
    let videoURL: URL
    let subtitleURL: URL

    @MainActor static func requested() -> Self? {
        guard ProcessInfo.processInfo.arguments.contains("-glaze.seekAudit.fixture") else { return nil }
        let folder = IOSLibraryModel.deviceLibraryURL.appendingPathComponent("GlazeSeekAudit", isDirectory: true)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("fixture.json")),
              let decoded = try? JSONDecoder().decode(Self.self, from: data),
              ["http", "https"].contains(decoded.videoURL.scheme),
              ["http", "https"].contains(decoded.subtitleURL.scheme) else { return nil }
        switch ProcessInfo.processInfo.environment["GLAZE_SEEK_AUDIT_CASE"] {
        case "local-srt":
            return Self(videoURL: decoded.videoURL, subtitleURL: folder.appendingPathComponent("probe.ko.srt"))
        case "local-all":
            return Self(videoURL: folder.appendingPathComponent("probe.mp4"), subtitleURL: folder.appendingPathComponent("probe.ko.srt"))
        default:
            return decoded
        }
    }
}

struct IOSSeekAuditFixtureView: View {
    let fixture: IOSSeekAuditFixture
    @State private var preferences = IOSUserPreferences()

    var body: some View {
        let subtitle = NetworkSubtitleResource(url: fixture.subtitleURL, displayName: "probe.ko.srt", languageCode: "ko")
        IOSPlayerView(resource: NetworkMediaResource(serverID: "controlled-audit", objectID: "probe",
            playbackURL: fixture.videoURL, subtitleResources: [subtitle]),
            title: "Glaze Seek Audit", startAt: 0.001, subtitleURL: subtitle.url)
            .environment(preferences)
    }
}
#endif
