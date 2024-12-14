import SwiftUI

struct SampleScrollView: View {
    let groupedSamples: [(Double, [(Int, [Sample])])]
    let addToNowPlaying: (Sample) -> Void
    let removeFromNowPlaying: (Sample) -> Void
    let isInPlaylist: (Sample) -> Bool

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(groupedSamples, id: \.0) { (bpm, keyGroups) in
                                VStack(alignment: .leading) {
                                    // BPM Header
                                    Text("\(Int(bpm)) BPM")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .padding(.leading)

                                    ForEach(keyGroups, id: \.0) { (_, samples) in
                                        VStack(alignment: .leading, spacing: 10) {
                                            ForEach(samples, id: \.id) { sample in
                                                SampleRecordView(
                                                    sample: sample,
                                                    isInPlaylist: isInPlaylist(sample),
                                                    onSelect: {
                                                        addToNowPlaying(sample)
                                                    },
                                                    onRemove: {
                                                        removeFromNowPlaying(sample)
                                                    }
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 44)
                    }
                }
            }
        }
    }
}
