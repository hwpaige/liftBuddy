# Decisions, and the measurements behind them

Read this before changing anything about charts or networking. Every entry here
is something that was tried and measured, not reasoned about. Several look
obviously wrong until you know why.

## Charts are drawn by us, not MapKit

Not a preference — MapKit **cannot** do it on watchOS:

- `MKTileOverlay` is `API_UNAVAILABLE(watchos)`.
- SwiftUI's `Map` has no tile-overlay type at all (zero matches in the whole
  `_MapKit_SwiftUI` interface).
- MapKit exposes no tile cache, so offline was never reachable through it either.

Drawing it ourselves also made the sailing-specific overlays possible: laylines,
wind ladders, tracks and the course are just drawing once the projection is ours.
`ChartProjection` gives `Coordinate → CGPoint`.

## Vector ENC, not raster tiles

Measured on the same Newport area:

| | size | zoom floor |
|---|---|---|
| raster tiles z12–16 | ~14 MB | ~1.8 m/px |
| baked ENC vector | **151 KB gzipped** | none |

About 90× smaller, and it stays sharp at start-line scale where a raster chart
has run out of detail. A start line is ~100 m; raster tops out well above that.

## NOAA endpoints: what is actually usable

| endpoint | state |
|---|---|
| `tileservice.charts.noaa.gov` (RNC Tile Service) | **decommissioned** by NOAA |
| `gis.charttools.noaa.gov/.../NOAACharts` WMTS | cache **empty** above z6; 404 at z8–16 |
| NCDS Maritime Chart Service `export` | timed out at 30 s |
| NCDS MBTiles (`distribution.charts.noaa.gov`) | reliable, but 140–600 MB/region and stale (May 2024) |
| `encdirect.noaa.gov` (ENC Direct to GIS) | works; **drops ~35% of requests** |
| `charts.noaa.gov/ENCs/*.zip` (S-57) | authoritative, weekly, 790 MB全 / 5–212 MB per state |

Three of these died or were found empty *during* this project. That is the case
for the app talking to our own API rather than to NOAA directly.

## ENC Direct is not a runtime dependency

Roughly a third of requests are silently dropped — never answered. Measured
consistently across curl, Python/urllib and URLSession, independent of HTTP/1.1
vs HTTP/2, gzip vs Brotli vs identity, concurrency, and rest periods. It answers
in ~0.26 s or not at all.

It is fine for an **offline bake**, which can simply ask again. It is not
something to point a shipping app at, both for reliability and because it is a
government GIS service, not a tile backend.

### What that forced in the client

- **Hedged requests.** A duplicate is launched after 1.2 s rather than waiting
  out a deadline; first answer wins. This took a two-cell venue download from
  ~180 s to 11.8 s.
- **Adaptive deadlines.** Start patient (20 s), then tighten to 4× the slowest
  observed success, clamped 3–20 s. A fixed timeout cannot suit both a Mac on
  wifi (~0.26 s) and a watch proxying through a phone.
- Both become unnecessary once the app talks to a CDN. Keep them as
  belt-and-braces, not as load-bearing.

## Two measurement traps that produced wrong conclusions

Recorded because both produced confident, wrong answers that shipped.

1. **Test ordering.** Comparing "shared connection" against "fresh connection
   per request" in sequence showed fresh was 20× faster. Reversing the order
   showed the opposite. Whichever ran *second* won, because the server and
   connection were warm. Connection reuse is in fact slightly better. An earlier
   version recycled the connection on every timeout because of this — and
   recycling mid-flight tore down a session sibling requests were still using,
   which turned one dropped request into a whole slow cell.

2. **Pre-granting permissions.** Every simulator test pre-granted location with
   `simctl privacy grant`, so authorization was settled before launch. That
   tested the *second* launch, every time, and hid a real bug:
   `startUpdatingLocation()` while `.notDetermined` does nothing, and
   CoreLocation does not honour it retroactively when permission is granted. The
   app waited for a fix forever after a perfectly normal first launch.

## Smaller things that are deliberate

- **Map heading is held when the boat is stopped.** Course over ground is noise
  below about half a knot; steering the chart off it makes it spin on a mooring.
- **Bow offset is ignored without a trustworthy course**, for the same reason.
- **`sync` only ever removes time.** Rounding to the nearest minute sometimes
  handed a minute back, which is alarming mid-countdown. The cost is that
  syncing while early on a signal loses most of a minute.
- **Race statistics cover the racing track only.** Counting prestart distance
  against racing time inflated average speed above the speed actually sailed.
- **Packs claim every layer in `fetchedLayers`.** A pack missing any is treated
  as partial and re-fetched over the network, defeating the point of serving it.
- **Per-layer ENC field lists.** A buoy has `BOYSHP` and no `BCNSHP`; a beacon
  the reverse. Asking for one wrong field name makes the service reject the
  entire query, and the layer silently vanishes from the chart.
