
import Foundation
import UIKit
import AVFoundation

class WakeLockManager: ObservableObject {
    @Published var isWakeLockEnabled: Bool = false
    
    func enableWakeLock() {
        UIApplication.shared.isIdleTimerDisabled = true
        isWakeLockEnabled = true
    }
    
    func disableWakeLock() {
        UIApplication.shared.isIdleTimerDisabled = false
        isWakeLockEnabled = false
    }
}
