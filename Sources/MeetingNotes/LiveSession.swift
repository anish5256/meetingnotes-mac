import Foundation

struct RecorderStateMachine {
    enum State: Equatable { case idle, starting, recording, paused, stopping }
    enum Action { case start, ready, pause, resume, stop, finish, fail }
    private(set) var state: State = .idle
    @discardableResult mutating func apply(_ action: Action) -> Bool {
        switch (state, action) {
        case (.idle, .start): state = .starting
        case (.starting, .ready): state = .recording
        case (.recording, .pause): state = .paused
        case (.paused, .resume): state = .recording
        case (.recording, .stop), (.paused, .stop): state = .stopping
        case (.stopping, .finish), (.starting, .fail): state = .idle
        default: return false
        }
        return true
    }
}

enum SegmentNaming {
    static func name(_ index: Int) -> String { String(format: "seg-%05d", index) }
    static func segments(in session: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: session.appendingPathComponent("segments"), includingPropertiesForKeys: [.isRegularFileKey])) ?? []
        return files.filter {
            $0.pathExtension == "m4a" && $0.deletingPathExtension().lastPathComponent.range(
                of: #"^seg-[0-9]{5,}$"#, options: .regularExpression) != nil &&
            (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

enum LiveSessionScanner {
    static func scan(meetings: URL, queued: Set<URL>) -> [URL] {
        // Resolve symlinks on both sides (/var vs /private/var) or a queued session is re-enqueued.
        let canonical = { (url: URL) in url.resolvingSymlinksInPath().standardizedFileURL }
        let queued = Set(queued.map(canonical))
        let folders = ((try? FileManager.default.contentsOfDirectory(
            at: meetings.appendingPathComponent("_live"), includingPropertiesForKeys: [.isDirectoryKey])) ?? []).map(canonical)
        return folders.filter {
            !queued.contains($0) &&
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
            !SegmentNaming.segments(in: $0).isEmpty
        }.sorted { $0.path < $1.path }
    }
}

enum RecordingRenamer {
    static func sanitized(_ title: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:\0").union(.controlCharacters)
        let value = title.components(separatedBy: forbidden).joined(separator: " ")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return value.isEmpty ? "Recording" : String(value.prefix(60))
    }
    static func rename(_ source: URL, title: String, meetings: URL) throws {
        let root = meetings.appendingPathComponent("_recordings").resolvingSymlinksInPath().standardizedFileURL
        let file = source.resolvingSymlinksInPath().standardizedFileURL
        guard file.pathComponents.starts(with: root.pathComponents),
              file.pathComponents.count > root.pathComponents.count else { return }
        let stem = sanitized(title)
        var index = 1
        while true {
            let suffix = index == 1 ? "" : " (\(index))"
            let target = file.deletingLastPathComponent().appendingPathComponent(stem + suffix + ".m4a")
            if target == file { return }
            if !FileManager.default.fileExists(atPath: target.path) {
                // moveItem fails if another writer wins the name; it never overwrites.
                try FileManager.default.moveItem(at: file, to: target)
                return
            }
            index += 1
        }
    }
}

enum ChildEnvironment {
    static var standard: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        return env
    }
}

// A mic callback can precede or follow system-file closure at a segment boundary.
struct SegmentCompletion {
    var microphoneFinished = false
    var systemClosed = false
    let systemRunning: Bool
    var canPublish: Bool { microphoneFinished && (systemClosed || !systemRunning) }
}

struct LiveCleanupConfiguration: Codable, Equatable, Sendable {
    let provider: String
    let model: String

    static func usable(provider: String, chatGPTConnected: Bool, claudeConnected: Bool, key: String) -> Bool {
        switch provider {
        case "codex": return chatGPTConnected
        case "claude": return claudeConnected
        case "anthropic": return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default: return false
        }
    }
    static func providerName(_ provider: String) -> String {
        switch provider {
        case "codex": return "ChatGPT"
        case "anthropic": return "Claude API key"
        default: return "Claude"
        }
    }
}

struct LiveSessionMetadata: Encodable, Sendable {
    let startedAt: String
    let inputDeviceName: String
    var segmentSeconds = 30
    let systemAudio: Bool
    var liveCleanup: LiveCleanupConfiguration? = nil
    enum CodingKeys: String, CodingKey {
        case startedAt = "started_at", inputDeviceName = "input_device_name"
        case segmentSeconds = "segment_seconds", systemAudio = "system_audio", liveCleanup = "live_cleanup"
    }
}

struct LiveTranscriptEvent: Decodable, Sendable {
    let event: String
    let index: Int?
    let text: String?
    var message: String? = nil
    var requested: String? = nil
    var used: String? = nil
    var provider: String? = nil
    var step: String? = nil

    var modelNotice: ModelNotice? {
        guard let requested, let used, let provider else { return nil }
        return ModelNotice(requested: requested, used: used, provider: provider, step: step ?? "live_cleanup")
    }
}

struct LiveTranscript: Equatable, Sendable {
    struct Segment: Identifiable, Equatable, Sendable {
        let id: Int
        var text: String
        var cleaned: Bool
    }
    private(set) var segments: [Segment] = []
    mutating func apply(_ event: LiveTranscriptEvent) {
        guard ["segment", "segment_cleaned"].contains(event.event),
              let index = event.index, index >= 0, let text = event.text else { return }
        let cleaned = event.event == "segment_cleaned"
        if let position = segments.firstIndex(where: { $0.id == index }) {
            // A delayed original event must not undo a correction.
            guard cleaned || !segments[position].cleaned else { return }
            segments[position].text = text
            segments[position].cleaned = cleaned
        } else {
            segments.append(Segment(id: index, text: text, cleaned: cleaned))
            segments.sort { $0.id < $1.id }
        }
    }
}

struct LiveCleanupStats: Decodable, Equatable, Sendable {
    let segments: Int
    let lines_total: Int
    let lines_sent: Int
    let calls: Int
    let chars_sent: Int
    let chars_received: Int
    let approx_tokens: Double

    var summary: String {
        let tokens = approx_tokens >= 1000 ? String(format: "%.1fk", locale: Locale(identifier: "en_US_POSIX"), approx_tokens / 1000) :
            String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), approx_tokens)
        return "Live cleanup: \(lines_sent) of \(lines_total) lines sent · ~\(tokens) tokens"
    }
}
