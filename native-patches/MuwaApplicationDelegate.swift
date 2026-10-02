import CarPlay
import UIKit

@MainActor
final class MuwaApplicationDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication,
                   configurationForConnecting session: UISceneSession,
                   options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    // Keep the configuration selected by SwiftUI for the existing phone scenes.
    guard session.role == .carTemplateApplication else { return session.configuration }
    let configuration = UISceneConfiguration(name: "Muwa CarPlay", sessionRole: session.role)
    configuration.sceneClass = CPTemplateApplicationScene.self
    configuration.delegateClass = CarPlaySceneDelegate.self
    return configuration
  }
}
