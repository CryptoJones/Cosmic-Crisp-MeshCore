import XCTest
@testable import MeshCoreKit

final class ExtendedProtocolTests: XCTestCase {
    let key = [UInt8](repeating: 0x42, count: 32)

    func testContactCommands() {
        XCTAssertEqual(Command.exportContact(), [0x11])
        XCTAssertEqual(Command.exportContact(publicKey: key), [0x11] + key)
        XCTAssertEqual(Command.importContact(card: [1, 2, 3]), [0x12, 1, 2, 3])
        XCTAssertEqual(Command.shareContact(publicKey: key), [0x10] + key)
        XCTAssertEqual(Command.removeContact(publicKey: key), [0x0F] + key)
        XCTAssertEqual(Command.getAdvertPath(publicKey: key), [0x2A, 0x00] + key)
    }

    func testAddOrUpdateContactLayout() {
        let c = Contact(publicKey: key, type: 1, flags: 0, outPathLength: 2, outPathHashMode: 0, outPath: [0xAA, 0xBB],
                        name: "Bob", lastAdvert: 1234, latitude: 1.5, longitude: -2.5, lastModified: 0)
        let b = Command.addOrUpdateContact(c)
        XCTAssertEqual(b.count, 1 + 32 + 1 + 1 + 1 + 64 + 32 + 4 + 4 + 4)
        XCTAssertEqual(b[0], 0x09)
        XCTAssertEqual(b[35], 2)                                 // path len, hash mode 0
        XCTAssertEqual(Array(b[36..<38]), [0xAA, 0xBB])
        XCTAssertEqual(Array(b[100..<103]), Array("Bob".utf8))
        var r = ByteReader(Array(b[132...]))
        XCTAssertEqual(r.u32(), 1234)
        XCTAssertEqual(r.i32(), 1_500_000)
        XCTAssertEqual(r.i32(), -2_500_000)

        var flood = c; flood.outPathLength = -1; flood.outPath = []
        XCTAssertEqual(Command.addOrUpdateContact(flood)[35], 0xFF)
    }

    func testRemoteRequestCommands() {
        XCTAssertEqual(Command.sendLogin(to: key, password: "pw"), [0x1A] + key + Array("pw".utf8))
        XCTAssertEqual(Command.sendLogout(to: key), [0x1D] + key)
        XCTAssertEqual(Command.sendStatusRequest(to: key), [0x1B] + key)
        XCTAssertEqual(Command.sendRemoteCommand(to: key, command: "ver", timestamp: 1),
                       [0x02, 0x01, 0x00, 1, 0, 0, 0] + key + Array("ver".utf8))
        XCTAssertEqual(Command.sendTelemetryRequest(to: key), [0x27, 0, 0, 0] + key)
        XCTAssertEqual(Command.getSelfTelemetry(), [0x27, 0, 0, 0])
        XCTAssertEqual(Command.sendPathDiscovery(to: key), [0x34, 0x00] + key)
        XCTAssertEqual(Command.sendTrace(tag: 1, auth: 2, flags: 0, path: [0x11, 0x22]),
                       [0x24, 1, 0, 0, 0, 2, 0, 0, 0, 0, 0x11, 0x22])
    }

    func testNodeParamCommands() {
        XCTAssertEqual(Command.setOtherParams(manualAddContacts: true, telemetryBase: 1, telemetryLoc: 2, telemetryEnv: 3,
                                              advertLocationPolicy: 1, multiAcks: 0),
                       [0x26, 1, 0b11_10_01, 1, 0])
        XCTAssertEqual(Command.setDevicePIN(123456), [0x25] + UInt32(123456).leBytes)
        XCTAssertEqual(Command.setTuningParams(rxDelayBase: 5, airtimeFactor: 7), [0x15, 5, 0, 0, 0, 7, 0, 0, 0])
        XCTAssertEqual(Command.getStats(.radio), [0x38, 1])
        XCTAssertEqual(Command.setDeviceTime(0x01020304), [0x06, 4, 3, 2, 1])
        XCTAssertEqual(Command.setRadioTxPower(17), [0x0C, 17])
    }

