import SwiftUI

@main
struct WB2APIApp: App {
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .preferredColorScheme(nil)
        }
        .onChange(of: scenePhase) { _, phase in
            // Console admin sessions expire server-side; when the app is
            // backgrounded for a while the web view reloads on return so the
            // user sees a fresh cookie instead of a stale "会话已过期" tab.
            if phase == .active {
                NotificationCenter.default.post(name: .wb2apiReloadRequested, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let wb2apiReloadRequested = Notification.Name("wb2api.reloadRequested")
}
