import SwiftUI
import liftBuddyKit
import liftBuddyUI

struct RootView: View {
    @State private var session = RaceSession()
    @State private var sync = ChartSyncReceiver()
    @State private var races = RaceStore()
    @State private var page = Page.map
    @Environment(\.scenePhase) private var scenePhase

    enum Page: Hashable {
        case map, line, timer, wind
    }

    var body: some View {
        TabView(selection: $page) {
            ChartMapPage(session: session)
                .tag(Page.map)
            LinePage(session: session)
                .tag(Page.line)
            TimerPage(session: session)
                .tag(Page.timer)
            WindPage(session: session)
                .tag(Page.wind)
        }
        .tabViewStyle(.verticalPage)
        .environment(races)
        .onAppear {
            session.begin()
            sync.activate()
        }
        .onChange(of: scenePhase) { _, phase in
            // Nothing sensor-driven should keep running once the app is gone
            // from the screen; a start sequence has no use for a dead battery.
            if phase == .active { session.begin() } else if phase == .background { session.end() }
        }
    }
}

/// A small label-over-value pair, the unit of information on every page.
struct Readout: View {
    let label: String
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    RootView()
}
