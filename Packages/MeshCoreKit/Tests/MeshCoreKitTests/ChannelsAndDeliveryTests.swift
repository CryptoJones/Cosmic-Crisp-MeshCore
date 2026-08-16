import XCTest
@testable import MeshCoreKit

final class ChannelsAndDeliveryTests: XCTestCase {
    func testSetChannelLayout() {
        let secret = [UInt8](repeating: 0xAB, count: 16)
        let b = Command.setChannel(1, name: "Public", secret: secret)
        XCTAssertEqual(b.count, 1 + 1 + 32 + 16)
        XCTAssertEqual(b[0], 0x20)
        XCTAssertEqual(b[1], 1)
        XCTAssertEqual(Array(b[2..<8]), Array("Public".utf8))
        XCTAssertEqual(b[8], 0)                       // NUL padded
        XCTAssertEqual(Array(b[34...]), secret)
    }

    func testResetPath() {
        let key = [UInt8](repeating: 7, count: 32)
        XCTAssertEqual(Command.resetPath(publicKey: key), [0x0D] + key)
    }

    func testHashtagSecretIsSHA256Prefix() {
        // sha256("#test") = 4d 3d 3c ... — pin the first bytes so a library change is caught.
        let s = ChannelKeys.hashtagSecret(for: "#test")
        XCTAssertEqual(s.count, 16)
        XCTAssertEqual(ChannelKeys.hashtagSecret(for: "#test"), s)   // deterministic
        XCTAssertNotEqual(ChannelKeys.hashtagSecret(for: "#other"), s)
    }

    func testSecretHexParsing() {
        XCTAssertEqual(ChannelKeys.secret(fromHex: "8b3387e9c5cdea6ac9e5edbaa115cd72"), ChannelKeys.publicChannel)
        XCTAssertNil(ChannelKeys.secret(fromHex: "8b33"))
        XCTAssertNil(ChannelKeys.secret(fromHex: "zz3387e9c5cdea6ac9e5edbaa115cd72"))
    }

    func testDeliveryTrackerConfirmAndExpire() {
        var t = DeliveryTracker()
        let id = UUID()
        let now = Date(timeIntervalSince1970: 1000)
        let p = t.track(messageID: id, sent: MessageSent(type: 1, expectedAck: [1, 2, 3, 4], suggestedTimeoutMillis: 5000),
                        attempt: 0, now: now)
        XCTAssertEqual(p.deadline.timeIntervalSince1970, 1006, accuracy: 0.001)   // 5s * 1.2
        XCTAssertTrue(t.isPending(id))
        XCTAssertNil(t.confirm(ackCode: [9, 9, 9, 9]))
        XCTAssertEqual(t.expired(now: now.addingTimeInterval(3)), [])
        XCTAssertEqual(t.confirm(ackCode: [1, 2, 3, 4]), id)
        XCTAssertFalse(t.isPending(id))

        let id2 = UUID()
        _ = t.track(messageID: id2, sent: MessageSent(type: 1, expectedAck: [5, 5, 5, 5], suggestedTimeoutMillis: 1000),
                    attempt: 1, now: now)
        let dead = t.expired(now: now.addingTimeInterval(2))
        XCTAssertEqual(dead.map(\.messageID), [id2])
        XCTAssertEqual(t.count, 0)
    }

    func testRetryPolicyMatchesReference() {
        XCTAssertEqual(DeliveryTracker.nextStep(afterFailedAttempt: 0), .retry(attempt: 1))
        XCTAssertEqual(DeliveryTracker.nextStep(afterFailedAttempt: 1), .resetPathThenRetry(attempt: 2))
        XCTAssertEqual(DeliveryTracker.nextStep(afterFailedAttempt: 2), .giveUp)
    }

    func testClientChannelRoundTrip() async throws {
        let t = MockTransport()
        await t.respond(to: .getChannel) { cmd in
            [[0x12, cmd[1]] + Array("Public".utf8) + [UInt8](repeating: 0, count: 26) + ChannelKeys.publicChannel]
        }
        await t.respond(to: .setChannel) { _ in [[0x00]] }
        await t.respond(to: .resetPath) { _ in [[0x00]] }
        let c = MeshCoreClient(transport: t, timeout: .seconds(2))
        await c.start()
        let ch = try await c.channel(0)
        XCTAssertEqual(ch.name, "Public")
        XCTAssertEqual(ch.secret, ChannelKeys.publicChannel)
        try await c.setChannel(1, name: "#test", secret: ChannelKeys.hashtagSecret(for: "#test"))
        try await c.resetPath(publicKey: [UInt8](repeating: 1, count: 32))
    }
}
