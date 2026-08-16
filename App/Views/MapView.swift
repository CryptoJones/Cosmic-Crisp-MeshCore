import SwiftUI
import MapKit
import MeshCoreKit

/// All positioned nodes on a map: own node (live GPS fix or advertised), contacts with
/// type-specific pins, tap for a detail popover, learned-path lines from us to a
/// contact when the hop hashes can be matched to known contacts.
struct MapView: View {
    @Environment(NodeSession.self) private var node
    @State private var camera: MapCameraPosition = .automatic
    @State private var selected: String?          // contact id
    @State private var showPaths = true
    @State private var showFlood = true
    @State private var showIPad = false
    @State private var ipadLocation: CLLocationCoordinate2D?
    private let locator = OneShotLocation()

    private var positioned: [Contact] { node.contacts.filter { Geo.hasPosition($0.latitude, $0.longitude) && (showFlood || $0.outPathLength >= 0) } }

    var body: some View {
        Map(position: $camera, selection: $selected) {
            if let me = node.selfPosition {
                Annotation(node.selfInfo?.name ?? "Me", coordinate: .init(latitude: me.0, longitude: me.1)) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.25)).frame(width: 44, height: 44)
                        Image(systemName: "iphone.radiowaves.left.and.right").foregroundStyle(.white).padding(8).background(Circle().fill(.blue))
                    }
                }
                .annotationTitles(.visible)
            }
            if showIPad, let loc = ipadLocation {
                Marker("iPad", systemImage: "ipad", coordinate: loc).tint(.gray)
            }
            ForEach(positioned) { c in
                Marker(c.name, systemImage: c.kind.icon, coordinate: .init(latitude: c.latitude, longitude: c.longitude))
                    .tint(c.kind.tint)
                    .tag(c.id)
            }
            if showPaths, let me = node.selfPosition {
                ForEach(positioned.filter { $0.outPathLength > 0 }) { c in
                    MapPolyline(coordinates: pathCoordinates(for: c, from: me))
                        .stroke(c.id == selected ? Color.orange : Color.blue.opacity(0.5),
                                style: StrokeStyle(lineWidth: c.id == selected ? 4 : 2, dash: [6, 4]))
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView(); MapUserLocationButton() }
        .overlay(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Paths", isOn: $showPaths)
                Toggle("Flood-only nodes", isOn: $showFlood)
                Toggle("iPad location", isOn: $showIPad)
                    .onChange(of: showIPad) { _, on in if on, ipadLocation == nil { Task { ipadLocation = await locator.request() } } }
                Button("Fit all") { fitAll() }
            }
            .toggleStyle(.switch).controlSize(.mini).font(.caption)
            .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10)).padding()
        }
        .overlay(alignment: .bottom) {
            if let id = selected, let c = node.contact(forHex: id) {
                MapContactCard(contact: c) { selected = nil }
                    .padding()
            }
        }
        .navigationTitle("Map")
        .navigationDestination(for: String.self) { ContactDetailView(publicKeyHex: $0) }
        .navigationDestination(for: ConversationKey.self) { ConversationView(key: $0) }
        .onAppear { fitAll() }
        .task { await node.refreshSelfTelemetry() }
    }

    private func fitAll() {
        var coords: [CLLocationCoordinate2D] = positioned.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
        if let me = node.selfPosition { coords.append(.init(latitude: me.0, longitude: me.1)) }
        guard !coords.isEmpty else { return }
        if coords.count == 1 { camera = .region(.init(center: coords[0], latitudinalMeters: 5000, longitudinalMeters: 5000)); return }
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.4, 0.02),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.4, 0.02))
        camera = .region(.init(center: center, span: span))
    }

    /// Us → each hop we can identify (by public-key hash prefix) → the contact.
    /// Unknown hops are skipped so the line still reaches the destination.
    private func pathCoordinates(for c: Contact, from me: (Double, Double)) -> [CLLocationCoordinate2D] {
        var pts: [CLLocationCoordinate2D] = [.init(latitude: me.0, longitude: me.1)]
        let hashLen = max(1, c.outPathHashMode + 1)
        for hop in stride(from: 0, to: c.outPath.count, by: hashLen).map({ Array(c.outPath[$0..<min($0 + hashLen, c.outPath.count)]) }) {
            if let n = node.contacts.first(where: { $0.publicKey.starts(with: hop) && Geo.hasPosition($0.latitude, $0.longitude) }) {
                pts.append(.init(latitude: n.latitude, longitude: n.longitude))
            }
        }
        pts.append(.init(latitude: c.latitude, longitude: c.longitude))
        return pts
    }
}

struct MapContactCard: View {
    @Environment(NodeSession.self) private var node
    let contact: Contact
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: contact.kind.icon).font(.title2).foregroundStyle(contact.kind.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name).font(.headline)
                HStack(spacing: 8) {
                    Text(contact.kind.label)
                    Text(contact.outPathLength < 0 ? "flood" : "\(contact.outPathLength) hop\(contact.outPathLength == 1 ? "" : "s")")
                    if let me = node.selfPosition {
                        let d = Geo.distance(from: me, to: (contact.latitude, contact.longitude))
                        Text("\(Geo.formatDistance(d)) \(Geo.compass(Geo.bearing(from: me, to: (contact.latitude, contact.longitude))))")
                    }
                    if contact.lastAdvert > 0 { Text(Date(timeIntervalSince1970: Double(contact.lastAdvert)), style: .relative) + Text(" ago") }
                }
                .font(.caption).foregroundStyle(.secondary)
                HStack {
                    NavigationLink("Details", value: contact.id).buttonStyle(.bordered).controlSize(.small)
                    if contact.kind == .chat || contact.kind == .room {
                        NavigationLink("Message", value: ConversationKey.contact(publicKeyHex: contact.id)).buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .frame(maxWidth: 520)
    }
}
