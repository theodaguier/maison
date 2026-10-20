import CloudKit
import UIKit

/// Installs `SceneDelegate`, the only way a SwiftUI app hears about accepted iCloud shares.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// The app was launched by opening an invitation.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            InvitationInbox.receive(metadata)
        }
    }

    /// An invitation was opened while the app was running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        InvitationInbox.receive(metadata)
    }
}

/// Holds invitations until the app's state is ready to accept them.
@MainActor
enum InvitationInbox {
    private static var pending: [CKShare.Metadata] = []
    private static var handler: ((CKShare.Metadata) -> Void)?

    static func receive(_ metadata: CKShare.Metadata) {
        if let handler {
            handler(metadata)
        } else {
            pending.append(metadata)
        }
    }

    static func deliver(to handler: @escaping (CKShare.Metadata) -> Void) {
        self.handler = handler
        pending.forEach(handler)
        pending.removeAll()
    }
}
