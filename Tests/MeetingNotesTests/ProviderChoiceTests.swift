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

    func testDefaultsForEverySectionAndProvider() {
        for section in ProviderModelDefaults.Section.allCases {
            let live = section == .liveCleanup
            let tier = live ? "tier:cheap" : "tier:default"
            let expected = ["claude": tier, "anthropic": tier, "codex": tier,
                            "proxy": "gpt-5", "none": tier, "fake": tier]
            for (provider, model) in expected {
                XCTAssertEqual(ProviderModelDefaults.model(for: provider, in: section), model)
            }
        }
    }

    func testProviderChangesResetModelsAndUnchangedProvidersPreserveSavedModels() {
        let providers = ["claude", "anthropic", "codex", "proxy", "none", "fake"]
        for section in ProviderModelDefaults.Section.allCases {
            for previous in providers {
                for provider in providers {
                    for saved in ["claude-sonnet-5-5", "gpt-6-astra", "my-custom-model", ""] {
                        let result = ProviderModelDefaults.model(saved, changingFrom: previous,
                                                                 to: provider, in: section)
                        XCTAssertEqual(result, previous == provider ? saved :
                            ProviderModelDefaults.model(for: provider, in: section))
                        if previous != provider {
                            if provider == "codex" { XCTAssertFalse(result.hasPrefix("claude-")) }
                            if ["claude", "anthropic"].contains(provider) {
                                XCTAssertTrue(result.hasPrefix("tier:"))
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    func testAutomaticSwitchUsesDefaultsAndPreservesModelsWithoutProviderChanges() throws {
        let suite = "ProviderChoiceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "providerSettingsMigrated")
        defaults.set(false, forKey: "summaryProviderChosen")
        defaults.set(false, forKey: "correctProviderChosen")
        for (previous, target) in [("codex", "claude"), ("claude", "codex")] {
            defaults.set(previous, forKey: "summaryProvider")
            defaults.set(previous, forKey: "correctProvider")
            defaults.set("my-custom-model", forKey: "summaryModel")
            defaults.set("my-other-model", forKey: "correctModel")
            let choice = SettingsView.applyProviderChoice(chatGPTConnected: target == "codex",
                claudeConnected: target == "claude", defaults: defaults)
            XCTAssertEqual(choice.summaryProvider, target)
            XCTAssertEqual(choice.correctProvider, target)
            XCTAssertEqual(defaults.string(forKey: "summaryModel"),
                           ProviderModelDefaults.model(for: target, in: .summary))
            XCTAssertEqual(defaults.string(forKey: "correctModel"),
                           ProviderModelDefaults.model(for: target, in: .correction))

            defaults.set("saved-summary", forKey: "summaryModel")
            defaults.set("saved-correction", forKey: "correctModel")
            _ = SettingsView.applyProviderChoice(chatGPTConnected: target == "codex",
                claudeConnected: target == "claude", defaults: defaults)
            XCTAssertEqual(defaults.string(forKey: "summaryModel"), "saved-summary")
            XCTAssertEqual(defaults.string(forKey: "correctModel"), "saved-correction")
        }
    }
}
