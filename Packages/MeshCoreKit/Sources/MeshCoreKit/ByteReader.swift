import Foundation

/// Little-endian cursor over a byte buffer. Mirrors the `dbuf.read(n)` idiom in the
/// reference Python library so parser code reads like the reference.
struct ByteReader {
    private let bytes: [UInt8]
    private(set) var offset: Int = 0

    init(_ data: Data) { self.bytes = [UInt8](data) }
    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var remaining: Int { bytes.count - offset }
    var isAtEnd: Bool { remaining <= 0 }

    /// Reads exactly `n` bytes; short reads return whatever is left (like Python's `read`).
    mutating func read(_ n: Int) -> [UInt8] {
        let end = min(offset + n, bytes.count)
        defer { offset = end }
        return offset < end ? Array(bytes[offset..<end]) : []
    }

    /// Reads all remaining bytes.
    mutating func readToEnd() -> [UInt8] { read(remaining) }

    mutating func skip(_ n: Int) { offset = min(offset + n, bytes.count) }

    mutating func u8() -> UInt8? { read(1).first }

    mutating func u16() -> UInt16? {
        let b = read(2); guard b.count == 2 else { return nil }
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    mutating func u32() -> UInt32? {
        let b = read(4); guard b.count == 4 else { return nil }
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func i32() -> Int32? { u32().map { Int32(bitPattern: $0) } }

    mutating func i8() -> Int8? { u8().map { Int8(bitPattern: $0) } }

    /// UTF-8 string of `n` bytes with NUL padding stripped (fixed-width name fields).
    mutating func fixedString(_ n: Int) -> String {
        let raw = read(n).prefix { $0 != 0 }
        return String(decoding: raw, as: UTF8.self)
    }

    /// UTF-8 string of all remaining bytes.
    mutating func restString() -> String {
        String(decoding: readToEnd(), as: UTF8.self)
    }
}

public extension Array where Element == UInt8 {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

public extension FixedWidthInteger {
    /// Little-endian byte representation, `MemoryLayout<Self>.size` bytes long.
    var leBytes: [UInt8] {
        withUnsafeBytes(of: littleEndian) { Array($0) }
    }
}
