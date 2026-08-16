import Foundation
import MeshCoreKit

#if !targetEnvironment(simulator)
import IOKit
import SystemExtensions

/// App side of the DriverKit bridge. Opens an `IOUserClient` connection to the
/// `MeshCoreUSB` dext, reads bytes via a shared ring / async external method,
/// and writes via an external method.
///
/// STATUS: skeleton. Method selectors must match `MeshCoreUSBUserClient` in
/// `Driver/MeshCoreUSBDriver.cpp`. Activation of the dext (OSSystemExtensionRequest)
/// is handled here as well because iPadOS requires the app that embeds a dext to
/// request activation once.
final class USBTransport: MeshCoreTransport, @unchecked Sendable {
    enum Selector: UInt32 {
        case write = 0
        case startRead = 1     // async: registers a callback the dext fires per USB IN completion
        case stopRead = 2
    }

    let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var connection: io_connect_t = IO_OBJECT_NULL

    static let dextBundleID = "net.thenetwerk.cosmiccrisp.MeshCoreUSB"

    private init() {
        var c: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream { c = $0 }
        continuation = c
    }

    static func open() async throws -> USBTransport {
        let t = USBTransport()
        try await t.activateDriverIfNeeded()
        try t.connectToDext()
        return t
    }

    private func activateDriverIfNeeded() async throws {
        // Idempotent: the system no-ops if the dext is already active/approved.
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: Self.dextBundleID, queue: .main)
        let delegate = ActivationDelegate()
        request.delegate = delegate
        OSSystemExtensionManager.shared.submitRequest(request)
        try await delegate.wait()
    }

    private func connectToDext() throws {
        let matching = IOServiceNameMatching("MeshCoreUSBDriver")
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw TransportError.notConnected }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else { throw TransportError.notConnected }
        // TODO: IOConnectCallAsyncScalarMethod(startRead) with a notification port
        // whose callback yields to `continuation`.
    }

    func send(_ bytes: [UInt8]) async throws {
        guard connection != IO_OBJECT_NULL else { throw TransportError.notConnected }
        let kr = bytes.withUnsafeBytes { buf in
            IOConnectCallStructMethod(connection, Selector.write.rawValue,
                                      buf.baseAddress, buf.count, nil, nil)
        }
        guard kr == KERN_SUCCESS else { throw TransportError.writeFailed("kern \(kr)") }
    }

    func close() async {
        if connection != IO_OBJECT_NULL { IOServiceClose(connection); connection = IO_OBJECT_NULL }
        continuation.finish()
    }
}

private final class ActivationDelegate: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait() async throws {
        try await withCheckedThrowingContinuation { self.continuation = $0 }
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction { .replace }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        // User must approve in Settings → General → VPN, DNS & Device Management (iPadOS shows a prompt).
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        continuation?.resume(); continuation = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
}
#endif
