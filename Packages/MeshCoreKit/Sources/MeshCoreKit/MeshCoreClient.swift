import Foundation

/// High-level, request/response client over any `MeshCoreTransport`.
///
/// One command is in flight at a time (the node itself is single-threaded about
/// this). Unsolicited pushes are delivered on `pushes`, regardless of whether a
/// request is pending — mirroring the subscribe-before-send pattern the
/// reference apps use, so a fast reply can't slip past the awaiting caller.
public actor MeshCoreClient {
    public let transport: any MeshCoreTransport
    /// Unsolicited node→host events (adverts, ACKs, "messages waiting", …).
    public nonisolated let pushes: AsyncStream<Response>
    private let pushContinuation: AsyncStream<Response>.Continuation

    private var decoder = FrameDecoder()
    private var pending: CheckedContinuation<Response, Error>?
    private var pendingCollector: (([Response]) -> Void)?
    private var collected: [Response] = []
    private var readTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private let defaultTimeout: Duration

    public init(transport: any MeshCoreTransport, timeout: Duration = .seconds(5)) {
        self.transport = transport
        self.defaultTimeout = timeout
        var c: AsyncStream<Response>.Continuation!
        pushes = AsyncStream { c = $0 }
        pushContinuation = c
    }

    /// Start pumping the transport. Call once.
    public func start() {
        guard readTask == nil else { return }
        readTask = Task { [weak self] in
            guard let self else { return }
            for await chunk in transport.incoming {
                await self.ingest(chunk)
            }
            await self.finish()
        }
    }

    public func stop() async {
        readTask?.cancel()
        readTask = nil
        await transport.close()
        finish()
    }

    // MARK: - Requests

    /// Send a command and await the single reply payload.
    public func request(_ command: [UInt8], timeout: Duration? = nil) async throws -> Response {
        precondition(pending == nil && pendingCollector == nil, "one request at a time")
        let limit = timeout ?? defaultTimeout
        return try await withCheckedThrowingContinuation { cont in
            pending = cont
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                await self?.fail(with: ProtocolError.timeout)
            }
            Task { [transport] in
                do { try await transport.send(Framing.encode(command)) }
                catch { self.fail(with: error) }
            }
        }
    }

    /// Handshake. Returns the node's `SelfInfo`.
    public func appStart(appName: String = "CosmicCrisp") async throws -> SelfInfo {
        switch try await request(Command.appStart(appName: appName)) {
        case .selfInfo(let s): return s
        case let other: throw ProtocolError.unexpected(other)
        }
    }

    public func deviceInfo() async throws -> DeviceInfo {
        switch try await request(Command.deviceQuery()) {
        case .deviceInfo(let d): return d
        case let other: throw ProtocolError.unexpected(other)
        }
    }

    public func battery() async throws -> BatteryInfo {
        switch try await request(Command.getBatteryVoltage()) {
        case .battery(let b): return b
        case let other: throw ProtocolError.unexpected(other)
        }
    }

    public func customVars() async throws -> [String: String] {
        switch try await request(Command.getCustomVars()) {
        case .customVars(let v): return v
        case let other: throw ProtocolError.unexpected(other)
        }
    }

    public func setCustomVar(_ key: String, _ value: String) async throws {
        try expectOK(await request(Command.setCustomVar(key, value)))
    }

    /// GPS is exposed by GPS-equipped boards (Wio Tracker L1 etc.) as custom var `gps`.
    public func setGPS(enabled: Bool) async throws {
        try await setCustomVar("gps", enabled ? "1" : "0")
    }

    public func setName(_ name: String) async throws {
        try expectOK(await request(Command.setAdvertName(name)))
    }

    public func sendAdvert(flood: Bool = false) async throws {
        try expectOK(await request(Command.sendSelfAdvert(flood: flood)))
    }

    /// Full contact list. The node streams `contactsStart`, N × `contact`, `contactsEnd`.
    public func contacts(since lastMod: UInt32 = 0) async throws -> [Contact] {
        precondition(pending == nil && pendingCollector == nil, "one request at a time")
        let limit = defaultTimeout
        let responses: [Response] = await withCheckedContinuation { cont in
            collected = []
            pendingCollector = { cont.resume(returning: $0) }
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                await self?.failCollector()
            }
            Task { [transport] in
                do { try await transport.send(Framing.encode(Command.getContacts(since: lastMod))) }
                catch { self.failCollector() }
            }
        }
        return responses.compactMap { if case .contact(let c) = $0 { return c } else { return nil } }
    }

    public func sendMessage(to publicKey: [UInt8], text: String, timestamp: UInt32? = nil) async throws -> MessageSent {
        let ts = timestamp ?? UInt32(Date().timeIntervalSince1970)
        switch try await request(Command.sendTextMessage(to: publicKey, text: text, timestamp: ts)) {
        case .messageSent(let m): return m
        case let other: throw ProtocolError.unexpected(other)
        }
    }

    public func sendChannelMessage(channel: UInt8, text: String, timestamp: UInt32? = nil) async throws {
        let ts = timestamp ?? UInt32(Date().timeIntervalSince1970)
        try expectOK(await request(Command.sendChannelTextMessage(channel: channel, text: text, timestamp: ts)))
    }

    /// Drain the node's inbound queue. Returns nil when there's nothing waiting.
    public func nextMessage() async throws -> ReceivedMessage? {
        switch try await request(Command.syncNextMessage()) {
        case .message(let m): return m
        case .noMoreMessages: return nil
        case let other: throw ProtocolError.unexpected(other)
        }
    }

    // MARK: - Internals

    private func ingest(_ chunk: [UInt8]) {
        for payload in decoder.feed(chunk) {
            let response = ResponseParser.parse(payload)
            if response.isPush {
                pushContinuation.yield(response)
                continue
            }
            if pendingCollector != nil {
                collected.append(response)
                if case .contactsEnd = response { completeCollector() }
                else if case .error = response { completeCollector() }
                continue
            }
            if let p = pending {
                pending = nil
                timeoutTask?.cancel(); timeoutTask = nil
                p.resume(returning: response)
            } else {
                // Late/unsolicited non-push reply — surface it rather than drop it.
                pushContinuation.yield(response)
            }
        }
    }

    private func fail(with error: Error) {
        timeoutTask?.cancel(); timeoutTask = nil
        if let p = pending { pending = nil; p.resume(throwing: error) }
    }

    private func completeCollector() {
        timeoutTask?.cancel(); timeoutTask = nil
        if let c = pendingCollector { pendingCollector = nil; c(collected) }
    }

    private func failCollector() { completeCollector() }

    private func finish() {
        pushContinuation.finish()
        fail(with: TransportError.notConnected)
        completeCollector()
    }

    private func expectOK(_ r: Response) throws {
        if case .ok = r { return }
        throw ProtocolError.unexpected(r)
    }
}

public enum ProtocolError: Error, Sendable {
    case unexpected(Response)
    case timeout
}
