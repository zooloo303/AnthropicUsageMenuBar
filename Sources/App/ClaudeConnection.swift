import AppKit
import SwiftUI
import WebKit
import UsageCore

@MainActor
final class ClaudeConnection: NSObject, WKUIDelegate {
    // WebKit owns persistent session storage; app updates and process restarts
    // keep the same data store. We never import another browser's credentials.
    private let dataStore = WKWebsiteDataStore.default()
    // Keep a browser attached while background requests renew cookies; a bare
    // cookie store without a WebView did not persist in the restart probe.
    private lazy var storageView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private var window: NSWindow?
    private var webView: WKWebView?
    private let defaults = UserDefaults.standard
    var isConnected: Bool { defaults.bool(forKey: "usage.claudeWebConnected") }

    func fetch() async throws -> UsageSnapshot {
        _ = storageView
        let cookies = await dataStore.httpCookieStore.allCookies()
        let result = try await ClaudeWebClient().fetch(cookies: cookies, userAgent: defaults.string(forKey: "usage.claudeWebUserAgent"))
        for cookie in result.cookies { await dataStore.httpCookieStore.setCookie(cookie) }
        return result.snapshot
    }

    func show(onConnected: @escaping (UsageSnapshot) -> Void) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        let browser = WKWebView(frame: .zero, configuration: configuration)
        browser.uiDelegate = self
        webView = browser
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 750),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Connect Claude — claude.ai"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ClaudeConnectionView(browser: browser, connect: { [weak self] in
            guard let self else { throw CancellationError() }
            if let agent = try? await self.webView?.evaluateJavaScript("navigator.userAgent") as? String {
                self.defaults.set(agent, forKey: "usage.claudeWebUserAgent")
            }
            let snapshot = try await self.fetch()
            self.defaults.set(true, forKey: "usage.claudeWebConnected")
            onConnected(snapshot)
            self.window?.close()
            self.window = nil
            self.webView = nil
        }))
        self.window = window
        browser.load(URLRequest(url: Provider.claude.usageURL))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Keep ordinary sign-in links in the connection window.
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.scheme == "https" { webView.load(navigationAction.request) }
        return nil
    }
}

private struct ClaudeBrowser: NSViewRepresentable {
    let browser: WKWebView
    func makeNSView(context: Context) -> WKWebView { browser }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

private struct ClaudeConnectionView: View {
    let browser: WKWebView
    let connect: () async throws -> Void
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sign in to Claude, then click Save connection.").font(.headline)
                    Text("Your sign-in is remembered across app restarts.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Save connection") {
                    checking = true
                    error = nil
                    Task {
                        do { try await connect() }
                        catch { self.error = error.localizedDescription }
                        checking = false
                    }
                }.disabled(checking)
                if checking { ProgressView().controlSize(.small) }
            }.padding()
            if let error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal).padding(.bottom) }
            Divider()
            ClaudeBrowser(browser: browser)
        }.frame(minWidth: 650, minHeight: 500)
    }
}
