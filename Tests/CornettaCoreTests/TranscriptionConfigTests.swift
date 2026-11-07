import Foundation
import Testing
@testable import CornettaCore

struct TranscriptionConfigTests {
    @Test func defaultEndpointIsLocalWhisper() {
        let config = TranscriptionConfig()
        #expect(config.endpointURL?.absoluteString == "http://127.0.0.1:8080/v1/audio/transcriptions")
        #expect(config.isConfigured)
    }

    @Test func supportsIPv4HostnamesAndIPv6() {
        #expect(TranscriptionConfig(host: "localhost", port: "9000").endpointURL?.absoluteString
                == "http://localhost:9000/v1/audio/transcriptions")
        #expect(TranscriptionConfig(host: "192.168.1.20", port: "8080").endpointURL?.absoluteString
                == "http://192.168.1.20:8080/v1/audio/transcriptions")
        #expect(TranscriptionConfig(host: "::1", port: "8080").endpointURL?.absoluteString
                == "http://[::1]:8080/v1/audio/transcriptions")
        #expect(TranscriptionConfig(host: "[::1]", port: "8080").endpointURL?.absoluteString
                == "http://[::1]:8080/v1/audio/transcriptions")
    }

    @Test func supportsHttpsAndNormalizesPath() {
        let config = TranscriptionConfig(scheme: "HTTPS", host: "whisper.local", port: "443",
                                         path: "v1/audio/transcriptions")
        #expect(config.endpointURL?.absoluteString == "https://whisper.local:443/v1/audio/transcriptions")
        #expect(TranscriptionConfig(path: "").endpointURL?.path == "/v1/audio/transcriptions")
    }

    @Test func rejectsInvalidConfiguration() {
        #expect(!TranscriptionConfig(scheme: "ftp").isConfigured)
        #expect(!TranscriptionConfig(host: "").isConfigured)
        #expect(!TranscriptionConfig(host: "bad host").isConfigured)
        #expect(!TranscriptionConfig(host: "example.com/extra").isConfigured)
        #expect(!TranscriptionConfig(host: "user@example.com").isConfigured)
        #expect(!TranscriptionConfig(path: "/v1/audio?token=secret").isConfigured)
        #expect(!TranscriptionConfig(port: "0").isConfigured)
        #expect(!TranscriptionConfig(port: "65536").isConfigured)
        #expect(!TranscriptionConfig(port: "abc").isConfigured)
    }

    @Test func storedConfigurationRoundTrips() throws {
        let suite = "TranscriptionConfigTests"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defaults.set("https", forKey: TranscriptionPreferences.schemeKey)
        defaults.set("whisper.lan", forKey: TranscriptionPreferences.hostKey)
        defaults.set("8443", forKey: TranscriptionPreferences.portKey)
        defaults.set("/custom/transcribe", forKey: TranscriptionPreferences.pathKey)
        defaults.set("large-v3", forKey: TranscriptionPreferences.modelKey)
        defaults.set("it", forKey: TranscriptionPreferences.languageKey)
        let config = TranscriptionConfig.stored(in: defaults)
        #expect(config.endpointURL?.absoluteString == "https://whisper.lan:8443/custom/transcribe")
        #expect(config.effectiveModel == "large-v3")
        #expect(config.effectiveLanguage == "it")
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
}
