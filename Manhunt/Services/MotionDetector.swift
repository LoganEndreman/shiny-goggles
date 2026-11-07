import Foundation
import CoreMotion
import CoreLocation

/// Detects when the player is riding in a vehicle.
///
/// Primary signal: CoreMotion's activity classifier, which runs on the motion
/// coprocessor and classifies accelerometer data (the vibration and
/// acceleration profile of a car is very different from walking/running).
///
/// Backup signal: sustained GPS speed above what any human can run, so a
/// runner can't dodge detection on phones where the classifier is slow.
@MainActor
final class MotionDetector: ObservableObject {
    @Published private(set) var isInVehicle = false
    @Published private(set) var activityLabel = "Unknown"

    /// Fired on every transition into "in a vehicle".
    var onVehicleDetected: (() -> Void)?

    /// ~32 km/h – faster than an elite sprinter, slower than city traffic.
    static let vehicleSpeed: CLLocationSpeed = 9
    static let requiredFastFixes = 3

    private let activityManager = CMMotionActivityManager()
    private var running = false
    private var activitySaysVehicle = false
    private var fastFixes = 0

    var isAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }

    /// Triggers the Motion & Fitness permission prompt ahead of the game.
    func requestPermission() {
        guard isAvailable else { return }
        let now = Date()
        activityManager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: .main) { _, _ in }
    }

    func start() {
        guard !running else { return }
        running = true
        guard isAvailable else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let activity else { return }
            MainActor.assumeIsolated { self?.handle(activity) }
        }
    }

    func stop() {
        activityManager.stopActivityUpdates()
        running = false
        activitySaysVehicle = false
        fastFixes = 0
        isInVehicle = false
    }

    /// Feed GPS fixes in for the speed-based backup check.
    func ingest(_ location: CLLocation) {
        guard running, location.speed >= 0, location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 else { return }
        let reliable = location.speedAccuracy >= 0 && location.speedAccuracy < 5
        if reliable && location.speed >= Self.vehicleSpeed {
            fastFixes += 1
        } else if location.speed < Self.vehicleSpeed {
            fastFixes = 0
        }
        recompute()
    }

    private func handle(_ activity: CMMotionActivity) {
        activitySaysVehicle = activity.automotive && activity.confidence != .low
        activityLabel = Self.label(for: activity)
        recompute()
    }

    private func recompute() {
        let inVehicle = activitySaysVehicle || fastFixes >= Self.requiredFastFixes
        guard inVehicle != isInVehicle else { return }
        isInVehicle = inVehicle
        if inVehicle { onVehicleDetected?() }
    }

    private static func label(for a: CMMotionActivity) -> String {
        if a.automotive { return "In vehicle" }
        if a.cycling { return "Cycling" }
        if a.running { return "Running" }
        if a.walking { return "Walking" }
        if a.stationary { return "Stationary" }
        return "Unknown"
    }
}
