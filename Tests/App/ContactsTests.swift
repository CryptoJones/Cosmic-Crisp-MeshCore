import XCTest
@testable import CosmicCrisp
import MeshCoreKit

@MainActor
final class ContactsTests: XCTestCase {
    func testGeo() {
        // Hastings, NE → Grand Island, NE: ~35 km, roughly north.
        let d = Geo.distance(from: (40.586, -98.389), to: (40.925, -98.342))
        XCTAssertEqual(d, 37_900, accuracy: 1000)
        let b = Geo.bearing(from: (40.586, -98.389), to: (40.925, -98.342))
        XCTAssertEqual(Geo.compass(b), "N")
        XCTAssertFalse(Geo.hasPosition(0, 0))
    }

    func testQRAndHex() {
        XCTAssertNotNil(QRCode.image(for: "meshcore://abcd"))
        XCTAssertEqual(ChannelKeys.bytes(fromHex: "cafe"), [0xCA, 0xFE])
        XCTAssertNil(ChannelKeys.bytes(fromHex: "caf"))
    }

    func testShareImportDeleteAgainstDemoNode() async throws {
        let session = NodeSession()
        await session.connect()
        let bob = try XCTUnwrap(session.contacts.first { $0.name.hasPrefix("Bob") })
        let maybeURI = await session.shareURI(for: bob)
        let uri = try XCTUnwrap(maybeURI)
        XCTAssertTrue(uri.hasPrefix("meshcore://"))
        let ok = await session.importContact(uri: uri)
        XCTAssertTrue(ok)
        let bad = await session.importContact(uri: "https://example.com")
        XCTAssertFalse(bad)
        await session.resetPath(bob)
        await session.removeContact(bob)
        XCTAssertNil(session.contact(forHex: bob.id))
        XCTAssertNotNil(session.selfPosition)
        await session.disconnect()
    }
}
