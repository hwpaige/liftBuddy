import Testing
import Foundation
@testable import liftBuddyKit

/// Builds a line of `length` meters running `axis` degrees from pin to boat.
func makeLine(axis: Double, length: Double = 100, accuracy: Double = 3) -> StartLine {
    let pin = LineMark(coordinate: testPin, accuracy: accuracy)
    let boatCoordinate = testPin.offset(bearing: Bearing(degrees: axis), distance: length)
    return StartLine(pin: pin, boat: LineMark(coordinate: boatCoordinate, accuracy: accuracy))
}

let northerly = Bearing(degrees: 0)

@Suite("StartLine geometry")
struct StartLineTests {
    @Test("needs both ends before it measures anything")
    func survey() {
        var line = StartLine()
        #expect(!line.isSurveyed)
        #expect(line.axis == nil)
        #expect(line.bias(wind: northerly) == nil)

        line.pin = LineMark(coordinate: testPin)
        #expect(!line.isSurveyed)
        #expect(line.length == nil)

        line.boat = LineMark(coordinate: testPin.offset(bearing: Bearing(degrees: 90), distance: 80))
        #expect(line.isSurveyed)
        #expect(isClose(line.length!, 80, tolerance: 0.01))
        #expect(isClose(line.axis!.degrees, 90, tolerance: 0.01))
    }

    @Test("swapping ends reverses the axis")
    func swap() {
        var line = makeLine(axis: 90)
        line.swapEnds()
        #expect(isClose(line.axis!.degrees, 270, tolerance: 0.05))
    }

    @Test("detects ends pinged the wrong way round")
    func reversed() {
        #expect(!makeLine(axis: 90).endsLookReversed(for: northerly))
        #expect(!makeLine(axis: 120).endsLookReversed(for: northerly))
        #expect(makeLine(axis: 270).endsLookReversed(for: northerly))
    }
}

@Suite("Line bias")
struct LineBiasTests {
    @Test("a square line has no favored end")
    func square() throws {
        let bias = try #require(makeLine(axis: 90).bias(wind: northerly))
        #expect(isClose(bias.degrees, 0, tolerance: 0.05))
        #expect(bias.favoredEnd == nil)
        #expect(!bias.isSignificant)
    }

    @Test("line rotated clockwise favors the pin")
    func pinFavored() throws {
        let bias = try #require(makeLine(axis: 100).bias(wind: northerly))
        #expect(isClose(bias.degrees, 10, tolerance: 0.05))
        #expect(bias.favoredEnd == .pin)
        #expect(bias.isSignificant)
        // A 100 m line skewed 10° is worth 100·sin(10°) upwind.
        #expect(isClose(bias.advantage, 17.36, tolerance: 0.05))
    }

    @Test("line rotated counter-clockwise favors the committee boat")
    func boatFavored() throws {
        let bias = try #require(makeLine(axis: 80).bias(wind: northerly))
        #expect(isClose(bias.degrees, -10, tolerance: 0.05))
        #expect(bias.favoredEnd == .boat)
        #expect(isClose(bias.advantage, 17.36, tolerance: 0.05))
    }

    @Test("bias follows the wind, not just the line")
    func windShift() throws {
        let line = makeLine(axis: 90)
        // Wind veers right by 10°: square is now 100, so this 090 line is
        // skewed −10 and the committee boat end goes upwind.
        let bias = try #require(line.bias(wind: Bearing(degrees: 10)))
        #expect(isClose(bias.degrees, -10, tolerance: 0.05))
        #expect(bias.favoredEnd == .boat)
    }

    @Test("a short line pinged sloppily cannot resolve a small bias")
    func uncertainty() throws {
        // 30 m line, 10 m accuracy at each end: a lot of angular slop.
        let sloppy = try #require(makeLine(axis: 95, length: 30, accuracy: 10).bias(wind: northerly))
        #expect(sloppy.uncertainty > 5)
        #expect(!sloppy.isSignificant)
        #expect(sloppy.favoredEnd == nil)

        // The same 5° on a long, well-pinged line is real.
        let crisp = try #require(makeLine(axis: 95, length: 300, accuracy: 3).bias(wind: northerly))
        #expect(crisp.uncertainty < 2)
        #expect(crisp.isSignificant)
        #expect(crisp.favoredEnd == .pin)
    }

    @Test("advantage converts to boat lengths")
    func boatLengths() throws {
        let bias = try #require(makeLine(axis: 100, length: 200).bias(wind: northerly))
        // 200·sin(10°) ≈ 34.7 m, about five lengths of a J/70.
        #expect(isClose(bias.advantageInBoatLengths(6.9), 5.03, tolerance: 0.05))
    }
}

@Suite("Line approach")
struct LineApproachTests {
    let line = makeLine(axis: 90, length: 100)

