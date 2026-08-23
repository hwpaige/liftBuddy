import Testing
import Foundation
@testable import liftBuddyKit

@Suite("Chart path")
struct ChartPathTests {
    @Test("flat storage round-trips coordinates")
    func roundTrip() {
        let coordinates = [
            Coordinate(latitude: 41.5, longitude: -71.3),
            Coordinate(latitude: 41.6, longitude: -71.2),
        ]
        let path = ChartPath(coordinates)
        #expect(path.count == 2)
        #expect(path.flat == [-71.3, 41.5, -71.2, 41.6])
        #expect(path[0] == coordinates[0])
        #expect(path[1] == coordinates[1])
        #expect(path.coordinates == coordinates)
    }

    @Test("empty path")
    func empty() {
        #expect(ChartPath([]).isEmpty)
        #expect(ChartPath([]).count == 0)
    }
}

@Suite("Depth shading")
struct DepthAreaTests {
    func area(_ min: Double?, _ max: Double? = nil) -> DepthArea {
        DepthArea(minimumDepth: min, maximumDepth: max, rings: [])
    }

    @Test("shallower water shades darker, and deep water not at all")
    func shallowness() {
        #expect(area(0).shallowness == 1)
        #expect(area(-1).shallowness == 1)
        #expect(isClose(area(5).shallowness, 0.5))
        #expect(area(10).shallowness == 0)
        #expect(area(40).shallowness == 0)
    }

    @Test("judged by the least water in the area")
    func governing() {
        #expect(area(2, 5).governingDepth == 2)
        // Where only the deep bound is charted, that is all there is to go on.
        #expect(area(nil, 5).governingDepth == 5)
        #expect(area(nil, nil).shallowness == 0)
    }
}

@Suite("ENC Direct queries")
struct ENCDirectTests {
    let bounds = TileBoundingBox(north: 41.53, south: 41.44, east: -71.27, west: -71.36)

    @Test("builds a paged GeoJSON envelope query")
    func queryURL() throws {
        let layer = try #require(ENCDirect.racingLayers.first { $0.role == .depthArea })
        let url = try #require(ENCDirect.queryURL(layer: layer, bounds: bounds, offset: 2000))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(url.path.hasSuffix("/enc_harbour/MapServer/227/query"))
        #expect(items["f"] == "geojson")
        #expect(items["inSR"] == "4326")
        #expect(items["outSR"] == "4326")
        // ArcGIS envelope order is west, south, east, north.
        #expect(items["geometry"] == "-71.36,41.44,-71.27,41.53")
        #expect(items["resultOffset"] == "2000")
    }

    @Test("the racing layer set stays small and covers what matters")
    func layers() {
        let roles = Set(ENCDirect.racingLayers.map(\.role))
        #expect(roles == [.depthArea, .depthContour, .land, .mark])
        // Every mark layer must say what kind of mark it yields.
        let marks = ENCDirect.racingLayers.filter { $0.role == .mark }
        #expect(marks.allSatisfy { $0.markKind != nil })
        #expect(!marks.isEmpty)
    }
}

@Suite("Chart simplification")
struct ChartSimplifyTests {
    /// Builds a path from metre offsets east/north of a fixed origin.
    func path(_ offsets: [(Double, Double)]) -> [Coordinate] {
        let origin = Coordinate(latitude: 41.5, longitude: -71.3)
        let plane = LocalPlane(origin: origin)
        return offsets.map { plane.unproject(PlanePoint(east: $0.0, north: $0.1)) }
    }

    @Test("collinear points collapse to the two ends")
    func straightLine() {
        let line = path((0...10).map { (Double($0) * 10, 0) })
        let simplified = ChartSimplify.douglasPeucker(line, toleranceMeters: 1)
        #expect(simplified.count == 2)
    }

    @Test("corners survive")
    func corners() {
        // A square with redundant points along each side.
        let square = path([
            (0, 0), (50, 0), (100, 0),
            (100, 50), (100, 100),
            (50, 100), (0, 100),
            (0, 50), (0, 0),
        ])
        let simplified = ChartSimplify.douglasPeucker(square, toleranceMeters: 2)
        #expect(simplified.count == 5)
    }

    @Test("tolerance decides what survives")
    func tolerance() {
        // A 3 m bump in an otherwise straight 200 m line.
        let bumpy = path([(0, 0), (100, 3), (200, 0)])
        #expect(ChartSimplify.douglasPeucker(bumpy, toleranceMeters: 1).count == 3)
        #expect(ChartSimplify.douglasPeucker(bumpy, toleranceMeters: 5).count == 2)
    }

    @Test("short inputs pass through untouched")
    func shortInputs() {
        let two = path([(0, 0), (10, 10)])
        #expect(ChartSimplify.douglasPeucker(two, toleranceMeters: 100).count == 2)
        #expect(ChartSimplify.douglasPeucker([], toleranceMeters: 1).isEmpty)
    }

