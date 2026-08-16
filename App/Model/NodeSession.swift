import Foundation
import Observation
import MeshCoreKit

/// App-facing state for the connected node. Owns the `MeshCoreClient`, keeps
/// contacts / channels / conversations, drains pushes, and runs the outbound
/// delivery + retry state machine.
@MainActor
@Observable
final class NodeSession {
    enum Status: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    private(set) var status: Status = .disconnected
    private(set) var selfInfo: SelfInfo?
    private(set) var deviceInfo: DeviceInfo?
    private(set) var battery: BatteryInfo?
    private(set) var contacts: [Contact] = []
    private(set) var channels: [ChannelSlot] = []
    private(set) var messages: [ChatMessage] = []
    private(set) var lastRead: [String: Date] = [:]
    private(set) var customVars: [String: String] = [:]
    private(set) var lastError: String?
    /// Adverts heard while manual-add-contacts is on: candidates the user can add.
    private(set) var pendingAdverts: [Contact] = []
    /// Cached self telemetry (battery/temp/GPS) from the node's own sensors.
    private(set) var selfTelemetry: TelemetryResponse?

    var gpsEnabled: Bool { customVars["gps"] == "1" }
    var transportDescription: String { TransportFactory.description }

    private var client: MeshCoreClient?
    private var store: MessageStore?
    private var pushTask: Task<Void, Never>?
    private var deliveryTask: Task<Void, Never>?
    private var tracker = DeliveryTracker()
    /// Serialises outbound sends so the one-request-at-a-time client is never overlapped.
    private var sendQueue: [() async -> Void] = []
    private var sending = false

    // MARK: - Lifecycle

