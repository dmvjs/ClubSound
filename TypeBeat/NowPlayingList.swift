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
                    keyColor: sample.keyColor(),
                    audioManager: audioManager
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(PlainListStyle())
        .frame(height: CGFloat(nowPlaying.count) * 60 + 10)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut, value: nowPlaying.count)
        .ignoresSafeArea(edges: .horizontal)
    }
}
