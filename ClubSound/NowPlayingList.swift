//
//  NowPlayingList.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/6/24.
//


import SwiftUI

struct NowPlayingList: View {
    @Binding var nowPlaying: [Sample]
    @Binding var sampleVolumes: [Int: Float]
    @ObservedObject var audioManager: AudioManager
    let removeFromNowPlaying: (Sample) -> Void

    var body: some View {
        List {
            ForEach(nowPlaying, id: \.id) { sample in
                NowPlayingRow(
                    sample: sample,
                    volume: Binding(
                        get: { sampleVolumes[sample.id] ?? 0.5 },
                        set: { newValue in
                            sampleVolumes[sample.id] = newValue
                            audioManager.setVolume(for: sample, volume: newValue)
                        }
                    ),
                    remove: { removeFromNowPlaying(sample) },
                    keyColor: sample.keyColor() // Use centralized color logic
                )
            }
        }
        .listStyle(PlainListStyle())
        .frame(height: CGFloat(nowPlaying.count) * 72 + 40)
        .animation(.easeInOut, value: nowPlaying.count)
    }

}
