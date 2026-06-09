import SwiftUI

@main
struct LooperApp: App {
    @AppStorage("AppLanguage") private var language: String = Self.defaultLanguage()
    @State private var splashVisible = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView(audioManager: .shared)

                if splashVisible {
                    SplashScreenView()
                        .transition(.opacity)
                        .zIndex(1)
                        .task {
                            // Splash plays its entrance animation underneath
                            // the audio engine warming up; then dissolves.
                            try? await Task.sleep(for: .milliseconds(1400))
                            withAnimation(.easeInOut(duration: 0.45)) {
                                splashVisible = false
                            }
                        }
                }
            }
            .id(language)
            .environment(\.locale, Locale(identifier: language))
            .onAppear(perform: setFallbackBackgroundColor)
        }
    }

    private static func defaultLanguage() -> String {
        let preferred = Locale.current.language.languageCode?.identifier ?? "en"
        let supported = ["en", "es", "fr", "de", "ja", "ko", "zh"]
        return supported.contains(preferred) ? preferred : "en"
    }

    private func setFallbackBackgroundColor() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.windows.first?.backgroundColor = UIColor(
            red: 0.05, green: 0.07, blue: 0.20, alpha: 1.0
        )
    }
}
