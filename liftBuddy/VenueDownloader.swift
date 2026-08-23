import Foundation
import liftBuddyKit

/// Fetches every chart cell a venue needs, on the phone.
///
/// This is where the slow, patient work belongs. The service drops roughly a
/// third of requests, which is miserable on a watch mid-race and merely a bit
/// slow on a phone sitting on wifi the night before — so the phone takes the
/// beating and the watch gets finished files.
@Observable
final class VenueDownloader {
    struct Progress: Equatable {
        var completed: Int
        var total: Int
        var failed: Int

        var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
        var isFinished: Bool { completed >= total }
    }

    private(set) var activeVenue: Venue.ID?
    private(set) var progress: Progress?
    private(set) var lastError: String?

    @ObservationIgnored private let service = ENCService()
    @ObservationIgnored private let documents: URL
    @ObservationIgnored private var task: Task<Void, Never>?

    init(documents: URL = URL.documentsDirectory) {
        self.documents = documents
    }

    var isDownloading: Bool { activeVenue != nil }

    /// How much of a venue is already on disk.
    func cachedCellCount(for venue: Venue) -> Int {
        venue.cells.count { isComplete(cell: $0) }
    }

    func isFullyCached(_ venue: Venue) -> Bool {
        cachedCellCount(for: venue) == venue.cellCount
    }

    func start(_ venue: Venue) {
        guard activeVenue == nil else { return }
        activeVenue = venue.id
        lastError = nil
        let cells = venue.cells
        progress = Progress(completed: 0, total: cells.count, failed: 0)

        task = Task { [weak self] in
            guard let self else { return }
            for cell in cells {
                if Task.isCancelled { break }
                if isComplete(cell: cell) {
                    advance()
                    continue
                }
                await fetch(cell)
            }
            finish()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        finish()
    }

    private func fetch(_ cell: TileCoordinate) async {
        let existing = readPack(cell)
        let missing = (existing ?? ChartPack(name: "", bounds: cell.boundingBox))
            .missingLayers(from: ENCDirect.racingLayers)
        guard !missing.isEmpty else {
            advance()
            return
        }
        do {
            let result = try await service.fetch(cell: cell, only: missing)
            var merged = existing ?? result.pack
            if existing != nil { merged.merge(result.pack) }
            write(merged, for: cell)
            advance(failed: result.isComplete ? 0 : 1)
        } catch {
            lastError = error.localizedDescription
            advance(failed: 1)
        }
    }

    private func advance(failed: Int = 0) {
        guard var current = progress else { return }
        current.completed += 1
        current.failed += failed
        progress = current
    }

    private func finish() {
        activeVenue = nil
        task = nil
    }

    // MARK: - Disk

    private func isComplete(cell: TileCoordinate) -> Bool {
        guard let pack = readPack(cell) else { return false }
        return pack.missingLayers(from: ENCDirect.racingLayers).isEmpty
    }

    private func readPack(_ cell: TileCoordinate) -> ChartPack? {
        let url = ChartCache.url(inDocuments: documents, cell: cell)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ChartCache.decoder().decode(ChartPack.self, from: data)
    }

    private func write(_ pack: ChartPack, for cell: TileCoordinate) {
        let url = ChartCache.url(inDocuments: documents, cell: cell)
        guard let data = try? ChartCache.encoder().encode(pack) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
