import SwiftUI

@main
struct ToolboxApp: App {
    var body: some Scene {
        WindowGroup {
            ToolListView()
                .tint(.accentColor)
        }
    }
}
