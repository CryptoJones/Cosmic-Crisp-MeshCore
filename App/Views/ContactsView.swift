import SwiftUI
import MeshCoreKit

struct ContactsView: View {
    @Environment(NodeSession.self) private var node
    @State private var showImport = false
    @State private var showMyCard = false
    @State private var search = ""

    private var filtered: [Contact] {
        let list = node.contacts.sorted { $0.lastAdvert > $1.lastAdvert }
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.id.hasPrefix(search.lowercased()) }
    }

    var body: some View {
        List {
            if !node.pendingAdverts.isEmpty {
                Section("Heard on the mesh — add?") {
                    ForEach(node.pendingAdverts) { c in
                        HStack {
                            ContactRowLabel(contact: c)
                            Spacer()
                            Button("Add") { Task { await node.addPending(c) } }.buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Ignore", role: .destructive) { node.dismissPending(c) }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            Section {
                ForEach(filtered) { c in
                    NavigationLink(value: c.id) { ContactRowLabel(contact: c, unread: node.unreadCount(in: .contact(publicKeyHex: c.id))) }
                }
            } header: {
                Text("\(node.contacts.count) contact\(node.contacts.count == 1 ? "" : "s")")
            }
        }
        .searchable(text: $search, prompt: "Name or key prefix")
        .overlay {
            if node.contacts.isEmpty && node.pendingAdverts.isEmpty {
                ContentUnavailableView("No contacts yet", systemImage: "person.2",
                                       description: Text("Contacts appear when nodes advertise, or import a meshcore:// link."))
            }
        }
        .navigationTitle("Contacts")
        .navigationDestination(for: String.self) { ContactDetailView(publicKeyHex: $0) }
        .navigationDestination(for: ConversationKey.self) { ConversationView(key: $0) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("My card", systemImage: "qrcode") { showMyCard = true }
                Button("Import", systemImage: "square.and.arrow.down") { showImport = true }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await node.refreshContacts() } }
            }
        }
        .sheet(isPresented: $showImport) { NavigationStack { ImportContactView() } }
        .sheet(isPresented: $showMyCard) { NavigationStack { ShareCardView(contact: nil) } }
        .refreshable { await node.refreshContacts() }
    }
}

struct ContactRowLabel: View {
    @Environment(NodeSession.self) private var node
    let contact: Contact
    var unread: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: contact.kind.icon).font(.title3).frame(width: 28).foregroundStyle(contact.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name.isEmpty ? "(unnamed)" : contact.name).font(.headline)
                HStack(spacing: 6) {
                    Text(contact.kind.label)
                    if let d = distanceText { Text("· \(d)") }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(contact.outPathLength < 0 ? "flood" : "\(contact.outPathLength) hop\(contact.outPathLength == 1 ? "" : "s")")
                if contact.lastAdvert > 0 {
                    Text(Date(timeIntervalSince1970: Double(contact.lastAdvert)), style: .relative)
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if unread > 0 { Circle().fill(.blue).frame(width: 8, height: 8) }
        }
        .padding(.vertical, 2)
    }

    private var distanceText: String? {
        guard let me = node.selfPosition, Geo.hasPosition(contact.latitude, contact.longitude) else { return nil }
        let d = Geo.distance(from: me, to: (contact.latitude, contact.longitude))
        return Geo.formatDistance(d) + " " + Geo.compass(Geo.bearing(from: me, to: (contact.latitude, contact.longitude)))
    }
}

extension Contact.Kind {
    var icon: String {
        switch self {
        case .chat: "person"
        case .repeater: "antenna.radiowaves.left.and.right"
        case .room: "person.3"
        case .sensor: "sensor"
        case .none: "questionmark"
        }
    }
    var label: String {
        switch self {
        case .chat: "Companion"
        case .repeater: "Repeater"
        case .room: "Room server"
        case .sensor: "Sensor"
        case .none: "Unknown"
        }
    }
    var tint: Color {
        switch self {
        case .chat: .blue
        case .repeater: .orange
        case .room: .purple
        case .sensor: .green
        case .none: .gray
        }
    }
}

