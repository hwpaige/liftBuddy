import Foundation
import liftBuddyKit

// Decodes output from the Python baker using the app's own decoder. If the two
// schemas ever drift, this fails loudly instead of the app silently showing an
// empty chart.
let root = URL(fileURLWithPath: NSString(string: "~/PycharmProjects/liftbuddy-charts/out")
    .expandingTildeInPath)
let files = try FileManager.default
    .subpathsOfDirectory(atPath: root.appendingPathComponent("cells").path)
    .filter { $0.hasSuffix(".json") }
    .sorted()

guard !files.isEmpty else { fatalError("no baked cells found") }

var totalAreas = 0, totalContours = 0, totalLand = 0, totalMarks = 0, totalVertices = 0
let decoder = ChartCache.decoder()

for relative in files {
    let url = root.appendingPathComponent("cells").appendingPathComponent(relative)
    let data = try Data(contentsOf: url)
    let pack = try decoder.decode(ChartPack.self, from: data)

    // The app treats a pack missing any racing layer as partial and refetches it.
    let missing = pack.missingLayers(from: ENCDirect.racingLayers)
    precondition(missing.isEmpty, "\(relative) would be treated as incomplete: \(missing.map(\.name))")

    totalAreas += pack.depthAreas.count
    totalContours += pack.depthContours.count
    totalLand += pack.land.count
    totalMarks += pack.marks.count
    totalVertices += pack.vertexCount
}

print("decoded \(files.count) packs with the app's own decoder")
print("  depth areas   \(totalAreas)")
print("  contours      \(totalContours)")
print("  land          \(totalLand)")
print("  marks         \(totalMarks)")
print("  vertices      \(totalVertices)")

// Spot-check that geometry survived the round trip meaningfully.
let sample = try decoder.decode(
    ChartPack.self,
    from: Data(contentsOf: root.appendingPathComponent("cells/13/2472/3056.json")))
if let area = sample.depthAreas.first, let ring = area.rings.first, ring.count > 2 {
    let first = ring[0]
    print("  sample vertex \(first.latitude), \(first.longitude)")
    precondition(first.isValid, "decoded coordinate is not a valid position")
    precondition(sample.bounds.contains(sample.bounds.center), "bounds are self-inconsistent")
}
if let mark = sample.marks.first(where: { $0.name != nil }) {
    print("  sample mark   \(mark.kind.rawValue) \(mark.colour ?? "-") \(mark.name ?? "-")")
}
print("SCHEMA OK")
