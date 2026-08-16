import Foundation
import MeshCoreKit

/// Picks the transport for the current environment.
///
/// - Simulator: a scripted `MockTransport` node so the UI is fully exercisable.
/// - Device: the DriverKit USB bridge (`USBTransport`), which needs the
///   `MeshCoreUSB` dext to be installed and approved.
enum TransportFactory {
    static var description: String {
        #if targetEnvironment(simulator)
        "Simulator (mock node)"
        #else
        "USB (DriverKit)"
        #endif
    }

    static func make() async throws -> any MeshCoreTransport {
        #if targetEnvironment(simulator)
        return await DemoNode.makeTransport()
        #else
        return try await USBTransport.open()
        #endif
    }
}
