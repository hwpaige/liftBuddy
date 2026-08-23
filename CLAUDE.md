# liftBuddy

A sailing app for Apple Watch, with an iPhone companion. It helps you do your
prestart homework — survey the start line, measure the wind, run the sequence —
and shows where you are on the course against a real nautical chart.

Start here, then read `docs/DECISIONS.md` before changing anything about charts
or networking. Several obvious-looking approaches have already been tried and
measured, and the reasons they were rejected are not guessable from the code.

## Layout

```
liftBuddy/                  iOS app  (companion: setup, venues, race history, full race UI)
liftBuddyWatch/             watchOS app (the primary device, worn while racing)
liftBuddyKit/               Swift package, two libraries:
  Sources/liftBuddyKit/     pure logic — no UI, no CoreLocation in the core.
                            Geo, racing math, chart model, race analysis.
  Sources/liftBuddyUI/      shared engine + chart renderer used by BOTH apps
                            (RaceSession, LocationEngine, ChartStreamer,
                            ChartMapPage). Scoped to iOS/watchOS.
docs/                       architecture, decisions, testing notes
```

The chart baking pipeline and API live in a **separate repo**:
`~/PycharmProjects/liftbuddy-charts`.

## Build and test

```bash
# fast: pure logic, no simulator needed. Run this first, always.
swift test --package-path liftBuddyKit

xcodebuild -project liftBuddy.xcodeproj -scheme liftBuddy \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project liftBuddy.xcodeproj -scheme liftBuddyWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Ultra 3 (49mm)' build
```

`liftBuddyKit` builds for macOS too, purely so those tests run without a
simulator. `liftBuddyUI` is compiled out on macOS with `#if os(iOS) || os(watchOS)`.

## The shape of it

- **`RaceSession`** is the single source of truth while racing. Both apps drive
  the same one, so their numbers cannot disagree. Derived values (line bias,
  approach, burn time) are computed properties, never stored.
- **`ChartStreamer`** holds chart cells: disk first, network second, everything
  cached permanently. It knows nothing about venues — charts download from
  wherever you are.
- **Chart rendering is ours, not MapKit's.** See `docs/DECISIONS.md`; this is
  not a preference, MapKit cannot do it on watchOS.

## Conventions

- Deployment targets iOS 18 / watchOS 11. Swift 5 language mode,
  `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on the app targets — **but not in
  the package**, so package types annotate `@MainActor` explicitly.
- `PRODUCT_BUNDLE_IDENTIFIER` is `com.harrison.liftBuddy` — a placeholder.
  Change it to a real team prefix before device signing.
- Comments explain *why*, especially where something looks wrong but is
  deliberate (held map heading at low speed, bow offset ignored when stopped).

## Known gaps

- **WatchConnectivity is unverified.** The phone queues chart transfers
  correctly and the watch session activates, but no file has ever been observed
  arriving — file transfer does not work between paired simulators. Needs real
  hardware.
- **No background operation.** The watch stops sensing when the app leaves the
  screen. Fixing it means an `HKWorkoutSession`; the HealthKit usage strings are
  already in place.
- **Races are recorded on both devices but never sync.**
