import CoreGraphics
import Foundation

/// Maps between geographic coordinates and screen points for a chart view.
///
/// This is the whole reason for rendering the chart ourselves rather than
/// handing it to MapKit: once the projection is ours, anything that can be
/// expressed as a coordinate — laylines, wind ladders, a track, the course —
/// is a few lines of drawing rather than something the map framework has to be
/// persuaded to allow.
///
/// Rotation is deliberately *not* handled here. The caller rotates the whole
/// drawing for course-up, which keeps this a plain north-up projection and
/// keeps the arithmetic testable.
public struct ChartProjection: Sendable {
    public let center: Coordinate
    public let size: CGSize
    public let metersPerPixel: Double
    public let zoom: Int
    public let tileSize: Int
    /// Screen points per tile pixel.
    ///
    /// At most 1 while the requested resolution is within what the source
    /// publishes — tiles are scaled down, so the chart stays sharp. Zoom in
    /// past the source's finest level (NOAA stops around 1.8 m/px) and there is
    /// nothing left to scale down, so tiles are enlarged and the chart goes
    /// soft. That is honest: it is the point where no more chart detail exists.
    public let scale: Double

    public init(
        center: Coordinate,
        metersPerPixel: Double,
        size: CGSize,
        source: ChartSource
    ) {
        self.center = center
        self.size = size
        self.metersPerPixel = metersPerPixel
        self.tileSize = source.tileSize
        let zoom = WebMercator.zoom(
            forMetersPerPixel: metersPerPixel,
            latitude: center.latitude,
            in: source.zoomRange
        )
        self.zoom = zoom
        let tileResolution = WebMercator.metersPerPixel(latitude: center.latitude, zoom: zoom)
        self.scale = metersPerPixel > 0 ? tileResolution / metersPerPixel : 1
    }

    /// Side length of one tile as drawn on screen.
    public var tileSideOnScreen: Double { Double(tileSize) * scale }

    /// True when the view is zoomed in past the finest chart the source has, so
    /// tiles are being enlarged. Worth surfacing rather than hiding: it tells
    /// the reader the detail they are looking at is interpolated, not surveyed.
    public var exceedsSourceDetail: Bool { scale > 1 }

    private var origin: TilePoint { WebMercator.point(for: center, zoom: zoom) }

    public func point(forTilePoint point: TilePoint) -> CGPoint {
        let o = origin
        let side = tileSideOnScreen
        return CGPoint(
            x: size.width / 2 + (point.x - o.x) * side,
            y: size.height / 2 + (point.y - o.y) * side
        )
    }

    public func point(for coordinate: Coordinate) -> CGPoint {
        point(forTilePoint: WebMercator.point(for: coordinate, zoom: zoom))
    }

    /// Where a tile image should be drawn.
    public func rect(for tile: TileCoordinate) -> CGRect {
        let topLeft = point(forTilePoint: TilePoint(x: Double(tile.x), y: Double(tile.y)))
        let side = tileSideOnScreen
        return CGRect(x: topLeft.x, y: topLeft.y, width: side, height: side)
    }

    /// The geographic area on screen, allowing for course-up rotation.
    ///
    /// Uses the circle that circumscribes the view, so the answer holds at any
    /// heading and a feature can never be culled just because the chart turned.
    public func visibleBounds(marginMeters: Double = 0) -> TileBoundingBox {
        let radius = hypot(size.width, size.height) / 2 * metersPerPixel + marginMeters
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

    /// Tiles needed to cover the view at any rotation.
    ///
    /// Uses the circle that circumscribes the view rather than the view rect,
    /// so course-up rotation can never expose an uncovered corner.
    public func visibleTiles() -> [TileCoordinate] {
        let side = tileSideOnScreen
        guard side > 0 else { return [] }
        let radius = hypot(size.width, size.height) / 2
        let reach = radius / side
        let o = origin
        let limit = (1 << zoom) - 1

        let minX = max(Int((o.x - reach).rounded(.down)), 0)
        let maxX = min(Int((o.x + reach).rounded(.down)), limit)
        let minY = max(Int((o.y - reach).rounded(.down)), 0)
        let maxY = min(Int((o.y + reach).rounded(.down)), limit)
        guard minX <= maxX, minY <= maxY else { return [] }

        var tiles: [TileCoordinate] = []
        tiles.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        for x in minX...maxX {
            for y in minY...maxY {
                tiles.append(TileCoordinate(z: zoom, x: x, y: y))
            }
        }
        return tiles
    }
}
