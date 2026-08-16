import Foundation
import MeshCoreKit

/// A scripted node for the simulator: one self, a few contacts, and a message
/// that "arrives" shortly after connect.
enum DemoNode {
    static func makeTransport() async -> MockTransport {
        let t = MockTransport()
        let selfKey = [UInt8](repeating: 0xA1, count: 32)
        let bobKey = [UInt8](repeating: 0xB0, count: 32)
        let rptKey = [UInt8](repeating: 0xC0, count: 32)

        await t.respond(to: .appStart) { _ in [selfInfo(name: "Demo Node", key: selfKey)] }
        await t.respond(to: .deviceQuery) { _ in
            var p: [UInt8] = [0x0D, 0x03, 100, 8]
            p += UInt32(0).leBytes
            p += pad("v1.17.1", 12)
            p += pad("Simulator", 40)
            p += pad("demo", 20)
            return [p]
        }
        await t.respond(to: .getBatteryVoltage) { _ in [[0x0C] + UInt16(4012).leBytes] }
        await t.respond(to: .getCustomVars) { _ in [[0x15] + Array("gps:0".utf8)] }
        await t.respond(to: .setCustomVar) { _ in [[0x00]] }
        await t.respond(to: .setAdvertName) { _ in [[0x00]] }
        await t.respond(to: .sendSelfAdvert) { _ in [[0x00]] }
        await t.respond(to: .sendChannelTextMessage) { _ in [[0x00]] }
        await t.respond(to: .sendTextMessage) { _ in
            var p: [UInt8] = [0x06, 0x01, 1, 2, 3, 4]
            p += UInt32(3000).leBytes
            return [p]
        }
        await t.respond(to: .getContacts) { _ in
            let start: [UInt8] = [0x02] + UInt32(2).leBytes
            let end: [UInt8] = [0x04] + UInt32(1).leBytes
            return [start,
                    contact(name: "Bob (chat)", key: bobKey, type: 1, lat: 40.5, lon: -98.9),
                    contact(name: "Ridge Repeater", key: rptKey, type: 2, lat: 40.6, lon: -98.8),
                    end]
        }
        let queue = MessageQueue()
        await t.respond(to: .syncNextMessage) { _ in
            if let m = queue.pop() { return [m] }
            return [[0x0A]]
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            var msg: [UInt8] = [0x10, 0x14, 0, 0]
            msg += Array(bobKey.prefix(6))
            msg += [0xFF, 0]
            msg += UInt32(Date().timeIntervalSince1970).leBytes
            msg += Array("hey from the mesh 👋".utf8)
            queue.push(msg)
            await t.push([0x83])
        }
        return t
    }

    private static func pad(_ s: String, _ n: Int) -> [UInt8] {
        let b = Array(s.utf8.prefix(n)); return b + [UInt8](repeating: 0, count: n - b.count)
    }

    private static func selfInfo(name: String, key: [UInt8]) -> [UInt8] {
        var p: [UInt8] = [0x05, 0x01, 22, 22]
        p += key
        p += Int32(40_495_004).leBytes
        p += Int32(-98_944_396).leBytes
        p += [0, 0, 0, 0]
        p += UInt32(910_525).leBytes
        p += UInt32(62_500).leBytes
        p += [7, 5]
        p += Array(name.utf8)
        return p
    }

    private static func contact(name: String, key: [UInt8], type: UInt8, lat: Double, lon: Double) -> [UInt8] {
        var p: [UInt8] = [0x03]
        p += key
        p += [type, 0, 0xFF]
        p += [UInt8](repeating: 0, count: 64)
        p += pad(name, 32)
        p += UInt32(Date().timeIntervalSince1970).leBytes
        p += Int32(lat * 1e6).leBytes
        p += Int32(lon * 1e6).leBytes
        p += UInt32(1).leBytes
        return p
    }
}

private final class MessageQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[UInt8]] = []
    func push(_ m: [UInt8]) { lock.lock(); items.append(m); lock.unlock() }
    func pop() -> [UInt8]? { lock.lock(); defer { lock.unlock() }; return items.isEmpty ? nil : items.removeFirst() }
}
