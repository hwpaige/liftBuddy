import Foundation

/// A place you sail, saved so its charts can be fetched before you get there.
///
/// A circle rather than a drawn rectangle: a venue is "the harbour and the few
/// kilometres of water outside it", which is a centre and a distance, and it
/// takes one number to adjust rather than four corners to drag.
public struct Venue: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var center: Coordinate
    /// Radius in meters.
    public var radius: Double
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        center: Coordinate,
        radius: Double,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.center = center
        self.radius = radius
        self.createdAt = createdAt
    }

    /// Sensible bounds for a race area. Below a kilometre you would sail off the
    /// chart during a single beat; past twenty you are downloading a coastline.
    public static let radiusRange: ClosedRange<Double> = 1_000...20_000

    public var bounds: TileBoundingBox {
        TileRegion(center: center, radius: radius, zoomRange: 0...0).boundingBox
    }

    /// The chart cells this venue needs, nearest the centre first.
    public var cells: [TileCoordinate] {
        ENCDirect.cells(covering: bounds)
    }

    public var cellCount: Int { cells.count }

    /// Whether a position falls inside the venue, used to pick the venue you
    /// are actually at.
    public func contains(_ coordinate: Coordinate) -> Bool {
        center.distance(to: coordinate) <= radius
    }

    public func distance(to coordinate: Coordinate) -> Double {
        center.distance(to: coordinate)
    }
}

extension Venue {
    /// Rough download weight, for warning before a big fetch on a phone.
    ///
    /// A cell of ENC vector runs to a couple of hundred kilobytes once baked,
    /// so this stays in the tens of megabytes even for a large venue.
    public static let approximateBytesPerCell = 180_000

    public var approximateBytes: Int { cellCount * Self.approximateBytesPerCell }
}
