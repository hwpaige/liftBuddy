import Foundation

/// Back-off schedule for a service that will push back if you lean on it.
///
/// NOAA ENC Direct throttles: a burst of queries gets the host to stop
/// answering entirely, for minutes, and a client that retries on a fixed short
/// interval simply extends its own outage. Delays grow exponentially and the
/// whole client stops asking after a run of failures.
public struct RetryPolicy: Sendable, Hashable {
    public var baseDelay: TimeInterval
    public var maximumDelay: TimeInterval
    /// Consecutive failures after which the client should stop trying entirely
    /// for `coolDown`.
    public var breakerThreshold: Int
    public var coolDown: TimeInterval

    public init(
        baseDelay: TimeInterval = 30,
        maximumDelay: TimeInterval = 600,
        breakerThreshold: Int = 4,
        coolDown: TimeInterval = 300
    ) {
        self.baseDelay = baseDelay
        self.maximumDelay = maximumDelay
        self.breakerThreshold = breakerThreshold
        self.coolDown = coolDown
    }

    /// Delay before the next attempt, doubling each time up to the cap.
    public func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let exponent = min(failures - 1, 16)
        return min(baseDelay * pow(2, Double(exponent)), maximumDelay)
    }

    public func shouldRetry(failures: Int, since lastAttempt: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastAttempt) >= delay(afterFailures: failures)
    }

    /// Whether the client as a whole should stay quiet, having been refused
    /// repeatedly. Backing off entirely recovers faster than trickling
    /// requests at a host that has stopped answering.
    public func isTripped(consecutiveFailures: Int, lastFailure: Date?, now: Date) -> Bool {
        guard consecutiveFailures >= breakerThreshold, let lastFailure else { return false }
        return now.timeIntervalSince(lastFailure) < coolDown
    }
}
