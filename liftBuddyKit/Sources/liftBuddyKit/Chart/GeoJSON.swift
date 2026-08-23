import Foundation

/// A decoded JSON value of unknown shape.
///
/// GeoJSON coordinates nest to a different depth for every geometry type, and
/// S-57 attributes mix strings, numbers and nulls in the same field across
/// layers. Rather than write a decoder per layer, decode loosely and pull out
/// what is needed.
public enum JSONValue: Sendable, Hashable, Decodable {
    case number(Double)
    case string(String)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            self = .null
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
        case .number(let value): String(value)
        default: nil
        }
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

extension JSONValue {
    /// A `[longitude, latitude]` leaf pair.
    var asCoordinate: Coordinate? {
        guard let pair = arrayValue, pair.count >= 2,
            let longitude = pair[0].doubleValue,
            let latitude = pair[1].doubleValue
        else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }

    /// An array of coordinate pairs.
    var asPath: [Coordinate] {
        (arrayValue ?? []).compactMap(\.asCoordinate)
    }

    /// An array of paths — a polygon's rings, or a multi-line's lines.
    var asPaths: [[Coordinate]] {
        (arrayValue ?? []).map(\.asPath).filter { !$0.isEmpty }
    }

    /// An array of polygons.
    var asPolygons: [[[Coordinate]]] {
        (arrayValue ?? []).map(\.asPaths).filter { !$0.isEmpty }
    }
}

/// A GeoJSON feature collection, as ArcGIS returns it for `f=geojson`.
public struct GeoJSONCollection: Sendable, Decodable {
    public var features: [GeoJSONFeature]
    /// Set when the service capped the response at its own record limit and
    /// there is more to collect.
    public var exceededTransferLimit: Bool?

    public init(features: [GeoJSONFeature], exceededTransferLimit: Bool? = nil) {
        self.features = features
        self.exceededTransferLimit = exceededTransferLimit
    }
}

public struct GeoJSONFeature: Sendable, Decodable {
    public var geometry: GeoJSONGeometry?
    public var properties: [String: JSONValue]?

    public func property(_ name: String) -> JSONValue? {
        guard let value = properties?[name], value != .null else { return nil }
        return value
    }

    public func number(_ name: String) -> Double? { property(name)?.doubleValue }
    public func text(_ name: String) -> String? { property(name)?.stringValue }
}

public struct GeoJSONGeometry: Sendable, Decodable {
    public var type: String
    public var coordinates: JSONValue

    /// Rings for `Polygon` and `MultiPolygon`; empty for anything else.
    public var rings: [[Coordinate]] {
        switch type {
        case "Polygon": coordinates.asPaths
        case "MultiPolygon": coordinates.asPolygons.flatMap { $0 }
        default: []
        }
    }

    /// Lines for `LineString` and `MultiLineString`.
    public var lines: [[Coordinate]] {
        switch type {
        case "LineString": [coordinates.asPath].filter { !$0.isEmpty }
        case "MultiLineString": coordinates.asPaths
        default: []
        }
    }

    public var point: Coordinate? {
        type == "Point" ? coordinates.asCoordinate : nil
    }
}
