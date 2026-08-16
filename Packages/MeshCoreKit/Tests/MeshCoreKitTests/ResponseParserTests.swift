import XCTest
@testable import MeshCoreKit

final class ResponseParserTests: XCTestCase {
    /// SELF_INFO built from a real Wio Tracker L1 (v1.17.1) session:
    /// name "CryptoJones", 910.525 MHz, BW 62.5, SF7, CR5, TX 22, at 40.495004,-98.944396.
    static func selfInfoPayload() -> [UInt8] {
        var p: [UInt8] = [0x05, 0x01, 22, 22]
        p += [UInt8](repeating: 0xAA, count: 32)
        p += Int32(40_495_004).leBytes + Int32(-98_944_396).leBytes
        p += [0, 0, 0b00_00_00, 0]                       // multi_acks, loc_policy, telemetry, manual_add
        p += UInt32(910_525).leBytes + UInt32(62_500).leBytes
        p += [7, 5]
        p += Array("CryptoJones".utf8)
        return p
    }

    func testSelfInfo() throws {
        guard case .selfInfo(let s) = ResponseParser.parse(Self.selfInfoPayload()) else { return XCTFail() }
        XCTAssertEqual(s.name, "CryptoJones")
        XCTAssertEqual(s.txPower, 22)
        XCTAssertEqual(s.radioFrequencyMHz, 910.525, accuracy: 1e-6)
        XCTAssertEqual(s.radioBandwidthKHz, 62.5, accuracy: 1e-6)
        XCTAssertEqual(s.spreadingFactor, 7)
        XCTAssertEqual(s.codingRate, 5)
        XCTAssertEqual(s.latitude, 40.495004, accuracy: 1e-6)
        XCTAssertEqual(s.longitude, -98.944396, accuracy: 1e-6)
        XCTAssertEqual(s.publicKeyHex.count, 64)
        XCTAssertFalse(s.manualAddContacts)
    }

    func testOkWithAndWithoutValue() {
        XCTAssertEqual(ResponseParser.parse([0x00]), .ok(value: nil))
        XCTAssertEqual(ResponseParser.parse([0x00, 0x2A, 0, 0, 0]), .ok(value: 42))
    }

    func testError() {
        XCTAssertEqual(ResponseParser.parse([0x01, 0x03]), .error(code: 3))
        XCTAssertEqual(ResponseParser.parse([0x01]), .error(code: nil))
    }

    func testCurrentTimeAndBattery() {
        XCTAssertEqual(ResponseParser.parse([0x09, 0x78, 0x56, 0x34, 0x12]), .currentTime(0x1234_5678))
        XCTAssertEqual(ResponseParser.parse([0x0C, 0x10, 0x0E]),
                       .battery(BatteryInfo(millivolts: 3600, storageUsedKB: nil, storageTotalKB: nil)))
    }

    func testCustomVars() {
        XCTAssertEqual(ResponseParser.parse([0x15] + Array("gps:1,foo:bar".utf8)),
                       .customVars(["gps": "1", "foo": "bar"]))
        XCTAssertEqual(ResponseParser.parse([0x15]), .customVars([:]))
    }

    func testContact() throws {
        var p: [UInt8] = [0x03]
        p += [UInt8](repeating: 0xBB, count: 32)
        p += [1, 0]                                   // type chat, flags
        p += [0x02]                                   // path len 2, hash mode 0
        p += [0xDE, 0xAD] + [UInt8](repeating: 0, count: 62)
        p += Array("Repeater-1".utf8) + [UInt8](repeating: 0, count: 22)
        p += UInt32(1000).leBytes + Int32(1_000_000).leBytes + Int32(-2_000_000).leBytes + UInt32(999).leBytes
        guard case .contact(let c) = ResponseParser.parse(p) else { return XCTFail() }
        XCTAssertEqual(c.name, "Repeater-1")
        XCTAssertEqual(c.kind, .chat)
        XCTAssertEqual(c.outPathLength, 2)
        XCTAssertEqual(c.outPath, [0xDE, 0xAD])
        XCTAssertEqual(c.latitude, 1.0, accuracy: 1e-9)
        XCTAssertEqual(c.longitude, -2.0, accuracy: 1e-9)
        XCTAssertEqual(c.lastModified, 999)
    }

    func testFloodContactPath() throws {
        var p: [UInt8] = [0x03] + [UInt8](repeating: 0, count: 32) + [1, 0, 0xFF]
        p += [UInt8](repeating: 0, count: 64 + 32 + 16)
        guard case .contact(let c) = ResponseParser.parse(p) else { return XCTFail() }
        XCTAssertEqual(c.outPathLength, -1)
        XCTAssertEqual(c.outPath, [])
    }

    func testContactMessageV3() throws {
        var p: [UInt8] = [0x10, 0xF8, 0, 0]           // SNR -2.0 (‑8/4), reserved
        p += [1, 2, 3, 4, 5, 6]                       // pubkey prefix
        p += [0xFF, 0]                                // direct, plain text
        p += UInt32(1_700_000_000).leBytes
        p += Array("hello mesh".utf8)
        guard case .message(let m) = ResponseParser.parse(p) else { return XCTFail() }
        XCTAssertEqual(m.source, .contact(publicKeyPrefix: [1, 2, 3, 4, 5, 6]))
        XCTAssertEqual(m.snr, -2.0)
        XCTAssertEqual(m.pathLength, -1)
        XCTAssertEqual(m.text, "hello mesh")
        XCTAssertEqual(m.senderTimestamp, 1_700_000_000)
    }

    func testChannelMessageV3() throws {
        var p: [UInt8] = [0x11, 0x08, 0, 0, 0x00, 0x01, 0x00]
        p += UInt32(5).leBytes + Array("chan hi".utf8)
        guard case .message(let m) = ResponseParser.parse(p) else { return XCTFail() }
        XCTAssertEqual(m.source, .channel(index: 0))
        XCTAssertEqual(m.snr, 2.0)
        XCTAssertEqual(m.pathLength, 1)
        XCTAssertEqual(m.text, "chan hi")
    }

    func testPushes() {
        XCTAssertEqual(ResponseParser.parse([0x83]), .pushMessagesWaiting)
        XCTAssertEqual(ResponseParser.parse([0x82, 1, 2, 3, 4, 0x10, 0, 0, 0]),
                       .pushSendConfirmed(ackCode: [1, 2, 3, 4], roundTripMillis: 16))
        XCTAssertTrue(ResponseParser.parse([0x80] + [UInt8](repeating: 1, count: 32)).isPush)
    }

    func testUnknownCodeIsKeptRaw() {
        XCTAssertEqual(ResponseParser.parse([0x7E, 1, 2]), .unhandled(code: 0x7E, payload: [0x7E, 1, 2]))
    }

    func testTruncatedIsMalformedNotCrash() {
        XCTAssertEqual(ResponseParser.parse([0x05, 1]), .malformed(code: 0x05, payload: [0x05, 1]))
        XCTAssertEqual(ResponseParser.parse([]), .malformed(code: nil, payload: []))
    }
}
