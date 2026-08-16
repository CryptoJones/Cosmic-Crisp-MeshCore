import XCTest
@testable import MeshCoreKit

final class ClientTests: XCTestCase {
    func makeNode() async -> (MockTransport, MeshCoreClient) {
        let t = MockTransport()
        await t.respond(to: .appStart) { _ in [ResponseParserTests.selfInfoPayload()] }
        await t.respond(to: .getBatteryVoltage) { _ in [[0x0C, 0x10, 0x0E]] }
        await t.respond(to: .getCustomVars) { _ in [[0x15] + Array("gps:0".utf8)] }
        await t.respond(to: .setCustomVar) { _ in [[0x00]] }
        await t.respond(to: .syncNextMessage) { _ in [[0x0A]] }
        await t.respond(to: .getContacts) { _ in
            var contact: [UInt8] = [0x03] + [UInt8](repeating: 0xCC, count: 32) + [1, 0, 0xFF]
            contact += [UInt8](repeating: 0, count: 64) + Array("Bob".utf8) + [UInt8](repeating: 0, count: 29)
            contact += [UInt8](repeating: 0, count: 16)
            return [[0x02, 1, 0, 0, 0], contact, [0x04, 0, 0, 0, 0]]
        }
        let c = MeshCoreClient(transport: t, timeout: .seconds(2))
        await c.start()
        return (t, c)
    }

    func testHandshake() async throws {
        let (_, c) = await makeNode()
        let info = try await c.appStart()
        XCTAssertEqual(info.name, "CryptoJones")
    }

    func testBatteryAndCustomVars() async throws {
        let (_, c) = await makeNode()
        let battery = try await c.battery()
        XCTAssertEqual(battery.millivolts, 3600)
        let vars = try await c.customVars()
        XCTAssertEqual(vars["gps"], "0")
        try await c.setGPS(enabled: true)
    }

    func testContactsStreamCollected() async throws {
        let (_, c) = await makeNode()
        let contacts = try await c.contacts()
        XCTAssertEqual(contacts.map(\.name), ["Bob"])
    }

    func testNextMessageNilWhenQueueEmpty() async throws {
        let (_, c) = await makeNode()
        let m = try await c.nextMessage()
        XCTAssertNil(m)
    }

    func testPushDeliveredWhileIdle() async throws {
        let (t, c) = await makeNode()
        let expectation = expectation(description: "push")
        let task = Task {
            for await p in c.pushes { if p == .pushMessagesWaiting { expectation.fulfill(); break } }
        }
        await t.push([0x83])
        await fulfillment(of: [expectation], timeout: 2)
        task.cancel()
    }

    func testUnscriptedCommandErrors() async {
        let (_, c) = await makeNode()
        do {
            _ = try await c.setName("x")
            XCTFail("expected error")
        } catch ProtocolError.unexpected(let r) {
            XCTAssertEqual(r, .error(code: 1))
        } catch { XCTFail("\(error)") }
    }

    func testTimeout() async {
        let silent = SilentTransport()
        let c = MeshCoreClient(transport: silent, timeout: .milliseconds(200))
        await c.start()
        do {
            _ = try await c.request([0x14])
            XCTFail("expected timeout")
        } catch ProtocolError.timeout {
        } catch { XCTFail("\(error)") }
    }
}

/// Accepts writes and never answers.
final class SilentTransport: MeshCoreTransport, @unchecked Sendable {
    let incoming: AsyncStream<[UInt8]>
    private let cont: AsyncStream<[UInt8]>.Continuation
    init() { var c: AsyncStream<[UInt8]>.Continuation!; incoming = AsyncStream { c = $0 }; cont = c }
    func send(_ bytes: [UInt8]) async throws {}
    func close() async { cont.finish() }
}
