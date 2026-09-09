import Foundation
import Security
import LocalAuthentication

public struct ClaudeClient: Sendable {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let credentials = try await ClaudeCredentials.shared.credentials()
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.timeoutInterval = 25
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("UsageMenuBar/1.0", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        let session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UsageError.message("Claude returned an invalid response.") }
        switch response.statusCode {
        case 200: return try UsageParser.claude(data, plan: credentials.subscriptionType)
        case 401, 403:
            await ClaudeCredentials.shared.invalidate(accessToken: credentials.accessToken)
            throw UsageError.message("Claude sign-in expired or access was denied. Open Claude Code, sign in again, then refresh.")
        case 429:
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
            throw UsageError.throttled(Date().addingTimeInterval(max(60, delay)))
        default: throw UsageError.message("Claude usage request failed (HTTP \(response.statusCode)). Try again later.")
        }
    }
}

// One process-wide, memory-only cache. Actor isolation serializes Keychain reads,
// without blocking the main actor. This compatibility reader never opens UI.
actor ClaudeCredentials {
    struct OAuth: Decodable, Sendable {
        let accessToken: String
        let subscriptionType: String?
        let expiresAt: Double?
    }
    private struct Credentials: Decodable { let claudeAiOauth: OAuth? }
    static let shared = ClaudeCredentials()
    private var cached: OAuth?
    private let read: @Sendable () throws -> OAuth

    init(read: @escaping @Sendable () throws -> OAuth = { try ClaudeCredentials.readCredentials() }) {
        self.read = read
    }

    func credentials(now: Date = Date()) throws -> OAuth {
        if let cached, cached.expiresAt.map({ $0 / 1000 > now.timeIntervalSince1970 }) ?? true {
            return cached
        }
        cached = nil
        let value = try read()
        cached = value
        return value
    }

    func invalidate(accessToken: String) {
        if cached?.accessToken == accessToken { cached = nil }
    }

    private static let keychainLock = NSLock()

    private static func readKeychain() throws -> (OSStatus, Data?) {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        // Claude Code uses the legacy login Keychain. The per-query UI flag alone
        // does not suppress all legacy Keychain dialogs, so guard that API too.
        var previous: DarwinBoolean = false
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else {
            throw UsageError.message("Could not configure silent Keychain access. Try refreshing again.")
        }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    private static func readCredentials() throws -> OAuth {
        let (status, keychainData) = try readKeychain()
        var data = keychainData
        if status == errSecInteractionNotAllowed || status == errSecInteractionRequired
            || status == errSecAuthFailed {
            throw UsageError.authenticationRequired
        } else if status != errSecSuccess && status != errSecItemNotFound {
            throw UsageError.message("Claude Keychain access failed. Use Connect Claude to save a web sign-in. Keychain status: \(status).")
        }
        if data == nil {
            let directory = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
                .map { URL(fileURLWithPath: $0) }
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
            data = try? Data(contentsOf: directory.appendingPathComponent(".credentials.json"))
        }
        guard let data,
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data),
              let oauth = credentials.claudeAiOauth, !oauth.accessToken.isEmpty else {
            throw UsageError.message("Sign in to Claude Code with your Claude subscription, then click Refresh.")
        }
        return oauth
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
