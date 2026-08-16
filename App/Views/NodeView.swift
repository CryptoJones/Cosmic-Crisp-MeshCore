import SwiftUI
import MeshCoreKit

struct NodeView: View {
    @Environment(NodeSession.self) private var node
    @State private var newName = ""

    var body: some View {
        Form {
            if let s = node.selfInfo {
                Section("Identity") {
                    LabeledContent("Name", value: s.name)
                    LabeledContent("Public key", value: s.publicKeyHex).font(.system(.footnote, design: .monospaced))
                    HStack {
                        TextField("New name", text: $newName)
                        Button("Rename") { Task { await node.setName(newName); newName = "" } }
                            .disabled(newName.isEmpty)
                    }
                }
                Section("Radio") {
                    LabeledContent("Frequency", value: String(format: "%.3f MHz", s.radioFrequencyMHz))
                    LabeledContent("Bandwidth", value: String(format: "%.1f kHz", s.radioBandwidthKHz))
                    LabeledContent("Spreading factor", value: "\(s.spreadingFactor)")
                    LabeledContent("Coding rate", value: "4/\(s.codingRate)")
                    LabeledContent("TX power", value: "\(s.txPower) / \(s.maxTxPower) dBm")
                }
                Section("Position") {
                    LabeledContent("Advertised", value: String(format: "%.6f, %.6f", s.latitude, s.longitude))
                    Toggle("GPS", isOn: Binding(get: { node.gpsEnabled }, set: { on in Task { await node.setGPS(on) } }))
                    Button("Send advert") { Task { await node.sendAdvert(flood: false) } }
                    Button("Flood advert") { Task { await node.sendAdvert(flood: true) } }
                }
            }
            Section("Device") {
                if let d = node.deviceInfo {
                    LabeledContent("Firmware", value: "\(d.version ?? "?") (protocol v\(d.firmwareVersion))")
                    LabeledContent("Model", value: d.model ?? "?")
                    LabeledContent("Build", value: d.firmwareBuild ?? "?")
                }
                if let b = node.battery {
                    LabeledContent("Battery", value: String(format: "%.2f V", Double(b.millivolts) / 1000))
                }
                Button("Refresh") { Task { await node.refreshBattery() } }
            }
            if let err = node.lastError {
                Section("Last error") { Text(err).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Node")
    }
}
