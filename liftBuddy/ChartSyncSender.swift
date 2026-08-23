import Foundation
import WatchConnectivity
import liftBuddyKit

/// Hands downloaded chart cells and venue definitions to the watch.
///
/// `transferFile` is used rather than a live message: it is queued by the
/// system, survives both apps being killed, and delivers whenever the watch
/// next comes within reach. Preloading a venue is exactly that kind of job —
/// it should finish on its own while the phone is in a pocket.
@Observable
final class ChartSyncSender: NSObject {
    private(set) var isSupported = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var outstandingTransfers = 0
    private(set) var lastError: String?

    /// Whether there is any point offering to send.
    var canSend: Bool { isSupported && isPaired && isWatchAppInstalled }

    func activate() {
        guard WCSession.isSupported() else { return }
        isSupported = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Tells the watch which venues exist, so it can say where it has charts.
    func send(venues: [Venue]) {
        guard canSend else { return }
        guard let data = try? ChartCache.encoder().encode(venues) else { return }
        do {
            try WCSession.default.updateApplicationContext([ChartSyncKeys.venues: data])
        } catch {
            lastError = "Could not update watch: \(error.localizedDescription)"
        }
    }

    /// Queues every cached cell of a venue for delivery.
    @discardableResult
    func send(cells: [TileCoordinate], fromDocuments documents: URL) -> Int {
        guard canSend else { return 0 }
        let session = WCSession.default
        var queued = 0
        for cell in cells {
            let url = ChartCache.url(inDocuments: documents, cell: cell)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            session.transferFile(url, metadata: ChartCache.metadata(for: cell))
            queued += 1
        }
        refreshOutstanding()
        return queued
    }

    fileprivate func refreshOutstanding() {
        guard isSupported else { return }
        outstandingTransfers = WCSession.default.outstandingFileTransfers.count
    }

    fileprivate func apply(paired: Bool, installed: Bool) {
        isPaired = paired
        isWatchAppInstalled = installed
    }
}

extension ChartSyncSender: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor [weak self] in
            self?.apply(paired: paired, installed: installed)
            self?.refreshOutstanding()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Reactivate so a switch to a different watch keeps working.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor [weak self] in self?.apply(paired: paired, installed: installed) }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: (any Error)?
    ) {
        let message = error?.localizedDescription
        Task { @MainActor [weak self] in
            if let message { self?.lastError = message }
            self?.refreshOutstanding()
        }
    }
}
