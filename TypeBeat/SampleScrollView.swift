import SwiftUI

struct SampleScrollView: View {
    let groupedSamples: [(Double, [(MusicKey, [Sample])])]
    let addToNowPlaying: (Sample) -> Void
    let removeFromNowPlaying: (Sample) -> Void
    let isInPlaylist: (Sample) -> Bool
    
    // MARK: - Constants
    private enum Constants {
        static let horizontalPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let headerHeight: CGFloat = 44
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: Constants.sectionSpacing, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedSamples, id: \.0) { bpm, keyGroups in
                    Section {
                        ForEach(keyGroups, id: \.0) { key, samples in
                            VStack(alignment: .leading, spacing: 8) {
                                keyHeader(for: key, samples: samples)
                                samplesList(samples)
                            }
                            .id("\(Int(bpm))-\(key.rawValue)")
                        }
                    } header: {
                        bpmHeader(bpm: bpm)
                            .id("\(Int(bpm))")
                    }
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Header Views
    private func bpmHeader(bpm: Double) -> some View {
        Text(String(format: "section.bpm".localized, Int(bpm)))
            .font(.title2.bold())
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: Constants.headerHeight)
            .padding(.leading, 4)
            .background(
                Color.black
                    .opacity(0.95)
                    .edgesIgnoringSafeArea(.horizontal)
            )
    }
    
    private func keyHeader(for key: MusicKey, samples: [Sample]) -> some View {
        Button(action: {
            let availableSamples = samples.filter { !isInPlaylist($0) }
            if let firstAvailable = availableSamples.first {
                addToNowPlaying(firstAvailable)
            }
        }) {
            HStack {
                Text(key.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                keyColor(for: key)
            )
            .cornerRadius(4)
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
        .allowsHitTesting(true)
    }
    
    private func samplesList(_ samples: [Sample]) -> some View {
        ForEach(samples) { sample in
            SampleRecordView(
                sample: sample,
                isInPlaylist: isInPlaylist(sample),
                onSelect: { addToNowPlaying(sample) },
                onRemove: { removeFromNowPlaying(sample) }
            )
        }
    }
    
    // MARK: - Helpers
    private func getKeyName(for key: Int) -> String {
        let keyNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return keyNames[key % 12]
    }
    
    private func keyColor(for key: MusicKey) -> Color {
        Sample(id: 0, title: "", key: key, bpm: 0, fileName: "").keyColor()
    }
    
    private func sectionHeader(bpm: Double, key: MusicKey) -> String {
        let bpmText = "section.bpm".localized(with: Int(bpm))
        let keyText = "section.key".localized(with: key.localizedName)
        return "\(bpmText) - \(keyText)"
    }
}

// MARK: - SafeArea Environment Key
private struct SafeAreaInsetsKey: EnvironmentKey {
    static let defaultValue: EdgeInsets = .init()
}

extension EnvironmentValues {
    var safeAreaInsets: EdgeInsets {
        get { self[SafeAreaInsetsKey.self] }
        set { self[SafeAreaInsetsKey.self] = newValue }
    }
}
