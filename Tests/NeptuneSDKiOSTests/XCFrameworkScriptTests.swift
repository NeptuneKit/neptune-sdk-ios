import Foundation
import Testing

@Suite("XCFramework 打包脚本")
struct XCFrameworkScriptTests {
    @Test("--help 输出使用说明")
    func helpShowsUsage() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-xcframework.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let result = try runScript(scriptPath: scriptPath, arguments: ["--help"])
        #expect(result.status == 0)
        #expect(result.output.contains("Usage:"))
        #expect(result.output.contains("--scheme"))
        #expect(result.output.contains("--build-library-for-distribution"))
        #expect(result.output.contains("--skip-dependency-check"))
    }

    @Test("release 资产脚本 --help 输出使用说明")
    func releaseAssetsHelpShowsUsage() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-assets.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let result = try runScript(scriptPath: scriptPath, arguments: ["--help"])
        #expect(result.status == 0)
        #expect(result.output.contains("Usage:"))
        #expect(result.output.contains("--tag"))
        #expect(result.output.contains("--dry-run"))
    }

    @Test("release 资产脚本拒绝非法 tag")
    func releaseAssetsRejectsInvalidTag() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-assets.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let result = try runScript(scriptPath: scriptPath, arguments: ["--tag", "invalid_version", "--dry-run"])
        #expect(result.status != 0)
        #expect(result.output.contains("must match"))
    }

    @Test("release 资产脚本 dry-run 成功")
    func releaseAssetsDryRunWorks() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-assets.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let result = try runScript(scriptPath: scriptPath, arguments: ["--tag", "v1.2.3", "--dry-run"])
        #expect(result.status == 0)
        #expect(result.output.contains("release_tag=v1.2.3"))
        #expect(result.output.contains("zip_path="))
    }

    @Test("release 资产脚本默认使用当天日期版本")
    func releaseAssetsDefaultsToDateVersion() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-assets.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let dateBase = "2030.1.2"
        let result = try runScript(
            scriptPath: scriptPath,
            arguments: ["--dry-run"],
            environment: ["NEPTUNE_RELEASE_DATE_BASE": dateBase]
        )
        #expect(result.status == 0)
        #expect(result.output.contains("release_tag=\(dateBase)"))
    }

    @Test("release 资产脚本同日多版本自动递增")
    func releaseAssetsDateVersionAutoIncrements() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-assets.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let dateBase = "2030.1.2"
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neptune-release-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let existingAsset = tempDir.appendingPathComponent("NeptuneSDKiOS-\(dateBase).xcframework.zip")
        FileManager.default.createFile(atPath: existingAsset.path, contents: Data())

        let result = try runScript(
            scriptPath: scriptPath,
            arguments: ["--output-dir", tempDir.path, "--dry-run"],
            environment: ["NEPTUNE_RELEASE_DATE_BASE": dateBase]
        )
        #expect(result.status == 0)
        #expect(result.output.contains("release_tag=\(dateBase).1"))
    }

    private func projectRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NeptuneSDKiOSTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // project root
    }

    private func runScript(
        scriptPath: String,
        arguments: [String],
        environment: [String: String] = [:]
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath] + arguments
        var mergedEnvironment = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            mergedEnvironment[key] = value
        }
        process.environment = mergedEnvironment
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        return (process.terminationStatus, output)
    }
}
