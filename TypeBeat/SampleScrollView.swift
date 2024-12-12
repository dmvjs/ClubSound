//
//  SampleScrollView.swift
//  ClubSound
//
//  Created by Kirk Elliott on 12/6/24.
//


import SwiftUI

struct SampleScrollView: View {
    let proxy: ScrollViewProxy
    let groupedSamples: [(Double, [(Int, [Sample])])]
    let addToNowPlaying: (Sample) -> Void
    let isInPlaylist: (Sample) -> Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ForEach(groupedSamples, id: \.0) { (bpm, keyGroups) in
                    VStack(alignment: .leading) {
                        // BPM Header
                        Text("\(Int(bpm)) BPM")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(.leading)
                            .id(bpm)

                        ForEach(keyGroups, id: \.0) { (key, samples) in
                            VStack(alignment: .leading, spacing: 10) {
                                // Key Header
                                HStack {
                                    Text("Key \(key)")
                                        .font(.headline)
                                        .foregroundColor(samples.first?.keyColor() ?? .gray) // Use color from the first sample
                                        .padding(.leading)
                                }

                                // Sample List
                                ForEach(samples, id: \.id) { sample in
                                    SampleRecordView(sample: sample, isInPlaylist: isInPlaylist(sample)) {
                                        addToNowPlaying(sample)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom)
        }
    }
}
