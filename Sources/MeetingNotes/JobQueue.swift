import Foundation
import Combine

struct Job: Identifiable, Sendable {
    let id = UUID()
    let file: URL
    let name: String
    var settings: JobSettings
    var live = false
    var stage = "queued"
    var modelNotice: String?
    var message: String?
    var folder: String?
    var title: String?
    var error: String?
    var log: String?
    var finished = false
}

struct JobEvent: Decodable, Sendable {
    let stage: String
    let folder: String?
    let title: String?
    let message: String?
    let log: String?
    let requested: String?
    let used: String?
    let provider: String?
    let step: String?

    var modelNotice: ModelNotice? {
        guard let requested, let used, let provider, let step else { return nil }
        return ModelNotice(requested: requested, used: used, provider: provider, step: step)
    }
}

@MainActor
final class JobQueue: ObservableObject {
    static let extensions: Set<String> = ["m4a", "mp3", "wav", "aac", "caf", "ogg", "opus", "flac", "aiff", "mp4", "mov"]
    @Published private(set) var jobs: [Job] = []
    @Published var notice: String?
    private var accountObservers: Set<AnyCancellable> = []
    private var running = false
    private var recovered = false
    private let recoveryCandidates: [URL]
    private let account: ProviderAccount
    private let claudeAccount: ProviderAccount

