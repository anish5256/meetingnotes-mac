import XCTest
@testable import MeetingNotes

final class ProviderChoiceTests: XCTestCase {
    private func choice(chatGPT: Bool = false, claude: Bool = false,
                        summary: String = "codex", chosen: Bool = false,
                        correction: String = "codex", correctionChosen: Bool = false,
                        key: Bool = false) -> ProviderChoice {
        ProviderChoice(summaryProvider: summary, summaryChosen: chosen,
            correctProvider: correction, correctChosen: correctionChosen,
            chatGPTConnected: chatGPT, claudeConnected: claude, anthropicKeySet: key)
    }

    func testOnlyClaudeAutomaticallySelectsClaudeForBothSteps() {
        let result = choice(claude: true)
        XCTAssertEqual(result.summaryProvider, "claude")
        XCTAssertEqual(result.correctProvider, "claude")
        XCTAssertEqual(result.notice, .none)
    }

    func testOnlyChatGPTAndBothPreferChatGPT() {
        for claude in [false, true] {
            let result = choice(chatGPT: true, claude: claude, summary: "claude", correction: "claude")
            XCTAssertEqual(result.summaryProvider, "codex")
            XCTAssertEqual(result.correctProvider, "codex")
            XCTAssertEqual(result.notice, .none)
        }
    }

    func testNeitherConnectedKeepsSelectionAndRequestsEitherAccount() {
        let result = choice()
        XCTAssertEqual(result.summaryProvider, "codex")
        XCTAssertEqual(result.correctProvider, "codex")
        XCTAssertEqual(result.notice, .connectAny)
    }

    func testExplicitChatGPTOffersClaudeWithoutChangingSelection() {
        let result = choice(claude: true, chosen: true)
        XCTAssertEqual(result.summaryProvider, "codex")
        XCTAssertEqual(result.correctProvider, "claude")
        XCTAssertEqual(result.notice, .selectedNotConnected(selected: "codex", alternative: "claude"))
        XCTAssertEqual(result.noticeStep, .summary)
    }

    func testCorrectionOffIsNeverAutomaticallyChanged() {
        for connected in [false, true] {
            XCTAssertEqual(choice(claude: connected, correction: "none").correctProvider, "none")
        }
    }

    func testExplicitConnectedChoiceIsPreserved() {
        let result = choice(chatGPT: true, claude: true, summary: "claude", chosen: true,
                            correction: "none", correctionChosen: true)
        XCTAssertEqual(result.summaryProvider, "claude")
        XCTAssertEqual(result.correctProvider, "none")
        XCTAssertEqual(result.notice, .none)
    }

    func testExplicitCorrectionAndNoAlternative() {
        let result = choice(summary: "fake", chosen: true, correctionChosen: true)
        XCTAssertEqual(result.notice, .selectedNotConnected(selected: "codex", alternative: nil))
        XCTAssertEqual(result.noticeStep, .correction)
    }

    func testConfiguredNonAccountProvidersNeedNoConnection() {
        for summary in ["anthropic", "proxy", "fake"] {
            XCTAssertEqual(choice(summary: summary, chosen: true, correction: "none", key: true).notice, .none)
        }
        XCTAssertEqual(choice(summary: "anthropic", chosen: true, correction: "none").notice,
                       .selectedNotConnected(selected: "anthropic", alternative: nil))
    }

    func testMigrationUsesOldDefaultsOnlyWhenFlagIsAbsent() {
        for (provider, oldDefault, expected) in [("codex", "codex", false), ("none", "none", false),
                                                  ("claude", "codex", true), ("codex", "none", true)] {
            XCTAssertEqual(ProviderChoice.migratedChoice(provider: provider, oldDefault: oldDefault, storedFlag: nil), expected)
            XCTAssertTrue(ProviderChoice.migratedChoice(provider: provider, oldDefault: oldDefault, storedFlag: true))
            XCTAssertFalse(ProviderChoice.migratedChoice(provider: provider, oldDefault: oldDefault, storedFlag: false))
        }
    }

    func testClaudeModelSwitchPreservesCustomModels() {
        XCTAssertEqual(ProviderChoice.summaryModel("claude-opus-5-5", switchingTo: "codex"), "")
        for model in ["", "gpt-5", "gpt-5-codex", "o3"] {
            XCTAssertEqual(ProviderChoice.summaryModel(model, switchingTo: "claude"), "claude-opus-5-5")
        }
        for model in ["claude-sonnet-5-5", "my-custom-model"] {
            XCTAssertEqual(ProviderChoice.summaryModel(model, switchingTo: "claude"), model)
        }
    }
}
