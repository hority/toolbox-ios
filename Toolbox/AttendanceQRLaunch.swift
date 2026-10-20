import AppIntents
import SwiftUI
import UIKit
import WidgetKit

/// Scene-local state, received through connection options on cold launch and updated
/// on an existing scene on warm launch. No QR is written to URLs, files or logs.
@MainActor
final class AttendanceQRSceneDelegate: NSObject, UIWindowSceneDelegate, ObservableObject {
    @Published var isShowingQR = false
    @Published var configuration: AttendanceQRConfiguration?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        for activity in connectionOptions.userActivities { receive(activity) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        receive(userActivity)
    }

    func receive(_ activity: NSUserActivity,
                 resolve: (NSUserActivity) -> AttendanceQRWidgetConfigurationIntent? = {
                     $0.widgetConfigurationIntent(of: AttendanceQRWidgetConfigurationIntent.self)
                 }) {
        guard activity.userInfo?[WidgetCenter.UserInfoKey.kind] as? String == "AttendanceQRWidget" else { return }
        let intent = resolve(activity)
        // Legacy operation/duration remain stored but don't change the shared QR.
        configuration = intent.flatMap {
            try? AttendanceQRConfiguration(label: $0.label, payload: $0.payload,
                                           operation: .arrival, durationSeconds: 30)
        }
        isShowingQR = true
    }

    func close() {
        isShowingQR = false
        configuration = nil
    }
}

@MainActor
final class ToolboxAppDelegate: NSObject, UIApplicationDelegate, ObservableObject {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        if connectingSceneSession.role == .windowApplication {
            configuration.delegateClass = AttendanceQRSceneDelegate.self
        }
        return configuration
    }
}

struct ToolboxRootView: View {
    @EnvironmentObject private var scene: AttendanceQRSceneDelegate

    var body: some View {
        Group {
            if scene.isShowingQR {
                AttendanceQRScreen(configuration: scene.configuration, close: scene.close)
            } else {
                ToolListView()
            }
        }
    }
}
