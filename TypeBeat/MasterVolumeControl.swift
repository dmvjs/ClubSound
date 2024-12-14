//
//  MasterVolumeControl.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/6/24.
//


import SwiftUI

struct MasterVolumeControl: View {
    @Binding var masterVolume: Float
    @ObservedObject var audioManager: AudioManager

    var body: some View {
        HStack {
            Circle()
                .fill(.black)
                .frame(width: 33, height: 33)
                .overlay(
                    Text("\(audioManager.bpm, specifier: "%.0f")")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.white)
                )
                .padding(8)

            Text("Master Volume")
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer()

            Slider(value: $masterVolume, in: 0...1)
                .accentColor(.blue)
                .frame(width: 150)
                .onChange(of: masterVolume) { newValue, _ in
                    audioManager.setMasterVolume(newValue)
                }
                .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.4))
        )
        .padding(.vertical, 8)
    }
}
