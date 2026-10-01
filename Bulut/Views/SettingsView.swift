import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(ChatEngine.self) private var engine

    @AppStorage("defaultSystemPrompt") private var defaultSystemPrompt = ""

    @State private var isConfirmingKeyRemoval = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Hesap") {
                    LabeledContent("API anahtarı", value: app.maskedAPIKey)
                        .font(.body.monospaced())
                    Link(destination: URL(string: "https://ollama.com/settings")!) {
                        Label("Kullanım ve plan (ollama.com)", systemImage: "chart.bar")
                    }
                    Button("Anahtarı kaldır / değiştir", role: .destructive) {
                        isConfirmingKeyRemoval = true
                    }
                }

                Section {
                    if app.modelNames.isEmpty {
                        Text(app.modelsError ?? "Model listesi henüz yüklenmedi.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Varsayılan model", selection: defaultModelBinding) {
                            ForEach(app.modelNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                    Button {
                        Task { await app.refreshModels() }
                    } label: {
                        HStack {
                            Label("Model listesini yenile", systemImage: "arrow.clockwise")
                            Spacer()
                            if app.isLoadingModels { ProgressView() }
                        }
                    }
                } header: {
                    Text("Modeller")
                } footer: {
                    Text("\(app.modelNames.count) bulut modeli. Yeni sohbetler varsayılan modelle açılır; sohbet ekranının başlığından değiştirebilirsin.")
                }

                Section {
                    TextEditor(text: $defaultSystemPrompt)
                        .frame(minHeight: 120)
                } header: {
                    Text("Varsayılan sistem talimatı")
                } footer: {
                    Text("Yeni açılan her sohbete kopyalanır. Örn: “Türkçe yanıt ver, kısa ve net ol.”")
                }

                Section {
                    Button("Tüm sohbetleri sil", role: .destructive) {
                        isConfirmingDeleteAll = true
                    }
                }

                Section {
                    LabeledContent("Sürüm", value: Self.versionString)
                    LabeledContent("Sunucu", value: "ollama.com/api")
                }
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .confirmationDialog("API anahtarı kaldırılsın mı?", isPresented: $isConfirmingKeyRemoval, titleVisibility: .visible) {
                Button("Kaldır", role: .destructive) {
                    engine.stopAll()
                    dismiss()
                    app.removeAPIKey()
                }
            } message: {
                Text("Sohbetlerin silinmez. Yeni bir anahtar girmen istenecek.")
            }
            .confirmationDialog("Tüm sohbetler silinsin mi?", isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
                Button("Hepsini sil", role: .destructive, action: deleteAllConversations)
            } message: {
                Text("Bu işlem geri alınamaz.")
            }
        }
    }

    private var defaultModelBinding: Binding<String> {
        Binding(
            get: { app.defaultModel },
            set: { app.setDefaultModel($0) }
        )
    }

    private func deleteAllConversations() {
        engine.stopAll()
        let all = (try? context.fetch(FetchDescriptor<Conversation>())) ?? []
        for conversation in all {
            context.delete(conversation)
        }
        try? context.save()
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
