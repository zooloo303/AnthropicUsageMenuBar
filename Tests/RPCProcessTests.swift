import Foundation
import Testing
@testable import UsageCore

struct RPCProcessTests {
    private func script(_ contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("fake-codex")
        try ("#!/bin/sh\n" + contents).write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)

        return file
    }

    @Test @MainActor func testHandshakeAndFragmentedResponse() async throws {
        let executable = try script("""
        read -r init
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r limits
        printf '%s' '{"id":2,"res'
        printf '%s\\n' 'ult":{"rateLimits":{"primary":{"usedPercent":24,"windowDurationMins":300}}}}'
        read -r stop
        """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let snapshot = try await CodexClient.fetch(executable: executable)
        #expect(snapshot.windows[0].usedPercent == 24)
    }

    @Test @MainActor func testServerErrorIsSanitized() async throws {
        let executable = try script("""
        read -r request
        printf '%s\\n' '{"id":1,"error":{"message":"private-server-detail"}}'
        read -r stop
        """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let rpc = RPCProcess(executable: executable)
        defer { rpc.close() }
        try rpc.start()
        do { _ = try await rpc.request("initialize"); Issue.record("Expected server error") }
        catch { #expect(!error.localizedDescription.contains("private-server-detail")) }
    }

    @Test @MainActor func testUnresponsiveServerTimesOut() async throws {
        let executable = try script("read -r request\nread -r more\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let rpc = RPCProcess(executable: executable)
        defer { rpc.close() }
        try rpc.start()
        let start = Date()
        do { _ = try await rpc.request("initialize", timeoutSeconds: 0.15); Issue.record("Expected timeout") }
        catch { #expect(error.localizedDescription.contains("timed out")) }
        #expect(Date().timeIntervalSince(start) < 3)
    }

    @Test @MainActor func testProcessExitDoesNotHang() async throws {
        let executable = try script("exit 1\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let rpc = RPCProcess(executable: executable)
        defer { rpc.close() }
        try rpc.start()
        do { _ = try await rpc.request("initialize", timeoutSeconds: 2); Issue.record("Expected connection failure") }
        catch { #expect(!error.localizedDescription.isEmpty) }
    }

    @Test @MainActor func testResponseImmediatelyBeforeExitIsPreserved() async throws {
        let executable = try script("""
        read -r request
        printf '%s\\n' '{"id":1,"result":{"ok":true}}'
        exit 0
        """)
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let rpc = RPCProcess(executable: executable)
        defer { rpc.close() }
        try rpc.start()
        let data = try await rpc.request("initialize", timeoutSeconds: 2)
        let response = try JSONSerialization.jsonObject(with: data) as? [String: Bool]
        #expect(response?["ok"] == true)
    }

    @Test @MainActor func testCancellationClosesPendingRequest() async throws {
        let executable = try script("read -r request\nread -r more\n")
        defer { try? FileManager.default.removeItem(at: executable.deletingLastPathComponent()) }
        let rpc = RPCProcess(executable: executable)
        defer { rpc.close() }
        try rpc.start()
        let task = Task { try await rpc.request("initialize") }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }
}
