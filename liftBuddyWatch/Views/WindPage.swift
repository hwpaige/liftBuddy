import SwiftUI
import liftBuddyKit
import liftBuddyUI

/// Where the wind direction comes from, and how it gets corrected.
struct WindPage: View {
    let session: RaceSession
    @State private var crownDegrees: Double = 0
    @FocusState private var crownFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                if let wind = session.wind {
                    reading(wind)
                } else {
                    unset
                }
                controls
            }
            .padding(.horizontal, 2)
        }
        .focusable(session.wind != nil)
        .focused($crownFocused)
        .digitalCrownRotation(
            $crownDegrees,
            from: 0,
            through: 360,
            by: 1,
            sensitivity: .medium,
            isContinuous: true,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownDegrees) { _, new in
            // Only a real turn of the crown counts. Without the threshold,
            // mirroring the crown to a freshly measured wind would immediately
            // rewrite it as a manual entry and throw away its provenance.
            guard let wind = session.wind else { return }
            guard wind.direction.separation(to: Bearing(degrees: new)) > 0.4 else { return }
            session.setWind(degrees: new)
        }
        .onChange(of: session.wind?.direction.degrees) { _, degrees in
            if let degrees { crownDegrees = degrees }
        }
        .onAppear {
            if let degrees = session.wind?.direction.degrees { crownDegrees = degrees }
            crownFocused = session.wind != nil
        }
    }

    // MARK: - Reading

    private func reading(_ wind: Wind) -> some View {
        VStack(spacing: 0) {
            Text(wind.direction.description)
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(wind.direction.cardinal)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("\(wind.source.label) · \(age(of: wind))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Turn the crown to adjust")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
    }

    private var unset: some View {
        VStack(spacing: 2) {
            Text("No wind set")
                .font(.system(size: 16, weight: .semibold))
            Text("Luff head to wind and tap below")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        Button {
            session.setHeadToWind()
        } label: {
            Text("Head to Wind")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
        }
        .tint(.teal)
        .disabled(session.location.heading == nil)

        if session.location.heading == nil {
            Text("Compass unavailable")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }

        if session.wind == nil {
            Button {
                // Seed from wherever the boat is pointing, then refine by crown.
                session.setWind(degrees: session.location.heading?.degrees ?? 0)
                crownFocused = true
            } label: {
                Text("Set by hand").font(.system(size: 13))
            }
            .tint(.gray)
        }
    }

    private func age(of wind: Wind) -> String {
        let seconds = max(0, session.now.timeIntervalSince(wind.updatedAt))
        if seconds < 60 { return "just now" }
        return "\(Int(seconds / 60)) min ago"
    }
}
