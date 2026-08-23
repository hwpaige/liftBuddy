import Testing
import Foundation
@testable import liftBuddyKit

/// Newport, RI — as good a place as any to hold a start line.
let testPin = Coordinate(latitude: 41.5, longitude: -71.3)

func isClose(_ a: Double, _ b: Double, tolerance: Double = 1e-6) -> Bool {
    abs(a - b) <= tolerance
}

/// Compares bearings by angular separation. Comparing `.degrees` directly is a
/// trap: a mean that lands a hair below north normalizes to 359.999…, which is
/// the right answer and a wildly wrong number.
func isCloseAngle(_ a: Bearing, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    a.separation(to: Bearing(degrees: b)) <= tolerance
}

@Suite("Bearing")
struct BearingTests {
    @Test("normalizes into 0..<360")
    func normalization() {
        #expect(Bearing(degrees: 370).degrees == 10)
        #expect(Bearing(degrees: -10).degrees == 350)
        #expect(Bearing(degrees: 360).degrees == 0)
        #expect(Bearing(degrees: -725).degrees == 355)
    }

    @Test("signed delta wraps the short way around north")
    func delta() {
        #expect(Bearing(degrees: 350).delta(to: Bearing(degrees: 10)) == 20)
        #expect(Bearing(degrees: 10).delta(to: Bearing(degrees: 350)) == -20)
        #expect(Bearing(degrees: 0).delta(to: Bearing(degrees: 180)) == 180)
        #expect(Bearing(degrees: 90).separation(to: Bearing(degrees: 270)) == 180)
    }

    @Test("circular mean does not average through the wrong side of the compass")
    func circularMean() throws {
        let mean = try #require(Bearing.mean([Bearing(degrees: 359), Bearing(degrees: 1)]))
        #expect(isCloseAngle(mean, 0))

        let quarter = try #require(Bearing.mean([Bearing(degrees: 350), Bearing(degrees: 10)]))
        #expect(isCloseAngle(quarter, 0))

        // Diametrically opposed bearings have no meaningful mean.
        #expect(Bearing.mean([Bearing(degrees: 0), Bearing(degrees: 180)]) == nil)
        #expect(Bearing.mean([]) == nil)
    }

    @Test("reciprocal and cardinal labels")
    func labels() {
        #expect(Bearing(degrees: 30).reciprocal.degrees == 210)
        #expect(Bearing(degrees: 0).cardinal == "N")
        #expect(Bearing(degrees: 46).cardinal == "NE")
        #expect(Bearing(degrees: 359).cardinal == "N")
        #expect(Bearing(degrees: 180).cardinal == "S")
    }
}

@Suite("Coordinate")
struct CoordinateTests {
    @Test("offset then measure returns the original distance and bearing")
    func roundTrip() {
        let target = testPin.offset(bearing: Bearing(degrees: 47), distance: 500)
        #expect(isClose(testPin.distance(to: target), 500, tolerance: 0.01))
        #expect(isClose(testPin.bearing(to: target).degrees, 47, tolerance: 0.01))
    }

    @Test("due-east offset is a pure longitude change")
    func dueEast() {
        let east = testPin.offset(bearing: Bearing(degrees: 90), distance: 100)
        #expect(east.longitude > testPin.longitude)
        #expect(isClose(east.latitude, testPin.latitude, tolerance: 1e-6))
    }
}

@Suite("LocalPlane")
struct LocalPlaneTests {
    @Test("projection round-trips to sub-centimeter over a race course")
    func roundTrip() {
        let plane = LocalPlane(origin: testPin)
        let far = testPin.offset(bearing: Bearing(degrees: 220), distance: 1500)
        let back = plane.unproject(plane.project(far))
        #expect(far.distance(to: back) < 0.01)
    }

    @Test("north and east axes land where expected")
    func axes() {
        let plane = LocalPlane(origin: testPin)
        let north = plane.project(testPin.offset(bearing: Bearing(degrees: 0), distance: 200))
        #expect(isClose(north.north, 200, tolerance: 0.5))
        #expect(isClose(north.east, 0, tolerance: 0.5))

        let east = plane.project(testPin.offset(bearing: Bearing(degrees: 90), distance: 200))
        #expect(isClose(east.east, 200, tolerance: 0.5))
        #expect(isClose(east.north, 0, tolerance: 0.5))
    }

    @Test("rotating the axis to port points upwind on a square line")
    func rotation() {
        // A line square to a northerly runs 090 from pin to boat.
        let along = PlanePoint.unit(Bearing(degrees: 90))
        let upwind = along.rotatedLeft
        #expect(isCloseAngle(upwind.bearing, 0))
    }
}

@Suite("Wind")
struct WindTests {
    @Test("bisects close-hauled headings across north")
    func closeHauled() throws {
        let wind = try #require(
            Wind.fromCloseHauled(port: Bearing(degrees: 315), starboard: Bearing(degrees: 45))
        )
        #expect(isCloseAngle(wind.direction, 0))
        #expect(wind.source == .tackAverage)
    }

    @Test("rejects headings that are not plausibly opposite tacks")
    func implausible() {
        // Same tack twice.
        #expect(Wind.fromCloseHauled(port: Bearing(degrees: 40), starboard: Bearing(degrees: 50)) == nil)
        // Reciprocal headings — sailing away from each other, not tacking.
        #expect(Wind.fromCloseHauled(port: Bearing(degrees: 0), starboard: Bearing(degrees: 180)) == nil)
    }
}
