import Foundation

struct ModelNotice: Codable, Equatable, Sendable {
    let requested: String
    let used: String
    let provider: String
    let step: String
    var message: String? = nil

    var formatted: String {
        if let message { return message }
        let name: String
        switch requested {
        case "claude-haiku-5-5": name = "Claude Haiku 5.5"
        case "claude-opus-5-5": name = "Claude Opus 5.5"
        case "claude-sonnet-5-5": name = "Claude Sonnet 5.5"
        default: name = requested
        }
        return "\(name) is no longer available; used \(used) instead. Update in Settings ▸ Models."
    }

    var section: String? {
        switch step.lowercased() {
        case "live_cleanup", "live-cleanup", "livecleanup", "cleanup": return "liveCleanup"
        case "correct", "correction", "correcting", "transcript correction": return "correction"
        case "summary", "summarize", "summarizing": return "summary"
        default: return nil
        }
    }

    func matches(provider: String, model: String) -> Bool {
        !model.hasPrefix("tier:") && requested == model && self.provider == provider
    }

    func persist(defaults: UserDefaults = .standard) {
        guard let section, let data = try? JSONEncoder().encode(self),
              let value = String(data: data, encoding: .utf8) else { return }
        defaults.set(value, forKey: "modelNotice." + section)
    }

    static func load(_ value: String) -> Self? {
        try? JSONDecoder().decode(Self.self, from: Data(value.utf8))
    }
}

struct ModelNoticeMetadata: Decodable, Sendable {
    let model_notices: [ModelNotice]?
}
