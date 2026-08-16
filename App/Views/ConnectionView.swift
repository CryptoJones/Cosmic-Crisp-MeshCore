import SwiftUI

/// Where the radio is: USB (device build), or a TCP endpoint (bridge / WiFi companion).
struct ConnectionView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    @State private var host = TransportFactory.savedTCP?.host ?? ""
    @State private var port = String(TransportFactory.savedTCP?.port ?? 5000)

    var body: some View {
        Form {
            Section {
                LabeledContent("Current", value: node.transportDescription)
                LabeledContent("Status", value: statusText)
            }
            Section {
                TextField("Host (e.g. makemake.local or 192.168.1.20)", text: $host).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Port", text: $port).keyboardType(.numberPad)
                Button("Save & connect") {
                    TransportFactory.savedTCP = host.isEmpty ? nil : .init(host: host, port: UInt16(port) ?? 5000)
                    Task { await node.disconnect(); await node.connect(); dismiss() }
                }
                if TransportFactory.savedTCP != nil {
                    Button("Clear TCP endpoint (use USB)", role: .destructive) {
                        TransportFactory.savedTCP = nil
                        Task { await node.disconnect(); await node.connect(); dismiss() }
                    }
                }
            } header: { Text("TCP radio") } footer: {
                Text("Run tools/serial-bridge.py on the computer the radio is plugged into, or point at a MeshCore WiFi companion node. Leave blank on a device build to use USB.")
            }
            Section { Button("Reconnect") { Task { await node.disconnect(); await node.connect() } } }
        }
        .navigationTitle("Connection")
        .toolbar { Button("Done") { dismiss() } }
    }

    private var statusText: String {
        switch node.status {
        case .connected: "Connected to \(node.selfInfo?.name ?? "node")"
        case .connecting: "Connecting…"
        case .disconnected: "Disconnected"
        case .failed(let why): "Failed: \(why)"
        }
    }
}
