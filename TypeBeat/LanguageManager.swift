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

    func localizedString(for key: String, comment: String = "") -> String {
        let bundle = Bundle.main
        let languageCode = currentLanguage

        if let path = bundle.path(forResource: languageCode, ofType: "lproj"),
           let languageBundle = Bundle(path: path) {
            return NSLocalizedString(key, tableName: "Localizable", bundle: languageBundle, value: key, comment: comment)
        }

        return NSLocalizedString(key, tableName: "Localizable", bundle: bundle, value: key, comment: comment)
    }
}
