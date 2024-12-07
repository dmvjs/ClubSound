import SwiftUI

@main
struct LooperApp: App {

    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .onAppear {
                    setFallbackBackgroundColor()
                }
        }
    }
    
    private func setFallbackBackgroundColor() {
            if let window = UIApplication.shared.connectedScenes
                .first(where: { $0 is UIWindowScene }) as? UIWindowScene {
                window.windows.first?.backgroundColor = UIColor(
                    red: 0.0, green: 0.0, blue: 0.35, alpha: 1.0 // Fallback color (dark blue)
                )
            }
        }
}

