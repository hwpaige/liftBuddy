import Foundation

/// A starting sequence, named by its warning signal.
public enum StartSequence: Int, Sendable, Codable, Hashable, CaseIterable, Identifiable {
    case three = 3
    case five = 5
    case six = 6
    case ten = 10

    public var id: Int { rawValue }
    public var minutes: Int { rawValue }
    public var duration: TimeInterval { TimeInterval(rawValue) * 60 }

    public var label: String {
        switch self {
        case .three: "3 min"
        case .five: "5 min"
        case .six: "6 min"
        case .ten: "10 min"
        }
    }

    /// Seconds before the start at which the committee makes a sound signal.
    /// RRS 26 is warning, preparatory at −1 minute from warning, one-minute,
    /// then the start.
    public var signalPoints: [TimeInterval] {
        switch self {
        case .three: [180, 120, 60, 0]
        case .five: [300, 240, 60, 0]
        case .six: [360, 180, 60, 0]
        case .ten: [600, 300, 240, 60, 0]
        }
    }
}

/// The starting sequence timer.
///
/// State is a single start date rather than a ticking counter, so the countdown
/// stays correct across app suspension, and every reading is a pure function of
/// the current time.
public struct RaceTimer: Sendable, Hashable, Codable {
    public enum Phase: Sendable, Hashable {
        case idle
        /// Counting down; the value is seconds remaining until the gun.
        case countdown(TimeInterval)
        /// The gun has gone; the value is seconds of elapsed race time.
        case racing(TimeInterval)
    }

    public var sequence: StartSequence
    /// When the gun goes. `nil` means the timer has not been started.
    public private(set) var startDate: Date?

    public init(sequence: StartSequence = .five, startDate: Date? = nil) {
        self.sequence = sequence
        self.startDate = startDate
    }

    public var isRunning: Bool { startDate != nil }

    /// Seconds until the gun. Negative once racing. `nil` when idle.
    public func timeToStart(at now: Date) -> TimeInterval? {
        guard let startDate else { return nil }
        return startDate.timeIntervalSince(now)
    }

    public func phase(at now: Date) -> Phase {
        guard let remaining = timeToStart(at: now) else { return .idle }
        return remaining > 0 ? .countdown(remaining) : .racing(-remaining)
    }

    /// Starts the full sequence from now.
    public mutating func start(at now: Date) {
        startDate = now.addingTimeInterval(sequence.duration)
    }

    /// Snaps the countdown down to the whole minute just passed.
    ///
    /// This is the button you hit on the committee's horn when your timer has
    /// drifted off theirs. It only ever takes time away: rounding to the
    /// nearest minute would sometimes hand a minute back, so pressing sync a
    /// few seconds after starting would jump the clock up rather than trimming
    /// it, which is alarming when you are counting down to a gun.
    ///
    /// The cost of only going down is that syncing while slightly *early* on a
    /// signal loses most of a minute, so it is worth pressing on the horn
    /// rather than in anticipation of it.
    ///
    /// Does nothing once the gun has gone, or inside the final minute where
    /// there is no lower whole minute left to snap to.
    @discardableResult
    public mutating func sync(at now: Date) -> Bool {
        guard let remaining = timeToStart(at: now), remaining > 0 else { return false }
        let snapped = (remaining / 60).rounded(.down) * 60
        guard snapped > 0 else { return false }
        startDate = now.addingTimeInterval(snapped)
        return true
    }

    /// Restarts the sequence from the top — general recall or postponement.
    public mutating func restart(at now: Date) {
        start(at: now)
    }

    /// Nudges the countdown, for a committee that is running the sequence long.
    public mutating func adjust(by seconds: TimeInterval) {
        guard let startDate else { return }
        self.startDate = startDate.addingTimeInterval(seconds)
    }

    public mutating func reset() {
        startDate = nil
    }
}

extension RaceTimer {
    /// Seconds-before-start at which the watch should tap your wrist.
    ///
    /// Dense near zero because that is when you are looking at the line rather
    /// than the watch, and the last ten seconds are counted out by feel.
    public static let hapticCues: [TimeInterval] =
        [600, 300, 240, 180, 120, 60, 30, 20, 10, 5, 4, 3, 2, 1, 0]

    /// The cues crossed by moving from `previous` seconds remaining to `current`.
    ///
    /// Driven off the countdown value rather than a repeating scheduler so that
    /// a dropped or coalesced tick can never silently skip the gun.
    public static func cuesCrossed(
        from previous: TimeInterval,
        to current: TimeInterval
    ) -> [TimeInterval] {
        guard previous > current else { return [] }
        return hapticCues.filter { $0 <= previous && $0 > current }
    }
}
