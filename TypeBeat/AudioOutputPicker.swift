//
//  AudioOutputPicker.swift
//  TypeBeat
//
//  Created by Kirk Elliott on 12/13/24.
//


import SwiftUI
import MediaPlayer

struct AudioOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let volumeView = MPVolumeView()
        volumeView.showsVolumeSlider = false // Hide the volume slider
        volumeView.showsRouteButton = true  // Show only the route picker
        volumeView.setRouteButtonImage(UIImage(systemName: "airplayaudio"), for: .normal)
        volumeView.tintColor = .white // Customize the button color
        return volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
