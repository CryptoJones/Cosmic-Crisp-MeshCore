import XCTest
@testable import CosmicCrisp
import MeshCoreKit

@MainActor
final class NodeSessionTests: XCTestCase {
    func testConnectsToDemoNode() async {
        let session = NodeSession()
        await session.connect()
        XCTAssertEqual(session.status, .connected)
        XCTAssertEqual(session.selfInfo?.name, "Demo Node")
        XCTAssertEqual(session.contacts.count, 2)
        // Demo Bob routes via the repeater: 1 hop whose hash matches the repeater's key prefix.
        let bob = session.contacts.first { $0.name.hasPrefix("Bob") }!
        let rpt = session.contacts.first { $0.kind == .repeater }!
        XCTAssertEqual(bob.outPathLength, 1)
        XCTAssertTrue(rpt.publicKey.starts(with: bob.outPath))
    }

    func testNodeSettingsAgainstDemoNode() async {
        let session = NodeSession()
        await session.connect()
        await session.setRadio(freqMHz: 906.875, bwKHz: 250, sf: 10, cr: 5)
        await session.setTxPower(17)
        await session.setAdvertLocation(lat: 41.25, lon: -95.93)
        await session.setOtherParams(manualAddContacts: true, telemetryLoc: 2)
        await session.setDevicePIN(123456)
        await session.syncTime()
        XCTAssertNotNil(session.deviceTime)
        await session.refreshStats()
        if case .core(let mv, _, _, _)? = session.stats.core { XCTAssertEqual(mv, 4012) } else { XCTFail("no core stats") }
        if case .radio(let nf, _, _, _, _)? = session.stats.radio { XCTAssertEqual(nf, -108) } else { XCTFail("no radio stats") }
        XCTAssertNil(session.lastError)
        XCTAssertEqual(session.selfTelemetry?.records.count, 3)
        await session.disconnect()
    }
}
