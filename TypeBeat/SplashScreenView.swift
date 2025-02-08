//
//  SplashScreenView.swift
//  Looper
//
//  Created by Kirk Elliott on 12/2/24.
//


import SwiftUI

struct SplashScreenView: View {
    @State private var scale: CGFloat = 0.5
    @State private var opacity: Double = 0.0


    @State private var isActive = false

        var body: some View {
            if isActive {
                ContentView(audioManager: AudioManager.shared)
            } else {
                ZStack {
                            // Background
                            LinearGradient(
                                gradient: Gradient(colors: [Color.black, Color.blue.opacity(0.7)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .edgesIgnoringSafeArea(.all)

                            // Animated Logo
                            Image("splash")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 150, height: 150)
                                .scaleEffect(scale)
                                .opacity(opacity)
                                .onAppear {
                                    withAnimation(.easeOut(duration: 1.5)) {
                                        scale = 1.2
                                        opacity = 1.0
                                    }
                                    withAnimation(.easeOut(duration: 3.0)) {
                                        scale = 1.0
                                    }
                                }
                        }
                        .transition(.opacity)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                                withAnimation {
                                    isActive = true
                                }
                            }
                        }
            }
        }

}
