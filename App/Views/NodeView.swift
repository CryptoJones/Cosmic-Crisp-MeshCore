import SwiftUI
import MapKit
import CoreLocation
import MeshCoreKit

struct NodeView: View {
    @Environment(NodeSession.self) private var node
    @State private var newName = ""
    @State private var showRadio = false
    @State private var showPosition = false
    @State private var showPIN = false
    @State private var confirmReboot = false

    var body: some View {
        Form {
            if let s = node.selfInfo {
                Section("Identity") {
                    LabeledContent("Name", value: s.name)
                    LabeledContent("Public key") {
                        Text(s.publicKeyHex).font(.system(.caption2, design: .monospaced)).textSelection(.enabled).multilineTextAlignment(.trailing)
                    }
                    HStack {
                        TextField("New name", text: $newName)
                        Button("Rename") { Task { await node.setName(newName); newName = "" } }
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                Section {
                    LabeledContent("Frequency", value: String(format: "%.3f MHz", s.radioFrequencyMHz))
                    LabeledContent("Bandwidth", value: String(format: "%.1f kHz", s.radioBandwidthKHz))
                    LabeledContent("Spreading factor", value: "\(s.spreadingFactor)")
                    LabeledContent("Coding rate", value: "4/\(s.codingRate)")
                    LabeledContent("TX power", value: "\(s.txPower) / \(s.maxTxPower) dBm")
                    Button("Edit radio settings…") { showRadio = true }
                } header: { Text("Radio") } footer: {
                    Text("Everyone on your mesh must use the same frequency, bandwidth, SF and CR.")
                }
                Section("Position & adverts") {
                    LabeledContent("Advertised", value: Geo.hasPosition(s.latitude, s.longitude) ? String(format: "%.5f, %.5f", s.latitude, s.longitude) : "not set")
                    if let fix = gpsFix { LabeledContent("GPS fix", value: fix) }
                    Button("Set position…") { showPosition = true }
                    Toggle("Share position in adverts", isOn: Binding(get: { s.advertLocationPolicy == 1 },
                                                                     set: { on in Task { await node.setOtherParams(advertLocationPolicy: on ? 1 : 0) } }))
                    Toggle("GPS receiver", isOn: Binding(get: { node.gpsEnabled }, set: { on in Task { await node.setGPS(on) } }))
                    Button("Send advert (zero hop)") { Task { await node.sendAdvert(flood: false) } }
                    Button("Send advert (flood)") { Task { await node.sendAdvert(flood: true) } }
                }
                Section("Behaviour") {
                    Toggle("Manually approve new contacts", isOn: Binding(get: { s.manualAddContacts },
                                                                       set: { on in Task { await node.setOtherParams(manualAddContacts: on) } }))
                    Toggle("Multi-ACK (ACK repeats)", isOn: Binding(get: { s.multiAcks > 0 },
                                                                    set: { on in Task { await node.setOtherParams(multiAcks: on ? 1 : 0) } }))
                    telemetryPicker("Telemetry: base", value: s.telemetryModeBase) { v in Task { await node.setOtherParams(telemetryBase: v) } }
                    telemetryPicker("Telemetry: location", value: s.telemetryModeLoc) { v in Task { await node.setOtherParams(telemetryLoc: v) } }
                    telemetryPicker("Telemetry: environment", value: s.telemetryModeEnv) { v in Task { await node.setOtherParams(telemetryEnv: v) } }
                }
            }
            Section("Sensors") {
                if let t = node.selfTelemetry, !t.records.isEmpty {
                    ForEach(Array(t.records.enumerated()), id: \.offset) { _, r in
                        LabeledContent(r.value.label, value: r.value.text)
                    }
                } else if let b = node.battery {
                    LabeledContent("Battery", value: String(format: "%.2f V", Double(b.millivolts) / 1000))
                }
                Button("Refresh sensors") { Task { await node.refreshSelfTelemetry(); await node.refreshBattery() } }
            }
            Section("Statistics") {
                if case .core(let mv, let up, let err, let q)? = node.stats.core {
                    LabeledContent("Battery", value: String(format: "%.2f V", Double(mv) / 1000))
                    LabeledContent("Uptime", value: Duration.seconds(Int(up)).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated)))
                    LabeledContent("Errors / queue", value: "\(err) / \(q)")
                }
                if case .radio(let nf, let rssi, let snr, let tx, let rx)? = node.stats.radio {
                    LabeledContent("Noise floor", value: "\(nf) dBm")
                    LabeledContent("Last RSSI / SNR", value: "\(rssi) dBm / \(String(format: "%.1f", snr)) dB")
                    LabeledContent("Airtime TX / RX", value: "\(tx) s / \(rx) s")
                }
                if case .packets(let recv, let sent, let ftx, let dtx, let frx, let drx, let errs)? = node.stats.packets {
                    LabeledContent("Packets RX / TX", value: "\(recv) / \(sent)")
                    LabeledContent("Flood TX / direct TX", value: "\(ftx) / \(dtx)")
                    LabeledContent("Flood RX / direct RX", value: "\(frx) / \(drx)")
                    if let errs { LabeledContent("RX errors", value: "\(errs)") }
                }
                Button("Refresh statistics") { Task { await node.refreshStats() } }
            }
            Section("Device") {
                if let d = node.deviceInfo {
                    LabeledContent("Firmware", value: "\(d.version ?? "?") (protocol v\(d.firmwareVersion))")
                    LabeledContent("Model", value: d.model ?? "?")
                    LabeledContent("Build", value: d.firmwareBuild ?? "?")
                    if let mc = d.maxContacts, let ch = d.maxChannels { LabeledContent("Capacity", value: "\(mc) contacts · \(ch) channels") }
                }
                LabeledContent("Node clock", value: node.deviceTime.map { $0.formatted(date: .abbreviated, time: .standard) } ?? "—")
                Button("Sync clock from iPad") { Task { await node.syncTime() } }
                Button("Set Bluetooth PIN…") { showPIN = true }
                Button("Reboot node", role: .destructive) { confirmReboot = true }
            }
            if let err = node.lastError {
                Section("Last error") { Text(err).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Node")
        .task { await node.refreshDeviceTime(); await node.refreshStats() }
        .sheet(isPresented: $showRadio) { NavigationStack { RadioSettingsView() } }
        .sheet(isPresented: $showPosition) { NavigationStack { PositionPickerView() } }
        .sheet(isPresented: $showPIN) { NavigationStack { PINView() } }
        .confirmationDialog("Reboot the node?", isPresented: $confirmReboot, titleVisibility: .visible) {
            Button("Reboot", role: .destructive) { Task { await node.reboot() } }
        }
    }

    private var gpsFix: String? {
        node.selfTelemetry?.records.compactMap { r -> String? in
            if case .location(let la, let lo, let alt) = r.value, Geo.hasPosition(la, lo) { return String(format: "%.5f, %.5f · %.0f m", la, lo, alt) }
            return nil
        }.first
    }

    private func telemetryPicker(_ title: String, value: UInt8, set: @escaping (UInt8) -> Void) -> some View {
        Picker(title, selection: Binding(get: { value }, set: set)) {
            Text("Off").tag(UInt8(0)); Text("Selected").tag(UInt8(1)); Text("All").tag(UInt8(2))
        }
    }
}

extension LPPRecord.Value {
    var label: String {
        switch self {
        case .voltage: "Battery"
        case .temperature: "Temperature"
        case .humidity: "Humidity"
        case .barometer: "Pressure"
        case .illuminance: "Light"
        case .percentage: "Level"
        case .altitude: "Altitude"
        case .power: "Power"
        case .current: "Current"
        case .analogInput: "Analog"
        case .digitalInput: "Digital"
        case .presence: "Presence"
        case .genericSensor: "Sensor"
        case .location: "GPS"
        }
    }
    var text: String {
        switch self {
        case .voltage(let v): String(format: "%.2f V", v)
        case .temperature(let v): String(format: "%.1f °C", v)
        case .humidity(let v): String(format: "%.0f %%", v)
        case .barometer(let v): String(format: "%.1f hPa", v)
        case .illuminance(let v): String(format: "%.0f lux", v)
        case .percentage(let v): String(format: "%.0f %%", v)
        case .altitude(let v): String(format: "%.0f m", v)
        case .power(let v): String(format: "%.0f W", v)
        case .current(let v): String(format: "%.3f A", v)
        case .analogInput(let v): String(format: "%.2f", v)
        case .digitalInput(let v): "\(v)"
        case .presence(let v): "\(v)"
        case .genericSensor(let v): "\(v)"
        case .location(let la, let lo, let alt): String(format: "%.4f, %.4f · %.0f m", la, lo, alt)
        }
    }
}

/// Radio parameters with the common regional presets.
struct RadioSettingsView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    @State private var freq: Double = 910.525
    @State private var bw: Double = 62.5
    @State private var sf: Int = 7
    @State private var cr: Int = 5
    @State private var tx: Int = 22

    struct Preset: Identifiable { let id = UUID(); let name: String; let freq: Double; let bw: Double; let sf: Int; let cr: Int }
    static let presets: [Preset] = [
        .init(name: "USA / Canada (Recommended)", freq: 910.525, bw: 62.5, sf: 7, cr: 5),
        .init(name: "USA / Canada (Narrow)", freq: 910.525, bw: 62.5, sf: 7, cr: 5),
        .init(name: "USA / Canada (Fast)", freq: 906.875, bw: 250, sf: 10, cr: 5),
        .init(name: "EU / UK (869.618)", freq: 869.618, bw: 250, sf: 11, cr: 5),
        .init(name: "EU / UK (869.525)", freq: 869.525, bw: 62.5, sf: 8, cr: 8),
        .init(name: "Australia / NZ", freq: 915.8, bw: 250, sf: 10, cr: 5),
    ]

    var body: some View {
        Form {
            Section("Preset") {
                ForEach(Self.presets) { p in
                    Button { freq = p.freq; bw = p.bw; sf = p.sf; cr = p.cr } label: {
                        HStack { Text(p.name); Spacer(); Text(String(format: "%.3f / %g / %d / %d", p.freq, p.bw, p.sf, p.cr)).font(.caption).foregroundStyle(.secondary) }
                    }.tint(.primary)
                }
            }
            Section("Parameters") {
                HStack { Text("Frequency (MHz)"); Spacer(); TextField("MHz", value: $freq, format: .number.precision(.fractionLength(3))).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 120) }
                Picker("Bandwidth (kHz)", selection: $bw) { ForEach([7.8, 10.4, 15.6, 20.8, 31.25, 41.7, 62.5, 125.0, 250.0, 500.0], id: \.self) { Text("\($0.formatted())").tag($0) } }
                Stepper("Spreading factor: \(sf)", value: $sf, in: 5...12)
                Stepper("Coding rate: 4/\(cr)", value: $cr, in: 5...8)
                Stepper("TX power: \(tx) dBm", value: $tx, in: 0...Int(node.selfInfo?.maxTxPower ?? 22))
            }
            Section { Text("Applying radio settings takes effect immediately; a mismatch with your mesh makes the node deaf. Presets follow MeshCore's regional defaults.").font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle("Radio")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    Task {
                        await node.setRadio(freqMHz: freq, bwKHz: bw, sf: UInt8(sf), cr: UInt8(cr))
                        if UInt8(tx) != node.selfInfo?.txPower { await node.setTxPower(UInt8(tx)) }
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            if let s = node.selfInfo { freq = s.radioFrequencyMHz; bw = s.radioBandwidthKHz; sf = Int(s.spreadingFactor); cr = Int(s.codingRate); tx = Int(s.txPower) }
        }
    }
}

/// Pick the advertised position: drop a pin on the map, use the node's GPS fix, or the iPad's location.
struct PositionPickerView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic
    @State private var locating = false
    private let locator = OneShotLocation()

    var body: some View {
        VStack(spacing: 0) {
            MapReader { proxy in
                Map(position: $camera) {
                    if let c = coordinate { Marker("Advertised position", systemImage: "mappin", coordinate: c).tint(.blue) }
                }
                .onTapGesture { pt in if let c = proxy.convert(pt, from: .local) { coordinate = c } }
            }
            HStack {
                if let c = coordinate { Text(String(format: "%.5f, %.5f", c.latitude, c.longitude)).font(.system(.caption, design: .monospaced)) }
                Spacer()
                if let fix = nodeFix { Button("Use node GPS") { coordinate = fix; camera = .region(.init(center: fix, latitudinalMeters: 2000, longitudinalMeters: 2000)) } }
                Button(locating ? "Locating…" : "Use iPad location") {
                    locating = true
                    Task { if let c = await locator.request() { coordinate = c; camera = .region(.init(center: c, latitudinalMeters: 2000, longitudinalMeters: 2000)) }; locating = false }
                }.disabled(locating)
            }
            .padding().background(.bar)
        }
        .navigationTitle("Set position")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if let c = coordinate { Task { await node.setAdvertLocation(lat: c.latitude, lon: c.longitude); dismiss() } } }.disabled(coordinate == nil)
            }
        }
        .onAppear {
            if let s = node.selfInfo, Geo.hasPosition(s.latitude, s.longitude) {
                coordinate = .init(latitude: s.latitude, longitude: s.longitude)
                camera = .region(.init(center: coordinate!, latitudinalMeters: 5000, longitudinalMeters: 5000))
            } else if let fix = nodeFix { coordinate = fix; camera = .region(.init(center: fix, latitudinalMeters: 5000, longitudinalMeters: 5000)) }
        }
    }

    private var nodeFix: CLLocationCoordinate2D? {
        node.selfTelemetry?.records.compactMap { r -> CLLocationCoordinate2D? in
            if case .location(let la, let lo, _) = r.value, Geo.hasPosition(la, lo) { return .init(latitude: la, longitude: lo) }; return nil
        }.first
    }
}

/// One-shot CoreLocation request.
final class OneShotLocation: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    func request() async -> CLLocationCoordinate2D? {
        await withCheckedContinuation { cont in
            continuation = cont
            manager.delegate = self
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestLocation() }
        }
    }
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.requestLocation()
        case .denied, .restricted: continuation?.resume(returning: nil); continuation = nil
        default: break
        }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        continuation?.resume(returning: locs.last?.coordinate); continuation = nil
    }
    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil); continuation = nil
    }
}

struct PINView: View {
    @Environment(NodeSession.self) private var node
    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    var body: some View {
        Form {
            Section {
                TextField("6-digit PIN (0 to disable)", text: $pin).keyboardType(.numberPad)
            } footer: { Text("Used by the Bluetooth companion firmware for pairing. Harmless on the USB build; kept for parity.") }
        }
        .navigationTitle("Bluetooth PIN")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { if let v = UInt32(pin) { Task { await node.setDevicePIN(v); dismiss() } } }.disabled(UInt32(pin) == nil)
            }
        }
    }
}
