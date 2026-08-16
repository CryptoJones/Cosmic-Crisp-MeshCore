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
        case sendBinaryReq = 0x32          // 50
        case factoryReset = 0x33           // 51
        case sendPathDiscoveryReq = 0x34   // 52
        case setFloodScope = 0x36          // 54
        case sendControlData = 0x37        // 55
        case getStats = 0x38               // 56
        case sendAnonReq = 0x39            // 57
        case setAutoaddConfig = 0x3A       // 58
        case getAutoaddConfig = 0x3B       // 59
        case getAllowedRepeatFreq = 0x3C   // 60
        case setPathHashMode = 0x3D        // 61
        case setDefaultFloodScope = 0x3F   // 63
        case getDefaultFloodScope = 0x40   // 64
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

    /// Configure a channel slot: 32-byte NUL-padded name + 16-byte secret.
    public static func setChannel(_ index: UInt8, name: String, secret: [UInt8]) -> [UInt8] {
        precondition(secret.count == 16, "channel secret must be 16 bytes")
        var nameBytes = Array(name.utf8.prefix(32))
        nameBytes += [UInt8](repeating: 0, count: 32 - nameBytes.count)
        return [Code.setChannel.rawValue, index] + nameBytes + secret
    }

    /// Forget the learned route to a contact so the next send floods.
    public static func resetPath(publicKey: [UInt8]) -> [UInt8] {
        [Code.resetPath.rawValue] + publicKey
    }

    // MARK: Contacts — sharing / editing

    /// Export a contact card (or, with nil, our own node card). Node replies `contactURI`.
    public static func exportContact(publicKey: [UInt8]? = nil) -> [UInt8] {
        [Code.exportContact.rawValue] + (publicKey ?? [])
    }

    /// Import a card previously exported (the bytes after `meshcore://`).
    public static func importContact(card: [UInt8]) -> [UInt8] {
        [Code.importContact.rawValue] + card
    }

    /// Ask the node to advertise this contact's card to the mesh.
    public static func shareContact(publicKey: [UInt8]) -> [UInt8] {
        [Code.shareContact.rawValue] + publicKey
    }

    /// Add or update a contact record on the node (used for manual-add and path/flag edits).
    /// Path field is 64 bytes NUL padded; length byte 0xFF = flood.
    public static func addOrUpdateContact(_ c: Contact) -> [UInt8] {
        var out: [UInt8] = [Code.addUpdateContact.rawValue] + c.publicKey + [c.type, c.flags]
        if c.outPathLength < 0 {
            out.append(0xFF)
        } else {
            out.append(UInt8(c.outPathLength & 0x3F) | UInt8((max(c.outPathHashMode, 0) & 0x3) << 6))
        }
        var path = Array(c.outPath.prefix(64)); path += [UInt8](repeating: 0, count: 64 - path.count)
        out += path
        var name = Array(c.name.utf8.prefix(32)); name += [UInt8](repeating: 0, count: 32 - name.count)
        out += name
        out += c.lastAdvert.leBytes + Int32(c.latitude * 1e6).leBytes + Int32(c.longitude * 1e6).leBytes
        return out
    }

    public static func getAdvertPath(publicKey: [UInt8]) -> [UInt8] {
        [Code.getAdvertPath.rawValue, 0x00] + publicKey
    }

    // MARK: Remote requests (repeaters / rooms / sensors). All reply `messageSent`; the answer arrives as a push.

    public static func sendLogin(to publicKey: [UInt8], password: String) -> [UInt8] {
        [Code.sendLogin.rawValue] + publicKey + Array(password.utf8)
    }

    public static func sendLogout(to publicKey: [UInt8]) -> [UInt8] {
        [Code.logout.rawValue] + publicKey
    }

    public static func sendStatusRequest(to publicKey: [UInt8]) -> [UInt8] {
        [Code.sendStatusReq.rawValue] + publicKey
    }

    /// Remote CLI command to a logged-in repeater/room (text type 1).
    public static func sendRemoteCommand(to destination: [UInt8], command: String, timestamp: UInt32) -> [UInt8] {
        [Code.sendTextMessage.rawValue, 0x01, 0x00] + timestamp.leBytes + destination + Array(command.utf8)
    }

    /// Telemetry request. Empty destination = our own node's telemetry (`getSelfTelemetry`).
    public static func sendTelemetryRequest(to publicKey: [UInt8]) -> [UInt8] {
        [Code.sendTelemetryReq.rawValue, 0, 0, 0] + publicKey
    }

    public static func getSelfTelemetry() -> [UInt8] { [Code.sendTelemetryReq.rawValue, 0, 0, 0] }

    public static func sendPathDiscovery(to publicKey: [UInt8]) -> [UInt8] {
        [Code.sendPathDiscoveryReq.rawValue, 0x00] + publicKey
    }

    /// Trace a route: `tag` identifies the reply, `auth` is echoed, `path` is the hop hashes to traverse.
    public static func sendTrace(tag: UInt32, auth: UInt32, flags: UInt8, path: [UInt8]) -> [UInt8] {
        [Code.sendTracePath.rawValue] + tag.leBytes + auth.leBytes + [flags] + path
    }

    // MARK: Node parameters

    /// manualAddContacts + packed telemetry modes + advert location policy (+ multi-acks).
    public static func setOtherParams(manualAddContacts: Bool, telemetryBase: UInt8, telemetryLoc: UInt8,
                                      telemetryEnv: UInt8, advertLocationPolicy: UInt8, multiAcks: UInt8) -> [UInt8] {
        let tele = (telemetryBase & 0b11) | ((telemetryLoc & 0b11) << 2) | ((telemetryEnv & 0b11) << 4)
        return [Code.setOtherParams.rawValue, manualAddContacts ? 1 : 0, tele, advertLocationPolicy, multiAcks]
    }

    public static func setDevicePIN(_ pin: UInt32) -> [UInt8] { [Code.setDevicePin.rawValue] + pin.leBytes }

    public static func setTuningParams(rxDelayBase: UInt32, airtimeFactor: UInt32) -> [UInt8] {
        [Code.setTuningParams.rawValue] + rxDelayBase.leBytes + airtimeFactor.leBytes
    }

    public enum StatsType: UInt8, Sendable { case core = 0, radio = 1, packets = 2 }
    public static func getStats(_ type: StatsType) -> [UInt8] { [Code.getStats.rawValue, type.rawValue] }

    public static func hasConnection(to publicKey: [UInt8]) -> [UInt8] { [Code.hasConnection.rawValue] + publicKey }
}
