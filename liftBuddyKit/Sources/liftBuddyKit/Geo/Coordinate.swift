import Foundation

/// A WGS-84 position. Deliberately independent of CoreLocation so the racing
/// math stays testable on any platform.
///
/// All distance and bearing work here goes through `LocalPlane`, the same
/// tangent-plane model the line geometry uses. Sharing one earth model means
/// `offset` and `distance` are exact inverses of each other, which matters more
/// than absolute geodetic precision: everything this app measures is a relative
/// distance between two points a few hundred meters apart, and mixing a
/// spherical model with an ellipsoidal one put a quarter-percent disagreement
/// between the two. The flat-earth approximation is good to centimeters over a
/// race course and should not be used past a few tens of kilometers.
public struct Coordinate: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}

extension Coordinate {
    /// Distance in meters.
    public func distance(to other: Coordinate) -> Double {
        LocalPlane(origin: self).project(other).magnitude
    }

    /// Bearing from `self` to `other`.
    public func bearing(to other: Coordinate) -> Bearing {
        LocalPlane(origin: self).project(other).bearing
    }

    /// The point `distance` meters away along `bearing`.
    public func offset(bearing: Bearing, distance: Double) -> Coordinate {
        LocalPlane(origin: self).unproject(PlanePoint.unit(bearing) * distance)
    }
}
