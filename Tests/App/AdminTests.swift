import XCTest
@testable import CosmicCrisp
import MeshCoreKit

@MainActor
final class AdminTests: XCTestCase {
    func testLoginStatusAndRemoteCLI() async throws {
        let session = NodeSession()
        await session.connect()
        let rpt = try XCTUnwrap(session.contacts.first { $0.kind == .repeater })

        await session.login(rpt, password: "wrong")
        XCTAssertFalse(session.adminState(rpt.id).loggedIn)
        XCTAssertTrue(session.adminState(rpt.id).lastLoginFailed)

        await session.login(rpt, password: "secret")
        XCTAssertTrue(session.adminState(rpt.id).loggedIn)
        XCTAssertTrue(session.adminState(rpt.id).isAdmin)

        await session.requestStatus(rpt)
        let st = try XCTUnwrap(session.adminState(rpt.id).status)
        XCTAssertEqual(st.batteryMillivolts, 4100)
        XCTAssertEqual(st.uptimeSeconds, 864000)
        XCTAssertEqual(st.lastSNR, 7.5)

        await session.sendCommand(rpt, "ver")
        try await Task.sleep(for: .milliseconds(1500))
        let console = session.adminState(rpt.id).console
        XCTAssertEqual(console.count, 2)
        XCTAssertTrue(console.last?.text.contains("repeater v1.17.1") == true)
        // CLI replies must not pollute the chat.
        XCTAssertFalse(session.messages(in: .contact(publicKeyHex: rpt.id)).contains { $0.text.contains("repeater v1.17.1") })

        await session.logout(rpt)
        XCTAssertFalse(session.adminState(rpt.id).loggedIn)
        await session.disconnect()
    }
}
