#if os(iOS) || os(watchOS)

    import SwiftUI
    import liftBuddyKit

    /// A recorded race drawn as a track against its start line.
    ///
    /// North-up and framed to fit the whole race, because this is for reading
    /// afterwards rather than steering by: the shape of the beat and where the
    /// start was made relative to the line are what you are looking for.
    public struct RaceTrackView: View {
        let race: RaceRecord
        var showsStartLine: Bool

        public init(race: RaceRecord, showsStartLine: Bool = true) {
            self.race = race
            self.showsStartLine = showsStartLine
        }

        public var body: some View {
            GeometryReader { geometry in
                Canvas { context, size in
                    guard let projection = projection(for: size) else { return }
                    if showsStartLine { drawLine(&context, projection) }
                    drawTrack(&context, projection)
                    drawGun(&context, projection)
                }
            }
        }

        // MARK: - Framing

        private var allCoordinates: [Coordinate] {
            var all = race.track.map(\.coordinate)
            if let pin = race.line?.pin { all.append(pin.coordinate) }
            if let boat = race.line?.boat { all.append(boat.coordinate) }
            return all
        }

        private func projection(for size: CGSize) -> ChartProjection? {
            let all = allCoordinates
            guard !all.isEmpty, size.width > 0, size.height > 0 else { return nil }
            let north = all.map(\.latitude).max()!
            let south = all.map(\.latitude).min()!
            let east = all.map(\.longitude).max()!
            let west = all.map(\.longitude).min()!
            let centre = Coordinate(latitude: (north + south) / 2, longitude: (east + west) / 2)

            let tall = Coordinate(latitude: north, longitude: centre.longitude)
                .distance(to: Coordinate(latitude: south, longitude: centre.longitude))
            let wide = Coordinate(latitude: centre.latitude, longitude: west)
                .distance(to: Coordinate(latitude: centre.latitude, longitude: east))

            // Fit the larger dimension with a margin, and never divide by zero
            // for a race that never moved.
            let metersPerPixel = max(
                max(tall / size.height, wide / size.width) * 1.2,
                0.25
            )
            return ChartProjection(
                center: centre, metersPerPixel: metersPerPixel, size: size, source: .noaaENC)
        }

        // MARK: - Drawing

        private func drawTrack(_ context: inout GraphicsContext, _ projection: ChartProjection) {
            // The prestart is drawn faintly so the racing track reads first,
            // while still showing how the approach was set up.
            stroke(race.prestartTrack, in: &context, projection, colour: .cyan.opacity(0.45), width: 1.5)
            stroke(race.racingTrack, in: &context, projection, colour: .green, width: 2.5)
        }

        private func stroke(
            _ points: [TrackPoint],
            in context: inout GraphicsContext,
            _ projection: ChartProjection,
            colour: Color,
            width: Double
        ) {
            guard points.count > 1 else { return }
            var path = Path()
            path.move(to: projection.point(for: points[0].coordinate))
            for point in points.dropFirst() {
                path.addLine(to: projection.point(for: point.coordinate))
            }
            context.stroke(
                path, with: .color(colour),
                style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        }

        private func drawLine(_ context: inout GraphicsContext, _ projection: ChartProjection) {
            guard let pin = race.line?.pin, let boat = race.line?.boat else { return }
            var path = Path()
            path.move(to: projection.point(for: pin.coordinate))
            path.addLine(to: projection.point(for: boat.coordinate))
            context.stroke(
                path, with: .color(.white.opacity(0.8)),
                style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            dot(projection.point(for: pin.coordinate), 4, .cyan, &context)
            dot(projection.point(for: boat.coordinate), 4, .orange, &context)
        }

        /// Where the boat was when the gun went.
        private func drawGun(_ context: inout GraphicsContext, _ projection: ChartProjection) {
            guard let atGun = race.track.min(by: { abs($0.time) < abs($1.time) }) else { return }
            dot(projection.point(for: atGun.coordinate), 5, .yellow, &context)
        }

        private func dot(
            _ centre: CGPoint, _ radius: Double, _ colour: Color,
            _ context: inout GraphicsContext
        ) {
            let box = CGRect(
                x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: box), with: .color(colour))
            context.stroke(Path(ellipseIn: box), with: .color(.black), lineWidth: 1)
        }
    }

#endif
