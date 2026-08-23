import Testing
import Foundation
@testable import liftBuddyKit

@Suite("Web Mercator")
struct WebMercatorTests {
    /// Reference tiles cross-checked against the standard slippy-map formula.
    @Test("known positions land on known tiles")
    func referenceTiles() throws {
        let cases: [(Coordinate, Int, Int, Int)] = [
            (Coordinate(latitude: 0.0001, longitude: 0.0001), 1, 1, 0),
            (Coordinate(latitude: 51.5007, longitude: -0.1246), 12, 2046, 1362),
            (Coordinate(latitude: 41.49, longitude: -71.30), 14, 4947, 6113),
            (Coordinate(latitude: -33.8568, longitude: 151.2153), 10, 942, 614),
        ]
        for (coordinate, zoom, x, y) in cases {
            let tile = try #require(TileCoordinate(coordinate: coordinate, zoom: zoom))
            #expect(tile.x == x)
            #expect(tile.y == y)
            #expect(tile.z == zoom)
        }
    }

    @Test("projection round-trips")
    func roundTrip() {
        let start = Coordinate(latitude: 41.49, longitude: -71.30)
        for zoom in [4, 10, 16] {
            let point = WebMercator.point(for: start, zoom: zoom)
            let back = WebMercator.coordinate(for: point, zoom: zoom)
            #expect(isClose(back.latitude, start.latitude, tolerance: 1e-9))
            #expect(isClose(back.longitude, start.longitude, tolerance: 1e-9))
        }
    }

    @Test("resolution halves with each zoom level and shrinks with latitude")
    func resolution() {
        #expect(isClose(WebMercator.metersPerPixel(latitude: 0, zoom: 0), 156_543.0339, tolerance: 1e-3))
        #expect(isClose(WebMercator.metersPerPixel(latitude: 41.5, zoom: 16), 1.7890, tolerance: 1e-3))
        let z12 = WebMercator.metersPerPixel(latitude: 41.5, zoom: 12)
        let z13 = WebMercator.metersPerPixel(latitude: 41.5, zoom: 13)
        #expect(isClose(z12 / z13, 2, tolerance: 1e-9))
    }

    @Test("picks a zoom fine enough for the requested resolution")
    func zoomSelection() {
        // 1.8 m/px at this latitude is z16; never return something coarser.
        #expect(WebMercator.zoom(forMetersPerPixel: 1.79, latitude: 41.5, in: 1...16) == 16)
        #expect(WebMercator.zoom(forMetersPerPixel: 7.16, latitude: 41.5, in: 1...16) == 14)
        // Clamped to the range the source actually publishes.
        #expect(WebMercator.zoom(forMetersPerPixel: 0.01, latitude: 41.5, in: 1...16) == 16)
        #expect(WebMercator.zoom(forMetersPerPixel: 100_000, latitude: 41.5, in: 4...16) == 4)
    }

    @Test("clamps beyond the Mercator latitude limit rather than producing nonsense")
    func poles() {
        #expect(TileCoordinate(coordinate: Coordinate(latitude: 89, longitude: 0), zoom: 5) == nil)
        #expect(TileCoordinate(coordinate: Coordinate(latitude: 41.5, longitude: 0), zoom: -1) == nil)
    }
}

@Suite("Tile coordinate")
struct TileCoordinateTests {
    @Test("bounding box matches the reference tile extent")
    func boundingBox() {
        let box = TileCoordinate(z: 14, x: 4947, y: 6113).boundingBox
        #expect(isClose(box.north, 41.492121, tolerance: 1e-5))
        #expect(isClose(box.south, 41.475660, tolerance: 1e-5))
        #expect(isClose(box.west, -71.301270, tolerance: 1e-5))
        #expect(isClose(box.east, -71.279297, tolerance: 1e-5))
    }

    @Test("a tile's own centre resolves back to that tile")
    func centreRoundTrip() throws {
        for tile in [
            TileCoordinate(z: 14, x: 4947, y: 6113),
            TileCoordinate(z: 8, x: 3, y: 200),
            TileCoordinate(z: 16, x: 19788, y: 24452),
        ] {
            let resolved = try #require(TileCoordinate(coordinate: tile.center, zoom: tile.z))
            #expect(resolved == tile)
            #expect(tile.boundingBox.contains(tile.center))
        }
    }

    @Test("validity and path")
    func validity() {
        #expect(TileCoordinate(z: 2, x: 3, y: 3).isValid)
        #expect(!TileCoordinate(z: 2, x: 4, y: 0).isValid)
        #expect(!TileCoordinate(z: 2, x: -1, y: 0).isValid)
        #expect(TileCoordinate(z: 14, x: 4947, y: 6113).path == "14/4947/6113")
    }
}

@Suite("Chart source")
struct ChartSourceTests {
    @Test("fills the template")
    func templating() throws {
        let url = try #require(ChartSource.noaaENC.url(for: TileCoordinate(z: 14, x: 4947, y: 6113)))
        #expect(url.absoluteString.hasSuffix("/14/4947/6113.png"))
    }

    @Test("refuses tiles the source does not publish")
    func outOfRange() {
        #expect(ChartSource.noaaENC.url(for: TileCoordinate(z: 22, x: 1, y: 1)) == nil)
        #expect(ChartSource.noaaENC.url(for: TileCoordinate(z: 4, x: 99, y: 1)) == nil)
    }
}

