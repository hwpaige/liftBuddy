import Foundation

/// A run of positions stored as flat longitude/latitude pairs.
///
/// Flat storage rather than `[Coordinate]` for two reasons: it roughly thirds
/// the size of an encoded chart pack, and it hands the renderer a contiguous
/// buffer instead of an array of structs to walk per frame.
public struct ChartPath: Sendable, Hashable, Codable {
    /// Interleaved longitude, latitude, longitude, latitude…
    public var flat: [Double]

    public init(flat: [Double]) {
        self.flat = flat
    }

    public init(_ coordinates: [Coordinate]) {
        var flat: [Double] = []
        flat.reserveCapacity(coordinates.count * 2)
        for c in coordinates {
            flat.append(c.longitude)
            flat.append(c.latitude)
        }
        self.flat = flat
    }

    public var count: Int { flat.count / 2 }
    public var isEmpty: Bool { count == 0 }

    public subscript(index: Int) -> Coordinate {
        Coordinate(latitude: flat[index * 2 + 1], longitude: flat[index * 2])
    }

    public var coordinates: [Coordinate] {
        (0..<count).map { self[$0] }
    }
}

/// An S-57 `DEPARE`: water between two charted depths.
public struct DepthArea: Sendable, Hashable, Codable {
    /// `DRVAL1` — the shallow bound in meters. Nil where the chart does not state one.
    public var minimumDepth: Double?
    /// `DRVAL2` — the deep bound in meters.
    public var maximumDepth: Double?
    /// Outer ring first, then any holes.
    public var rings: [ChartPath]

    public init(minimumDepth: Double?, maximumDepth: Double?, rings: [ChartPath]) {
        self.minimumDepth = minimumDepth
        self.maximumDepth = maximumDepth
        self.rings = rings
    }

    /// The depth to judge this area by: the shallow bound, because what matters
    /// is the least water you might find in it.
    public var governingDepth: Double? { minimumDepth ?? maximumDepth }

    /// 0 for open water, 1 for a drying bank — drives how dark the area is
    /// shaded, following the usual chart convention of darker meaning shallower.
    public var shallowness: Double {
        guard let depth = governingDepth else { return 0 }
        if depth <= 0 { return 1 }
        if depth >= 10 { return 0 }
        return 1 - depth / 10
    }
}

/// An S-57 `DEPCNT`: a line of constant charted depth.
public struct DepthContour: Sendable, Hashable, Codable {
    /// `VALDCO` in meters.
    public var depth: Double?
    public var path: ChartPath

    public init(depth: Double?, path: ChartPath) {
        self.depth = depth
        self.path = path
    }
}

/// An S-57 `LNDARE`.
public struct LandArea: Sendable, Hashable, Codable {
    public var rings: [ChartPath]

    public init(rings: [ChartPath]) {
        self.rings = rings
    }
}

/// What kind of charted object a mark is.
public enum ChartMarkKind: String, Sendable, Codable, CaseIterable {
    case buoyLateral
    case buoySafeWater
    case buoySpecial
    case buoyCardinal
    case buoyIsolatedDanger
    case beacon
    case light
    case daymark
    case obstruction
    case other
}

/// A charted point object — a buoy, beacon or light.
///
/// Racing marks are often government marks, and the ones that are not still
/// have to be told apart from the channel buoys around them, so the S-57
/// colour and shape are carried through rather than flattened to a dot.
public struct ChartMark: Sendable, Hashable, Codable, Identifiable {
    public var id: Int
    public var coordinate: Coordinate
    public var kind: ChartMarkKind
    /// S-57 `COLOUR`, a comma-separated list of colour codes.
    public var colour: String?
    /// S-57 `BOYSHP` or `BCNSHP`.
    public var shape: String?
    /// S-57 `OBJNAM`.
    public var name: String?

    public init(
        id: Int,
        coordinate: Coordinate,
        kind: ChartMarkKind,
        colour: String? = nil,
        shape: String? = nil,
        name: String? = nil
    ) {
        self.id = id
        self.coordinate = coordinate
        self.kind = kind
        self.colour = colour
        self.shape = shape
        self.name = name
    }
}

