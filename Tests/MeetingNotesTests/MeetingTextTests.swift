import AppKit
import XCTest
@testable import MeetingNotes

final class MeetingTextTests: XCTestCase {
    func testTranscriptKeepsLabelsAndSeparatesTurns() {
        let source = "[0:03] Speaker 1: Hello.\n\n[12:45] Speaker 2: नमस्ते.\n"
        XCTAssertEqual(MeetingAttributedText.transcript(source).string,
                       "[0:03] Speaker 1: Hello.\n\n[12:45] Speaker 2: नमस्ते.")
        XCTAssertEqual(MeetingAttributedText.transcript("Unlabelled text").string, "Unlabelled text")
        XCTAssertEqual(MeetingAttributedText.transcript("").string, "")
    }

    func testSummaryDropsLeadingTitleAndRendersMarkdown() {
        let source = """
        # Planning

        ## Next **steps**
        - [ ] Ask **Sam**
        - Ship **today**

        A **bold** paragraph
        continued here.
        """
        XCTAssertEqual(MeetingAttributedText.summary(source).string,
                       "Next steps\n\n☐ Ask Sam\n\n• Ship today\n\nA bold paragraph continued here.")
        XCTAssertEqual(MeetingAttributedText.summary("").string, "")
    }

    func testOnlyLeadingTitleIsHiddenAndUnmatchedBoldIsPreserved() {
        XCTAssertEqual(MeetingAttributedText.summary("\n# Title\n\nText **unfinished\n\n# Later").string,
                       "Text **unfinished\n\n# Later")
    }

    func testCopyReturnsExactUnformattedFileContents() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let summary = "# Title\n\n- [ ] **Do it**\n"
        let transcript = "[0:01] Speaker 1: Original.\r\n\r\n[0:05] Speaker 2: Yes.\r\n"
        let english = "[0:01] Speaker 1: English.\n"
        for (name, text) in [("summary.md", summary), ("transcript.corrected.txt", transcript),
                             ("transcript.english.txt", english), ("transcript.hinglish.txt", "Fallback")] {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let content = MeetingText.load(folder)
        XCTAssertEqual(content.copyText(for: .summary), summary)
        XCTAssertEqual(content.copyText(for: .summary, showEnglish: true), summary)
        XCTAssertEqual(content.copyText(for: .transcript), transcript)
        XCTAssertEqual(content.copyText(for: .transcript, showEnglish: true), english)
        try FileManager.default.removeItem(at: folder.appendingPathComponent("transcript.corrected.txt"))
        XCTAssertEqual(MeetingText.load(folder).copyText(for: .transcript), "Fallback")
    }
}
