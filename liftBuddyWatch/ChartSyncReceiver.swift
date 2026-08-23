import Foundation
import WatchConnectivity
import liftBuddyKit
import liftBuddyUI

/// Receives chart cells and venue definitions from the paired phone.
///
/// The phone does the bulk fetching, where a slow, patient download over wifi
/// costs nothing. Anything it has already gathered arrives here as finished
/// files, so the watch spends no radio time on water it was told about in
/// advance — and falls back to fetching for itself only where it was not.
@Observable
final class ChartSyncReceiver: NSObject {
    private(set) var receivedCellCount = 0
    private(set) var lastReceived: Date?
    private(set) var isPhoneReachable = false
    private(set) var venues: [Venue] = []

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    fileprivate func noteReceived(_ cell: TileCoordinate) {
        receivedCellCount += 1
        lastReceived = Date()
        NotificationCenter.default.post(
            name: .chartCellReceived,
            object: nil,
            userInfo: [Notification.Name.chartCellKey: cell]
        )
    }

    fileprivate func apply(venues: [Venue]) {
        self.venues = venues
    }

    fileprivate func apply(reachable: Bool) {
        isPhoneReachable = reachable
    }
}

extension ChartSyncReceiver: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in self?.apply(reachable: reachable) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor [weak self] in self?.apply(reachable: reachable) }
    }

    /// The transferred file is deleted as soon as this returns, so the copy has
    /// to happen here and now rather than being hopped onto another actor.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let cell = ChartCache.cell(from: file.metadata) else { return }
        let destination = ChartCache.url(inDocuments: URL.documentsDirectory, cell: cell)
        let manager = FileManager.default
        do {
            try manager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: file.fileURL, to: destination)
        } catch {
            return
        }
        Task { @MainActor [weak self] in self?.noteReceived(cell) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard let data = applicationContext[ChartSyncKeys.venues] as? Data,
            let venues = try? ChartCache.decoder().decode([Venue].self, from: data)
        else { return }
        Task { @MainActor [weak self] in self?.apply(venues: venues) }
    }
}
