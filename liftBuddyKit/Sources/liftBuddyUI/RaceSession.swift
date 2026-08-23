// This module is the racing engine and chart renderer shared by the watch
// and phone apps. It is scoped to those two platforms: it speaks CoreLocation
// authorization and haptics, neither of which has a meaningful macOS form, and
// the package still needs to build for macOS so the pure-logic tests can run.
#if os(iOS) || os(watchOS)

import Foundation
import liftBuddyKit

/// The live state of one start: the line you surveyed, the wind you measured,
/// the clock you are running against, and everything derived from those.
///
/// Derived values are computed properties rather than stored state so there is
/// exactly one source of truth. A start line that says one thing on the timer
/// page and another on the line page would be worse than no app at all.
@MainActor
@Observable
public final class RaceSession {
    public var line = StartLine()
    public var wind: Wind?
    public var timer = RaceTimer(sequence: .five)

    /// The boat being raced. Drives both the bow offset applied to every fix and
    /// the boat-length figure that makes line bias mean something.
    public var boat: BoatProfile = .default

    /// The clock the whole UI reads from, so every page agrees on "now".
    public private(set) var now = Date()

    /// Positions gathered for the race being sailed.
    ///
    /// Recording starts with the sequence, not with the gun, because the
    /// prestart is the part worth reviewing — where you were with a minute to
    /// go decides the start far more than anything after it.
    public private(set) var isRecording = false
    public private(set) var recordedTrack: [TrackPoint] = []

    public let location = LocationEngine()

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var lastCountdown: TimeInterval?
    @ObservationIgnored private var lastRecordedFix: Date?

    public init() {}

    // MARK: - Lifecycle

    public func begin() {
        location.start()
        guard ticker == nil else { return }
        // Fast enough that a haptic cue lands within a fifth of a second of the
        // mark, which is well inside what anyone can perceive against a horn.
        let ticker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    public func end() {
        ticker?.invalidate()
        ticker = nil
        location.stop()
    }

    private func tick() {
        now = Date()
        captureTrack()
        guard let remaining = timer.timeToStart(at: now) else {
            lastCountdown = nil
            return
        }
        defer { lastCountdown = remaining }
        // Cues are derived from how far the countdown moved, not from a
        // repeating schedule, so a stalled or coalesced tick cannot swallow the
        // gun — it just fires everything it skipped over.
        guard let previous = lastCountdown else { return }
        for cue in RaceTimer.cuesCrossed(from: previous, to: remaining) {
            Haptics.playCue(secondsBeforeStart: cue)
        }
    }

    // MARK: - Recording

    public func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordedTrack.removeAll()
        lastRecordedFix = nil
    }

    /// Ends the recording and hands back the race, or `nil` if nothing useful
    /// was captured. Leaves the line and wind in place: the next race of the
    /// day is usually on the same line.
    public func finishRecording(named name: String) -> RaceRecord? {
        defer {
            isRecording = false
            recordedTrack.removeAll()
            lastRecordedFix = nil
        }
        guard let gun = timer.startDate, !recordedTrack.isEmpty else { return nil }
        return RaceRecord(
            name: name,
            startedAt: gun,
            endedAt: now,
            line: line.isSurveyed ? line : nil,
            wind: wind,
            boat: boat,
            track: recordedTrack
        )
    }

    /// Appends the current fix, once per fix.
    ///
    /// Driven from the tick rather than from a location callback so there is a
    /// single clock: the tick already knows what "now" is, and the gun is what
    /// every recorded time is measured against.
    private func captureTrack() {
        guard isRecording, let fix = location.fix, let gun = timer.startDate else { return }
        guard fix.timestamp != lastRecordedFix, fix.coordinate.isValid else { return }
        lastRecordedFix = fix.timestamp
        recordedTrack.append(
            TrackPoint(
                time: fix.timestamp.timeIntervalSince(gun),
                coordinate: fix.coordinate,
                speed: max(fix.speed, 0),
                course: fix.hasUsableCourse ? fix.course : nil
            ))
    }

    // MARK: - Derived

    public var fix: BoatFix? { location.fix }

    public var phase: RaceTimer.Phase { timer.phase(at: now) }

    public var timeToStart: TimeInterval? { timer.timeToStart(at: now) }

    public var bias: LineBias? {
        guard let wind else { return nil }
        return line.bias(wind: wind.direction)
    }

    public var approach: LineApproach? {
        guard let fix else { return nil }
        return line.approach(from: fix, bowOffset: boat.bowOffset)
    }

    /// Seconds of slack between the gun and hitting the line at current speed.
    public var burnTime: TimeInterval? {
        guard let approach, let timeToStart, timeToStart > 0 else { return nil }
        return approach.burnTime(timeToStart: timeToStart)
    }

    /// Flags a line pinged with the ends the wrong way round, which silently
    /// inverts every bias call until someone notices.
    public var endsLookReversed: Bool {
        guard let wind else { return false }
        return line.endsLookReversed(for: wind.direction)
    }

    // MARK: - Line

    public func ping(_ end: LineEnd) {
        guard let fix, fix.coordinate.isValid else {
            Haptics.refused()
            return
        }
        line[end] = LineMark(
            coordinate: fix.projectedToBow(boat.bowOffset),
            pingedAt: fix.timestamp,
            accuracy: fix.horizontalAccuracy
        )
        Haptics.pinged()
    }

    public func clearLine() {
        line = StartLine()
        Haptics.cleared()
    }

    public func swapEnds() {
        line.swapEnds()
        Haptics.pinged()
    }

    // MARK: - Wind

    /// Luff head to wind and tap. Uses the compass, not GPS course: stopped and
    /// pointing into the breeze is precisely when course over ground is noise.
    public func setHeadToWind() {
        guard let heading = location.heading else {
            Haptics.refused()
            return
        }
        wind = .headToWind(heading: heading, at: now)
        Haptics.pinged()
    }

    public func setWind(degrees: Double) {
        wind = Wind(direction: Bearing(degrees: degrees), source: .manual, updatedAt: now)
    }

    // MARK: - Timer

    /// One button for the whole sequence: start it, then sync it to the horn.
    public func primaryTimerAction() {
        switch phase {
        case .idle:
            timer.start(at: now)
            lastCountdown = timer.timeToStart(at: now)
            startRecording()
            Haptics.sequenceStarted()
        case .countdown:
            if timer.sync(at: now) {
                lastCountdown = timer.timeToStart(at: now)
                Haptics.tick()
            }
        case .racing:
            // Handled by the view, which has somewhere to save the race to.
            break
        }
    }

    /// Ends the race, returning it to be saved.
    public func finishRace(named name: String) -> RaceRecord? {
        let record = finishRecording(named: name)
        timer.reset()
        lastCountdown = nil
        Haptics.sequenceStopped()
        return record
    }

    public func resetTimer() {
        timer.reset()
        lastCountdown = nil
        Haptics.sequenceStopped()
    }

    public func cycleSequence() {
        let all = StartSequence.allCases
        guard let index = all.firstIndex(of: timer.sequence) else { return }
        timer.sequence = all[(index + 1) % all.count]
        Haptics.tick()
    }
}

#endif
