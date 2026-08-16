import Foundation
import MeshCoreKit

#if !targetEnvironment(simulator)
// IOKit comes in through App/CosmicCrisp-Bridging-Header.h (no Swift module on iOS).

/// App side of the DriverKit bridge.
///
/// - Opens an `IOUserClient` connection to the embedded `MeshCoreUSB` dext. (On iPadOS
///   there is no in-app activation API — `OSSystemExtensionRequest` is macOS-only; the
///   system installs the embedded driver with the app and the user enables it in Settings.)
/// - Registers an async completion (`startRead`); the dext fires it once per USB
///   bulk-IN completion with the bytes packed into the async scalars
///   (`Wire.maxChunk` bytes max, see `Driver/MeshCoreUSBShared.h`).
/// - Writes go straight through `IOConnectCallStructMethod(write)`.
final class USBTransport: MeshCoreTransport, @unchecked Sendable {
    // Selectors come from Driver/MeshCoreUSBShared.h via the bridging header.
    enum Selector {
        static let write = UInt32(kMeshCoreUSBSelWrite)
        static let startRead = UInt32(kMeshCoreUSBSelStartRead)
        static let stopRead = UInt32(kMeshCoreUSBSelStopRead)
    }

    static let dextBundleID = "net.thenetwerk.cosmiccrisp.MeshCoreUSB"
    static let serviceName = "MeshCoreUSBDriver"

    let incoming: AsyncStream<[UInt8]>
    private let continuation: AsyncStream<[UInt8]>.Continuation
    private var connection: io_connect_t = IO_OBJECT_NULL
    private var notifyPort: IONotificationPortRef?
    private let queue = DispatchQueue(label: "net.thenetwerk.cosmiccrisp.usb")
    private let lock = NSLock()
    private var closed = false

    private init() {
        var c: AsyncStream<[UInt8]>.Continuation!
        incoming = AsyncStream { c = $0 }
        continuation = c
    }

    deinit { teardown() }

    static func open() async throws -> USBTransport {
        let t = USBTransport()
        try t.connectToDext()
        try t.startReading()
        return t
    }

    // MARK: - Connection

    private func connectToDext() throws {
        guard let matching = IOServiceNameMatching(Self.serviceName) else { throw USBError.matchingFailed }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { throw USBError.driverNotFound }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connection)
        guard kr == KERN_SUCCESS else { throw USBError.kern("IOServiceOpen", kr) }
    }

    private func startReading() throws {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { throw USBError.notifyPortFailed }
        IONotificationPortSetDispatchQueue(port, queue)
        notifyPort = port

        // refcon → self (unretained; teardown() clears the port before self dies).
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var asyncRef = [io_user_reference_t](repeating: 0, count: Int(kOSAsyncRef64Count))
        asyncRef[Int(kIOAsyncCalloutFuncIndex)] = io_user_reference_t(UInt(bitPattern: unsafeBitCast(usbReadCallback, to: Int.self)))
        asyncRef[Int(kIOAsyncCalloutRefconIndex)] = io_user_reference_t(UInt(bitPattern: refcon))

        let kr = IOConnectCallAsyncScalarMethod(connection, Selector.startRead,
                                                IONotificationPortGetMachPort(port),
                                                &asyncRef, UInt32(kOSAsyncRef64Count),
                                                nil, 0, nil, nil)
        guard kr == KERN_SUCCESS else { throw USBError.kern("startRead", kr) }
    }

    /// Called on `queue` for each async completion from the dext.
    fileprivate func handleCompletion(result: IOReturn, args: UnsafeMutablePointer<UnsafeMutableRawPointer?>?, count: UInt32) {
        guard result == KERN_SUCCESS else {
            // Driver reported a pipe error or detach; end the stream so the client fails fast.
            teardown()
            return
        }
        guard let args, count >= 1 else { return }
        // Async scalars arrive as an array of pointer-sized words; on 64-bit they ARE the uint64s.
        let words = UnsafeBufferPointer(start: UnsafeRawPointer(args).assumingMemoryBound(to: UInt64.self),
                                        count: Int(count))
        guard let bytes = AsyncScalarCodec.unpack(words), !bytes.isEmpty else { return }
        continuation.yield(bytes)
    }

    // MARK: - MeshCoreTransport

    func send(_ bytes: [UInt8]) async throws {
        let (conn, isClosed) = lock.withLock { (connection, closed) }
        guard !isClosed, conn != IO_OBJECT_NULL else { throw TransportError.notConnected }
        let kr = bytes.withUnsafeBytes { buf in
            IOConnectCallStructMethod(conn, Selector.write, buf.baseAddress, buf.count, nil, nil)
        }
        guard kr == KERN_SUCCESS else { throw TransportError.writeFailed(String(format: "kern 0x%08x", kr)) }
    }

    func close() async { teardown() }

    private func teardown() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        closed = true
        if connection != IO_OBJECT_NULL {
            _ = IOConnectCallScalarMethod(connection, Selector.stopRead, nil, 0, nil, nil)
            IOServiceClose(connection)
            connection = IO_OBJECT_NULL
        }
        if let port = notifyPort { IONotificationPortDestroy(port); notifyPort = nil }
        continuation.finish()
    }
}

/// C-convention trampoline for IOKit async completions.
private let usbReadCallback: IOAsyncCallback = { refcon, result, args, numArgs in
    guard let refcon else { return }
    let transport = Unmanaged<USBTransport>.fromOpaque(refcon).takeUnretainedValue()
    transport.handleCompletion(result: result, args: args, count: numArgs)
}

enum USBError: Error, CustomStringConvertible {
    case matchingFailed
    case driverNotFound
    case notifyPortFailed
    case kern(String, kern_return_t)

    var description: String {
        switch self {
        case .matchingFailed: "IOServiceNameMatching failed"
        case .driverNotFound: "MeshCoreUSB driver not running — is the node plugged in and the driver enabled in Settings?"
        case .notifyPortFailed: "IONotificationPortCreate failed"
        case .kern(let what, let kr): "\(what) failed (kern 0x\(String(kr, radix: 16)))"
        }
    }
}

#endif
