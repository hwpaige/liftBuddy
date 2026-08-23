import Testing
import Foundation
@testable import liftBuddyKit

func decodeFeatures(_ json: String) throws -> [GeoJSONFeature] {
    try JSONDecoder().decode(GeoJSONCollection.self, from: Data(json.utf8)).features
}

@Suite("GeoJSON decoding")
struct GeoJSONTests {
    @Test("reads the geometry types ENC actually returns")
    func geometryTypes() throws {
        let features = try decodeFeatures(
            """
            {"type":"FeatureCollection","features":[
              {"type":"Feature","geometry":{"type":"Polygon","coordinates":
                [[[-71.3,41.5],[-71.2,41.5],[-71.2,41.6],[-71.3,41.5]],
                 [[-71.28,41.52],[-71.26,41.52],[-71.26,41.54],[-71.28,41.52]]]},
               "properties":{"DRVAL1":0,"DRVAL2":2}},
              {"type":"Feature","geometry":{"type":"MultiPolygon","coordinates":
                [[[[-71.1,41.1],[-71.0,41.1],[-71.0,41.2],[-71.1,41.1]]],
                 [[[-70.9,41.1],[-70.8,41.1],[-70.8,41.2],[-70.9,41.1]]]]},
               "properties":{}},
              {"type":"Feature","geometry":{"type":"LineString","coordinates":
                [[-71.3,41.5],[-71.25,41.55]]},"properties":{"VALDCO":10}},
              {"type":"Feature","geometry":{"type":"MultiLineString","coordinates":
                [[[-71.3,41.5],[-71.25,41.55]],[[-71.2,41.5],[-71.1,41.5]]]},"properties":{}},
              {"type":"Feature","geometry":{"type":"Point","coordinates":[-71.35,41.48]},
               "properties":{"COLOUR":"4","OBJNAM":"Bell Buoy 11","OBJECTID":101084}}
            ]}
            """)
        #expect(features.count == 5)

        // Polygon: outer ring plus a hole.
        #expect(features[0].geometry?.rings.count == 2)
        #expect(features[0].geometry?.rings.first?.count == 4)
        #expect(features[0].number("DRVAL1") == 0)
        #expect(features[0].number("DRVAL2") == 2)

        // MultiPolygon flattens to all its rings.
        #expect(features[1].geometry?.rings.count == 2)

        #expect(features[2].geometry?.lines.count == 1)
        #expect(features[2].number("VALDCO") == 10)
        #expect(features[3].geometry?.lines.count == 2)

        let point = try #require(features[4].geometry?.point)
        #expect(isClose(point.latitude, 41.48))
        #expect(isClose(point.longitude, -71.35))
        #expect(features[4].text("OBJNAM") == "Bell Buoy 11")
        #expect(features[4].text("COLOUR") == "4")
        #expect(Int(features[4].number("OBJECTID") ?? 0) == 101084)
    }

    @Test("a geometry only yields the shapes of its own type")
    func typeDiscipline() throws {
        let features = try decodeFeatures(
            """
            {"type":"FeatureCollection","features":[
              {"type":"Feature","geometry":{"type":"Point","coordinates":[-71.3,41.5]},
               "properties":{}}]}
            """)
        #expect(features[0].geometry?.rings.isEmpty == true)
        #expect(features[0].geometry?.lines.isEmpty == true)
        #expect(features[0].geometry?.point != nil)
    }

    @Test("nulls, missing geometry and blank strings read as absent")
    func missingValues() throws {
        let features = try decodeFeatures(
            """
            {"type":"FeatureCollection","features":[
              {"type":"Feature","geometry":null,
               "properties":{"DRVAL1":null,"OBJNAM":"  ","COLOUR":"3"}}]}
            """)
        #expect(features[0].geometry == nil)
        #expect(features[0].number("DRVAL1") == nil)
        #expect(features[0].number("NOT_THERE") == nil)
        // S-57 pads unused text attributes with spaces; that is not a name.
        #expect(features[0].text("OBJNAM") == nil)
        #expect(features[0].text("COLOUR") == "3")
    }

    @Test("numeric attributes survive being sent as strings")
    func looseNumbers() throws {
        let features = try decodeFeatures(
            """
            {"type":"FeatureCollection","features":[
              {"type":"Feature","geometry":null,"properties":{"VALDCO":"18.3"}}]}
            """)
        #expect(isClose(features[0].number("VALDCO") ?? 0, 18.3))
    }
}

