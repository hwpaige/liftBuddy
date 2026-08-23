#if os(iOS) || os(watchOS)

    import Foundation
    import liftBuddyKit

    /// Saved races, newest first.
    ///
    /// One file per race rather than a single document: a race is written once
    /// and never edited, and keeping them separate means a corrupt or
    /// half-written file costs one race rather than the whole history — and lets
    /// a single race be handed to the phone as-is.
    @MainActor
    @Observable
    public final class RaceStore {
        public private(set) var races: [RaceRecord] = []

        @ObservationIgnored private let directory: URL

        public init(documents: URL = URL.documentsDirectory) {
            directory = documents.appendingPathComponent("races", isDirectory: true)
            load()
        }

        public var isEmpty: Bool { races.isEmpty }

        public func save(_ race: RaceRecord) {
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            guard let data = try? ChartCache.encoder().encode(race) else { return }
            try? data.write(to: url(for: race.id), options: .atomic)
            races.removeAll { $0.id == race.id }
            races.insert(race, at: 0)
            sort()
        }

        public func delete(_ race: RaceRecord) {
            try? FileManager.default.removeItem(at: url(for: race.id))
            races.removeAll { $0.id == race.id }
        }

        /// True if this race is already stored, so a re-send from the watch does
        /// not duplicate it.
        public func contains(_ id: RaceRecord.ID) -> Bool {
            races.contains { $0.id == id }
        }

        public func reload() { load() }

        private func url(for id: RaceRecord.ID) -> URL {
            directory.appendingPathComponent("\(id.uuidString).json", isDirectory: false)
        }

        private func load() {
            guard
                let files = try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: nil)
            else { return }
            let decoder = ChartCache.decoder()
            races = files.compactMap { file in
                guard file.pathExtension == "json",
                    let data = try? Data(contentsOf: file)
                else { return nil }
                return try? decoder.decode(RaceRecord.self, from: data)
            }
            sort()
        }

        private func sort() {
            races.sort { $0.startedAt > $1.startedAt }
        }
    }

#endif
