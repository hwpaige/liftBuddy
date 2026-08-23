import Foundation

/// An area to make available offline: a circle around a venue, expanded to
/// whole tiles at every zoom in range.
///
/// Centre-and-radius rather than a drawn rectangle because that is how sailors
/// describe a venue — "ten kilometres around the harbour" — and because the
/// download UI then needs exactly one number.
public struct TileRegion: Sendable, Hashable, Codable {
    public var center: Coordinate
    /// Radius in meters.
    public var radius: Double
    public var zoomRange: ClosedRange<Int>

    public init(center: Coordinate, radius: Double, zoomRange: ClosedRange<Int>) {
        self.center = center
        self.radius = radius
        self.zoomRange = zoomRange
    }

    /// The enclosing box. Uses the tangent-plane offset, whose error at venue
    /// scale is far below one tile, and any error here only ever pulls in a
    /// tile that was not strictly needed.
    public var boundingBox: TileBoundingBox {
        let north = center.offset(bearing: Bearing(degrees: 0), distance: radius)
        let south = center.offset(bearing: Bearing(degrees: 180), distance: radius)
        let east = center.offset(bearing: Bearing(degrees: 90), distance: radius)
        let west = center.offset(bearing: Bearing(degrees: 270), distance: radius)
        return TileBoundingBox(
            north: north.latitude,
            south: south.latitude,
            east: east.longitude,
            west: west.longitude
        )
    }

    /// Every tile covering the region, coarsest zoom first so a download shows
    /// something useful early instead of finishing the fine detail last.
    public func tiles() -> [TileCoordinate] {
        let box = boundingBox
        var result: [TileCoordinate] = []
        for zoom in zoomRange {
            guard
                let topLeft = TileCoordinate(
                    coordinate: Coordinate(latitude: box.north, longitude: box.west), zoom: zoom),
                let bottomRight = TileCoordinate(
                    coordinate: Coordinate(latitude: box.south, longitude: box.east), zoom: zoom)
            else { continue }
            let limit = (1 << zoom) - 1
            for x in min(topLeft.x, bottomRight.x)...max(topLeft.x, bottomRight.x) {
                for y in min(topLeft.y, bottomRight.y)...max(topLeft.y, bottomRight.y) {
                    guard x >= 0, y >= 0, x <= limit, y <= limit else { continue }
                    result.append(TileCoordinate(z: zoom, x: x, y: y))
                }
            }
        }
        return result
    }

    public var tileCount: Int { tiles().count }

    public func estimatedBytes(tileBytes: Int) -> Int { tileCount * tileBytes }

    public func estimatedBytes(for source: ChartSource) -> Int {
        estimatedBytes(tileBytes: source.averageTileBytes)
    }
}
