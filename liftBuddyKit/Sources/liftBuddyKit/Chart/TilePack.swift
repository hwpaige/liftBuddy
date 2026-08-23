import Foundation

/// Metadata for a downloaded offline chart area.
public struct TilePack: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    /// Human name for the venue: "Newport", "Cowes".
    public var name: String
    public var sourceID: String
    public var region: TileRegion
    public var tileCount: Int
    public var byteCount: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        sourceID: String,
        region: TileRegion,
        tileCount: Int,
        byteCount: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.sourceID = sourceID
        self.region = region
        self.tileCount = tileCount
        self.byteCount = byteCount
        self.createdAt = createdAt
    }
}

/// Where tiles live on disk.
///
/// A plain `z/x/y.png` tree rather than a database: it is trivially inspectable,
/// resumable (a missing file is simply re-fetched), and transfers to the watch
/// as an ordinary directory.
public enum TilePackLayout {
    public static let indexFileName = "pack.json"

    public static func sourceDirectory(root: URL, sourceID: String) -> URL {
        root.appendingPathComponent(sourceID, isDirectory: true)
    }

    public static func fileURL(root: URL, sourceID: String, tile: TileCoordinate) -> URL {
        sourceDirectory(root: root, sourceID: sourceID)
            .appendingPathComponent("\(tile.z)", isDirectory: true)
            .appendingPathComponent("\(tile.x)", isDirectory: true)
            .appendingPathComponent("\(tile.y).png", isDirectory: false)
    }

    public static func indexURL(root: URL, sourceID: String) -> URL {
        sourceDirectory(root: root, sourceID: sourceID)
            .appendingPathComponent(indexFileName, isDirectory: false)
    }
}
