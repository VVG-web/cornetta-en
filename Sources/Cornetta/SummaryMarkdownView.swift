import AppKit
import CornettaCore
import SwiftUI

/// Renders the generated summary as a readable article instead of raw Markdown.
/// The parser is local and deterministic: no web view and no network access.
struct SummaryMarkdownView: View {
    private let blocks: [SummaryMarkdownBlock]

    init(markdown: String) {
        blocks = SummaryMarkdownParser.blocks(from: markdown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: SummaryMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(styledInline(text))
                .font(headingFont(level))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level == 1 ? 4 : 9)
        case .paragraph(let text):
            Text(styledInline(text))
                .font(.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .list(let list):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    listRow(item)
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 3)
                Text(styledInline(text))
                    .font(.body)
                    .italic()
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        case .code(let language, let text):
            codeBlock(language: language, text: text)
        case .rule:
            Divider().padding(.vertical, 3)
        case .table(let table):
            tableBlock(table)
        }
    }

    private func listRow(_ item: SummaryMarkdownListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            marker(item.marker)
            Text(styledInline(item.text))
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, CGFloat(item.depth) * 18)
    }

    @ViewBuilder
    private func marker(_ marker: SummaryMarkdownListItem.Marker) -> some View {
        switch marker {
        case .bullet:
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
        case .number(let number):
            Text("\(number).")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 22, alignment: .trailing)
        case .task(let checked):
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.body)
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
                .frame(width: 14, alignment: .trailing)
        }
    }

    private func codeBlock(language: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.22)))
    }

    private func tableBlock(_ table: SummaryMarkdownTable) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                GridRow {
                    ForEach(table.headers.indices, id: \.self) { index in
                        Text(styledInline(table.headers[index]))
                            .font(.callout.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().gridCellColumns(max(table.headers.count, 1))
                ForEach(table.rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(table.headers.indices, id: \.self) { columnIndex in
                            Text(styledInline(table.rows[rowIndex][columnIndex]))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.22)))
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .system(size: 24, weight: .bold)
        case 2: return .system(size: 20, weight: .semibold)
        case 3: return .system(size: 17, weight: .semibold)
        default: return .system(size: 15, weight: .semibold)
        }
    }

    private func styledInline(_ source: String) -> AttributedString {
        guard var value = try? AttributedString(
            markdown: source,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(source)
        }
        let codeRanges = value.runs.compactMap { run in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        for range in codeRanges {
            value[range].font = .system(size: 12, design: .monospaced)
            value[range].foregroundColor = .orange
        }
        return value
    }
}
