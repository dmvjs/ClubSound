import Foundation
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
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
