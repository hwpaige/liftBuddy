import Foundation
import liftBuddyKit

/// The places you sail, and how much of each is already on disk.
@Observable
final class VenueStore {
    private(set) var venues: [Venue] = []

    @ObservationIgnored private let fileURL: URL

    init(documents: URL = URL.documentsDirectory) {
        fileURL = documents.appendingPathComponent("venues.json", isDirectory: false)
        load()
    }

    func add(_ venue: Venue) {
        venues.append(venue)
        save()
    }

    func remove(_ venue: Venue) {
        venues.removeAll { $0.id == venue.id }
        save()
    }

    func rename(_ venue: Venue, to name: String) {
        guard let index = venues.firstIndex(where: { $0.id == venue.id }) else { return }
        venues[index].name = name
        save()
    }

    /// The venue you are standing in, if any — used to decide what is worth
    /// having on the watch right now.
    func venue(containing coordinate: Coordinate) -> Venue? {
        venues
            .filter { $0.contains(coordinate) }
            .min { $0.distance(to: coordinate) < $1.distance(to: coordinate) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let stored = try? ChartCache.decoder().decode([Venue].self, from: data)
        else { return }
        venues = stored
    }

    private func save() {
        guard let data = try? ChartCache.encoder().encode(venues) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
