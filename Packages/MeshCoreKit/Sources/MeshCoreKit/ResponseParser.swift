import Foundation

/// Decodes node→host payloads (already de-framed) into `Response` values.
/// Layouts mirror `meshcore/reader.py` in the reference Python library.
public enum ResponseParser {
    public static func parse(_ payload: [UInt8]) -> Response {
        guard let first = payload.first else { return .malformed(code: nil, payload: payload) }
        guard let code = ResponseCode(rawValue: first) else { return .unhandled(code: first, payload: payload) }
        var r = ByteReader(payload)
        r.skip(1)

        switch code {
        case .ok:
            return .ok(value: payload.count == 5 ? r.u32() : nil)

        case .error:
            return .error(code: r.u8())

        case .contactsStart:
            guard let n = r.u32() else { return .malformed(code: first, payload: payload) }
            return .contactsStart(count: n)

        case .contact, .pushNewAdvert:
            guard let c = parseContact(&r) else { return .malformed(code: first, payload: payload) }
            return code == .contact ? .contact(c) : .pushNewAdvert(c)

        case .contactsEnd:
            return .contactsEnd(mostRecentLastModified: r.u32())

        case .selfInfo:
            guard let s = parseSelfInfo(&r) else { return .malformed(code: first, payload: payload) }
            return .selfInfo(s)

        case .messageSent:
            guard let type = r.u8() else { return .malformed(code: first, payload: payload) }
            let ack = r.read(4)
            guard ack.count == 4, let timeout = r.u32() else { return .malformed(code: first, payload: payload) }
            return .messageSent(MessageSent(type: type, expectedAck: ack, suggestedTimeoutMillis: timeout))

        case .contactMessageReceived, .contactMessageReceivedV3:
            guard let m = parseContactMessage(&r, v3: code == .contactMessageReceivedV3) else {
                return .malformed(code: first, payload: payload)
            }
            return .message(m)

        case .channelMessageReceived, .channelMessageReceivedV3:
            guard let m = parseChannelMessage(&r, v3: code == .channelMessageReceivedV3) else {
                return .malformed(code: first, payload: payload)
            }
            return .message(m)

        case .currentTime:
            guard let t = r.u32() else { return .malformed(code: first, payload: payload) }
            return .currentTime(t)

        case .noMoreMessages:
            return .noMoreMessages

        case .battery:
            guard let mv = r.u16() else { return .malformed(code: first, payload: payload) }
            return .battery(BatteryInfo(millivolts: mv, storageUsedKB: r.u32(), storageTotalKB: r.u32()))

        case .deviceInfo:
            guard let fw = r.u8() else { return .malformed(code: first, payload: payload) }
            var info = DeviceInfo(firmwareVersion: fw)
            if fw >= 3 {
                info.maxContacts = r.u8().map { Int($0) * 2 }
                info.maxChannels = r.u8().map { Int($0) }
                info.blePin = r.u32()
                info.firmwareBuild = r.fixedString(12)
                info.model = r.fixedString(40)
                info.version = r.fixedString(20)
            }
            if fw >= 9 { info.repeaterMode = r.u8().map { $0 != 0 } }
            if fw >= 10 { info.pathHashMode = r.u8() }
            return .deviceInfo(info)

        case .customVars:
            let raw = r.restString()
            var vars: [String: String] = [:]
            if !raw.isEmpty {
                for pair in raw.split(separator: ",") {
                    let kv = pair.split(separator: ":", maxSplits: 1)
                    if kv.count == 2 { vars[String(kv[0])] = String(kv[1]) }
                }
            }
            return .customVars(vars)

        case .channelInfo:
            guard let idx = r.u8() else { return .malformed(code: first, payload: payload) }
            let name = r.fixedString(32)
            let secret = r.read(16)
            return .channelInfo(ChannelInfo(index: idx, name: name, secret: secret))

        case .pushAdvert:
            let key = r.read(32)
            return key.count == 32 ? .pushAdvert(publicKey: key) : .malformed(code: first, payload: payload)

        case .pushPathUpdated:
            let key = r.read(32)
            return key.count == 32 ? .pushPathUpdated(publicKey: key) : .malformed(code: first, payload: payload)

        case .pushMessagesWaiting:
            return .pushMessagesWaiting

        case .pushSendConfirmed:
            let ack = r.read(4)
            guard ack.count == 4 else { return .malformed(code: first, payload: payload) }
            return .pushSendConfirmed(ackCode: ack, roundTripMillis: r.u32())

        case .pushContactsFull:
            return .pushContactsFull

        case .contactURI:
            return .contactURI(card: r.readToEnd())

        case .advertPath:
            guard let ts = r.u32(), let plen = r.u8() else { return .malformed(code: first, payload: payload) }
            let (len, mode) = decodePathLength(plen)
            let path = r.readToEnd()
            return .advertPath(AdvertPath(timestamp: ts, pathLength: len, pathHashMode: mode,
                                          path: len > 0 ? Array(path.prefix(len * (mode + 1))) : []))

        case .tuningParams:
            guard let rx = r.u32(), let af = r.u32() else { return .malformed(code: first, payload: payload) }
            return .tuningParams(rxDelayBase: rx, airtimeFactor: af)

        case .stats:
            guard let type = r.u8() else { return .malformed(code: first, payload: payload) }
            switch type {
            case 0:
                guard let mv = r.u16(), let up = r.u32(), let err = r.u16(), let q = r.u8() else { return .malformed(code: first, payload: payload) }
                return .stats(.core(batteryMillivolts: mv, uptimeSeconds: up, errors: err, queueLength: q))
            case 1:
                guard let nf = r.u16(), let rssi = r.i8(), let snr = r.i8(), let tx = r.u32(), let rx = r.u32() else { return .malformed(code: first, payload: payload) }
                return .stats(.radio(noiseFloor: Int16(bitPattern: nf), lastRSSI: rssi, lastSNR: Double(snr) / 4, txAirSeconds: tx, rxAirSeconds: rx))
            case 2:
                guard let recv = r.u32(), let sent = r.u32(), let ftx = r.u32(), let dtx = r.u32(), let frx = r.u32(), let drx = r.u32() else { return .malformed(code: first, payload: payload) }
                return .stats(.packets(received: recv, sent: sent, floodTx: ftx, directTx: dtx, floodRx: frx, directRx: drx, receiveErrors: r.u32()))
            default:
                return .unhandled(code: first, payload: payload)
            }

        case .pushStatusResponse:
            // 0x87, reserved, pubkey[6], then 52+ bytes of status fields
            r.skip(1)
            let prefix = r.read(6)
            guard prefix.count == 6, payload.count >= 60,
                  let bat = r.u16(), let q = r.u16(), let nf = r.u16(), let rssi = r.u16(),
                  let nrecv = r.u32(), let nsent = r.u32(), let air = r.u32(), let up = r.u32(),
                  let sf = r.u32(), let sd = r.u32(), let rf = r.u32(), let rd = r.u32(),
                  let full = r.u16(), let snr = r.u16(), let ddup = r.u16(), let fdup = r.u16(), let rxair = r.u32()
            else { return .malformed(code: first, payload: payload) }
            return .pushStatusResponse(NodeStatus(publicKeyPrefix: prefix, batteryMillivolts: bat, txQueueLength: q,
                noiseFloor: Int16(bitPattern: nf), lastRSSI: Int16(bitPattern: rssi), packetsReceived: nrecv, packetsSent: nsent,
                airtimeSeconds: air, uptimeSeconds: up, sentFlood: sf, sentDirect: sd, receivedFlood: rf, receivedDirect: rd,
                fullEvents: full, lastSNR: Double(Int16(bitPattern: snr)) / 4, directDuplicates: ddup, floodDuplicates: fdup,
                rxAirtimeSeconds: rxair, receiveErrors: r.u32()))

        case .pushTelemetryResponse:
            r.skip(1)
            let prefix = r.read(6)
            guard prefix.count == 6 else { return .malformed(code: first, payload: payload) }
            return .pushTelemetryResponse(TelemetryResponse(publicKeyPrefix: prefix, records: CayenneLPP.decode(r.readToEnd())))

        case .pushPathDiscoveryResponse:
            r.skip(1)
            let prefix = r.read(6)
            guard prefix.count == 6, let opl = r.u8() else { return .malformed(code: first, payload: payload) }
            let ohl = Int((opl & 0xC0) >> 6) + 1, olen = Int(opl & 0x3F)
            let outPath = r.read(olen * ohl)
            guard let ipl = r.u8() else { return .malformed(code: first, payload: payload) }
            let ihl = Int((ipl & 0xC0) >> 6) + 1, ilen = Int(ipl & 0x3F)
            let inPath = r.read(ilen * ihl)
            return .pushPathDiscoveryResponse(PathDiscoveryResponse(publicKeyPrefix: prefix, outPath: outPath, outPathHashLength: ohl,
                                                                     inPath: inPath, inPathHashLength: ihl))

        case .pushTraceData:
            r.skip(1)
            guard let rawLen = r.u8(), let flags = r.u8(), let tag = r.u32(), let auth = r.u32() else { return .malformed(code: first, payload: payload) }
            let hashLen = 1 << Int(flags & 3)
            let n = Int(rawLen) / hashLen
            var hops: [TraceResponse.Hop] = []
            var finalSNR: Double?
            if n > 0, r.remaining >= n * hashLen + n + 1 {
                let hashes = (0..<n).map { _ in r.read(hashLen) }
                let snrs = (0..<n).map { _ in Double(r.i8() ?? 0) / 4 }
                hops = zip(hashes, snrs).map { TraceResponse.Hop(hash: $0, snr: $1) }
                finalSNR = r.i8().map { Double($0) / 4 }
            }
            return .pushTraceData(TraceResponse(tag: tag, auth: auth, flags: flags, hops: hops, finalSNR: finalSNR))

        case .pushLoginSuccess, .pushLoginFailed:
            var perms: UInt8?
            var prefix: [UInt8]?
            if code == .pushLoginSuccess {
                perms = r.u8()
                if r.remaining >= 6 { prefix = r.read(6) }
            } else {
                r.skip(1)
                if r.remaining >= 6 { prefix = r.read(6) }
            }
            return .pushLoginResult(LoginResult(success: code == .pushLoginSuccess, isAdmin: (perms ?? 0) & 1 == 1,
                                                permissions: perms, publicKeyPrefix: prefix))

        case .pushContactDeleted:
            let key = r.read(32)
            return key.count == 32 ? .pushContactDeleted(publicKey: key) : .malformed(code: first, payload: payload)

        case .pushRawData:
            guard let snr = r.i8(), let rssi = r.i8() else { return .malformed(code: first, payload: payload) }
            r.skip(1)   // reserved
            return .pushRawData(snr: Double(snr) / 4, rssi: rssi, payload: r.readToEnd())

        case .pushLogData:
            return .pushLogData(payload: r.readToEnd())

        default:
            return .unhandled(code: first, payload: payload)
        }
    }

