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
        #expect(result.output.contains("SemVer"))
    }

    @Test("release 资产脚本 dry-run 成功")
    func releaseAssetsDryRunWorks() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-assets.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let result = try runScript(scriptPath: scriptPath, arguments: ["--tag", "1.2.3", "--dry-run"])
        #expect(result.status == 0)
        #expect(result.output.contains("release_tag=1.2.3"))
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

    @Test("release 资产脚本拒绝四段版本号")
    func releaseAssetsRejectsFourSegmentVersion() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-release-assets.sh")
            .path

        #expect(FileManager.default.fileExists(atPath: scriptPath))

        let result = try runScript(
            scriptPath: scriptPath,
            arguments: ["--tag", "2026.4.4.1", "--dry-run"]
        )
        #expect(result.status != 0)
        #expect(result.output.contains("SemVer"))
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
        #expect(result.output.contains("release_tag=2030.1.3"))
    }

    @Test("运行时依赖检查应忽略静态成员条目")
    func runtimeDependencyCheckIgnoresStaticObjectEntries() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-xcframework.sh")
            .path

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neptune-xcframework-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let frameworkDir = tempDir
            .appendingPathComponent("Fake.xcframework/ios-arm64/NeptuneSDKiOS.framework", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        let binaryPath = frameworkDir.appendingPathComponent("NeptuneSDKiOS")
        FileManager.default.createFile(atPath: binaryPath.path, contents: Data([0]))

        let fakeOtoolPath = tempDir.appendingPathComponent("otool")
        let fakeOtoolScript = """
        #!/usr/bin/env bash
        set -euo pipefail
        target="$2"
        cat <<EOF
        $target:
            $target(_AtomicsShims.o): (compatibility version 0.0.0, current version 0.0.0)
            /usr/lib/libobjc.A.dylib (compatibility version 1.0.0, current version 228.0.0)
        EOF
        """
        try fakeOtoolScript.write(to: fakeOtoolPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeOtoolPath.path)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(tempDir.path):\(env["PATH"] ?? "")"
        let result = try runScript(
            scriptPath: scriptPath,
            arguments: ["--framework-name", "NeptuneSDKiOS", "--check-runtime-dependencies-only", tempDir.appendingPathComponent("Fake.xcframework").path],
            environment: env
        )
        #expect(result.status == 0)
        #expect(result.output.contains("runtime dependency check passed"))
    }

    @Test("运行时依赖检查遇到三方动态库应失败")
    func runtimeDependencyCheckFailsOnThirdPartyDynamicLibrary() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("build-xcframework.sh")
            .path

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neptune-xcframework-leak-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let frameworkDir = tempDir
            .appendingPathComponent("Fake.xcframework/ios-arm64/NeptuneSDKiOS.framework", isDirectory: true)
        try FileManager.default.createDirectory(at: frameworkDir, withIntermediateDirectories: true)
        let binaryPath = frameworkDir.appendingPathComponent("NeptuneSDKiOS")
        FileManager.default.createFile(atPath: binaryPath.path, contents: Data([0]))

        let fakeOtoolPath = tempDir.appendingPathComponent("otool")
        let fakeOtoolScript = """
        #!/usr/bin/env bash
        set -euo pipefail
        target="$2"
        cat <<EOF
        $target:
            /tmp/libBadDependency.dylib (compatibility version 1.0.0, current version 1.0.0)
        EOF
        """
        try fakeOtoolScript.write(to: fakeOtoolPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeOtoolPath.path)

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(tempDir.path):\(env["PATH"] ?? "")"
        let result = try runScript(
            scriptPath: scriptPath,
            arguments: ["--framework-name", "NeptuneSDKiOS", "--check-runtime-dependencies-only", tempDir.appendingPathComponent("Fake.xcframework").path],
            environment: env
        )
        #expect(result.status != 0)
        #expect(result.output.contains("检测到非系统动态依赖"))
    }

    @Test("wrapper 同步脚本 --help 输出使用说明")
    func wrapperSyncHelpShowsUsage() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("sync-xcframework-wrapper.sh")
            .path

        let result = try runScript(scriptPath: scriptPath, arguments: ["--help"])
        #expect(result.status == 0)
        #expect(result.output.contains("Usage:"))
        #expect(result.output.contains("--repo-dir"))
        #expect(result.output.contains("--tag"))
        #expect(result.output.contains("--checksum"))
    }

    @Test("wrapper 同步脚本拒绝非法 checksum")
    func wrapperSyncRejectsInvalidChecksum() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("sync-xcframework-wrapper.sh")
            .path

        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neptune-wrapper-invalid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoDir) }

        try """
        let releaseTag = "2026.4.5"
        let binaryChecksum = "old"
        """.write(to: repoDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "README".write(to: repoDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let result = try runScript(
            scriptPath: scriptPath,
            arguments: [
                "--repo-dir", repoDir.path,
                "--tag", "2026.4.7",
                "--checksum", "abc"
            ]
        )
        #expect(result.status != 0)
        #expect(result.output.contains("64"))
    }

    @Test("wrapper 同步脚本更新 Package 与 README")
    func wrapperSyncUpdatesPackageAndReadme() throws {
        let scriptPath = projectRoot()
            .appendingPathComponent("scripts")
            .appendingPathComponent("sync-xcframework-wrapper.sh")
            .path

        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("neptune-wrapper-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: repoDir) }

        let packageContents = """
        // swift-tools-version: 5.9

        import PackageDescription

        let releaseTag = "2026.4.5"
        let binaryFileName = "NeptuneSDKiOS-\\(releaseTag).xcframework.zip"
        let binaryURL = "https://github.com/neptunekit/neptune-sdk-xcframework/releases/download/\\(releaseTag)/\\(binaryFileName)"
        let binaryChecksum = "oldchecksumoldchecksumoldchecksumoldchecksumoldchecksumoldchecksum12"
        """
        try packageContents.write(to: repoDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        let readmeContents = """
        ## 当前发布版本

        - Release tag: `2026.4.5`
        - XCFramework zip: `NeptuneSDKiOS-2026.4.5.xcframework.zip`
        - SHA256: `oldchecksumoldchecksumoldchecksumoldchecksumoldchecksumoldchecksum12`
        """
        try readmeContents.write(to: repoDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let checksum = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        let result = try runScript(
            scriptPath: scriptPath,
            arguments: [
                "--repo-dir", repoDir.path,
                "--tag", "2026.4.7",
                "--checksum", checksum
            ]
        )
        #expect(result.status == 0)

        let packageAfter = try String(contentsOf: repoDir.appendingPathComponent("Package.swift"), encoding: .utf8)
        let readmeAfter = try String(contentsOf: repoDir.appendingPathComponent("README.md"), encoding: .utf8)

        #expect(packageAfter.contains("let releaseTag = \"2026.4.7\""))
        #expect(packageAfter.contains("let binaryChecksum = \"\(checksum)\""))
        #expect(readmeAfter.contains("- Release tag: `2026.4.7`"))
        #expect(readmeAfter.contains("- XCFramework zip: `NeptuneSDKiOS-2026.4.7.xcframework.zip`"))
        #expect(readmeAfter.contains("- SHA256: `\(checksum)`"))
        #expect(result.output.contains("updated wrapper repo metadata"))
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
