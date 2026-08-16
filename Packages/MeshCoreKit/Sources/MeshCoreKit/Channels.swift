import Foundation
import CryptoKit

/// Channel key conventions used by MeshCore companion apps.
public enum ChannelKeys {
    /// The default "Public" channel secret shared by all MeshCore nodes.
    public static let publicChannel: [UInt8] = [
        0x8B, 0x33, 0x87, 0xE9, 0xC5, 0xCD, 0xEA, 0x6A,
        0xC9, 0xE5, 0xED, 0xBA, 0xA1, 0x15, 0xCD, 0x72,
    ]

    /// Hashtag channels (`#name`) derive their secret from the name: first 16
    /// bytes of SHA-256(name). Matches the reference library / official apps.
    public static func hashtagSecret(for name: String) -> [UInt8] {
        Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
    }

    public static func randomSecret() -> [UInt8] {
        (0..<16).map { _ in UInt8.random(in: 0...255) }
    }

    /// Parse a 32-hex-char secret.
    public static func secret(fromHex hex: String) -> [UInt8]? {
        guard let b = bytes(fromHex: hex), b.count == 16 else { return nil }
        return b
    }

    /// Parse any even-length hex string.
    public static func bytes(fromHex hex: String) -> [UInt8]? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.count % 2 == 0, !clean.isEmpty, clean.allSatisfy({ $0.isHexDigit }) else { return nil }
        var out: [UInt8] = []
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            out.append(UInt8(clean[i..<j], radix: 16)!)
            i = j
        }
        return out
    }
}
