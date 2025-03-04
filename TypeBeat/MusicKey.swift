//
//  MusicKey.swift
//  TypeBeat
//
//  Created by Kirk Elliott on 2/8/25.
//


enum MusicKey: String, CaseIterable, Comparable {
    case C, CSharp, D, DSharp, E, F, FSharp, G, GSharp, A, ASharp, B
    
    var localizedName: String {
        // Use the language manager to get localized key names
        let localizationKey = "key.\(self.rawValue.lowercased())"
        return LanguageManager.shared.localizedString(for: localizationKey)
    }
    
    static func < (lhs: MusicKey, rhs: MusicKey) -> Bool {
        // Order based on the natural order of musical keys
        let order = MusicKey.allCases
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}