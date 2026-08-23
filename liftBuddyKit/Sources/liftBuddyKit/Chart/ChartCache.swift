import Foundation

/// Where baked chart cells live on disk.
///
/// Shared so the phone writes exactly where the watch reads. A plain
/// `charts/cells/z/x/y.json` tree: inspectable, resumable, and each cell is a
/// self-contained file that can be handed across as-is.
public enum ChartCache {
    public static let folder = "charts/cells"

    public static func directory(inDocuments documents: URL) -> URL {
        documents.appendingPathComponent(folder, isDirectory: true)
    }

    public static func url(inDocuments documents: URL, cell: TileCoordinate) -> URL {
        directory(inDocuments: documents)
            .appendingPathComponent("\(cell.z)", isDirectory: true)
            .appendingPathComponent("\(cell.x)", isDirectory: true)
            .appendingPathComponent("\(cell.y).json", isDirectory: false)
    }

    /// Metadata keys used when a cell is handed from phone to watch. The
    /// receiver has only the file and this dictionary to place it by.
    public enum MetadataKey {
        public static let zoom = "z"
        public static let x = "x"
        public static let y = "y"
    }

    public static func metadata(for cell: TileCoordinate) -> [String: Any] {
        [MetadataKey.zoom: cell.z, MetadataKey.x: cell.x, MetadataKey.y: cell.y]
    }

    /// Recovers the cell a transferred file belongs to. Returns `nil` for
    /// anything that did not come from `metadata(for:)`.
    public static func cell(from metadata: [String: Any]?) -> TileCoordinate? {
        guard let metadata,
            let z = metadata[MetadataKey.zoom] as? Int,
            let x = metadata[MetadataKey.x] as? Int,
            let y = metadata[MetadataKey.y] as? Int
        else { return nil }
        let cell = TileCoordinate(z: z, x: x, y: y)
        return cell.isValid ? cell : nil
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Keys shared by both ends of the phone/watch connection.
public enum ChartSyncKeys {
    public static let venues = "venues"
}

extension Notification.Name {
    /// Posted on the watch when a chart cell arrives from the paired phone, so
    /// anything already drawing can pick it up without polling the disk.
    public static let chartCellReceived = Notification.Name("liftBuddy.chartCellReceived")
    /// userInfo key carrying the `TileCoordinate`.
    public static let chartCellKey = "cell"
}
