import XCTest
@testable import CosmicCrisp
import MeshCoreKit

/// Runs only against a real node reachable over TCP (e.g. `tools/serial-bridge.py`).
/// Enable with: `TEST_RUNNER_MESHCORE_TCP=127.0.0.1:5000 xcodebuild … test`
/// (xcodebuild forwards `TEST_RUNNER_*` env vars to the test host).
@MainActor
final class LiveRadioTests: XCTestCase {
    override func setUp() async throws {
        try XCTSkipIf(TransportFactory.tcpTarget == nil, "MESHCORE_TCP not set — skipping live radio test")
    }

    func testConnectListChannelsAndBroadcast() async throws {
        let session = NodeSession()
        await session.connect()
        XCTAssertEqual(session.status, .connected, "\(session.lastError ?? "")")
        let info = try XCTUnwrap(session.selfInfo)
        print("LIVE: node \(info.name) fw \(session.deviceInfo?.version ?? "?") channels \(session.configuredChannels.map(\.name))")
        XCTAssertFalse(session.channels.isEmpty)
        XCTAssertTrue(session.configuredChannels.contains { $0.secretHex == ChannelKeys.publicChannel.hexString },
                      "expected the Public channel to be configured")

        // Real LoRa broadcast on the public channel.
        let text = "Cosmic Crisp live test \(Int(Date().timeIntervalSince1970) % 100000)"
        session.send(text: text, in: .channel(index: 0))
        try await Task.sleep(for: .seconds(2))
        let m = try XCTUnwrap(session.messages(in: .channel(index: 0)).last { $0.text == text })
        XCTAssertEqual(m.status, .sent, "\(session.lastError ?? "")")
        await session.disconnect()
    }

    func testTelemetryStatsAndCard() async throws {
        let target = try XCTUnwrap(TransportFactory.tcpTarget)
        let t = try await TCPTransport.connect(host: target.host, port: target.port)
        let c = MeshCoreClient(transport: t)
        await c.start()
        let me = try await c.appStart()
        let tele = try await c.selfTelemetry()
        print("LIVE telemetry:", tele.records)
        XCTAssertTrue(tele.records.contains { if case .voltage = $0.value { true } else { false } })
        let core = try await c.stats(.core)
        let radio = try await c.stats(.radio)
        let packets = try await c.stats(.packets)
        print("LIVE stats:", core, radio, packets)
        let card = try await c.exportContact()
        print("LIVE card: meshcore://\(card.hexString)")
        XCTAssertGreaterThan(card.count, 32)
        let time = try await c.deviceTime()
        print("LIVE time:", time, "node:", me.name)
        XCTAssertGreaterThan(time, 1_700_000_000)
        await c.stop()
    }
}
