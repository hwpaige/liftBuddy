import Foundation

/// NOAA's ENC Direct to GIS service — S-57 vector charts served as GeoJSON.
///
/// This is the vector source, not the raster tile rendering of it. The
/// difference matters: geometry stays sharp at any zoom, arrives roughly two
/// orders of magnitude smaller, and carries the S-57 attributes, so a buoy is a
/// buoy with a colour and a name rather than some coloured pixels.
public enum ENCDirect {
    public static let baseURLString =
        "https://encdirect.noaa.gov/arcgis/rest/services/encdirect"

    public static let attribution = "NOAA ENC Direct to GIS (S-57)"

    /// What a layer contributes to the chart.
    public enum LayerRole: String, Sendable, Hashable, Codable {
        case depthArea
        case depthContour
        case land
        case mark

        var defaultOutFields: String {
            switch self {
            case .depthArea: "DRVAL1,DRVAL2"
            case .depthContour: "VALDCO"
            case .land: "OBJECTID"
            // Marks vary by kind; resolved in Layer.init.
            case .mark: "OBJECTID,OBJNAM"
            }
        }
    }

    /// Zoom at which the world is diced into cacheable chart cells.
    ///
    /// A cell is about 3.7 km at mid latitudes — big enough that one covers a
    /// whole race area, so the chart appears after a single round of requests,
    /// and small enough that the round is roughly 60 KB over the wire.
    public static let cellZoom = 13

    /// Decimal places kept on every coordinate. Five is about 1 m, which is
    /// finer than a watch can draw and less than half the bytes of full
    /// precision — the single biggest saving available on this service.
    public static let geometryPrecision = 5

    /// Cells covering an area, nearest the centre first so the chart fills in
    /// from where the boat is rather than from a corner.
    public static func cells(covering bounds: TileBoundingBox) -> [TileCoordinate] {
        guard
            let topLeft = TileCoordinate(
                coordinate: Coordinate(latitude: bounds.north, longitude: bounds.west),
                zoom: cellZoom),
            let bottomRight = TileCoordinate(
                coordinate: Coordinate(latitude: bounds.south, longitude: bounds.east),
                zoom: cellZoom)
        else { return [] }
        let centre = WebMercator.point(for: bounds.center, zoom: cellZoom)
        var cells: [TileCoordinate] = []
        for x in min(topLeft.x, bottomRight.x)...max(topLeft.x, bottomRight.x) {
            for y in min(topLeft.y, bottomRight.y)...max(topLeft.y, bottomRight.y) {
                let cell = TileCoordinate(z: cellZoom, x: x, y: y)
                if cell.isValid { cells.append(cell) }
            }
        }
        return cells.sorted {
            hypot(Double($0.x) + 0.5 - centre.x, Double($0.y) + 0.5 - centre.y)
                < hypot(Double($1.x) + 0.5 - centre.x, Double($1.y) + 0.5 - centre.y)
        }
    }

    /// One queryable layer in one usage band.
    public struct Layer: Sendable, Hashable, Codable {
        public var service: String
        public var id: Int
        public var name: String
        public var role: LayerRole
        public var markKind: ChartMarkKind?
        /// Only the S-57 attributes actually rendered. Asking for `*` drags
        /// down thirty-odd mostly-null fields per feature.
        public var outFields: String

        public init(
            service: String,
            id: Int,
            name: String,
            role: LayerRole,
            markKind: ChartMarkKind? = nil,
            outFields: String? = nil
        ) {
            self.service = service
            self.id = id
            self.name = name
            self.role = role
            self.markKind = markKind
            self.outFields = outFields ?? Layer.fields(for: role, markKind: markKind)
        }

