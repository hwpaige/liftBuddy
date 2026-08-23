// This module is the racing engine and chart renderer shared by the watch
// and phone apps. It is scoped to those two platforms: it speaks CoreLocation
// authorization and haptics, neither of which has a meaningful macOS form, and
// the package still needs to build for macOS so the pure-logic tests can run.
#if os(iOS) || os(watchOS)

import Foundation
import liftBuddyKit

/// Streams NOAA ENC vector charts for wherever the boat is, and keeps them.
///
/// The world is diced into cells of a few kilometres. Whatever the screen
/// covers is requested, nearest first; everything that arrives is written to
/// disk, so a second visit to a venue needs no network at all. That is the
/// point: fetch while there is signal, race after there is not.
///
/// The fetch policy is deliberately timid. ENC Direct throttles — lean on it
/// and it stops answering for minutes — so failures back off exponentially,
/// a run of them stops the client asking altogether for a while, and a cell
/// that came back short is topped up one layer at a time rather than refetched.
@MainActor
@Observable
public final class ChartStreamer {
    public struct Indexed<Feature: Sendable>: Sendable {
        public let feature: Feature
        public let bounds: TileBoundingBox
    }

    public private(set) var depthAreas: [Indexed<DepthArea>] = []
    public private(set) var depthContours: [Indexed<DepthContour>] = []
    public private(set) var land: [Indexed<LandArea>] = []
    public private(set) var marks: [ChartMark] = []
    public private(set) var lastError: String?
    /// Observed mirrors of the fetch state.
    ///
    /// The dictionaries backing these are deliberately not observed — they
    /// change on every tile and would thrash the view — but that means anything
    /// derived from them directly never triggers a redraw, and the UI sits on a
    /// stale answer. These are the observed truth for the view.
    public private(set) var loadedCellCount = 0
    public private(set) var activeFetchCount = 0

    @ObservationIgnored private var packs: [TileCoordinate: ChartPack] = [:]
    @ObservationIgnored private var loading: Set<TileCoordinate> = []
    @ObservationIgnored private var failures: [TileCoordinate: Int] = [:]
    @ObservationIgnored private var lastAttempt: [TileCoordinate: Date] = [:]
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var lastFailure: Date?

    /// Written once in `init` and read once in `deinit`, which cannot hop to
    /// the main actor. Nothing else touches it.
    @ObservationIgnored private nonisolated(unsafe) var observer: (any NSObjectProtocol)?
    @ObservationIgnored private let service: ENCService
    @ObservationIgnored private let policy = RetryPolicy()

    /// Cells kept in memory — a wide berth around one race area, bounded over
    /// a long day.
    private static let cellLimit = 12
    /// One cell at a time: a cell already issues several layer requests, and
    /// the service will not take a flood of them.
    private static let maximumInFlight = 1

