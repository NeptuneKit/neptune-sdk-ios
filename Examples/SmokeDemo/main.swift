import Foundation
import NeptuneSDKiOSSmokeDemoSupport

@main
struct SmokeDemoMain {
    static func main() async throws {
        let runner = NeptuneSmokeDemoRunner()
        let summary = try await runner.run()
        print(runner.render(summary: summary))
    }
}
