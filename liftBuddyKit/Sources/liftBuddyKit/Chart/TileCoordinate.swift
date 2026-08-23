import Foundation

/// The geographic extent of a tile.
public struct TileBoundingBox: Sendable, Hashable, Codable {
    public var north: Double
    public var south: Double
    public var east: Double
    public var west: Double

    public init(north: Double, south: Double, east: Double, west: Double) {
        self.north = north
        self.south = south
        self.east = east
        self.west = west
    }

    public var center: Coordinate {
        Coordinate(latitude: (north + south) / 2, longitude: (east + west) / 2)
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        coordinate.latitude <= north && coordinate.latitude >= south
            && coordinate.longitude >= west && coordinate.longitude <= east
    }
}

/// One tile in an XYZ scheme: `z` zoom, `x` column from the antimeridian, `y`
/// row from the north. Origin is top-left, the convention NOAA and OSM use.
public struct TileCoordinate: Sendable, Hashable, Codable, Comparable {
    public let z: Int
    public let x: Int
    public let y: Int

    public init(z: Int, x: Int, y: Int) {
        self.z = z
        self.x = x
        self.y = y
    }

    /// The tile containing `coordinate`. Returns `nil` above the Mercator
    /// latitude limit, where there is no tile to return.
    public init?(coordinate: Coordinate, zoom: Int) {
        guard coordinate.isValid, zoom >= 0 else { return nil }
        guard abs(coordinate.latitude) <= WebMercator.latitudeLimit else { return nil }
        let point = WebMercator.point(for: coordinate, zoom: zoom)
        let limit = 1 << zoom
        self.init(
            z: zoom,
            x: min(max(Int(point.x.rounded(.down)), 0), limit - 1),
            y: min(max(Int(point.y.rounded(.down)), 0), limit - 1)
        )
    }

    /// Number of tiles per side at this zoom.
    public var span: Int { 1 << max(0, z) }

    public var isValid: Bool {
        z >= 0 && x >= 0 && y >= 0 && x < span && y < span
    }

    public var boundingBox: TileBoundingBox {
        let topLeft = WebMercator.coordinate(for: TilePoint(x: Double(x), y: Double(y)), zoom: z)
        let bottomRight = WebMercator.coordinate(
            for: TilePoint(x: Double(x + 1), y: Double(y + 1)),
            zoom: z
        )
        return TileBoundingBox(
            north: topLeft.latitude,
            south: bottomRight.latitude,
            east: bottomRight.longitude,
            west: topLeft.longitude
        )
    }

    public var center: Coordinate { boundingBox.center }

    /// Path component used on disk and in most URL templates: `z/x/y`.
    public var path: String { "\(z)/\(x)/\(y)" }

    public static func < (lhs: TileCoordinate, rhs: TileCoordinate) -> Bool {
        (lhs.z, lhs.x, lhs.y) < (rhs.z, rhs.x, rhs.y)
    }
}
