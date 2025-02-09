import Foundation

extension String {
    var localized: String {
        let language = UserDefaults.standard.string(forKey: "AppLanguage") ?? "en"
        let path = Bundle.main.path(forResource: language, ofType: "lproj")
        let bundle = path != nil ? Bundle(path: path!) : Bundle.main
        
        let localizedString = NSLocalizedString(self, tableName: nil, bundle: bundle ?? Bundle.main, value: "", comment: "")
        
        // If we get back the same string and it's a key format (contains a dot)
        if localizedString == self && self.contains(".") {
            // Return everything after the last dot
            return String(self.split(separator: ".").last ?? "")
        }
        
        return localizedString
    }
    
    func localized(with arguments: CVarArg...) -> String {
            let localizedString = NSLocalizedString(self, comment: "")
            
            // If the localized string is the same as the key and contains a dot,
            // it means no translation was found - return the part after the dot
            if localizedString == self && self.contains(".") {
                return String(self.split(separator: ".").last ?? "")
            }
            
            if arguments.isEmpty {
                return localizedString
            }
            
            return String(format: localizedString, arguments: arguments)
        }
}
