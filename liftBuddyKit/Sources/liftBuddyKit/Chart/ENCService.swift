import Foundation
import os

private let logger = Logger(subsystem: "com.harrison.liftBuddy", category: "chart")

/// An error the service returned in an otherwise successful response.
public struct ArcGISError: Error, Sendable, CustomStringConvertible {
    public var message: String
    public var details: [String]

    public var description: String {
        details.isEmpty ? message : "\(message): \(details.joined(separator: "; "))"
    }

    struct Envelope: Decodable {
        struct Body: Decodable {
            var message: String?
            var details: [String]?
        }
        var error: Body
    }

    static func from(_ data: Data) -> ArcGISError? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        return ArcGISError(
            message: envelope.error.message ?? "Query failed",
            details: envelope.error.details ?? []
        )
    }
}

/// The outcome of fetching one chart cell.
public struct ENCFetchResult: Sendable {
    public var pack: ChartPack
    /// Layers that failed. A cell with any failure is worth drawing but not
    /// worth caching, since the gap would otherwise be permanent.
    public var failedLayers: [String]

    public var isComplete: Bool { failedLayers.isEmpty }
}

/// Fetches S-57 vector charts from NOAA ENC Direct and bakes them into
/// renderable geometry.
///
/// Individual layer failures are tolerated rather than fatal: losing the buoys
/// should not blank the depth contours, and a partly fetched cell is simply
/// topped up later.
///
/// The request strategy is shaped by two measured properties of the service:
///
/// 1. It answers in about 0.26 s or not at all. Roughly a third of requests are
///    dropped and never answered, consistently, across every client and every
///    combination of protocol, compression and concurrency that was tried.
///    So a request that has taken a couple of seconds is not slow, it is dead;
///    the timeout is short and the retries are quick.
/// 2. Reusing a connection makes it much worse — successful requests slow from
///    0.26 s to between one and five seconds, and more of them stall. Each
///    request therefore gets its own connection.
///
/// Ignoring either point costs about a minute per cell.
public struct ENCService: Sendable {
    public var layers: [ENCDirect.Layer]
    /// Vertex tolerance applied at parse time, so what is cached and drawn is
    /// already reduced.
    public var simplifyToleranceMeters: Double
    public var pageSize: Int
    /// Layer requests in flight at once.
    public var maximumConcurrentRequests: Int
    /// Connection lifecycle and the learned request deadline.
    public let transport: ENCTransport

    public init(
        layers: [ENCDirect.Layer] = ENCDirect.racingLayers,
        simplifyToleranceMeters: Double = 2,
        pageSize: Int = 1000,
        maximumConcurrentRequests: Int = 3,
        transport: ENCTransport = ENCTransport()
    ) {
        self.layers = layers
        self.simplifyToleranceMeters = simplifyToleranceMeters
        self.pageSize = pageSize
        self.maximumConcurrentRequests = max(1, maximumConcurrentRequests)
        self.transport = transport
    }

    /// Geometry before marks: the shape of the water is what makes the chart
    /// look like a chart, so it should land in the first round of requests.
    private static func priority(_ role: ENCDirect.LayerRole) -> Int {
        switch role {
        case .depthArea: 0
        case .land: 1
        case .depthContour: 2
        case .mark: 3
        }
    }

    public func fetch(
        cell: TileCoordinate,
        only: [ENCDirect.Layer]? = nil,
        onProgress: (@Sendable (ChartPack) -> Void)? = nil
    ) async throws -> ENCFetchResult {
        try await fetch(
            bounds: cell.boundingBox,
            name: "cell \(cell.path)",
            only: only,
            onProgress: onProgress
        )
    }

