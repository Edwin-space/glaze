import SwiftUI
import GlazeCore

@main
struct GlazeiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase
    init() {
        DiagnosticsCenter.shared.start()
        IOSDiagnosticReports.shared.start()
    }
    /// Only so the player can turn the screen sideways on request; see
    /// `IOSScreenOrientation`.
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in DiagnosticsCenter.shared.setActive(phase == .active) }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
                    DiagnosticsCenter.shared.record("app.memory_warning")
                }
        }
    }
}
