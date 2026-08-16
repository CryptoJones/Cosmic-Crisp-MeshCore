import SwiftUI
import MeshCoreKit

/// Repeater / room-server administration: login, status, remote CLI.
struct AdminView: View {
    @Environment(NodeSession.self) private var node
    let publicKeyHex: String
    @State private var password = ""
    @State private var command = ""
    @FocusState private var cmdFocused: Bool

    var body: some View {
        if let c = node.contact(forHex: publicKeyHex) {
            let st = node.adminState(c.id)
            Form {
                Section("Session") {
                    if st.loggedIn {
                        LabeledContent("Logged in", value: st.isAdmin ? "admin" : "guest")
                        Button("Log out") { Task { await node.logout(c) } }
                    } else {
                        SecureField("Password (blank for guest)", text: $password)
                        Button(st.busy ? "Logging in…" : "Log in") { Task { await node.login(c, password: password) } }.disabled(st.busy)
                        if st.lastLoginFailed { Text("Login failed or no reply").foregroundStyle(.red).font(.caption) }
                    }
                }
                Section {
                    if let s = st.status {
                        LabeledContent("Battery", value: String(format: "%.2f V", Double(s.batteryMillivolts) / 1000))
                        LabeledContent("Uptime", value: Duration.seconds(Int(s.uptimeSeconds)).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated)))
                        LabeledContent("Noise floor / last RSSI", value: "\(s.noiseFloor) / \(s.lastRSSI) dBm")
                        LabeledContent("Last SNR", value: String(format: "%.1f dB", s.lastSNR))
                        LabeledContent("Packets RX / TX", value: "\(s.packetsReceived) / \(s.packetsSent)")
                        LabeledContent("Flood / direct TX", value: "\(s.sentFlood) / \(s.sentDirect)")
                        LabeledContent("Flood / direct RX", value: "\(s.receivedFlood) / \(s.receivedDirect)")
                        LabeledContent("Duplicates (direct / flood)", value: "\(s.directDuplicates) / \(s.floodDuplicates)")
                        LabeledContent("Airtime TX / RX", value: "\(s.airtimeSeconds) s / \(s.rxAirtimeSeconds) s")
                        LabeledContent("TX queue / full events", value: "\(s.txQueueLength) / \(s.fullEvents)")
                        if let e = s.receiveErrors { LabeledContent("RX errors", value: "\(e)") }
                    }
                    Button(st.busy ? "Requesting…" : "Request status") { Task { await node.requestStatus(c) } }.disabled(st.busy)
                } header: { Text("Status") } footer: {
                    if let d = st.statusDate { Text("As of \(d.formatted(date: .omitted, time: .standard))") }
                }
                Section {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(st.console) { line in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(line.outgoing ? ">" : "<").foregroundStyle(line.outgoing ? .blue : .green)
                                        Text(line.text)
                                    }
                                    .font(.system(.footnote, design: .monospaced)).id(line.id)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 120, maxHeight: 280)
                        .onChange(of: st.console.count) { _, _ in if let l = st.console.last { proxy.scrollTo(l.id) } }
                    }
                    HStack {
                        TextField("Command (e.g. ver, clock, get name)", text: $command)
                            .font(.system(.body, design: .monospaced))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($cmdFocused)
                            .onSubmit(sendCommand)
                        Button("Send", action: sendCommand).disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack {
                        ForEach(["ver", "clock", "get name", "get radio", "neighbors"], id: \.self) { q in
                            Button(q) { command = q; sendCommand() }.buttonStyle(.bordered).controlSize(.mini).font(.system(.caption, design: .monospaced))
                        }
                    }
                } header: { Text("Remote CLI") } footer: {
                    Text(st.loggedIn ? "Replies arrive over the mesh and appear above." : "Log in first — most commands need an admin session.")
                }
            }
            .navigationTitle("\(c.name) — admin")
        } else {
            ContentUnavailableView("Contact not found", systemImage: "person.slash")
        }
    }

    private func sendCommand() {
        guard let c = node.contact(forHex: publicKeyHex) else { return }
        let text = command.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        command = ""
        cmdFocused = true
        Task { await node.sendCommand(c, text) }
    }
}
