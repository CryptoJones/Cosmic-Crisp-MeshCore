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
    /// Known radios (per public key). Updated on every successful connect.
    private(set) var profiles: [NodeProfile] = ProfileStore.load()
    /// True when the connected node has a profile passcode that has not been entered this session.
    private(set) var profileLocked = false
    var appLock: AppLock?
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
            deviceInfo = try? await c.deviceInfo()
            profiles = ProfileStore.touch(publicKeyHex: info.publicKeyHex, name: info.name, model: deviceInfo?.model)
            profileLocked = appLock?.hasProfilePasscode(info.publicKeyHex) ?? false
            let s = MessageStore(nodeKeyHex: info.publicKeyHex)
            store = s
            messages = await s.messages
            lastRead = await s.lastRead
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

    // MARK: - Repeater / room admin

    struct AdminState: Equatable {
        struct ConsoleLine: Identifiable, Equatable { let id = UUID(); let date: Date; let outgoing: Bool; let text: String }
        var loggedIn = false
        var isAdmin = false
        var lastLoginFailed = false
        var status: NodeStatus?
        var statusDate: Date?
        var console: [ConsoleLine] = []
        var busy = false
    }
    private(set) var admin: [String: AdminState] = [:]

    func adminState(_ hex: String) -> AdminState { admin[hex] ?? AdminState() }

    private func prefixHex(_ c: Contact) -> String { Array(c.publicKey.prefix(6)).hexString }

    /// Wait for a specific push (login result / status) for a contact, with timeout.
    private func awaitPush(_ key: String, timeout: Duration) async -> Response? {
        await withCheckedContinuation { (cont: CheckedContinuation<Response?, Never>) in
            awaitingBox[key] = ContinuationHolder(cont)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.timeoutPush(key)
            }
        }
    }
    private var awaitingBox: [String: ContinuationHolder] = [:]
    private func timeoutPush(_ key: String) { awaitingBox.removeValue(forKey: key)?.resume(nil) }
    private func deliverPush(_ key: String, _ r: Response) -> Bool {
        guard let h = awaitingBox.removeValue(forKey: key) else { return false }
        h.resume(r); return true
    }

    func login(_ c: Contact, password: String) async {
        guard let client else { return }
        admin[c.id, default: AdminState()].busy = true
        defer { admin[c.id]?.busy = false }
        do {
            let sent = try await client.sendLogin(to: c.publicKey, password: password)
            let wait = Duration.milliseconds(Int(Double(sent.suggestedTimeoutMillis) * 1.25) + 500)
            if case .pushLoginResult(let r)? = await awaitPush("login:\(prefixHex(c))", timeout: wait) {
                admin[c.id]?.loggedIn = r.success
                admin[c.id]?.isAdmin = r.isAdmin
                admin[c.id]?.lastLoginFailed = !r.success
            } else {
                admin[c.id]?.lastLoginFailed = true
                lastError = "No login reply from \(c.name)"
            }
        } catch { lastError = "\(error)"; admin[c.id]?.lastLoginFailed = true }
    }

    func logout(_ c: Contact) async {
        guard let client else { return }
        try? await client.sendLogout(to: c.publicKey)
        admin[c.id]?.loggedIn = false
        admin[c.id]?.isAdmin = false
    }

    func requestStatus(_ c: Contact) async {
        guard let client else { return }
        admin[c.id, default: AdminState()].busy = true
        defer { admin[c.id]?.busy = false }
        do {
            let sent = try await client.sendStatusRequest(to: c.publicKey)
            let wait = Duration.milliseconds(Int(Double(sent.suggestedTimeoutMillis) * 1.25) + 500)
            if case .pushStatusResponse(let st)? = await awaitPush("status:\(prefixHex(c))", timeout: wait) {
                admin[c.id]?.status = st
                admin[c.id]?.statusDate = .now
            } else { lastError = "No status reply from \(c.name)" }
        } catch { lastError = "\(error)" }
    }

    /// Remote CLI: the reply arrives later as a text message with textType 1 and is routed to the console.
    func sendCommand(_ c: Contact, _ command: String) async {
        guard let client else { return }
        let line = AdminState.ConsoleLine(date: .now, outgoing: true, text: command)
        admin[c.id, default: AdminState()].console.append(line)
        do { _ = try await client.sendRemoteCommand(to: c.publicKey, command: command) }
        catch { lastError = "\(error)"; admin[c.id]?.console.append(.init(date: .now, outgoing: false, text: "send failed: \(error)")) }
    }

    // MARK: - Diagnostics

    struct PacketLogEntry: Identifiable, Equatable {
        enum Kind: String { case raw = "RAW", log = "LOG" }
        let id = UUID()
        let date: Date
        let kind: Kind
        let snr: Double?
        let rssi: Int8?
        let payload: [UInt8]
    }
    private(set) var packetLog: [PacketLogEntry] = []
    var packetLogEnabled = true
    private(set) var pathResults: [String: PathDiscoveryResponse] = [:]      // contact id → last result
    private(set) var traceResults: [String: TraceResponse] = [:]
    private var traceTags: [UInt32: String] = [:]

    func clearPacketLog() { packetLog.removeAll() }

    /// Ask the mesh for the current out/in path to a contact. Reply comes as a push.
    func discoverPath(_ c: Contact) async {
        guard let client else { return }
        do {
            let sent = try await client.sendPathDiscovery(to: c.publicKey)
            let wait = Duration.milliseconds(Int(Double(sent.suggestedTimeoutMillis) * 1.25) + 500)
            if case .pushPathDiscoveryResponse(let r)? = await awaitPush("path:\(prefixHex(c))", timeout: wait) {
                pathResults[c.id] = r
                await refreshContacts()
            } else { lastError = "No path discovery reply from \(c.name)" }
        } catch { lastError = "\(error)" }
    }

    /// Trace along the contact's learned path (or direct); each hop reports SNR.
    func trace(_ c: Contact) async {
        guard let client else { return }
        let tag = UInt32.random(in: 1...UInt32.max), auth = UInt32.random(in: 1...UInt32.max)
        let flags: UInt8 = UInt8(max(c.outPathHashMode, 0) & 3)
        do {
            let sent = try await client.sendTrace(tag: tag, auth: auth, flags: flags, path: c.outPathLength > 0 ? c.outPath : [])
            traceTags[tag] = c.id
            let wait = Duration.milliseconds(Int(Double(sent.suggestedTimeoutMillis) * 1.25) + 500)
            if case .pushTraceData(let r)? = await awaitPush("trace:\(tag)", timeout: wait) {
                traceResults[c.id] = r
            } else { lastError = "No trace reply from \(c.name)" }
            traceTags[tag] = nil
        } catch { lastError = "\(error)" }
    }

    /// Resolve a hop hash to a contact name if we know one.
    func nameForHop(_ hash: [UInt8]) -> String? {
        contacts.first { $0.publicKey.starts(with: hash) }?.name
    }

    // MARK: - Profiles

    func unlockProfile(passcode: String) -> Bool {
        guard let key = selfInfo?.publicKeyHex, let appLock else { profileLocked = false; return true }
        let ok = appLock.verifyProfilePasscode(key, passcode: passcode)
        if ok { profileLocked = false }
        return ok
    }

    func setProfilePasscode(_ passcode: String?) {
        guard let key = selfInfo?.publicKeyHex else { return }
        appLock?.setProfilePasscode(key, passcode: passcode)
    }

    func removeProfile(_ p: NodeProfile) {
        profiles = ProfileStore.remove(publicKeyHex: p.publicKeyHex)
        appLock?.setProfilePasscode(p.publicKeyHex, passcode: nil)
        if selfInfo?.publicKeyHex == p.publicKeyHex { messages = []; lastRead = [:]; Task { await store?.clear() } }
    }

    // MARK: - Node settings

    private(set) var stats: (core: Stats?, radio: Stats?, packets: Stats?) = (nil, nil, nil)
    private(set) var deviceTime: Date?

    private func reloadSelf() async {
        guard let client else { return }
        selfInfo = try? await client.appStart()
    }

    func setRadio(freqMHz: Double, bwKHz: Double, sf: UInt8, cr: UInt8) async {
        guard let client else { return }
        do { try await client.setRadio(freqMHz: freqMHz, bwKHz: bwKHz, sf: sf, cr: cr); await reloadSelf() }
        catch { lastError = "\(error)" }
    }

    func setTxPower(_ dbm: UInt8) async {
        guard let client else { return }
        do { try await client.setTxPower(dbm); await reloadSelf() } catch { lastError = "\(error)" }
    }

    func setAdvertLocation(lat: Double, lon: Double) async {
        guard let client else { return }
        do { try await client.setAdvertLocation(lat: lat, lon: lon); await reloadSelf() } catch { lastError = "\(error)" }
    }

    /// Advert location policy: 0 = never share, 1 = share in adverts.
    func setOtherParams(manualAddContacts: Bool? = nil, telemetryBase: UInt8? = nil, telemetryLoc: UInt8? = nil,
                        telemetryEnv: UInt8? = nil, advertLocationPolicy: UInt8? = nil, multiAcks: UInt8? = nil) async {
        guard let client, let s = selfInfo else { return }
        do {
            try await client.setOtherParams(manualAddContacts: manualAddContacts ?? s.manualAddContacts,
                                            telemetryBase: telemetryBase ?? s.telemetryModeBase,
                                            telemetryLoc: telemetryLoc ?? s.telemetryModeLoc,
                                            telemetryEnv: telemetryEnv ?? s.telemetryModeEnv,
                                            advertLocationPolicy: advertLocationPolicy ?? s.advertLocationPolicy,
                                            multiAcks: multiAcks ?? s.multiAcks)
            await reloadSelf()
        } catch { lastError = "\(error)" }
    }

    func setDevicePIN(_ pin: UInt32) async {
        guard let client else { return }
        do { try await client.setDevicePIN(pin) } catch { lastError = "\(error)" }
    }

    func refreshDeviceTime() async {
        guard let client else { return }
        deviceTime = (try? await client.deviceTime()).map { Date(timeIntervalSince1970: Double($0)) }
    }

    func syncTime() async {
        guard let client else { return }
        do { try await client.setDeviceTime(UInt32(Date().timeIntervalSince1970)); await refreshDeviceTime() }
        catch { lastError = "\(error)" }
    }

    func refreshStats() async {
        guard let client else { return }
        stats = (try? await client.stats(.core), try? await client.stats(.radio), try? await client.stats(.packets))
    }

    func reboot() async {
        guard let client else { return }
        try? await client.reboot()
        await disconnect()
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
        for c in contacts where c.kind == .chat || c.kind == .room { keys.insert(.contact(publicKeyHex: c.id)) }
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
        case .pushLoginResult(let r):
            let pfx = r.publicKeyPrefix?.hexString ?? ""
            if !deliverPush("login:\(pfx)", push) {
                // Older firmware omits the prefix: resolve any single pending login.
                if let k = awaitingBox.keys.first(where: { $0.hasPrefix("login:") }) { _ = deliverPush(k, push) }
            }
        case .pushStatusResponse(let st):
            _ = deliverPush("status:\(st.publicKeyPrefix.hexString)", push)
        case .pushPathDiscoveryResponse(let r):
            _ = deliverPush("path:\(r.publicKeyPrefix.hexString)", push)
        case .pushTraceData(let r):
            _ = deliverPush("trace:\(r.tag)", push)
        case .pushRawData(let snr, let rssi, let payload):
            if packetLogEnabled { appendLog(.init(date: .now, kind: .raw, snr: snr, rssi: rssi, payload: payload)) }
        case .pushLogData(let payload):
            if packetLogEnabled { appendLog(.init(date: .now, kind: .log, snr: nil, rssi: nil, payload: payload)) }
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
            if m.textType == 1, case .contact(let hex) = key {   // remote CLI reply
                admin[hex, default: AdminState()].console.append(.init(date: .now, outgoing: false, text: m.text))
                continue
            }
            let ts = m.senderTimestamp > 0 ? Date(timeIntervalSince1970: Double(m.senderTimestamp)) : .now
            let chat = ChatMessage(conversation: key, direction: .incoming, text: m.text, timestamp: ts,
                                   status: .delivered, snr: m.snr, pathLength: m.pathLength,
                                   senderPrefixHex: prefixHex, senderName: name)
            var stored = chat
            if let sig = m.signature {   // room-server relay: signature = original poster's key prefix
                stored.signatureHex = sig.hexString
                stored.senderName = contacts.first { $0.publicKey.starts(with: sig) }?.name ?? "\(sig.hexString)…"
            }
            messages.append(stored)
            await store?.append(stored)
        }
    }

    private func appendLog(_ e: PacketLogEntry) {
        packetLog.append(e)
        if packetLog.count > 500 { packetLog.removeFirst(packetLog.count - 500) }
    }

    private func upsert(_ contact: Contact) {
        if let i = contacts.firstIndex(where: { $0.publicKey == contact.publicKey }) {
            contacts[i] = contact
        } else {
            contacts.append(contact)
        }
    }
}


/// Boxes a continuation so it can live in a dictionary and be resumed exactly once.
private final class ContinuationHolder: @unchecked Sendable {
    private var cont: CheckedContinuation<Response?, Never>?
    init(_ c: CheckedContinuation<Response?, Never>) { cont = c }
    func resume(_ r: Response?) { cont?.resume(returning: r); cont = nil }
}