@Suite("Chart cells")
struct ChartCellTests {
    @Test("a cell is a few kilometres across")
    func cellSize() throws {
        let cell = try #require(
            TileCoordinate(
                coordinate: Coordinate(latitude: 41.49882, longitude: -71.33318),
                zoom: ENCDirect.cellZoom))
        let box = cell.boundingBox
        let width = Coordinate(latitude: box.north, longitude: box.west)
            .distance(to: Coordinate(latitude: box.north, longitude: box.east))
        #expect(width > 2500 && width < 5000)
    }

    @Test("cells cover the area, nearest the centre first")
    func covering() throws {
        let centre = Coordinate(latitude: 41.49882, longitude: -71.33318)
        let bounds = TileBoundingBox(
            north: 41.53, south: 41.46, east: -71.29, west: -71.38)
        let cells = ENCDirect.cells(covering: bounds)
        #expect(cells.count > 1)

        let centreCell = try #require(
            TileCoordinate(coordinate: bounds.center, zoom: ENCDirect.cellZoom))
        // The chart must fill in from where the boat is, not from a corner.
        #expect(cells.first == centreCell)

        // Everything in the box is covered by some cell.
        for probe in [centre, Coordinate(latitude: 41.52, longitude: -71.37)] {
            let cell = try #require(TileCoordinate(coordinate: probe, zoom: ENCDirect.cellZoom))
            #expect(cells.contains(cell))
        }
    }

    @Test("a tiny area still needs one cell")
    func single() {
        let point = TileBoundingBox(north: 41.5, south: 41.5, east: -71.3, west: -71.3)
        #expect(ENCDirect.cells(covering: point).count == 1)
    }
}

@Suite("ENC query tuning")
struct ENCQueryTuningTests {
    @Test("asks only for the attributes it draws, at reduced precision")
    func tuning() throws {
        let bounds = TileBoundingBox(north: 41.53, south: 41.44, east: -71.27, west: -71.36)
        for layer in ENCDirect.racingLayers {
            let url = try #require(ENCDirect.queryURL(layer: layer, bounds: bounds))
            let items = Dictionary(
                uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems ?? []).map { ($0.name, $0.value ?? "") })
            #expect(items["outFields"] != "*")
            #expect(items["outFields"] == layer.outFields)
            #expect(items["geometryPrecision"] == "5")
        }
    }

    @Test("precision can be turned off when full fidelity is wanted")
    func fullPrecision() throws {
        let bounds = TileBoundingBox(north: 41.53, south: 41.44, east: -71.27, west: -71.36)
        let layer = ENCDirect.racingLayers[0]
        let url = try #require(
            ENCDirect.queryURL(layer: layer, bounds: bounds, geometryPrecision: nil))
        #expect(!url.absoluteString.contains("geometryPrecision"))
    }
}

@Suite("ENC layer attributes")
struct ENCLayerFieldTests {
    /// Naming a field a layer does not have makes ENC Direct reject the entire
    /// query, so the layer just disappears from the chart with no error worth
    /// reading. These lists were read off the live service; pin them.
    @Test("no mark layer asks for a shape attribute it does not have")
    func shapeFields() {
        for layer in ENCDirect.racingLayers where layer.role == .mark {
            let fields = Set(layer.outFields.split(separator: ",").map(String.init))
            #expect(!(fields.contains("BOYSHP") && fields.contains("BCNSHP")))
            #expect(fields.contains("OBJECTID"))

            switch layer.markKind {
            case .buoyLateral, .buoySafeWater, .buoySpecial, .buoyCardinal, .buoyIsolatedDanger:
                #expect(fields.contains("BOYSHP"))
                #expect(!fields.contains("BCNSHP"))
            case .beacon, .daymark:
                #expect(fields.contains("BCNSHP"))
                #expect(!fields.contains("BOYSHP"))
            case .light:
                #expect(fields.contains("COLOUR"))
                #expect(!fields.contains("BOYSHP"))
                #expect(!fields.contains("BCNSHP"))
            case .obstruction:
                // Obstructions carry no colour at all.
                #expect(!fields.contains("COLOUR"))
            default:
                break
            }
        }
    }

    @Test("geometry layers ask only for the depth attributes they render")
    func geometryFields() throws {
        let byRole = Dictionary(
            grouping: ENCDirect.racingLayers, by: \.role
        ).mapValues { $0.map(\.outFields) }
        #expect(byRole[.depthArea] == ["DRVAL1,DRVAL2"])
        #expect(byRole[.depthContour] == ["VALDCO"])
    }
}

@Suite("ArcGIS error envelope")
struct ArcGISErrorTests {
    @Test("an error returned with HTTP 200 is recognised, not mistaken for bad JSON")
    func envelope() throws {
        let data = Data(
            """
            {"error":{"code":400,"message":"Failed to execute query.",
             "details":["Invalid field: BCNSHP"]}}
            """.utf8)
        let error = try #require(ArcGISError.from(data))
        #expect(error.message == "Failed to execute query.")
        #expect(error.details == ["Invalid field: BCNSHP"])
        #expect(error.description.contains("BCNSHP"))
    }

    @Test("a normal feature collection is not read as an error")
    func notAnError() {
        let data = Data(#"{"type":"FeatureCollection","features":[]}"#.utf8)
        #expect(ArcGISError.from(data) == nil)
    }
}