    public init(service: ENCService = ENCService()) {
        self.service = service
        // A cell delivered by the phone is already on disk; forget whatever we
        // knew about it so the next pass reads it rather than refetching.
        observer = NotificationCenter.default.addObserver(
            forName: .chartCellReceived, object: nil, queue: .main
        ) { [weak self] note in
            guard let cell = note.userInfo?[Notification.Name.chartCellKey] as? TileCoordinate
            else { return }
            MainActor.assumeIsolated { self?.forget(cell) }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Drops in-memory state for a cell so it is re-read from disk.
    public func forget(_ cell: TileCoordinate) {
        packs.removeValue(forKey: cell)
        failures.removeValue(forKey: cell)
        lastAttempt.removeValue(forKey: cell)
        rebuildIndex()
    }

    public var hasChart: Bool { !depthAreas.isEmpty || !land.isEmpty || !depthContours.isEmpty }
    public var isFetching: Bool { activeFetchCount > 0 }
    /// True while backing off after repeated refusals.
    public var isThrottled: Bool {
        policy.isTripped(
            consecutiveFailures: consecutiveFailures, lastFailure: lastFailure, now: Date())
    }

    public nonisolated static var cacheDirectory: URL {
        ChartCache.directory(inDocuments: URL.documentsDirectory)
    }

    // MARK: - Driving

    /// Requests whatever the view now covers. Cheap to call on every fix.
    public func update(visibleBounds: TileBoundingBox, at now: Date = Date()) {
        guard !isThrottled else { return }
        let needed = ENCDirect.cells(covering: visibleBounds)
        for cell in needed {
            guard loading.count < Self.maximumInFlight else { break }
            guard shouldLoad(cell, at: now) else { continue }
            loading.insert(cell)
            activeFetchCount = loading.count
            lastAttempt[cell] = now
            Task { [weak self] in await self?.load(cell) }
        }
        evict(keeping: Set(needed))
    }

    private func shouldLoad(_ cell: TileCoordinate, at now: Date) -> Bool {
        guard !loading.contains(cell) else { return false }
        // A cell with every layer present is finished forever.
        if let pack = packs[cell], pack.missingLayers(from: ENCDirect.racingLayers).isEmpty {
            return false
        }
        guard let attempted = lastAttempt[cell] else { return true }
        return policy.shouldRetry(
            failures: failures[cell] ?? 0, since: attempted, now: now)
    }

    private func load(_ cell: TileCoordinate) async {
        defer {
            loading.remove(cell)
            activeFetchCount = loading.count
        }

        // Disk before network, always — a cached cell costs nothing and works
        // with the radio off.
        if packs[cell] == nil, let cached = await Self.readCache(cell) {
            packs[cell] = cached
            rebuildIndex()
        }

        let existing = packs[cell]
        let missing = (existing ?? ChartPack(name: "", bounds: cell.boundingBox))
            .missingLayers(from: ENCDirect.racingLayers)
        guard !missing.isEmpty else {
            failures[cell] = 0
            consecutiveFailures = 0
            return
        }

        do {
            let result = try await service.fetch(cell: cell, only: missing) {
                [weak self] partial in
                guard let self else { return }
                Task { @MainActor in self.absorb(partial, into: cell) }
            }
            absorb(result.pack, into: cell)

            // Whatever came back is cached, gaps and all. Re-fetching a whole
            // cell to recover one missing layer is what gets a client throttled.
            if let pack = packs[cell] {
                await Self.writeCache(pack, for: cell)
            }

            if result.isComplete {
                failures[cell] = 0
                consecutiveFailures = 0
                lastError = nil
            } else {
                failures[cell, default: 0] += 1
                lastError = "Chart incomplete (\(result.failedLayers.count) layers)"
            }
        } catch {
            failures[cell, default: 0] += 1
            consecutiveFailures += 1
            lastFailure = Date()
            lastError = Self.describe(error)
        }
    }

    private func absorb(_ pack: ChartPack, into cell: TileCoordinate) {
        if var existing = packs[cell] {
            // A progress callback resends everything gathered so far, so
            // replace rather than merge when the layer sets overlap.
            let overlaps = pack.fetchedLayers.contains { existing.fetchedLayers.contains($0) }
            if overlaps {
                let keep = existing.fetchedLayers.filter { !pack.fetchedLayers.contains($0) }
                if keep.isEmpty {
                    packs[cell] = pack
                } else {
                    existing.merge(pack)
                    packs[cell] = existing
                }
            } else {
                existing.merge(pack)
                packs[cell] = existing
            }
        } else {
            packs[cell] = pack
        }
        rebuildIndex()
    }

    // MARK: - Index

    /// Flattens the loaded cells into the arrays the renderer walks, with the
    /// per-feature extents it culls against. Done on arrival, not per frame.
    private func rebuildIndex() {
        var areas: [Indexed<DepthArea>] = []
        var contours: [Indexed<DepthContour>] = []
        var landAreas: [Indexed<LandArea>] = []
        var allMarks: [ChartMark] = []

        for pack in packs.values {
            for area in pack.depthAreas {
                if let bounds = TileBoundingBox.union(area.rings.compactMap(\.bounds)) {
                    areas.append(Indexed(feature: area, bounds: bounds))
                }
            }
            for contour in pack.depthContours {
                if let bounds = contour.path.bounds {
                    contours.append(Indexed(feature: contour, bounds: bounds))
                }
            }
            for area in pack.land {
                if let bounds = TileBoundingBox.union(area.rings.compactMap(\.bounds)) {
                    landAreas.append(Indexed(feature: area, bounds: bounds))
                }
            }
            allMarks.append(contentsOf: pack.marks)
        }

        // Shallowest last, so a shoal is never buried under the deep water
        // polygon surrounding it.
        areas.sort { $0.feature.shallowness < $1.feature.shallowness }

        depthAreas = areas
        depthContours = contours
        land = landAreas
        marks = allMarks
        loadedCellCount = packs.count
    }

    private func evict(keeping needed: Set<TileCoordinate>) {
        guard packs.count > Self.cellLimit, let centre = needed.first else { return }
        let removable = packs.keys.filter { !needed.contains($0) }
        guard !removable.isEmpty else { return }
        let farthest = removable.sorted {
            hypot(Double($0.x - centre.x), Double($0.y - centre.y))
                > hypot(Double($1.x - centre.x), Double($1.y - centre.y))
        }
        for cell in farthest.prefix(packs.count - Self.cellLimit) {
            // Dropped from memory only; the cell stays on disk.
            packs.removeValue(forKey: cell)
            lastAttempt.removeValue(forKey: cell)
        }
        rebuildIndex()
    }

    // MARK: - Disk

    private nonisolated static func cacheURL(_ cell: TileCoordinate) -> URL {
        ChartCache.url(inDocuments: URL.documentsDirectory, cell: cell)
    }

    private nonisolated static func readCache(_ cell: TileCoordinate) async -> ChartPack? {
        await Task.detached(priority: .userInitiated) {
            guard let data = try? Data(contentsOf: cacheURL(cell), options: .mappedIfSafe)
            else { return nil }
            return try? ChartCache.decoder().decode(ChartPack.self, from: data)
        }.value
    }

    private nonisolated static func writeCache(_ pack: ChartPack, for cell: TileCoordinate) async {
        await Task.detached(priority: .utility) {
            let url = cacheURL(cell)
            guard let data = try? ChartCache.encoder().encode(pack) else { return }
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }.value
    }

    private nonisolated static func describe(_ error: Error) -> String {
        if let arcgis = error as? ArcGISError { return arcgis.message }
        guard let urlError = error as? URLError else { return "Chart fetch failed" }
        return switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost: "No connection"
        case .timedOut: "Chart service not responding"
        default: "Chart fetch failed"
        }
    }
}

#endif
