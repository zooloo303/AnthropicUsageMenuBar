import Foundation
import Testing
@testable import UsageCore

struct ClaudeWebClientTests {
    let org = "11111111-1111-4111-8111-111111111111"
    let secondOrg = "22222222-2222-4222-8222-222222222222"

    func cookie(_ name: String = "sessionKey", _ value: String = "fake-session", domain: String = "claude.ai") -> HTTPCookie {
        HTTPCookie(properties: [.name: name, .value: value, .domain: domain, .path: "/", .secure: "TRUE",
                               .expires: Date().addingTimeInterval(86400)])!
    }
    func response(_ request: URLRequest, status: Int = 200, body: String,
                  headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }

    @Test func savedSessionWorksForFreshClientsWithoutKeychain() async throws {
        for _ in 0..<2 {
            let result = try await ClaudeWebClient().fetch(cookies: [cookie(), cookie("foreign", "secret", domain: "example.com")]) { request in
                #expect(request.url?.host == "claude.ai")
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionKey=fake-session") == true)
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("foreign") == false)
                if request.url!.path == "/api/organizations" {
                    return response(request, body: "[{\"uuid\":\"\(org)\"}]")
                }
                #expect(request.url!.path == "/api/organizations/\(org)/usage")
                return response(request, body: "{\"five_hour\":{\"utilization\":42,\"resets_at\":null}}")
            }
            #expect(result.snapshot.windows[0].usedPercent == 42)
        }
    }

    @Test func missingSessionMakesNoNetworkRequest() async {
        do {
            _ = try await ClaudeWebClient().fetch(cookies: []) { request in
                Issue.record("Must not make a request without a session")
                return response(request, body: "{}")
            }
            Issue.record("Expected sign-in requirement")
        } catch { #expect(error is UsageError) }
    }

    @Test func renewalIsUsedImmediatelyAndReturnedForPersistence() async throws {
        let result = try await ClaudeWebClient().fetch(cookies: [cookie()]) { request in
            if request.url!.path == "/api/organizations" {
                return response(request, body: "[{\"uuid\":\"\(org)\"}]",
                                headers: ["Set-Cookie": "sessionKey=renewed; Path=/; Secure; Max-Age=86400"])
            }
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("sessionKey=renewed") == true)
            return response(request, body: "{\"five_hour\":{\"utilization\":7,\"resets_at\":null}}")
        }
        #expect(result.cookies.first?.value == "renewed")
    }

    @Test func activeOrganizationIsRespected() async throws {
        _ = try await ClaudeWebClient().fetch(cookies: [cookie(), cookie("lastActiveOrg", secondOrg)]) { request in
            if request.url!.path == "/api/organizations" {
                return response(request, body: "[{\"uuid\":\"\(org)\"},{\"uuid\":\"\(secondOrg)\"}]")
            }
            #expect(request.url!.path == "/api/organizations/\(secondOrg)/usage")
            return response(request, body: "{\"five_hour\":{\"utilization\":7,\"resets_at\":null}}")
        }
    }

    @Test func ambiguousOrganizationDoesNotShowAnotherAccountsUsage() async {
        do {
            _ = try await ClaudeWebClient().fetch(cookies: [cookie()]) { request in
                #expect(request.url!.path == "/api/organizations")
                return response(request, body: "[{\"uuid\":\"\(org)\"},{\"uuid\":\"\(secondOrg)\"}]")
            }
            Issue.record("Expected organization selection")
        } catch { #expect(error.localizedDescription.contains("select your organization")) }
    }

    @Test func revokedSessionRequestsExplicitReconnectWithoutLeakingResponse() async {
        do {
            _ = try await ClaudeWebClient().fetch(cookies: [cookie()]) { request in
                response(request, status: 401, body: "private account detail")
            }
            Issue.record("Expected sign-in requirement")
        } catch {
            #expect(error.localizedDescription.contains("Connect Claude"))
            #expect(!error.localizedDescription.contains("private account detail"))
        }
    }

    @Test func rateLimitRetainsRetryDelay() async {
        let start = Date()
        do {
            _ = try await ClaudeWebClient().fetch(cookies: [cookie()]) { request in
                response(request, status: 429, body: "{}", headers: ["Retry-After": "600"])
            }
            Issue.record("Expected backoff")
        } catch UsageError.throttled(let date) { #expect(date.timeIntervalSince(start) >= 600) }
        catch { Issue.record("Expected throttled error") }
    }
}
