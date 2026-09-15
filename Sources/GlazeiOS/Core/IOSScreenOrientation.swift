import SwiftUI
import UIKit

/// Turning the picture sideways because the viewer asked, not because the phone moved.
///
/// Someone watching in bed has rotation lock on — that is what it is for, and they are
/// not going to turn it off for one film and back on afterwards. Without a button, a
/// 21:9 film plays in a strip across the middle of an upright phone and there is
/// nothing they can do about it.
///
/// iOS grants a requested orientation only if the view controller currently says it
/// supports it, so the app has to change its answer *first* and then ask. That answer
/// lives here, and `IOSAppDelegate` is the only thing that reads it.
@MainActor
enum IOSScreenOrientation {
    private(set) static var allowed: UIInterfaceOrientationMask = .all

    static var isLandscape: Bool {
        scene?.interfaceOrientation.isLandscape ?? false
    }

    /// Turns the screen and keeps it there until released.
    static func hold(_ mask: UIInterfaceOrientationMask) {
        allowed = mask
        request(mask)
    }

    /// Hands the screen back to the device — and to the viewer's rotation lock.
    static func release() {
        allowed = .all
        request(.all)
    }

    private static func request(_ mask: UIInterfaceOrientationMask) {
        guard let scene else { return }
        // iOS asks the *topmost presented* controller what it supports, not the root.
        // The player is a full-screen cover — its own controller — so telling only the
        // root leaves the answer stale and the request is judged against it.
        for controller in stack(from: scene.keyWindow?.rootViewController) {
            controller.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
    }

    private static func stack(from root: UIViewController?) -> [UIViewController] {
        var controllers: [UIViewController] = []
        var next = root
        while let controller = next {
            controllers.append(controller)
            next = controller.presentedViewController
        }
        return controllers
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}

/// Exists for one method. iOS asks the delegate which orientations are allowed, and
/// there is no SwiftUI way to answer.
final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { IOSScreenOrientation.allowed }
    }
}
