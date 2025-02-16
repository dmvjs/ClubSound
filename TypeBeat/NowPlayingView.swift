import SwiftUI

struct NowPlayingView: View {
    @Binding var nowPlaying: [Sample]
    @Binding var sampleVolumes: [Int: Float]
    @Binding var mainVolume: Float
    @ObservedObject var audioManager: AudioManager
    let removeFromNowPlaying: (Sample) -> Void

    var body: some View {
        VStack(spacing: 2) {
            if !nowPlaying.isEmpty {
                MainVolumeControl(mainVolume: $mainVolume, audioManager: audioManager)
                    .padding(.horizontal, 12)
                    .padding(.top, 2)
                    .padding(.bottom, 4)
                
                NowPlayingList(
                    nowPlaying: $nowPlaying,
                    sampleVolumes: $sampleVolumes,
                    audioManager: audioManager,
                    removeFromNowPlaying: removeFromNowPlaying
                )
            }
        }
        .frame(maxWidth: .greatestFiniteMagnitude, alignment: .bottom)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
