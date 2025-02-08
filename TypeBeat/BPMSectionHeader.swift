import SwiftUI
struct BPMSectionHeader: View {
    let bpm: Double
    
    var body: some View {
        Text("\(Int(bpm)) BPM")
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.8))
    }
} 
