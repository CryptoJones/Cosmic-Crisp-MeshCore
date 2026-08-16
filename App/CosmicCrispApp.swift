import SwiftUI

@main
struct CosmicCrispApp: App {
    @State private var node = NodeSession()
    @State private var lock = AppLock()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(node)
                    .environment(lock)
                    .task {
                        node.appLock = lock
                        lock.lockOnLaunch()
                        await node.connect()
                    }
                if lock.isLocked || node.profileLocked {
                    LockScreen()
                        .environment(node)
                        .environment(lock)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: lock.isLocked)
            .onChange(of: phase) { _, p in
                switch p {
                case .background: lock.didEnterBackground()
                case .active: lock.willEnterForeground()
                default: break
                }
            }
        }
    }
}
