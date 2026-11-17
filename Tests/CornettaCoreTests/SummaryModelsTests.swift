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
        #expect(complete.modelsURL?.absoluteString == "https://api.example.com/v1/models")
        let hostOnly = SummaryConfig(baseURL: "http://127.0.0.1:8081", model: "chat-1")
        #expect(hostOnly.chatCompletionsURL?.absoluteString
                == "http://127.0.0.1:8081/v1/chat/completions")
        #expect(hostOnly.modelsURL?.absoluteString == "http://127.0.0.1:8081/v1/models")
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
        let tags = RecordingTags(title: "Weekly planning", artist: "Alice, Bob",
                                 album: "Operations", date: "2026-11-17",
                                 comment: "Budget review")
        let prompt = SummaryPrompt(name: "Test",
                                   body: "{{topic}}|{{participants}}|{{date}}|{{time}}|{{notes}}|{{language}}")
        let rendered = prompt.rendered(meeting: info, tags: tags,
                                       transcript: "You: Hello", language: .english)
        #expect(rendered.contains("Planning|Alice, Bob|1970-01-01|00:00|Bring numbers|English"))
        #expect(rendered.contains("You: Hello"))
        #expect(!rendered.contains("{{"))
    }

    @Test func promptIncludesEveryTagAndMeetingFieldBeforeTranscript() throws {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 17,
                                                               hour: 9, minute: 30)) ?? .distantPast
        let info = MeetingInfo(topic: "Quarterly planning", participants: "Alice, Bob",
                               startDate: start, notes: "Review the budget\nConfirm owners")
        let tags = RecordingTags(title: "Quarterly planning", artist: "Alice and Bob",
                                 album: "Operations", date: "2026-11-17",
                                 comment: "Recorded in the small room")
        let prompt = SummaryPrompt(name: "Custom",
                                   body: "Summarize this meeting.\nTranscript:\n{{transcript}}\nKeep it short.")
        let rendered = prompt.rendered(meeting: info, tags: tags,
                                       transcript: "You: Hello", language: .english)

        let expected = [
            "Meeting information:",
            "Topic: Quarterly planning",
            "Participants: Alice, Bob",
            "Start date: 2026-11-17",
            "Start time: 09:30",
            "Start date and time (ISO 8601): ",
            "Notes: Review the budget\nConfirm owners",
            "Audio tags:",
            "Title: Quarterly planning",
            "Artist: Alice and Bob",
            "Album: Operations",
            "Date: 2026-11-17",
            "Comment: Recorded in the small room",
            "Transcript:",
            "You: Hello",
        ]
        for line in expected {
            #expect(rendered.contains(line), "Missing prompt line: \(line)")
        }

        let context = try #require(rendered.range(of: "Meeting information:"))
        let audioTags = try #require(rendered.range(of: "Audio tags:"))
        let instructions = try #require(rendered.range(of: "Summarize this meeting."))
        let transcript = try #require(rendered.range(of: "Transcript:"))
        let firstLine = try #require(rendered.range(of: "You: Hello"))
        #expect(context.lowerBound < audioTags.lowerBound)
        #expect(audioTags.lowerBound < instructions.lowerBound)
        #expect(instructions.lowerBound < transcript.lowerBound)
        #expect(transcript.lowerBound < firstLine.lowerBound)
        #expect(!rendered.contains("{{"))
    }

    @Test func promptWithoutTranscriptPlaceholderStillGetsContextFirst() throws {
        let info = MeetingInfo(topic: "Planning", participants: "Alice",
                               startDate: Date(timeIntervalSince1970: 1_700_000_000),
                               notes: "")
        let tags = RecordingTags(title: "Planning", artist: "Alice", album: "",
                                 date: "", comment: "")
        let prompt = SummaryPrompt(name: "No transcript variable",
                                   body: "Summarize the discussion.")
        let rendered = prompt.rendered(meeting: info, tags: tags,
                                       transcript: "You: Only this line", language: .italian)

        let context = try #require(rendered.range(of: "Meeting information:"))
        let transcript = try #require(rendered.range(of: "You: Only this line"))
        #expect(context.lowerBound < transcript.lowerBound)
        #expect(rendered.contains("Album: (not provided)"))
        #expect(rendered.contains("Date: (not provided)"))
        #expect(rendered.contains("Comment: (not provided)"))
        #expect(rendered.contains("Notes: (not provided)"))
        #expect(rendered.contains("Transcript:"))
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
