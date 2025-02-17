import SwiftUI
struct SampleRecordView: View {
    let sample: Sample
    let isInPlaylist: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Text(sample.title)
            .font(.system(size: 16))
            .foregroundColor(.white.opacity(0.9))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .onTapGesture {
                if !isInPlaylist {
                    onSelect()
                }
            }
            .accessibilityIdentifier("sample-\(sample.id)")
    }
}
