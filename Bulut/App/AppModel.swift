import Foundation
import Observation

/// App-wide state: the API key, the cloud model list and user defaults.
@MainActor
@Observable
final class AppModel {
    private enum DefaultsKey {
        static let defaultModel = "defaultModel"
        static let cachedModels = "cachedModelNames"
    }

    /// Models tried first when picking a default and when checking a new key.
    static let preferredModels = ["gpt-oss:120b", "gpt-oss:20b"]

    private(set) var apiKey: String?
    private(set) var modelNames: [String]
    private(set) var isLoadingModels = false
    private(set) var modelsError: String?
    private(set) var defaultModel: String

    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        apiKey = KeychainStore.readAPIKey()
        modelNames = defaults.stringArray(forKey: DefaultsKey.cachedModels) ?? []
        defaultModel = defaults.string(forKey: DefaultsKey.defaultModel) ?? ""
    }

    var hasAPIKey: Bool { apiKey != nil }

    var client: OllamaClient? {
        apiKey.map { OllamaClient(apiKey: $0) }
    }

    /// Last 4 characters of the key, for display in Settings.
    var maskedAPIKey: String {
        guard let apiKey, apiKey.count > 4 else { return "••••" }
        return "••••••••" + String(apiKey.suffix(4))
    }

    // MARK: Key management

    /// Checks the key with a real authenticated request. Throws `OllamaError.unauthorized` for a bad key.
    func verify(key: String) async throws {
        let client = OllamaClient(apiKey: key)
        let models = try await client.listModels()
        applyModels(models.map(\.name))
        let names = Set(modelNames)
        let probe = Self.preferredModels.first(where: names.contains) ?? modelNames.first ?? "gpt-oss:20b"
        try await client.verifyKey(using: probe)
    }

    func saveAPIKey(_ key: String) throws {
        try KeychainStore.saveAPIKey(key)
        apiKey = key
    }

    func removeAPIKey() {
        KeychainStore.deleteAPIKey()
        apiKey = nil
    }

    // MARK: Models

    func refreshModels() async {
        guard let client, !isLoadingModels else { return }
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await client.listModels()
            applyModels(models.map(\.name))
            modelsError = nil
        } catch {
            modelsError = error.localizedDescription
        }
    }

    func setDefaultModel(_ name: String) {
        defaultModel = name
        defaults.set(name, forKey: DefaultsKey.defaultModel)
    }

    private func applyModels(_ names: [String]) {
        modelNames = names
        defaults.set(names, forKey: DefaultsKey.cachedModels)
        if defaultModel.isEmpty {
            let available = Set(names)
            if let pick = Self.preferredModels.first(where: available.contains) ?? names.first {
                setDefaultModel(pick)
            }
        }
    }
}