    /// - Parameter onProgress: called with everything gathered so far after
    ///   each round of requests. Layers are ordered so the first round is the
    ///   shape of the water, which means the chart can be on screen long
    ///   before the last buoy layer has answered.
    public func fetch(
        bounds: TileBoundingBox,
        name: String,
        only: [ENCDirect.Layer]? = nil,
        onProgress: (@Sendable (ChartPack) -> Void)? = nil
    ) async throws -> ENCFetchResult {
        var pack = ChartPack(
            name: name,
            bounds: bounds,
            attribution: ENCDirect.attribution
        )
        var failed: [String] = []

        let ordered = (only ?? layers).sorted { Self.priority($0.role) < Self.priority($1.role) }
        for window in stride(from: 0, to: ordered.count, by: maximumConcurrentRequests) {
            let chunk = Array(
                ordered[window..<min(window + maximumConcurrentRequests, ordered.count)])
            try await withThrowingTaskGroup(of: (ENCDirect.Layer, [GeoJSONFeature]?).self) { group in
                for layer in chunk {
                    group.addTask {
                        do {
                            return (
                                layer, try await features(of: layer, bounds: bounds)
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return (layer, nil)
                        }
                    }
                }
                for try await (layer, features) in group {
                    guard let features else {
                        failed.append(layer.name)
                        continue
                    }
                    merge(features, from: layer, into: &pack)
                    pack.fetchedLayers.append(layer.name)
                }
            }
            if !pack.isEmpty { onProgress?(pack) }
        }

        return ENCFetchResult(pack: pack, failedLayers: failed)
    }

    // MARK: - Networking

    private func features(
        of layer: ENCDirect.Layer,
        bounds: TileBoundingBox
    ) async throws -> [GeoJSONFeature] {
        var all: [GeoJSONFeature] = []
        var offset = 0
        while true {
            guard
                let url = ENCDirect.queryURL(
                    layer: layer, bounds: bounds, offset: offset, pageSize: pageSize)
            else { break }
            let data = try await load(url)
            let page: GeoJSONCollection
            do {
                page = try JSONDecoder().decode(GeoJSONCollection.self, from: data)
            } catch {
                // ArcGIS answers a bad query with HTTP 200 and an error body.
                // Without this the real reason is buried under a decoding
                // failure, which is how a wrong field name stays hidden.
                throw ArcGISError.from(data) ?? error
            }
            all.append(contentsOf: page.features)
            // Page on the service's own flag, not on a short page. ENC Direct
            // caps responses at its `maxRecordCount` (1000) regardless of what
            // was asked for, so comparing against our own page size silently
            // truncates every dense cell at the cap.
            guard page.exceededTransferLimit == true, !page.features.isEmpty else { break }
            offset += page.features.count
            try Task.checkCancellation()
        }
        return all
    }

    /// Retries quickly rather than waiting patiently.
    ///
    /// ENC Direct answers in about a quarter of a second or not at all — a
    /// measured bimodal split, with roughly a quarter of requests simply never
    /// answering. Waiting out a long timeout is therefore pure loss: the
    /// request that has taken two seconds is not slow, it is dead. Abandoning
    /// it early and asking again costs one round trip and usually succeeds,
    /// which turns a minute of stalling per cell into a few seconds.
    /// Fetches a URL, hedging against the service's habit of never answering.
    ///
    /// ENC Direct replies in a fraction of a second or not at all — about a
    /// third of requests are simply dropped. Waiting out a deadline and then
    /// retrying spends the whole deadline discovering something already known,
    /// so instead a second attempt is launched while the first is still
    /// outstanding, and the first answer to arrive wins. A request that has
    /// taken a second is almost certainly dead; asking again costs one round
    /// trip, and the duplicate is cancelled the moment either succeeds.
    private func load(_ url: URL) async throws -> Data {
        let label = url.pathComponents.suffix(2).joined(separator: "/")
        let started = ContinuousClock.now
        let deadline = await transport.timeout
        let hedge = Self.hedgeDelay

        let data = try await withThrowingTaskGroup(of: Data?.self) { group -> Data? in
            for attempt in 0..<Self.maximumAttempts {
                group.addTask { [self] in
                    if attempt > 0 {
                        try? await Task.sleep(for: .seconds(hedge * Double(attempt)))
                    }
                    if Task.isCancelled { return nil }
                    return try? await single(url, deadline: deadline)
                }
            }
            for try await result in group {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            return nil
        }

        guard let data else {
            logger.error("\(label) no answer from any attempt")
            throw URLError(.timedOut)
        }
        let elapsed = ContinuousClock.now - started
        await transport.record(latency: elapsed.seconds)
        logger.info("\(label) ok \(data.count)B in \(elapsed)")
        return data
    }

    /// One attempt, with its own deadline.
    private func single(_ url: URL, deadline: TimeInterval) async throws -> Data {
        let session = await transport.currentSession()
        await transport.beginRequest()
        defer { Task { await transport.endRequest() } }
        return try await withDeadline(deadline) {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return data
        }
    }

    /// How long to wait before launching a duplicate. Several times the healthy
    /// response time, so a merely-slow request is not doubled needlessly.
    private static let hedgeDelay: TimeInterval = 1.2

    /// Runs `work`, giving up after `seconds`.
    ///
    /// The deadline is enforced here rather than by the session so it can change
    /// between requests as the link is measured; a session's timeout is fixed
    /// when it is created.
    private func withDeadline<T: Sendable>(
        _ seconds: TimeInterval,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
    }

    /// Three attempts against a service that drops roughly a quarter of
    /// requests puts the odds of losing a layer under two percent.
    private static let maximumAttempts = 3

    // MARK: - Baking

    private func merge(
        _ features: [GeoJSONFeature],
        from layer: ENCDirect.Layer,
        into pack: inout ChartPack
    ) {
        switch layer.role {
        case .depthArea:
            for feature in features {
                let rings = simplifiedRings(feature)
                guard !rings.isEmpty else { continue }
                pack.depthAreas.append(
                    DepthArea(
                        minimumDepth: feature.number("DRVAL1"),
                        maximumDepth: feature.number("DRVAL2"),
                        rings: rings
                    ))
            }
        case .land:
            for feature in features {
                let rings = simplifiedRings(feature)
                guard !rings.isEmpty else { continue }
                pack.land.append(LandArea(rings: rings))
            }
        case .depthContour:
            for feature in features {
                let depth = feature.number("VALDCO")
                for line in feature.geometry?.lines ?? [] {
                    let simplified = ChartSimplify.douglasPeucker(
                        line, toleranceMeters: simplifyToleranceMeters)
                    guard simplified.count >= 2 else { continue }
                    pack.depthContours.append(
                        DepthContour(depth: depth, path: ChartPath(simplified)))
                }
            }
        case .mark:
            for feature in features {
                guard let point = feature.geometry?.point else { continue }
                pack.marks.append(
                    ChartMark(
                        id: Int(feature.number("OBJECTID") ?? 0),
                        coordinate: point,
                        kind: layer.markKind ?? .other,
                        colour: feature.text("COLOUR"),
                        shape: feature.text("BOYSHP") ?? feature.text("BCNSHP"),
                        name: feature.text("OBJNAM")
                    ))
            }
        }
    }

    private func simplifiedRings(_ feature: GeoJSONFeature) -> [ChartPath] {
        (feature.geometry?.rings ?? []).compactMap { ring in
            ChartSimplify.simplifyRing(ring, toleranceMeters: simplifyToleranceMeters)
                .map(ChartPath.init)
        }
    }
}
