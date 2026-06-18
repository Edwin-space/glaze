import SwiftUI

@main
struct GlazeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("command.open_video")) {
                    NotificationCenter.default.post(name: .openVideoCommand, object: nil)
                }
                .keyboardShortcut("o")
            }
        }
    }
}