@Suite("Tile region")
struct TileRegionTests {
    let newport = Coordinate(latitude: 41.49, longitude: -71.30)

    @Test("covers the centre at every zoom in range")
    func coverage() throws {
        let region = TileRegion(center: newport, radius: 5000, zoomRange: 12...16)
        let tiles = region.tiles()
        for zoom in 12...16 {
            let expected = try #require(TileCoordinate(coordinate: newport, zoom: zoom))
            #expect(tiles.contains(expected))
        }
        let allValid = tiles.allSatisfy { $0.isValid }
        #expect(allValid)
        // Coarsest first, so a download is useful before it finishes.
        #expect(tiles.first?.z == 12)
        #expect(tiles.last?.z == 16)
    }

    @Test("a race area is a download worth doing on a phone")
    func size() {
        let region = TileRegion(center: newport, radius: 5000, zoomRange: 12...16)
        // ~700 tiles at roughly 20 KB: a few tens of megabytes at most.
        #expect((500...1000).contains(region.tileCount))
        let megabytes = Double(region.estimatedBytes(for: .noaaENC)) / 1_048_576
        #expect(megabytes > 5 && megabytes < 30)
    }

    @Test("grows with radius and with zoom depth")
    func growth() {
        let small = TileRegion(center: newport, radius: 2000, zoomRange: 12...16)
        let large = TileRegion(center: newport, radius: 10000, zoomRange: 12...16)
        #expect(large.tileCount > small.tileCount)

        let shallow = TileRegion(center: newport, radius: 5000, zoomRange: 12...14)
        let deep = TileRegion(center: newport, radius: 5000, zoomRange: 12...16)
        #expect(deep.tileCount > shallow.tileCount)
    }

    @Test("a tiny region at coarse zoom is a single tile")
    func single() {
        let region = TileRegion(center: newport, radius: 50, zoomRange: 10...10)
        #expect(region.tileCount == 1)
    }
}

@Suite("Chart projection")
struct ChartProjectionTests {
    let newport = Coordinate(latitude: 41.49, longitude: -71.30)
    let size = CGSize(width: 200, height: 240)

    func projection(metersPerPixel: Double = 2) -> ChartProjection {
        ChartProjection(
            center: newport,
            metersPerPixel: metersPerPixel,
            size: size,
            source: .noaaENC
        )
    }

    @Test("the centre coordinate lands in the middle of the view")
    func centre() {
        let point = projection().point(for: newport)
        #expect(isClose(point.x, 100, tolerance: 0.001))
        #expect(isClose(point.y, 120, tolerance: 0.001))
    }

    @Test("offsets scale by metres per pixel, with north up")
    func offsets() {
        let p = projection(metersPerPixel: 2)
        let north = p.point(for: newport.offset(bearing: Bearing(degrees: 0), distance: 100))
        // 100 m at 2 m/px is 50 px, and up the screen is negative y.
        #expect(isClose(north.y, 120 - 50, tolerance: 0.5))
        #expect(isClose(north.x, 100, tolerance: 0.5))

        let east = p.point(for: newport.offset(bearing: Bearing(degrees: 90), distance: 100))
        #expect(isClose(east.x, 100 + 50, tolerance: 0.5))
        #expect(isClose(east.y, 120, tolerance: 0.5))
    }

    @Test("tiles are scaled down while chart detail lasts")
    func scale() {
        // NOAA's finest is z16, about 1.79 m/px at this latitude.
        for mpp in [2.0, 8, 40, 200] {
            let p = projection(metersPerPixel: mpp)
            #expect(p.scale > 0)
            #expect(p.scale <= 1.0001)
            #expect(!p.exceedsSourceDetail)
        }
    }

    @Test("zooming past the finest chart enlarges tiles and says so")
    func beyondDetail() {
        for mpp in [0.5, 1.0] {
            let p = projection(metersPerPixel: mpp)
            #expect(p.zoom == ChartSource.noaaENC.zoomRange.upperBound)
            #expect(p.scale > 1)
            #expect(p.exceedsSourceDetail)
        }
    }

    @Test("visible tiles cover the centre and the rotated corners")
    func visibility() throws {
        let p = projection(metersPerPixel: 2)
        let tiles = p.visibleTiles()
        let centreTile = try #require(TileCoordinate(coordinate: newport, zoom: p.zoom))
        #expect(tiles.contains(centreTile))

        // Everything within the circumscribed circle must be covered, which is
        // what makes course-up rotation safe.
        let radius = hypot(size.width, size.height) / 2
        for bearing in stride(from: 0.0, to: 360.0, by: 45.0) {
            let corner = newport.offset(bearing: Bearing(degrees: bearing), distance: radius * 2)
            let tile = try #require(TileCoordinate(coordinate: corner, zoom: p.zoom))
            #expect(tiles.contains(tile))
        }
    }

    @Test("a tile's rect encloses the coordinates inside it")
    func tileRects() throws {
        let p = projection(metersPerPixel: 2)
        let centreTile = try #require(TileCoordinate(coordinate: newport, zoom: p.zoom))
        let rect = p.rect(for: centreTile)
        #expect(rect.contains(p.point(for: newport)))
        #expect(isClose(rect.width, p.tileSideOnScreen, tolerance: 1e-9))
        #expect(isClose(rect.width, rect.height, tolerance: 1e-9))
    }
}
