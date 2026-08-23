import Testing
import Foundation
@testable import liftBuddyKit

/// A boat closing on the line from below at 3 m/s, crossing shortly after the gun.
func approachTrack(from seconds: Int = -30, to end: Int = 30) -> [TrackPoint] {
    let line = makeLine(axis: 90, length: 100)
    let midpoint = line.midpoint!
    return (seconds...end).map { t in
        let below = 20 - 3 * Double(t)
        return TrackPoint(
            time: TimeInterval(t),
            coordinate: midpoint.offset(bearing: Bearing(degrees: 180), distance: below),
            speed: 3,
            course: Bearing(degrees: 0)
        )
    }
}

func record(
    track: [TrackPoint],
    line: StartLine? = makeLine(axis: 90, length: 100),
    wind: Wind? = Wind(direction: Bearing(degrees: 0)),
    duration: TimeInterval = 60
) -> RaceRecord {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    return RaceRecord(
        name: "Race",
        startedAt: start,
        endedAt: start.addingTimeInterval(duration),
        line: line,
        wind: wind,
        track: track
    )
}

@Suite("Start analysis")
struct StartAnalysisTests {
    @Test("measures the gun from the nearest fix to it")
    func atTheGun() throws {
        let analysis = try #require(record(track: approachTrack()).startAnalysis)
        #expect(isClose(analysis.distanceToLine, 20, tolerance: 0.5))
        #expect(isClose(analysis.speed, 3, tolerance: 0.01))
        #expect(isClose(analysis.positionAlongLine, 0.5, tolerance: 0.01))
        #expect(!analysis.wasOver)
        #expect(isClose(analysis.speedInKnots, 5.83, tolerance: 0.02))
    }

    @Test("finds when the line was actually crossed")
    func crossing() throws {
        // 20 m out closing at 3 m/s crosses just under seven seconds late.
        let analysis = try #require(record(track: approachTrack()).startAnalysis)
        #expect(isClose(try #require(analysis.timeToCross), 7, tolerance: 1))
    }

    @Test("flags a start that was over the line")
    func overEarly() throws {
        // Same approach, thirty seconds earlier: already across at the gun.
        let early = approachTrack().map {
            TrackPoint(
                time: $0.time, coordinate: $0.coordinate, speed: $0.speed, course: $0.course)
        }.map {
            TrackPoint(
                time: $0.time - 12, coordinate: $0.coordinate, speed: $0.speed, course: $0.course)
        }
        let analysis = try #require(record(track: early).startAnalysis)
        #expect(analysis.wasOver)
        #expect(analysis.distanceToLine < 0)
        // Already over, so there is no crossing to report.
        #expect(analysis.timeToCross == nil)
    }

    @Test("says which end you started at, and whether it was the favoured one")
    func favoured() throws {
        let line = makeLine(axis: 100, length: 100)  // pin favoured
        let pinEnd = line.pin!.coordinate
        let track = [
            TrackPoint(
                time: 0,
                coordinate: pinEnd.offset(bearing: Bearing(degrees: 190), distance: 15),
                speed: 3, course: Bearing(degrees: 10))
        ]
        let analysis = try #require(record(track: track, line: line).startAnalysis)
        #expect(analysis.favoredEnd == .pin)
        #expect(analysis.endStartedAt == .pin)
        #expect(analysis.startedAtFavoredEnd == true)
    }

    @Test("a square line has no favoured end to have missed")
    func squareLine() throws {
        let analysis = try #require(record(track: approachTrack()).startAnalysis)
        #expect(analysis.favoredEnd == nil)
        #expect(analysis.startedAtFavoredEnd == nil)
    }

    @Test("needs a surveyed line")
    func noLine() {
        #expect(record(track: approachTrack(), line: nil).startAnalysis == nil)
        #expect(record(track: approachTrack(), line: StartLine()).startAnalysis == nil)
        #expect(record(track: []).startAnalysis == nil)
    }
}

