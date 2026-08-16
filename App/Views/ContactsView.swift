import SwiftUI
import MeshCoreKit

struct ContactsView: View {
    @Environment(NodeSession.self) private var node
    @State private var draft: [String: String] = [:]

    var body: some View {
        List(node.contacts) { c in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: icon(c.kind))
                    Text(c.name).font(.headline)
                    Spacer()
                    Text(c.outPathLength < 0 ? "flood" : "\(c.outPathLength) hop\(c.outPathLength == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(c.id.prefix(16) + "…").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                if c.kind == .chat {
                    HStack {
                        TextField("Message", text: Binding(get: { draft[c.id] ?? "" }, set: { draft[c.id] = $0 }))
                            .textFieldStyle(.roundedBorder)
                        Button("Send") {
                            let text = draft[c.id] ?? ""
                            draft[c.id] = ""
                            Task { await node.send(text: text, to: c) }
                        }
                        .disabled((draft[c.id] ?? "").isEmpty)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if node.contacts.isEmpty { ContentUnavailableView("No contacts yet", systemImage: "person.2") }
        }
        .navigationTitle("Contacts")
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
