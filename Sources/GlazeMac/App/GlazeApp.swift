import AppKit
import GlazeCore
import SwiftUI

@main
struct GlazeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 620)
                // Opening a video from Finder while Glaze was running made a *second*
                // window and played the file there, behind the one the viewer was
                // already looking at — so nothing appeared to happen. Declaring that
                // this window accepts any external event routes the open to the window
                // that is already up.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        }
        .handlesExternalEvents(matching: ["*"])
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // Not a nicety: libVLC and FFmpeg are LGPL, and the licence requires that
            // whoever has a copy of this app can read the notice and find the source.
            CommandGroup(after: .appInfo) {
                Button(L10n.string("legal.title")) {
                    openWindow(id: Self.licensesWindowID)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("command.open_video")) {
                    NotificationCenter.default.post(name: .openVideoCommand, object: nil)
                }
                .keyboardShortcut("o")
            }
        }

        // Reachable with ⌘, whether or not a video is open — the subtitle inspector
        // needs one, so it could not be the only home for these.
        Settings {
            GlazeSettingsView()
        }

        Window(L10n.string("legal.title"), id: Self.licensesWindowID) {
            MacLicensesView()
        }
        .defaultSize(width: 820, height: 560)
    }

    static let licensesWindowID = "licenses"
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        for argument in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: argument)
            if FileManager.default.fileExists(atPath: url.path) {
                enqueueOpenMedia(url)
                break
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        enqueueOpenMedia(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let filename = filenames.first else {
            sender.reply(toOpenOrPrint: .failure)
            return
        }

        enqueueOpenMedia(URL(fileURLWithPath: filename))
        sender.reply(toOpenOrPrint: .success)
    }

    private func enqueueOpenMedia(_ url: URL) {
        Task { @MainActor in
            PendingOpenMediaURLs.append(url)
        }
    }
}
