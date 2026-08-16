import SwiftUI
import MeshCoreKit

/// Manage the node's channel slots: add (public / hashtag / custom key), rename, remove.
struct ChannelsView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    @State private var editing: ChannelSlot?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                ForEach(node.channels) { slot in
                    Button { editing = slot } label: {
                        HStack {
                            Text("\(slot.index)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 22)
                            if slot.isEmpty {
                                Text("Empty slot").foregroundStyle(.tertiary)
                            } else {
                                VStack(alignment: .leading) {
                                    Text(slot.name)
                                    Text(slot.secretHex).font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if slot.secretHex == ChannelKeys.publicChannel.hexString {
                                Text("public").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("Channels are group chats keyed by a shared 16-byte secret. `#hashtag` names derive their key from the name so anyone can join by typing it.")
            }
        }
        .navigationTitle("Channels")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { adding = true }.disabled(node.freeChannelIndex == nil)
            }
        }
        .sheet(item: $editing) { slot in NavigationStack { ChannelEditor(slot: slot) } }
        .sheet(isPresented: $adding) {
            if let idx = node.freeChannelIndex {
                NavigationStack { ChannelEditor(slot: ChannelSlot(index: idx, name: "", secretHex: "")) }
            }
        }
        .task { await node.loadChannels() }
        .refreshable { await node.loadChannels() }
    }
}

struct ChannelEditor: View {
    enum KeyMode: String, CaseIterable, Identifiable {
        case hashtag = "Hashtag", publicKey = "Public", custom = "Custom key", random = "Random key"
        var id: String { rawValue }
    }

    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    let slot: ChannelSlot
    @State private var name: String
    @State private var mode: KeyMode
    @State private var customHex: String

    init(slot: ChannelSlot) {
        self.slot = slot
        _name = State(initialValue: slot.name)
        _customHex = State(initialValue: slot.secretHex)
        if slot.secretHex == ChannelKeys.publicChannel.hexString { _mode = State(initialValue: .publicKey) }
        else if slot.name.hasPrefix("#") { _mode = State(initialValue: .hashtag) }
        else if slot.isEmpty { _mode = State(initialValue: .hashtag) }
        else { _mode = State(initialValue: .custom) }
    }

    private var secret: [UInt8]? {
        switch mode {
        case .publicKey: ChannelKeys.publicChannel
        case .hashtag: name.hasPrefix("#") ? ChannelKeys.hashtagSecret(for: name) : nil
        case .custom: ChannelKeys.secret(fromHex: customHex)
        case .random: ChannelKeys.secret(fromHex: customHex) ?? nil
        }
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField(mode == .hashtag ? "#hashtag" : "Channel name", text: $name)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                if mode == .hashtag && !name.isEmpty && !name.hasPrefix("#") {
                    Text("Hashtag channels must start with #").font(.caption).foregroundStyle(.red)
                }
            }
            Section("Key") {
                Picker("Key", selection: $mode) { ForEach(KeyMode.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .onChange(of: mode) { _, m in
                        if m == .random { customHex = ChannelKeys.randomSecret().hexString }
                        if m == .publicKey && name.isEmpty { name = "Public" }
                    }
                switch mode {
                case .custom, .random:
                    TextField("32 hex characters", text: $customHex)
                        .font(.system(.body, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                case .publicKey:
                    Text(ChannelKeys.publicChannel.hexString).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                case .hashtag:
                    Text("Derived from the name (SHA-256).").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !slot.isEmpty {
                Section {
                    Button("Remove channel", role: .destructive) {
                        Task { await node.clearChannel(index: slot.index); dismiss() }
                    }
                }
            }
        }
        .navigationTitle(slot.isEmpty ? "Add channel (slot \(slot.index))" : "Edit channel \(slot.index)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let secret else { return }
                    Task { await node.setChannel(index: slot.index, name: name, secret: secret); dismiss() }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || secret == nil)
            }
        }
    }
}
