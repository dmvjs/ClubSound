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
        Text(key.name)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(keyColor(for: key))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
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

extension View {
    func sticky(axis: Axis) -> some View {
        StickyModifier(axis: axis, content: self)
    }
}

struct StickyModifier<T: View>: View {
    let axis: Axis
    let content: T
    
    var body: some View {
        content
            .overlay(GeometryReader { proxy in
                Color.clear.preference(
                    key: StickyPreferenceKey.self,
                    value: [StickyItem(id: proxy.frame(in: .named("scroll")).debugDescription, frame: proxy.frame(in: .named("scroll")), axis: axis)]
                )
            })
    }
}

struct StickyItem: Equatable {
    let id: String
    let frame: CGRect
    let axis: Axis
}

struct StickyPreferenceKey: PreferenceKey {
    static var defaultValue: [StickyItem] = []
    
    static func reduce(value: inout [StickyItem], nextValue: () -> [StickyItem]) {
        value.append(contentsOf: nextValue())
    }
}
