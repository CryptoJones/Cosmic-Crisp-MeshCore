import Foundation

/// A byte pipe to a MeshCore node. Implementations: the DriverKit USB bridge on
/// device, `MockTransport` in tests and the simulator, and (later) TCP.
///
/// Transports deal in raw bytes; framing is applied by `MeshCoreClient`.
public protocol MeshCoreTransport: Sendable {
    /// Bytes arriving from the node, in arbitrary chunk sizes.
    var incoming: AsyncStream<[UInt8]> { get }
    func send(_ bytes: [UInt8]) async throws
    func close() async
}

public enum TransportError: Error, Sendable, Equatable {
    case notConnected
    case writeFailed(String)
    case timeout
}
