import AVFoundation
import Foundation

/// The five standard audio tags Cornetta can edit on a recording.
///
/// The values are written into the `.m4a` as iTunes/MP4 metadata, so they are also
/// visible in Finder and in other audio players. Text is trimmed before saving.
public struct RecordingTags: Codable, Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    public var date: String
    public var comment: String

    public init(title: String = "", artist: String = "", album: String = "",
                date: String = "", comment: String = "") {
        self.title = title
        self.artist = artist
        self.album = album
        self.date = date
        self.comment = comment
    }

    public static let empty = RecordingTags()

    public var isEmpty: Bool {
        [title, artist, album, date, comment].allSatisfy {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    public var normalized: RecordingTags {
        RecordingTags(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                      artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
                      album: album.trimmingCharacters(in: .whitespacesAndNewlines),
                      date: date.trimmingCharacters(in: .whitespacesAndNewlines),
                      comment: comment.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A short line for the recording header, when at least one descriptive tag is set.
    public var summary: String {
        [artist, album, comment].map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

public enum RecordingTagError: LocalizedError {
    case cannotExport
    case emptyOutput
    case replaceFailed

    public var errorDescription: String? {
        switch self {
        case .cannotExport:
            return "Il file audio non può essere esportato con i nuovi tag."
        case .emptyOutput:
            return "L'esportazione dei tag ha prodotto un file vuoto."
        case .replaceFailed:
            return "Non riesco a sostituire il file audio con quello aggiornato."
        }
    }
}

/// Reads and writes the five tags through AVFoundation. The original file is only
/// replaced after a successful passthrough export, so a failed save leaves it intact.
public enum RecordingTagStore {
    private static let managedIdentifiers: Set<String> = [
        AVMetadataIdentifier.iTunesMetadataSongName.rawValue,
        AVMetadataIdentifier.iTunesMetadataArtist.rawValue,
        AVMetadataIdentifier.iTunesMetadataAlbum.rawValue,
        AVMetadataIdentifier.iTunesMetadataReleaseDate.rawValue,
        AVMetadataIdentifier.iTunesMetadataUserComment.rawValue,
        AVMetadataIdentifier.commonIdentifierTitle.rawValue,
        AVMetadataIdentifier.commonIdentifierArtist.rawValue,
        AVMetadataIdentifier.commonIdentifierAuthor.rawValue,
        AVMetadataIdentifier.commonIdentifierCreator.rawValue,
        AVMetadataIdentifier.commonIdentifierAlbumName.rawValue,
        AVMetadataIdentifier.commonIdentifierCreationDate.rawValue,
        AVMetadataIdentifier.commonIdentifierDescription.rawValue,
    ]

    public static func read(from url: URL) async -> RecordingTags {
        (try? await load(from: url)) ?? .empty
    }

    public static func load(from url: URL) async throws -> RecordingTags {
        let asset = AVURLAsset(url: url)
        var result = RecordingTags()
        async let metadata = asset.load(.metadata)
        async let common = asset.load(.commonMetadata)
        let groups = [try await metadata, try await common]
        for item in groups.joined() {
            guard let identifier = item.identifier,
                  let value = try? await item.load(.value) else { continue }
            let text = text(from: value)
            guard !text.isEmpty else { continue }
            switch identifier {
            case .iTunesMetadataSongName, .commonIdentifierTitle:
                if result.title.isEmpty { result.title = text }
            case .iTunesMetadataArtist, .commonIdentifierArtist, .commonIdentifierAuthor, .commonIdentifierCreator:
                if result.artist.isEmpty { result.artist = text }
            case .iTunesMetadataAlbum, .commonIdentifierAlbumName:
                if result.album.isEmpty { result.album = text }
            case .iTunesMetadataReleaseDate, .commonIdentifierCreationDate:
                if result.date.isEmpty { result.date = text }
            case .iTunesMetadataUserComment, .commonIdentifierDescription:
                if result.comment.isEmpty { result.comment = text }
            default:
                break
            }
        }
        return result.normalized
    }

    /// Rewrites the audio with the five tags, preserving any metadata Cornetta does
    /// not manage, then replaces the original atomically.
    public static func write(_ tags: RecordingTags, to url: URL) async throws {
        let tags = tags.normalized
        let container = containerExtension(for: url)
        let directory = url.deletingLastPathComponent()
        let source = directory.appendingPathComponent(".cornetta-tags-source-\(UUID().uuidString).\(container)")
        let temporary = directory.appendingPathComponent(".cornetta-tags-output-\(UUID().uuidString).m4a")
        try? FileManager.default.removeItem(at: source)
        try? FileManager.default.removeItem(at: temporary)
        do {
            try FileManager.default.copyItem(at: url, to: source)
        } catch {
            throw RecordingTagError.cannotExport
        }
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: temporary)
        }
        // Cornetta's own recordings are AAC in a CAF container even though the
        // file is named .m4a. AVAssetExportSession refuses a .m4a path with CAF
        // bytes, so the working copy uses the real container extension.
        let asset = AVURLAsset(url: source)
        let existing = (try? await asset.load(.metadata)) ?? []
        let preserved = existing.filter {
            guard let identifier = $0.identifier?.rawValue else { return true }
            return !managedIdentifiers.contains(identifier)
        }
        var metadata = preserved
        metadata.append(contentsOf: items(for: tags))

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            throw RecordingTagError.cannotExport
        }
        session.metadata = metadata
        do {
            try await session.export(to: temporary, as: .m4a)
            let size = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0 else { throw RecordingTagError.emptyOutput }
            do {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary,
                                                          backupItemName: nil, options: [])
            } catch {
                throw RecordingTagError.replaceFailed
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    private static func containerExtension(for url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return url.pathExtension.lowercased() == "caf" ? "caf" : "m4a"
        }
        defer { try? handle.close() }
        let header = (try? handle.read(upToCount: 12)) ?? Data()
        if header.starts(with: Data("caff".utf8)) { return "caf" }
        if header.count >= 8, Data(header[4..<8]) == Data("ftyp".utf8) { return "m4a" }
        return url.pathExtension.lowercased() == "caf" ? "caf" : "m4a"
    }

    public static func removeTemporaryFiles(in folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder,
                                                                   includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(".cornetta-tags-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private static func items(for tags: RecordingTags) -> [AVMetadataItem] {
        [
            item(.iTunesMetadataSongName, tags.title),
            item(.iTunesMetadataArtist, tags.artist),
            item(.iTunesMetadataAlbum, tags.album),
            item(.iTunesMetadataReleaseDate, tags.date),
            item(.iTunesMetadataUserComment, tags.comment),
        ].compactMap { $0 }
    }

    private static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        return item
    }

    private static func text(from value: Any?) -> String {
        switch value {
        case let string as String:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let string as NSString:
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        case let number as NSNumber:
            return number.stringValue
        case let date as Date:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: date)
        default:
            return ""
        }
    }
}
