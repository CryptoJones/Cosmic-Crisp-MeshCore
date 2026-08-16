import XCTest
@testable import CosmicCrisp

@MainActor
final class NodeSessionTests: XCTestCase {
    func testConnectsToDemoNode() async {
        let session = NodeSession()
        await session.connect()
        XCTAssertEqual(session.status, .connected)
        XCTAssertEqual(session.selfInfo?.name, "Demo Node")
        XCTAssertEqual(session.contacts.count, 2)
    }
}
