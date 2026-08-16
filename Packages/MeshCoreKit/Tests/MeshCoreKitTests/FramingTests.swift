import XCTest
@testable import MeshCoreKit

final class FramingTests: XCTestCase {
    func testEncodeWrapsWithMarkerAndLittleEndianLength() {
        XCTAssertEqual(Framing.encode([0x14]), [0x3C, 0x01, 0x00, 0x14])
        let long = [UInt8](repeating: 0xAB, count: 258)
        XCTAssertEqual(Array(Framing.encode(long).prefix(3)), [0x3C, 0x02, 0x01])
    }

    func testDecodeSingleFrame() {
        var d = FrameDecoder()
        XCTAssertEqual(d.feed([0x3E, 0x02, 0x00, 0x00, 0x2A]), [[0x00, 0x2A]])
    }

    func testDecodeAcrossChunkBoundaries() {
        var d = FrameDecoder()
        XCTAssertEqual(d.feed([0x3E]), [])
        XCTAssertEqual(d.feed([0x03, 0x00, 0x09]), [])
        XCTAssertEqual(d.feed([0x01, 0x02, 0x3E, 0x01]), [[0x09, 0x01, 0x02]])
        XCTAssertEqual(d.feed([0x00, 0x0A]), [[0x0A]])
    }

    func testDecodeSkipsLeadingJunk() {
        var d = FrameDecoder()
        let junk = Array("boot: hello\r\n".utf8)
        XCTAssertEqual(d.feed(junk + [0x3E, 0x01, 0x00, 0x0A]), [[0x0A]])
    }

    func testDecodeResyncsOnBogusLength() {
        var d = FrameDecoder()
        // '>' followed by an absurd length, then a real frame.
        XCTAssertEqual(d.feed([0x3E, 0xFF, 0xFF, 0x3E, 0x01, 0x00, 0x0A]), [[0x0A]])
    }

    func testDecoderWithHostMarker() {
        var d = FrameDecoder(marker: Framing.hostToNode)
        XCTAssertEqual(d.feed(Framing.encode([0x14])), [[0x14]])
    }

    func testMultipleFramesInOneChunk() {
        var d = FrameDecoder()
        XCTAssertEqual(d.feed([0x3E, 0x01, 0x00, 0x0A, 0x3E, 0x01, 0x00, 0x00]), [[0x0A], [0x00]])
    }
}
