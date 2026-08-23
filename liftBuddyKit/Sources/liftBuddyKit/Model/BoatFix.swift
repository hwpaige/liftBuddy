import Foundation

/// One GPS sample, already stripped of CoreLocation.
public struct BoatFix: Sendable, Hashable, Codable {
    public var coordinate: Coordinate
    /// Course over ground. `nil` when the receiver could not resolve one —
    /// which is normal when sitting still, since COG is derived from motion.
    public var course: Bearing?
    /// Speed over ground, meters per second. Negative means unknown.
    public var speed: Double
    public var timestamp: Date
    /// Horizontal accuracy in meters; negative means invalid.
    public var horizontalAccuracy: Double

    public init(
        coordinate: Coordinate,
        course: Bearing? = nil,
        speed: Double = -1,
        timestamp: Date = Date(),
        horizontalAccuracy: Double = -1
    ) {
        self.coordinate = coordinate
        self.course = course
        self.speed = speed
        self.timestamp = timestamp
        self.horizontalAccuracy = horizontalAccuracy
    }

    /// Below roughly half a knot, GPS course over ground is noise. Anything
    /// steering off COG has to gate on this.
    public static let courseValidSpeedThreshold = Units.metersPerSecond(fromKnots: 0.5)

    public var hasUsableCourse: Bool {
        course != nil && speed >= BoatFix.courseValidSpeedThreshold
    }

    public var speedInKnots: Double { speed > 0 ? speed.knots : 0 }

    /// The watch is on a wrist somewhere amidships, but what crosses the line
    /// is the bow. Projects the fix forward along the course by `meters`.
    ///
    /// Returns the raw coordinate unchanged when there is no trustworthy
    /// course to project along — better a known small error than a wild guess.
    public func projectedToBow(_ meters: Double) -> Coordinate {
        guard meters > 0, hasUsableCourse, let course else { return coordinate }
        return coordinate.offset(bearing: course, distance: meters)
    }
}
