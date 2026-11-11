import Foundation

struct EngineLayout: Sendable {
    let python: URL
    let scriptsDir: URL
    let modelsDir: URL
    let ffmpeg: URL?
    let isBuiltIn: Bool
    var cwd: URL { scriptsDir }
    var envAdditions: [String: String] {
        guard let ffmpeg else { return [:] }
        return ["MEETINGNOTES_FFMPEG": ffmpeg.path, "PATH": ffmpeg.deletingLastPathComponent().path]
    }
    /// Interpreter flags. `-I` ignores PYTHON* env vars, so the cache location must be a `-X` option:
    /// the built-in engine must never write __pycache__ into the signed app bundle.
    var pythonFlags: [String] {
        guard isBuiltIn else { return ["-I"] }
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MeetingNotes/pycache")
        return ["-I", "-X", "pycache_prefix=" + cache.path]
    }

    func environment(merging base: [String: String]) -> [String: String] {
        var result = base
        for (key, value) in envAdditions {
            result[key] = key == "PATH" ? value + ":" + (base[key] ?? "") : value
        }
        return result
    }

    var description: String {
        if !isBuiltIn { return "Developer: " + scriptsDir.path }
        let version = (try? String(contentsOf: scriptsDir.appendingPathComponent("ENGINE_VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "Built-in (version \(version.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"))"
    }
}

// Resolution takes explicit inputs; it never reads preferences or mutates the filesystem.
enum EngineLocator {
    enum Failure: LocalizedError {
        case missing
        var errorDescription: String? { "The transcription engine is missing. Reinstall MeetingNotes." }
    }

    static func resolve(repoPath: String, useDeveloperEngine: Bool, resourcesURL: URL?,
                        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) throws -> EngineLayout {
        let repo = URL(fileURLWithPath: NSString(string: repoPath).expandingTildeInPath)
        let developerPython = repo.appendingPathComponent("venv/bin/python")
        let developer = EngineLayout(python: developerPython, scriptsDir: repo,
                                     modelsDir: repo.appendingPathComponent("models"), ffmpeg: nil, isBuiltIn: false)
        if useDeveloperEngine && exists(developerPython) { return developer }
        if let engine = resourcesURL?.appendingPathComponent("engine") {
            let python = engine.appendingPathComponent("python/bin/python3")
            if exists(python) {
                let scripts = engine.appendingPathComponent("app")
                return EngineLayout(python: python, scriptsDir: scripts,
                                    modelsDir: scripts.appendingPathComponent("models"),
                                    ffmpeg: engine.appendingPathComponent("bin/ffmpeg"), isBuiltIn: true)
            }
        }
        if exists(developerPython) { return developer }
        throw Failure.missing
    }
}