    func testContactURIAndAdvertPath() {
        XCTAssertEqual(ResponseParser.parse([0x0B, 0xDE, 0xAD]), .contactURI(card: [0xDE, 0xAD]))
        guard case .advertPath(let p) = ResponseParser.parse([0x16] + UInt32(99).leBytes + [0x02, 0xA1, 0xB2, 0, 0]) else { return XCTFail() }
        XCTAssertEqual(p.timestamp, 99); XCTAssertEqual(p.pathLength, 2); XCTAssertEqual(p.path, [0xA1, 0xB2])
    }

    func testStats() {
        XCTAssertEqual(ResponseParser.parse([0x18, 0] + UInt16(4100).leBytes + UInt32(3600).leBytes + UInt16(2).leBytes + [3]),
                       .stats(.core(batteryMillivolts: 4100, uptimeSeconds: 3600, errors: 2, queueLength: 3)))
        XCTAssertEqual(ResponseParser.parse([0x18, 1] + Int16(-110).leBytes + [UInt8(bitPattern: -90), UInt8(bitPattern: 20)] + UInt32(10).leBytes + UInt32(20).leBytes),
                       .stats(.radio(noiseFloor: -110, lastRSSI: -90, lastSNR: 5.0, txAirSeconds: 10, rxAirSeconds: 20)))
        var pk: [UInt8] = [0x18, 2]
        for v in [1, 2, 3, 4, 5, 6] as [UInt32] { pk += v.leBytes }
        XCTAssertEqual(ResponseParser.parse(pk), .stats(.packets(received: 1, sent: 2, floodTx: 3, directTx: 4, floodRx: 5, directRx: 6, receiveErrors: nil)))
    }

