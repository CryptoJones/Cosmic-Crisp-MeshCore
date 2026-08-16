import XCTest
@testable import CosmicCrisp
import MeshCoreKit

@MainActor
final class DiagnosticsTests: XCTestCase {
    func testPathDiscoveryTraceAndPacketLog() async throws {
        let session = NodeSession()
        await session.connect()
        let bob = try XCTUnwrap(session.contacts.first { $0.name.hasPrefix("Bob") })
        let rpt = try XCTUnwrap(session.contacts.first { $0.kind == .repeater })

        await session.discoverPath(bob)
        let path = try XCTUnwrap(session.pathResults[bob.id])
        XCTAssertEqual(path.outHops, [[rpt.publicKey[0]]])
        XCTAssertEqual(session.nameForHop(path.outHops[0]), rpt.name)

        await session.trace(bob)
        let tr = try XCTUnwrap(session.traceResults[bob.id])
        XCTAssertEqual(tr.hops.count, 1)
        XCTAssertEqual(tr.hops[0].snr, 5.5)
        XCTAssertEqual(tr.finalSNR, 7.5)

        try await Task.sleep(for: .seconds(4))
        XCTAssertTrue(session.packetLog.contains { $0.kind == .raw && $0.rssi == -95 })
        session.clearPacketLog()
        XCTAssertTrue(session.packetLog.isEmpty)
        await session.disconnect()
    }
}
