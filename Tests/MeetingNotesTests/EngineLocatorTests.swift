import XCTest
@testable import MeetingNotes

final class EngineLocatorTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func touch(_ file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: file)
    }

    func testDeveloperOverrideAndBuiltInDefault() throws {
        let root = try temporary()
        let repo = root.appendingPathComponent("developer checkout")
        let resources = root.appendingPathComponent("Resources")
        try touch(repo.appendingPathComponent("venv/bin/python"))
        try touch(resources.appendingPathComponent("engine/python/bin/python3"))
        let developer = try EngineLocator.resolve(repoPath: repo.path, useDeveloperEngine: true, resourcesURL: resources)
        XCTAssertFalse(developer.isBuiltIn)
        XCTAssertEqual(developer.python, repo.appendingPathComponent("venv/bin/python"))
        XCTAssertEqual(developer.scriptsDir.standardizedFileURL.path, repo.standardizedFileURL.path)
        XCTAssertEqual(developer.modelsDir, repo.appendingPathComponent("models"))
        XCTAssertEqual(developer.cwd.standardizedFileURL.path, repo.standardizedFileURL.path)
        XCTAssertNil(developer.ffmpeg)
        XCTAssertTrue(developer.envAdditions.isEmpty)
        let builtIn = try EngineLocator.resolve(repoPath: repo.path, useDeveloperEngine: false, resourcesURL: resources)
        XCTAssertTrue(builtIn.isBuiltIn)
        XCTAssertEqual(builtIn.python, resources.appendingPathComponent("engine/python/bin/python3"))
        XCTAssertEqual(builtIn.scriptsDir, resources.appendingPathComponent("engine/app"))
        XCTAssertEqual(builtIn.modelsDir, resources.appendingPathComponent("engine/app/models"))
        XCTAssertEqual(builtIn.cwd, builtIn.scriptsDir)
        XCTAssertEqual(builtIn.ffmpeg, resources.appendingPathComponent("engine/bin/ffmpeg"))
        let environment = builtIn.environment(merging: ["PATH": "/opt/homebrew/bin:/usr/bin", "HOME": "/Users/example"])
        XCTAssertEqual(environment["PATH"], resources.appendingPathComponent("engine/bin").path + ":/opt/homebrew/bin:/usr/bin")
        XCTAssertEqual(environment["MEETINGNOTES_FFMPEG"], builtIn.ffmpeg?.path)
        XCTAssertEqual(environment["HOME"], "/Users/example")
        try touch(builtIn.scriptsDir.appendingPathComponent("ENGINE_VERSION"))
        try Data("test-version\n".utf8).write(to: builtIn.scriptsDir.appendingPathComponent("ENGINE_VERSION"))
        XCTAssertEqual(builtIn.description, "Built-in (version test-version)")
    }

    func testMissingDeveloperOverrideFallsBackToBuiltIn() throws {
        let root = try temporary()
        try touch(root.appendingPathComponent("engine/python/bin/python3"))
        for override in [false, true] {
            let layout = try EngineLocator.resolve(repoPath: root.appendingPathComponent("missing").path,
                useDeveloperEngine: override, resourcesURL: root)
            XCTAssertTrue(layout.isBuiltIn)
        }
    }

    func testAbsentBuiltInFallsBackToDeveloper() throws {
        let repo = try temporary()
        try touch(repo.appendingPathComponent("venv/bin/python"))
        for override in [false, true] {
            for resources in [nil, Optional(repo.appendingPathComponent("Resources"))] {
                let layout = try EngineLocator.resolve(repoPath: repo.path,
                    useDeveloperEngine: override, resourcesURL: resources)
                XCTAssertFalse(layout.isBuiltIn)
            }
        }
    }

    func testMissingEverythingExplainsReinstall() throws {
        let root = try temporary()
        for override in [false, true] {
            XCTAssertThrowsError(try EngineLocator.resolve(repoPath: root.path,
                useDeveloperEngine: override, resourcesURL: root)) { error in
                XCTAssertEqual(error.localizedDescription, "The transcription engine is missing. Reinstall MeetingNotes.")
            }
        }
    }
}
