import Foundation

/// Command byte builders for the MeshCore companion protocol.
///
/// Every command is a leading opcode byte followed by opcode-specific fields, all
/// little-endian. Layouts mirror `meshcore/commands/*.py` in the reference library.
public enum Command {
    // MARK: Opcodes
    public enum Code: UInt8 {
        case appStart = 0x01
        case sendTextMessage = 0x02
        case sendChannelTextMessage = 0x03
        case getContacts = 0x04
        case getDeviceTime = 0x05
        case setDeviceTime = 0x06
        case sendSelfAdvert = 0x07
        case setAdvertName = 0x08
        case addUpdateContact = 0x09
        case syncNextMessage = 0x0A
        case setRadioParams = 0x0B
        case setRadioTxPower = 0x0C
        case resetPath = 0x0D
        case setAdvertLatLon = 0x0E
        case removeContact = 0x0F
        case shareContact = 0x10
        case exportContact = 0x11
        case importContact = 0x12
        case reboot = 0x13
        case getBatteryVoltage = 0x14
        case setTuningParams = 0x15
        case deviceQuery = 0x16
        case exportPrivateKey = 0x17
        case importPrivateKey = 0x18
        case sendRawData = 0x19
        case sendLogin = 0x1A
        case sendStatusReq = 0x1B
        case hasConnection = 0x1C
        case logout = 0x1D
        case getContactByKey = 0x1E
        case getChannel = 0x1F
        case setChannel = 0x20
        case signStart = 0x21
        case signData = 0x22
        case signFinish = 0x23
        case sendTracePath = 0x24
        case setDevicePin = 0x25
        case setOtherParams = 0x26
        case sendTelemetryReq = 0x27
        case getCustomVars = 0x28
        case setCustomVar = 0x29
        case getAdvertPath = 0x2A
        case getTuningParams = 0x2B
        case sendBinaryReq = 0x32
        case setAutoaddConfig = 0x33
        case getAutoaddConfig = 0x34
        case setPathHashMode = 0x35
        case getPathHashMode = 0x36
        case sendPathDiscoveryReq = 0x37
        case getStats = 0x38
        case sendAnonReq = 0x39
        case getAllowedRepeatFreq = 0x3A
        case sendControlData = 0x3B
        case setFloodScope = 0x3C
        case getDefaultFloodScope = 0x3D
    }

    /// Companion protocol version this client speaks.
    public static let appVersion: UInt8 = 3

    // MARK: Device

    /// `CMD_APP_START`: handshake. Node replies with `SELF_INFO`.
    public static func appStart(appName: String = "CosmicCrisp") -> [UInt8] {
        // Reference: b"\x01\x03      mccli" — 6 reserved bytes then the app name.
        [Code.appStart.rawValue, appVersion] + [UInt8](repeating: 0x20, count: 6) + Array(appName.utf8)
    }

    public static func deviceQuery() -> [UInt8] { [Code.deviceQuery.rawValue, appVersion] }

    public static func sendSelfAdvert(flood: Bool) -> [UInt8] {
        flood ? [Code.sendSelfAdvert.rawValue, 0x01] : [Code.sendSelfAdvert.rawValue]
    }

    public static func setAdvertName(_ name: String) -> [UInt8] {
        [Code.setAdvertName.rawValue] + Array(name.utf8)
    }

    public static func setAdvertLatLon(lat: Double, lon: Double) -> [UInt8] {
        [Code.setAdvertLatLon.rawValue]
            + Int32(lat * 1e6).leBytes + Int32(lon * 1e6).leBytes + UInt32(0).leBytes
    }

    public static func getBatteryVoltage() -> [UInt8] { [Code.getBatteryVoltage.rawValue] }
    public static func getDeviceTime() -> [UInt8] { [Code.getDeviceTime.rawValue] }

    public static func setDeviceTime(_ epoch: UInt32) -> [UInt8] {
        [Code.setDeviceTime.rawValue] + epoch.leBytes
    }

    public static func setRadioTxPower(_ dbm: UInt8) -> [UInt8] {
        [Code.setRadioTxPower.rawValue, dbm]
    }

    /// Frequency and bandwidth in kHz ×1000 (i.e. Hz/1000 → the firmware's kHz×1000 units).
    public static func setRadioParams(freqMHz: Double, bwKHz: Double, sf: UInt8, cr: UInt8) -> [UInt8] {
        [Code.setRadioParams.rawValue]
            + UInt32(freqMHz * 1000).leBytes + UInt32(bwKHz * 1000).leBytes + [sf, cr]
    }

    public static func reboot() -> [UInt8] { [Code.reboot.rawValue] + Array("reboot".utf8) }

    public static func getCustomVars() -> [UInt8] { [Code.getCustomVars.rawValue] }

    /// Custom vars are `key:value` UTF-8 pairs. GPS on the Wio Tracker L1 is `gps` = `1`/`0`.
    public static func setCustomVar(_ key: String, _ value: String) -> [UInt8] {
        [Code.setCustomVar.rawValue] + Array("\(key):\(value)".utf8)
    }

    // MARK: Contacts

    public static func getContacts(since lastMod: UInt32 = 0) -> [UInt8] {
        lastMod > 0 ? [Code.getContacts.rawValue] + lastMod.leBytes : [Code.getContacts.rawValue]
    }

    public static func getContact(publicKey: [UInt8]) -> [UInt8] {
        [Code.getContactByKey.rawValue] + publicKey
    }

    public static func removeContact(publicKey: [UInt8]) -> [UInt8] {
        [Code.removeContact.rawValue] + publicKey
    }

    // MARK: Messaging

    /// Direct text message. `destination` is the contact's 32-byte public key
    /// (or a 6-byte prefix). `attempt` increments on retries.
    public static func sendTextMessage(to destination: [UInt8], text: String,
                                       timestamp: UInt32, attempt: UInt8 = 0) -> [UInt8] {
        [Code.sendTextMessage.rawValue, 0x00, attempt] + timestamp.leBytes + destination + Array(text.utf8)
    }

    /// Text message to a channel index.
    public static func sendChannelTextMessage(channel: UInt8, text: String, timestamp: UInt32) -> [UInt8] {
        [Code.sendChannelTextMessage.rawValue, 0x00, channel] + timestamp.leBytes + Array(text.utf8)
    }

    /// Ask the node for the next queued inbound message. Node replies with a
    /// `CONTACT_MSG_RECV_V3` / `CHANNEL_MSG_RECV_V3`, or `NO_MORE_MSGS`.
    public static func syncNextMessage() -> [UInt8] { [Code.syncNextMessage.rawValue] }

    public static func getChannel(_ index: UInt8) -> [UInt8] { [Code.getChannel.rawValue, index] }
}
