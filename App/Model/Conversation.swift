import Foundation
import MeshCoreKit

/// Where a message lives: a direct chat with a contact, or a channel slot.
enum ConversationKey: Hashable, Codable, Sendable {
    case contact(publicKeyHex: String)
    case channel(index: UInt8)

    var isChannel: Bool { if case .channel = self { return true } else { return false } }
}

/// One message in a conversation, persisted.
struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Direction: String, Codable, Sendable { case incoming, outgoing }
    enum Status: String, Codable, Sendable {
        case sending      // handed to the node, awaiting messageSent
        case sent         // node accepted; awaiting ACK (DMs) — final for channels
        case delivered    // ACK received
        case failed       // gave up after retries or node error
    }

    let id: UUID
    let conversation: ConversationKey
    let direction: Direction
    var text: String
    /// Sender-side timestamp (epoch seconds) for incoming; local send time for outgoing.
    var timestamp: Date
    var status: Status
    var attempt: Int
    var snr: Double?
    var pathLength: Int?
    /// For incoming DMs when the sender wasn't in contacts at receive time.
    var senderPrefixHex: String?
    var senderName: String?
    var roundTripMillis: UInt32?

    init(id: UUID = UUID(), conversation: ConversationKey, direction: Direction, text: String,
         timestamp: Date = .now, status: Status, attempt: Int = 0, snr: Double? = nil,
         pathLength: Int? = nil, senderPrefixHex: String? = nil, senderName: String? = nil) {
        self.id = id; self.conversation = conversation; self.direction = direction; self.text = text
        self.timestamp = timestamp; self.status = status; self.attempt = attempt; self.snr = snr
        self.pathLength = pathLength; self.senderPrefixHex = senderPrefixHex; self.senderName = senderName
    }
}

/// A configured channel slot on the node.
struct ChannelSlot: Identifiable, Codable, Equatable, Sendable {
    let index: UInt8
    var name: String
    var secretHex: String
    var id: UInt8 { index }
    var isEmpty: Bool { name.isEmpty }
}

/// JSON-file persistence for messages + per-conversation read markers, keyed by
/// the node's public key so switching radios doesn't mix histories.
actor MessageStore {
    struct Snapshot: Codable {
        var messages: [ChatMessage] = []
        var lastRead: [String: Date] = [:]     // ConversationKey encoded as string
    }

    private let url: URL
    private var snapshot = Snapshot()
    private var saveTask: Task<Void, Never>?

    init(nodeKeyHex: String, directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CosmicCrisp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("messages-\(nodeKeyHex.prefix(16)).json")
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = s
        }
    }

    var messages: [ChatMessage] { snapshot.messages }
    var lastRead: [String: Date] { snapshot.lastRead }

    func append(_ m: ChatMessage) { snapshot.messages.append(m); scheduleSave() }

    func update(_ id: UUID, _ change: @Sendable (inout ChatMessage) -> Void) {
        guard let i = snapshot.messages.firstIndex(where: { $0.id == id }) else { return }
        change(&snapshot.messages[i]); scheduleSave()
    }

    func markRead(_ key: ConversationKey, at date: Date = .now) {
        snapshot.lastRead[Self.keyString(key)] = date; scheduleSave()
    }

    func clear() { snapshot = Snapshot(); scheduleSave() }

    static func keyString(_ key: ConversationKey) -> String {
        switch key {
        case .contact(let hex): "c:\(hex)"
        case .channel(let idx): "ch:\(idx)"
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [snapshot, url] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
        }
    }

    /// Flush immediately (tests, app background).
    func flush() {
        saveTask?.cancel()
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: url, options: .atomic) }
    }
}
