import Foundation

/// How far the start line is skewed from square to the wind, and what that is
/// worth in distance.
public struct LineBias: Sendable, Hashable {
    /// Signed skew from square, in degrees. Positive means the pin end is
    /// further upwind (pin favored); negative means the committee boat is.
    public var degrees: Double
    /// The end worth starting at, or `nil` when the line is square within the
    /// accuracy of the pings.
    public var favoredEnd: LineEnd?
    /// Upwind distance gained by starting at the favored end, in meters.
    public var advantage: Double
    public var lineLength: Double
    /// Rough angular uncertainty from GPS error at the two pings, in degrees.
    ///
    /// A short line pinged with sloppy accuracy simply cannot resolve a small
    /// bias, and the app should say so rather than inventing a favored end.
    public var uncertainty: Double

    /// Whether the measured bias is larger than the error in measuring it.
    public var isSignificant: Bool { abs(degrees) > uncertainty }

    public func advantageInBoatLengths(_ boatLength: Double) -> Double {
        Units.boatLengths(meters: advantage, boatLength: boatLength)
    }
}

extension StartLine {
    /// Default assumed ping accuracy when the fix did not report one.
    static let assumedPingAccuracy = 5.0

    /// Computes line bias for a given true wind direction.
    ///
    /// A line square to the wind runs `wind + 90` from pin to committee boat.
    /// Everything here is the signed departure from that.
    public func bias(wind: Bearing) -> LineBias? {
        guard let axis, let length, length > 0 else { return nil }

        let squareAxis = Bearing(degrees: wind.degrees + 90)
        let skew = squareAxis.delta(to: axis)

        let pinAccuracy = (pin?.accuracy ?? -1) > 0 ? pin!.accuracy : StartLine.assumedPingAccuracy
        let boatAccuracy = (boat?.accuracy ?? -1) > 0 ? boat!.accuracy : StartLine.assumedPingAccuracy
        let positionError = (pinAccuracy * pinAccuracy + boatAccuracy * boatAccuracy).squareRoot()
        let uncertainty = atan2(positionError, length) * 180 / .pi

        let advantage = length * abs(sin(skew * .pi / 180))

        let favored: LineEnd?
        if abs(skew) <= uncertainty {
            favored = nil
        } else {
            favored = skew > 0 ? .pin : .boat
        }

        return LineBias(
            degrees: skew,
            favoredEnd: favored,
            advantage: advantage,
            lineLength: length,
            uncertainty: uncertainty
        )
    }
}
