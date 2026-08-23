#if canImport(CoreLocation)
import CoreLocation

/// The one place CoreLocation touches the racing model. Everything downstream
/// works in `Coordinate` and `BoatFix`, which keeps the math testable off-device.
extension Coordinate {
    public init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    public var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension BoatFix {
    /// CoreLocation reports a negative course and speed rather than an optional
    /// when it has nothing; those become `nil` and "unknown" here so the rest of
    /// the app never has to remember the sentinel.
    public init(_ location: CLLocation) {
        self.init(
            coordinate: Coordinate(location.coordinate),
            course: location.course >= 0 ? Bearing(degrees: location.course) : nil,
            speed: location.speed,
            timestamp: location.timestamp,
            horizontalAccuracy: location.horizontalAccuracy
        )
    }
}
#endif
