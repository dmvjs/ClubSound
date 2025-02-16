import SwiftUI

struct Language {
    let code: String
    let name: String
}

struct LanguageSelectionView: View {
    @Environment(\.dismiss) var dismiss
    @State private var showingConfirmation = false
    @State private var pendingLanguage: String?
    
    private let languages = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Español"),
        Language(code: "fr", name: "Français"),
        Language(code: "de", name: "Deutsch"),
        Language(code: "ja", name: "日本語"),
        Language(code: "ko", name: "한국어"),
        Language(code: "zh", name: "中文")
    ]
    
    var body: some View {
        NavigationView {
            List(languages, id: \.code) { language in
                Button(action: {
                    if language.code != LanguageManager.shared.currentLanguage {
                        pendingLanguage = language.code
                        showingConfirmation = true
                    }
                }) {
                    HStack {
                        Text(language.name)
                        Spacer()
                        if language.code == LanguageManager.shared.currentLanguage {
                            Image(systemName: "checkmark")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("language.select".localized)
            .alert("language.change.title".localized, isPresented: $showingConfirmation) {
                Button("language.change.cancel".localized, role: .cancel) {
                    pendingLanguage = nil
                }
                Button("language.change.confirm".localized) {
                    if let newLanguage = pendingLanguage {
                        AudioManager.shared.stopAllPlayers()
                        UserDefaults.standard.set(newLanguage, forKey: "AppLanguage")
                        UserDefaults.standard.synchronize()
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            NotificationCenter.default.post(name: NSNotification.Name("LanguageChanged"), object: nil)
                        }
                    }
                }
            } message: {
                Text("language.change.message".localized)
            }
        }
    }
} 
