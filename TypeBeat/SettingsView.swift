import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    let languages = [
        ("English", "en"),
        ("Deutsch", "de"),
        ("Español", "es"),
        ("Français", "fr"),
        ("日本語", "ja"),
        ("한국어", "ko"),
        ("中文", "zh")
    ]
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("settings.language".localized)) {
                    ForEach(languages, id: \.1) { language in
                        Button(action: {
                            changeLanguage(to: language.1)
                        }) {
                            HStack {
                                Text(language.0)
                                Spacer()
                                if UserDefaults.standard.string(forKey: "AppLanguage") == language.1 {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("settings.title".localized)
            .navigationBarItems(trailing: Button("common.done".localized) {
                dismiss()
            })
        }
    }
    
    func changeLanguage(to language: String) {
        // Stop all playback first
        AudioManager.shared.stopAllPlayback()
        
        // Set the new language
        UserDefaults.standard.set(language, forKey: "AppLanguage")
        UserDefaults.standard.synchronize()
        
        // Restart app
        exit(0)
    }
} 