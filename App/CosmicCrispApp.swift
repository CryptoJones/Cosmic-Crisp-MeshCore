import SwiftUI

@main
struct CosmicCrispApp: App {
    @State private var node = NodeSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(node)
                .task { await node.connect() }
        }
    }
}
