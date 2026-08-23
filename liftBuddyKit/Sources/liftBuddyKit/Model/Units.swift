import Foundation

/// Everything internal is SI (meters, meters/second, seconds). Sailors are not,
/// so conversions live here rather than being sprinkled through view code.
public enum Units {
    public static let metersPerNauticalMile = 1852.0
    public static let metersPerFoot = 0.3048

    public static func knots(fromMetersPerSecond mps: Double) -> Double {
        mps * 3600 / metersPerNauticalMile
    }

    public static func metersPerSecond(fromKnots knots: Double) -> Double {
        knots * metersPerNauticalMile / 3600
    }

    public static func boatLengths(meters: Double, boatLength: Double) -> Double {
        guard boatLength > 0 else { return 0 }
        return meters / boatLength
    }
}

extension Double {
    /// Reads as speed in knots, assuming the receiver is meters per second.
    public var knots: Double { Units.knots(fromMetersPerSecond: self) }
}
