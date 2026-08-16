import Foundation
import CoreLocation

enum Geo {
    /// Great-circle distance in metres.
    static func distance(from a: (Double, Double), to b: (Double, Double)) -> CLLocationDistance {
        CLLocation(latitude: a.0, longitude: a.1).distance(from: CLLocation(latitude: b.0, longitude: b.1))
    }

    /// Initial bearing in degrees (0 = north, clockwise).
    static func bearing(from a: (Double, Double), to b: (Double, Double)) -> Double {
        let lat1 = a.0 * .pi / 180, lat2 = b.0 * .pi / 180
        let dLon = (b.1 - a.1) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func compass(_ deg: Double) -> String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((deg + 22.5) / 45) % 8]
    }

    static func formatDistance(_ m: Double) -> String {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 1
        return f.string(from: Measurement(value: m, unit: UnitLength.meters))
    }

    static func hasPosition(_ lat: Double, _ lon: Double) -> Bool { !(lat == 0 && lon == 0) }
}
