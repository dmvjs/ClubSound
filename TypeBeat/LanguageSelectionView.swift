import SwiftUI

struct LanguageSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("AppLanguage") private var language: String = "en"

    @State private var pendingLanguage: String?
    @State private var showingConfirmation = false

    private struct Language: Identifiable {
        let id: String
        let name: String
        init(_ id: String, _ name: String) { self.id = id; self.name = name }
    }

    private let languages: [Language] = [
        .init("en", "English"),
        .init("es", "Español"),
        .init("fr", "Français"),
        .init("de", "Deutsch"),
        .init("ja", "日本語"),
        .init("ko", "한국어"),
        .init("zh", "中文")
    ]

    var body: some View {
        NavigationStack {
            List(languages) { lang in
                Button {
                    guard lang.id != language else { return }
                    pendingLanguage = lang.id
                    showingConfirmation = true
                } label: {
                    HStack {
                        Text(lang.name)
                        Spacer()
                        if lang.id == language {
                            Image(systemName: "checkmark").foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("language.select".localized)
            .alert("language.change.title".localized, isPresented: $showingConfirmation) {
                Button("language.change.cancel".localized, role: .cancel) {
                    pendingLanguage = nil
                }
                Button("language.change.confirm".localized, action: confirmLanguageChange)
            } message: {
                Text("language.change.message".localized)
            }
        }
    }

    private func confirmLanguageChange() {
        guard let newLanguage = pendingLanguage else { return }
        AudioManager.shared.reset()
        dismiss()
        // Let the sheet dismissal animate before triggering the root view
        // rebuild that the @AppStorage change causes (via .id(language) in
        // ClubSoundApp).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            language = newLanguage
        }
    }
}
