import SwiftUI
struct SampleRow: View {
    let sample: Sample
    let isInPlaylist: Bool
    let addToNowPlaying: () -> Void
    let removeFromNowPlaying: () -> Void
    
    var body: some View {
        Button(action: {
            if isInPlaylist {
                removeFromNowPlaying()
            } else {
                addToNowPlaying()
            }
        }) {
            HStack {
                Text(sample.title)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
} 
