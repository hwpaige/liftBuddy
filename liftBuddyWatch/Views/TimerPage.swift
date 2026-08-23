import SwiftUI
import liftBuddyKit
import liftBuddyUI

/// The page you are actually looking at in the last thirty seconds: one enormous
/// number, and one button that does the only thing worth doing right now.
struct TimerPage: View {
    let session: RaceSession

    @Environment(RaceStore.self) private var races

    var body: some View {
        VStack(spacing: 2) {
            header
            Text(clockText)
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(clockTint)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            slack
            Spacer(minLength: 2)
            primaryButton
        }
        .padding(.horizontal, 2)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if session.approach?.isOverEarly == true, case .countdown = session.phase {
            Text("OVER THE LINE")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.red)
        } else if case .idle = session.phase {
            Button(action: session.cycleSequence) {
                Text("\(session.timer.sequence.label) sequence")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } else {
            Text(session.timer.sequence.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Slack

    /// Burn time is the whole game: seconds you can afford to waste and still
    /// hit the line at full speed on the gun.
    @ViewBuilder
    private var slack: some View {
        if let approach = session.approach, case .countdown = session.phase {
            HStack(spacing: 8) {
                if let burn = session.burnTime {
                    Text(RaceFormat.signedSeconds(burn))
                        .foregroundStyle(burn >= 0 ? .green : .red)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
                Text(RaceFormat.distance(approach.distanceToLine))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        } else if !session.line.isSurveyed {
            Text("Ping the line for burn time")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var primaryButton: some View {
        Button(action: primaryAction) {
            Text(primaryLabel)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .tint(primaryTint)

        // A running clock needs a visible way out. This was a long press on the
        // button above, which nobody can be expected to find.
        if session.timer.isRunning {
            Button(action: session.resetTimer) {
                Text("Reset")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Presentation

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

    /// Racing finishes and saves the race; everything else is the session's
    /// own action.
    private func primaryAction() {
        guard case .racing = session.phase else {
            session.primaryTimerAction()
            return
        }
        if let record = session.finishRace(named: "Race") {
            races.save(record)
        }
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