    /// A fix `metersBelow` the line, `alongLine` meters from the pin.
    func fix(alongLine: Double, metersBelow: Double, course: Double? = nil, speed: Double = 0)
        -> BoatFix
    {
        let onLine = testPin.offset(bearing: Bearing(degrees: 90), distance: alongLine)
        let position = onLine.offset(bearing: Bearing(degrees: 180), distance: metersBelow)
        return BoatFix(
            coordinate: position,
            course: course.map { Bearing(degrees: $0) },
            speed: speed,
            horizontalAccuracy: 3
        )
    }

    @Test("measures perpendicular distance from below the line")
    func belowLine() throws {
        let approach = try #require(line.approach(from: fix(alongLine: 50, metersBelow: 50)))
        #expect(isClose(approach.perpendicularDistance, 50, tolerance: 0.5))
        #expect(isClose(approach.distanceToLine, 50, tolerance: 0.5))
        #expect(!approach.isOverEarly)
        #expect(approach.isBetweenEnds)
        #expect(isClose(approach.positionAlongLine, 0.5, tolerance: 0.01))
        #expect(isClose(approach.distanceToPin, 70.7, tolerance: 0.5))
        #expect(isClose(approach.distanceToBoat, 70.7, tolerance: 0.5))
    }

    @Test("flags being over the line early")
    func overEarly() throws {
        let approach = try #require(line.approach(from: fix(alongLine: 50, metersBelow: -20)))
        #expect(approach.isOverEarly)
        #expect(isClose(approach.perpendicularDistance, -20, tolerance: 0.5))
        #expect(isClose(approach.distanceToLine, 20, tolerance: 0.5))
    }

    @Test("time to line uses closing speed, not raw boat speed")
    func timeToLine() throws {
        // Straight at the line at 2 m/s from 50 m out: 25 seconds.
        let headOn = try #require(
            line.approach(from: fix(alongLine: 50, metersBelow: 50, course: 0, speed: 2))
        )
        #expect(isClose(headOn.closingSpeed, 2, tolerance: 0.05))
        #expect(isClose(try #require(headOn.timeToLine), 25, tolerance: 0.5))

        // Reaching along the line closes nothing.
        let parallel = try #require(
            line.approach(from: fix(alongLine: 50, metersBelow: 50, course: 90, speed: 2))
        )
        #expect(isClose(parallel.closingSpeed, 0, tolerance: 0.05))
        #expect(parallel.timeToLine == nil)

        // Sailing away from the line never resolves to a time.
        let away = try #require(
            line.approach(from: fix(alongLine: 50, metersBelow: 50, course: 180, speed: 2))
        )
        #expect(away.closingSpeed < 0)
        #expect(away.timeToLine == nil)
    }

    @Test("past an end, distance is to the end and not to open water")
    func outsideEnds() throws {
        // 30 m beyond the boat end, 40 m below the line: 50 m to the end itself.
        let approach = try #require(line.approach(from: fix(alongLine: 130, metersBelow: 40)))
        #expect(!approach.isBetweenEnds)
        #expect(approach.positionAlongLine > 1)
        #expect(isClose(approach.distanceToLine, 50, tolerance: 0.5))
        // The perpendicular is still reported, and still says "not over".
        #expect(isClose(approach.perpendicularDistance, 40, tolerance: 0.5))
    }

    @Test("burn time is the slack between the gun and the line")
    func burnTime() throws {
        let approach = try #require(
            line.approach(from: fix(alongLine: 50, metersBelow: 50, course: 0, speed: 2))
        )
        // 25 s to the line with 40 s to go: 15 s to burn.
        #expect(isClose(try #require(approach.burnTime(timeToStart: 40)), 15, tolerance: 0.5))
        // With 10 s to go you are 15 s late.
        #expect(isClose(try #require(approach.burnTime(timeToStart: 10)), -15, tolerance: 0.5))
    }

    @Test("bow offset moves the reference point forward along the course")
    func bowOffset() throws {
        let sample = fix(alongLine: 50, metersBelow: 50, course: 0, speed: 2)
        let atWrist = try #require(line.approach(from: sample))
        let atBow = try #require(line.approach(from: sample, bowOffset: 5))
        #expect(isClose(atBow.distanceToLine, atWrist.distanceToLine - 5, tolerance: 0.2))
    }

    @Test("ignores bow offset when the course is untrustworthy")
    func bowOffsetWhenStopped() throws {
        // Drifting: GPS course is noise, so do not project along it.
        let drifting = fix(alongLine: 50, metersBelow: 50, course: 0, speed: 0.05)
        let approach = try #require(line.approach(from: drifting, bowOffset: 5))
        #expect(isClose(approach.distanceToLine, 50, tolerance: 0.5))
    }
}

