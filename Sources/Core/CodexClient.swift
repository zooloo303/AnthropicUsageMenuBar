import Foundation

public enum CodexLocator {
    public static func find(override: String = "") -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        if !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let path = (override as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }
        var paths = ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex",
                     "/Applications/Codex.app/Contents/Resources/codex",
                     "\(home)/Applications/Codex.app/Contents/Resources/codex"]
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        // Zed's ACP installation includes the native Codex executable.
        #if arch(arm64)
        let platform = "darwin-arm64", triple = "aarch64-apple-darwin"
        #else
        let platform = "darwin-x64", triple = "x86_64-apple-darwin"
        #endif
        let vendor = "\(home)/Library/Application Support/Zed/external_agents/registry/npx/codex-acp/node_modules/@openai/codex-\(platform)/vendor/\(triple)"
        paths += ["\(vendor)/bin/codex", "\(vendor)/codex/codex"]
        for path in paths where fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
        // Common versioned installations (one level only, no scan of personal files).
        for (root, suffix) in [("\(home)/.nvm/versions/node", "bin/codex"),
                               ("\(home)/.vscode/extensions", "bin/macos-\(platform == "darwin-arm64" ? "aarch64" : "x86_64")/codex")] {
            for child in ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted().reversed() {
                let path = "\(root)/\(child)/\(suffix)"
                if fm.isExecutableFile(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }
        return nil
    }
}

@MainActor
public enum CodexClient {
    public static func fetch(executable: URL) async throws -> UsageSnapshot {
        let connection = RPCProcess(executable: executable)
        defer { connection.close() }
        try connection.start()
        _ = try await connection.request("initialize", params: ["clientInfo": ["name": "usage_menu_bar", "title": "Usage Menu Bar", "version": "1.0.0"]])
        try connection.notify("initialized")
        let data = try await connection.request("account/rateLimits/read")
        return try UsageParser.codex(data)
    }
}

// A short-lived stdio connection. It only initializes and reads rate limits;
// it never starts a thread, sends a prompt, or changes the signed-in account.
@MainActor
final class RPCProcess {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var closed = false

    init(executable: URL) {
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        // Do not expose server logs (which may contain private configuration).
        process.standardError = FileHandle.nullDevice
    }

    func start() throws {
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Preserve byte/EOF ordering, including a response immediately before exit.
            DispatchQueue.main.async { [weak self] in self?.receive(data) }
        }
        do { try process.run() }
        catch { throw UsageError.message("Could not launch Codex. Choose a working Codex executable in Settings.") }
    }

    func request(_ method: String, params: [String: Any] = [:], timeoutSeconds: Double = 30) async throws -> Data {
        try Task.checkCancellation()
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !closed else { continuation.resume(throwing: CancellationError()); return }
                pending[id] = continuation
                deadlines[id] = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000)) }
                    catch { return }
                    self?.fail(UsageError.message("Codex usage timed out. Check your connection and sign-in, then refresh."))
                }
                do { try send(["id": id, "method": method, "params": params]) }
                catch { fail(error) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.fail(CancellationError()) }
        }
    }

    func notify(_ method: String) throws { try send(["method": method, "params": [:]]) }

    private func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    private func receive(_ data: Data) {
        guard !closed else { return }
        guard !data.isEmpty else { fail(UsageError.message("Codex closed its usage connection.")); return }
        buffer.append(data)
        guard buffer.count <= 4_000_000 else { fail(UsageError.message("Unexpectedly large response from Codex.")); return }
        while let end = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            guard let message = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let id = message["id"] as? Int else { continue }
            // Decline any server-initiated requests instead of executing actions.
            if message["method"] != nil {
                try? send(["id": id, "error": ["code": -32601, "message": "Usage-only client"]])
                continue
            }
            guard let continuation = pending.removeValue(forKey: id) else { continue }
            deadlines.removeValue(forKey: id)?.cancel()
            if message["error"] != nil {
                continuation.resume(throwing: UsageError.message("Codex could not read subscription usage. Sign in to Codex with ChatGPT and try again."))
            } else if let result = message["result"], let data = try? JSONSerialization.data(withJSONObject: result) {
                continuation.resume(returning: data)
            } else { continuation.resume(throwing: UsageError.message("Unexpected response from Codex.")) }
        }
    }

    private func fail(_ error: Error) {
        let continuations = pending.values
        pending.removeAll()
        for task in deadlines.values { task.cancel() }
        deadlines.removeAll()
        for continuation in continuations { continuation.resume(throwing: error) }
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        output.fileHandleForReading.readabilityHandler = nil
        process.terminationHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            let child = process
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
        try? output.fileHandleForReading.close()
        for task in deadlines.values { task.cancel() }
        deadlines.removeAll()
        let continuations = pending.values
        pending.removeAll()
        for continuation in continuations { continuation.resume(throwing: CancellationError()) }
    }
}
