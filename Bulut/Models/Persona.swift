import Foundation
import SwiftData

/// A named system prompt that can be applied to a conversation.
@Model
final class Persona {
    var id: UUID = UUID()
    var name: String = ""
    var systemPrompt: String = ""
    var createdAt: Date = Date()

    init(name: String, systemPrompt: String) {
        self.id = UUID()
        self.name = name
        self.systemPrompt = systemPrompt
        self.createdAt = Date()
    }
}

enum PersonaSeeder {
    private static let seededKey = "didSeedPersonas"

    static let builtIns: [(name: String, prompt: String)] = [
        (
            "TUS soru çözücü",
            """
            Sen bir TUS (Tıpta Uzmanlık Sınavı) hazırlık asistanısın. Verilen soruyu çöz: önce doğru şıkkı yaz, \
            sonra her şıkkın neden doğru ya da yanlış olduğunu kısaca açıkla. Konunun temel bilgisini ve akılda \
            kalıcı bir ipucunu ekle. Emin olmadığın bilgiyi uydurma, belirsizliği açıkça söyle. Türkçe yanıt ver.
            """
        ),
        (
            "Swift reviewer",
            """
            Kıdemli bir Swift/SwiftUI kod inceleyicisisin. Kodu doğruluk, Swift 6 concurrency güvenliği, bellek ve \
            performans, API kullanımı ve okunabilirlik açısından incele. Bulguları önem sırasına göre grupla, ilgili \
            satırları alıntıla ve en küçük düzeltmeyi kod olarak öner. Var olmayan API uydurma; emin değilsen söyle. \
            Türkçe yanıt ver, kod ve tanımlayıcılar İngilizce kalsın.
            """
        ),
        (
            "Kısa ve net",
            "Kısa ve net yanıt ver. Giriş ve özet cümlesi yazma. Gerekirse madde işareti kullan. Türkçe yanıt ver."
        ),
        (
            "Çevirmen TR ⇄ EN",
            """
            Çevirmensin. Metin Türkçeyse İngilizceye, değilse Türkçeye çevir. Yalnızca çeviriyi yaz; anlamı, tonu \
            ve Markdown biçimini koru. Tıbbi terimleri yerleşik karşılıklarıyla çevir.
            """
        ),
    ]

    /// Adds the built-in personas on first launch only, so deleting one keeps it deleted.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: seededKey) else { return }
        for (offset, persona) in builtIns.enumerated() {
            let model = Persona(name: persona.name, systemPrompt: persona.prompt)
            // Keep the built-in order when sorting by creation date.
            model.createdAt = Date().addingTimeInterval(Double(offset) * 0.001)
            context.insert(model)
        }
        try? context.save()
        defaults.set(true, forKey: seededKey)
    }
}
