import SwiftUI
import MeshCoreKit

struct RootView: View {
    @Environment(NodeSession.self) private var node
    /// Initial section; overridable with launch argument `-section <node|contacts|messages|map>`
    /// (used by screenshot/CI runs).
    @State private var selection: Section? = Section.fromLaunchArguments() ?? .node

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink("Node", value: Section.node)
                NavigationLink("Contacts", value: Section.contacts)
                NavigationLink(value: Section.messages) {
                    HStack {
                        Text("Messages")
                        Spacer()
                        if node.totalUnread > 0 {
                            Text("\(node.totalUnread)").font(.caption.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(.blue))
                        }
                    }
                }
                NavigationLink("Map", value: Section.map)
            }
            .navigationTitle("Cosmic Crisp")
            .safeAreaInset(edge: .bottom) { StatusBar() }
        } detail: {
            NavigationStack {
                switch selection ?? .node {
                case .node: NodeView()
                case .contacts: ContactsView()
                case .messages: MessagesView()
                case .map: MapView()
                }
            }
        }
    }

    enum Section: String, Hashable, CaseIterable {
        case node, contacts, messages, map

        static func fromLaunchArguments() -> Section? {
            let args = ProcessInfo.processInfo.arguments
            guard let i = args.firstIndex(of: "-section"), i + 1 < args.count else { return nil }
            return Section(rawValue: args[i + 1].lowercased())
        }
    }
}

struct StatusBar: View {
    @Environment(NodeSession.self) private var node

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 10, height: 10)
            Text(label).font(.footnote)
            Spacer()
            Text(node.transportDescription).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private var color: Color {
        switch node.status {
        case .connected: .green
        case .connecting: .yellow
        case .disconnected: .gray
        case .failed: .red
        }
    }

    private var label: String {
        switch node.status {
        case .connected: "Connected to \(node.selfInfo?.name ?? "node")"
        case .connecting: "Connecting…"
        case .disconnected: "Disconnected"
        case .failed(let why): "Failed: \(why)"
        }
    }
}
