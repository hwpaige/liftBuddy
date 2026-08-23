// This module is the racing engine and chart renderer shared by the watch
// and phone apps. It is scoped to those two platforms: it speaks CoreLocation
// authorization and haptics, neither of which has a meaningful macOS form, and
// the package still needs to build for macOS so the pure-logic tests can run.
#if os(iOS) || os(watchOS)

import SwiftUI
import liftBuddyKit

/// The course drawn on a NOAA ENC vector chart.
///
/// Vector rather than raster, which is what makes this work at racing scale: a
/// raster chart runs out of detail around 1.8 m/px and a start line is smaller
/// than that, so it would be enlarged into mush exactly when you need it.
/// Geometry has no such floor, arrives about ninety times smaller, and carries
/// the S-57 attributes — so a buoy knows it is green and knows its name.
public struct ChartMapPage: View {
    let session: RaceSession
    /// Height of any chrome overlapping the bottom of the chart.
    ///
    /// The boat is placed relative to the part of the chart you can actually
    /// see. On a watch that is the whole screen; on a phone a control panel
    /// covers the lower third, and without this the boat sits underneath it.
    let bottomInset: CGFloat

    public init(session: RaceSession, bottomInset: CGFloat = 0) {
        self.session = session
        self.bottomInset = bottomInset
    }

    /// The part of the view not hidden by chrome.
    private func visibleHeight(_ size: CGSize) -> CGFloat {
        max(size.height - bottomInset, 1)
    }

    @State private var charts = ChartStreamer()
    /// Held across fixes so the chart does not spin when the boat is stopped
    /// and course over ground is noise.
    @State private var mapHeading: Double = 0

    private static let lookAheadFraction = 0.18

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Palette.deepWater.ignoresSafeArea()

                if let projection = projection(for: geometry.size), let fix = session.fix {
                    Canvas { context, _ in
                        draw(in: &context, projection: projection)
                    }
                    .rotationEffect(.degrees(-mapHeading))

                    boatGlyph(fix, size: geometry.size)
                } else {
                    waiting(in: geometry.size)
                }

