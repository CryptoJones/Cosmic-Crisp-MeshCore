import SwiftUI
import MapKit
import MeshCoreKit

struct MapView: View {
    @Environment(NodeSession.self) private var node

    var body: some View {
        Map {
            if let s = node.selfInfo, s.latitude != 0 || s.longitude != 0 {
                Marker(s.name, systemImage: "iphone.radiowaves.left.and.right",
                       coordinate: .init(latitude: s.latitude, longitude: s.longitude)).tint(.blue)
            }
            ForEach(node.contacts.filter { $0.latitude != 0 || $0.longitude != 0 }) { c in
                Marker(c.name, systemImage: c.kind == .repeater ? "antenna.radiowaves.left.and.right" : "person",
                       coordinate: .init(latitude: c.latitude, longitude: c.longitude))
                    .tint(c.kind == .repeater ? .orange : .green)
            }
        }
        .navigationTitle("Map")
    }
}
