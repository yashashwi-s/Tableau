import SwiftUI

@main
struct PhotoWidgetOSXApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The menu bar and settings window are managed by AppDelegate
        // We just need one Scene to satisfy the protocol
        Settings {
            EmptyView()
        }
    }
}
