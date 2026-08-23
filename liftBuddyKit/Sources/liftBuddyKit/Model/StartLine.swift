import Foundation

/// Which end of the start line.
public enum LineEnd: String, Sendable, Codable, CaseIterable, Hashable {
    /// The port end, marked by a buoy — to your left when looking upwind.
    case pin
    /// The starboard end, the race committee boat — to your right looking upwind.
    case boat

    public var label: String {
        switch self {
        case .pin: "Pin"
        case .boat: "Boat"
        }
    }

    public var other: LineEnd {
        switch self {
        case .pin: .boat
        case .boat: .pin
        }
    }
}

/// A pinged end of the start line, with enough provenance to decide whether it
/// is still worth trusting.
public struct LineMark: Sendable, Hashable, Codable {
    public var coordinate: Coordinate
    public var pingedAt: Date
    /// Horizontal accuracy at the moment of the ping, in meters.
    public var accuracy: Double

    public init(coordinate: Coordinate, pingedAt: Date = Date(), accuracy: Double = -1) {
        self.coordinate = coordinate
        self.pingedAt = pingedAt
        self.accuracy = accuracy
    }
}

/// The start line as surveyed by sailing to each end and pinging it.
///
/// A line needs both ends before any of the interesting math works, so both are
/// optional here and `surveyed` is the gate everything else checks.
public struct StartLine: Sendable, Hashable, Codable {
    public var pin: LineMark?
    public var boat: LineMark?

    public init(pin: LineMark? = nil, boat: LineMark? = nil) {
        self.pin = pin
        self.boat = boat
    }

    public subscript(end: LineEnd) -> LineMark? {
        get {
            switch end {
            case .pin: pin
            case .boat: boat
            }
        }
        set {
            switch end {
            case .pin: pin = newValue
            case .boat: boat = newValue
            }
        }
    }

    /// Both ends pinged — the precondition for bias, distance, and time to line.
    public var isSurveyed: Bool { pin != nil && boat != nil }

    /// Line length in meters, pin to boat.
    public var length: Double? {
        guard let pin, let boat else { return nil }
        return pin.coordinate.distance(to: boat.coordinate)
    }

    /// Bearing along the line from the pin to the committee boat.
    ///
    /// With the pin at the port end, this runs to the right when you look
    /// upwind, which is what fixes the sign of every other calculation here.
    public var axis: Bearing? {
        guard let pin, let boat else { return nil }
        return pin.coordinate.bearing(to: boat.coordinate)
    }

    public var midpoint: Coordinate? {
        // `axis` and `length` already require both ends, so checking the pin is
        // enough to have somewhere to measure from.
        guard let pin, let axis, let length else { return nil }
        return pin.coordinate.offset(bearing: axis, distance: length / 2)
    }

    /// Swaps which end is which — the one-tap fix for pinging them backwards.
    public mutating func swapEnds() {
        (pin, boat) = (boat, pin)
    }

    /// Whether the ends look reversed for the given wind, i.e. the committee
    /// boat is to port rather than starboard when looking upwind.
    ///
    /// A square line runs `wind + 90` from pin to boat, so anything more than a
    /// right angle away from that means the ends are the wrong way round.
    public func endsLookReversed(for wind: Bearing) -> Bool {
        guard let axis else { return false }
        return Bearing(degrees: wind.degrees + 90).separation(to: axis) > 90
    }
}
