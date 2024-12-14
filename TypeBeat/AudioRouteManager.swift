//
//  AudioRouteManager.swift
//  TypeBeat
//
//  Created by Kirk Elliott on 12/13/24.
//


import AVFoundation

class AudioRouteManager: ObservableObject {
    @Published var currentOutput: String = "Speaker"

    private var audioSession = AVAudioSession.sharedInstance()

    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(routeChanged),
            name: AVAudioSession.routeChangeNotification,
            object: nil
        )
        updateCurrentOutput()
    }

    @objc private func routeChanged(notification: Notification) {
        updateCurrentOutput()
    }

    func updateCurrentOutput() {
        guard let currentRoute = audioSession.currentRoute.outputs.first else {
            currentOutput = "Unknown"
            return
        }
        currentOutput = currentRoute.portName
    }
}
