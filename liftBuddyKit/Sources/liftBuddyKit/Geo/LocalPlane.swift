import Foundation

/// A point on a local tangent plane, in meters east and north of an origin.
public struct PlanePoint: Sendable, Hashable {
    public var east: Double
    public var north: Double

    public init(east: Double, north: Double) {
        self.east = east
        self.north = north
    }

    public static let zero = PlanePoint(east: 0, north: 0)

    public var magnitude: Double { hypot(east, north) }

    /// Bearing of this point as seen from the plane origin.
    public var bearing: Bearing { Bearing(radians: atan2(east, north)) }

    public static func - (lhs: PlanePoint, rhs: PlanePoint) -> PlanePoint {
        PlanePoint(east: lhs.east - rhs.east, north: lhs.north - rhs.north)
    }

    public static func + (lhs: PlanePoint, rhs: PlanePoint) -> PlanePoint {
        PlanePoint(east: lhs.east + rhs.east, north: lhs.north + rhs.north)
    }

    public static func * (lhs: PlanePoint, rhs: Double) -> PlanePoint {
        PlanePoint(east: lhs.east * rhs, north: lhs.north * rhs)
    }

    public func dot(_ other: PlanePoint) -> Double {
        east * other.east + north * other.north
    }

    /// Unit vector pointing along `bearing`.
    public static func unit(_ bearing: Bearing) -> PlanePoint {
        PlanePoint(east: sin(bearing.radians), north: cos(bearing.radians))
    }

    /// This vector rotated 90° counter-clockwise (to port).
    public var rotatedLeft: PlanePoint { PlanePoint(east: -north, north: east) }

    /// This vector rotated 90° clockwise (to starboard).
    public var rotatedRight: PlanePoint { PlanePoint(east: north, north: -east) }
}

/// An equirectangular tangent-plane projection anchored at `origin`.
///
/// A race course spans a kilometre or two at most, where the error from
/// treating the earth as flat is well under the GPS noise floor — and planar
/// vector math makes line geometry far easier to reason about than spherical
/// trigonometry.
public struct LocalPlane: Sendable {
    public let origin: Coordinate
    private let metersPerDegreeLatitude: Double
    private let metersPerDegreeLongitude: Double

    public init(origin: Coordinate) {
        self.origin = origin
        let lat = origin.latitude * .pi / 180
        // WGS-84 meridian/parallel scale at this latitude.
        self.metersPerDegreeLatitude =
            111_132.92 - 559.82 * cos(2 * lat) + 1.175 * cos(4 * lat) - 0.0023 * cos(6 * lat)
        self.metersPerDegreeLongitude =
            111_412.84 * cos(lat) - 93.5 * cos(3 * lat) + 0.118 * cos(5 * lat)
    }

    public func project(_ coordinate: Coordinate) -> PlanePoint {
        PlanePoint(
            east: (coordinate.longitude - origin.longitude) * metersPerDegreeLongitude,
            north: (coordinate.latitude - origin.latitude) * metersPerDegreeLatitude
        )
    }

    public func unproject(_ point: PlanePoint) -> Coordinate {
        Coordinate(
            latitude: origin.latitude + point.north / metersPerDegreeLatitude,
            longitude: origin.longitude + point.east / metersPerDegreeLongitude
        )
    }
}
