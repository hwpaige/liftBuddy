import Foundation

/// Owns the connection to ENC Direct and decides how long to wait on it.
///
/// Two things were measured, one of which overturned an earlier assumption.
///
/// *Timeouts.* On a warm connection ENC Direct answers in about a quarter of a
/// second, but roughly a third of requests are never answered at all, and a
/// cold start can take ten seconds or more. So the deadline is learned: patient
/// until the link has been measured, then tightened to a multiple of the
/// latency actually observed. A watch reaching the network through its phone
/// settles somewhere much higher than a Mac on wifi, without either being
/// hard-coded.
///
/// *Connections.* An earlier version recycled the connection on every timeout,
/// on the theory that reuse degrades it. That was an artefact of measuring the
/// two strategies in sequence — whichever ran second looked faster, because the
/// server and the connection were warm by then. Reuse is in fact slightly
/// *better* once warm. Worse, recycling mid-flight tore down a session that
/// sibling requests in the same batch were still using, which is what turned
/// one dropped request into a whole slow cell. The connection is now kept, and
/// only ever replaced while nothing is using it.
public actor ENCTransport {
    /// Deadline used before anything has been measured. Patient enough for a
    /// cold start on a slow link.
    public static let initialTimeout: TimeInterval = 20
    /// Never wait less than this, however fast the link looks.
    public static let minimumTimeout: TimeInterval = 3
    public static let maximumTimeout: TimeInterval = 20
    private static let slackFactor: Double = 4
    private static let sampleSize = 8

    private var session: URLSession?
    private var latencies: [TimeInterval] = []
    private var inFlight = 0

    public init() {}

    /// The deadline to apply to the next request.
    ///
    /// Based on the slowest recent success rather than the average: the cost of
    /// being slightly too patient is one slow retry, while being too impatient
    /// abandons requests that would have succeeded.
    public var timeout: TimeInterval {
        guard latencies.count >= 3, let slowest = latencies.max() else {
            return Self.initialTimeout
        }
        return min(max(slowest * Self.slackFactor, Self.minimumTimeout), Self.maximumTimeout)
    }

    public func currentSession() -> URLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.ephemeral
        // The real deadline is enforced per request; these are only backstops.
        configuration.timeoutIntervalForRequest = Self.maximumTimeout * 2
        configuration.timeoutIntervalForResource = Self.maximumTimeout * 3
        // A watch radio may be asleep and the phone link down. Failing instantly
        // rather than waiting a moment for it is the difference between a chart
        // and a blank screen.
        configuration.waitsForConnectivity = true
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        let created = URLSession(configuration: configuration)
        session = created
        return created
    }

    public func beginRequest() { inFlight += 1 }

    public func endRequest() { inFlight = max(0, inFlight - 1) }

    public func record(latency: TimeInterval) {
        latencies.append(latency)
        if latencies.count > Self.sampleSize { latencies.removeFirst() }
    }

    /// Replaces the connection, but only when nothing is using it.
    ///
    /// Tearing down a session that sibling requests are still running turns one
    /// dropped request into a batch of stalled ones.
    @discardableResult
    public func recycleIfIdle() -> Bool {
        guard inFlight == 0 else { return false }
        session?.finishTasksAndInvalidate()
        session = nil
        return true
    }
}

extension Duration {
    /// Seconds as a `Double`, for arithmetic and logging.
    public var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
