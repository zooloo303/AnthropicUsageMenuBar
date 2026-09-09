import Foundation
import Security

public struct ClaudeClient: Sendable {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        // Keychain can prompt or block, so keep it off the UI thread.
        let credentials = try await Task.detached { try Self.credentials() }.value
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
        case 401, 403: throw UsageError.message("Claude sign-in expired or access was denied. Open Claude Code, sign in again, then refresh.")
        case 429:
            let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
            throw UsageError.throttled(Date().addingTimeInterval(max(60, delay)))
        default: throw UsageError.message("Claude usage request failed (HTTP \(response.statusCode)). Try again later.")
        }
    }

    private struct OAuth: Decodable {
        let accessToken: String
        let subscriptionType: String?
    }
    private struct Credentials: Decodable { let claudeAiOauth: OAuth? }

    private static func credentials() throws -> OAuth {
        // Read Claude Code's own credential entry; never copy, modify, or log it.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        var data: Data?
        if status == errSecSuccess { data = result as? Data }
        else if status != errSecItemNotFound {
            throw UsageError.message("Allow Usage Menu Bar to read the Claude Code credential in Keychain, then refresh. Keychain status: \(status).")
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
