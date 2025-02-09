import SwiftUI

@main
struct LooperApp: App {
    @State private var languageChanged = false
    @State private var currentLocale: Locale = {
        // If user has explicitly set a language, use that
        if let savedLanguage = UserDefaults.standard.string(forKey: "AppLanguage") {
            return Locale(identifier: savedLanguage)
        }
        
        // Otherwise get the user's preferred language from system
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        
        // Only use if it's one of our supported languages
        let supportedLanguages = ["en", "es", "fr", "de", "ja", "ko", "zh"]
        let defaultLanguage = supportedLanguages.contains(preferredLanguage) ? preferredLanguage : "en"
        
        // Save this as our app's language
        UserDefaults.standard.set(defaultLanguage, forKey: "AppLanguage")
        UserDefaults.standard.synchronize()
        
        return Locale(identifier: defaultLanguage)
    }()
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .id(languageChanged)
                .environment(\.locale, currentLocale)
                .onAppear {
                    print("App starting with locale: \(currentLocale.identifier)")  // Debug
                    setFallbackBackgroundColor()
                    setupLanguageChangeObserver()
                }
        }
    }
    
    private func getCurrentLocale() -> Locale {
        return LanguageManager.shared.getLocale()
    }
    
    private func setFallbackBackgroundColor() {
        if let window = UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene {
            window.windows.first?.backgroundColor = UIColor(
                red: 0.0, green: 0.0, blue: 0.35, alpha: 1.0 // Fallback color (dark blue)
            )
        }
    }

    private func setupLanguageChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LanguageChanged"),
            object: nil,
            queue: .main
        ) { _ in
            languageChanged.toggle()
            
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first
            else { return }
            
            let rootView = SplashScreenView()
                .environment(\.locale, getCurrentLocale())
            
            window.rootViewController = UIHostingController(rootView: rootView)
            
            UIView.transition(
                with: window,
                duration: 0.3,
                options: .transitionCrossDissolve,
                animations: nil,
                completion: nil
            )
        }
    }
}

