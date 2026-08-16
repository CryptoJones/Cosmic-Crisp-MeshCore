import XCTest
@testable import CosmicCrisp

final class AsyncScalarCodecTests: XCTestCase {
    func testRoundTripSmall() {
        let bytes: [UInt8] = [0x3E, 0x02, 0x00, 0x00, 0x2A]
        let words = AsyncScalarCodec.pack(bytes)
        XCTAssertEqual(words.count, 2)
        XCTAssertEqual(words[0], 5)
        XCTAssertEqual(words[1], 0x2A_0000_023E)          // little-endian packing
        XCTAssertEqual(AsyncScalarCodec.unpack(words), bytes)
    }

    func testRoundTripMaxChunkFillsAllScalars() {
        let bytes = (0..<AsyncScalarCodec.maxChunk).map { UInt8(truncatingIfNeeded: $0 &* 7) }
        let words = AsyncScalarCodec.pack(bytes)
        XCTAssertEqual(words.count, AsyncScalarCodec.scalarCount)
        XCTAssertEqual(AsyncScalarCodec.unpack(words), bytes)
    }

    func testEmpty() {
        XCTAssertEqual(AsyncScalarCodec.pack([]), [0])
        XCTAssertEqual(AsyncScalarCodec.unpack([0]), [])
    }

    func testRejectsInconsistentHeader() {
        XCTAssertNil(AsyncScalarCodec.unpack([]))
        XCTAssertNil(AsyncScalarCodec.unpack([64, 0]))       // claims 64 bytes, delivers 1 word
        XCTAssertNil(AsyncScalarCodec.unpack([UInt64(AsyncScalarCodec.maxChunk + 1)] + [UInt64](repeating: 0, count: 15)))
    }

    /// Mirrors the C++ side: `memcpy(&args[1], bytes, length)` on a little-endian CPU.
    func testMatchesMemcpyLayout() {
        let bytes: [UInt8] = Array(1...13)
        var expected = [UInt64](repeating: 0, count: 3)
        expected[0] = 13
        expected.withUnsafeMutableBytes { raw in
            bytes.withUnsafeBytes { src in raw.baseAddress!.advanced(by: 8).copyMemory(from: src.baseAddress!, byteCount: 13) }
        }
        XCTAssertEqual(AsyncScalarCodec.pack(bytes), expected)
    }
}
