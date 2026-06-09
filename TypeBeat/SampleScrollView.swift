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
                                    .background(Color.black)
                                samplesList(samples.sorted(by: { $0.title < $1.title }))
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
            // Solid black backdrop that extends UP through the top safe
            // area, so when the header is pinned at the top of the scroll
            // view, it covers the whole status-bar zone too. The soft
            // scroll edge effect then handles the fade below the header.
            .background(
                Color.black.ignoresSafeArea(edges: [.top, .horizontal])
            )
            .accessibilityIdentifier("bpm-header-\(Int(bpm))")
    }
    
    private func keyHeader(for key: MusicKey, samples: [Sample]) -> some View {
        Text(key.localizedName)
            .font(.system(size: 12, weight: .heavy))
            .foregroundColor(key.color)
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
