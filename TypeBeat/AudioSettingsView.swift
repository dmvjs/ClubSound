//
//  AudioSettingsView.swift
//  TypeBeat
//
//  Created by Kirk Elliott on 12/13/24.
//
import SwiftUI

struct AudioSettingsView: View {
    @StateObject private var audioRouteManager = AudioRouteManager()

    var body: some View {
        VStack(spacing: 20) {
            Text("Current Output: \(audioRouteManager.currentOutput)")
                .font(.headline)
                .foregroundColor(.white)

            AudioOutputPicker()
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.blue))
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
        }
        .padding()
        .background(Color.black.opacity(0.9))
        .cornerRadius(12)
        .onAppear {
            audioRouteManager.updateCurrentOutput()
        }
    }
}
