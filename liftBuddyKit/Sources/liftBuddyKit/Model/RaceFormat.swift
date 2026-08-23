import Foundation

/// Display formatting shared by the watch and the phone.
///
/// On a wrist, at speed, in spray: short strings, monospaced digits, no units
/// the reader has to decode.
public enum RaceFormat {
    /// A countdown as `4:32`, or `-0:15` once the gun has gone.
    public static func clock(_ seconds: TimeInterval) -> String {
        let negative = seconds < 0
        let total = Int(abs(seconds).rounded(.down))
        let string = String(format: "%d:%02d", total / 60, total % 60)
        return negative ? "-" + string : string
    }

    /// Seconds of slack, signed: `+12s`, `-8s`.
    public static func signedSeconds(_ seconds: TimeInterval) -> String {
        let value = Int(seconds.rounded())
        return value >= 0 ? "+\(value)s" : "\(value)s"
    }

    /// Distance with a sensible unit for the scale: meters up close, kilometers
    /// once the number would stop fitting.
    public static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        return String(format: "%.2f km", meters / 1000)
    }

    /// Boat lengths, the unit sailors actually judge a start in.
    public static func boatLengths(_ count: Double) -> String {
        count < 10 ? String(format: "%.1f", count) : "\(Int(count.rounded()))"
    }

    public static func knots(_ metersPerSecond: Double) -> String {
        String(format: "%.1f kn", metersPerSecond.knots)
    }

    /// A signed bias angle: `8°` — the sign is carried by the end name beside it.
    public static func degrees(_ value: Double) -> String {
        "\(Int(abs(value).rounded()))°"
    }
}
