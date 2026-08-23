// This module is the racing engine and chart renderer shared by the watch
// and phone apps. It is scoped to those two platforms: it speaks CoreLocation
// authorization and haptics, neither of which has a meaningful macOS form, and
// the package still needs to build for macOS so the pure-logic tests can run.
#if os(iOS) || os(watchOS)

import Foundation

#if canImport(WatchKit)
    import WatchKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Taps for the starting sequence.
///
/// In the last minute you are looking at the line, not the screen, so the
/// countdown has to be felt rather than read. The cues sharpen as the gun
/// approaches: soft on the minutes, distinct on the half-minute marks, clicks
/// for the final five, and something unmistakable for the start itself.
///
/// The watch has purpose-built haptics for this; a phone in a pocket has a
/// blunter vocabulary, so the mapping is per platform rather than pretending
/// one set of names means the same thing everywhere.
@MainActor
public enum Haptics {
    public enum Cue: Sendable {
        case gun
        case countdownTick
        case halfMinute
        case minute
        case sequenceStarted
        case sequenceStopped
        case pinged
        case cleared
        case refused
    }

    public static func play(_ cue: Cue) {
        #if canImport(WatchKit)
            WKInterfaceDevice.current().play(watchType(for: cue))
        #elseif canImport(UIKit)
            playOnPhone(cue)
        #endif
    }

    /// The cue for a given point in the countdown.
    public static func playCue(secondsBeforeStart seconds: TimeInterval) {
        switch seconds {
        case 0: play(.gun)
        case 1...5: play(.countdownTick)
        case 10, 20, 30: play(.halfMinute)
        default: play(.minute)
        }
    }

    public static func pinged() { play(.pinged) }
    public static func cleared() { play(.cleared) }
    public static func refused() { play(.refused) }
    public static func sequenceStarted() { play(.sequenceStarted) }
    public static func sequenceStopped() { play(.sequenceStopped) }
    public static func tick() { play(.countdownTick) }

    #if canImport(WatchKit)
        private static func watchType(for cue: Cue) -> WKHapticType {
            switch cue {
            case .gun: .success
            case .countdownTick: .click
            case .halfMinute: .directionUp
            case .minute: .notification
            case .sequenceStarted: .start
            case .sequenceStopped: .stop
            case .pinged: .success
            case .cleared: .retry
            case .refused: .failure
            }
        }
    #elseif canImport(UIKit)
        private static func playOnPhone(_ cue: Cue) {
            switch cue {
            case .gun:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .refused:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            case .pinged, .sequenceStarted:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .countdownTick, .cleared, .sequenceStopped:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .halfMinute, .minute:
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            }
        }
    #endif
}

#endif
