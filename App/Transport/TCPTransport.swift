import Foundation
import Network
import MeshCoreKit

/// Companion protocol over TCP — the same framed byte stream as USB serial.
/// Used for MeshCore WiFi/TCP companion nodes, and by the iPad simulator to
/// reach a USB radio through `tools/serial-bridge.py` on the host Mac.
final class TCPTransport: MeshCoreTransport, @unchecked Sendable {
    let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "net.thenetwerk.cosmiccrisp.tcp")
    private let lock = NSLock()
    private var closed = false

    private init(host: String, port: UInt16) {
        var c: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream { c = $0 }
        continuation = c
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: params)
    }

    static func connect(host: String, port: UInt16, timeout: Duration = .seconds(5)) async throws -> TCPTransport {
        let t = TCPTransport(host: host, port: port)
        try await t.waitReady(timeout: timeout)
        t.receiveLoop()
        return t
    }

    private func waitReady(timeout: Duration) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let done = OnceFlag()
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    if done.trip() { cont.resume() }
                case .failed(let err):
                    if done.trip() { cont.resume(throwing: err) } else { self?.teardown() }
                case .cancelled:
                    if done.trip() { cont.resume(throwing: TransportError.notConnected) } else { self?.teardown() }
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .seconds(Int(timeout.components.seconds))) { [weak self] in
                if done.trip() { self?.connection.cancel(); cont.resume(throwing: TransportError.timeout) }
            }
        }
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.continuation.yield([UInt8](data)) }
            if isComplete || error != nil { self.teardown(); return }
            self.receiveLoop()
        }
    }

    func send(_ bytes: [UInt8]) async throws {
        guard !lock.withLock({ closed }) else { throw TransportError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { err in
                if let err { cont.resume(throwing: TransportError.writeFailed(err.localizedDescription)) }
                else { cont.resume() }
            })
        }
    }

    func close() async { teardown() }

    private func teardown() {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        connection.cancel()
        continuation.finish()
    }
}

/// Thread-safe one-shot latch.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var tripped = false
    func trip() -> Bool { lock.lock(); defer { lock.unlock() }; if tripped { return false }; tripped = true; return true }
}
