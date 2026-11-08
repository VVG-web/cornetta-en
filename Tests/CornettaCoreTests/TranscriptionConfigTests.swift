import Foundation
import Testing
@testable import CornettaCore

struct TranscriptionConfigTests {
    @Test func defaultEndpointIsLocalWhisper() {
        let config = TranscriptionConfig()
        #expect(config.endpointURL?.absoluteString == "http://127.0.0.1:8080/v1/audio/transcriptions")
        #expect(config.isConfigured)
    }

    @Test func appendsTheOpenAIPathToBaseURLs() {
        #expect(TranscriptionConfig(baseURL: "https://api.example.com/v1").endpointURL?.absoluteString
                == "https://api.example.com/v1/audio/transcriptions")
        #expect(TranscriptionConfig(baseURL: "https://api.example.com/v1/").endpointURL?.absoluteString
                == "https://api.example.com/v1/audio/transcriptions")
        #expect(TranscriptionConfig(baseURL: "https://api.example.com/v1/audio/transcriptions")
            .endpointURL?.absoluteString == "https://api.example.com/v1/audio/transcriptions")
        #expect(TranscriptionConfig(baseURL: "http://localhost:9000").endpointURL?.absoluteString
                == "http://localhost:9000/audio/transcriptions")
        #expect(TranscriptionConfig(baseURL: "http://[::1]:8080/v1").endpointURL?.absoluteString
                == "http://[::1]:8080/v1/audio/transcriptions")
    }

    @Test func rejectsInvalidBaseURLs() {
        #expect(!TranscriptionConfig(baseURL: "").isConfigured)
        #expect(!TranscriptionConfig(baseURL: "ftp://api.example.com/v1").isConfigured)
        #expect(!TranscriptionConfig(baseURL: "https://").isConfigured)
        #expect(!TranscriptionConfig(baseURL: "https://bad host/v1").isConfigured)
        #expect(!TranscriptionConfig(baseURL: "https://api.example.com/v1?token=x").isConfigured)
        #expect(!TranscriptionConfig(baseURL: "https://user@api.example.com/v1").isConfigured)
        #expect(!TranscriptionConfig(baseURL: "https://api.example.com:0/v1").isConfigured)
        #expect(!TranscriptionConfig(baseURL: "https://api.example.com:65536/v1").isConfigured)
    }

    @Test func modelsURLUsesTheBasePathOnlyOnce() {
        #expect(TranscriptionConfig(baseURL: "https://api.example.com/v1").modelsURL?.absoluteString
                == "https://api.example.com/v1/models")
        #expect(TranscriptionConfig(baseURL: "https://api.example.com/v1/audio/transcriptions")
            .modelsURL?.absoluteString == "https://api.example.com/v1/models")
        #expect(TranscriptionConfig(baseURL: "http://127.0.0.1:8080").modelsURL?.absoluteString
                == "http://127.0.0.1:8080/models")
    }

    @Test func parsesOpenAIModelLists() throws {
        let data = Data(#"{"data":[{"id":"faster-whisper-large-v3"},{"id":"whisper-1"}]}"#.utf8)
        #expect(TranscriptionModelList.ids(from: data) == ["faster-whisper-large-v3", "whisper-1"])
        let alt = Data(#"{"models":[{"id":"igpu"}]}"#.utf8)
        #expect(TranscriptionModelList.ids(from: alt) == ["igpu"])
        #expect(TranscriptionModelList.ids(from: Data("not json".utf8)) == nil)
    }

    @Test func storedConfigurationRoundTrips() throws {
        let suite = "TranscriptionConfigTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("https://api.example.com/v1", forKey: TranscriptionPreferences.baseURLKey)
        defaults.set("faster-whisper-large-v3", forKey: TranscriptionPreferences.modelKey)
        defaults.set("ru", forKey: TranscriptionPreferences.languageKey)
        let config = TranscriptionConfig.stored(in: defaults)
        #expect(config.endpointURL?.absoluteString
                == "https://api.example.com/v1/audio/transcriptions")
        #expect(config.effectiveModel == "faster-whisper-large-v3")
        #expect(config.effectiveLanguage == "ru")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func migratesTheSeparateEndpointFields() throws {
        let suite = "TranscriptionMigrationFields"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("https", forKey: TranscriptionPreferences.schemeKey)
        defaults.set("whisper.lan", forKey: TranscriptionPreferences.hostKey)
        defaults.set("8443", forKey: TranscriptionPreferences.portKey)
        defaults.set("/v1/audio/transcriptions", forKey: TranscriptionPreferences.pathKey)
        let config = TranscriptionConfig.stored(in: defaults)
        #expect(config.baseURL == "https://whisper.lan:8443/v1")
        #expect(config.endpointURL?.absoluteString
                == "https://whisper.lan:8443/v1/audio/transcriptions")
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func automaticTranscriptionRequiresAFreshOptIn() throws {
        let suite = "TranscriptionMigrationTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set(true, forKey: TranscriptionPreferences.autoTranscribeKey)
        TranscriptionPreferences.migrateIfNeeded(in: defaults)
        #expect(!defaults.bool(forKey: TranscriptionPreferences.autoTranscribeKey))
        #expect(defaults.bool(forKey: TranscriptionPreferences.migrationKey))
        defaults.set(true, forKey: TranscriptionPreferences.autoTranscribeKey)
        TranscriptionPreferences.migrateIfNeeded(in: defaults)
        #expect(defaults.bool(forKey: TranscriptionPreferences.autoTranscribeKey))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func authorizationHeaderIsOptionalAndBearerOnly() {
        #expect(TranscriptionAuthorization.header(for: "") == nil)
        #expect(TranscriptionAuthorization.header(for: "   ") == nil)
        #expect(TranscriptionAuthorization.header(for: "sk-test") == "Bearer sk-test")
    }

}