    @Test("a ring that collapses below three points is discarded")
    func ringCollapse() {
        let sliver = path([(0, 0), (100, 0), (200, 0), (0, 0)])
        #expect(ChartSimplify.simplifyRing(sliver, toleranceMeters: 5) == nil)

        let real = path([(0, 0), (100, 0), (100, 100), (0, 100), (0, 0)])
        let kept = ChartSimplify.simplifyRing(real, toleranceMeters: 2)
        #expect(kept?.count == 5)
    }

    @Test("handles a large ring without running out of stack")
    func largeRing() {
        let big = path((0..<20_000).map { (Double($0) * 0.5, sin(Double($0) / 40) * 30) })
        let simplified = ChartSimplify.douglasPeucker(big, toleranceMeters: 2)
        #expect(simplified.count > 2)
        #expect(simplified.count < big.count / 4)
    }
}

@Suite("Ring area")
struct RingAreaTests {
    func square(_ side: Double) -> [Coordinate] {
        let plane = LocalPlane(origin: Coordinate(latitude: 41.5, longitude: -71.3))
        return [(0.0, 0.0), (side, 0), (side, side), (0, side), (0, 0)].map {
            plane.unproject(PlanePoint(east: $0.0, north: $0.1))
        }
    }

    @Test("shoelace area matches the geometry")
    func area() {
        #expect(isClose(abs(ChartSimplify.area(of: square(100))), 10_000, tolerance: 1))
        #expect(isClose(abs(ChartSimplify.area(of: square(10))), 100, tolerance: 0.1))
    }

    @Test("winding shows in the sign")
    func winding() {
        let ring = square(100)
        let reversed = Array(ring.reversed())
        #expect(ChartSimplify.area(of: ring) * ChartSimplify.area(of: reversed) < 0)
    }

    @Test("degenerate rings have no area")
    func degenerate() {
        #expect(ChartSimplify.area(of: []) == 0)
        #expect(isClose(ChartSimplify.area(of: square(0)), 0, tolerance: 1e-9))
    }
}

@Suite("Retry policy")
struct RetryPolicyTests {
    let policy = RetryPolicy(
        baseDelay: 30, maximumDelay: 600, breakerThreshold: 4, coolDown: 300)

    @Test("delays double and then stop growing")
    func backoff() {
        #expect(policy.delay(afterFailures: 0) == 0)
        #expect(policy.delay(afterFailures: 1) == 30)
        #expect(policy.delay(afterFailures: 2) == 60)
        #expect(policy.delay(afterFailures: 3) == 120)
        #expect(policy.delay(afterFailures: 5) == 480)
        #expect(policy.delay(afterFailures: 6) == 600)
        // Never overflows into a delay measured in years.
        #expect(policy.delay(afterFailures: 500) == 600)
    }

    @Test("a fresh cell is tried at once, a failing one is made to wait")
    func retryTiming() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(policy.shouldRetry(failures: 0, since: start, now: start))
        #expect(!policy.shouldRetry(failures: 1, since: start, now: start.addingTimeInterval(20)))
        #expect(policy.shouldRetry(failures: 1, since: start, now: start.addingTimeInterval(31)))
        #expect(!policy.shouldRetry(failures: 3, since: start, now: start.addingTimeInterval(90)))
        #expect(policy.shouldRetry(failures: 3, since: start, now: start.addingTimeInterval(121)))
    }

    @Test("a run of refusals silences the client, then lets it back in")
    func breaker() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(!policy.isTripped(consecutiveFailures: 3, lastFailure: start, now: start))
        #expect(policy.isTripped(consecutiveFailures: 4, lastFailure: start, now: start))
        #expect(
            policy.isTripped(
                consecutiveFailures: 9, lastFailure: start,
                now: start.addingTimeInterval(299)))
        #expect(
            !policy.isTripped(
                consecutiveFailures: 9, lastFailure: start,
                now: start.addingTimeInterval(301)))
        // Nothing to back off from without a recorded failure.
        #expect(!policy.isTripped(consecutiveFailures: 9, lastFailure: nil, now: start))
    }
}

@Suite("Partial packs")
struct PartialPackTests {
    func pack(_ layers: [String]) -> ChartPack {
        ChartPack(
            name: "cell",
            bounds: TileBoundingBox(north: 1, south: 0, east: 1, west: 0),
            marks: layers.map {
                ChartMark(
                    id: $0.hashValue, coordinate: Coordinate(latitude: 0.5, longitude: 0.5),
                    kind: .buoyLateral)
            },
            fetchedLayers: layers)
    }

    @Test("knows which layers it still needs")
    func missing() {
        let all = ENCDirect.racingLayers
        let partial = pack([all[0].name, all[1].name])
        let missing = partial.missingLayers(from: all)
        #expect(missing.count == all.count - 2)
        #expect(!missing.contains { $0.name == all[0].name })

        let complete = pack(all.map(\.name))
        #expect(complete.missingLayers(from: all).isEmpty)
    }

    @Test("a top-up folds into what was already there")
    func merging() {
        let all = ENCDirect.racingLayers
        var base = pack([all[0].name])
        base.merge(pack([all[1].name]))
        #expect(Set(base.fetchedLayers) == Set([all[0].name, all[1].name]))
        #expect(base.marks.count == 2)
        #expect(base.missingLayers(from: all).count == all.count - 2)
    }

