//
//  MusicKey.swift
//  TypeBeat
//
//  Created by Kirk Elliott on 2/8/25.
//


enum MusicKey: String, CaseIterable {
    case C = "C"
    case CSharp = "C#"
    case D = "D"
    case DSharp = "D#"
    case E = "E"
    case F = "F"
    case FSharp = "F#"
    case G = "G"
    case GSharp = "G#"
    case A = "A"
    case ASharp = "A#"
    case B = "B"
    
    var localizedName: String {
        return "key.\(self.rawValue.lowercased().replacingOccurrences(of: "#", with: "sharp"))".localized
    }
    
    var name: String {
        return localizedName
    }
}