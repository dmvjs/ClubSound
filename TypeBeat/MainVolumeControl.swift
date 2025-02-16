//
//  MainVolumeControl.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/6/24.
//


import SwiftUI

struct MainVolumeControl: View {
    @Binding var mainVolume: Float
    @ObservedObject var audioManager: AudioManager
    @State private var progress: Double = 0
    
    var body: some View {
        HStack {
            // BPM Circle with progress ring
            ZStack {
                Circle()
                    .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                    .frame(width: 39, height: 39)
                
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(Color.blue, lineWidth: 3)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 39, height: 39)
                    .animation(.linear(duration: 1/30), value: progress)
                
                Circle()
                    .fill(Color.black)
                    .frame(width: 33, height: 33)
                    .overlay(
                        Text("\(Int(audioManager.bpm))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            .padding(8)
            .onAppear {
                // Start the progress updates when view appears
                startProgressUpdates()
            }

            Text("main.volume".localized)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(2)
            Spacer()

            Slider(value: $mainVolume, in: 0...1)
                .accentColor(.blue)
                .frame(width: 150)
                .onChange(of: mainVolume) { newValue, _ in
                    audioManager.setMasterVolume(newValue)
                }
                .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.systemGray6).opacity(0.4))
        )
        .padding(.top, 8)
    }
    
    private func startProgressUpdates() {
        // Create a timer that updates more frequently
        Timer.scheduledTimer(withTimeInterval: 1/30, repeats: true) { _ in
            if audioManager.isPlaying {
                progress = audioManager.loopProgress()
            } else {
                progress = 0
            }
        }
    }
}
