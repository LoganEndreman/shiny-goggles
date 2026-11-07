import Foundation

/// "4:05" or "1:02:09".
func clock(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded(.up)))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
