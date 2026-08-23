import Foundation

/// A position in continuous tile space at a given zoom: `x` and `y` in tile
/// units, where the integer part is the tile and the fraction is the position
/// inside it. This is what a renderer needs — whole-tile coordinates alone
/// cannot place a boat within a tile.
public struct TilePoint: Sendable, Hashable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Pixel position, for a source with the given tile size.
    public func pixels(tileSize: Int) -> (x: Double, y: Double) {
        (x * Double(tileSize), y * Double(tileSize))
    }
}

/// The Web Mercator (EPSG:3857) projection used by every XYZ tile service,
/// NOAA's included.
///
/// This is deliberately separate from `LocalPlane`. The tangent plane is right
/// for race geometry — accurate over a course, indifferent to the rest of the
/// world. Mercator is what the tiles are actually drawn in, so anything that
/// has to line up with a chart image has to go through here instead.
public enum WebMercator {
    /// Side length of a standard raster tile, in pixels.
    public static let tileSize = 256

    /// Ground resolution at the equator, meters per pixel at zoom 0.
    public static let equatorialResolution = 156_543.033_928_041

    /// Latitude beyond which Mercator diverges; the projection is clamped here,
    /// as every tile service does.
    public static let latitudeLimit = 85.051_128_779_806_6

    public static func point(for coordinate: Coordinate, zoom: Int) -> TilePoint {
        let n = Double(1 << max(0, zoom))
        let latitude = min(max(coordinate.latitude, -latitudeLimit), latitudeLimit)
        let x = (coordinate.longitude + 180) / 360 * n
        let y = (1 - asinh(tan(latitude * .pi / 180)) / .pi) / 2 * n
        return TilePoint(x: x, y: y)
    }

    public static func coordinate(for point: TilePoint, zoom: Int) -> Coordinate {
        let n = Double(1 << max(0, zoom))
        let longitude = point.x / n * 360 - 180
        let latitude = atan(sinh(.pi * (1 - 2 * point.y / n))) * 180 / .pi
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// Ground resolution in meters per pixel. Mercator stretches with latitude,
    /// so this is only meaningful for a specific one.
    public static func metersPerPixel(latitude: Double, zoom: Int) -> Double {
        equatorialResolution * cos(latitude * .pi / 180) / Double(1 << max(0, zoom))
    }

    /// The zoom whose resolution is closest to `metersPerPixel` without going
    /// coarser — pick the zoom for a camera, then fetch those tiles.
    public static func zoom(
        forMetersPerPixel target: Double,
        latitude: Double,
        in range: ClosedRange<Int>
    ) -> Int {
        guard target > 0 else { return range.upperBound }
        let ideal = log2(equatorialResolution * cos(latitude * .pi / 180) / target)
        return min(max(Int(ideal.rounded(.up)), range.lowerBound), range.upperBound)
    }
}
