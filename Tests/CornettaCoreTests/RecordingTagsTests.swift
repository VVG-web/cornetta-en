import AVFoundation
import Foundation
import Testing
@testable import CornettaCore

struct RecordingTagsTests {
    private func makeM4A(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("CornettaTags-\(UUID().uuidString).m4a")
        try writeAudio(to: url)
        return url
    }

    /// Cornetta writes AAC through AVAudioFile into a `.m4a.parziale` path,
    /// which creates a CAF container, then renames it to `.m4a`.
    private func makeCAFNamedM4A(in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("CornettaTags-\(UUID().uuidString).m4a")
        let partial = url.appendingPathExtension("parziale")
        try writeAudio(to: partial)
        try FileManager.default.moveItem(at: partial, to: url)
        return url
    }

    private func writeAudio(to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 64_000,
        ]
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: 22_050) else {
                throw RecordingTagError.emptyOutput
            }
            buffer.frameLength = 22_050
            if let data = buffer.floatChannelData {
                for index in 0..<Int(buffer.frameLength) {
                    data[0][index] = sin(Float(index) * 2 * .pi * 440 / 22_050) * 0.1
                }
            }
            try file.write(from: buffer)
        }
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CornettaTagTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func normalizesAndSummarizesFiveTags() {
        let tags = RecordingTags(title: "  Planning  ", artist: " Vadim ",
                                 album: " Project X ", date: " 2026-11-09 ",
                                 comment: " Release topic ")
        #expect(tags.normalized
                == RecordingTags(title: "Planning", artist: "Vadim",
                                 album: "Project X", date: "2026-11-09",
                                 comment: "Release topic"))
        #expect(tags.normalized.summary == "Vadim · Project X · Release topic")
        #expect(RecordingTags.empty.isEmpty)
        #expect(!tags.isEmpty)
    }

    @Test func writesAndReadsFiveTagsFromM4A() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeM4A(in: directory)
        let tags = RecordingTags(title: "Planning call", artist: "Vadim",
                                 album: "Project X", date: "2026-11-09",
                                 comment: "Release planning")
        try await RecordingTagStore.write(tags, to: url)
        #expect(await RecordingTagStore.read(from: url) == tags)
        #expect(try AVAudioFile(forReading: url).length > 0)
    }

    @Test func writesTagsToCAFStoredWithM4AExtension() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeCAFNamedM4A(in: directory)
        #expect(Data((try? Data(contentsOf: url))?.prefix(4) ?? Data()) == Data("caff".utf8))
        let tags = RecordingTags(title: "CAF call", artist: "Vadim",
                                 album: "Project X", date: "2026-11-09",
                                 comment: "Recorded by Cornetta")
        try await RecordingTagStore.write(tags, to: url)
        #expect(await RecordingTagStore.read(from: url) == tags)
        #expect(try AVAudioFile(forReading: url).length > 0)
        #expect(Data((try? Data(contentsOf: url))?.prefix(4) ?? Data()) != Data("caff".utf8))
    }

    @Test func clearingTagsKeepsAudioReadable() async throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeM4A(in: directory)
        try await RecordingTagStore.write(
            RecordingTags(title: "Temporary", comment: "Remove me"), to: url)
        try await RecordingTagStore.write(.empty, to: url)
        #expect(await RecordingTagStore.read(from: url) == .empty)
        #expect(try AVAudioFile(forReading: url).length > 0)
    }

    @Test func removesInterruptedTagTemps() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let temp = directory.appendingPathComponent(".cornetta-tags-test.m4a")
        try Data("partial".utf8).write(to: temp)
        RecordingTagStore.removeTemporaryFiles(in: directory)
        #expect(!FileManager.default.fileExists(atPath: temp.path))
    }
}