/// A baked vector chart for one venue.
///
/// This is what replaces a tile pyramid. For a race area it is a couple of
/// hundred kilobytes rather than tens of megabytes, and because it is geometry
/// rather than pixels it stays sharp at any zoom — which matters precisely at
/// start-line scale, where a raster chart has run out of detail.
public struct ChartPack: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var bounds: TileBoundingBox
    public var generatedAt: Date
    public var attribution: String
    public var depthAreas: [DepthArea]
    public var depthContours: [DepthContour]
    public var land: [LandArea]
    public var marks: [ChartMark]
    /// Names of the layers that actually came back.
    ///
    /// A pack missing a layer is still worth keeping and drawing; recording
    /// what is present means a later top-up asks only for the gaps instead of
    /// fetching the whole cell again.
    public var fetchedLayers: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        bounds: TileBoundingBox,
        generatedAt: Date = Date(),
        attribution: String = "NOAA ENC",
        depthAreas: [DepthArea] = [],
        depthContours: [DepthContour] = [],
        land: [LandArea] = [],
        marks: [ChartMark] = [],
        fetchedLayers: [String] = []
    ) {
        self.id = id
        self.name = name
        self.bounds = bounds
        self.generatedAt = generatedAt
        self.attribution = attribution
        self.depthAreas = depthAreas
        self.depthContours = depthContours
        self.land = land
        self.marks = marks
        self.fetchedLayers = fetchedLayers
    }

    /// Layers still to fetch for this pack to be complete.
    public func missingLayers(from all: [ENCDirect.Layer]) -> [ENCDirect.Layer] {
        let have = Set(fetchedLayers)
        return all.filter { !have.contains($0.name) }
    }

    public var isEmpty: Bool {
        depthAreas.isEmpty && depthContours.isEmpty && land.isEmpty && marks.isEmpty
    }

    /// Folds a later fetch into this pack, so a cell that arrived a layer at a
    /// time ends up identical to one fetched in a single go.
    public mutating func merge(_ other: ChartPack) {
        depthAreas.append(contentsOf: other.depthAreas)
        depthContours.append(contentsOf: other.depthContours)
        land.append(contentsOf: other.land)
        marks.append(contentsOf: other.marks)
        for layer in other.fetchedLayers where !fetchedLayers.contains(layer) {
            fetchedLayers.append(layer)
        }
    }

    public var vertexCount: Int {
        depthAreas.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }
            + depthContours.reduce(0) { $0 + $1.path.count }
            + land.reduce(0) { $0 + $1.rings.reduce(0) { $0 + $1.count } }
    }
}

extension ChartPath {
    /// Geographic extent, or `nil` for an empty path.
    public var bounds: TileBoundingBox? {
        guard count > 0 else { return nil }
        var north = -Double.infinity, south = Double.infinity
        var east = -Double.infinity, west = Double.infinity
        for i in stride(from: 0, to: flat.count, by: 2) {
            let longitude = flat[i], latitude = flat[i + 1]
            north = max(north, latitude)
            south = min(south, latitude)
            east = max(east, longitude)
            west = min(west, longitude)
        }
        return TileBoundingBox(north: north, south: south, east: east, west: west)
    }
}

extension TileBoundingBox {
    /// Whether two boxes overlap at all — the cull test every frame runs.
    ///
    /// At start-line zoom a venue pack is almost entirely off screen, so this
    /// is what keeps the frame cost proportional to what is visible rather
    /// than to what was downloaded.
    public func intersects(_ other: TileBoundingBox) -> Bool {
        !(other.west > east || other.east < west || other.south > north || other.north < south)
    }

    public static func union(_ boxes: [TileBoundingBox]) -> TileBoundingBox? {
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) {
            TileBoundingBox(
                north: max($0.north, $1.north),
                south: min($0.south, $1.south),
                east: max($0.east, $1.east),
                west: min($0.west, $1.west)
            )
        }
    }

    /// Grows the box by a margin in meters, so features just off screen are
    /// still drawn and nothing pops in at the edge.
    public func expanded(byMeters margin: Double) -> TileBoundingBox {
        let plane = LocalPlane(origin: center)
        let northEast = plane.unproject(
            plane.project(Coordinate(latitude: north, longitude: east))
                + PlanePoint(east: margin, north: margin))
        let southWest = plane.unproject(
            plane.project(Coordinate(latitude: south, longitude: west))
                + PlanePoint(east: -margin, north: -margin))
        return TileBoundingBox(
            north: northEast.latitude,
            south: southWest.latitude,
            east: northEast.longitude,
            west: southWest.longitude
        )
    }
}
