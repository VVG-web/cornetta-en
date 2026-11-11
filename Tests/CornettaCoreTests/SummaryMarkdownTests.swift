import Testing
@testable import CornettaCore

struct SummaryMarkdownTests {
    @Test func parsesHeadingsParagraphsAndLists() {
        let blocks = SummaryMarkdownParser.blocks(from: """
        # Weekly sync

        A readable **summary** with _emphasis_.

        ## Decisions
        - Ship 0.9.6
        - [x] Update the feed
          1. Verify the signature

        > Keep the transcript local.
        """)
        #expect(blocks.count == 5)
        if case .heading(let level, let text) = blocks[0] {
            #expect(level == 1)
            #expect(text == "Weekly sync")
        } else {
            Issue.record("first block is not a heading")
        }
        if case .paragraph(let text) = blocks[1] {
            #expect(text == "A readable **summary** with _emphasis_.")
        } else {
            Issue.record("second block is not a paragraph")
        }
        if case .heading(let level, let text) = blocks[2] {
            #expect(level == 2)
            #expect(text == "Decisions")
        } else {
            Issue.record("third block is not a heading")
        }
        if case .list(let list) = blocks[3] {
            #expect(list.items.count == 3)
            #expect(list.items[0].marker == .bullet)
            #expect(list.items[1].marker == .task(checked: true))
            #expect(list.items[1].text == "Update the feed")
            #expect(list.items[2].marker == .number(1))
            #expect(list.items[2].depth == 1)
            #expect(list.items[2].text == "Verify the signature")
        } else {
            Issue.record("fourth block is not a list")
        }
        if case .quote(let text) = blocks[4] {
            #expect(text == "Keep the transcript local.")
        } else {
            Issue.record("fifth block is not a quote")
        }
    }

    @Test func parsesCodeFencesAndRules() {
        let blocks = SummaryMarkdownParser.blocks(from: """
        Intro

        ```swift
        let value = 42
        print(value)
        ```

        ---

        End
        """)
        #expect(blocks.count == 4)
        if case .code(let language, let text) = blocks[1] {
            #expect(language == "swift")
            #expect(text == "let value = 42\nprint(value)")
        } else {
            Issue.record("second block is not code")
        }
        #expect(blocks[2] == .rule)
        if case .paragraph(let text) = blocks[3] {
            #expect(text == "End")
        } else {
            Issue.record("fourth block is not a paragraph")
        }
    }

    @Test func parsesTablesAndPadsShortRows() {
        let blocks = SummaryMarkdownParser.blocks(from: """
        | Item | Owner | Status |
        | --- | :--- | ---: |
        | Feed | Ana | Done |
        | Tests | Bo |
        """)
        #expect(blocks.count == 1)
        if case .table(let table) = blocks[0] {
            #expect(table.headers == ["Item", "Owner", "Status"])
            #expect(table.rows.count == 2)
            #expect(table.rows[0] == ["Feed", "Ana", "Done"])
            #expect(table.rows[1] == ["Tests", "Bo", ""])
        } else {
            Issue.record("block is not a table")
        }
    }

    @Test func keepsUnclosedCodeFenceAndDropsTrailingHeadingHashes() {
        let blocks = SummaryMarkdownParser.blocks(from: """
        ## Title ###

        ```
        still code
        """)
        #expect(blocks.count == 2)
        if case .heading(let level, let text) = blocks[0] {
            #expect(level == 2)
            #expect(text == "Title")
        } else {
            Issue.record("first block is not a heading")
        }
        if case .code(let language, let text) = blocks[1] {
            #expect(language == nil)
            #expect(text == "still code")
        } else {
            Issue.record("second block is not code")
        }
    }

    @Test func emptyMarkdownHasNoBlocks() {
        #expect(SummaryMarkdownParser.blocks(from: "\n\n").isEmpty)
    }
}
