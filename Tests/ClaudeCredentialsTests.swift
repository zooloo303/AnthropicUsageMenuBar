import Foundation
import Testing
@testable import UsageCore

struct ClaudeCredentialsTests {
    private func token(_ value: String = "test-token", expiresAt: Double? = nil) -> ClaudeCredentials.OAuth {
        ClaudeCredentials.OAuth(accessToken: value, subscriptionType: "max", expiresAt: expiresAt)
    }

    @Test func repeatedAndConcurrentRefreshesReuseCredential() async throws {
        let reads = Reads()
        let value = token()
        let cache = ClaudeCredentials {
            reads.record(false)
            return value
        }
        _ = try await cache.credentials()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<20 { group.addTask { _ = try await cache.credentials() } }
            try await group.waitForAll()
        }
        #expect(reads.values == [false])
    }

    @Test func failedReadCanRecoverWhenCredentialBecomesAvailable() async throws {
        let reads = Reads()
        let value = token()
        let cache = ClaudeCredentials {
            reads.record(false)
            if reads.values.count == 1 { throw UsageError.authenticationRequired }
            return value
        }
        do { _ = try await cache.credentials(); Issue.record("Expected silent access failure") }
        catch { #expect(error is UsageError) }
        _ = try await cache.credentials()
        _ = try await cache.credentials()
        #expect(reads.values == [false, false])
    }

    @Test func expiredTokenIsRereadSilently() async throws {
        let reads = Reads()
        let value = token(expiresAt: 2_000_000)
        let cache = ClaudeCredentials { reads.record(false); return value }
        _ = try await cache.credentials(now: Date(timeIntervalSince1970: 1000))
        _ = try await cache.credentials(now: Date(timeIntervalSince1970: 1500))
        _ = try await cache.credentials(now: Date(timeIntervalSince1970: 2000))
        #expect(reads.values == [false, false])
    }

    @Test func rejectedTokenIsEvictedButOlderRequestsCannotEvictNewToken() async throws {
        let reads = Reads()
        let cache = ClaudeCredentials {
            reads.record(false)
            return ClaudeCredentials.OAuth(accessToken: "token-\(reads.values.count)", subscriptionType: nil, expiresAt: nil)
        }
        let first = try await cache.credentials()
        await cache.invalidate(accessToken: first.accessToken)
        let second = try await cache.credentials()
        await cache.invalidate(accessToken: first.accessToken)
        let third = try await cache.credentials()
        #expect(first.accessToken != second.accessToken)
        #expect(second.accessToken == third.accessToken)
        #expect(reads.values == [false, false])
    }
}

private final class Reads: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Bool] = []
    var values: [Bool] { lock.lock(); defer { lock.unlock() }; return storage }
    func record(_ value: Bool) { lock.lock(); defer { lock.unlock() }; storage.append(value) }
}
