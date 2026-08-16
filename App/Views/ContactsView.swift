import SwiftUI
import MeshCoreKit

struct ContactsView: View {
    @Environment(NodeSession.self) private var node

    var body: some View {
        List(node.contacts) { c in
            NavigationLink(value: ConversationKey.contact(publicKeyHex: c.id)) {
                HStack(spacing: 12) {
                    Image(systemName: icon(c.kind)).font(.title3).frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.name).font(.headline)
                        Text(c.id.prefix(16) + "…").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(c.outPathLength < 0 ? "flood" : "\(c.outPathLength) hop\(c.outPathLength == 1 ? "" : "s")")
                        if c.lastAdvert > 0 {
                            Text(Date(timeIntervalSince1970: Double(c.lastAdvert)), style: .relative) + Text(" ago")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if node.unreadCount(in: .contact(publicKeyHex: c.id)) > 0 {
                        Circle().fill(.blue).frame(width: 8, height: 8)
                    }
                }
                .padding(.vertical, 2)
            }
            .disabled(c.kind != .chat)
        }
        .overlay {
            if node.contacts.isEmpty { ContentUnavailableView("No contacts yet", systemImage: "person.2") }
        }
        .navigationTitle("Contacts")
        .navigationDestination(for: ConversationKey.self) { ConversationView(key: $0) }
        .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await node.refreshContacts() } } }
    }

    private func icon(_ k: Contact.Kind) -> String {
        switch k {
        case .chat: "person"
        case .repeater: "antenna.radiowaves.left.and.right"
        case .room: "person.3"
        case .sensor: "sensor"
        case .none: "questionmark"
        }
    }
}
