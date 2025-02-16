import SwiftUI
struct SampleRow: View {
    let sample: Sample
    let isInPlaylist: Bool
    let addToNowPlaying: () -> Void
    let removeFromNowPlaying: () -> Void
    
    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            if isInPlaylist {
                DispatchQueue.main.async {
                    removeFromNowPlaying()
                }
            } else {
                DispatchQueue.main.async {
                    addToNowPlaying()
                }
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
