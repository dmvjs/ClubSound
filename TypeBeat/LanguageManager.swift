import Foundation

class LanguageManager {
    static let shared = LanguageManager()
    
    private let languageKey = "AppLanguage"
    private var pendingLanguage: String?
    
    var currentLanguage: String {
        get {
            UserDefaults.standard.string(forKey: languageKey) ?? "en"
        }
        set {
            pendingLanguage = newValue
        }
    }
    
    func confirmLanguageChange() {
        if let newLanguage = pendingLanguage {
            UserDefaults.standard.set(newLanguage, forKey: languageKey)
            UserDefaults.standard.synchronize()
            NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
            pendingLanguage = nil
        }
    }
    
    func cancelLanguageChange() {
        pendingLanguage = nil
    }
    
    func getLocale() -> Locale {
        return Locale(identifier: currentLanguage)
    }
} 