    init(account: ProviderAccount, claudeAccount: ProviderAccount) {
        self.account = account
        self.claudeAccount = claudeAccount
        recoveryCandidates = LiveSessionScanner.scan(meetings: Paths.url(SettingsView.snapshot().meetings), queued: [])
        account.$state.combineLatest(claudeAccount.$state).sink { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.applyProviderChoice() }
        }.store(in: &accountObservers)
    }

    func applyProviderChoice() {
        guard account.state != .checking, account.state != .connecting,
              claudeAccount.state != .checking, claudeAccount.state != .connecting else { return }
        _ = SettingsView.applyProviderChoice(chatGPTConnected: account.state == .connected,
                                             claudeConnected: claudeAccount.state == .connected)
    }

    func importFiles(_ urls: [URL]) async {
        let settings = SettingsView.snapshot()
        for source in urls {
            guard Self.extensions.contains(source.pathExtension.lowercased()) else {
                notice = "Unsupported audio file: \(source.lastPathComponent)"
                continue
            }
            let access = source.startAccessingSecurityScopedResource()
            do {
                // Keep file access until the copy completes; copying never blocks the UI actor.
                let destination = try await Task.detached {
                    let inbox = Paths.url(settings.meetings).appendingPathComponent("_inbox")
                    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
                    let target = inbox.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
                    try FileManager.default.copyItem(at: source, to: target)
                    return target
                }.value
                enqueue(destination, settings: settings, name: source.lastPathComponent)
            } catch { notice = "Could not import \(source.lastPathComponent): \(error.localizedDescription)" }
            if access { source.stopAccessingSecurityScopedResource() }
        }
    }

    func enqueue(_ url: URL, settings: JobSettings, name: String? = nil, live: Bool = false) {
        jobs.append(Job(file: url, name: name ?? url.lastPathComponent, settings: settings, live: live))
        runNext()
    }

    func recoverLiveSessions() {
        guard !recovered else { return }
        recovered = true
        let settings = SettingsView.snapshot()
        // This snapshot was taken at initialization, before any new capture can start.
        let sessions = recoveryCandidates
        for session in sessions where !jobs.contains(where: { $0.file.standardizedFileURL == session.standardizedFileURL }) {
            do {
                // No capture is active for these launch-recovered sessions.
                try Data().write(to: session.appendingPathComponent("STOP"), options: .atomic)
                enqueue(session, settings: settings, live: true)
            } catch { notice = "Could not recover session: \(error.localizedDescription)" }
        }
    }

    private func runNext() {
        guard !running, let job = jobs.first(where: { !$0.finished }) else { return }
        running = true
        update(job.id) { $0.stage = "starting" }
        Task {
            var job = job
            // Launch recovery can race an activation-triggered account refresh.
            while account.state == .checking || claudeAccount.state == .checking ||
                  account.state == .connecting || claudeAccount.state == .connecting {
                try? await Task.sleep(for: .milliseconds(100))
            }
            applyProviderChoice()
            let choice = ProviderChoice(summaryProvider: job.settings.summaryProvider,
                summaryChosen: job.settings.summaryProviderChosen,
                correctProvider: job.settings.correctProvider, correctChosen: job.settings.correctProviderChosen,
                chatGPTConnected: account.state == .connected, claudeConnected: claudeAccount.state == .connected,
                anthropicKeySet: !job.settings.anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if job.settings.summaryProvider != choice.summaryProvider {
                job.settings.summaryModel = ProviderModelDefaults.model(for: choice.summaryProvider, in: .summary)
            }
            job.settings.summaryProvider = choice.summaryProvider
            if job.settings.correctProvider != choice.correctProvider {
                job.settings.correctModel = ProviderModelDefaults.model(for: choice.correctProvider, in: .correction)
            }
            job.settings.correctProvider = choice.correctProvider
            let resolvedSettings = job.settings
            update(job.id) { $0.settings = resolvedSettings }
            let providers = [job.settings.summaryProvider, job.settings.correctProvider]
            let executionJob = job
            let error: String?
            if providers.contains("codex"), account.state != .connected {
                error = "Connect ChatGPT first (button at the top)"
            } else if providers.contains("claude"), claudeAccount.state != .connected {
                error = "Connect Claude first (button at the top)"
            } else if providers.contains("anthropic"),
                      job.settings.anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                error = "Add your Anthropic API key in Settings"
            } else { error = nil }
            if let error {
                update(job.id) {
                    $0.error = error
                    $0.stage = "error"
                    $0.finished = true
                }
                running = false
                runNext()
                return
            }
            let result = await Task.detached {
                await Self.execute(executionJob) { event in
                    await self.receive(event, for: executionJob.id)
                }
            }.value
            update(job.id) {
                if let result, $0.error == nil { $0.error = result }
                if $0.error != nil { $0.stage = "error" }
                $0.finished = true
                if $0.error == nil {
                    if !$0.live, let title = $0.title {
                        do { try RecordingRenamer.rename($0.file, title: title, meetings: Paths.url($0.settings.meetings)) }
                        catch { notice = "Meeting saved, but recording could not be renamed: \(error.localizedDescription)" }
                    }
                    let inbox = Paths.url($0.settings.meetings).appendingPathComponent("_inbox")
                        .standardizedFileURL
                    let file = $0.file.standardizedFileURL
                    let inboxParts = inbox.resolvingSymlinksInPath().pathComponents
                    let fileParts = file.resolvingSymlinksInPath().pathComponents
                    if file.pathComponents.starts(with: inbox.pathComponents),
                       file.pathComponents.count > inbox.pathComponents.count,
                       fileParts.starts(with: inboxParts), fileParts.count > inboxParts.count {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
            }
            running = false
            runNext()
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        if let index = jobs.firstIndex(where: { $0.id == id }) { change(&jobs[index]) }
    }

    private func receive(_ event: JobEvent, for id: UUID) {
        if event.stage == "notice" {
            if let structured = event.modelNotice {
                structured.persist()
            } else if let message = event.message, let job = jobs.first(where: { $0.id == id }) {
                // Older stage notices contain only a message; use the active step's
                // snapshotted selection until meta.json supplies the full fallback record.
                let correction = job.stage == "correcting"
                if correction || job.stage == "summarizing" {
                    let provider = correction ? job.settings.correctProvider : job.settings.summaryProvider
                    let model = correction ? job.settings.correctModel : job.settings.summaryModel
                    if !model.isEmpty && !model.hasPrefix("tier:") {
                        ModelNotice(requested: model, used: "", provider: provider,
                                    step: correction ? "correction" : "summary", message: message).persist()
                    }
                }
            }
            let message = event.message ?? event.modelNotice?.formatted
            update(id) { $0.modelNotice = message }
            if let message { notice = message }
            return
        }
        if event.stage == "done", let folder = event.folder,
           let data = try? Data(contentsOf: Paths.url(folder).appendingPathComponent("meta.json")),
           let metadata = try? JSONDecoder().decode(ModelNoticeMetadata.self, from: data) {
            for notice in metadata.model_notices ?? [] { notice.persist() }
        }
        update(id) {
            $0.stage = event.stage
            $0.message = event.message
            if let folder = event.folder { $0.folder = folder }
            if let title = event.title { $0.title = title }
            if event.stage == "error" { $0.error = event.message ?? "The pipeline failed." }
            if let log = event.log { $0.log = log }
        }
    }

    nonisolated private static func execute(
        _ job: Job, event: @escaping @Sendable (JobEvent) async -> Void
    ) async -> String? {
        let process = Process()
        let engine: EngineLayout
        do {
            engine = try EngineLocator.resolve(repoPath: job.settings.repo,
                useDeveloperEngine: job.settings.useDeveloperEngine, resourcesURL: Bundle.main.resourceURL)
        } catch { return error.localizedDescription }
        process.executableURL = engine.python
        process.currentDirectoryURL = engine.cwd
        // Part C accepts --live-session without an AUDIO positional.
        let input = job.live ? ["--live-session", job.file.path] : [job.file.path]
        let args = engine.pythonFlags + [engine.scriptsDir.appendingPathComponent("summarize.py").path] + input + [
                    "--meetings-dir", Paths.url(job.settings.meetings).path,
                    "--summary-backend", job.settings.summaryProvider,
                    "--summary-model", job.settings.summaryModel,
                    "--correct-backend", job.settings.correctProvider,
                    "--correct-model", job.settings.correctModel,
                    "--proxy-url", job.settings.proxyURL]
        process.arguments = args
        var environment = engine.environment(merging: ChildEnvironment.standard)
        environment["CLIPROXY_API_KEY"] = job.settings.proxyKey
        environment.removeValue(forKey: "ANTHROPIC_API_KEY")
        if [job.settings.summaryProvider, job.settings.correctProvider].contains("anthropic") {
            environment["ANTHROPIC_API_KEY"] = job.settings.anthropicKey
        }
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        defer { try? pipe.fileHandleForReading.close() }
        do { try process.run() }
        catch { return "Could not launch the pipeline: \(error.localizedDescription)" }
        var buffer = Data()
        var done = false
        var malformed = false
        func decode(_ line: Data) async {
            guard !line.isEmpty else { return }
            if let value = try? JSONDecoder().decode(JobEvent.self, from: line) {
                if value.stage == "done", value.folder != nil { done = true }
                await event(value)
            } else { malformed = true }
        }
        // This entire function runs in a detached task, including blocking pipe reads and waitUntilExit.
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                await decode(line)
            }
        }
        await decode(buffer)
        process.waitUntilExit()
        if process.terminationStatus != 0 { return "Pipeline exited with status \(process.terminationStatus)." }
        if !done { return malformed ? "Pipeline returned invalid JSON output." : "Pipeline exited without a done event." }
        return nil
    }
}
