import SwiftUI

/// App lock preferences + known radio profiles.
struct SecurityView: View {
    @Environment(NodeSession.self) private var node
    @Environment(AppLock.self) private var lock
    @State private var newPasscode = ""
    @State private var confirmRemove: NodeProfile?

    var body: some View {
        @Bindable var lock = lock
        Form {
            Section {
                Picker("Require \(lock.biometryLabel)", selection: $lock.mode) {
                    ForEach(AppLock.Mode.allCases) { Text($0.label).tag($0) }
                }
                if lock.mode == .everyForeground {
                    Picker("Re-lock after", selection: $lock.graceSeconds) {
                        Text("Immediately").tag(1); Text("1 minute").tag(60); Text("5 minutes").tag(300); Text("15 minutes").tag(900)
                    }
                }
                if !lock.deviceAuthAvailable { Text("Set a device passcode in Settings to enable app lock.").font(.caption).foregroundStyle(.red) }
            } header: { Text("App lock") } footer: {
                Text("Uses \(lock.biometryLabel) — the same protection as your iPad. Message history is stored with iOS complete data protection.")
            }
            Section {
                if let key = node.selfInfo?.publicKeyHex {
                    if lock.hasProfilePasscode(key) {
                        LabeledContent("This radio", value: "Passcode set")
                        Button("Remove profile passcode", role: .destructive) { node.setProfilePasscode(nil) }
                    } else {
                        SecureField("New profile passcode", text: $newPasscode)
                        Button("Set passcode for \(node.selfInfo?.name ?? "this radio")") { node.setProfilePasscode(newPasscode); newPasscode = "" }
                            .disabled(newPasscode.count < 4)
                    }
                } else {
                    Text("Connect a radio to set a per-radio passcode.").foregroundStyle(.secondary)
                }
            } header: { Text("Per-radio passcode") } footer: {
                Text("For iPads shared between people with their own radios: each radio's history can require its own passcode on top of the app lock.")
            }
            Section("Known radios") {
                ForEach(node.profiles) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(p.name).font(.headline)
                                if p.publicKeyHex == node.selfInfo?.publicKeyHex { Text("connected").font(.caption).foregroundStyle(.green) }
                                if lock.hasProfilePasscode(p.publicKeyHex) { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                            }
                            Text(p.model ?? "").font(.caption).foregroundStyle(.secondary)
                            Text(p.publicKeyHex.prefix(16) + "…").font(.system(.caption2, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("last used").font(.caption2).foregroundStyle(.secondary)
                            Text(p.lastConnected, style: .relative).font(.caption)
                        }
                    }
                    .swipeActions { Button("Forget", role: .destructive) { confirmRemove = p } }
                }
                if node.profiles.isEmpty { Text("No radios yet").foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Security & radios")
        .confirmationDialog("Forget \(confirmRemove?.name ?? "")? This deletes its message history on this iPad.",
                            isPresented: Binding(get: { confirmRemove != nil }, set: { if !$0 { confirmRemove = nil } }), titleVisibility: .visible) {
            Button("Forget radio", role: .destructive) { if let p = confirmRemove { node.removeProfile(p) }; confirmRemove = nil }
        }
    }
}
