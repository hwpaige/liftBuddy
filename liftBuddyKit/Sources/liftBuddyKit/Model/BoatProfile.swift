import Foundation

/// The boat you are racing. Lives in the shared kit because the phone is where
/// you set it up and the watch is where it gets used.
public struct BoatProfile: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// Length overall in meters — the unit line bias is priced in.
    public var lengthOverall: Double
    /// Meters from the watch on your wrist to the bow. On a dinghy this is
    /// noise; on a 40-footer it is most of a boat length of start line.
    public var bowOffset: Double

    public init(
        id: UUID = UUID(),
        name: String,
        lengthOverall: Double,
        bowOffset: Double = 0
    ) {
        self.id = id
        self.name = name
        self.lengthOverall = lengthOverall
        self.bowOffset = bowOffset
    }

    public static let `default` = BoatProfile(name: "J/70", lengthOverall: 6.9, bowOffset: 2.0)

    /// Common one-designs, so nobody has to look up their own LOA in meters.
    public static let presets: [BoatProfile] = [
        BoatProfile(name: "Optimist", lengthOverall: 2.30, bowOffset: 0.8),
        BoatProfile(name: "ILCA / Laser", lengthOverall: 4.23, bowOffset: 1.5),
        BoatProfile(name: "420", lengthOverall: 4.20, bowOffset: 1.5),
        BoatProfile(name: "470", lengthOverall: 4.70, bowOffset: 1.6),
        BoatProfile(name: "Snipe", lengthOverall: 4.72, bowOffset: 1.6),
        BoatProfile(name: "J/70", lengthOverall: 6.90, bowOffset: 2.0),
        BoatProfile(name: "Melges 24", lengthOverall: 7.32, bowOffset: 2.2),
        BoatProfile(name: "Etchells", lengthOverall: 9.30, bowOffset: 2.8),
        BoatProfile(name: "J/105", lengthOverall: 10.52, bowOffset: 3.2),
    ]
}
