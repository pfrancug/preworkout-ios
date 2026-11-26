import Foundation

/// One way to show a duration everywhere: "0:45", "4:07", "1:05:03".
/// Hours appear only from one hour up. Never raw seconds.
enum DurationText {
    static func format(_ seconds: Double) -> String {
        format(Int(max(0, seconds).rounded()))
    }

    static func format(_ seconds: Int) -> String {
        let total = max(0, seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Splits whole seconds into hours, minutes and seconds.
    static func parts(_ seconds: Int) -> (h: Int, m: Int, s: Int) {
        let total = max(0, seconds)
        return (total / 3600, (total % 3600) / 60, total % 60)
    }
}
