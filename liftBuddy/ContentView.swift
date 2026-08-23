import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Race", systemImage: "sailboat.circle") {
                RaceView()
            }
            Tab("Venues", systemImage: "map") {
                VenueListView()
            }
            Tab("Races", systemImage: "flag.checkered") {
                RaceHistoryView()
            }
            Tab("Boat", systemImage: "sailboat") {
                BoatSettingsView()
            }
        }
    }
}
