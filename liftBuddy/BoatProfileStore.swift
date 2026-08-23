import Foundation
import liftBuddyKit

/// Persists the boat you race. The phone is where this gets typed in; the watch
/// is where it gets used.
@Observable
final class BoatProfileStore {
    private static let storageKey = "boatProfile"

    var profile: BoatProfile {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode(BoatProfile.self, from: data)
        {
            profile = stored
        } else {
            profile = .default
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
