import Foundation

/// A compass bearing in degrees true, always normalized to `[0, 360)`.
///
/// Sailing math mixes degrees and radians constantly, and wraparound at north is
/// the classic source of bugs (averaging 359° and 1° must give 0°, not 180°).
/// Wrapping the value in a type keeps that arithmetic in one place.
public struct Bearing: Sendable, Hashable, Codable {
    /// Normalized to `[0, 360)`.
    public let degrees: Double

    public init(degrees: Double) {
        self.degrees = Bearing.normalize(degrees)
    }

    public init(radians: Double) {
        self.init(degrees: radians * 180 / .pi)
    }

    public var radians: Double { degrees * .pi / 180 }

    /// The opposite bearing. Wind blowing *from* 030 is blowing *toward* 210.
    public var reciprocal: Bearing { Bearing(degrees: degrees + 180) }

    /// Signed angle from `self` to `other`, in `(-180, 180]`.
    ///
    /// Positive means `other` is clockwise (to the right) of `self`.
    public func delta(to other: Bearing) -> Double {
        var d = (other.degrees - degrees).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d <= -180 { d += 360 }
        return d
    }

    /// Unsigned separation between two bearings, in `[0, 180]`.
    public func separation(to other: Bearing) -> Double { abs(delta(to: other)) }

    public static func + (lhs: Bearing, rhs: Double) -> Bearing {
        Bearing(degrees: lhs.degrees + rhs)
    }

    public static func - (lhs: Bearing, rhs: Double) -> Bearing {
        Bearing(degrees: lhs.degrees - rhs)
    }

    /// Circular (vector) mean. Returns `nil` for an empty input, or when the
    /// bearings cancel out so completely that no mean is meaningful.
    public static func mean(_ bearings: [Bearing]) -> Bearing? {
        guard !bearings.isEmpty else { return nil }
        var sinSum = 0.0
        var cosSum = 0.0
        for b in bearings {
            sinSum += sin(b.radians)
            cosSum += cos(b.radians)
        }
        guard hypot(sinSum, cosSum) > 1e-9 else { return nil }
        return Bearing(radians: atan2(sinSum, cosSum))
    }

    /// Normalizes any degree value into `[0, 360)`.
    public static func normalize(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return 0 }
        let r = degrees.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}

extension Bearing: CustomStringConvertible {
    /// Three-digit compass notation, the way it is spoken on the water: `047°`.
    public var description: String { String(format: "%03.0f°", degrees.rounded()) }
}

extension Bearing {
    /// Eight-point compass label, for at-a-glance reading on a small screen.
    public var cardinal: String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((degrees / 45).rounded()) % 8
        return points[index]
    }
}
