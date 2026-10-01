import SwiftData
import SwiftUI

/// Settings screen: add, edit and delete personas.
struct PersonaListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Persona.createdAt) private var personas: [Persona]

    @State private var isAdding = false

    var body: some View {
        List {
            ForEach(personas) { persona in
                NavigationLink {
                    PersonaEditorView(persona: persona)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(persona.name)
                        Text(persona.systemPrompt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    context.delete(personas[index])
                }
                try? context.save()
            }
        }
        .overlay {
            if personas.isEmpty {
                ContentUnavailableView("Persona yok", systemImage: "person.crop.rectangle.stack", description: Text("Sağ üstteki + ile ekle."))
            }
        }
        .navigationTitle("Personalar")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isAdding = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Persona ekle")
            }
        }
        .sheet(isPresented: $isAdding) {
            NavigationStack {
                PersonaEditorView(persona: nil)
            }
        }
    }
}

/// Edits an existing persona, or creates one when `persona` is nil.
struct PersonaEditorView: View {
    let persona: Persona?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var prompt = ""

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Ad") {
                TextField("Örn. Kardiyoloji asistanı", text: $name)
            }
            Section {
                TextEditor(text: $prompt)
                    .frame(minHeight: 220)
            } header: {
                Text("Sistem talimatı")
            } footer: {
                Text("Bu persona seçilen sohbette her isteğin başında modele gönderilir.")
            }
        }
        .navigationTitle(persona == nil ? "Yeni persona" : "Personayı düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet", action: save)
                    .disabled(!canSave)
            }
            if persona == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .onAppear {
            name = persona?.name ?? ""
            prompt = persona?.systemPrompt ?? ""
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let persona {
            persona.name = trimmedName
            persona.systemPrompt = trimmedPrompt
        } else {
            context.insert(Persona(name: trimmedName, systemPrompt: trimmedPrompt))
        }
        try? context.save()
        dismiss()
    }
}
