import Foundation

/// How a wind direction was arrived at. Shown in the UI because a hand-entered
/// wind and one averaged over ten minutes of upwind sailing deserve very
/// different amounts of trust.
public enum WindSource: String, Sendable, Codable, CaseIterable {
    case manual
    case headToWind
    case tackAverage

    public var label: String {
        switch self {
        case .manual: "Manual"
        case .headToWind: "Head to wind"
        case .tackAverage: "Tack average"
        }
    }
}

/// True wind. `direction` follows the sailing convention: the direction the
/// wind is coming *from*.
public struct Wind: Sendable, Hashable, Codable {
    public var direction: Bearing
    /// True wind speed in meters per second, when known.
    public var speed: Double?
    public var source: WindSource
    public var updatedAt: Date

    public init(
        direction: Bearing,
        speed: Double? = nil,
        source: WindSource = .manual,
        updatedAt: Date = Date()
    ) {
        self.direction = direction
        self.speed = speed
        self.source = source
        self.updatedAt = updatedAt
    }

    public var speedInKnots: Double? { speed.map { $0.knots } }

    /// Point the bow straight into the wind and tap: heading is the wind direction.
    public static func headToWind(heading: Bearing, at date: Date = Date()) -> Wind {
        Wind(direction: heading, source: .headToWind, updatedAt: date)
    }

    /// Wind direction from close-hauled headings on both tacks. The bisector of
    /// the two is the wind, and it cancels out whatever tacking angle the boat
    /// happens to sail — no polars required.
    ///
    /// Returns `nil` if the two headings are not plausibly opposite tacks: a
    /// sane tacking angle is somewhere between 45° and 135° of total separation.
    public static func fromCloseHauled(
        port: Bearing,
        starboard: Bearing,
        at date: Date = Date()
    ) -> Wind? {
        let separation = port.separation(to: starboard)
        guard (45.0...135.0).contains(separation) else { return nil }
        guard let mean = Bearing.mean([port, starboard]) else { return nil }
        return Wind(direction: mean, source: .tackAverage, updatedAt: date)
    }
}
