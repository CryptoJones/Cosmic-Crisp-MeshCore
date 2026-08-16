import Foundation

/// First byte of every node→host payload.
public enum ResponseCode: UInt8, Sendable {
    case ok = 0x00
    case error = 0x01
    case contactsStart = 0x02
    case contact = 0x03
    case contactsEnd = 0x04
    case selfInfo = 0x05
    case messageSent = 0x06
    case contactMessageReceived = 0x07
    case channelMessageReceived = 0x08
    case currentTime = 0x09
    case noMoreMessages = 0x0A
    case contactURI = 0x0B
    case battery = 0x0C
    case deviceInfo = 0x0D
    case privateKey = 0x0E
    case disabled = 0x0F
    case contactMessageReceivedV3 = 0x10
    case channelMessageReceivedV3 = 0x11
    case channelInfo = 0x12
    case signStart = 0x13
    case signature = 0x14
    case customVars = 0x15
    case advertPath = 0x16
    case tuningParams = 0x17
    case stats = 0x18
    case autoaddConfig = 0x19
    case allowedRepeatFreq = 0x1A
    case channelDataReceived = 0x1B
    case defaultFloodScope = 0x1C

    // Unsolicited pushes (high bit set)
    case pushAdvert = 0x80
    case pushPathUpdated = 0x81
    case pushSendConfirmed = 0x82
    case pushMessagesWaiting = 0x83
    case pushRawData = 0x84
    case pushLoginSuccess = 0x85
    case pushLoginFailed = 0x86
    case pushStatusResponse = 0x87
    case pushLogData = 0x88
    case pushTraceData = 0x89
    case pushNewAdvert = 0x8A
    case pushTelemetryResponse = 0x8B
    case pushBinaryResponse = 0x8C
    case pushPathDiscoveryResponse = 0x8D
    case pushControlData = 0x8E
    case pushContactDeleted = 0x8F
    case pushContactsFull = 0x90

    public var isPush: Bool { rawValue & 0x80 != 0 }
}

// MARK: - Parsed models

public struct SelfInfo: Sendable, Equatable {
    public var advertType: UInt8
    public var txPower: UInt8
    public var maxTxPower: UInt8
    public var publicKey: [UInt8]           // 32 bytes
    public var latitude: Double
    public var longitude: Double
    public var multiAcks: UInt8
    public var advertLocationPolicy: UInt8
    public var telemetryModeEnv: UInt8
    public var telemetryModeLoc: UInt8
    public var telemetryModeBase: UInt8
    public var manualAddContacts: Bool
    public var radioFrequencyMHz: Double
    public var radioBandwidthKHz: Double
    public var spreadingFactor: UInt8
    public var codingRate: UInt8
    public var name: String

    public var publicKeyHex: String { publicKey.hexString }
}

public struct Contact: Sendable, Equatable, Identifiable {
    public enum Kind: UInt8, Sendable { case none = 0, chat = 1, repeater = 2, room = 3, sensor = 4 }

    public var publicKey: [UInt8]           // 32 bytes
    public var type: UInt8
    public var flags: UInt8
    /// -1 = flood routing; otherwise number of hops in `outPath`.
    public var outPathLength: Int
    public var outPathHashMode: Int
    public var outPath: [UInt8]
    public var name: String
    public var lastAdvert: UInt32
    public var latitude: Double
    public var longitude: Double
    public var lastModified: UInt32

    public var id: String { publicKey.hexString }
    public var kind: Kind { Kind(rawValue: type) ?? .none }
}

public struct ReceivedMessage: Sendable, Equatable {
    public enum Source: Sendable, Equatable {
        case contact(publicKeyPrefix: [UInt8])   // 6 bytes
        case channel(index: UInt8)
    }
    public var source: Source
    public var snr: Double?                 // V3 frames only
    public var pathLength: Int              // -1 = direct
    public var textType: UInt8
    public var senderTimestamp: UInt32
    public var signature: [UInt8]?          // textType == 2 (signed plain text)
    public var text: String
}

public struct MessageSent: Sendable, Equatable {
    public var type: UInt8
    public var expectedAck: [UInt8]         // 4 bytes
    public var suggestedTimeoutMillis: UInt32
}

public struct DeviceInfo: Sendable, Equatable {
    public var firmwareVersion: UInt8
    public var maxContacts: Int?
    public var maxChannels: Int?
    public var blePin: UInt32?
    public var firmwareBuild: String?
    public var model: String?
    public var version: String?
    public var repeaterMode: Bool?
    public var pathHashMode: UInt8?
}

public struct BatteryInfo: Sendable, Equatable {
    public var millivolts: UInt16
    public var storageUsedKB: UInt32?
    public var storageTotalKB: UInt32?
}

public struct ChannelInfo: Sendable, Equatable {
    public var index: UInt8
    public var name: String
    public var secret: [UInt8]              // 16 bytes
}

/// A decoded node→host payload.
public enum Response: Sendable, Equatable {
    case ok(value: UInt32?)
    case error(code: UInt8?)
    case contactsStart(count: UInt32)
    case contact(Contact)
    case contactsEnd(mostRecentLastModified: UInt32?)
    case selfInfo(SelfInfo)
    case messageSent(MessageSent)
    case message(ReceivedMessage)
    case currentTime(UInt32)
    case noMoreMessages
    case battery(BatteryInfo)
    case deviceInfo(DeviceInfo)
    case customVars([String: String])
    case channelInfo(ChannelInfo)
    case pushAdvert(publicKey: [UInt8])
    case pushNewAdvert(Contact)
    case pushMessagesWaiting
    case pushSendConfirmed(ackCode: [UInt8], roundTripMillis: UInt32?)
    case pushPathUpdated(publicKey: [UInt8])
    case pushContactsFull
    /// Anything we don't decode yet — kept raw so nothing is silently dropped.
    case unhandled(code: UInt8, payload: [UInt8])
    case malformed(code: UInt8?, payload: [UInt8])

    public var isPush: Bool {
        switch self {
        case .pushAdvert, .pushNewAdvert, .pushMessagesWaiting, .pushSendConfirmed,
             .pushPathUpdated, .pushContactsFull: return true
        case .unhandled(let code, _): return code & 0x80 != 0
        default: return false
        }
    }
}
