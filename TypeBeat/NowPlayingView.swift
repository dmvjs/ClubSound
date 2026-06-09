import SwiftUI

struct NowPlayingView: View {
    @Bindable var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 2) {
            MainVolumeControl(audioManager: audioManager)
                .padding(.horizontal, 6)
                .padding(.top, 2)
                .padding(.bottom, 4)

            NowPlayingList(audioManager: audioManager)
        }
        .frame(maxWidth: .greatestFiniteMagnitude, alignment: .bottom)
    }
}
