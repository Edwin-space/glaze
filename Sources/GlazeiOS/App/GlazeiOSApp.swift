import SwiftUI

@main
struct GlazeiOSApp: App {
    /// Only so the player can turn the screen sideways on request; see
    /// `IOSScreenOrientation`.
    @UIApplicationDelegateAdaptor(IOSAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .preferredColorScheme(.dark)
        }
    }
}
