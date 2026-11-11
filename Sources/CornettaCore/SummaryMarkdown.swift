import Foundation

/// A small Markdown block model used by the summary reader. It intentionally
/// covers the constructs language models produce most often, without pulling a
/// web view or a third-party renderer into the app.
public enum SummaryMarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(SummaryMarkdownList)
    case quote(String)
    case code(language: String?, text: String)
    case rule
    case table(SummaryMarkdownTable)
}

public struct SummaryMarkdownList: Equatable, Sendable {
    public var items: [SummaryMarkdownListItem]

    public init(items: [SummaryMarkdownListItem]) {
        self.items = items
    }
}

public struct SummaryMarkdownListItem: Equatable, Sendable {
    public enum Marker: Equatable, Sendable {
        case bullet
        case number(Int)
        case task(checked: Bool)
    }

    public var marker: Marker
    public var depth: Int
    public var text: String

    public init(marker: Marker, depth: Int = 0, text: String) {
        self.marker = marker
        self.depth = depth
        self.text = text
    }
}

public struct SummaryMarkdownTable: Equatable, Sendable {
    public var headers: [String]
    public var rows: [[String]]

    public init(headers: [String], rows: [[String]]) {
        self.headers = headers
        self.rows = rows
    }
}

public enum SummaryMarkdownParser {
    public static func blocks(from markdown: String) -> [SummaryMarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var result: [SummaryMarkdownBlock] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                index += 1
                continue
            }
            if let fence = fenceStart(trimmed) {
                let code = readCode(lines: lines, start: index, fence: fence)
                result.append(.code(language: code.language, text: code.text))
                index = code.next
                continue
            }
            if let heading = heading(trimmed) {
                result.append(.heading(level: heading.level, text: heading.text))
                index += 1
                continue
            }
            if isRule(trimmed) {
                result.append(.rule)
                index += 1
                continue
            }
            if isTableStart(lines: lines, at: index) {
                let table = readTable(lines: lines, start: index)
                result.append(.table(table.table))
                index = table.next
                continue
            }
            if let item = listItem(line) {
                var items = [item]
                index += 1
                while index < lines.count, let next = listItem(lines[index]) {
                    items.append(next)
                    index += 1
                }
                result.append(.list(SummaryMarkdownList(items: items)))
                continue
            }
            if trimmed.hasPrefix(">") {
                let quote = readQuote(lines: lines, start: index)
                result.append(.quote(quote.text))
                index = quote.next
                continue
            }
            let paragraph = readParagraph(lines: lines, start: index)
            result.append(.paragraph(paragraph.text))
            index = paragraph.next
        }
        return result
    }

    private struct CodeFence {
        let character: Character
        let language: String?
    }

    private static func fenceStart(_ line: String) -> CodeFence? {
        guard let first = line.first, first == "`" || first == "~" else { return nil }
        let marker = String(repeating: first, count: 3)
        guard line.hasPrefix(marker) else { return nil }
        let language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return CodeFence(character: first, language: language.isEmpty ? nil : language)
    }

    private static func readCode(lines: [String], start: Int, fence: CodeFence) -> (language: String?, text: String, next: Int) {
        let closing = String(repeating: fence.character, count: 3)
        var body: [String] = []
        var index = start + 1
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(closing) {
                index += 1
                break
            }
            body.append(lines[index])
            index += 1
        }
        return (fence.language, body.joined(separator: "\n"), index)
    }

    private static func heading(_ line: String) -> (level: Int, text: String)? {
        var level = 0
        for character in line {
            if character == "#" {
                level += 1
            } else {
                break
            }
        }
        guard (1...6).contains(level), line.dropFirst(level).first == " " else { return nil }
        var text = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)] == "#" {
            end = text.index(before: end)
        }
        if end < text.endIndex, end > text.startIndex,
           text[text.index(before: end)] == " " {
            text = String(text[..<end]).trimmingCharacters(in: .whitespaces)
        }
        return (level, text)
    }

    private static func isRule(_ line: String) -> Bool {
        let compact = line.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first,
              first == "-" || first == "*" || first == "_" else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func listItem(_ line: String) -> SummaryMarkdownListItem? {
        let leading = line.prefix { $0 == " " || $0 == "\t" }.count
        let depth = min(leading / 2, 8)
        let body = line.dropFirst(leading)
        var marker: SummaryMarkdownListItem.Marker?
        var text: Substring
        if let first = body.first, first == "-" || first == "*" || first == "+" {
            guard body.dropFirst().first == " " else { return nil }
            marker = .bullet
            text = body.dropFirst(2)
        } else {
            let digits = body.prefix { $0.isNumber }
            guard !digits.isEmpty, let separator = body.dropFirst(digits.count).first,
                  separator == "." || separator == ")" else { return nil }
            let after = body.dropFirst(digits.count + 1)
            guard after.first == " " else { return nil }
            marker = .number(Int(digits) ?? 1)
            text = after.dropFirst()
        }
        let content = String(text).trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("[ ] ") || content.lowercased().hasPrefix("[x] ") {
            marker = .task(checked: content.lowercased().hasPrefix("[x]"))
            text = content.dropFirst(4)
        }
        guard let marker else { return nil }
        return SummaryMarkdownListItem(marker: marker, depth: depth,
                                       text: text.trimmingCharacters(in: .whitespaces))
    }

    private static func isTableStart(lines: [String], at index: Int) -> Bool {
        guard lines[index].contains("|"), index + 1 < lines.count,
              lines[index + 1].contains("|"), isTableSeparator(lines[index + 1]) else { return false }
        return true
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let trimmed = cell.trimmingCharacters(in: .whitespaces)
            let dashes = trimmed.filter { $0 == "-" }.count
            return dashes >= 3 && trimmed.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func tableCells(_ line: String) -> [String] {
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|"), !cells.isEmpty {
            cells.removeFirst()
        }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|"), !cells.isEmpty {
            cells.removeLast()
        }
        return cells.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func readTable(lines: [String], start: Int) -> (table: SummaryMarkdownTable, next: Int) {
        let headers = tableCells(lines[start])
        var rows: [[String]] = []
        var index = start + 2
        while index < lines.count {
            let line = lines[index]
            guard line.contains("|"), !line.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            var cells = tableCells(line)
            if cells.count < headers.count {
                cells.append(contentsOf: Array(repeating: "", count: headers.count - cells.count))
            }
            rows.append(Array(cells.prefix(headers.count)))
            index += 1
        }
        return (SummaryMarkdownTable(headers: headers, rows: rows), index)
    }

    private static func readQuote(lines: [String], start: Int) -> (text: String, next: Int) {
        var body: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var content = trimmed.dropFirst()
            if content.first == " " { content = content.dropFirst() }
            body.append(String(content))
            index += 1
        }
        return (body.joined(separator: " "), index)
    }

    private static func readParagraph(lines: [String], start: Int) -> (text: String, next: Int) {
        var body: [String] = []
        var index = start
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isBlockStart(lines: lines, at: index) { break }
            body.append(trimmed)
            index += 1
        }
        return (body.joined(separator: " "), index)
    }

    private static func isBlockStart(lines: [String], at index: Int) -> Bool {
        let line = lines[index]
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return fenceStart(trimmed) != nil
            || heading(trimmed) != nil
            || isRule(trimmed)
            || trimmed.hasPrefix(">")
            || listItem(line) != nil
            || isTableStart(lines: lines, at: index)
    }
}