                chrome
            }
            .onChange(of: session.fix, initial: true) { _, _ in
                if let fix = session.fix, fix.hasUsableCourse, let course = fix.course {
                    mapHeading = course.degrees
                }
                // Ask for a little beyond the screen so the chart is already
                // there by the time the boat sails onto it.
                if let projection = projection(for: geometry.size) {
                    charts.update(visibleBounds: projection.visibleBounds(marginMeters: 400))
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, projection: ChartProjection) {
        // A margin so features do not pop in at the edge as the boat moves.
        let visible = projection.visibleBounds(marginMeters: 150)

        for item in charts.depthAreas where item.bounds.intersects(visible) {
            var path = Path()
            for ring in item.feature.rings {
                append(ring, to: &path, projection: projection, closed: true)
            }
            // Even-odd so inner rings punch holes rather than painting over them.
            context.fill(
                path,
                with: .color(Palette.water(shallowness: item.feature.shallowness)),
                style: FillStyle(eoFill: true)
            )
        }

        for item in charts.depthContours where item.bounds.intersects(visible) {
            var path = Path()
            append(item.feature.path, to: &path, projection: projection, closed: false)
            context.stroke(path, with: .color(Palette.contour), lineWidth: 0.75)
        }

        for item in charts.land where item.bounds.intersects(visible) {
            var path = Path()
            for ring in item.feature.rings {
                append(ring, to: &path, projection: projection, closed: true)
            }
            context.fill(path, with: .color(Palette.land), style: FillStyle(eoFill: true))
            context.stroke(path, with: .color(Palette.landEdge), lineWidth: 0.75)
        }

        for mark in charts.marks where visible.contains(mark.coordinate) {
            dot(
                at: projection.point(for: mark.coordinate),
                radius: 3,
                fill: Palette.mark(colour: mark.colour),
                in: &context
            )
        }

        drawCourse(in: &context, projection: projection)
    }

    private func drawCourse(in context: inout GraphicsContext, projection: ChartProjection) {
        if let pin = session.line.pin, let boat = session.line.boat {
            var line = Path()
            line.move(to: projection.point(for: pin.coordinate))
            line.addLine(to: projection.point(for: boat.coordinate))
            context.stroke(
                line,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 4])
            )
        }
        if let pin = session.line.pin {
            dot(at: projection.point(for: pin.coordinate), radius: 5.5, fill: .cyan, in: &context)
        }
        if let boat = session.line.boat {
            dot(at: projection.point(for: boat.coordinate), radius: 5.5, fill: .orange, in: &context)
        }
    }

    private func dot(
        at centre: CGPoint,
        radius: Double,
        fill: Color,
        in context: inout GraphicsContext
    ) {
        let box = CGRect(
            x: centre.x - radius,
            y: centre.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.fill(Path(ellipseIn: box), with: .color(fill))
        context.stroke(Path(ellipseIn: box), with: .color(.black), lineWidth: 1)
    }

    private func append(
        _ chartPath: ChartPath,
        to path: inout Path,
        projection: ChartProjection,
        closed: Bool
    ) {
        guard chartPath.count > 1 else { return }
        path.move(to: projection.point(for: chartPath[0]))
        for index in 1..<chartPath.count {
            path.addLine(to: projection.point(for: chartPath[index]))
        }
        if closed { path.closeSubpath() }
    }

    // MARK: - Projection

    private func projection(for size: CGSize) -> ChartProjection? {
        guard let fix = session.fix, size.width > 0, size.height > 0 else { return nil }
        let metersPerPixel = metersPerPixel(for: size)
        // Shift the centre by half the hidden strip as well, so the boat ends
        // up in the middle of what is visible rather than the middle of the view.
        let visible = visibleHeight(size)
        let centre = fix.coordinate.offset(
            bearing: Bearing(degrees: mapHeading),
            distance: metersPerPixel * (visible * Self.lookAheadFraction + bottomInset / 2)
        )
        return ChartProjection(
            center: centre,
            metersPerPixel: metersPerPixel,
            size: size,
            source: .noaaENC
        )
    }

    private func metersPerPixel(for size: CGSize) -> Double {
        let size = CGSize(width: size.width, height: visibleHeight(size))
        let span = max(
            session.line.length ?? 0,
            (session.approach?.distanceToLine ?? 0) * 2,
            400
        )
        let across = max(min(size.width, size.height), 1)
        return span * 1.5 / across
    }

    // MARK: - Chrome

    private func waiting(in size: CGSize) -> some View {
        VStack(spacing: 6) {
            if !noSignal { ProgressView().tint(.white) }
            // Explicit light tints, not `.secondary`/`.tertiary`: those are
            // pitched for a system background, and this always sits on the
            // near-black chart, where they are all but invisible.
            Text(waitingMessage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
            if let hint = waitingHint {
                Text(hint)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        // Centred in the part of the chart that is not covered by chrome.
        .padding(.bottom, bottomInset)
        .frame(width: size.width, height: size.height)
    }

    private var noSignal: Bool {
        session.location.isAuthorized && session.location.hasFailedWithoutFix
    }

    private var waitingMessage: String {
        if !session.location.isAuthorized { return "Location access needed" }
        return noSignal ? "No GPS signal" : "Waiting for GPS"
    }

    /// Says what to do about it, when there is something to do.
    private var waitingHint: String? {
        if !session.location.isAuthorized {
            return "Allow location access to see your position on the chart."
        }
        guard noSignal else { return nil }
        #if targetEnvironment(simulator)
            // The simulator has no location until one is chosen, which looks
            // exactly like a boat with no sky.
            return "Simulator has no location set. Choose one in Features › Location."
        #else
            return "Waiting for a clear view of the sky."
        #endif
    }

    private func boatGlyph(_ fix: BoatFix, size: CGSize) -> some View {
        Image(systemName: "location.north.fill")
            .font(.system(size: 17))
            .foregroundStyle(.green)
            .rotationEffect(.degrees((fix.course?.degrees ?? mapHeading) - mapHeading))
            .shadow(color: .black, radius: 2)
            .position(
                x: size.width / 2,
                y: visibleHeight(size) / 2 + visibleHeight(size) * Self.lookAheadFraction
            )
    }

    /// Only says anything when there is nothing on screen to speak for itself.
    private var status: String? {
        if charts.hasChart { return nil }
        if charts.isFetching { return "Loading chart…" }
        if let failure = charts.lastError { return failure }
        // An empty chart with no error means nothing has been fetched for here
        // yet, which is a different problem from a failed fetch and has a
        // different answer.
        return "No chart for this area yet"
    }

    @ViewBuilder
    private var chrome: some View {
        VStack(spacing: 0) {
            if let status {
                Text(status)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.bottom, 2)
            }
            if let approach = session.approach, session.line.isSurveyed {
                HStack(spacing: 5) {
                    Text(
                        approach.isOverEarly
                            ? "OVER" : RaceFormat.distance(approach.distanceToLine)
                    )
                    .foregroundStyle(approach.isOverEarly ? .red : .primary)
                    if let time = approach.timeToLine {
                        Text("·").foregroundStyle(.secondary)
                        Text(RaceFormat.clock(time)).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(.black.opacity(0.6), in: Capsule())
                .padding(.bottom, 6)
            }
        }
        // Fill the space and hang off the bottom. A bare `Spacer()` inside a
        // centre-aligned ZStack has nothing to expand into, so the whole thing
        // collapses and lands mid-screen instead.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Sit above any panel or tab bar covering the bottom of the chart,
        // rather than underneath it where nothing can be read.
        .padding(.bottom, bottomInset)
    }
}

/// Night-mode chart colours.
///
/// Inverted from a paper chart on purpose: on a dim wrist display the useful
/// signal is "shallow", so shallow water gets brighter and more saturated as it
/// gets shoaler, while safe water recedes to almost black.
public enum Palette {
    public static let deepWater = Color(red: 0.05, green: 0.08, blue: 0.14)
    public static let contour = Color(red: 0.35, green: 0.52, blue: 0.68).opacity(0.55)
    public static let land = Color(red: 0.20, green: 0.18, blue: 0.13)
    public static let landEdge = Color(red: 0.45, green: 0.40, blue: 0.28)

    public static func water(shallowness: Double) -> Color {
        let s = min(max(shallowness, 0), 1)
        return Color(
            red: 0.06 + 0.10 * s,
            green: 0.11 + 0.27 * s,
            blue: 0.19 + 0.38 * s
        )
    }

    /// S-57 `COLOUR` codes. A comma-separated list means a banded mark; the
    /// first colour is enough to tell it apart at this size.
    public static func mark(colour: String?) -> Color {
        switch colour?.split(separator: ",").first.map(String.init) {
        case "1": .white
        case "2": Color(white: 0.25)
        case "3": .red
        case "4": .green
        case "6": .yellow
        case "11": .orange
        default: Color(white: 0.75)
        }
    }
}

#endif
