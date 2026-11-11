import XCTest
@testable import MeetingNotes

final class LiveCleanupTests: XCTestCase {
    @MainActor
    func testFreshAndLegacyPreferencesDefaultOnAndExplicitOffPersists() throws {
        let suite = "LiveCleanupTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(SettingsView.snapshot(defaults: defaults).liveCleanupEnabled)
        for legacy in [false, true] {
            defaults.set(legacy, forKey: "liveCleanupEnabled")
            defaults.set(false, forKey: "liveCleanupEnabledV2")
            XCTAssertTrue(SettingsView.snapshot(defaults: defaults).liveCleanupEnabled)
        }
        defaults.set(true, forKey: "liveCleanupEnabledChosen")
        XCTAssertFalse(SettingsView.snapshot(defaults: defaults).liveCleanupEnabled)
    }

    func testOffRequiresConfirmationAndCancelKeepsOn() {
        var state = LiveCleanupPreference()
        state.apply(.confirmOff)
        XCTAssertTrue(state.enabled)
        state.apply(.requestOff)
        XCTAssertEqual(state, LiveCleanupPreference(enabled: true, explicitChoice: false, pendingConfirmation: true))
        state.apply(.cancel)
        XCTAssertEqual(state, LiveCleanupPreference())
        state.apply(.requestOff)
        state.apply(.confirmOff)
        XCTAssertEqual(state, LiveCleanupPreference(enabled: false, explicitChoice: true))
        state.apply(.turnOn)
        XCTAssertEqual(state, LiveCleanupPreference(enabled: true, explicitChoice: true))
    }

    func testAutoProviderForAllAccountAndKeyCombinations() throws {
        for chatGPT in [false, true] {
            for claude in [false, true] {
                for key in [false, true] {
                    let choice = ProviderChoice.liveCleanup(provider: "codex", model: "old-model", chosen: false,
                        chatGPTConnected: chatGPT, claudeConnected: claude, anthropicKeySet: key)
                    let expected = claude ? "claude" : (chatGPT ? "codex" : (key ? "anthropic" : nil))
                    XCTAssertEqual(choice?.provider, expected)
                    XCTAssertEqual(choice?.model, expected.map { _ in "tier:cheap" })
                    let session = LiveSessionMetadata(startedAt: "now", inputDeviceName: "Mic",
                        systemAudio: false, liveCleanup: choice)
                    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
                    XCTAssertEqual(json["live_cleanup"] == nil, expected == nil)
                }
            }
        }
    }

    func testExplicitProviderAndModelArePreservedWithoutFallback() {
        XCTAssertEqual(ProviderChoice.liveCleanup(provider: "codex", model: "custom", chosen: true,
            chatGPTConnected: true, claudeConnected: true, anthropicKeySet: true),
            LiveCleanupConfiguration(provider: "codex", model: "custom"))
        XCTAssertNil(ProviderChoice.liveCleanup(provider: "codex", model: "custom", chosen: true,
            chatGPTConnected: false, claudeConnected: true, anthropicKeySet: true))
    }

    func testSessionEncodingOmitsDisabledCleanupAndIncludesEnabledConfiguration() throws {
        var session = LiveSessionMetadata(startedAt: "2026-11-11T10:00:00Z",
                                          inputDeviceName: "Mic", systemAudio: true)
        func json() throws -> [String: Any] {
            try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        }
        let disabled = try json()
        XCTAssertNil(disabled["live_cleanup"])
        XCTAssertEqual(disabled["segment_seconds"] as? Int, 30)
        XCTAssertEqual(disabled["system_audio"] as? Bool, true)
        XCTAssertEqual(disabled["input_device_name"] as? String, "Mic")
        for provider in ["claude", "codex", "anthropic"] {
            session.liveCleanup = LiveCleanupConfiguration(provider: provider, model: ProviderModelDefaults.model(for: provider, in: .liveCleanup))
            let configuration = try XCTUnwrap(try json()["live_cleanup"] as? [String: String])
            XCTAssertEqual(configuration, ["provider": provider, "model": session.liveCleanup!.model])
            XCTAssertFalse(configuration.keys.contains("api_key"))
        }
    }

    func testCleanedEventReplacesSegmentWithoutChangingIdentityOrOrder() throws {
        func event(_ source: String) throws -> LiveTranscriptEvent {
            try JSONDecoder().decode(LiveTranscriptEvent.self, from: Data(source.utf8))
        }
        var transcript = LiveTranscript()
        transcript.apply(try event(#"{"event":"segment","index":2,"text":"Second"}"#))
        transcript.apply(try event(#"{"event":"segment","index":1,"text":"Uncertain"}"#))
        let cleaned = try event(#"{"event":"segment_cleaned","index":1,"text":"Corrected"}"#)
        XCTAssertEqual(cleaned.index, 1)
        transcript.apply(cleaned)
        XCTAssertEqual(transcript.segments.map(\.id), [1, 2])
        XCTAssertEqual(transcript.segments.map(\.text), ["Corrected", "Second"])
        XCTAssertEqual(transcript.segments.map(\.cleaned), [true, false])
        transcript.apply(cleaned)
        transcript.apply(try event(#"{"event":"segment","index":1,"text":"Stale"}"#))
        transcript.apply(try event(#"{"event":"segment_cleaned","text":"Missing index"}"#))
        XCTAssertEqual(transcript.segments.count, 2)
        XCTAssertEqual(transcript.segments[0].text, "Corrected")
    }

    func testCorrectionCanArriveBeforeOriginal() {
        var transcript = LiveTranscript()
        transcript.apply(LiveTranscriptEvent(event: "segment_cleaned", index: 0, text: "Clean"))
        transcript.apply(LiveTranscriptEvent(event: "segment", index: 0, text: "Raw"))
        XCTAssertEqual(transcript.segments.first?.text, "Clean")
    }

    func testStatsDecodeAndFormat() throws {
        let data = Data(#"{"segments":7,"lines_total":214,"lines_sent":18,"calls":4,"chars_sent":5000,"chars_received":3400,"approx_tokens":2100}"#.utf8)
        let stats = try JSONDecoder().decode(LiveCleanupStats.self, from: data)
        XCTAssertEqual(stats.summary, "Live cleanup: 18 of 214 lines sent · ~2.1k tokens")
        let zero = LiveCleanupStats(segments: 0, lines_total: 0, lines_sent: 0, calls: 0,
                                    chars_sent: 0, chars_received: 0, approx_tokens: 0)
        XCTAssertEqual(zero.summary, "Live cleanup: 0 of 0 lines sent · ~0 tokens")
    }

    func testUsabilityRequiresSelectedAccountOrNonblankKey() {
        XCTAssertFalse(LiveCleanupConfiguration.usable(provider: "claude", chatGPTConnected: true, claudeConnected: false, key: "key"))
        XCTAssertTrue(LiveCleanupConfiguration.usable(provider: "codex", chatGPTConnected: true, claudeConnected: false, key: ""))
        XCTAssertTrue(LiveCleanupConfiguration.usable(provider: "claude", chatGPTConnected: false, claudeConnected: true, key: ""))
        XCTAssertFalse(LiveCleanupConfiguration.usable(provider: "anthropic", chatGPTConnected: true, claudeConnected: true, key: " \n"))
        XCTAssertTrue(LiveCleanupConfiguration.usable(provider: "anthropic", chatGPTConnected: false, claudeConnected: false, key: "key"))
    }
}
