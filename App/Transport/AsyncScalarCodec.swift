import Foundation

/// Byte packing used on the dext → app async completion path.
///
/// Layout (see `Driver/MeshCoreUSBShared.h`): scalar[0] = byte count,
/// scalars[1...] = bytes packed 8 per UInt64, little-endian. Max 120 bytes per
/// callback (16 scalars total). Pure and platform-independent so it can be tested
/// in the simulator even though the USB path itself can't run there.
enum AsyncScalarCodec {
    static let maxChunk = Int(kMeshCoreUSBMaxChunk)
    static let scalarCount = 16

    static func pack(_ bytes: [UInt8]) -> [UInt64] {
        precondition(bytes.count <= maxChunk)
        var words = [UInt64](repeating: 0, count: 1 + (bytes.count + 7) / 8)
        words[0] = UInt64(bytes.count)
        for (i, b) in bytes.enumerated() {
            words[1 + i / 8] |= UInt64(b) << (8 * UInt64(i % 8))
        }
        return words
    }

    /// Returns nil if the header is inconsistent with the number of scalars delivered.
    static func unpack(_ words: UnsafeBufferPointer<UInt64>) -> [UInt8]? {
        guard let first = words.first else { return nil }
        let length = Int(first)
        guard length >= 0, length <= maxChunk, words.count >= 1 + (length + 7) / 8 else { return nil }
        var out = [UInt8](repeating: 0, count: length)
        for i in 0..<length {
            out[i] = UInt8(truncatingIfNeeded: words[1 + i / 8] >> (8 * UInt64(i % 8)))
        }
        return out
    }

    static func unpack(_ words: [UInt64]) -> [UInt8]? {
        words.withUnsafeBufferPointer { unpack($0) }
    }
}