@Suite("Race timer")
struct RaceTimerTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("counts down from the sequence length, then counts up")
    func countdown() throws {
        var timer = RaceTimer(sequence: .five)
        #expect(!timer.isRunning)
        #expect(timer.phase(at: t0) == .idle)

        timer.start(at: t0)
        #expect(timer.isRunning)
        #expect(isClose(try #require(timer.timeToStart(at: t0)), 300))
        #expect(timer.phase(at: t0) == .countdown(300))
        #expect(timer.phase(at: t0.addingTimeInterval(60)) == .countdown(240))
        #expect(timer.phase(at: t0.addingTimeInterval(300)) == .racing(0))
        #expect(timer.phase(at: t0.addingTimeInterval(330)) == .racing(30))
    }

    @Test("sync snaps down to the minute just passed, never up")
    func sync() throws {
        var timer = RaceTimer(sequence: .five)
        timer.start(at: t0)

        // 13 s after starting: 4:47 remaining trims to 4:00, it does not jump
        // back up to 5:00.
        let late = t0.addingTimeInterval(13)
        let syncedLate = timer.sync(at: late)
        #expect(syncedLate)
        #expect(isClose(try #require(timer.timeToStart(at: late)), 240))

        // 50 s further on: 3:10 remaining trims to 3:00.
        let drifted = late.addingTimeInterval(50)
        let syncedDrifted = timer.sync(at: drifted)
        #expect(syncedDrifted)
        #expect(isClose(try #require(timer.timeToStart(at: drifted)), 180))
    }

    @Test("sync never adds time")
    func syncNeverAdds() throws {
        var timer = RaceTimer(sequence: .five)
        timer.start(at: t0)
        for offset in stride(from: 1.0, to: 240, by: 7) {
            let now = t0.addingTimeInterval(offset)
            let before = try #require(timer.timeToStart(at: now))
            timer.sync(at: now)
            let after = try #require(timer.timeToStart(at: now))
            #expect(after <= before + 0.001)
        }
    }

    @Test("sync inside the last minute does nothing rather than firing the gun")
    func syncNearZero() throws {
        var timer = RaceTimer(sequence: .five)
        timer.start(at: t0)
        let nearly = t0.addingTimeInterval(280)  // 20 s left
        let synced = timer.sync(at: nearly)
        #expect(!synced)
        // Untouched: there is no lower whole minute to snap to.
        #expect(isClose(try #require(timer.timeToStart(at: nearly)), 20))
    }

    @Test("sync does nothing once racing")
    func syncAfterStart() {
        var timer = RaceTimer(sequence: .five)
        timer.start(at: t0)
        let racing = t0.addingTimeInterval(320)
        let synced = timer.sync(at: racing)
        #expect(!synced)
        #expect(timer.phase(at: racing) == .racing(20))
    }

    @Test("adjust, restart, and reset")
    func controls() throws {
        var timer = RaceTimer(sequence: .three)
        timer.start(at: t0)
        timer.adjust(by: 60)
        #expect(isClose(try #require(timer.timeToStart(at: t0)), 240))

        let recall = t0.addingTimeInterval(500)
        timer.restart(at: recall)
        #expect(isClose(try #require(timer.timeToStart(at: recall)), 180))

        timer.reset()
        #expect(!timer.isRunning)
        #expect(timer.phase(at: t0) == .idle)
    }

    @Test("haptic cues fire once each as the countdown passes them")
    func cues() {
        #expect(RaceTimer.cuesCrossed(from: 65, to: 58) == [60])
        #expect(RaceTimer.cuesCrossed(from: 11, to: 9) == [10])
        #expect(RaceTimer.cuesCrossed(from: 58, to: 57) == [])
        // A stalled tick must not swallow the gun.
        #expect(RaceTimer.cuesCrossed(from: 6, to: -1) == [5, 4, 3, 2, 1, 0])
        // Time running backwards yields nothing.
        #expect(RaceTimer.cuesCrossed(from: 10, to: 20) == [])
    }
}

@Suite("Formatting")
struct RaceFormatTests {
    @Test("clock pads seconds and marks time after the gun")
    func clock() {
        #expect(RaceFormat.clock(272) == "4:32")
        #expect(RaceFormat.clock(60) == "1:00")
        #expect(RaceFormat.clock(9) == "0:09")
        #expect(RaceFormat.clock(0) == "0:00")
        #expect(RaceFormat.clock(-15) == "-0:15")
        #expect(RaceFormat.clock(-90) == "-1:30")
    }

    @Test("slack and distance read the way they are spoken")
    func values() {
        #expect(RaceFormat.signedSeconds(12) == "+12s")
        #expect(RaceFormat.signedSeconds(-8) == "-8s")
        #expect(RaceFormat.distance(45.4) == "45 m")
        #expect(RaceFormat.distance(1240) == "1.24 km")
        #expect(RaceFormat.degrees(-8.3) == "8°")
    }
}
