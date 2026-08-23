// This module is the racing engine and chart renderer shared by the watch
// and phone apps. It is scoped to those two platforms: it speaks CoreLocation
// authorization and haptics, neither of which has a meaningful macOS form, and
// the package still needs to build for macOS so the pure-logic tests can run.
#if os(iOS) || os(watchOS)

import CoreLocation
import Foundation
import liftBuddyKit

/// Owns CoreLocation and republishes it as the model types the racing math wants.
///
/// GPS and compass are both needed and are *not* interchangeable: course over
/// ground is what you are actually doing through the water, while compass
/// heading is the only thing that still works when you are stopped — which is
/// exactly the situation when you luff head to wind to take a wind reading.
@MainActor
@Observable
public final class LocationEngine: NSObject {
    public private(set) var fix: BoatFix?
    /// Compass heading, true north when available.
    public private(set) var heading: Bearing?
    public private(set) var authorization: CLAuthorizationStatus = .notDetermined
    public private(set) var isRunning = false
    /// True when CoreLocation has reported a failure and has never yet given a
    /// fix. Distinguishes "still acquiring" from "there is no signal here",
    /// which otherwise look identical and wait forever.
    public private(set) var hasFailedWithoutFix = false

    @ObservationIgnored private let manager = CLLocationManager()
    /// Whether the app has asked for updates, independent of whether it is yet
    /// allowed to have them.
    @ObservationIgnored private var wantsUpdates = false

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = kCLDistanceFilterNone
        authorization = manager.authorizationStatus
    }

    public var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    /// True once the fix is good enough to trust a line ping to.
    public var hasRacingQualityFix: Bool {
        guard let fix else { return false }
        return fix.horizontalAccuracy > 0 && fix.horizontalAccuracy <= 10
    }

    /// Asks for updates, starting them as soon as that is allowed.
    ///
    /// Starting updates before authorization is granted does nothing, and
    /// CoreLocation does not go back and honour the request once the user says
    /// yes — so the intent is remembered here and acted on when the answer
    /// arrives. Getting this wrong leaves the app waiting for a fix forever
    /// after a perfectly normal first launch, until it is relaunched.
    public func start() {
        wantsUpdates = true
        guard authorization != .notDetermined else {
            manager.requestWhenInUseAuthorization()
            return
        }
        beginUpdates()
    }

    private func beginUpdates() {
        guard wantsUpdates, isAuthorized, !isRunning else { return }
        isRunning = true
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() {
            manager.startUpdatingHeading()
        }
    }

    public func stop() {
        wantsUpdates = false
        guard isRunning else { return }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
    }

    private func ingest(_ fix: BoatFix) {
        self.fix = fix
        hasFailedWithoutFix = false
    }

    private func noteFailure() {
        // A failure after a good fix is a boat passing under a bridge, not a
        // problem to report; only a failure with nothing to show is worth
        // surfacing.
        if fix == nil { hasFailedWithoutFix = true }
    }

    private func ingest(heading: Bearing?) {
        self.heading = heading
    }

    private func ingest(authorization: CLAuthorizationStatus) {
        self.authorization = authorization
        if isAuthorized {
            // The answer to the prompt is the cue to actually start.
            beginUpdates()
        } else if isRunning {
            // Permission withdrawn mid-session.
            isRunning = false
            manager.stopUpdatingLocation()
            manager.stopUpdatingHeading()
        }
    }
}

extension LocationEngine: CLLocationManagerDelegate {
    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let latest = locations.last else { return }
        let fix = BoatFix(latest)
        Task { @MainActor [weak self] in self?.ingest(fix) }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateHeading newHeading: CLHeading
    ) {
        // Negative accuracy means the compass is uncalibrated and lying.
        guard newHeading.headingAccuracy >= 0 else {
            Task { @MainActor [weak self] in self?.ingest(heading: nil) }
            return
        }
        let degrees = newHeading.trueHeading >= 0
            ? newHeading.trueHeading
            : newHeading.magneticHeading
        let bearing = degrees >= 0 ? Bearing(degrees: degrees) : nil
        Task { @MainActor [weak self] in self?.ingest(heading: bearing) }
    }

    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in self?.ingest(authorization: status) }
    }

    public nonisolated func locationManager(
        _ manager: CLLocationManager, didFailWithError error: Error
    ) {
        // The last fix stays on screen rather than blanking mid-approach; this
        // only records that something is wrong so the UI can say so when there
        // is nothing to show at all.
        Task { @MainActor [weak self] in self?.noteFailure() }
    }
}

#endif
