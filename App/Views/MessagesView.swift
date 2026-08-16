import SwiftUI
import MeshCoreKit

struct MessagesView: View {
    @Environment(NodeSession.self) private var node
    @State private var channelDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            List(node.messages) { m in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(sender(m)).font(.subheadline.bold())
                        Spacer()
                        Text(m.received, style: .time).font(.caption).foregroundStyle(.secondary)
                        if let snr = m.message.snr {
                            Text(String(format: "SNR %.2f", snr)).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Text(m.message.text)
                }
            }
            .overlay { if node.messages.isEmpty { ContentUnavailableView("No messages", systemImage: "bubble.left") } }
            HStack {
                TextField("Message channel 0", text: $channelDraft).textFieldStyle(.roundedBorder)
                Button("Send") {
                    let t = channelDraft; channelDraft = ""
                    Task { await node.send(text: t, channel: 0) }
                }.disabled(channelDraft.isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle("Messages")
    }

    private func sender(_ m: NodeSession.LoggedMessage) -> String {
        switch m.message.source {
        case .contact(let prefix): m.senderName ?? prefix.hexString
        case .channel(let idx): "Channel \(idx)"
        }
    }
}
