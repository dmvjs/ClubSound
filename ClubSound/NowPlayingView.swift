import SwiftUI

struct NowPlayingView: View {
    let proxy: ScrollViewProxy
    @Binding var nowPlaying: [Sample]
    @Binding var sampleVolumes: [Int: Float]
    @Binding var masterVolume: Float
    @ObservedObject var audioManager: AudioManager
    let removeFromNowPlaying: (Sample) -> Void

    var body: some View {
        VStack(spacing: 8) {
            MasterVolumeControl(masterVolume: $masterVolume, audioManager: audioManager)

            if nowPlaying.isEmpty {
                EmptyView()
            } else {
                NowPlayingList(
                    nowPlaying: $nowPlaying,
                    sampleVolumes: $sampleVolumes,
                    audioManager: audioManager,
                    removeFromNowPlaying: removeFromNowPlaying
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.vertical, 16)
    }
}