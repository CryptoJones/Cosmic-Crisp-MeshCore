import Foundation

/// MeshCore companion serial framing.
///
/// Host → node:  `0x3C` `<len:u16 LE>` `<payload>`
/// Node → host:  `0x3E` `<len:u16 LE>` `<payload>`
///
/// The BLE transport carries bare payloads (one characteristic write per command);
/// serial/USB wraps them in these frames so the byte stream can be resynchronised.
public enum Framing {
    public static let hostToNode: UInt8 = 0x3C  // '<'
    public static let nodeToHost: UInt8 = 0x3E  // '>'
    /// Frames longer than this are treated as corruption and the decoder resyncs.
    public static let maxPayload = 300

    public static func encode(_ payload: [UInt8]) -> [UInt8] {
        precondition(payload.count <= UInt16.max)
        return [hostToNode] + UInt16(payload.count).leBytes + payload
    }
}

/// Incremental decoder for node→host frames. Feed it arbitrary byte chunks; it
/// yields complete payloads and silently skips leading junk (some radios
/// interleave debug text on the same UART).
public struct FrameDecoder: Sendable {
    private var buffer: [UInt8] = []
    private let marker: UInt8

    /// - Parameter marker: start-of-frame byte to sync on. Defaults to node→host (`>`);
    ///   a mock node decoding host commands passes `Framing.hostToNode`.
    public init(marker: UInt8 = Framing.nodeToHost) { self.marker = marker }

    public mutating func feed(_ chunk: [UInt8]) -> [[UInt8]] {
        buffer.append(contentsOf: chunk)
        var out: [[UInt8]] = []
        while true {
            // Resync to the next start-of-frame marker.
            guard let start = buffer.firstIndex(of: marker) else {
                buffer.removeAll(keepingCapacity: true)
                return out
            }
            if start > 0 { buffer.removeFirst(start) }
            guard buffer.count >= 3 else { return out }
            let length = Int(buffer[1]) | Int(buffer[2]) << 8
            if length > Framing.maxPayload {
                // Bad length: drop the marker byte and search again.
                buffer.removeFirst()
                continue
            }
            guard buffer.count >= 3 + length else { return out }
            out.append(Array(buffer[3..<(3 + length)]))
            buffer.removeFirst(3 + length)
        }
    }

    public mutating func feed(_ data: Data) -> [[UInt8]] { feed([UInt8](data)) }
}
