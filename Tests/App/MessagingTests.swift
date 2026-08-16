import XCTest
@testable import CosmicCrisp
import MeshCoreKit

@MainActor
final class MessagingTests: XCTestCase {
    func testMessageStoreRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = MessageStore(nodeKeyHex: "abcd", directory: dir)
        let m = ChatMessage(conversation: .channel(index: 0), direction: .outgoing, text: "hi", status: .sent)
        await store.append(m)
        await store.update(m.id) { $0.status = .delivered }
        await store.markRead(.channel(index: 0))
        await store.flush()

        let reopened = MessageStore(nodeKeyHex: "abcd", directory: dir)
        let msgs = await reopened.messages
        XCTAssertEqual(msgs.count, 1)
        XCTAssertEqual(msgs.first?.status, .delivered)
        let read = await reopened.lastRead
        XCTAssertNotNil(read["ch:0"])
    }

    func testDemoNodeConversationsChannelsAndDelivery() async throws {
        let session = NodeSession()
        await session.connect()
        XCTAssertEqual(session.status, .connected)
        // Channels loaded from the (mock) node.
        XCTAssertEqual(session.configuredChannels.map(\.name), ["Public", "#nebraska"])
        XCTAssertNotNil(session.freeChannelIndex)

        // Send a DM to Bob; the demo node ACKs ~0.8s later.
        let bob = try XCTUnwrap(session.contacts.first { $0.name.hasPrefix("Bob") })
        let key = ConversationKey.contact(publicKeyHex: bob.id)
        session.send(text: "hello bob", in: key)
        try await Task.sleep(for: .seconds(2))
        let sent = try XCTUnwrap(session.messages(in: key).last)
        XCTAssertEqual(sent.status, .delivered)
        XCTAssertEqual(sent.roundTripMillis, 640)

        // Channel send is fire-and-forget (OK response only).
        session.send(text: "hi all", in: .channel(index: 0))
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(session.messages(in: .channel(index: 0)).last?.status, .sent)

        // Incoming demo messages arrive ~3s after connect: one DM, one channel message.
        try await Task.sleep(for: .seconds(2))
        XCTAssertTrue(session.messages(in: key).contains { $0.direction == .incoming })
        XCTAssertTrue(session.messages(in: .channel(index: 1)).contains { $0.direction == .incoming })
        XCTAssertGreaterThan(session.totalUnread, 0)
        session.markRead(key)
        XCTAssertEqual(session.unreadCount(in: key), 0)

        // Add a channel through the node.
        let idx = try XCTUnwrap(session.freeChannelIndex)
        await session.setChannel(index: idx, name: "#test", secret: ChannelKeys.hashtagSecret(for: "#test"))
        XCTAssertTrue(session.configuredChannels.contains { $0.name == "#test" })
        await session.disconnect()
    }
}
