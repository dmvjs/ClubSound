import SwiftUI

enum MusicKey: String, CaseIterable, Comparable {
    case C, CSharp, D, DSharp, E, F, FSharp, G, GSharp, A, ASharp, B

    var localizedName: String {
        LanguageManager.shared.localizedString(for: "key.\(rawValue.lowercased())")
    }

    var color: Color {
        switch self {
        case .C:      return Color(red: 0.20, green: 0.20, blue: 0.50)
        case .CSharp: return Color(red: 0.40, green: 0.20, blue: 0.50)
        case .D:      return Color(red: 0.60, green: 0.20, blue: 0.30)
        case .DSharp: return Color(red: 0.70, green: 0.50, blue: 0.20)
        case .E:      return Color(red: 0.80, green: 0.40, blue: 0.20)
        case .F:      return Color(red: 0.60, green: 0.20, blue: 0.20)
        case .FSharp: return Color(red: 0.20, green: 0.50, blue: 0.20)
        case .G:      return Color(red: 0.50, green: 0.50, blue: 0.20)
        case .GSharp: return Color(red: 0.20, green: 0.60, blue: 0.60)
        case .A:      return Color(red: 0.30, green: 0.40, blue: 0.50)
        case .ASharp: return Color(red: 0.60, green: 0.40, blue: 0.50)
        case .B:      return Color(red: 0.20, green: 0.20, blue: 0.50)
        }
    }

    static func < (lhs: MusicKey, rhs: MusicKey) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}
