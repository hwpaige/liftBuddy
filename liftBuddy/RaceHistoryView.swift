import SwiftUI
import liftBuddyKit
import liftBuddyUI

/// Saved races. The phone is where these get read: a track is unreadable on a
/// wrist, and this is the one part of the app nobody looks at while sailing.
struct RaceHistoryView: View {
    @Environment(RaceStore.self) private var races

    var body: some View {
        NavigationStack {
            List {
                if races.isEmpty {
                    ContentUnavailableView {
                        Label("No races yet", systemImage: "flag.checkered")
                    } description: {
                        Text("Start a sequence on the phone or the watch and the race is recorded from the moment the clock starts.")
                    }
                }
                ForEach(races.races) { race in
                    NavigationLink {
                        RaceDetailView(race: race)
                    } label: {
                        RaceRow(race: race)
                    }
                }
                .onDelete { offsets in
                    for index in offsets { races.delete(races.races[index]) }
                }
            }
            .navigationTitle("Races")
        }
    }
}

private struct RaceRow: View {
    let race: RaceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(race.name).font(.headline)
                Spacer()
                Text(race.startedAt, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label(RaceFormat.clock(race.duration), systemImage: "clock")
                if let start = race.startAnalysis {
                    Label(
                        start.wasOver
                            ? "OVER" : RaceFormat.distance(abs(start.distanceToLine)),
                        systemImage: "flag"
                    )
                    .foregroundStyle(start.wasOver ? .red : .secondary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// One race: the shape of it, then how the start went, then the totals.
struct RaceDetailView: View {
    let race: RaceRecord

    var body: some View {
        List {
            Section {
                RaceTrackView(race: race)
                    .frame(height: 260)
                    .background(Palette.deepWater, in: RoundedRectangle(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
            } footer: {
                Text("Faint blue is the prestart, green is racing, yellow marks where you were at the gun.")
            }

            if let start = race.startAnalysis {
                Section("Start") {
                    row(
                        "Distance to line",
                        start.wasOver
                            ? "over by \(RaceFormat.distance(abs(start.distanceToLine)))"
                            : RaceFormat.distance(start.distanceToLine),
                        tint: start.wasOver ? .red : .primary
                    )
                    row("Speed at gun", String(format: "%.1f kn", start.speedInKnots))
                    row("End", start.endStartedAt.label)
                    if let favoured = start.favoredEnd {
                        row(
                            "Favoured end",
                            favoured.label,
                            tint: start.startedAtFavoredEnd == true ? .green : .orange
                        )
                    }
                    if let cross = start.timeToCross {
                        row("Crossed the line", "\(Int(cross))s after the gun")
                    }
                }
            }

            Section("Race") {
                let stats = race.statistics
                row("Duration", RaceFormat.clock(stats.duration))
                row("Distance", RaceFormat.distance(stats.distanceSailed))
                row("Top speed", String(format: "%.1f kn", stats.maximumSpeedInKnots))
                row("Average", String(format: "%.1f kn", stats.averageSpeedInKnots))
                if race.wind != nil {
                    row("Tacks", "\(stats.tacks)")
                    row("Gybes", "\(stats.gybes)")
                }
            }

            Section("Setup") {
                row("Boat", race.boat.name)
                if let wind = race.wind {
                    row("Wind", "\(wind.direction.description) · \(wind.source.label)")
                }
                if let length = race.line?.length {
                    row("Line", RaceFormat.distance(length))
                }
                row("Track points", "\(race.track.count)")
            }
        }
        .navigationTitle(race.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        LabeledContent(label) {
            Text(value).foregroundStyle(tint).monospacedDigit()
        }
    }
}
