import Foundation
import MeshCoreKit

/// Picks the transport for the current environment.
///
/// Order of precedence:
/// 1. `-tcp host:port` launch argument (or `MESHCORE_TCP` env) → `TCPTransport`.
///    Works everywhere; in the simulator it's how we reach a real USB radio via
///    `tools/serial-bridge.py` on the host Mac.
/// 2. Simulator → scripted `MockTransport` demo node.
/// 3. Device → DriverKit `USBTransport`.
enum TransportFactory {
    struct TCPTarget: Equatable { let host: String; let port: UInt16 }

    static var tcpTarget: TCPTarget? {
        let args = ProcessInfo.processInfo.arguments
        var spec: String?
        if let i = args.firstIndex(of: "-tcp"), i + 1 < args.count { spec = args[i + 1] }
        spec = spec ?? ProcessInfo.processInfo.environment["MESHCORE_TCP"]
        guard let spec, let colon = spec.lastIndex(of: ":"),
              let port = UInt16(spec[spec.index(after: colon)...]) else { return nil }
        let host = String(spec[..<colon])
        return TCPTarget(host: host.isEmpty ? "127.0.0.1" : host, port: port)
    }

    static var description: String {
        if let t = tcpTarget { return "TCP \(t.host):\(t.port)" }
        #if targetEnvironment(simulator)
        return "Simulator (mock node)"
        #else
        return "USB (DriverKit)"
        #endif
    }

    static func make() async throws -> any MeshCoreTransport {
        if let t = tcpTarget { return try await TCPTransport.connect(host: t.host, port: t.port) }
        #if targetEnvironment(simulator)
        return await DemoNode.makeTransport()
        #else
        return try await USBTransport.open()
        #endif
    }
}