    func connect() async {
        guard client == nil else { return }
        status = .connecting
        do {
            let transport = try await TransportFactory.make()
            let c = MeshCoreClient(transport: transport)
            await c.start()
            client = c
            let info = try await c.appStart()
            selfInfo = info
            let s = MessageStore(nodeKeyHex: info.publicKeyHex)
            store = s
            messages = await s.messages
            lastRead = await s.lastRead
            deviceInfo = try? await c.deviceInfo()
            battery = try? await c.battery()
            customVars = (try? await c.customVars()) ?? [:]
            contacts = (try? await c.contacts()) ?? []
            selfTelemetry = try? await c.selfTelemetry()
            await loadChannels()
            status = .connected
            pushTask = Task { [weak self] in
                for await push in c.pushes { await self?.handle(push) }
            }
            deliveryTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    await self?.sweepExpired()
                }
            }
            await drainMessages()
        } catch {
            status = .failed("\(error)")
            lastError = "\(error)"
        }
    }

    func disconnect() async {
        pushTask?.cancel(); deliveryTask?.cancel()
        await store?.flush()
        await client?.stop()
        client = nil
        status = .disconnected
    }

    // MARK: - Node

    func refreshContacts() async {
        guard let client else { return }
        contacts = (try? await client.contacts()) ?? contacts
    }

    func refreshBattery() async {
        guard let client else { return }
        battery = try? await client.battery()
    }

    func setGPS(_ on: Bool) async {
        guard let client else { return }
        do {
            try await client.setGPS(enabled: on)
            customVars = (try? await client.customVars()) ?? customVars
        } catch { lastError = "\(error)" }
    }

    func setName(_ name: String) async {
        guard let client else { return }
        do {
            try await client.setName(name)
            selfInfo = try await client.appStart()
        } catch { lastError = "\(error)" }
    }

    func sendAdvert(flood: Bool) async {
        guard let client else { return }
        do { try await client.sendAdvert(flood: flood) } catch { lastError = "\(error)" }
    }

    // MARK: - Contacts

    var selfPosition: (Double, Double)? {
        // Prefer the live GPS fix from telemetry, fall back to the advertised position.
        if let loc = selfTelemetry?.records.compactMap({ r -> (Double, Double)? in
            if case .location(let la, let lo, _) = r.value, Geo.hasPosition(la, lo) { return (la, lo) } else { return nil }
        }).first { return loc }
        if let s = selfInfo, Geo.hasPosition(s.latitude, s.longitude) { return (s.latitude, s.longitude) }
        return nil
    }

    func refreshSelfTelemetry() async {
        guard let client else { return }
        selfTelemetry = try? await client.selfTelemetry()
    }

    func resetPath(_ c: Contact) async {
        guard let client else { return }
        do { try await client.resetPath(publicKey: c.publicKey); await refreshContacts() }
        catch { lastError = "\(error)" }
    }

    func removeContact(_ c: Contact) async {
        guard let client else { return }
        do {
            try await client.removeContact(publicKey: c.publicKey)
            contacts.removeAll { $0.publicKey == c.publicKey }
        } catch { lastError = "\(error)" }
    }

    /// `meshcore://…` URI for a contact, or for our own node when nil.
    func shareURI(for c: Contact?) async -> String? {
        guard let client else { return nil }
        do { return "meshcore://" + (try await client.exportContact(publicKey: c?.publicKey)).hexString }
        catch { lastError = "\(error)"; return nil }
    }

    /// Import a `meshcore://<hex>` card. Returns false (and sets lastError) on failure.
    @discardableResult
    func importContact(uri: String) async -> Bool {
        guard let client else { return false }
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasPrefix("meshcore://"),
              let card = ChannelKeys.bytes(fromHex: String(trimmed.dropFirst("meshcore://".count))) else {
            lastError = "Not a meshcore:// contact link"; return false
        }
        do {
            try await client.importContact(card: card)
            await refreshContacts()
            return true
        } catch { lastError = "\(error)"; return false }
    }

    /// Ask the node to re-broadcast a contact's card to the mesh.
    func shareToMesh(_ c: Contact) async {
        guard let client else { return }
        do { try await client.shareContact(publicKey: c.publicKey) } catch { lastError = "\(error)" }
    }

    /// Manual-add flow: promote a heard advert into the contact list.
    func addPending(_ c: Contact) async {
        guard let client else { return }
        do {
            try await client.addOrUpdateContact(c)
            pendingAdverts.removeAll { $0.publicKey == c.publicKey }
            await refreshContacts()
        } catch { lastError = "\(error)" }
    }

    func dismissPending(_ c: Contact) { pendingAdverts.removeAll { $0.publicKey == c.publicKey } }

    // MARK: - Channels

    /// Node firmware exposes a fixed number of channel slots (deviceInfo.maxChannels, default 8).
    var channelSlotCount: Int { max(1, min(deviceInfo?.maxChannels ?? 8, 40)) }

    func loadChannels() async {
        guard let client else { return }
        var slots: [ChannelSlot] = []
        for i in 0..<channelSlotCount {
            guard let info = try? await client.channel(UInt8(i)) else { break }
            slots.append(ChannelSlot(index: info.index, name: info.name, secretHex: info.secret.hexString))
        }
        channels = slots
    }

    func setChannel(index: UInt8, name: String, secret: [UInt8]) async {
        guard let client else { return }
        do {
            try await client.setChannel(index, name: name, secret: secret)
            await loadChannels()
        } catch { lastError = "\(error)" }
    }

    func clearChannel(index: UInt8) async {
        await setChannel(index: index, name: "", secret: [UInt8](repeating: 0, count: 16))
    }

    var configuredChannels: [ChannelSlot] { channels.filter { !$0.isEmpty } }
    var freeChannelIndex: UInt8? { channels.first(where: \.isEmpty)?.index }

    // MARK: - Conversations

    func messages(in key: ConversationKey) -> [ChatMessage] {
        messages.filter { $0.conversation == key }
    }

    func unreadCount(in key: ConversationKey) -> Int {
        let since = lastRead[MessageStore.keyString(key)] ?? .distantPast
        return messages.filter { $0.conversation == key && $0.direction == .incoming && $0.timestamp > since }.count
    }

    var totalUnread: Int {
        Set(messages.map(\.conversation)).reduce(0) { $0 + unreadCount(in: $1) }
    }

    func markRead(_ key: ConversationKey) {
        lastRead[MessageStore.keyString(key)] = .now
        Task { await store?.markRead(key) }
    }

    func contact(forHex hex: String) -> Contact? { contacts.first { $0.id == hex } }

    /// Conversations ordered by most recent activity: every configured channel and
    /// every chat-type contact, plus anything with history.
    var conversationKeys: [ConversationKey] {
        var keys = Set<ConversationKey>()
        for ch in configuredChannels { keys.insert(.channel(index: ch.index)) }
        for c in contacts where c.kind == .chat { keys.insert(.contact(publicKeyHex: c.id)) }
        for m in messages { keys.insert(m.conversation) }
        return keys.sorted { lastActivity($0) > lastActivity($1) }
    }

    private func lastActivity(_ key: ConversationKey) -> Date {
        messages.last { $0.conversation == key }?.timestamp ?? .distantPast
    }

    func title(for key: ConversationKey) -> String {
        switch key {
        case .channel(let idx):
            let ch = channels.first { $0.index == idx }
            return ch.map { $0.name.isEmpty ? "Channel \(idx)" : $0.name } ?? "Channel \(idx)"
        case .contact(let hex):
            return contact(forHex: hex)?.name ?? "\(hex.prefix(12))…"
        }
    }

    // MARK: - Sending

    func send(text: String, in key: ConversationKey) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let m = ChatMessage(conversation: key, direction: .outgoing, text: trimmed, status: .sending)
        messages.append(m)
        Task { await store?.append(m) }
        enqueue { [weak self] in await self?.transmit(m.id, attempt: 0) }
    }

    func retry(_ id: UUID) {
        guard let m = messages.first(where: { $0.id == id }), m.status == .failed else { return }
        update(id) { $0.status = .sending; $0.attempt = 0 }
        enqueue { [weak self] in await self?.transmit(id, attempt: 0) }
    }

    private func enqueue(_ job: @escaping () async -> Void) {
        sendQueue.append(job)
        guard !sending else { return }
        sending = true
        Task { [weak self] in
            while let next = await self?.dequeue() { await next() }
            await self?.finishedSending()
        }
    }
    private func dequeue() -> (() async -> Void)? { sendQueue.isEmpty ? nil : sendQueue.removeFirst() }
    private func finishedSending() { sending = false }

    private func transmit(_ id: UUID, attempt: Int) async {
        guard let client, let m = messages.first(where: { $0.id == id }) else { return }
        do {
            switch m.conversation {
            case .channel(let idx):
                try await client.sendChannelMessage(channel: idx, text: m.text)
                update(id) { $0.status = .sent; $0.attempt = attempt }
            case .contact(let hex):
                guard let contact = contact(forHex: hex) else {
                    update(id) { $0.status = .failed }; lastError = "Unknown contact"; return
                }
                let sent = try await client.sendMessage(to: contact.publicKey, text: m.text)
                _ = tracker.track(messageID: id, sent: sent, attempt: attempt)
                update(id) { $0.status = .sent; $0.attempt = attempt }
            }
        } catch {
            lastError = "\(error)"
            await failedAttempt(id, attempt: attempt)
        }
    }

    private func failedAttempt(_ id: UUID, attempt: Int) async {
        switch DeliveryTracker.nextStep(afterFailedAttempt: attempt) {
        case .giveUp:
            update(id) { $0.status = .failed }
        case .retry(let next):
            enqueue { [weak self] in await self?.transmit(id, attempt: next) }
        case .resetPathThenRetry(let next):
            if let client, let m = messages.first(where: { $0.id == id }),
               case .contact(let hex) = m.conversation, let c = contact(forHex: hex) {
                try? await client.resetPath(publicKey: c.publicKey)
                await refreshContacts()
            }
            enqueue { [weak self] in await self?.transmit(id, attempt: next) }
        }
    }

    private func sweepExpired() async {
        for p in tracker.expired() {
            await failedAttempt(p.messageID, attempt: p.attempt)
        }
    }

    private func update(_ id: UUID, _ change: @Sendable @escaping (inout ChatMessage) -> Void) {
        if let i = messages.firstIndex(where: { $0.id == id }) { change(&messages[i]) }
        Task { await store?.update(id, change) }
    }

    // MARK: - Inbound

    private func handle(_ push: Response) async {
        switch push {
        case .pushMessagesWaiting:
            await drainMessages()
        case .pushSendConfirmed(let ack, let rtt):
            if let id = tracker.confirm(ackCode: ack) {
                update(id) { $0.status = .delivered; $0.roundTripMillis = rtt }
            }
        case .pushNewAdvert(let contact):
            if selfInfo?.manualAddContacts == true, !contacts.contains(where: { $0.publicKey == contact.publicKey }) {
                if let i = pendingAdverts.firstIndex(where: { $0.publicKey == contact.publicKey }) { pendingAdverts[i] = contact }
                else { pendingAdverts.append(contact) }
            } else {
                upsert(contact)
            }
        case .pushContactDeleted(let key):
            contacts.removeAll { $0.publicKey == key }
        case .pushAdvert, .pushPathUpdated:
            await refreshContacts()
        default:
            break
        }
    }

    private func drainMessages() async {
        guard let client else { return }
        while let m = try? await client.nextMessage() {
            let key: ConversationKey
            var prefixHex: String?
            var name: String?
            switch m.source {
            case .contact(let prefix):
                prefixHex = prefix.hexString
                if let c = contacts.first(where: { $0.publicKey.starts(with: prefix) }) {
                    key = .contact(publicKeyHex: c.id); name = c.name
                } else {
                    // Unknown sender: refresh once, then fall back to a prefix-keyed conversation.
                    await refreshContacts()
                    if let c = contacts.first(where: { $0.publicKey.starts(with: prefix) }) {
                        key = .contact(publicKeyHex: c.id); name = c.name
                    } else {
                        key = .contact(publicKeyHex: prefix.hexString)
                    }
                }
            case .channel(let idx):
                key = .channel(index: idx)
            }
            let ts = m.senderTimestamp > 0 ? Date(timeIntervalSince1970: Double(m.senderTimestamp)) : .now
            let chat = ChatMessage(conversation: key, direction: .incoming, text: m.text, timestamp: ts,
                                   status: .delivered, snr: m.snr, pathLength: m.pathLength,
                                   senderPrefixHex: prefixHex, senderName: name)
            messages.append(chat)
            await store?.append(chat)
        }
    }

    private func upsert(_ contact: Contact) {
        if let i = contacts.firstIndex(where: { $0.publicKey == contact.publicKey }) {
            contacts[i] = contact
        } else {
            contacts.append(contact)
        }
    }
}
