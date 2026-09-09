import Foundation

/// Reads the same subscription limits as Claude's usage page using the app's
/// own browser session. No CLI tokens, Keychain permissions, or token rotation.
public struct ClaudeWebClient {
    public init() {}

    public func fetch(cookies: [HTTPCookie], userAgent: String? = nil) async throws -> (snapshot: UsageSnapshot, cookies: [HTTPCookie]) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let session = URLSession(configuration: configuration, delegate: ClaudeWebNoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await fetch(cookies: cookies, userAgent: userAgent) { request in
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw UsageError.message("Claude returned an invalid response.")
            }
            return (data, response)
        }
    }

    func fetch(cookies: [HTTPCookie], userAgent: String? = nil, send: (URLRequest) async throws -> (Data, HTTPURLResponse)) async throws
        -> (snapshot: UsageSnapshot, cookies: [HTTPCookie]) {
        var cookies = cookies.filter(Self.isClaudeCookie)
        guard cookies.contains(where: { $0.name == "sessionKey" && !$0.value.isEmpty }) else {
            throw UsageError.claudeWebSignInRequired
        }
        var updates: [HTTPCookie] = []
        func get(_ path: String) async throws -> Data {
            let url = URL(string: "https://claude.ai" + path)!
            var request = URLRequest(url: url)
            request.timeoutInterval = 25
            let matching = cookies.filter { url.path.hasPrefix($0.path) }
            request.allHTTPHeaderFields = HTTPCookie.requestHeaderFields(with: matching)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
            let (data, response) = try await send(request)
            switch response.statusCode {
            case 200: break
            case 401: throw UsageError.claudeWebSignInRequired
            case 403: throw UsageError.message("Claude needs a browser check. Open Connect Claude and visit the usage page.")
            case 429:
                let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init) ?? 300
                throw UsageError.throttled(Date().addingTimeInterval(max(60, delay)))
            default: throw UsageError.message("Claude usage request failed (HTTP \(response.statusCode)). Try again later.")
            }
            let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
            }
            for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).filter(Self.isClaudeCookie) {
                cookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
                cookies.append(cookie)
                updates.append(cookie)
            }
            return data
        }
        let organizations = try JSONDecoder().decode([Organization].self, from: await get("/api/organizations"))
        let activeID = cookies.first(where: { $0.name == "lastActiveOrg" })?.value
        let organization: Organization
        if let active = organizations.first(where: { $0.uuid == activeID }) { organization = active }
        else if organizations.count == 1, let only = organizations.first { organization = only }
        else {
            throw UsageError.message("Open Connect Claude and select your organization on Claude's usage page.")
        }
        guard UUID(uuidString: organization.uuid) != nil else {
            throw UsageError.message("Claude returned an invalid organization.")
        }
        let data = try await get("/api/organizations/\(organization.uuid)/usage")
        return (try UsageParser.claude(data), updates)
    }

    static func isClaudeCookie(_ cookie: HTTPCookie) -> Bool {
        (cookie.domain == "claude.ai" || cookie.domain == ".claude.ai")
            && (cookie.expiresDate.map { $0 > Date() } ?? true)
    }

    private struct Organization: Decodable { let uuid: String }
}

private final class ClaudeWebNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
