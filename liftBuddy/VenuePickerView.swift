import CoreLocation
import MapKit
import SwiftUI
import liftBuddyKit

/// Pick a sailing venue by dragging the map under a fixed circle.
///
/// The circle stays put and the world moves beneath it, which is the one
/// interaction that cannot fight with panning — dragging a rectangle onto a map
/// that also pans means every gesture is ambiguous.
struct VenuePickerView: View {
    let onSave: (Venue) -> Void

    @Environment(\.dismiss) private var dismiss
    /// An explicit region, never `.automatic`.
    ///
    /// `.automatic` frames the camera to fit the map's content. The content
    /// here is a circle drawn at the centre the camera reports, so the two
    /// chase each other: the camera moves, the circle moves, the camera
    /// reframes. The loop never settles and the whole screen renders blank.
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 41.49882, longitude: -71.33318),
            latitudinalMeters: 20_000,
            longitudinalMeters: 20_000
        )
    )
    @State private var centre = Coordinate(latitude: 41.49882, longitude: -71.33318)
    @State private var radius: Double = 5000
    @State private var name = ""
    @State private var locationManager = CLLocationManager()

    private var draft: Venue {
        Venue(name: displayName, center: centre, radius: radius)
    }

    private var displayName: String {
        name.trimmingCharacters(in: .whitespaces).isEmpty ? "Untitled venue" : name
    }

    var body: some View {
        NavigationStack {
            // A VStack rather than safeAreaInset: the map has no intrinsic size,
            // and inside an inset it can end up laid out at zero height, which
            // collapses the whole screen to blank white.
            VStack(spacing: 0) {
                ZStack {
                    Map(position: $camera) {
                        MapCircle(center: centre.clCoordinate, radius: radius)
                            .foregroundStyle(.blue.opacity(0.18))
                            .stroke(.blue, lineWidth: 2)
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                    .onMapCameraChange(frequency: .continuous) { context in
                        centre = Coordinate(context.region.center)
                    }
                    crosshair
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                controls
            }
            .navigationTitle("New Venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                if locationManager.authorizationStatus == .notDetermined {
                    locationManager.requestWhenInUseAuthorization()
                }
            }
        }
    }

    private var crosshair: some View {
        Image(systemName: "plus")
            .font(.system(size: 22, weight: .light))
            .foregroundStyle(.blue)
            .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack(spacing: 10) {
            TextField("Venue name", text: $name)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)

            VStack(spacing: 2) {
                HStack {
                    Text("Radius")
                    Spacer()
                    Text(RaceFormat.distance(radius)).monospacedDigit()
                }
                .font(.subheadline)
                Slider(
                    value: $radius,
                    in: Venue.radiusRange,
                    step: 500
                )
            }

            HStack {
                Label(
                    "\(draft.cellCount) chart cells",
                    systemImage: "square.grid.3x3"
                )
                Spacer()
                Text(estimate)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
    }

    private var estimate: String {
        let megabytes = Double(draft.approximateBytes) / 1_048_576
        return megabytes < 1
            ? String(format: "~%.0f KB", Double(draft.approximateBytes) / 1024)
            : String(format: "~%.0f MB", megabytes)
    }
}
