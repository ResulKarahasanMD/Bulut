# Bulut

Ollama Cloud modelleriyle konuşmak için kişisel iOS uygulaması (SwiftUI, iOS 17+).

## Kurulum
1. `Bulut.xcodeproj` dosyasını Xcode 16 veya üstüyle aç.
2. Bulut target → Signing & Capabilities → Team kısmından Developer hesabını seç. Gerekirse Bundle Identifier'ı değiştir.
3. iPhone'unu seçip ▶︎ ile çalıştır.
4. İlk açılışta ollama.com/settings/keys adresinden aldığın API anahtarını yapıştır. Anahtar tek token'lık bir istekle doğrulanır ve Anahtar Zinciri'nde saklanır.

## Özellikler (Faz 1)
- Model listesi canlı olarak `/api/tags` üzerinden gelir. Sohbet başına model seçilir, varsayılan model ayarlanabilir.
- Yanıtlar akış hâlinde gelir. Durdurma ve yeniden üretme var.
- Düşünen modellerde düşünme bölümü katlanabilir şekilde gösterilir.
- Markdown desteklenir: başlık, liste, tablo, alıntı ve kopyalanabilir kod blokları.
- Sohbet başına sistem talimatı ve varsayılan sistem talimatı tanımlanabilir.
- Sohbetler SwiftData'da tutulur. Arama, silme ve paylaşma yapılabilir.
