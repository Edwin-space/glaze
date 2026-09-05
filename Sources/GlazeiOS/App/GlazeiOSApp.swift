import SwiftUI

@main
struct GlazeiOSApp: App {
    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .preferredColorScheme(.dark)
        }
    }
}