struct ContactDetailView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    let publicKeyHex: String
    @State private var showShare = false
    @State private var confirmDelete = false

    var body: some View {
        if let c = node.contact(forHex: publicKeyHex) {
            Form {
                Section {
                    LabeledContent("Name", value: c.name)
                    LabeledContent("Type", value: c.kind.label)
                    LabeledContent("Public key") {
                        Text(c.id).font(.system(.caption, design: .monospaced)).textSelection(.enabled).multilineTextAlignment(.trailing)
                    }
                    if c.lastAdvert > 0 {
                        LabeledContent("Last heard", value: Date(timeIntervalSince1970: Double(c.lastAdvert)).formatted(date: .abbreviated, time: .shortened))
                    }
                }
                Section("Route") {
                    LabeledContent("Path", value: c.outPathLength < 0 ? "Flood (no learned route)" : "\(c.outPathLength) hop\(c.outPathLength == 1 ? "" : "s")")
                    if !c.outPath.isEmpty {
                        LabeledContent("Hops") {
                            Text(c.outPath.hexString).font(.system(.caption, design: .monospaced))
                        }
                    }
                    Button("Reset path (flood next message)") { Task { await node.resetPath(c) } }
                }
                Section("Position") {
                    if Geo.hasPosition(c.latitude, c.longitude) {
                        LabeledContent("Advertised", value: String(format: "%.5f, %.5f", c.latitude, c.longitude))
                        if let me = node.selfPosition {
                            let d = Geo.distance(from: me, to: (c.latitude, c.longitude))
                            let b = Geo.bearing(from: me, to: (c.latitude, c.longitude))
                            LabeledContent("From you", value: "\(Geo.formatDistance(d)) \(Geo.compass(b)) (\(Int(b))°)")
                        }
                    } else {
                        Text("No position advertised").foregroundStyle(.secondary)
                    }
                }
                Section {
                    if c.kind == .chat {
                        NavigationLink("Open conversation", value: ConversationKey.contact(publicKeyHex: c.id))
                    }
                    if c.kind == .repeater || c.kind == .room {
                        NavigationLink("Administer", value: AdminTarget(publicKeyHex: c.id))
                    }
                    Button("Share contact…", systemImage: "square.and.arrow.up") { showShare = true }
                    Button("Broadcast card to mesh", systemImage: "antenna.radiowaves.left.and.right") { Task { await node.shareToMesh(c) } }
                    NavigationLink("Diagnostics", value: DiagnosticsTarget(publicKeyHex: c.id))
                }
                Section {
                    Button("Delete contact", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(c.name)
            .navigationDestination(for: ConversationKey.self) { ConversationView(key: $0) }
            .navigationDestination(for: AdminTarget.self) { AdminView(publicKeyHex: $0.publicKeyHex) }
            .navigationDestination(for: DiagnosticsTarget.self) { DiagnosticsView(publicKeyHex: $0.publicKeyHex) }
            .sheet(isPresented: $showShare) { NavigationStack { ShareCardView(contact: c) } }
            .confirmationDialog("Delete \(c.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await node.removeContact(c); dismiss() } }
            }
        } else {
            ContentUnavailableView("Contact not found", systemImage: "person.slash")
        }
    }
}

struct AdminTarget: Hashable { let publicKeyHex: String }
struct DiagnosticsTarget: Hashable { let publicKeyHex: String }

/// meshcore:// link + QR for a contact, or our own node.
struct ShareCardView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    let contact: Contact?
    @State private var uri: String?

    var body: some View {
        VStack(spacing: 20) {
            if let uri {
                if let img = QRCode.image(for: uri) {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 320)
                }
                Text(uri).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).padding(.horizontal)
                ShareLink(item: uri) { Label("Share link", systemImage: "square.and.arrow.up") }.buttonStyle(.borderedProminent)
                Button("Copy") { UIPasteboard.general.string = uri }
            } else {
                ProgressView("Exporting card…")
            }
        }
        .padding()
        .navigationTitle(contact?.name ?? "My node")
        .toolbar { Button("Done") { dismiss() } }
        .task { uri = await node.shareURI(for: contact) }
    }
}

struct ImportContactView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        Form {
            Section("Paste a meshcore:// link") {
                TextField("meshcore://…", text: $text, axis: .vertical).lineLimit(3...8)
                    .font(.system(.caption, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Paste from clipboard") { text = UIPasteboard.general.string ?? text }
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle("Import contact")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    Task {
                        if await node.importContact(uri: text) { dismiss() } else { error = node.lastError }
                    }
                }.disabled(text.isEmpty)
            }
        }
    }
}
