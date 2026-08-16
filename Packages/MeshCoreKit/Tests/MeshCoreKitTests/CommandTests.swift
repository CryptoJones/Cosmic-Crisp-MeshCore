import XCTest
@testable import MeshCoreKit

final class CommandTests: XCTestCase {
    func testAppStartMatchesReference() {
        // Reference library sends b"\x01\x03      mccli"
        XCTAssertEqual(Command.appStart(appName: "mccli"), [0x01, 0x03] + Array("      mccli".utf8))
    }

    func testDeviceQuery() { XCTAssertEqual(Command.deviceQuery(), [0x16, 0x03]) }

    func testAdvert() {
        XCTAssertEqual(Command.sendSelfAdvert(flood: false), [0x07])
        XCTAssertEqual(Command.sendSelfAdvert(flood: true), [0x07, 0x01])
    }

    func testSetLatLon() {
        let b = Command.setAdvertLatLon(lat: 40.495004, lon: -98.944396)
        XCTAssertEqual(b[0], 0x0E)
        XCTAssertEqual(b.count, 13)
        var r = ByteReader(Array(b.dropFirst()))
        XCTAssertEqual(r.i32(), 40_495_004)
        XCTAssertEqual(r.i32(), -98_944_396)
        XCTAssertEqual(r.u32(), 0)
    }

    func testSetRadioParams() {
        let b = Command.setRadioParams(freqMHz: 910.525, bwKHz: 62.5, sf: 7, cr: 5)
        var r = ByteReader(Array(b.dropFirst()))
        XCTAssertEqual(b[0], 0x0B)
        XCTAssertEqual(r.u32(), 910_525)
        XCTAssertEqual(r.u32(), 62_500)
        XCTAssertEqual(r.u8(), 7)
        XCTAssertEqual(r.u8(), 5)
    }

    func testCustomVar() {
        XCTAssertEqual(Command.setCustomVar("gps", "1"), [0x29] + Array("gps:1".utf8))
    }

    func testTextMessageLayout() {
        let key = [UInt8](repeating: 0x11, count: 32)
        let b = Command.sendTextMessage(to: key, text: "hi", timestamp: 0x0102_0304, attempt: 2)
        XCTAssertEqual(Array(b.prefix(7)), [0x02, 0x00, 0x02, 0x04, 0x03, 0x02, 0x01])
        XCTAssertEqual(Array(b[7..<39]), key)
        XCTAssertEqual(Array(b[39...]), Array("hi".utf8))
    }

    func testChannelMessageLayout() {
        let b = Command.sendChannelTextMessage(channel: 1, text: "yo", timestamp: 1)
        XCTAssertEqual(b, [0x03, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00] + Array("yo".utf8))
    }

    func testGetContactsWithLastMod() {
        XCTAssertEqual(Command.getContacts(), [0x04])
        XCTAssertEqual(Command.getContacts(since: 0x01), [0x04, 0x01, 0x00, 0x00, 0x00])
    }
}
