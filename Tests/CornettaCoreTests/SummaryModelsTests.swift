import Foundation
import Testing
@testable import CornettaCore

struct SummaryModelsTests {
    private func defaults(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func chatCompletionsAndModelsURLs() {
        let config = SummaryConfig(baseURL: "https://api.example.com/v1", model: "chat-1")
        #expect(config.chatCompletionsURL?.absoluteString
                == "https://api.example.com/v1/chat/completions")
        #expect(config.modelsURL?.absoluteString == "https://api.example.com/v1/models")
        let complete = SummaryConfig(baseURL: "https://api.example.com/v1/chat/completions",
                                     model: "chat-1")
        #expect(complete.chatCompletionsURL?.absoluteString
                == "https://api.example.com/v1/chat/completions")
        #expect(!SummaryConfig(baseURL: "ftp://api.example.com/v1").isConfigured)
    }

    @Test func providersDefaultToListAndSurviveDeletion() throws {
        let store = try defaults("SummaryProvidersTests")
        let first = SummaryProvider(name: "First", baseURL: "http://127.0.0.1:8080/v1",
                                    model: "chat-1")
        let second = SummaryProvider(name: "Second", baseURL: "https://api.example.com/v1",
                                     model: "chat-2")
        try SummaryProviderCatalog.save(first, apiKey: nil, makeDefault: true, in: store)
        try SummaryProviderCatalog.save(second, apiKey: nil, makeDefault: false, in: store)
        #expect(SummaryProviderCatalog.all(in: store).count == 2)
        #expect(SummaryProviderCatalog.defaultProvider(in: store)?.id == first.id)
        SummaryProviderCatalog.delete(first, in: store)
        #expect(SummaryProviderCatalog.defaultProvider(in: store)?.id == second.id)
        store.removePersistentDomain(forName: "SummaryProvidersTests")
    }

    @Test func promptCatalogKeepsExactlyOneDefault() throws {
        let store = try defaults("SummaryPromptsTests")
        let initial = SummaryPromptCatalog.all(in: store)
        #expect(initial.count == 1)
        #expect(initial[0].isDefault)
        var second = SummaryPrompt(name: "Second", body: "Summarize {{transcript}}",
                                   isDefault: true)
        SummaryPromptCatalog.save(second, in: store)
        let prompts = SummaryPromptCatalog.all(in: store)
        #expect(prompts.count == 2)
        #expect(prompts.filter(\.isDefault).count == 1)
        #expect(prompts.first(where: \.isDefault)?.id == second.id)
        SummaryPromptCatalog.delete(second, in: store)
        second = SummaryPromptCatalog.all(in: store)[0]
        #expect(second.isDefault)
        store.removePersistentDomain(forName: "SummaryPromptsTests")
    }

    @Test func promptRendersVariablesAndAppendsTranscript() {
        let start = Calendar.current.date(from: DateComponents(year: 1970, month: 1, day: 1,
                                                               hour: 0, minute: 0)) ?? .distantPast
        let info = MeetingInfo(topic: "Planning", participants: "Alice, Bob",
                               startDate: start, notes: "Bring numbers")
        let prompt = SummaryPrompt(name: "Test",
                                   body: "{{topic}}|{{participants}}|{{date}}|{{time}}|{{notes}}|{{language}}")
        let rendered = prompt.rendered(meeting: info, transcript: "You: Hello", language: .english)
        #expect(rendered.contains("Planning|Alice, Bob|1970-01-01|00:00|Bring numbers|English"))
        #expect(rendered.contains("You: Hello"))
        #expect(!rendered.contains("{{"))
    }

    @Test func meetingAndSummaryStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SummaryStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let recording = root.appendingPathComponent("Chiamata 2026-11-09 10.00.m4a")
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let info = MeetingInfo(topic: "Planning", participants: "Alice",
                               startDate: Date(timeIntervalSince1970: 1_700_000_000),
                               notes: "Agenda")
        try SummaryStore.saveMeeting(info, for: recording, support: support)
        #expect(SummaryStore.loadMeeting(for: recording, support: support) == info)

        let record = SummaryRecord(recording: recording.lastPathComponent, title: "Planning",
                                   text: "Summary text", providerID: UUID(),
                                   providerName: "Provider", model: "model-1",
                                   promptID: UUID(), promptName: "Prompt", language: "en")
        try SummaryStore.saveSummary(record, for: recording, support: support,
                                     markdown: "# Planning\n\nSummary text\n")
        let loaded = SummaryStore.loadSummary(for: recording, support: support)
        #expect(loaded?.text == record.text)
        #expect(loaded?.model == record.model)
        #expect(loaded?.promptName == record.promptName)
        #expect(abs((loaded?.createdAt ?? .distantPast).timeIntervalSince(record.createdAt)) < 1)
        let markdown = try String(contentsOf: SummaryStore.summaryMarkdownURL(for: recording,
                                                                              support: support),
                                  encoding: .utf8)
        #expect(markdown.contains("Summary text"))
        SummaryStore.delete(for: recording, support: support)
        #expect(SummaryStore.loadMeeting(for: recording, support: support) == nil)
        #expect(SummaryStore.loadSummary(for: recording, support: support) == nil)
    }
}