    @Test("merging the same layer twice does not duplicate the layer record")
    func idempotentLayerNames() {
        let all = ENCDirect.racingLayers
        var base = pack([all[0].name])
        base.merge(pack([all[0].name]))
        #expect(base.fetchedLayers == [all[0].name])
    }
}

@Suite("Adaptive request deadline")
struct ENCTransportTests {
    @Test("stays patient until it has measured the link")
    func beforeMeasurement() async {
        let transport = ENCTransport()
        #expect(await transport.timeout == ENCTransport.initialTimeout)
        await transport.record(latency: 0.25)
        await transport.record(latency: 0.25)
        // Two samples is not yet evidence.
        #expect(await transport.timeout == ENCTransport.initialTimeout)
    }

    @Test("tightens to a multiple of observed latency")
    func tightens() async {
        let transport = ENCTransport()
        for _ in 0..<3 { await transport.record(latency: 1.0) }
        // Four times the slowest success.
        #expect(await transport.timeout == 4.0)
    }

    @Test("judges by the slowest recent success, not the average")
    func slowestWins() async {
        let transport = ENCTransport()
        await transport.record(latency: 0.1)
        await transport.record(latency: 0.1)
        await transport.record(latency: 2.0)
        // Being slightly too patient costs one slow retry; being too impatient
        // throws away requests that would have worked.
        #expect(await transport.timeout == 8.0)
    }

    @Test("clamped at both ends")
    func clamping() async {
        let fast = ENCTransport()
        for _ in 0..<3 { await fast.record(latency: 0.05) }
        #expect(await fast.timeout == ENCTransport.minimumTimeout)

        let slow = ENCTransport()
        for _ in 0..<3 { await slow.record(latency: 30) }
        #expect(await slow.timeout == ENCTransport.maximumTimeout)
    }

    @Test("forgets old samples so it can retighten after a slow patch")
    func forgets() async {
        let transport = ENCTransport()
        for _ in 0..<3 { await transport.record(latency: 5.0) }
        #expect(await transport.timeout == ENCTransport.maximumTimeout)
        // A run of fast responses should win back the tighter deadline.
        for _ in 0..<8 { await transport.record(latency: 0.25) }
        #expect(await transport.timeout == ENCTransport.minimumTimeout)
    }
}

@Suite("Venue")
struct VenueTests {
    let newport = Coordinate(latitude: 41.49882, longitude: -71.33318)

    @Test("covers itself with chart cells, centre first")
    func cells() throws {
        let venue = Venue(name: "Newport", center: newport, radius: 5000)
        let cells = venue.cells
        #expect(!cells.isEmpty)
        let centreCell = try #require(TileCoordinate(coordinate: newport, zoom: ENCDirect.cellZoom))
        #expect(cells.first == centreCell)
        let allValid = cells.allSatisfy { $0.isValid }
        #expect(allValid)
    }

    @Test("a bigger venue needs more cells and more download")
    func growth() {
        let small = Venue(name: "s", center: newport, radius: 2000)
        let large = Venue(name: "l", center: newport, radius: 15000)
        #expect(large.cellCount > small.cellCount)
        #expect(large.approximateBytes > small.approximateBytes)
        // A race area should stay a sane download on a phone.
        #expect(small.approximateBytes < 20_000_000)
    }

    @Test("knows whether you are sailing in it")
    func containment() {
        let venue = Venue(name: "Newport", center: newport, radius: 5000)
        #expect(venue.contains(newport))
        #expect(venue.contains(newport.offset(bearing: Bearing(degrees: 45), distance: 4000)))
        #expect(!venue.contains(newport.offset(bearing: Bearing(degrees: 45), distance: 6000)))
        #expect(isClose(venue.distance(to: newport), 0, tolerance: 0.01))
    }
}

@Suite("Chart cache layout")
struct ChartCacheTests {
    let documents = URL(fileURLWithPath: "/tmp/docs", isDirectory: true)

    @Test("phone and watch agree on the path for a cell")
    func path() {
        let cell = TileCoordinate(z: 13, x: 2472, y: 3056)
        let url = ChartCache.url(inDocuments: documents, cell: cell)
        #expect(url.path.hasSuffix("charts/cells/13/2472/3056.json"))
    }

    @Test("a transferred file can be placed from its metadata alone")
    func metadataRoundTrip() throws {
        let cell = TileCoordinate(z: 13, x: 2472, y: 3056)
        let recovered = try #require(ChartCache.cell(from: ChartCache.metadata(for: cell)))
        #expect(recovered == cell)
    }

    @Test("rejects metadata that did not come from us")
    func badMetadata() {
        #expect(ChartCache.cell(from: nil) == nil)
        #expect(ChartCache.cell(from: [:]) == nil)
        #expect(ChartCache.cell(from: ["z": "13", "x": 1, "y": 1]) == nil)
        // Out-of-range coordinates must not become a path.
        #expect(ChartCache.cell(from: ["z": 2, "x": 99, "y": 0]) == nil)
    }
}
