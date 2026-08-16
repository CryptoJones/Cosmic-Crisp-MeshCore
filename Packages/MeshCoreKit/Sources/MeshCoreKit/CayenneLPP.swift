import Foundation

/// Cayenne Low Power Payload decoding — the format MeshCore uses for telemetry.
/// Each record: channel(1) type(1) data(N, big-endian). Only the types MeshCore
/// firmware actually emits are decoded; unknown types stop parsing (like the reference).
public struct LPPRecord: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case voltage(Double)          // V
        case temperature(Double)      // °C
        case humidity(Double)         // %RH
        case barometer(Double)        // hPa
        case illuminance(Double)      // lux
        case percentage(Double)
        case altitude(Double)         // m
        case power(Double)
        case current(Double)
        case analogInput(Double)
        case digitalInput(UInt8)
        case presence(UInt8)
        case genericSensor(UInt32)
        case location(latitude: Double, longitude: Double, altitude: Double)
    }
    public let channel: UInt8
    public let type: UInt8
    public let value: Value
}

public enum CayenneLPP {
    /// (byteCount, divisor, signed) per type — mirrors python-cayennelpp's table.
    static let types: [UInt8: (Int, Double, Bool)] = [
        0: (1, 1, false), 2: (2, 100, true), 100: (4, 1, false), 101: (2, 1, false), 102: (1, 1, false),
        103: (2, 10, true), 104: (1, 2, false), 115: (2, 10, false), 116: (2, 100, false), 117: (2, 1000, false),
        120: (1, 1, false), 121: (2, 1, true), 128: (2, 1, false), 136: (9, 1, true),
    ]

    public static func decode(_ bytes: [UInt8]) -> [LPPRecord] {
        var out: [LPPRecord] = []
        var i = 0
        while i + 2 <= bytes.count, bytes[i] != 0 || i + 1 < bytes.count {
            let channel = bytes[i], type = bytes[i + 1]
            guard let (size, divisor, signed) = types[type], i + 2 + size <= bytes.count else { break }
            let data = Array(bytes[(i + 2)..<(i + 2 + size)])
            i += 2 + size
            func be(_ b: ArraySlice<UInt8>, signed: Bool) -> Double {
                var v: Int64 = 0
                for x in b { v = (v << 8) | Int64(x) }
                if signed, let f = b.first, f & 0x80 != 0 { v -= Int64(1) << (8 * Int64(b.count)) }
                return Double(v)
            }
            let value: LPPRecord.Value
            switch type {
            case 0: value = .digitalInput(data[0])
            case 2: value = .analogInput(be(data[...], signed: signed) / divisor)
            case 100: value = .genericSensor(UInt32(be(data[...], signed: false)))
            case 101: value = .illuminance(be(data[...], signed: signed) / divisor)
            case 102: value = .presence(data[0])
            case 103: value = .temperature(be(data[...], signed: signed) / divisor)
            case 104: value = .humidity(be(data[...], signed: signed) / divisor)
            case 115: value = .barometer(be(data[...], signed: signed) / divisor)
            case 116: value = .voltage(be(data[...], signed: signed) / divisor)
            case 117: value = .current(be(data[...], signed: signed) / divisor)
            case 120: value = .percentage(be(data[...], signed: signed) / divisor)
            case 121: value = .altitude(be(data[...], signed: signed) / divisor)
            case 128: value = .power(be(data[...], signed: signed) / divisor)
            case 136:
                value = .location(latitude: be(data[0..<3], signed: true) / 10000,
                                  longitude: be(data[3..<6], signed: true) / 10000,
                                  altitude: be(data[6..<9], signed: true) / 100)
            default: continue
            }
            out.append(LPPRecord(channel: channel, type: type, value: value))
        }
        return out
    }
}
