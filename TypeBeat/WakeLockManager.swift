import UIKit
import Observation

@MainActor
@Observable
final class WakeLockManager {
    var isWakeLockEnabled: Bool = false

    func enableWakeLock() {
        UIApplication.shared.isIdleTimerDisabled = true
        isWakeLockEnabled = true
    }

    func disableWakeLock() {
        UIApplication.shared.isIdleTimerDisabled = false
        isWakeLockEnabled = false
    }
}
