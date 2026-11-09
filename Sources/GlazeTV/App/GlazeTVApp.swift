import SwiftUI
import GlazeCore

@main
struct GlazeTVApp: App {
    @Environment(\.scenePhase) private var scenePhase
    init() { DiagnosticsCenter.shared.start() }
    var body: some Scene {
        WindowGroup {
            TVRootView()
                .onChange(of: scenePhase) { _, phase in DiagnosticsCenter.shared.setActive(phase == .active) }
        }
    }
}
