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

    static func summaryModel(_ model: String, switchingTo provider: String) -> String {
        let value = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if provider == "codex", value.hasPrefix("claude-") { return "" }
        return provider == "claude" && (value.isEmpty || value.hasPrefix("gpt-") ||
            value.hasPrefix("chatgpt") || value.contains("codex") ||
            ["o1", "o3", "o4"].contains(where: { value.hasPrefix($0) })) ? "claude-opus-5-5" : model
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
