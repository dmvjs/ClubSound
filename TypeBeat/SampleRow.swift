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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                    .shadow(color: isInPlaylist ? .red.opacity(0.2) : .clear, radius: 4)
            )
            .padding(.horizontal, 4)
        }
    }
} 
