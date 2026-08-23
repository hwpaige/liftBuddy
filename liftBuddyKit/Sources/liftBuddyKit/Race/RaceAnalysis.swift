import Foundation

/// How the start went.
///
/// This is the one part of a race worth reviewing in detail, because it is the
/// only part you can rehearse. Everything here is measured at the gun.
public struct StartAnalysis: Sendable, Hashable {
    /// Meters to the line at the gun. Negative means over.
    public var distanceToLine: Double
    /// Speed over ground at the gun, m/s.
    public var speed: Double
    /// Where along the line, 0 at the pin and 1 at the committee boat.
    public var positionAlongLine: Double
    public var wasOver: Bool
    /// Seconds after the gun that the line was actually crossed. `nil` if the
    /// track never crosses — either already over, or it stops too soon.
    public var timeToCross: TimeInterval?
    /// The end the wind favoured, if the line and wind were both recorded.
    public var favoredEnd: LineEnd?

    /// Which half of the line the start was made in.
    public var endStartedAt: LineEnd { positionAlongLine < 0.5 ? .pin : .boat }

    /// Whether the start was made at the favoured end. `nil` when the line was
    /// square, or bias could not be computed.
    public var startedAtFavoredEnd: Bool? {
        guard let favoredEnd else { return nil }
        return endStartedAt == favoredEnd
    }

    public var speedInKnots: Double { speed.knots }
}

/// Whole-race numbers.
///
/// Everything here covers the race itself — from the gun to the finish. The
/// prestart is recorded and drawn, but distance spent circling before the start
/// is not distance raced, and counting it makes the average speed a fiction.
public struct RaceStatistics: Sendable, Hashable {
    public var duration: TimeInterval
    /// Distance through the water from the gun, in meters.
    public var distanceSailed: Double
    public var maximumSpeed: Double
    public var averageSpeed: Double
    public var tacks: Int
    public var gybes: Int

    public var maximumSpeedInKnots: Double { maximumSpeed.knots }
    public var averageSpeedInKnots: Double { averageSpeed.knots }
    public var maneuvers: Int { tacks + gybes }
}

extension RaceRecord {
    /// Grades the start against the line as it was recorded.
    public var startAnalysis: StartAnalysis? {
        guard let line, line.isSurveyed else { return nil }
        // The fix nearest the gun, from either side of it.
        guard let atGun = track.min(by: { abs($0.time) < abs($1.time) }) else { return nil }

        let fix = BoatFix(
            coordinate: atGun.coordinate,
            course: atGun.course,
            speed: atGun.speed,
            timestamp: startedAt
        )
        guard let approach = line.approach(from: fix) else { return nil }

        // The first moment after the gun the boat is on the course side.
        var crossing: TimeInterval?
        if !approach.isOverEarly {
            for point in track where point.time >= 0 {
                let sample = BoatFix(
                    coordinate: point.coordinate, course: point.course, speed: point.speed)
                if line.approach(from: sample)?.isOverEarly == true {
                    crossing = point.time
                    break
                }
            }
        }

        return StartAnalysis(
            distanceToLine: approach.perpendicularDistance,
            speed: max(atGun.speed, 0),
            positionAlongLine: approach.positionAlongLine,
            wasOver: approach.isOverEarly,
            timeToCross: crossing,
            favoredEnd: wind.flatMap { line.bias(wind: $0.direction) }?.favoredEnd
        )
    }

    /// Distance, speed and how many times the boat was turned through the wind.
    public var statistics: RaceStatistics {
        // Measured over the racing track only, so it is consistent with
        // `duration`, which runs from the gun.
        let racing = racingTrack
        var distance = 0.0
        var maximum = 0.0
        for (previous, current) in zip(racing, racing.dropFirst()) {
            distance += previous.coordinate.distance(to: current.coordinate)
            maximum = max(maximum, current.speed)
        }
        maximum = max(maximum, racing.first?.speed ?? 0)
        let elapsed = duration
        let maneuvers = RaceRecord.countManeuvers(track: racing, wind: wind?.direction)

        return RaceStatistics(
            duration: elapsed,
            distanceSailed: distance,
            maximumSpeed: maximum,
            averageSpeed: elapsed > 0 ? distance / elapsed : 0,
            tacks: maneuvers.tacks,
            gybes: maneuvers.gybes
        )
    }

    /// Counts tacks and gybes by watching which side of the wind the boat is on.
    ///
    /// A tack is turning the bow through the wind, a gybe the stern; both show
    /// up as the boat crossing from one side of the wind axis to the other, and
    /// what separates them is whether it was sailing toward the wind or away
    /// when it happened.
    ///
    /// The switch needs a healthy angle on the new side before it counts, so
    /// that a boat wandering either side of dead downwind does not register a
    /// gybe every few seconds.
    static func countManeuvers(
        track: [TrackPoint],
        wind: Bearing?
    ) -> (tacks: Int, gybes: Int) {
        guard let wind else { return (0, 0) }
        /// Degrees onto the new side before a crossing is believed.
        let hysteresis = 25.0
        var tacks = 0
        var gybes = 0
        var side = 0

        for point in track {
            guard let course = point.course,
                point.speed >= BoatFix.courseValidSpeedThreshold
            else { continue }
            let offWind = wind.delta(to: course)
            guard abs(offWind) > hysteresis, abs(offWind) < 180 - hysteresis else { continue }
            let newSide = offWind > 0 ? 1 : -1
            defer { side = newSide }
            guard side != 0, newSide != side else { continue }
            // Close to the wind means the bow went through it.
            if abs(offWind) < 90 {
                tacks += 1
            } else {
                gybes += 1
            }
        }
        return (tacks, gybes)
    }
}
