import AVFoundation
import Observation

@MainActor
@Observable
final class AudioRouteManager {
    var currentOutput: String = "Speaker"

    init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateCurrentOutput() }
        }
        updateCurrentOutput()
    }

    func updateCurrentOutput() {
        guard let currentRoute = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            currentOutput = "Unknown"
            return
        }
        currentOutput = currentRoute.portName
    }
}
