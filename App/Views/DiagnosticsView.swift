import SwiftUI
import MeshCoreKit

/// Per-contact diagnostics: path discovery and trace route.
struct DiagnosticsView: View {
    @Environment(NodeSession.self) private var node
    let publicKeyHex: String
    @State private var busy = false

    var body: some View {
        if let c = node.contact(forHex: publicKeyHex) {
            Form {
                Section("Learned route") {
                    LabeledContent("Out path", value: c.outPathLength < 0 ? "flood" : hopsText(c.outPath, hashLen: c.outPathHashMode + 1))
                }
                Section {
                    if let r = node.pathResults[c.id] {
                        LabeledContent("Out (us → them)", value: r.outHops.isEmpty ? "direct" : r.outHops.map(hopName).joined(separator: " → "))
                        LabeledContent("In (them → us)", value: r.inHops.isEmpty ? "direct" : r.inHops.map(hopName).joined(separator: " → "))
                    }
                    Button(busy ? "Discovering…" : "Discover path") { run { await node.discoverPath(c) } }.disabled(busy)
                } header: { Text("Path discovery") } footer: {
                    Text("Asks the mesh for the current route in both directions and updates the contact's learned path.")
                }
                Section {
                    if let t = node.traceResults[c.id] {
                        ForEach(Array(t.hops.enumerated()), id: \.offset) { i, hop in
                            LabeledContent("Hop \(i + 1): \(hopName(hop.hash))", value: String(format: "SNR %.2f dB", hop.snr))
                        }
                        if let f = t.finalSNR { LabeledContent("Final hop (to us)", value: String(format: "SNR %.2f dB", f)) }
                        if t.hops.isEmpty && t.finalSNR == nil { Text("Trace returned with no hop data").foregroundStyle(.secondary) }
                    }
                    Button(busy ? "Tracing…" : "Trace route") { run { await node.trace(c) } }.disabled(busy)
                } header: { Text("Trace route") } footer: {
                    Text("Sends a trace along the learned path; every repeater stamps its SNR on the way back.")
                }
                Section {
                    NavigationLink("Packet log", value: PacketLogTarget())
                }
            }
            .navigationTitle("\(c.name) — diagnostics")
            .navigationDestination(for: PacketLogTarget.self) { _ in PacketLogView() }
        } else {
            ContentUnavailableView("Contact not found", systemImage: "person.slash")
        }
    }

    private func run(_ op: @escaping () async -> Void) { busy = true; Task { await op(); busy = false } }
    private func hopName(_ hash: [UInt8]) -> String { node.nameForHop(hash) ?? hash.hexString }
    private func hopsText(_ path: [UInt8], hashLen: Int) -> String {
        guard !path.isEmpty else { return "direct" }
        return stride(from: 0, to: path.count, by: max(hashLen, 1)).map { hopName(Array(path[$0..<min($0 + max(hashLen, 1), path.count)])) }.joined(separator: " → ")
    }
}

struct PacketLogTarget: Hashable {}

/// Raw packets and RF log lines pushed by the node.
struct PacketLogView: View {
    @Environment(NodeSession.self) private var node
    @State private var showHex = true

    var body: some View {
        @Bindable var node = node
        List(node.packetLog.reversed()) { e in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(e.kind.rawValue).font(.caption.bold()).foregroundStyle(e.kind == .raw ? .blue : .secondary)
                    Text(e.date, style: .time).font(.caption)
                    if let snr = e.snr { Text(String(format: "SNR %.2f", snr)).font(.caption) }
                    if let rssi = e.rssi { Text("RSSI \(rssi)").font(.caption) }
                    Spacer()
                    Text("\(e.payload.count) B").font(.caption).foregroundStyle(.secondary)
                }
                Text(showHex ? e.payload.hexString : String(decoding: e.payload.filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self))
                    .font(.system(.caption2, design: .monospaced)).textSelection(.enabled)
            }
        }
        .overlay { if node.packetLog.isEmpty { ContentUnavailableView("No packets logged", systemImage: "waveform.path.ecg", description: Text("Raw packets and RF log lines the node pushes appear here.")) } }
        .navigationTitle("Packet log")
        .toolbar {
            Toggle("Log", isOn: $node.packetLogEnabled).toggleStyle(.switch)
            Toggle("Hex", isOn: $showHex).toggleStyle(.button)
            Button("Clear", systemImage: "trash") { node.clearPacketLog() }
        }
    }
}