    func testStatusResponse() {
        var p: [UInt8] = [0x87, 0x00] + [1, 2, 3, 4, 5, 6]
        p += UInt16(4000).leBytes + UInt16(1).leBytes + Int16(-105).leBytes + Int16(-80).leBytes
        p += UInt32(100).leBytes + UInt32(50).leBytes + UInt32(30).leBytes + UInt32(86400).leBytes
        p += UInt32(10).leBytes + UInt32(40).leBytes + UInt32(60).leBytes + UInt32(40).leBytes
        p += UInt16(0).leBytes + Int16(22).leBytes + UInt16(1).leBytes + UInt16(2).leBytes + UInt32(15).leBytes
        p += UInt32(3).leBytes
        guard case .pushStatusResponse(let s) = ResponseParser.parse(p) else { return XCTFail() }
        XCTAssertEqual(s.publicKeyPrefix, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(s.batteryMillivolts, 4000)
        XCTAssertEqual(s.noiseFloor, -105); XCTAssertEqual(s.lastRSSI, -80)
        XCTAssertEqual(s.uptimeSeconds, 86400)
        XCTAssertEqual(s.lastSNR, 5.5)
        XCTAssertEqual(s.receiveErrors, 3)
    }

    func testTelemetryLPP() {
        // Real capture shape from a Wio Tracker L1: voltage 4.02, temp 35.5, GPS 40.4941/-98.9439/270.5
        var p: [UInt8] = [0x8B, 0x00] + [UInt8](repeating: 0, count: 6)
        p += [1, 116, 0x01, 0x92]                                     // 402 → 4.02 V
        p += [1, 103, 0x01, 0x63]                                     // 355 → 35.5 °C
        p += [1, 136, 6, 45, 205, 240, 231, 1, 0, 105, 170]           // 404941, -989439, 27050 (3-byte BE each)
        guard case .pushTelemetryResponse(let t) = ResponseParser.parse(p) else { return XCTFail() }
        XCTAssertEqual(t.records.count, 3)
        XCTAssertEqual(t.records[0].value, .voltage(4.02))
        XCTAssertEqual(t.records[1].value, .temperature(35.5))
        guard case .location(let lat, let lon, let alt) = t.records[2].value else { return XCTFail() }
        XCTAssertEqual(lat, 40.4941, accuracy: 1e-4)
        XCTAssertEqual(lon, -98.9439, accuracy: 1e-4)
        XCTAssertEqual(alt, 270.5, accuracy: 1e-2)
    }

    func testPathDiscoveryAndTrace() {
        let p: [UInt8] = [0x8D, 0x00, 1, 2, 3, 4, 5, 6, 0x02, 0xAA, 0xBB, 0x41, 0xC1, 0xC2]   // in: len1 hashlen2
        guard case .pushPathDiscoveryResponse(let d) = ResponseParser.parse(p) else { return XCTFail() }
        XCTAssertEqual(d.outHops, [[0xAA], [0xBB]])
        XCTAssertEqual(d.inHops, [[0xC1, 0xC2]])

        var t: [UInt8] = [0x89, 0x00, 2, 0x00] + UInt32(7).leBytes + UInt32(9).leBytes
        t += [0x11, 0x22] + [UInt8(bitPattern: 8), UInt8(bitPattern: -4)] + [UInt8(bitPattern: 20)]
        guard case .pushTraceData(let tr) = ResponseParser.parse(t) else { return XCTFail() }
        XCTAssertEqual(tr.tag, 7); XCTAssertEqual(tr.auth, 9)
        XCTAssertEqual(tr.hops, [.init(hash: [0x11], snr: 2.0), .init(hash: [0x22], snr: -1.0)])
        XCTAssertEqual(tr.finalSNR, 5.0)
    }

    func testLoginResults() {
        XCTAssertEqual(ResponseParser.parse([0x85, 0x01, 1, 2, 3, 4, 5, 6]),
                       .pushLoginResult(LoginResult(success: true, isAdmin: true, permissions: 1, publicKeyPrefix: [1, 2, 3, 4, 5, 6])))
        XCTAssertEqual(ResponseParser.parse([0x86, 0x00, 1, 2, 3, 4, 5, 6]),
                       .pushLoginResult(LoginResult(success: false, isAdmin: false, permissions: nil, publicKeyPrefix: [1, 2, 3, 4, 5, 6])))
    }

    func testRawAndLogAndDeleted() {
        XCTAssertEqual(ResponseParser.parse([0x84, UInt8(bitPattern: 10), UInt8(bitPattern: -70), 0xFF, 0xAB]),
                       .pushRawData(snr: 2.5, rssi: -70, payload: [0xAB]))
        XCTAssertEqual(ResponseParser.parse([0x88, 1, 2]), .pushLogData(payload: [1, 2]))
        XCTAssertEqual(ResponseParser.parse([0x8F] + key), .pushContactDeleted(publicKey: key))
        XCTAssertTrue(ResponseParser.parse([0x8F] + key).isPush)
    }

    func testClientRemoteAndParams() async throws {
        let t = MockTransport()
        await t.respond(to: .exportContact) { _ in [[0x0B, 0xCA, 0xFE]] }
        await t.respond(to: .importContact) { _ in [[0x00]] }
        await t.respond(to: .sendLogin) { _ in [[0x06, 0x01, 1, 1, 1, 1] + UInt32(2000).leBytes] }
        await t.respond(to: .sendTelemetryReq) { cmd in
            cmd.count == 4 ? [[0x8B, 0x00] + [UInt8](repeating: 0, count: 6) + [1, 116, 0x01, 0x92]]
                           : [[0x06, 0x00, 2, 2, 2, 2] + UInt32(1500).leBytes]
        }
        await t.respond(to: .getStats) { _ in [[0x18, 0] + UInt16(3900).leBytes + UInt32(1).leBytes + UInt16(0).leBytes + [0]] }
        await t.respond(to: .setOtherParams) { _ in [[0x00]] }
        await t.respond(to: .getDeviceTime) { _ in [[0x09] + UInt32(1_700_000_000).leBytes] }
        let c = MeshCoreClient(transport: t, timeout: .seconds(2))
        await c.start()
        let card = try await c.exportContact()
        XCTAssertEqual(card, [0xCA, 0xFE])
        try await c.importContact(card: [0xCA, 0xFE])
        let sent = try await c.sendLogin(to: key, password: "x")
        XCTAssertEqual(sent.expectedAck, [1, 1, 1, 1])
        let tele = try await c.selfTelemetry()
        XCTAssertEqual(tele.records.first?.value, .voltage(4.02))
        _ = try await c.sendTelemetryRequest(to: key)
        guard case .core(let mv, _, _, _) = try await c.stats(.core) else { return XCTFail() }
        XCTAssertEqual(mv, 3900)
        try await c.setOtherParams(manualAddContacts: false, telemetryBase: 0, telemetryLoc: 0, telemetryEnv: 0, advertLocationPolicy: 0, multiAcks: 0)
        let time = try await c.deviceTime()
        XCTAssertEqual(time, 1_700_000_000)
    }
}