    // MARK: - Pieces

    /// Path-length byte: 0xFF = flood; otherwise top 2 bits are hash mode, low 6 bits are hop count.
    static func decodePathLength(_ b: UInt8) -> (length: Int, hashMode: Int) {
        b == 0xFF ? (-1, -1) : (Int(b & 0x3F), Int(b >> 6))
    }

    static func parseContact(_ r: inout ByteReader) -> Contact? {
        let key = r.read(32)
        guard key.count == 32, let type = r.u8(), let flags = r.u8(), let plen = r.u8() else { return nil }
        let (len, mode) = decodePathLength(plen)
        let pathField = r.read(64)
        guard pathField.count == 64 else { return nil }
        let outPath: [UInt8] = len > 0 ? Array(pathField.prefix(len * (mode + 1))) : []
        let name = r.fixedString(32)
        guard let lastAdvert = r.u32(), let lat = r.i32(), let lon = r.i32(), let lastMod = r.u32() else { return nil }
        return Contact(publicKey: key, type: type, flags: flags, outPathLength: len, outPathHashMode: mode,
                       outPath: outPath, name: name, lastAdvert: lastAdvert,
                       latitude: Double(lat) / 1e6, longitude: Double(lon) / 1e6, lastModified: lastMod)
    }

    static func parseSelfInfo(_ r: inout ByteReader) -> SelfInfo? {
        guard let advType = r.u8(), let tx = r.u8(), let maxTx = r.u8() else { return nil }
        let key = r.read(32)
        guard key.count == 32, let lat = r.i32(), let lon = r.i32(),
              let multiAcks = r.u8(), let locPolicy = r.u8(), let tele = r.u8(), let manual = r.u8(),
              let freq = r.u32(), let bw = r.u32(), let sf = r.u8(), let cr = r.u8() else { return nil }
        return SelfInfo(advertType: advType, txPower: tx, maxTxPower: maxTx, publicKey: key,
                        latitude: Double(lat) / 1e6, longitude: Double(lon) / 1e6,
                        multiAcks: multiAcks, advertLocationPolicy: locPolicy,
                        telemetryModeEnv: (tele >> 4) & 0b11, telemetryModeLoc: (tele >> 2) & 0b11,
                        telemetryModeBase: tele & 0b11, manualAddContacts: manual > 0,
                        radioFrequencyMHz: Double(freq) / 1000, radioBandwidthKHz: Double(bw) / 1000,
                        spreadingFactor: sf, codingRate: cr, name: r.restString())
    }

