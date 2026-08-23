import Foundation

/// Vertex reduction for chart geometry.
///
/// ENC polygons are surveyed at a precision no watch screen can show. Dropping
/// vertices that sit within a metre or two of the line they lie on cuts a pack
/// by more than half and removes work from every frame, without moving anything
/// far enough to see.
public enum ChartSimplify {
    /// Douglas–Peucker, with tolerance in meters.
    ///
    /// Iterative rather than recursive: chart rings run to thousands of points,
    /// and a recursive implementation on adversarial geometry can run the stack
    /// out.
    public static func douglasPeucker(
        _ points: [Coordinate],
        toleranceMeters: Double
    ) -> [Coordinate] {
        guard points.count > 2, toleranceMeters > 0 else { return points }

        let plane = LocalPlane(origin: points[0])
        let projected = points.map { plane.project($0) }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last > first + 1 else { continue }
            var maxDistance = 0.0
            var maxIndex = first
            for i in (first + 1)..<last {
                let distance = perpendicularDistance(
                    projected[i], from: projected[first], to: projected[last])
                if distance > maxDistance {
                    maxDistance = distance
                    maxIndex = i
                }
            }
            if maxDistance > toleranceMeters {
                keep[maxIndex] = true
                stack.append((first, maxIndex))
                stack.append((maxIndex, last))
            }
        }

        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    /// Simplifies a closed ring, discarding it if there is no area left to draw.
    ///
    /// Vertex count alone is not enough. Simplifying an out-and-back sliver
    /// leaves three collinear points — a well-formed ring enclosing nothing,
    /// which costs pack size and frame time and paints not a single pixel.
    /// ENC data genuinely contains these, so the area is checked too.
    public static func simplifyRing(
        _ points: [Coordinate],
        toleranceMeters: Double
    ) -> [Coordinate]? {
        let simplified = douglasPeucker(points, toleranceMeters: toleranceMeters)
        guard simplified.count >= 3 else { return nil }
        // Anything smaller than the square of the tolerance is below the
        // precision we just claimed to be working at.
        guard abs(area(of: simplified)) > toleranceMeters * toleranceMeters else { return nil }
        return simplified
    }

    /// Signed area of a ring in square meters, by the shoelace formula.
    /// Positive is counter-clockwise.
    public static func area(of ring: [Coordinate]) -> Double {
        guard ring.count >= 3 else { return 0 }
        let plane = LocalPlane(origin: ring[0])
        let points = ring.map { plane.project($0) }
        var total = 0.0
        for i in points.indices {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            total += a.east * b.north - b.east * a.north
        }
        return total / 2
    }

    private static func perpendicularDistance(
        _ point: PlanePoint,
        from start: PlanePoint,
        to end: PlanePoint
    ) -> Double {
        let segment = end - start
        let lengthSquared = segment.dot(segment)
        guard lengthSquared > 0 else { return (point - start).magnitude }
        // Clamped projection, so a point beyond either end measures to that end
        // rather than to the infinite line.
        let t = max(0, min(1, (point - start).dot(segment) / lengthSquared))
        let closest = start + segment * t
        return (point - closest).magnitude
    }
}
