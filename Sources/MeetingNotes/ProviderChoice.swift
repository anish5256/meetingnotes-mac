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

    /// Live cleanup prefers a small Claude model in AUTO, independently of other steps.
    static func liveCleanup(provider: String, model: String, chosen: Bool,
                            chatGPTConnected: Bool, claudeConnected: Bool,
                            anthropicKeySet: Bool) -> LiveCleanupConfiguration? {
        let selected = chosen ? provider : (claudeConnected ? "claude" :
            (chatGPTConnected ? "codex" : (anthropicKeySet ? "anthropic" : "none")))
        let usable: Bool
        switch selected {
        case "claude": usable = claudeConnected
        case "codex": usable = chatGPTConnected
        case "anthropic": usable = anthropicKeySet
        default: usable = false
        }
        guard usable else { return nil }
        return LiveCleanupConfiguration(provider: selected,
            model: chosen ? model : ProviderModelDefaults.model(for: selected, in: .liveCleanup))
    }

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

    static func model(for provider: String, in section: Section) -> String {
        provider == "proxy" ? "gpt-5" : (section == .liveCleanup ? "tier:cheap" : "tier:default")
    }

    static func migrated(_ saved: String, provider: String, in section: Section) -> String {
        guard provider != "proxy" else { return saved }
        let old = section == .liveCleanup
            ? ["claude-haiku-5-5", "gpt-6-luna", ""] : ["claude-opus-5-5", ""]
        return old.contains(saved) ? model(for: provider, in: section) : saved
    }

    static func menuModels(provider: String, in section: Section) -> [String] {
        let pinned = ["claude", "anthropic"].contains(provider)
            ? ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"]
            : (provider == "codex" ? ["", "gpt-6.1-sol", "gpt-6.1-terra", "gpt-6-luna", "gpt-6-astra"] : [""])
        return [model(for: provider, in: section)] + pinned
    }

    static func model(_ saved: String, changingFrom previous: String, to provider: String,
                      in section: Section) -> String {
        previous == provider ? saved : model(for: provider, in: section)
    }
}

/// The old default-off preference is deliberately not consulted.
struct LiveCleanupPreference: Equatable, Sendable {
    var enabled = true
    var explicitChoice = false
    var pendingConfirmation = false

    enum Action { case requestOff, turnOn, confirmOff, cancel }

    mutating func apply(_ action: Action) {
        switch action {
        case .requestOff:
            pendingConfirmation = enabled
        case .turnOn:
            enabled = true
            explicitChoice = true
            pendingConfirmation = false
        case .confirmOff:
            guard pendingConfirmation else { return }
            enabled = false
            explicitChoice = true
            pendingConfirmation = false
        case .cancel:
            pendingConfirmation = false
        }
    }

    static func load(defaults: UserDefaults) -> Self {
        let explicit = defaults.bool(forKey: "liveCleanupEnabledChosen")
        return Self(enabled: explicit ? (defaults.object(forKey: "liveCleanupEnabledV2") as? Bool ?? true) : true,
                    explicitChoice: explicit)
    }
}
