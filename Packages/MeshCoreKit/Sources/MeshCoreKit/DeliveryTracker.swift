import Foundation

/// Tracks outbound direct messages awaiting an ACK.
///
/// After `sendTextMessage` the node answers `messageSent(expectedAck, suggestedTimeout)`;
/// when the recipient's ACK arrives the node pushes `pushSendConfirmed(ackCode)`.
/// This maps ack codes back to message IDs and applies the reference retry policy:
/// up to `maxAttempts` sends, and after `floodAfter` failed direct attempts the
/// caller should `resetPath` so the next attempt floods.
public struct DeliveryTracker: Sendable {
    public struct Pending: Sendable, Equatable {
        public let messageID: UUID
        public let ackCode: [UInt8]
        public let deadline: Date
        public let attempt: Int
    }

    public static let maxAttempts = 3
    public static let floodAfter = 2

    private var pending: [UUID: Pending] = [:]

    public init() {}

    public var count: Int { pending.count }

    public mutating func track(messageID: UUID, sent: MessageSent, attempt: Int, now: Date = .now) -> Pending {
        // Reference: wait suggested_timeout * 1.2
        let deadline = now.addingTimeInterval(Double(sent.suggestedTimeoutMillis) / 1000 * 1.2)
        let p = Pending(messageID: messageID, ackCode: sent.expectedAck, deadline: deadline, attempt: attempt)
        pending[messageID] = p
        return p
    }

    /// Returns the message ID confirmed by this ack code, if any.
    public mutating func confirm(ackCode: [UInt8]) -> UUID? {
        guard let hit = pending.values.first(where: { $0.ackCode == ackCode }) else { return nil }
        pending[hit.messageID] = nil
        return hit.messageID
    }

    /// Messages whose deadline has passed; they are removed from tracking.
    public mutating func expired(now: Date = .now) -> [Pending] {
        let dead = pending.values.filter { $0.deadline <= now }
        for p in dead { pending[p.messageID] = nil }
        return dead
    }

    public func isPending(_ id: UUID) -> Bool { pending[id] != nil }

    /// Retry decision for a timed-out attempt (attempt numbers start at 0).
    public static func nextStep(afterFailedAttempt attempt: Int) -> RetryStep {
        let next = attempt + 1
        if next >= maxAttempts { return .giveUp }
        return next == floodAfter ? .resetPathThenRetry(attempt: next) : .retry(attempt: next)
    }

    public enum RetryStep: Equatable, Sendable {
        case retry(attempt: Int)
        case resetPathThenRetry(attempt: Int)
        case giveUp
    }
}
