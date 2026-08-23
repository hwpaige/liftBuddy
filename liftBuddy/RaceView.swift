import SwiftUI
import liftBuddyKit
import liftBuddyUI

/// Everything the watch does, on the phone.
///
/// The same `RaceSession` drives both, so the numbers cannot drift apart. The
/// layout differs because the constraints do: the watch pages one reading at a
/// time because that is all that fits, while a phone can show the chart and the
/// whole prestart at once — which is what you want when planning on the way out
/// rather than glancing down at thirty seconds.
struct RaceView: View {
    @Environment(BoatProfileStore.self) private var boats
    @Environment(RaceStore.self) private var races
    @Environment(VenueStore.self) private var venues
    @State private var session = RaceSession()
    @State private var panelHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            ChartMapPage(session: session, bottomInset: panelHeight)
                .ignoresSafeArea()

            panel
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Tell the chart how much of itself is covered, so the boat
                    // is drawn above the panel rather than behind it.
                    panelHeight = height + 60
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .onAppear {
            session.boat = boats.profile
            session.begin()
        }
        .onChange(of: boats.profile) { _, profile in session.boat = profile }
        .onDisappear { session.end() }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            timerRow
            if session.line.isSurveyed { approachRow }
            Divider()
            lineRow
            windRow
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Timer

    private var timerRow: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text(clockText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(clockTint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Button(action: session.cycleSequence) {
                    Text("\(session.timer.sequence.label) sequence")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(session.timer.isRunning)
                Text(gpsSummary)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(session.fix == nil ? .orange : .secondary)
            }
            Spacer()
            VStack(spacing: 6) {
                Button(action: primaryAction) {
                    Text(primaryLabel)
                        .font(.headline)
                        .frame(width: 96, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(primaryTint)

                // A running clock needs a visible way out. This used to be a
                // long press on the button above, which nobody can be expected
                // to discover, and which a slow tap could trigger by accident.
                if session.timer.isRunning {
                    Button(role: .destructive, action: session.resetTimer) {
                        Text("Reset").font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    private var approachRow: some View {
        HStack(spacing: 0) {
            reading(
                "Burn",
                session.burnTime.map { RaceFormat.signedSeconds($0) } ?? "—",
                tint: (session.burnTime ?? 0) >= 0 ? .green : .red
            )
            reading(
                session.approach?.isOverEarly == true ? "OVER" : "To line",
                session.approach.map { RaceFormat.distance($0.distanceToLine) } ?? "—",
                tint: session.approach?.isOverEarly == true ? .red : .primary
            )
            reading(
                "Time",
                session.approach?.timeToLine.map { RaceFormat.clock($0) } ?? "—"
            )
        }
    }

    // MARK: - Line

    private var lineRow: some View {
        HStack(spacing: 10) {
            ForEach(LineEnd.allCases, id: \.self) { end in
                pingButton(end)
            }

            VStack(alignment: .trailing, spacing: 0) {
                if let bias = session.bias, let end = bias.favoredEnd {
                    Text(end.label.uppercased())
                        .font(.subheadline.bold())
                        .foregroundStyle(end == .pin ? .cyan : .orange)
                    Text(
                        "\(RaceFormat.degrees(bias.degrees)) · \(RaceFormat.boatLengths(bias.advantageInBoatLengths(session.boat.lengthOverall)))L"
                    )
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                } else if session.bias != nil {
                    Text("SQUARE").font(.subheadline.bold()).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, alignment: .trailing)
        }
    }

    /// Pinged and not-pinged must not be a matter of shade.
    ///
    /// These were both grey capsules differing only in tint, and an end that
    /// had merely become tappable looked much like one that had been recorded.
    /// An empty end is now outlined and an recorded one is filled and ticked.
    @ViewBuilder
    private func pingButton(_ end: LineEnd) -> some View {
        let pinged = session.line[end] != nil
        let colour: Color = end == .pin ? .cyan : .orange
        let label = VStack(spacing: 1) {
            HStack(spacing: 3) {
                if pinged { Image(systemName: "checkmark.circle.fill").font(.caption2) }
                Text(end.label).font(.subheadline.bold())
            }
            Text(pinged ? "pinged" : "tap at end")
                .font(.caption2)
                .opacity(0.85)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)

        if pinged {
            Button { session.ping(end) } label: { label }
                .buttonStyle(.borderedProminent)
                .tint(colour)
                .disabled(session.fix == nil)
        } else {
            Button { session.ping(end) } label: { label }
                .buttonStyle(.bordered)
                .tint(.secondary)
                .disabled(session.fix == nil)
        }
    }

    // MARK: - Wind

    private var windRow: some View {
        HStack(spacing: 10) {
            Button {
                session.setHeadToWind()
            } label: {
                Label("Head to Wind", systemImage: "location.north.line")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.teal)
            .disabled(session.location.heading == nil)

            VStack(alignment: .trailing, spacing: 0) {
                if let wind = session.wind {
                    Text(wind.direction.description)
                        .font(.subheadline.bold())
                        .monospacedDigit()
                    Text(wind.source.label)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No wind").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, alignment: .trailing)
        }
    }

    // MARK: - Bits

    private func reading(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    /// Concrete proof that the receiver is alive, and how much to trust it.
    ///
    /// Without this, acquiring a fix changes almost nothing on screen — a small
    /// arrow appears on a dark chart — and there is no way to tell a working
    /// GPS from a stalled one.
    private var gpsSummary: String {
        guard let fix = session.fix else { return "No GPS" }
        let accuracy = fix.horizontalAccuracy > 0
            ? "±\(Int(fix.horizontalAccuracy.rounded())) m" : "accuracy unknown"
        return "GPS \(accuracy) · \(String(format: "%.1f kn", fix.speedInKnots))"
    }

    private var clockText: String {
        switch session.phase {
        case .idle: RaceFormat.clock(session.timer.sequence.duration)
        case .countdown(let remaining): RaceFormat.clock(remaining)
        case .racing(let elapsed): RaceFormat.clock(elapsed)
        }
    }

    private var clockTint: Color {
        switch session.phase {
        case .idle: .secondary
        case .countdown(let remaining): remaining <= 60 ? .orange : .primary
        case .racing: .green
        }
    }

    /// Racing finishes and saves; everything else is the session's own action.
    private func primaryAction() {
        guard case .racing = session.phase else {
            session.primaryTimerAction()
            return
        }
        if let record = session.finishRace(named: raceName) {
            races.save(record)
        }
    }

    /// Named for where it was sailed when that is known, since the date is
    /// already shown beside it in the list.
    private var raceName: String {
        session.fix.flatMap { venues.venue(containing: $0.coordinate)?.name } ?? "Race"
    }

    private var primaryLabel: String {
        switch session.phase {
        case .idle: "Start"
        case .countdown: "Sync"
        case .racing: "Finish"
        }
    }

    private var primaryTint: Color {
        switch session.phase {
        case .idle: .green
        case .countdown: .blue
        case .racing: .gray
        }
    }
}
