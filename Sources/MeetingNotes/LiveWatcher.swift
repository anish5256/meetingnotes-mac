import Foundation

// Pipe reads and JSON decoding stay off the UI actor. The watcher is allowed to finish
// after Stop; finalization can recover everything if it exits early.
enum LiveWatcher {
    private struct Event: Decodable { let event: String; let text: String? }
    static func run(session: URL, settings: JobSettings,
                    text: @escaping @Sendable (String) async -> Void,
                    notice: @escaping @Sendable (String) async -> Void) async {
        let process = Process()
        let engine: EngineLayout
        do {
            engine = try EngineLocator.resolve(repoPath: settings.repo,
                useDeveloperEngine: settings.useDeveloperEngine, resourcesURL: Bundle.main.resourceURL)
        } catch {
            await notice(error.localizedDescription)
            return
        }
        process.executableURL = engine.python
        process.arguments = ["-I", engine.scriptsDir.appendingPathComponent("live_transcribe.py").path, "watch", session.path]
        process.currentDirectoryURL = engine.cwd
        process.environment = engine.environment(merging: ChildEnvironment.standard)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardInput = FileHandle.nullDevice
        let logURL = session.appendingPathComponent("watcher.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let log = try? FileHandle(forWritingTo: logURL)
        process.standardError = log ?? FileHandle.nullDevice
        defer { try? pipe.fileHandleForReading.close(); try? log?.close() }
        do { try process.run() } catch {
            await notice("Live transcription could not start. Recording will be transcribed after Stop.")
            return
        }
        try? pipe.fileHandleForWriting.close()
        var buffer = Data()
        var stopped = false
        func decode(_ data: Data) async {
            guard let event = try? JSONDecoder().decode(Event.self, from: data) else { return }
            if event.event == "downloading_model" { await notice("Downloading speech model (one time)…") }
            if event.event == "stopped" { stopped = true }
            if event.event == "segment", let value = event.text { await text(value) }
        }
        while true {
            let data = pipe.fileHandleForReading.availableData
            if data.isEmpty { break }
            buffer.append(data)
            while let end = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                await decode(line)
            }
        }
        await decode(buffer)
        process.waitUntilExit()
        if !stopped { await notice("Live transcription stopped early. Recording will be recovered after Stop.") }
    }
}
