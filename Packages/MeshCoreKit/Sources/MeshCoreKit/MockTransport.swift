import Foundation

/// In-memory transport that plays a scripted node. Feed it responder closures
/// keyed by command opcode; anything unscripted answers `ERROR`.
///
/// Used by unit tests and by the app when running in the iOS Simulator (which
/// has no USB). It speaks *framed* bytes on both sides so it exercises the real
/// codec path.
public actor MockTransport: MeshCoreTransport {
    public typealias Responder = @Sendable ([UInt8]) -> [[UInt8]]   // command payload → response payloads

    public nonisolated let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var responders: [UInt8: Responder] = [:]
    private var decoder = FrameDecoder(marker: Framing.hostToNode)
    public private(set) var sentCommands: [[UInt8]] = []

    public init() {
        var c: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream { c = $0 }
        continuation = c
    }

    public func respond(to code: Command.Code, _ responder: @escaping Responder) {
        responders[code.rawValue] = responder
    }

    /// Emit an unsolicited (push) payload as the node would.
    public func push(_ payload: [UInt8]) {
        emit(payload)
    }

    /// Emit raw bytes without framing (to test decoder resync against junk).
    public func pushRaw(_ bytes: [UInt8]) {
        continuation.yield(bytes)
    }

    public func send(_ bytes: [UInt8]) async throws {
        for cmd in decoder.feed(bytes) {
            sentCommands.append(cmd)
            guard let op = cmd.first else { continue }
            if let responder = responders[op] {
                for r in responder(cmd) { emit(r) }
            } else {
                emit([ResponseCode.error.rawValue, 0x01])
            }
        }
    }

    public func close() async { continuation.finish() }

    private func emit(_ payload: [UInt8]) {
        continuation.yield([Framing.nodeToHost] + UInt16(payload.count).leBytes + payload)
    }
}
