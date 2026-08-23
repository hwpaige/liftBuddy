import Foundation

/// Where the boat sits relative to the start line, and how fast that is changing.
public struct LineApproach: Sendable, Hashable {
    /// Distance in meters to the line as it actually matters: measured
    /// perpendicular while between the ends, and to the nearer end once past
    /// them — because outside the ends the perpendicular is to water you would
    /// have to sail around.
    public var distanceToLine: Double
    /// Signed perpendicular distance in meters. Positive on the pre-start side,
    /// negative once over.
    public var perpendicularDistance: Double
    public var isOverEarly: Bool
    /// Rate the gap is closing, m/s. Negative means opening.
    public var closingSpeed: Double
    /// Seconds to reach the line at the current closing speed, or `nil` when
    /// not closing on it at all.
    public var timeToLine: TimeInterval?
    public var distanceToPin: Double
    public var distanceToBoat: Double
    /// Position along the line: 0 at the pin, 1 at the committee boat.
    /// Values outside that range mean the boat is past an end.
    public var positionAlongLine: Double
    public var isBetweenEnds: Bool

    /// Below this closing speed a time-to-line figure is meaningless noise.
    static let minimumClosingSpeed = Units.metersPerSecond(fromKnots: 0.2)

    /// Seconds of slack: how long you could stall and still hit the line on the
    /// gun. Positive means time to burn, negative means you are already late.
    public func burnTime(timeToStart: TimeInterval) -> TimeInterval? {
        guard let timeToLine else { return nil }
        return timeToStart - timeToLine
    }
}

extension StartLine {
    /// Resolves the boat's position against the line.
    ///
    /// - Parameters:
    ///   - fix: the current GPS fix.
    ///   - bowOffset: meters from the watch to the bow, projected along course.
    public func approach(from fix: BoatFix, bowOffset: Double = 0) -> LineApproach? {
        guard let pin, let boat, let axis, let length, length > 0 else { return nil }

        let position = fix.projectedToBow(bowOffset)
        let plane = LocalPlane(origin: pin.coordinate)
        let p = plane.project(position)
        let pinPoint = PlanePoint.zero
        let boatPoint = plane.project(boat.coordinate)

        let along = PlanePoint.unit(axis)
        // Rotating the line axis to port points upwind, to the course side.
        let upwind = along.rotatedLeft

        let distanceAlong = p.dot(along)
        let upwindOffset = p.dot(upwind)

        let perpendicular = -upwindOffset
        let isOver = upwindOffset > 0
        let positionAlongLine = distanceAlong / length
        let isBetweenEnds = distanceAlong >= 0 && distanceAlong <= length

        let distanceToPin = (p - pinPoint).magnitude
        let distanceToBoat = (p - boatPoint).magnitude

        // Once past an end, the gap that matters is to that end, not to the
        // line extended off into open water.
        let target: PlanePoint
        let distance: Double
        if isBetweenEnds {
            target = p + upwind * (-upwindOffset)
            distance = abs(perpendicular)
        } else if distanceAlong < 0 {
            target = pinPoint
            distance = distanceToPin
        } else {
            target = boatPoint
            distance = distanceToBoat
        }

        var closingSpeed = 0.0
        if fix.hasUsableCourse, let course = fix.course {
            let velocity = PlanePoint.unit(course) * fix.speed
            let gap = target - p
            if gap.magnitude > 0.01 {
                let toTarget = gap * (1 / gap.magnitude)
                closingSpeed = velocity.dot(toTarget)
            }
        }

        let timeToLine: TimeInterval? =
            closingSpeed > LineApproach.minimumClosingSpeed ? distance / closingSpeed : nil

        return LineApproach(
            distanceToLine: distance,
            perpendicularDistance: perpendicular,
            isOverEarly: isOver,
            closingSpeed: closingSpeed,
            timeToLine: timeToLine,
            distanceToPin: distanceToPin,
            distanceToBoat: distanceToBoat,
            positionAlongLine: positionAlongLine,
            isBetweenEnds: isBetweenEnds
        )
    }
}
