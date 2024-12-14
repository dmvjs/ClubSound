//
//  AirPlayOutputPicker.swift
//  TypeBeat
//
//  Created by Kirk Elliott on 12/13/24.
//


import SwiftUI
import AVKit

struct AirPlayOutputPicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let routePickerView = AVRoutePickerView()
        routePickerView.tintColor = .white
        return routePickerView
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
