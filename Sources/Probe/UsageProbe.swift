import Foundation
import UsageCore

@main
struct UsageProbe {
    @MainActor static func main() async {
        let requested = CommandLine.arguments.dropFirst()
        var failed = false
        for provider in Provider.allCases where requested.isEmpty || requested.contains(provider.rawValue) {
            do {
                let snapshot: UsageSnapshot
                if provider == .claude { snapshot = try await ClaudeClient().fetch() }
                else {
                    guard let executable = CodexLocator.find() else { throw UsageError.message("Codex executable not found.") }
                    snapshot = try await CodexClient.fetch(executable: executable)
                }
                print("\(provider.title): connected (\(snapshot.windows.count) usage windows)")
                for window in snapshot.windows {
                    print("  \(window.title): \(window.usedPercent)% used; reset \(window.resetsAt?.formatted() ?? "not provided")")
                }
            } catch {
                failed = true
                print("\(provider.title): \(error.localizedDescription)")
            }
        }
        exit(failed ? 1 : 0)
    }
}