@Suite("Race statistics")
struct RaceStatisticsTests {
    @Test("distance is measured from the gun, matching the duration")
    func distanceAndSpeed() {
        // The track runs -30s to +30s at 3 m/s, but only the racing half counts:
        // 30 steps of 3 m over the 60 s the record says it lasted.
        let stats = record(track: approachTrack()).statistics
        #expect(isClose(stats.distanceSailed, 90, tolerance: 1))
        #expect(isClose(stats.maximumSpeed, 3, tolerance: 0.01))
        #expect(stats.duration == 60)
    }

    @Test("average speed cannot exceed the speed actually sailed")
    func averageIsConsistent() {
        // Counting prestart distance against racing time inflated this.
        let stats = record(track: approachTrack(), duration: 30).statistics
        #expect(stats.averageSpeed <= stats.maximumSpeed + 0.01)
        #expect(isClose(stats.averageSpeed, 3, tolerance: 0.15))
    }

    @Test("circling before the start is not distance raced")
    func prestartExcluded() {
        let wandering = (-60...0).map { t in
            TrackPoint(
                time: TimeInterval(t),
                coordinate: testPin.offset(
                    bearing: Bearing(degrees: Double(t) * 6), distance: 40),
                speed: 3, course: Bearing(degrees: 0))
        }
        let stats = record(track: wandering, duration: 10).statistics
        // Only the single point at t = 0 is racing, so no distance was raced.
        #expect(stats.distanceSailed == 0)
    }

    @Test("an empty track has no distance and does not divide by zero")
    func empty() {
        let stats = record(track: [], duration: 0).statistics
        #expect(stats.distanceSailed == 0)
        #expect(stats.averageSpeed == 0)
        #expect(stats.maneuvers == 0)
    }
}

@Suite("Tacks and gybes")
struct ManeuverTests {
    let northerly = Bearing(degrees: 0)

    /// A track holding each heading for ten samples in turn.
    func zigzag(_ headings: [Double]) -> [TrackPoint] {
        var points: [TrackPoint] = []
        var t = 0.0
        for heading in headings {
            for _ in 0..<10 {
                points.append(
                    TrackPoint(
                        time: t, coordinate: testPin, speed: 3,
                        course: Bearing(degrees: heading)))
                t += 1
            }
        }
        return points
    }

    @Test("counts a beat's tacks and no gybes")
    func tacks() {
        // Close-hauled either side of a northerly: three changes of tack.
        let result = RaceRecord.countManeuvers(
            track: zigzag([45, 315, 45, 315]), wind: northerly)
        #expect(result.tacks == 3)
        #expect(result.gybes == 0)
    }

    @Test("counts a run's gybes and no tacks")
    func gybes() {
        // Broad reaching either side of dead downwind.
        let result = RaceRecord.countManeuvers(
            track: zigzag([135, 225, 135]), wind: northerly)
        #expect(result.gybes == 2)
        #expect(result.tacks == 0)
    }

    @Test("a beat then a run counts each correctly")
    func mixed() {
        let result = RaceRecord.countManeuvers(
            track: zigzag([45, 315, 45, 135, 225]), wind: northerly)
        #expect(result.tacks == 2)
        // Bearing away from close-hauled onto a run is not a gybe; only the
        // crossing from one side of the wind to the other counts.
        #expect(result.gybes == 1)
    }

    @Test("wandering near dead downwind does not invent gybes")
    func hysteresis() {
        // Small wiggles either side of the wind axis, inside the dead band.
        let result = RaceRecord.countManeuvers(
            track: zigzag([5, 355, 5, 355, 175, 185]), wind: northerly)
        #expect(result.tacks + result.gybes == 0)
    }

    @Test("no wind means nothing can be counted")
    func noWind() {
        let result = RaceRecord.countManeuvers(track: zigzag([45, 315]), wind: nil)
        #expect(result.tacks == 0 && result.gybes == 0)
    }

    @Test("drifting does not count, because course over ground is noise")
    func drifting() {
        let drifting = zigzag([45, 315]).map {
            TrackPoint(time: $0.time, coordinate: $0.coordinate, speed: 0.05, course: $0.course)
        }
        let result = RaceRecord.countManeuvers(track: drifting, wind: northerly)
        #expect(result.tacks == 0)
    }
}
