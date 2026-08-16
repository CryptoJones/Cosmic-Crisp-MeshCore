import SwiftUI
import MeshCoreKit

/// Conversation list: channels + direct chats, most recent first, unread badges.
struct MessagesView: View {
    @Environment(NodeSession.self) private var node
    @State private var selected: ConversationKey?
    @State private var showChannels = false

    var body: some View {
        List(node.conversationKeys, id: \.self, selection: $selected) { key in
            NavigationLink(value: key) { ConversationRow(key: key) }
        }
        .overlay {
            if node.conversationKeys.isEmpty {
                ContentUnavailableView("No conversations", systemImage: "bubble.left.and.bubble.right",
                                       description: Text("Add a channel or wait for a contact advert."))
            }
        }
        .navigationTitle("Messages")
        .navigationDestination(for: ConversationKey.self) { ConversationView(key: $0) }
        .toolbar {
            Button("Channels", systemImage: "number") { showChannels = true }
        }
        .sheet(isPresented: $showChannels) { NavigationStack { ChannelsView() } }
    }
}

struct ConversationRow: View {
    @Environment(NodeSession.self) private var node
    let key: ConversationKey

    var body: some View {
        let last = node.messages(in: key).last
        let unread = node.unreadCount(in: key)
        HStack(spacing: 12) {
            Image(systemName: key.isChannel ? "number.circle.fill" : "person.circle.fill")
                .font(.title2).foregroundStyle(key.isChannel ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(node.title(for: key)).font(.headline)
                    Spacer()
                    if let last { Text(last.timestamp, style: .time).font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    Text(last.map { ($0.direction == .outgoing ? "You: " : "") + $0.text } ?? "No messages yet")
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    if unread > 0 {
                        Text("\(unread)").font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(.blue))
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

/// One conversation: bubbles + composer. DMs show delivery state.
struct ConversationView: View {
    @Environment(NodeSession.self) private var node
    let key: ConversationKey
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let msgs = node.messages(in: key)
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(msgs) { m in
                            MessageBubble(message: m, showSender: key.isChannel) { node.retry(m.id) }
                                .id(m.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: msgs.count) { _, _ in
                    if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
                .onAppear { if let last = msgs.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
            Divider()
            HStack(alignment: .bottom) {
                TextField("Message \(node.title(for: key))", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(send)
                Button(action: send) { Image(systemName: "arrow.up.circle.fill").font(.title) }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(node.title(for: key))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .contact(let hex) = key, let c = node.contact(forHex: hex) {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(c.outPathLength < 0 ? "flood" : "\(c.outPathLength) hop\(c.outPathLength == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { node.markRead(key) }
        .onChange(of: msgs.count) { _, _ in node.markRead(key) }
    }

    private func send() {
        node.send(text: draft, in: key)
        draft = ""
        focused = true
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let showSender: Bool
    let onRetry: () -> Void

    var body: some View {
        let outgoing = message.direction == .outgoing
        HStack {
            if outgoing { Spacer(minLength: 60) }
            VStack(alignment: outgoing ? .trailing : .leading, spacing: 3) {
                if !outgoing, showSender || message.signatureHex != nil, let name = message.senderName ?? message.senderPrefixHex {
                    Text(name).font(.caption.bold()).foregroundStyle(.secondary)
                }
                Text(message.text)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(outgoing ? Color.accentColor : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(outgoing ? .white : .primary)
                HStack(spacing: 6) {
                    Text(message.timestamp, style: .time)
                    if let snr = message.snr { Text(String(format: "SNR %.1f", snr)) }
                    if let hops = message.pathLength { Text(hops < 0 ? "direct" : "\(hops) hop\(hops == 1 ? "" : "s")") }
                    if outgoing { statusView }
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            if !outgoing { Spacer(minLength: 60) }
        }
    }

    @ViewBuilder private var statusView: some View {
        switch message.status {
        case .sending: ProgressView().controlSize(.mini)
        case .sent: Image(systemName: "checkmark")
        case .delivered:
            HStack(spacing: 2) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                if let rtt = message.roundTripMillis { Text("\(rtt) ms") }
            }
        case .failed:
            Button(action: onRetry) {
                Label("Failed — retry", systemImage: "exclamationmark.arrow.circlepath").foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}
