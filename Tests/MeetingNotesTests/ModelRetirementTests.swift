import XCTest
@testable import MeetingNotes

final class ModelRetirementTests: XCTestCase {
    @MainActor
    func testMigrationRunsOnceAndPreservesExplicitModels() throws {
        let suite = "ModelRetirementTests." + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        for section in ProviderModelDefaults.Section.allCases {
            for provider in ["claude", "anthropic", "codex", "none", "fake"] {
                let oldDefaults = section == .liveCleanup ? ["claude-haiku-5-5", "gpt-6-luna", ""] : ["claude-opus-5-5", ""]
                for saved in oldDefaults {
                    XCTAssertEqual(ProviderModelDefaults.migrated(saved, provider: provider, in: section),
                                   ProviderModelDefaults.model(for: provider, in: section))
                }
                for saved in ["custom", "claude-sonnet-5-5", "gpt-6-astra", "tier:cheap"] {
                    XCTAssertEqual(ProviderModelDefaults.migrated(saved, provider: provider, in: section), saved)
                }
            }
            XCTAssertEqual(ProviderModelDefaults.migrated("gpt-5", provider: "proxy", in: section), "gpt-5")
        }
        d.set("claude", forKey: "summaryProvider")
        d.set("claude-opus-5-5", forKey: "summaryModel")
        d.set("codex", forKey: "correctProvider")
        d.set("", forKey: "correctModel")
        d.set("gpt-6-luna", forKey: "liveCleanupModel")
        SettingsView.migrateSettings(defaults: d)
        XCTAssertEqual(d.string(forKey: "summaryModel"), "tier:default")
        XCTAssertEqual(d.string(forKey: "correctModel"), "tier:default")
        XCTAssertEqual(d.string(forKey: "liveCleanupModel"), "tier:cheap")
        d.set("claude-opus-5-5", forKey: "summaryModel")
        SettingsView.migrateSettings(defaults: d)
        XCTAssertEqual(d.string(forKey: "summaryModel"), "claude-opus-5-5")
    }

    func testMenuTagsStartWithTierAndKeepPinnedChoices() {
        for section in ProviderModelDefaults.Section.allCases {
            for provider in ["claude", "anthropic", "codex"] {
                let models = ProviderModelDefaults.menuModels(provider: provider, in: section)
                XCTAssertEqual(models.first, section == .liveCleanup ? "tier:cheap" : "tier:default")
                XCTAssertTrue(models.contains(provider == "codex" ? "gpt-6-luna" : "claude-haiku-5-5"))
                XCTAssertFalse(models.contains("custom")) // Picker appends its Custom… sentinel.
            }
        }
    }

    func testNoticeDecodingFormattingAndPersistence() throws {
        let payload = #"{"requested":"claude-haiku-5-5","used":"haiku","provider":"claude","step":"live_cleanup"}"#
        let notice = try JSONDecoder().decode(ModelNotice.self, from: Data(payload.utf8))
        XCTAssertEqual(notice.formatted, "Claude Haiku 5.5 is no longer available; used haiku instead. Update in Settings ▸ Models.")
        XCTAssertTrue(notice.matches(provider: "claude", model: "claude-haiku-5-5"))
        XCTAssertFalse(notice.matches(provider: "claude", model: "tier:cheap"))
        XCTAssertFalse(notice.matches(provider: "codex", model: notice.requested))
        let liveJSON = "{\"event\":\"model_notice\"," + payload.dropFirst()
        let live = try JSONDecoder().decode(LiveTranscriptEvent.self, from: Data(liveJSON.utf8))
        XCTAssertEqual(live.modelNotice, notice)
        let job = try JSONDecoder().decode(JobEvent.self, from: Data(#"{"stage":"notice","message":"Model replaced"}"#.utf8))
        XCTAssertEqual(job.stage, "notice")
        XCTAssertEqual(job.message, "Model replaced")
        let meta = try JSONDecoder().decode(ModelNoticeMetadata.self, from: Data(("{\"model_notices\":[" + payload + "]}").utf8))
        XCTAssertEqual(meta.model_notices, [notice])
        let suite = "ModelNoticeTests." + UUID().uuidString
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        notice.persist(defaults: d)
        XCTAssertEqual(ModelNotice.load(d.string(forKey: "modelNotice.liveCleanup") ?? ""), notice)
        XCTAssertNil(ModelNotice.load("invalid"))
    }
}
