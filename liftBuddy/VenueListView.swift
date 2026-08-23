import SwiftUI
import liftBuddyKit

/// The venues you have saved, and how ready each one is for the watch.
struct VenueListView: View {
    @Environment(VenueStore.self) private var store
    @Environment(VenueDownloader.self) private var downloader
    @Environment(ChartSyncSender.self) private var sync

    @State private var isPicking = false

    var body: some View {
        NavigationStack {
            List {
                if store.venues.isEmpty {
                    ContentUnavailableView {
                        Label("No venues", systemImage: "map")
                    } description: {
                        Text("Add the places you sail so their charts are on the watch before you get there.")
                    }
                }

                ForEach(store.venues) { venue in
                    VenueRow(venue: venue)
                }
                .onDelete { offsets in
                    for index in offsets { store.remove(store.venues[index]) }
                }

                if !store.venues.isEmpty {
                    Section {
                        watchStatus
                    }
                }
            }
            .navigationTitle("Venues")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { isPicking = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $isPicking) {
                VenuePickerView { venue in
                    store.add(venue)
                    sync.send(venues: store.venues)
                }
            }
        }
    }

    @ViewBuilder
    private var watchStatus: some View {
        if !sync.canSend {
            Label("Watch app not installed", systemImage: "applewatch.slash")
                .foregroundStyle(.secondary)
                .font(.footnote)
        } else if sync.outstandingTransfers > 0 {
            Label(
                "Sending \(sync.outstandingTransfers) cells to watch",
                systemImage: "arrow.up.circle"
            )
            .font(.footnote)
        } else {
            Label("Watch up to date", systemImage: "applewatch")
                .foregroundStyle(.secondary)
                .font(.footnote)
        }
    }
}

private struct VenueRow: View {
    let venue: Venue

    @Environment(VenueDownloader.self) private var downloader
    @Environment(ChartSyncSender.self) private var sync

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(venue.name).font(.headline)
                Spacer()
                Text(RaceFormat.distance(venue.radius))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if downloader.activeVenue == venue.id, let progress = downloader.progress {
                ProgressView(value: progress.fraction) {
                    Text("Downloading \(progress.completed) of \(progress.total)")
                        .font(.caption)
                }
                Button("Cancel", role: .destructive) { downloader.cancel() }
                    .font(.caption)
                    .buttonStyle(.borderless)
            } else {
                let cached = downloader.cachedCellCount(for: venue)
                Text("\(cached) of \(venue.cellCount) cells on this phone")
                    .font(.caption)
                    .foregroundStyle(cached == venue.cellCount ? .green : .secondary)

                HStack(spacing: 12) {
                    Button {
                        downloader.start(venue)
                    } label: {
                        Label(
                            cached == venue.cellCount ? "Refresh" : "Download",
                            systemImage: "arrow.down.circle"
                        )
                    }
                    .disabled(downloader.isDownloading)

                    Button {
                        sync.send(cells: venue.cells, fromDocuments: URL.documentsDirectory)
                    } label: {
                        Label("Send to Watch", systemImage: "applewatch")
                    }
                    .disabled(!sync.canSend || cached == 0)
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}
