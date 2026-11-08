import Foundation
import Testing
@testable import CornettaCore

struct TranscriptionProvidersTests {
    private func defaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func migratesTheOldSingleProviderAndKeepsTheLegacyKeyAccount() throws {
        let store = try defaults("TranscriptionProvidersMigration")
        store.set("https://api.example.com/v1", forKey: TranscriptionPreferences.baseURLKey)
        store.set("faster-whisper-large-v3", forKey: TranscriptionPreferences.modelKey)
        store.set("ru", forKey: TranscriptionPreferences.languageKey)
        let provider = TranscriptionProviderCatalog.selected(in: store)
        #expect(provider.isHTTP)
        #expect(provider.baseURL == "https://api.example.com/v1")
        #expect(provider.model == "faster-whisper-large-v3")
        #expect(provider.language == "ru")
        #expect(provider.usesLegacyKey)
        #expect(provider.credentialAccount == TranscriptionCredential.legacyAccount)
        #expect(TranscriptionProviderCatalog.custom(in: store).count == 1)
        #expect(store.string(forKey: TranscriptionPreferences.baseURLKey) == nil)
        store.removePersistentDomain(forName: "TranscriptionProvidersMigration")
    }

    @Test func freshInstallGetsALocalHTTPProviderAndAppleOption() throws {
        let store = try defaults("TranscriptionProvidersFresh")
        let all = TranscriptionProviderCatalog.all(in: store)
        #expect(all.first?.kind == .apple)
        #expect(all.count == 2)
        #expect(all[1].kind == .http)
        #expect(all[1].baseURL == TranscriptionPreferences.defaultBaseURL)
        #expect(TranscriptionProviderCatalog.selected(in: store).id == all[1].id)
        store.removePersistentDomain(forName: "TranscriptionProvidersFresh")
    }

    @Test func savesSelectsAndDeletesMultipleHTTPProviders() throws {
        let store = try defaults("TranscriptionProvidersMultiple")
        let first = TranscriptionProvider(name: "Local", kind: .http,
                                          baseURL: "http://127.0.0.1:8080/v1",
                                          model: "whisper-1", language: "it")
        let second = TranscriptionProvider(name: "Paid", kind: .http,
                                           baseURL: "https://api.example.com/v1",
                                           model: "faster-whisper-large-v3", language: "ru")
        try TranscriptionProviderCatalog.save(first, apiKey: "", select: true, in: store)
        try TranscriptionProviderCatalog.save(second, apiKey: "", select: true, in: store)
        #expect(TranscriptionProviderCatalog.custom(in: store).count == 3)
        #expect(TranscriptionProviderCatalog.selected(in: store).id == second.id)
        TranscriptionProviderCatalog.select(first.id, in: store)
        #expect(TranscriptionProviderCatalog.selected(in: store).id == first.id)
        TranscriptionProviderCatalog.delete(first, in: store)
        #expect(TranscriptionProviderCatalog.custom(in: store).count == 2)
        #expect(TranscriptionProviderCatalog.selected(in: store).id != first.id)
        store.removePersistentDomain(forName: "TranscriptionProvidersMultiple")
    }

    @Test func providerCodableRoundTrip() throws {
        let provider = TranscriptionProvider(name: "Paid", kind: .http,
                                             baseURL: "https://api.example.com/v1",
                                             model: "large-v3", language: "ru",
                                             usesLegacyKey: false)
        let decoded = try JSONDecoder().decode(TranscriptionProvider.self,
                                               from: JSONEncoder().encode(provider))
        #expect(decoded == provider)
        #expect(decoded.credentialAccount == TranscriptionCredential.account(for: provider.id))
    }
}
