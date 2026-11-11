import Foundation

/// Account-independent policy shared by preferences, notices, and queued jobs.
struct ProviderChoice: Equatable, Sendable {
    enum Step: String, Equatable, Sendable { case summary = "Summary", correction = "Transcript correction" }
    enum Notice: Equatable, Sendable {
        case none
        case connectAny
        case selectedNotConnected(selected: String, alternative: String?)
    }
    let summaryProvider: String
    let correctProvider: String
    let notice: Notice
    let noticeStep: Step?

    static func migratedChoice(provider: String, oldDefault: String, storedFlag: Bool?) -> Bool {
        storedFlag ?? (provider != oldDefault)
    }

    init(summaryProvider: String, summaryChosen: Bool, correctProvider: String, correctChosen: Bool,
         chatGPTConnected: Bool, claudeConnected: Bool, anthropicKeySet: Bool) {
        let alternative: String? = chatGPTConnected ? "codex" : (claudeConnected ? "claude" : nil)
        func effective(_ provider: String, chosen: Bool, correction: Bool = false) -> String {
            chosen || (correction && provider == "none") ? provider : (alternative ?? provider)
        }
        self.summaryProvider = effective(summaryProvider, chosen: summaryChosen)
        self.correctProvider = effective(correctProvider, chosen: correctChosen, correction: true)
        func usable(_ provider: String) -> Bool {
            switch provider {
            case "codex": return chatGPTConnected
            case "claude": return claudeConnected
            case "anthropic": return anthropicKeySet
            default: return true // Off, offline, and custom endpoints need no account.
            }
        }
        let steps: [(Step, String, Bool)] = [(.summary, self.summaryProvider, summaryChosen),
                                            (.correction, self.correctProvider, correctChosen)]
        // An explicit disconnected selection takes precedence over a generic prompt.
        if let step = steps.first(where: { $0.2 && !usable($0.1) }) {
            notice = .selectedNotConnected(selected: step.1, alternative: alternative)
            noticeStep = step.0
        } else if let step = steps.first(where: { !usable($0.1) }) {
            notice = .connectAny
            noticeStep = step.0
        } else {
            notice = .none
            noticeStep = nil
        }
    }
}

/// Pure defaults policy; saved models survive until their provider changes.
enum ProviderModelDefaults {
    enum Section: CaseIterable, Hashable, Sendable { case liveCleanup, correction, summary }

    private static let table: [Section: [String: String]] = [
        .liveCleanup: ["claude": "claude-haiku-5-5", "anthropic": "claude-haiku-5-5",
                       "codex": "gpt-6-luna", "proxy": "gpt-5", "none": "", "fake": ""],
        .correction: ["claude": "claude-opus-5-5", "anthropic": "claude-opus-5-5",
                      "codex": "", "proxy": "gpt-5", "none": "", "fake": ""],
        .summary: ["claude": "claude-opus-5-5", "anthropic": "claude-opus-5-5",
                   "codex": "", "proxy": "gpt-5", "none": "", "fake": ""]
    ]

    static func model(for provider: String, in section: Section) -> String {
        table[section]?[provider] ?? ""
    }

    static func model(_ saved: String, changingFrom previous: String, to provider: String,
                      in section: Section) -> String {
        previous == provider ? saved : model(for: provider, in: section)
    }
}
