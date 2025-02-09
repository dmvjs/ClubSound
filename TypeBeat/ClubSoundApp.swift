import SwiftUI

@main
struct LooperApp: App {
    @State private var languageChanged = false
    @State private var currentLocale: Locale = {
        if let savedLanguage = UserDefaults.standard.string(forKey: "AppLanguage") {
            return Locale(identifier: savedLanguage)
        }
        
        let preferredLanguage = Locale.current.language.languageCode?.identifier ?? "en"
        let supportedLanguages = ["en", "es", "fr", "de", "ja", "ko", "zh"]
        let defaultLanguage = supportedLanguages.contains(preferredLanguage) ? preferredLanguage : "en"
        
        UserDefaults.standard.set(defaultLanguage, forKey: "AppLanguage")
        return Locale(identifier: defaultLanguage)
    }()
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView()
                .id(languageChanged)
                .environment(\.locale, currentLocale)
                .onAppear {
                    setFallbackBackgroundColor()
                    setupLanguageChangeObserver()
                }
        }
    }
    
    private func setFallbackBackgroundColor() {
        if let window = UIApplication.shared.connectedScenes
            .first(where: { $0 is UIWindowScene }) as? UIWindowScene {
            window.windows.first?.backgroundColor = UIColor(
                red: 0.0, green: 0.0, blue: 0.35, alpha: 1.0
            )
        }
    }

    private func setupLanguageChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("LanguageChanged"),
            object: nil,
            queue: .main
        ) { [self] _ in
            withAnimation {
                languageChanged.toggle()
                currentLocale = LanguageManager.shared.getLocale()
            }
        }
    }
}

