import SwiftUI
import liftBuddyKit
import liftBuddyUI

/// Survey the line, then read what it is worth.
struct LinePage: View {
    let session: RaceSession

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                biasHeadline
                if session.line.isSurveyed {
                    distances
                }
                pingButtons
                if session.line.isSurveyed {
                    lineFooter
                }
            }
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Bias

    @ViewBuilder
    private var biasHeadline: some View {
        if !session.line.isSurveyed {
            VStack(spacing: 2) {
                Text("Start Line")
                    .font(.system(size: 15, weight: .semibold))
                Text("Sail to each end and ping it")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if session.wind == nil {
            VStack(spacing: 2) {
                Text("Set the wind")
                    .font(.system(size: 15, weight: .semibold))
                Text("Bias needs a wind direction")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if let bias = session.bias {
            VStack(spacing: 0) {
                if let end = bias.favoredEnd {
                    Text(end.label.uppercased())
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(end == .pin ? .cyan : .orange)
                    Text("\(RaceFormat.degrees(bias.degrees)) · \(RaceFormat.boatLengths(bias.advantageInBoatLengths(session.boat.lengthOverall))) lengths")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("SQUARE")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                    // Saying "square" when the pings simply cannot resolve the
                    // angle would be a lie of precision, so say which it is.
                    Text(
                        bias.uncertainty >= abs(bias.degrees)
                            ? "within ±\(RaceFormat.degrees(bias.uncertainty)) of measurable"
                            : "no end favored"
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Distances

    @ViewBuilder
    private var distances: some View {
        if let approach = session.approach {
            HStack(spacing: 4) {
                Readout(
                    label: approach.isOverEarly ? "OVER" : "To line",
                    value: RaceFormat.distance(approach.distanceToLine),
                    tint: approach.isOverEarly ? .red : .primary
                )
                Readout(
                    label: "Time",
                    value: approach.timeToLine.map { RaceFormat.clock($0) } ?? "—"
                )
            }
            HStack(spacing: 4) {
                Readout(label: "Pin", value: RaceFormat.distance(approach.distanceToPin))
                Readout(label: "Boat", value: RaceFormat.distance(approach.distanceToBoat))
            }
        } else {
            Text("Waiting for GPS")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pings

    private var pingButtons: some View {
        HStack(spacing: 6) {
            pingButton(.pin)
            pingButton(.boat)
        }
    }

    private func pingButton(_ end: LineEnd) -> some View {
        Button {
            session.ping(end)
        } label: {
            VStack(spacing: 0) {
                Text(end.label)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(session.line[end] == nil ? "tap at end" : "pinged")
                    .font(.system(size: 9))
                    .opacity(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .tint(session.line[end] == nil ? .gray : (end == .pin ? .cyan : .orange))
        .disabled(session.fix == nil)
    }

    // MARK: - Footer

    @ViewBuilder
    private var lineFooter: some View {
        if session.endsLookReversed {
            // Pinging the ends backwards silently inverts every bias call, so
            // offer the one-tap fix rather than just flagging it.
            Button {
                session.swapEnds()
            } label: {
                Label("Ends look swapped", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .semibold))
            }
            .tint(.yellow)
        }

        if let length = session.line.length {
            Text("Line \(RaceFormat.distance(length))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }

        Button(role: .destructive, action: session.clearLine) {
            Text("Clear line").font(.system(size: 12))
        }
    }
}
