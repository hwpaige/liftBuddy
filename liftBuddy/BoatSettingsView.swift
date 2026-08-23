import SwiftUI
import liftBuddyKit

/// Boat setup: the numbers that are miserable to type on a wrist.
struct BoatSettingsView: View {
    @Environment(BoatProfileStore.self) private var boats

    var body: some View {
        @Bindable var boats = boats

        NavigationStack {
            Form {
                Section {
                    Picker("Class", selection: presetSelection) {
                        ForEach(BoatProfile.presets) { preset in
                            Text(preset.name).tag(preset.name)
                        }
                        Text("Custom").tag("")
                    }

                    LabeledContent("Length") {
                        Text(String(format: "%.2f m", boats.profile.lengthOverall))
                            .monospacedDigit()
                    }
                    Slider(value: $boats.profile.lengthOverall, in: 2...20, step: 0.01)

                    LabeledContent("Wrist to bow") {
                        Text(String(format: "%.1f m", boats.profile.bowOffset))
                            .monospacedDigit()
                    }
                    Slider(value: $boats.profile.bowOffset, in: 0...10, step: 0.1)
                } header: {
                    Text("Boat")
                } footer: {
                    Text(
                        "Line bias is reported in boat lengths. The bow offset moves every GPS fix forward from your wrist to the part of the boat that actually crosses the line."
                    )
                }
            }
            .navigationTitle("Boat")
        }
    }

    /// Selecting a preset replaces the measurements; editing the sliders
    /// afterwards leaves the picker on "Custom" rather than silently claiming
    /// the boat is still a stock one-design.
    private var presetSelection: Binding<String> {
        Binding(
            get: {
                BoatProfile.presets.first {
                    $0.name == boats.profile.name
                        && $0.lengthOverall == boats.profile.lengthOverall
                }?.name ?? ""
            },
            set: { name in
                guard let preset = BoatProfile.presets.first(where: { $0.name == name }) else {
                    boats.profile.name = "Custom"
                    return
                }
                boats.profile.name = preset.name
                boats.profile.lengthOverall = preset.lengthOverall
                boats.profile.bowOffset = preset.bowOffset
            }
        )
    }
}

#Preview {
    BoatSettingsView()
        .environment(BoatProfileStore(defaults: UserDefaults(suiteName: "preview")!))
}
