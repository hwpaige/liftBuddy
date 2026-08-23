import SwiftUI
import liftBuddyKit
import liftBuddyUI

@main
struct LiftBuddyApp: App {
    @State private var boats = BoatProfileStore()
    @State private var venues = VenueStore()
    @State private var downloader = VenueDownloader()
    @State private var sync = ChartSyncSender()
    @State private var races = RaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(boats)
                .environment(venues)
                .environment(downloader)
                .environment(sync)
                .environment(races)
                .task {
                    sync.activate()
                    sync.send(venues: venues.venues)
                }
        }
    }
}
