import UIKit

/// Owns the app's one window. Apps built with the iOS 27 SDK must use the UIScene life cycle:
/// without a scene manifest the app exits at launch on iOS 27 (measured 2026-10-20 on Derell's
/// iPhone, iOS 27.0.1: launched, then "terminated with exit code 0", no crash report).
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = ViewController.fieldGreen
        window.rootViewController = ViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}
