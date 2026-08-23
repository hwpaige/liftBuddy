import Foundation

/// An XYZ raster tile service.
///
/// Kept as a value with a URL template rather than hard-coded so the basemap is
/// swappable: NOAA covers US waters only, and anyone racing elsewhere needs a
/// different source without a code change.
public struct ChartSource: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var name: String
    /// Template containing `{z}`, `{x}` and `{y}`.
    public var urlTemplate: String
    public var zoomRange: ClosedRange<Int>
    public var tileSize: Int
    public var attribution: String
    /// Rough average tile weight, used to size a download before starting it.
    public var averageTileBytes: Int

    public init(
        id: String,
        name: String,
        urlTemplate: String,
        zoomRange: ClosedRange<Int>,
        tileSize: Int = WebMercator.tileSize,
        attribution: String,
        averageTileBytes: Int = 20_000
    ) {
        self.id = id
        self.name = name
        self.urlTemplate = urlTemplate
        self.zoomRange = zoomRange
        self.tileSize = tileSize
        self.attribution = attribution
        self.averageTileBytes = averageTileBytes
    }

    public func url(for tile: TileCoordinate) -> URL? {
        guard tile.isValid, zoomRange.contains(tile.z) else { return nil }
        let filled = urlTemplate
            .replacingOccurrences(of: "{z}", with: String(tile.z))
            .replacingOccurrences(of: "{x}", with: String(tile.x))
            .replacingOccurrences(of: "{y}", with: String(tile.y))
        return URL(string: filled)
    }

    /// NOAA's ENC tile service. Free, public, no key, US waters.
    ///
    /// The endpoint could not be reached from the machine this was written on,
    /// so treat the URL as unverified until a tile actually comes back — that
    /// is exactly why this type is configurable.
    public static let noaaENC = ChartSource(
        id: "noaa-enc",
        name: "NOAA ENC",
        urlTemplate: "https://tileservice.charts.noaa.gov/tiles/50000_1/{z}/{x}/{y}.png",
        zoomRange: 1...16,
        attribution: "NOAA ENC",
        averageTileBytes: 20_000
    )

    public static let all: [ChartSource] = [.noaaENC]
}
