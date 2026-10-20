import SwiftUI

@main
struct ToolboxApp: App {
    @UIApplicationDelegateAdaptor(ToolboxAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ToolboxRootView()
                .tint(.accentColor)
        }
    }
}
