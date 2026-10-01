import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var app

    @State private var key = ""
    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var canSaveAnyway = false

    private var trimmedKey: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "cloud.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.tint)
                        Text("Bulut")
                            .font(.largeTitle.bold())
                        Text("Ollama Cloud modelleriyle kişisel sohbet. Anahtarın yalnızca bu cihazın Anahtar Zinciri'nde saklanır ve sadece ollama.com'a gönderilir.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .listRowBackground(Color.clear)

                Section {
                    SecureField("API anahtarı", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.password)
                        .onSubmit { Task { await verifyAndSave() } }
                    PasteButton(payloadType: String.self) { strings in
                        Task { @MainActor in
                            key = strings.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        }
                    }
                } header: {
                    Text("API anahtarı")
                } footer: {
                    Link("Anahtarı ollama.com/settings/keys adresinden oluştur",
                         destination: URL(string: "https://ollama.com/settings/keys")!)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        if canSaveAnyway {
                            Button("Doğrulamadan kaydet") { save() }
                        }
                    }
                }

                Section {
                    Button {
                        Task { await verifyAndSave() }
                    } label: {
                        HStack {
                            Text(isChecking ? "Doğrulanıyor…" : "Doğrula ve kaydet")
                            Spacer()
                            if isChecking { ProgressView() }
                        }
                    }
                    .disabled(trimmedKey.isEmpty || isChecking)
                } footer: {
                    Text("Doğrulama, anahtarınla tek token'lık küçük bir istek gönderir.")
                }
            }
            .navigationTitle("Kurulum")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func verifyAndSave() async {
        let candidate = trimmedKey
        guard !candidate.isEmpty, !isChecking else { return }
        isChecking = true
        errorMessage = nil
        canSaveAnyway = false
        defer { isChecking = false }

        do {
            try await app.verify(key: candidate)
            try app.saveAPIKey(candidate)
        } catch OllamaError.unauthorized {
            errorMessage = "Anahtar geçersiz (401). Kopyalarken eksik kalmış olabilir."
        } catch {
            errorMessage = "Doğrulanamadı: \(error.localizedDescription)"
            canSaveAnyway = true
        }
    }

    private func save() {
        do {
            try app.saveAPIKey(trimmedKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