    static func parseContactMessage(_ r: inout ByteReader, v3: Bool) -> ReceivedMessage? {
        var snr: Double?
        if v3 {
            guard let s = r.i8() else { return nil }
            snr = Double(s) / 4
            r.skip(2)
        }
        let prefix = r.read(6)
        guard prefix.count == 6, let plen = r.u8(), let txtType = r.u8(), let ts = r.u32() else { return nil }
        let (len, _) = decodePathLength(plen)
        var sig: [UInt8]?
        if txtType == 2 { let s = r.read(4); guard s.count == 4 else { return nil }; sig = s }
        return ReceivedMessage(source: .contact(publicKeyPrefix: prefix), snr: snr, pathLength: len,
                               textType: txtType, senderTimestamp: ts, signature: sig, text: r.restString())
    }

    static func parseChannelMessage(_ r: inout ByteReader, v3: Bool) -> ReceivedMessage? {
        var snr: Double?
        if v3 {
            guard let s = r.i8() else { return nil }
            snr = Double(s) / 4
            r.skip(2)
        }
        guard let idx = r.u8(), let plen = r.u8(), let txtType = r.u8(), let ts = r.u32() else { return nil }
        let (len, _) = decodePathLength(plen)
        return ReceivedMessage(source: .channel(index: idx), snr: snr, pathLength: len,
                               textType: txtType, senderTimestamp: ts, signature: nil, text: r.restString())
    }
}
