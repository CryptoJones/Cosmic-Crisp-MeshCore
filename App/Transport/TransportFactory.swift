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

    /// User-configured TCP endpoint (Settings), used when no launch arg/env is present.
    static var savedTCP: TCPTarget? {
        get {
            guard let host = UserDefaults.standard.string(forKey: "transport.tcp.host"), !host.isEmpty else { return nil }
            let port = UserDefaults.standard.integer(forKey: "transport.tcp.port")
            return TCPTarget(host: host, port: UInt16(port == 0 ? 5000 : port))
        }
        set {
            UserDefaults.standard.set(newValue?.host ?? "", forKey: "transport.tcp.host")
            UserDefaults.standard.set(Int(newValue?.port ?? 5000), forKey: "transport.tcp.port")
        }
    }

    static var effectiveTCP: TCPTarget? { tcpTarget ?? savedTCP }

    static var description: String {
        if let t = effectiveTCP { return "TCP \(t.host):\(t.port)" }
        #if targetEnvironment(simulator)
        return "Simulator (mock node)"
        #elseif NO_USB_DRIVER
        return "No radio configured"
        #else
        return "USB (DriverKit)"
        #endif
    }

    static func make() async throws -> any MeshCoreTransport {
        if let t = effectiveTCP { return try await TCPTransport.connect(host: t.host, port: t.port) }
        #if targetEnvironment(simulator)
        return await DemoNode.makeTransport()
        #elseif NO_USB_DRIVER
        throw TransportError.notConnected
        #else
        return try await USBTransport.open()
        #endif
    }
}
