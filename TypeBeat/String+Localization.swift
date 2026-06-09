import Foundation

extension String {
    /// Localized string for the user's selected `AppLanguage`. Falls back to
    /// the bundle default if that .lproj is missing. If the key itself is
    /// returned (no translation found) AND looks like a dotted key
    /// (`"section.bpm"`), strips the prefix so callers don't display
    /// `"section.bpm"` verbatim.
    var localized: String {
        let result = NSLocalizedString(self, bundle: .appLocalization, value: "", comment: "")
        return missingKeyFallback(result)
    }

    /// Same lookup as `localized`, with `String(format:)` interpolation.
    func localized(with arguments: CVarArg...) -> String {
        let format = NSLocalizedString(self, bundle: .appLocalization, value: "", comment: "")
        let resolved = missingKeyFallback(format)
        return arguments.isEmpty ? resolved : String(format: resolved, arguments: arguments)
    }

    private func missingKeyFallback(_ result: String) -> String {
        guard result == self || result.isEmpty, contains(".") else { return result }
        return String(split(separator: ".").last ?? "")
    }
}

extension Bundle {
    /// Bundle for the user's chosen `AppLanguage`. Falls back to `.main` if
    /// the .lproj for that language isn't bundled.
    static var appLocalization: Bundle {
        let language = UserDefaults.standard.string(forKey: "AppLanguage") ?? "en"
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"),
           let bundle = Bundle(path: path) {
            return bundle
        }
        return .main
    }
}