        /// Attribute lists are per layer, not per role.
        ///
        /// Naming a field a layer does not have makes the service reject the
        /// whole query — a buoy has `BOYSHP` and no `BCNSHP`, a beacon the
        /// reverse, a light neither, and an obstruction not even `COLOUR`. Ask
        /// for one wrong name and that layer silently vanishes from the chart.
        /// These were read off the live service.
        static func fields(for role: LayerRole, markKind: ChartMarkKind?) -> String {
            guard role == .mark else { return role.defaultOutFields }
            return switch markKind {
            case .buoyLateral, .buoySafeWater, .buoySpecial, .buoyCardinal, .buoyIsolatedDanger:
                "OBJECTID,COLOUR,BOYSHP,OBJNAM"
            case .beacon, .daymark:
                "OBJECTID,COLOUR,BCNSHP,OBJNAM"
            case .light:
                "OBJECTID,COLOUR,OBJNAM"
            default:
                "OBJECTID,OBJNAM"
            }
        }
    }

    /// The layers worth carrying for racing, in the harbour usage band.
    ///
    /// Deliberately short. A full chart has hundreds of layers, almost none of
    /// which change a tactical decision; what does is where the land is, where
    /// it is too shallow to go, and which marks are out there. Layer numbers
    /// are per-service, and these were read from the live service catalogue —
    /// other usage bands number their layers differently.
    public static let racingLayers: [Layer] = [
        Layer(service: "enc_harbour", id: 227, name: "Harbor.Depth_Area", role: .depthArea),
        Layer(service: "enc_harbour", id: 104, name: "Harbor.Depth_Contour_line", role: .depthContour),
        Layer(service: "enc_harbour", id: 233, name: "Harbor.Land_Area", role: .land),
        Layer(service: "enc_harbour", id: 6, name: "Harbour.Buoy_Lateral_point", role: .mark, markKind: .buoyLateral),
        Layer(service: "enc_harbour", id: 7, name: "Harbour.Buoy_Safe_Water_point", role: .mark, markKind: .buoySafeWater),
        Layer(service: "enc_harbour", id: 8, name: "Harbour.Buoy_Special_Purpose_General_point", role: .mark, markKind: .buoySpecial),
        Layer(service: "enc_harbour", id: 4, name: "Harbour.Buoy_Cardinal_point", role: .mark, markKind: .buoyCardinal),
        Layer(service: "enc_harbour", id: 5, name: "Harbour.Buoy_Isolated_Danger_point", role: .mark, markKind: .buoyIsolatedDanger),
        Layer(service: "enc_harbour", id: 1, name: "Harbour.Beacon_Lateral_point", role: .mark, markKind: .beacon),
        Layer(service: "enc_harbour", id: 11, name: "Harbour.Light_point", role: .mark, markKind: .light),
        Layer(service: "enc_harbour", id: 33, name: "Harbor.Obstruction_point", role: .mark, markKind: .obstruction),
    ]

    /// Builds one page of an ArcGIS feature query.
    ///
    /// The service pages results, so a caller keeps raising `offset` until it
    /// gets back fewer features than it asked for.
    public static func queryURL(
        layer: Layer,
        bounds: TileBoundingBox,
        offset: Int = 0,
        pageSize: Int = 1000,
        geometryPrecision: Int? = ENCDirect.geometryPrecision
    ) -> URL? {
        var components = URLComponents(
            string: "\(baseURLString)/\(layer.service)/MapServer/\(layer.id)/query"
        )
        components?.queryItems = [
            URLQueryItem(name: "where", value: "1=1"),
            URLQueryItem(
                name: "geometry",
                value: "\(bounds.west),\(bounds.south),\(bounds.east),\(bounds.north)"
            ),
            URLQueryItem(name: "geometryType", value: "esriGeometryEnvelope"),
            URLQueryItem(name: "inSR", value: "4326"),
            URLQueryItem(name: "spatialRel", value: "esriSpatialRelIntersects"),
            URLQueryItem(name: "returnGeometry", value: "true"),
            URLQueryItem(name: "outSR", value: "4326"),
            URLQueryItem(name: "outFields", value: layer.outFields),
            URLQueryItem(name: "f", value: "geojson"),
            URLQueryItem(name: "resultOffset", value: String(offset)),
            URLQueryItem(name: "resultRecordCount", value: String(pageSize)),
        ]
        if let geometryPrecision {
            components?.queryItems?.append(
                URLQueryItem(name: "geometryPrecision", value: String(geometryPrecision)))
        }
        return components?.url
    }
}
