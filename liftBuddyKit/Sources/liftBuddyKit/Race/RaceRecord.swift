import Foundation

/// One recorded position along a race.
///
/// Time is stored relative to the gun rather than as a date, so a track reads
/// the way a sailor thinks about it: −0:30 is half a minute before the start,
/// and everything positive is racing.
public struct TrackPoint: Sendable, Hashable, Codable {
    /// Seconds from the start. Negative during the prestart.
    public var time: TimeInterval
    public var coordinate: Coordinate
    /// Speed over ground, m/s.
    public var speed: Double
    public var course: Bearing?

    public init(time: TimeInterval, coordinate: Coordinate, speed: Double, course: Bearing?) {
        self.time = time
        self.coordinate = coordinate
        self.speed = speed
        self.course = course
    }

    enum CodingKeys: String, CodingKey {
        case time = "t"
        case coordinate = "c"
        case speed = "s"
        case course = "h"
    }
}

/// A recorded race: the track, and the setup it was sailed against.
public struct RaceRecord: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    /// When the gun went.
    public var startedAt: Date
    public var endedAt: Date
    public var line: StartLine?
    public var wind: Wind?
    public var boat: BoatProfile
    /// Ordered by time, prestart first.
    public var track: [TrackPoint]

    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        endedAt: Date,
        line: StartLine? = nil,
        wind: Wind? = nil,
        boat: BoatProfile = .default,
        track: [TrackPoint] = []
    ) {
        self.id = id
        self.name = name
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.line = line
        self.wind = wind
        self.boat = boat
        self.track = track
    }

    public var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// The part of the track sailed after the gun.
    public var racingTrack: [TrackPoint] { track.filter { $0.time >= 0 } }

    /// The part sailed before it.
    public var prestartTrack: [TrackPoint] { track.filter { $0.time < 0 } }
}
