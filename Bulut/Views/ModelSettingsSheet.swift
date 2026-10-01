import SwiftUI

/// Per-conversation request settings. Every value can fall back to the model's own default.
struct ModelSettingsSheet: View {
    @Bindable var conversation: Conversation
    let details: ModelDetails?
    @Environment(\.dismiss) private var dismiss

    private static let defaultTemperature = 0.8
    private static let contextSteps = [4_096, 8_192, 16_384, 32_768, 65_536, 131_072, 262_144, 524_288, 1_048_576]

    var body: some View {
        NavigationStack {
            Form {
                if let details, details.hasThinkControl {
                    Section {
                        Picker("Düşünme", selection: $conversation.think) {
                            Text(defaultThinkLabel(details)).tag(ThinkSetting?.none)
                            ForEach(details.thinkOptions, id: \.self) { option in
                                Text(option.label).tag(ThinkSetting?.some(option))
                            }
                        }
                    } header: {
                        Text("Düşünme")
                    } footer: {
                        Text("Daha uzun düşünme yanıtı geciktirir, zor sorularda daha iyi sonuç verebilir.")
                    }
                }

                Section {
                    Toggle("Özel sıcaklık", isOn: customTemperature)
                    if conversation.temperature != nil {
                        Slider(value: temperature, in: 0...2, step: 0.1) {
                            Text("Sıcaklık")
                        } minimumValueLabel: {
                            Text("0")
                        } maximumValueLabel: {
                            Text("2")
                        }
                        LabeledContent("Değer", value: temperature.wrappedValue.formatted(.number.precision(.fractionLength(1))))
                    }
                } header: {
                    Text("Sıcaklık")
                } footer: {
                    Text("Düşük değer daha tutarlı, yüksek değer daha yaratıcı yanıt verir. Kapalıyken modelin varsayılanı kullanılır.")
                }

                Section {
                    Picker("Bağlam", selection: $conversation.contextLength) {
                        Text("Model varsayılanı").tag(Int?.none)
                        ForEach(contextChoices, id: \.self) { value in
                            Text(Self.tokenLabel(value)).tag(Int?.some(value))
                        }
                    }
                } header: {
                    Text("Bağlam uzunluğu")
                } footer: {
                    if let limit = details?.contextLength {
                        Text("Bu model en fazla \(Self.tokenLabel(limit)) token destekliyor.")
                    }
                }

                if details == nil {
                    Section {
                        Text("Model bilgisi henüz alınamadı; düşünme seçenekleri bağlantı kurulunca görünür.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Model ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sıfırla") {
                        conversation.think = nil
                        conversation.temperature = nil
                        conversation.contextLength = nil
                    }
                    .disabled(conversation.think == nil && conversation.temperature == nil && conversation.contextLength == nil)
                }
            }
        }
    }

    private var contextChoices: [Int] {
        let limit = details?.contextLength ?? 131_072
        return Self.contextSteps.filter { $0 <= limit }
    }

    private func defaultThinkLabel(_ details: ModelDetails) -> String {
        guard let value = details.defaultThink else { return "Model varsayılanı" }
        return "Model varsayılanı (\(value.label))"
    }

    private var customTemperature: Binding<Bool> {
        Binding(
            get: { conversation.temperature != nil },
            set: { conversation.temperature = $0 ? Self.defaultTemperature : nil }
        )
    }

    private var temperature: Binding<Double> {
        Binding(
            get: { conversation.temperature ?? Self.defaultTemperature },
            set: { conversation.temperature = ($0 * 10).rounded() / 10 }
        )
    }

    static func tokenLabel(_ value: Int) -> String {
        value >= 1_048_576 ? "\(value / 1_048_576)M" : "\(value / 1_024)K"
    }
}
